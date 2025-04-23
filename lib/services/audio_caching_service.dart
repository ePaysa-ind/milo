// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/services/audio_caching_service.dart
// Version: 1.1.0
// Last Updated: April 21, 2025
// Description: Service for managing local caching of audio files with optimizations for elderly users

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:mime/mime.dart';
import 'dart:convert';

import '../models/nudge_model.dart';
import '../utils/advanced_logger.dart';
import '../services/nudge_service.dart';
import '../utils/error_reporter.dart';
import '../utils/config.dart';

// Error categories for better error handling
enum AudioCacheErrorType {
  network,
  storage,
  permission,
  invalidContent,
  timeout,
  unknown
}

/// Configuration for the audio caching service
///
/// This allows dynamic adjustments to cache behavior without code changes
class AudioCachingConfig {
  // Default storage limits
  final int maxCacheSizeBytes;
  final int maxQueueSize;
  final int maxFileAge;
  final int maxConcurrentDownloads;

  // Network parameters
  final int lowPriorityDownloadChunkSize;
  final int highPriorityDownloadChunkSize;
  final Duration downloadTimeout;
  final Duration networkRetryDelay;
  final int maxRetryCount;

  // Battery thresholds
  final int lowBatteryThreshold;
  final bool pauseDownloadsOnLowBattery;

  // File parameters
  final List<String> allowedMimeTypes;
  final int maxFileSizeBytes;

  // Priority settings
  final bool prioritizeRecentNudges;
  final bool prioritizeUserFavorites;

  const AudioCachingConfig({
    this.maxCacheSizeBytes = 100 * 1024 * 1024, // 100 MB
    this.maxQueueSize = 20,
    this.maxFileAge = 30, // days
    this.maxConcurrentDownloads = 2,
    this.lowPriorityDownloadChunkSize = 128 * 1024, // 128 KB
    this.highPriorityDownloadChunkSize = 512 * 1024, // 512 KB
    this.downloadTimeout = const Duration(minutes: 5),
    this.networkRetryDelay = const Duration(seconds: 5),
    this.maxRetryCount = 3,
    this.lowBatteryThreshold = 15, // percent
    this.pauseDownloadsOnLowBattery = true,
    this.allowedMimeTypes = const [
      'audio/mpeg',
      'audio/mp4',
      'audio/x-m4a',
      'audio/ogg'
    ],
    this.maxFileSizeBytes = 10 * 1024 * 1024, // 10 MB
    this.prioritizeRecentNudges = true,
    this.prioritizeUserFavorites = true,
  });
}

/// Service responsible for caching audio files locally
///
/// This service provides optimized audio file caching specifically designed for:
/// - Elderly users who may have intermittent connectivity
/// - Devices with limited storage
/// - Efficient background downloading when on WiFi
/// - Automatic cleanup of unused cached files
class AudioCachingService {
  // Dependency injection for testability
  final ConnectivityProvider _connectivityProvider;
  final StorageProvider _storageProvider;
  final BatteryProvider _batteryProvider;
  final HttpClientProvider _httpClientProvider;
  final AudioCachingConfig _config;
  final NudgeService? _nudgeService;

  // Internal state
  Directory? _cacheDirectory;
  bool _isInitialized = false;
  final Map<String, _CachedFileMetadata> _metadata = {};
  final Map<String, _DownloadOperation> _ongoingDownloads = {};
  ConnectivityResult _currentConnectivity = ConnectivityResult.none;
  int _batteryLevel = 100;
  bool _isCharging = false;
  final _mutex = _AsyncMutex();

  // Download queue and processing
  final List<_PendingDownload> _downloadQueue = [];
  int _activeDownloads = 0;
  final _downloadsCompleter = Completer<void>();

  // Progress streams
  final StreamController<_DownloadProgress> _progressStreamController =
  StreamController<_DownloadProgress>.broadcast();

  // Periodic cleanup timer
  Timer? _cleanupTimer;

  /// Stream of download progress updates
  Stream<DownloadProgress> get downloadProgress =>
      _progressStreamController.stream.map(
            (progress) => DownloadProgress(
          url: progress.url,
          progress: progress.progress,
          bytesReceived: progress.bytesReceived,
          totalBytes: progress.totalBytes,
          cacheKey: progress.cacheKey,
          nudgeId: progress.nudgeId,
          isHighPriority: progress.isHighPriority,
        ),
      );

  /// Factory constructor that returns a singleton instance
  /// Using factory pattern instead of static singleton for better testability
  factory AudioCachingService({
    NudgeService? nudgeService,
    ConnectivityProvider? connectivityProvider,
    StorageProvider? storageProvider,
    BatteryProvider? batteryProvider,
    HttpClientProvider? httpClientProvider,
    AudioCachingConfig? config,
  }) {
    return _instance ??= AudioCachingService._internal(
      nudgeService: nudgeService,
      connectivityProvider: connectivityProvider ?? RealConnectivityProvider(),
      storageProvider: storageProvider ?? RealStorageProvider(),
      batteryProvider: batteryProvider ?? RealBatteryProvider(),
      httpClientProvider: httpClientProvider ?? RealHttpClientProvider(),
      config: config ?? const AudioCachingConfig(),
    );
  }

  // Instance for singleton pattern - static but nullable for better testability
  static AudioCachingService? _instance;

  /// Internal constructor
  AudioCachingService._internal({
    required ConnectivityProvider connectivityProvider,
    required StorageProvider storageProvider,
    required BatteryProvider batteryProvider,
    required HttpClientProvider httpClientProvider,
    required AudioCachingConfig config,
    NudgeService? nudgeService,
  }) :
        _connectivityProvider = connectivityProvider,
        _storageProvider = storageProvider,
        _batteryProvider = batteryProvider,
        _httpClientProvider = httpClientProvider,
        _config = config,
        _nudgeService = nudgeService;

  /// Reset the singleton instance (for testing)
  @visibleForTesting
  static void resetInstance() {
    _instance?._dispose();
    _instance = null;
  }

  /// Dispose of resources
  void _dispose() {
    _cleanupTimer?.cancel();
    _progressStreamController.close();
    for (final download in _ongoingDownloads.values) {
      download.cancelToken.cancel();
    }
    _ongoingDownloads.clear();
  }

  /// Initialize the caching service
  ///
  /// Sets up cache directory, loads metadata, and initializes monitoring
  ///
  /// Throws [AudioCacheException] if initialization fails
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      AdvancedLogger.log('AudioCachingService', 'Initializing audio cache service');

      // Set up the cache directory
      await _setupCacheDirectory();

      // Load metadata
      await _loadMetadata();

      // Set up connectivity monitoring
      await _setupConnectivityMonitoring();

      // Set up battery monitoring
      await _setupBatteryMonitoring();

      // Schedule periodic cleanup
      _setupPeriodicCleanup();

      // Complete any outstanding downloads completer
      if (!_downloadsCompleter.isCompleted) {
        _downloadsCompleter.complete();
      }

      _isInitialized = true;
      AdvancedLogger.log('AudioCachingService', 'Audio cache service initialized successfully');
    } catch (e, stackTrace) {
      final errorType = _categorizeError(e);
      final exception = AudioCacheException(
        'Failed to initialize audio cache service: ${e.toString()}',
        errorType,
        cause: e,
      );
      ErrorReporter.reportError(
        'AudioCachingService.initialize',
        exception,
        stackTrace,
      );
      throw exception;
    }
  }

  /// Set up the cache directory
  ///
  /// Creates the directory if it doesn't exist
  Future<void> _setupCacheDirectory() async {
    // Get application documents directory
    final appDir = await _storageProvider.getApplicationDocumentsDirectory();
    _cacheDirectory = Directory('${appDir.path}/nudge_audio_cache');

    // Create directory if it doesn't exist
    if (!await _cacheDirectory!.exists()) {
      await _cacheDirectory!.create(recursive: true);
    }
  }

  /// Set up connectivity monitoring
  ///
  /// Monitors network status changes and reacts accordingly
  Future<void> _setupConnectivityMonitoring() async {
    try {
      // Check current connectivity
      _currentConnectivity = await _connectivityProvider.checkConnectivity();

      // Set up connectivity listener
      _connectivityProvider.onConnectivityChanged.listen((ConnectivityResult result) {
        _currentConnectivity = result;
        AdvancedLogger.log('AudioCachingService', 'Connectivity changed: $_currentConnectivity');

        // Start processing queue if we're back online and not at low battery
        if (result != ConnectivityResult.none && _shouldProcessDownloads()) {
          _processDownloadQueue();
        }
      });
    } catch (e) {
      AdvancedLogger.logError('AudioCachingService', 'Error setting up connectivity monitoring: $e');
      // Continue without connectivity monitoring as a fallback
    }
  }

  /// Set up battery monitoring
  ///
  /// Monitors battery level and charging status
  Future<void> _setupBatteryMonitoring() async {
    try {
      // Get initial battery level
      _batteryLevel = await _batteryProvider.batteryLevel;
      _isCharging = await _batteryProvider.isCharging;

      // Set up battery level listener
      _batteryProvider.onBatteryLevelChanged.listen((int level) {
        final previousLevel = _batteryLevel;
        _batteryLevel = level;

        // If we crossed the threshold (in either direction), update downloads
        if ((previousLevel < _config.lowBatteryThreshold && level >= _config.lowBatteryThreshold) ||
            (previousLevel >= _config.lowBatteryThreshold && level < _config.lowBatteryThreshold)) {
          if (_shouldProcessDownloads()) {
            _processDownloadQueue();
          }
        }
      });

      // Set up charging status listener
      _batteryProvider.onChargingStatusChanged.listen((bool charging) {
        _isCharging = charging;

        // If we started charging and have pending downloads, process queue
        if (charging && _shouldProcessDownloads()) {
          _processDownloadQueue();
        }
      });
    } catch (e) {
      AdvancedLogger.logError('AudioCachingService', 'Error setting up battery monitoring: $e');
      // Continue without battery monitoring as a fallback
    }
  }

  /// Set up periodic cleanup
  ///
  /// Schedules regular cleanup of cache to maintain size limits
  void _setupPeriodicCleanup() {
    // Cancel any existing timer
    _cleanupTimer?.cancel();

    // Run cleanup immediately
    _scheduleCleanup();

    // Schedule cleanup every 6 hours
    _cleanupTimer = Timer.periodic(const Duration(hours: 6), (timer) {
      _scheduleCleanup();
    });
  }

  /// Check if downloads should be processed based on device state
  ///
  /// Considers battery level, charging status, and connectivity
  bool _shouldProcessDownloads() {
    if (_currentConnectivity == ConnectivityResult.none) {
      return false;
    }

    if (_config.pauseDownloadsOnLowBattery &&
        _batteryLevel < _config.lowBatteryThreshold &&
        !_isCharging) {
      return false;
    }

    return true;
  }

  /// Get a cached file for the given URL
  ///
  /// If the file is already cached, returns it immediately
  /// If not, downloads it in the background and returns when complete
  ///
  /// [url] URL of the audio file
  /// [highPriority] Whether this is a high priority download
  /// [nudge] Optional nudge metadata for tracking
  /// [forceRefresh] Whether to force a fresh download even if cached
  ///
  /// Returns a [Future] that completes with the cached [File], or null if unable to download
  ///
  /// Throws [AudioCacheException] if an error occurs
  Future<File?> getCachedFile(String url, {
    bool highPriority = false,
    NudgeDelivery? nudge,
    bool forceRefresh = false,
  }) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      // Validate URL
      if (!await _isValidUrl(url)) {
        throw AudioCacheException(
          'Invalid URL: $url',
          AudioCacheErrorType.invalidContent,
        );
      }

      try {
        // Generate cache key from URL
        final cacheKey = _generateCacheKey(url);
        final filePath = '${_cacheDirectory!.path}/$cacheKey.mp3';
        final file = File(filePath);

        // Check if file exists and is valid
        if (!forceRefresh && await file.exists() && await _isFileValid(file)) {
          // Update last accessed time
          await _updateLastAccessed(cacheKey);
          AdvancedLogger.log('AudioCachingService', 'Using cached audio file: $cacheKey');

          // Notify for accessibility
          _notifyAccessibilityEvent('Audio ready for playback');

          return file;
        }

        // If already downloading, wait for it to complete
        if (_ongoingDownloads.containsKey(cacheKey)) {
          AdvancedLogger.log('AudioCachingService', 'Waiting for ongoing download: $cacheKey');
          return _ongoingDownloads[cacheKey]!.future;
        }

        // If offline, return null
        if (_currentConnectivity == ConnectivityResult.none) {
          AdvancedLogger.log('AudioCachingService', 'Cannot download file: device is offline');
          _notifyAccessibilityEvent('Cannot download audio: You are offline');
          return null;
        }

        // Check queue size
        if (_downloadQueue.length >= _config.maxQueueSize && !highPriority) {
          // For low priority requests, drop or replace older items
          _pruneDownloadQueue();
        }

        // Start download
        final completer = Completer<File>();
        final cancelToken = CancelToken();

        // Create download operation for tracking
        final operation = _DownloadOperation(
          future: completer.future,
          cancelToken: cancelToken,
          isHighPriority: highPriority,
        );

        _ongoingDownloads[cacheKey] = operation;

        if (highPriority) {
          // For high priority, download immediately
          AdvancedLogger.log('AudioCachingService', 'Starting high priority download: $cacheKey');
          _downloadFile(
            url,
            cacheKey,
            file,
            completer,
            cancelToken,
            highPriority: true,
            nudge: nudge,
          );
        } else {
          // For low priority, add to queue
          AdvancedLogger.log('AudioCachingService', 'Queueing download: $cacheKey');
          _downloadQueue.add(_PendingDownload(
            url: url,
            cacheKey: cacheKey,
            file: file,
            completer: completer,
            cancelToken: cancelToken,
            nudge: nudge,
            timestamp: DateTime.now(),
          ));

          // Process queue if conditions are right
          if (_shouldProcessDownloads()) {
            _processDownloadQueue();
          }
        }

        // Create a timeout for the download
        final timeoutFuture = Future.delayed(_config.downloadTimeout, () {
          if (!completer.isCompleted) {
            AdvancedLogger.logError('AudioCachingService', 'Download timed out: $url');

            // Cancel the download
            cancelToken.cancel();

            // Complete with error
            completer.completeError(AudioCacheException(
              'Download timed out',
              AudioCacheErrorType.timeout,
            ));
          }
        });

        // Return the file future (will complete when download finishes)
        unawaited(timeoutFuture);
        return completer.future;

      } catch (e, stackTrace) {
        final errorType = _categorizeError(e);
        final exception = e is AudioCacheException
            ? e
            : AudioCacheException(
          'Failed to get cached file: ${e.toString()}',
          errorType,
          cause: e,
        );

        ErrorReporter.reportError(
          'AudioCachingService.getCachedFile',
          exception,
          stackTrace,
        );

        // Notify for accessibility
        _notifyAccessibilityEvent('Error accessing audio file');

        throw exception;
      }
    });
  }

  /// Prefetch an audio file in the background
  ///
  /// This method queues the file for download but doesn't wait for completion
  ///
  /// [url] URL of the audio file to prefetch
  /// [nudge] Optional nudge metadata for tracking
  /// [importance] Importance of this prefetch (0-10, higher = more important)
  ///
  /// Returns a [Stream] that reports download progress
  Future<Stream<DownloadProgress>?> prefetchFile(String url, {
    NudgeDelivery? nudge,
    int importance = 5,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Validate URL
      if (!await _isValidUrl(url)) {
        AdvancedLogger.logError('AudioCachingService', 'Invalid URL for prefetch: $url');
        return null;
      }

      // Generate cache key from URL
      final cacheKey = _generateCacheKey(url);
      final filePath = '${_cacheDirectory!.path}/$cacheKey.mp3';
      final file = File(filePath);

      // Check if file exists or is already queued
      if (await file.exists() || _ongoingDownloads.containsKey(cacheKey)) {
        return null;
      }

      // If offline, don't queue
      if (_currentConnectivity == ConnectivityResult.none) {
        return null;
      }

      // Check queue size
      if (_downloadQueue.length >= _config.maxQueueSize) {
        // For prefetch, only add if it's more important than the least important item
        if (!_pruneDownloadQueueForImportance(importance)) {
          AdvancedLogger.log('AudioCachingService', 'Prefetch queue full, skipping: $cacheKey');
          return null;
        }
      }

      // Create a completer that we'll track but caller won't wait for
      final completer = Completer<File>();
      final cancelToken = CancelToken();

      // Create download operation for tracking
      final operation = _DownloadOperation(
        future: completer.future,
        cancelToken: cancelToken,
        isHighPriority: false,
      );

      _ongoingDownloads[cacheKey] = operation;

      // Add to queue with low priority
      _downloadQueue.add(_PendingDownload(
        url: url,
        cacheKey: cacheKey,
        file: file,
        completer: completer,
        cancelToken: cancelToken,
        nudge: nudge,
        timestamp: DateTime.now(),
        importance: importance,
      ));

      // Process queue if conditions are right
      if (_shouldProcessDownloads()) {
        _processDownloadQueue();
      }

      AdvancedLogger.log('AudioCachingService', 'Queued file for prefetching: $cacheKey');

      // Return a filtered stream of progress events for this download
      return downloadProgress.where((progress) => progress.cacheKey == cacheKey);

    } catch (e) {
      AdvancedLogger.logError('AudioCachingService', 'Failed to prefetch file: $e');
      // Don't rethrow for prefetch - it's a best-effort operation
      return null;
    }
  }

  /// Clear all cached files
  ///
  /// Use with caution - this will delete all cached audio files
  ///
  /// [preserveHighPriorityDownloads] Whether to preserve ongoing high priority downloads
  ///
  /// Throws [AudioCacheException] if an error occurs
  Future<void> clearCache({bool preserveHighPriorityDownloads = false}) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      try {
        AdvancedLogger.log('AudioCachingService', 'Clearing cache');

        // Cancel all low-priority downloads
        final downloadsToClear = preserveHighPriorityDownloads
            ? _ongoingDownloads.entries
            .where((entry) => !entry.value.isHighPriority)
            .map((entry) => entry.key)
            .toList()
            : _ongoingDownloads.keys.toList();

        for (final key in downloadsToClear) {
          _ongoingDownloads[key]!.cancelToken.cancel();
          _ongoingDownloads.remove(key);
        }

        // Clear the download queue (or filter it)
        if (preserveHighPriorityDownloads) {
          _downloadQueue.removeWhere((download) =>
          !_ongoingDownloads.containsKey(download.cacheKey) ||
              !_ongoingDownloads[download.cacheKey]!.isHighPriority
          );
        } else {
          _downloadQueue.clear();
        }

        // Wait a moment for downloads to cancel
        await Future.delayed(const Duration(milliseconds: 100));

        // Delete all files in cache directory
        if (_cacheDirectory != null && await _cacheDirectory!.exists()) {
          final files = await _cacheDirectory!.list().toList();
          for (final entity in files) {
            if (entity is File) {
              // Skip files that are currently being downloaded with high priority
              if (preserveHighPriorityDownloads) {
                final fileName = entity.path.split('/').last;
                final cacheKey = fileName.endsWith('.mp3')
                    ? fileName.substring(0, fileName.length - 4)
                    : fileName;

                if (_ongoingDownloads.containsKey(cacheKey) &&
                    _ongoingDownloads[cacheKey]!.isHighPriority) {
                  continue;
                }
              }

              await entity.delete();
            }
          }
        }

        // Update metadata
        if (preserveHighPriorityDownloads) {
          // Keep metadata for high priority downloads
          final keysToKeep = _ongoingDownloads.entries
              .where((entry) => entry.value.isHighPriority)
              .map((entry) => entry.key)
              .toSet();

          _metadata.removeWhere((key, _) => !keysToKeep.contains(key));
        } else {
          // Clear all metadata
          _metadata.clear();
        }

        await _saveMetadata();

        AdvancedLogger.log('AudioCachingService', 'Cache cleared');
      } catch (e, stackTrace) {
        final errorType = _categorizeError(e);
        final exception = AudioCacheException(
          'Failed to clear cache: ${e.toString()}',
          errorType,
          cause: e,
        );

        ErrorReporter.reportError(
          'AudioCachingService.clearCache',
          exception,
          stackTrace,
        );

        throw exception;
      }
    });
  }

  /// Get the current cache size in bytes
  ///
  /// Returns the total size of all cached files
  Future<int> getCacheSize() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      int totalSize = 0;

      if (_cacheDirectory != null && await _cacheDirectory!.exists()) {
        final files = await _cacheDirectory!.list().toList();

        for (final entity in files) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }

      return totalSize;
    } catch (e) {
      AdvancedLogger.logError('AudioCachingService', 'Failed to get cache size: $e');
      return 0;
    }
  }

  /// Delete a specific cached file
  ///
  /// [url] URL of the file to delete
  ///
  /// Throws [AudioCacheException] if an error occurs
  Future<void> deleteCachedFile(String url) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      try {
        final cacheKey = _generateCacheKey(url);
        final filePath = '${_cacheDirectory!.path}/$cacheKey.mp3';
        final file = File(filePath);

        // Cancel any ongoing download
        if (_ongoingDownloads.containsKey(cacheKey)) {
          _ongoingDownloads[cacheKey]!.cancelToken.cancel();
          _ongoingDownloads.remove(cacheKey);
        }

        // Remove from queue
        _downloadQueue.removeWhere((download) => download.cacheKey == cacheKey);

        if (await file.exists()) {
          await file.delete();
        }

        // Remove from metadata
        _metadata.remove(cacheKey);
        await _saveMetadata();

        AdvancedLogger.log('AudioCachingService', 'Deleted cached file: $cacheKey');
      } catch (e, stackTrace) {
        final errorType = _categorizeError(e);
        final exception = AudioCacheException(
          'Failed to delete cached file: ${e.toString()}',
          errorType,
          cause: e,
        );

        ErrorReporter.reportError(
          'AudioCachingService.deleteCachedFile',
          exception,
          stackTrace,
        );

        throw exception;
      }
    });
  }

  /// Get free space available for caching
  ///
  /// Returns the number of bytes available for caching before reaching the limit
  Future<int> getAvailableSpace() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final currentSize = await getCacheSize();
      return _config.maxCacheSizeBytes - currentSize;
    } catch (e) {
      AdvancedLogger.logError('AudioCachingService', 'Failed to get available space: $e');
      return 0;
    }
  }

  /// Wait for all high-priority downloads to complete
  ///
  /// This is useful when we know the user is about to play audio
  /// and we want to ensure it's ready
  ///
  /// [timeout] Maximum time to wait
  Future<void> waitForPriorityDownloads({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Check if there are any high priority downloads active
    final hasHighPriorityDownloads = _ongoingDownloads.values
        .any((op) => op.isHighPriority);

    // If no high priority downloads, return immediately
    if (!hasHighPriorityDownloads) {
      return;
    }

    // Reset completer if needed
    if (_downloadsCompleter.isCompleted) {
      _downloadsCompleter = Completer<void>();
    }

    // Wait for completer with timeout
    return _downloadsCompleter.future.timeout(
      timeout,
      onTimeout: () {
        AdvancedLogger.log('AudioCachingService', 'Timeout waiting for priority downloads');
      },
    );
  }

  /// Forces the cache to download all queued files immediately
  ///
  /// Useful before going offline or when preparing content
  ///
  /// [limit] Maximum number of files to download
  ///
  /// Returns the number of files downloaded
  Future<int> downloadAllQueuedFiles({int? limit}) async {
    return _mutex.synchronized(() async {
      if (_downloadQueue.isEmpty) return 0;

      int downloaded = 0;
      final filesToDownload = limit != null && limit < _downloadQueue.length
          ? _downloadQueue.take(limit).toList()
          : List<_PendingDownload>.from(_downloadQueue);

      _downloadQueue.clear();

      // Sort by importance
      filesToDownload.sort((a, b) => b.importance.compareTo(a.importance));

      // Process all downloads with high priority
      for (final download in filesToDownload) {
        if (!_ongoingDownloads.containsKey(download.cacheKey)) {
          continue; // Skip if already removed
        }

        try {
          await _downloadFile(
            download.url,
            download.cacheKey,
            download.file,
            download.completer,
            download.cancelToken,
            highPriority: true,
            nudge: download.nudge,
          );
          downloaded++;
        } catch (e) {
          AdvancedLogger.logError(
            'AudioCachingService',
            'Error in force download: $e',
          );
        }
      }

      return downloaded;
    });
  }

  /// Check if a URL is valid and points to an audio file
  ///
  /// [url] The URL to validate
  ///
  /// Returns true if the URL is valid, false otherwise
  Future<bool> _isValidUrl(String url) async {
    try {
      // Basic URL validation
      if (url.isEmpty) return false;

      // Check if it's a well-formed URL
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) return false;

      // Only allow http/https URLs
      if (uri.scheme != 'http' && uri.scheme != 'https') return false;

      // Additional checks could include:
      // 1. Domain allowlist check
      // 2. Path validation
      // 3. Query parameter validation

      return true;
    } catch (e) {
      AdvancedLogger.logError('AudioCachingService', 'URL validation error: $e');
      return false;
    }
  }

  /// Check if a file is valid and contains audio data
  ///
  /// [file] The file to validate
  ///
  /// Returns true if the file is valid, false otherwise
  Future<bool> _isFileValid(File file) async {
    try {
      // Check if file exists
      if (!await file.exists()) return false;

      // Check file size
      final size = await file.length();
      if (size <= 0) return false;

      // We could do more validation here, like:
      // 1. Check file headers for audio formats
      // 2. Try to open the file with the audio player
      // 3. Validate the file integrity

      return true;
    } catch (e) {
      AdvancedLogger.logError('AudioCachingService', 'File validation error: $e');
      return false;
    }
  }

  /// Generate a stable cache key from a URL
  ///
  /// [url] The URL to generate a key for
  ///
  /// Returns a unique, stable key for the URL
  String _generateCacheKey(String url) {
    // Use SHA-256 hash of the URL to create a stable, unique key
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Prune the download queue to maintain maximum size
  ///
  /// Removes the least important items from the queue
  void _pruneDownloadQueue() {
    if (_downloadQueue.length <= _config.maxQueueSize) return;

    // Sort queue by importance (lowest first)
    _downloadQueue.sort((a, b) => a.importance.compareTo(b.importance));

    // Remove items until we're under the limit
    while (_downloadQueue.length > _config.maxQueueSize) {
      final download = _downloadQueue.removeAt(0);

      // Cancel the download
      if (_ongoingDownloads.containsKey(download.cacheKey)) {
        _ongoingDownloads[download.cacheKey]!.cancelToken.cancel();
        _ongoingDownloads.remove(download.cacheKey);

        // Complete with error
        if (!download.completer.isCompleted) {
          download.completer.completeError(AudioCacheException(
            'Download canceled due to queue limits',
            AudioCacheErrorType.storage,
          ));
        }
      }

      AdvancedLogger.log(
        'AudioCachingService',
        'Pruned download from queue: ${download.cacheKey}',
      );
    }
  }

  /// Prune the download queue to make room for a more important item
  ///
  /// [importance] Importance of new item to add
  ///
  /// Returns true if room was made, false if the new item is not important enough
  bool _pruneDownloadQueueForImportance(int importance) {
    if (_downloadQueue.length < _config.maxQueueSize) return true;

    // Find the least important item
    int leastImportantIndex = 0;
    int leastImportance = _downloadQueue[0].importance;

    for (int i = 1; i < _downloadQueue.length; i++) {
      if (_downloadQueue[i].importance < leastImportance) {
        leastImportantIndex = i;
        leastImportance = _downloadQueue[i].importance;
      }
    }

    // Check if new item is more important
    if (importance > leastImportance) {
      // Remove the least important item
      final download = _downloadQueue.removeAt(leastImportantIndex);

      // Cancel the download
      if (_ongoingDownloads.containsKey(download.cacheKey)) {
        _ongoingDownloads[download.cacheKey]!.cancelToken.cancel();
        _ongoingDownloads.remove(download.cacheKey);

        // Complete with error
        if (!download.completer.isCompleted) {
          download.completer.completeError(AudioCacheException(
            'Download canceled due to priority limits',
            AudioCacheErrorType.storage,
          ));
        }
      }

      AdvancedLogger.log(
        'AudioCachingService',
        'Pruned lower priority download from queue: ${download.cacheKey}',
      );

      return true;
    }

    return false;
  }

  /// Download a file and store it in the cache
  ///
  /// [url] The URL to download
  /// [cacheKey] The cache key for the file
  /// [file] The file to write to
  /// [completer] Completer to resolve when download completes
  /// [cancelToken] Token to cancel the download
  /// [highPriority] Whether this is a high priority download
  /// [nudge] Optional nudge metadata for tracking
  Future<void> _downloadFile(
      String url,
      String cacheKey,
      File file,
      Completer<File> completer,
      CancelToken cancelToken,
      {
        bool highPriority = false,
        NudgeDelivery? nudge,
      }
      ) async {
    // Track active downloads
    _activeDownloads++;

    int retryCount = 0;
    bool success = false;

    try {
      // Check if we have enough space
      final availableSpace = await getAvailableSpace();
      if (availableSpace < 0) {
        // Not enough space, need to clean up
        await _enforceMaxCacheSize();
      }

      // Check battery level if not high priority
      if (!highPriority &&
          _config.pauseDownloadsOnLowBattery &&
          _batteryLevel < _config.lowBatteryThreshold &&
          !_isCharging) {
        throw AudioCacheException(
          'Download aborted: battery level too low',
          AudioCacheErrorType.storage,
        );
      }

      // Determine chunk size based on priority
      final chunkSize = highPriority
          ? _config.highPriorityDownloadChunkSize
          : _config.lowPriorityDownloadChunkSize;

      while (retryCount <= _config.maxRetryCount && !success) {
        if (cancelToken.isCancelled) {
          throw AudioCacheException(
            'Download canceled',
            AudioCacheErrorType.unknown,
          );
        }

        try {
          // Start chunked download
          final client = _httpClientProvider.getClient();
          final request = http.Request('GET', Uri.parse(url));
          final streamedResponse = await client.send(request);

          if (streamedResponse.statusCode != 200) {
            throw HttpException(
              'Failed to download file: HTTP ${streamedResponse.statusCode}',
            );
          }

          // Check content type if available
          final contentType = streamedResponse.headers['content-type'];
          if (contentType != null &&
              !_isAllowedContentType(contentType)) {
            throw AudioCacheException(
              'Invalid content type: $contentType',
              AudioCacheErrorType.invalidContent,
            );
          }

          // Get content length if available
          final contentLength = streamedResponse.contentLength ?? -1;

          // Check file size if known
          if (contentLength > _config.maxFileSizeBytes) {
            throw AudioCacheException(
              'File too large: ${contentLength ~/ 1024} KB (max: ${_config.maxFileSizeBytes ~/ 1024} KB)',
              AudioCacheErrorType.storage,
            );
          }

          // Create temp file
          final tempPath = '${file.path}.download';
          final tempFile = File(tempPath);
          final sink = tempFile.openWrite();

          int bytesReceived = 0;

          try {
            // Download in chunks
            await for (final chunk in streamedResponse.stream.cast<Uint8List>()) {
              // Check if canceled
              if (cancelToken.isCancelled) {
                throw AudioCacheException(
                  'Download canceled',
                  AudioCacheErrorType.unknown,
                );
              }

              // Add chunk to file
              sink.add(chunk);

              // Update progress
              bytesReceived += chunk.length;

              // Report progress
              _progressStreamController.add(_DownloadProgress(
                url: url,
                progress: contentLength > 0
                    ? bytesReceived / contentLength
                    : 0.0,
                bytesReceived: bytesReceived,
                totalBytes: contentLength,
                cacheKey: cacheKey,
                nudgeId: nudge?.id,
                isHighPriority: highPriority,
              ));

              // Add a small delay between chunks for low priority downloads
              // to avoid impacting network performance for other operations
              if (!highPriority) {
                await Future.delayed(const Duration(milliseconds: 50));
              }
            }

            // Successfully downloaded
            success = true;
          } finally {
            await sink.flush();
            await sink.close();
            client.close();
          }

          // Only proceed if successful
          if (success) {
            // Perform audio validation
            if (!await _validateAudioFile(tempFile)) {
              throw AudioCacheException(
                'Downloaded file is not valid audio',
                AudioCacheErrorType.invalidContent,
              );
            }

            // Move temp file to final location
            await tempFile.rename(file.path);

            // Add to metadata
            _metadata[cacheKey] = _CachedFileMetadata(
              url: url,
              cacheKey: cacheKey,
              fileSize: bytesReceived,
              lastAccessed: DateTime.now(),
              createdAt: DateTime.now(),
              isComplete: true,
              nudgeId: nudge?.id,
              importance: nudge != null && _config.prioritizeUserFavorites && nudge.userFeedback == true
                  ? 8  // Higher importance for nudges user liked
                  : 5, // Default importance
              contentType: contentType,
            );

            await _saveMetadata();

            // Notify for accessibility
            _notifyAccessibilityEvent('Audio download complete');

            // Complete the download
            if (!completer.isCompleted) {
              completer.complete(file);
            }

            AdvancedLogger.log(
              'AudioCachingService',
              'Downloaded file (${highPriority ? 'high' : 'low'} priority): $cacheKey, ${bytesReceived ~/ 1024}KB',
            );
          }
        } catch (e) {
          // Handle retry
          retryCount++;

          if (retryCount <= _config.maxRetryCount &&
              _shouldRetryDownload(e) &&
              !cancelToken.isCancelled) {
            AdvancedLogger.log(
              'AudioCachingService',
              'Retrying download (attempt $retryCount): $cacheKey',
            );

            // Wait before retry
            await Future.delayed(_config.networkRetryDelay);
          } else {
            // Max retries reached or non-retryable error
            rethrow;
          }
        }
      }
    } catch (e, stackTrace) {
      _logger.e('Error downloading file: $url', e, stackTrace);

      // Complete with error if not already completed
      if (!completer.isCompleted) {
        final errorType = _categorizeError(e);
        final exception = e is AudioCacheException
            ? e
            : AudioCacheException(
          'Download failed: ${e.toString()}',
          errorType,
          cause: e,
        );

        completer.completeError(exception);
      }

      // Notify for accessibility
      _notifyAccessibilityEvent('Audio download failed');

      // Clean up any partial file
      try {
        if (await file.exists()) {
          await file.delete();
        }

        final tempFile = File('${file.path}.download');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (cleanupError) {
        _logger.e('Error cleaning up partial download', cleanupError);
      }
    } finally {
      // Remove from ongoing downloads if we initiated the download
      _ongoingDownloads.remove(cacheKey);

      // Update active downloads count
      _activeDownloads--;

      // Check if we need to complete the downloads completer
      if (_activeDownloads == 0 && !_downloadsCompleter.isCompleted) {
        _downloadsCompleter.complete();
      }

      // Continue processing queue if possible
      if (_activeDownloads < _config.maxConcurrentDownloads) {
        _processDownloadQueue();
      }
    }
  }

  /// Check if content type is allowed
  ///
  /// [contentType] The content type to check
  ///
  /// Returns true if the content type is allowed, false otherwise
  bool _isAllowedContentType(String contentType) {
    // Strip parameters from content type
    final baseType = contentType.split(';').first.trim().toLowerCase();

    // Check against allowed types
    return _config.allowedMimeTypes.contains(baseType);
  }

  /// Validate an audio file
  ///
  /// [file] The file to validate
  ///
  /// Returns true if the file is valid audio, false otherwise
  Future<bool> _validateAudioFile(File file) async {
    try {
      // Check file size
      final fileSize = await file.length();
      if (fileSize <= 0 || fileSize > _config.maxFileSizeBytes) {
        return false;
      }

      // Read file header (first 12 bytes should be enough for most audio formats)
      final header = await file.openRead(0, 12).fold<Uint8List>(
        Uint8List(0),
            (previous, element) => Uint8List.fromList([...previous, ...element]),
      );

      // Check for common audio format signatures
      // MP3: Starts with ID3 or with sync word 0xFF
      // M4A: Starts with 'ftyp'
      // OGG: Starts with 'OggS'
      if (header.length >= 3 &&
          header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33) {
        return true; // ID3 tag (MP3)
      }

      if (header.length >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0) {
        return true; // MP3 sync word
      }

      if (header.length >= 8 &&
          header[4] == 0x66 && header[5] == 0x74 &&
          header[6] == 0x79 && header[7] == 0x70) {
        return true; // M4A/AAC ('ftyp')
      }

      if (header.length >= 4 &&
          header[0] == 0x4F && header[1] == 0x67 &&
          header[2] == 0x67 && header[3] == 0x53) {
        return true; // OGG ('OggS')
      }

      // If we can't determine from the header, we could try:
      // 1. Using a more comprehensive audio format detection library
      // 2. Check file extension
      // 3. Try to decode a small portion of the file

      // For now, be permissive if we don't recognize the format
      return true;
    } catch (e) {
      AdvancedLogger.logError('AudioCachingService', 'Audio validation error: $e');
      return false;
    }
  }

  /// Process the download queue in the background
  ///
  /// This method processes downloads up to the maximum concurrent limit
  /// to avoid overloading the network connection.
  Future<void> _processDownloadQueue() async {
    if (_downloadQueue.isEmpty || _activeDownloads >= _config.maxConcurrentDownloads) {
      return;
    }

    // Check conditions
    if (!_shouldProcessDownloads()) {
      return;
    }

    // Prioritize queue
    _prioritizeDownloadQueue();

    // Process up to max concurrent downloads
    while (_downloadQueue.isNotEmpty && _activeDownloads < _config.maxConcurrentDownloads) {
      // Check conditions again
      if (!_shouldProcessDownloads()) {
        break;
      }

      // Get next download
      final nextDownload = _downloadQueue.removeAt(0);

      // Start download
      _downloadFile(
        nextDownload.url,
        nextDownload.cacheKey,
        nextDownload.file,
        nextDownload.completer,
        nextDownload.cancelToken,
        highPriority: false,
        nudge: nextDownload.nudge,
      );
    }
  }

  /// Prioritize the download queue
  ///
  /// Sorts the queue based on various priority factors
  void _prioritizeDownloadQueue() {
    if (_downloadQueue.isEmpty) return;

    _downloadQueue.sort((a, b) {
      // First sort by explicit importance
      if (a.importance != b.importance) {
        return b.importance.compareTo(a.importance);
      }

      // Then by additional factors
      if (_config.prioritizeRecentNudges) {
        // More recent nudges get higher priority
        return b.timestamp.compareTo(a.timestamp);
      } else {
        // Older requests get higher priority
        return a.timestamp.compareTo(b.timestamp);
      }
    });
  }

  /// Update the last accessed time for a cached file
  ///
  /// [cacheKey] The cache key to update
  Future<void> _updateLastAccessed(String cacheKey) async {
    if (_metadata.containsKey(cacheKey)) {
      _metadata[cacheKey] = _metadata[cacheKey]!.copyWith(
        lastAccessed: DateTime.now(),
      );

      // Don't save metadata on every access, just update in-memory
      // We'll save periodically during cleanup

      // If the nudge has been marked as liked by the user, increase importance
      if (_config.prioritizeUserFavorites &&
          _metadata[cacheKey]!.nudgeId != null &&
          _nudgeService != null) {
        try {
          final nudge = await _nudgeService!.getNudgeDeliveryById(_metadata[cacheKey]!.nudgeId!);
          if (nudge != null && nudge.userFeedback == true) {
            _metadata[cacheKey] = _metadata[cacheKey]!.copyWith(
              importance: 8, // Higher importance for liked nudges
            );
          }
        } catch (e) {
          // Ignore errors here
        }
      }
    }
  }

  /// Load metadata from persistent storage
  Future<void> _loadMetadata() async {
    try {
      final prefs = await _storageProvider.getSharedPreferences();
      final metadataJson = prefs.getString('audio_cache_metadata');

      if (metadataJson != null) {
        final metadataList = jsonDecode(metadataJson) as List<dynamic>;

        for (final item in metadataList) {
          try {
            final metadata = _CachedFileMetadata.fromJson(item as Map<String, dynamic>);
            _metadata[metadata.cacheKey] = metadata;
          } catch (e) {
            _logger.w('Failed to parse metadata item', e);
          }
        }

        AdvancedLogger.log('AudioCachingService', 'Loaded metadata for ${_metadata.length} cached files');
      }
    } catch (e) {
      _logger.e('Failed to load cache metadata', e);
      // Continue with empty metadata
    }
  }

  /// Save metadata to persistent storage
  Future<void> _saveMetadata() async {
    try {
      final prefs = await _storageProvider.getSharedPreferences();
      final metadataList = _metadata.values.map((m) => m.toJson()).toList();
      final metadataJson = jsonEncode(metadataList);

      await prefs.setString('audio_cache_metadata', metadataJson);
    } catch (e) {
      _logger.e('Failed to save cache metadata', e);
    }
  }

  /// Schedule cache cleanup as needed
  Future<void> _scheduleCleanup() async {
    try {
      // Check cache size
      final cacheSize = await getCacheSize();

      // If cache is over 80% full, enforce max size
      if (cacheSize > _config.maxCacheSizeBytes * 0.8) {
        await _enforceMaxCacheSize();
      }

      // Remove old files
      await _removeOldFiles();

      // Compare metadata with actual files and sync
      await _syncMetadataWithFiles();

      // Save metadata after cleanup
      await _saveMetadata();
    } catch (e) {
      _logger.e('Failed to schedule cleanup', e);
    }
  }

  /// Enforce the maximum cache size by removing least recently used files
  Future<void> _enforceMaxCacheSize() async {
    try {
      // Get current cache size
      final cacheSize = await getCacheSize();

      if (cacheSize <= _config.maxCacheSizeBytes) {
        return;
      }

      // Calculate how much we need to free up (target 70% of max)
      final targetSize = _config.maxCacheSizeBytes * 0.7;
      final bytesToFree = cacheSize - targetSize.toInt();

      if (bytesToFree <= 0) {
        return;
      }

      // Build a priority list for deletion
      // Items with lower scores get deleted first
      final deletionCandidates = <String, int>{};

      for (final entry in _metadata.entries) {
        final metadata = entry.value;
        final key = entry.key;

        // Skip files that are currently being downloaded
        if (_ongoingDownloads.containsKey(key)) {
          continue;
        }

        // Calculate a priority score (higher = more important to keep)
        int score = 0;

        // Factor 1: Last accessed time (more recent = higher score)
        final daysSinceAccess = DateTime.now().difference(metadata.lastAccessed).inDays;
        score += max(30 - daysSinceAccess, 0) * 10; // Max 300 points for recent access

        // Factor 2: User feedback (liked nudges get higher score)
        if (_config.prioritizeUserFavorites &&
            metadata.nudgeId != null &&
            _nudgeService != null) {
          try {
            final nudge = await _nudgeService!.getNudgeDeliveryById(metadata.nudgeId!);
            if (nudge != null && nudge.userFeedback == true) {
              score += 200; // Significant boost for liked nudges
            }
          } catch (e) {
            // Ignore errors here
          }
        }

        // Factor 3: Explicit importance
        score += metadata.importance * 20; // Up to 200 points for importance

        // Factor 4: File size (smaller files get lower deletion priority)
        score += min(metadata.fileSize ~/ 102400, 10); // Up to 10 points for small files

        deletionCandidates[key] = score;
      }

      // Sort by score (ascending - delete lowest scores first)
      final sortedKeys = deletionCandidates.keys.toList()
        ..sort((a, b) => deletionCandidates[a]!.compareTo(deletionCandidates[b]!));

      int freedBytes = 0;

      // Remove files until we've freed enough space
      for (final key in sortedKeys) {
        if (freedBytes >= bytesToFree) {
          break;
        }

        final filePath = '${_cacheDirectory!.path}/$key.mp3';
        final file = File(filePath);

        if (await file.exists()) {
          final fileSize = await file.length();
          await file.delete();
          freedBytes += fileSize;

          // Remove from metadata
          _metadata.remove(key);

          AdvancedLogger.log(
            'AudioCachingService',
            'Removed cached file: $key, ${fileSize ~/ 1024}KB (score: ${deletionCandidates[key]})',
          );
        }
      }

      AdvancedLogger.log(
        'AudioCachingService',
        'Freed ${freedBytes ~/ 1024}KB from cache',
      );
    } catch (e) {
      _logger.e('Failed to enforce max cache size', e);
    }
  }

  /// Remove files that are older than the maximum age
  Future<void> _removeOldFiles() async {
    try {
      final now = DateTime.now();
      final cutoffDate = now.subtract(Duration(days: _config.maxFileAge));

      // Get candidates for removal
      final filesToRemove = _metadata.entries
          .where((entry) =>
      entry.value.createdAt.isBefore(cutoffDate) &&
          !_ongoingDownloads.containsKey(entry.key))
          .map((entry) => entry.key)
          .toList();

      for (final key in filesToRemove) {
        // Skip if user has liked the nudge
        if (_config.prioritizeUserFavorites &&
            _metadata[key]!.nudgeId != null &&
            _nudgeService != null) {
          try {
            final nudge = await _nudgeService!.getNudgeDeliveryById(_metadata[key]!.nudgeId!);
            if (nudge != null && nudge.userFeedback == true) {
              continue; // Keep liked nudges longer
            }
          } catch (e) {
            // Ignore errors here
          }
        }

        final filePath = '${_cacheDirectory!.path}/$key.mp3';
        final file = File(filePath);

        if (await file.exists()) {
          await file.delete();
        }

        // Remove from metadata
        _metadata.remove(key);

        AdvancedLogger.log(
          'AudioCachingService',
          'Removed old cached file: $key',
        );
      }
    } catch (e) {
      _logger.e('Failed to remove old files', e);
    }
  }

  /// Sync metadata with actual files on disk
  Future<void> _syncMetadataWithFiles() async {
    try {
      if (_cacheDirectory == null || !await _cacheDirectory!.exists()) {
        return;
      }

      // Get all files in the cache directory
      final files = await _cacheDirectory!.list().toList();
      final fileNames = files
          .whereType<File>()
          .map((f) => f.path.split('/').last)
          .where((name) => name.endsWith('.mp3'))
          .map((name) => name.substring(0, name.length - 4))
          .toSet();

      // Remove metadata for files that don't exist
      final keysToRemove = _metadata.keys
          .where((key) => !fileNames.contains(key))
          .toList();

      for (final key in keysToRemove) {
        _metadata.remove(key);
      }

      // Add metadata for files that exist but aren't in metadata
      final keysToAdd = fileNames
          .where((name) => !_metadata.containsKey(name))
          .toList();

      for (final key in keysToAdd) {
        final filePath = '${_cacheDirectory!.path}/$key.mp3';
        final file = File(filePath);

        if (await file.exists()) {
          final fileSize = await file.length();

          _metadata[key] = _CachedFileMetadata(
            url: 'unknown', // We don't know the original URL
            cacheKey: key,
            fileSize: fileSize,
            lastAccessed: DateTime.now(),
            createdAt: DateTime.now(),
            isComplete: true,
            nudgeId: null,
            importance: 5, // Default importance
            contentType: null,
          );
        }
      }

      if (keysToRemove.isNotEmpty || keysToAdd.isNotEmpty) {
        AdvancedLogger.log(
          'AudioCachingService',
          'Synced metadata: removed ${keysToRemove.length}, added ${keysToAdd.length}',
        );
      }
    } catch (e) {
      _logger.e('Failed to sync metadata with files', e);
    }
  }

  /// Send an accessibility notification
  ///
  /// Announces important events to assist elderly users
  ///
  /// [message] The message to announce
  void _notifyAccessibilityEvent(String message) {
    try {
      // Only announce significant events to avoid overwhelming the user
      HapticFeedback.mediumImpact();
      SemanticsService.announce(message, TextDirection.ltr);
    } catch (e) {
      // Ignore accessibility errors
    }
  }

  /// Categorize an error into a specific error type
  ///
  /// [error] The error to categorize
  ///
  /// Returns the appropriate error type
  AudioCacheErrorType _categorizeError(dynamic error) {
    if (error is AudioCacheException) {
      return error.type;
    }

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('permission') ||
        errorString.contains('access denied')) {
      return AudioCacheErrorType.permission;
    }

    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('socket') ||
        errorString.contains('internet') ||
        error is SocketException) {
      return AudioCacheErrorType.network;
    }

    if (errorString.contains('storage') ||
        errorString.contains('disk') ||
        errorString.contains('space') ||
        errorString.contains('capacity') ||
        errorString.contains('file')) {
      return AudioCacheErrorType.storage;
    }

    if (errorString.contains('content') ||
        errorString.contains('format') ||
        errorString.contains('invalid') ||
        errorString.contains('corrupt') ||
        errorString.contains('mime')) {
      return AudioCacheErrorType.invalidContent;
    }

    if (errorString.contains('timeout') ||
        errorString.contains('timed out')) {
      return AudioCacheErrorType.timeout;
    }

    return AudioCacheErrorType.unknown;
  }

  /// Determine if a download should be retried
  ///
  /// [error] The error that occurred
  ///
  /// Returns true if the download should be retried, false otherwise
  bool _shouldRetryDownload(dynamic error) {
    if (error is AudioCacheException) {
      // Only retry network errors, not content or permission errors
      return error.type == AudioCacheErrorType.network ||
          error.type == AudioCacheErrorType.timeout;
    }

    final errorString = error.toString().toLowerCase();

    // Retry network-related errors
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('socket') ||
        errorString.contains('timeout') ||
        errorString.contains('internet') ||
        error is SocketException) {
      return true;
    }

    // Don't retry permission or content errors
    if (errorString.contains('permission') ||
        errorString.contains('access denied') ||
        errorString.contains('content') ||
        errorString.contains('format') ||
        errorString.contains('invalid')) {
      return false;
    }

    // For unknown errors, retry once
    return true;
  }
}

/// Exception for audio cache operations
class AudioCacheException implements Exception {
  /// User-friendly error message
  final String message;

  /// Type of error
  final AudioCacheErrorType type;

  /// Original cause of the error
  final dynamic cause;

  AudioCacheException(this.message, this.type, {this.cause});

  @override
  String toString() => 'AudioCacheException: $message';
}

/// Progress information for downloads
class DownloadProgress {
  /// URL being downloaded
  final String url;

  /// Progress from 0.0 to 1.0
  final double progress;

  /// Bytes received so far
  final int bytesReceived;

  /// Total bytes to download (may be -1 if unknown)
  final int totalBytes;

  /// Cache key for the download
  final String cacheKey;

  /// Associated nudge ID (if any)
  final String? nudgeId;

  /// Whether this is a high priority download
  final bool isHighPriority;

  DownloadProgress({
    required this.url,
    required this.progress,
    required this.bytesReceived,
    required this.totalBytes,
    required this.cacheKey,
    this.nudgeId,
    this.isHighPriority = false,
  });
}

/// Internal progress tracking
class _DownloadProgress {
  final String url;
  final double progress;
  final int bytesReceived;
  final int totalBytes;
  final String cacheKey;
  final String? nudgeId;
  final bool isHighPriority;

  _DownloadProgress({
    required this.url,
    required this.progress,
    required this.bytesReceived,
    required this.totalBytes,
    required this.cacheKey,
    this.nudgeId,
    this.isHighPriority = false,
  });
}

/// Metadata for a cached file
class _CachedFileMetadata {
  /// Original URL of the file
  final String url;

  /// Cache key (hash of the URL)
  final String cacheKey;

  /// Size of the file in bytes
  final int fileSize;

  /// When the file was last accessed
  final DateTime lastAccessed;

  /// When the file was created
  final DateTime createdAt;

  /// Whether the download completed successfully
  final bool isComplete;

  /// ID of the associated nudge (if any)
  final String? nudgeId;

  /// Importance of this file (0-10, higher = more important)
  final int importance;

  /// Content type of the file
  final String? contentType;

  _CachedFileMetadata({
    required this.url,
    required this.cacheKey,
    required this.fileSize,
    required this.lastAccessed,
    required this.createdAt,
    required this.isComplete,
    this.nudgeId,
    this.importance = 5,
    this.contentType,
  });

  /// Create a copy with updated fields
  _CachedFileMetadata copyWith({
    String? url,
    String? cacheKey,
    int? fileSize,
    DateTime? lastAccessed,
    DateTime? createdAt,
    bool? isComplete,
    String? nudgeId,
    int? importance,
    String? contentType,
  }) {
    return _CachedFileMetadata(
      url: url ?? this.url,
      cacheKey: cacheKey ?? this.cacheKey,
      fileSize: fileSize ?? this.fileSize,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      createdAt: createdAt ?? this.createdAt,
      isComplete: isComplete ?? this.isComplete,
      nudgeId: nudgeId ?? this.nudgeId,
      importance: importance ?? this.importance,
      contentType: contentType ?? this.contentType,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'cacheKey': cacheKey,
      'fileSize': fileSize,
      'lastAccessed': lastAccessed.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isComplete': isComplete,
      'nudgeId': nudgeId,
      'importance': importance,
      'contentType': contentType,
    };
  }

  /// Create from JSON
  factory _CachedFileMetadata.fromJson(Map<String, dynamic> json) {
    return _CachedFileMetadata(
      url: json['url'] as String,
      cacheKey: json['cacheKey'] as String,
      fileSize: json['fileSize'] as int,
      lastAccessed: DateTime.fromMillisecondsSinceEpoch(json['lastAccessed'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      isComplete: json['isComplete'] as bool,
      nudgeId: json['nudgeId'] as String?,
      importance: json['importance'] as int? ?? 5,
      contentType: json['contentType'] as String?,
    );
  }
}

/// Pending download in the queue
class _PendingDownload {
  /// URL to download
  final String url;

  /// Cache key
  final String cacheKey;

  /// File to save to
  final File file;

  /// Completer to resolve when download completes
  final Completer<File> completer;

  /// Token to cancel the download
  final CancelToken cancelToken;

  /// Associated nudge (if any)
  final NudgeDelivery? nudge;

  /// When this download was queued
  final DateTime timestamp;

  /// Importance of this download (0-10, higher = more important)
  final int importance;

  _PendingDownload({
    required this.url,
    required this.cacheKey,
    required this.file,
    required this.completer,
    required this.cancelToken,
    this.nudge,
    DateTime? timestamp,
    this.importance = 5,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Download operation tracking
class _DownloadOperation {
  /// Future that completes when download is done
  final Future<File> future;

  /// Token to cancel the download
  final CancelToken cancelToken;

  /// Whether this is a high priority download
  final bool isHighPriority;

  _DownloadOperation({
    required this.future,
    required this.cancelToken,
    this.isHighPriority = false,
  });
}

/// Cancel token for downloads
class CancelToken {
  bool _isCancelled = false;

  /// Whether this token has been cancelled
  bool get isCancelled => _isCancelled;

  /// Cancel the operation
  void cancel() {
    _isCancelled = true;
  }
}

/// Simple mutex for synchronizing access to critical sections
class _AsyncMutex {
  Completer<void>? _completer;

  /// Execute a function with mutual exclusion
  Future<T> synchronized<T>(Future<T> Function() fn) async {
    // Wait for any ongoing operation
    if (_completer != null) {
      await _completer!.future;
    }

    // Create a new completer
    _completer = Completer<void>();

    try {
      // Execute the function
      return await fn();
    } finally {
      // Complete the completer
      final completer = _completer;
      _completer = null;
      completer!.complete();
    }
  }
}

/// Helper function to run futures without awaiting them
void unawaited(Future<void> future) {
  // Deliberately not awaiting the future
  // This function just silences the "unawaited future" lint warning
}

// Interfaces for testability
// These allow mocking dependencies in tests

/// Interface for connectivity services
abstract class ConnectivityProvider {
  /// Get the current connectivity status
  Future<ConnectivityResult> checkConnectivity();

  /// Stream of connectivity changes
  Stream<ConnectivityResult> get onConnectivityChanged;
}

/// Real implementation of ConnectivityProvider
class RealConnectivityProvider implements ConnectivityProvider {
  final Connectivity _connectivity = Connectivity();

  @override
  Future<ConnectivityResult> checkConnectivity() {
    return _connectivity.checkConnectivity();
  }

  @override
  Stream<ConnectivityResult> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }
}

/// Interface for storage services
abstract class StorageProvider {
  /// Get the application documents directory
  Future<Directory> getApplicationDocumentsDirectory();

  /// Get shared preferences
  Future<SharedPreferences> getSharedPreferences();
}

/// Real implementation of StorageProvider
class RealStorageProvider implements StorageProvider {
  @override
  Future<Directory> getApplicationDocumentsDirectory() {
    return getApplicationDocumentsDirectory();
  }

  @override
  Future<SharedPreferences> getSharedPreferences() {
    return SharedPreferences.getInstance();
  }
}

/// Interface for battery services
abstract class BatteryProvider {
  /// Get the current battery level (0-100)
  Future<int> get batteryLevel;

  /// Check if the device is currently charging
  Future<bool> get isCharging;

  /// Stream of battery level changes
  Stream<int> get onBatteryLevelChanged;

  /// Stream of charging status changes
  Stream<bool> get onChargingStatusChanged;
}

/// Real implementation of BatteryProvider
class RealBatteryProvider implements BatteryProvider {
  final Battery _battery = Battery();

  @override
  Future<int> get batteryLevel {
    return _battery.batteryLevel;
  }

  @override
  Future<bool> get isCharging async {
    return await _battery.batteryState.then(
          (state) => state == BatteryState.charging || state == BatteryState.full,
    );
  }

  @override
  Stream<int> get onBatteryLevelChanged {
    return Stream<int>.periodic(const Duration(minutes: 5), (_) {
      return _battery.batteryLevel;
    }).asyncMap((future) => future);
  }

  @override
  Stream<bool> get onChargingStatusChanged {
    return _battery.onBatteryStateChanged.map(
          (state) => state == BatteryState.charging || state == BatteryState.full,
    );
  }
}

/// Interface for HTTP clients
abstract class HttpClientProvider {
  /// Get an HTTP client
  http.Client getClient();
}

/// Real implementation of HttpClientProvider
class RealHttpClientProvider implements HttpClientProvider {
  @override
  http.Client getClient() {
    return http.Client();
  }
}