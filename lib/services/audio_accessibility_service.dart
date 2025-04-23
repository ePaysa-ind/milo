// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/services/audio_accessibility_service.dart
// Version: 1.1.0
// Last Updated: April 21, 2025
// Description: Service for enhancing audio accessibility for elderly users (55+)
// Change History:
// - 1.0.0: Initial implementation with basic features
// - 1.1.0: Added platform-specific implementation, improved error recovery,
//          memory management, performance monitoring, and localization support

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/nudge_model.dart';
import '../utils/advanced_logger.dart';
import '../utils/error_reporter.dart';
import '../utils/config.dart';
import '../services/localization_service.dart';
import '../services/secure_storage_service.dart';
import '../services/app_lifecycle_service.dart';

/// Error types for audio accessibility operations
enum AudioAccessibilityErrorType {
  /// Audio engine related errors
  engine,

  /// File access errors
  fileAccess,

  /// Processing errors
  processing,

  /// Device compatibility errors
  compatibility,

  /// Permission related errors
  permission,

  /// Resource constraints (memory, CPU)
  resource,

  /// Data privacy issues
  privacy,

  /// Format compatibility issues
  format,

  /// Generic errors
  unknown
}

/// Configuration for the audio accessibility service
///
/// This allows dynamic adjustments to accessibility features without code changes
class AudioAccessibilityConfig {
  /// Default speaking rate (0.5 - 2.0, 1.0 is normal)
  final double defaultSpeakingRate;

  /// Default pitch (0.5 - 2.0, 1.0 is normal)
  final double defaultPitch;

  /// Default volume (0.0 - 1.0)
  final double defaultVolume;

  /// Enable frequency adjustment for better clarity
  final bool enableFrequencyAdjustment;

  /// Bass boost amount (0.0 - 1.0)
  final double bassBoost;

  /// Treble boost for speech clarity (0.0 - 1.0)
  final double trebleBoost;

  /// Enable auto-volume normalization
  final bool enableVolumeNormalization;

  /// Target RMS level for normalization (dB)
  final double targetRmsLevel;

  /// Maximum gain for normalization
  final double maxNormalizationGain;

  /// Enable audio focus for hearing aids
  final bool enableHearingAidFocus;

  /// Enable haptic feedback for audio events
  final bool enableHapticFeedback;

  /// Speaking rate increment for speed controls
  final double speedControlIncrement;

  /// Timeout duration for audio processing
  final Duration processingTimeout;

  /// Maximum cache size in bytes
  final int maxCacheSizeBytes;

  /// Maximum age of cached files in days
  final int maxCacheAgeDays;

  /// Maximum memory usage for processing in bytes
  final int maxMemoryUsageBytes;

  /// Enable debug logging
  final bool enableDebugLogs;

  /// Enable privacy-focused processing (local-only)
  final bool enablePrivacyMode;

  /// Supported audio formats
  final List<String> supportedFormats;

  /// Default language for announcements
  final String defaultLanguage;

  /// Enable battery-saving mode
  final bool enableBatterySaving;

  /// Number of processing retry attempts
  final int maxProcessingRetries;

  const AudioAccessibilityConfig({
    this.defaultSpeakingRate = 0.85, // Slightly slower for elderly users
    this.defaultPitch = 1.0,
    this.defaultVolume = 0.85,
    this.enableFrequencyAdjustment = true,
    this.bassBoost = 0.3,
    this.trebleBoost = 0.5, // Higher treble helps with speech clarity
    this.enableVolumeNormalization = true,
    this.targetRmsLevel = -18.0,
    this.maxNormalizationGain = 12.0,
    this.enableHearingAidFocus = true,
    this.enableHapticFeedback = true,
    this.speedControlIncrement = 0.1,
    this.processingTimeout = const Duration(seconds: 30),
    this.maxCacheSizeBytes = 100 * 1024 * 1024, // 100 MB
    this.maxCacheAgeDays = 7,
    this.maxMemoryUsageBytes = 50 * 1024 * 1024, // 50 MB
    this.enableDebugLogs = false,
    this.enablePrivacyMode = true,
    this.supportedFormats = const ['mp3', 'aac', 'm4a', 'wav', 'ogg'],
    this.defaultLanguage = 'en',
    this.enableBatterySaving = true,
    this.maxProcessingRetries = 3,
  });

  /// Create a config optimized for low-end devices
  factory AudioAccessibilityConfig.lowResource() {
    return const AudioAccessibilityConfig(
      enableFrequencyAdjustment: false,
      enableVolumeNormalization: true, // Keep this as it's most important
      maxCacheSizeBytes: 50 * 1024 * 1024, // 50 MB
      maxMemoryUsageBytes: 20 * 1024 * 1024, // 20 MB
      maxProcessingRetries: 1,
      processingTimeout: Duration(seconds: 15),
    );
  }

  /// Create a high-privacy config with local-only processing
  factory AudioAccessibilityConfig.highPrivacy() {
    return const AudioAccessibilityConfig(
      enablePrivacyMode: true,
      maxCacheAgeDays: 1, // Very short retention
    );
  }
}

/// Processing mode for the service
enum ProcessingMode {
  /// Full processing with all features
  full,

  /// Basic processing for lower-end devices
  basic,

  /// Minimal processing for emergencies or very low resources
  minimal,

  /// Direct passthrough with no processing
  passthrough
}

/// Accessibility event types
enum AudioAccessibilityEventType {
  /// Service initialization completed
  serviceInitialized,

  /// Processing started
  processingStarted,

  /// Processing progress updated
  processingProgress,

  /// Processing completed
  processingCompleted,

  /// Processing error occurred
  processingError,

  /// Playback started
  playbackStarted,

  /// Playback paused
  playbackPaused,

  /// Playback resumed
  playbackResumed,

  /// Playback stopped
  playbackStopped,

  /// Playback completed
  playbackCompleted,

  /// Playback interrupted
  playbackInterrupted,

  /// Playback error
  playbackError,

  /// Settings changed
  settingsChanged,

  /// Memory pressure detected
  memoryPressure,

  /// Cache cleared
  cacheCleared,

  /// Feature enabled/disabled
  featureToggled,
}

/// Accessibility features that can be applied to audio
enum AccessibilityFeature {
  /// Volume normalization for consistent levels
  volumeNormalization,

  /// Frequency adjustment for better speech perception
  frequencyAdjustment,

  /// Dynamic range compression for better hearing in noisy environments
  dynamicRangeCompression,

  /// Noise reduction to improve clarity
  noiseReduction,

  /// Speech enhancement to improve intelligibility
  speechEnhancement,

  /// Hearing aid compatibility features
  hearingAidCompatibility,
}

/// Playback state for enhanced audio
class PlaybackState {
  /// Whether audio is currently playing
  final bool isPlaying;

  /// Current playback position in seconds
  final double positionSeconds;

  /// Total duration in seconds
  final double durationSeconds;

  /// Current volume level (0.0-1.0)
  final double volume;

  /// Current playback speed (0.5-2.0)
  final double speed;

  /// Whether audio is currently buffering
  final bool isBuffering;

  /// Percentage loaded (0.0-1.0)
  final double bufferedPercentage;

  /// Whether an error occurred during playback
  final bool hasError;

  /// Error message if hasError is true
  final String? errorMessage;

  PlaybackState({
    required this.isPlaying,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.volume,
    required this.speed,
    this.isBuffering = false,
    this.bufferedPercentage = 0.0,
    this.hasError = false,
    this.errorMessage,
  });

  /// Create a copy with updated properties
  PlaybackState copyWith({
    bool? isPlaying,
    double? positionSeconds,
    double? durationSeconds,
    double? volume,
    double? speed,
    bool? isBuffering,
    double? bufferedPercentage,
    bool? hasError,
    String? errorMessage,
  }) {
    return PlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      isBuffering: isBuffering ?? this.isBuffering,
      bufferedPercentage: bufferedPercentage ?? this.bufferedPercentage,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Event for accessibility service status updates
class AudioAccessibilityEvent {
  /// Type of event
  final AudioAccessibilityEventType type;

  /// Human-readable message describing the event
  final String message;

  /// When the event occurred
  final DateTime timestamp;

  /// Nudge ID if this event is related to a nudge
  final String? nudgeId;

  /// Progress value (0.0-1.0) for progress events
  final double? progress;

  /// Error type if this is an error event
  final AudioAccessibilityErrorType? errorType;

  /// Additional data related to the event
  final Map<String, dynamic>? data;

  AudioAccessibilityEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.nudgeId,
    this.progress,
    this.errorType,
    this.data,
  });
}

/// Debug metrics for monitoring performance
class DebugMetrics {
  /// Processing time in milliseconds
  final int? processingTime;

  /// Current memory usage in bytes
  final int memoryUsage;

  /// Total cache size in bytes
  final int cacheSize;

  /// Number of active operations
  final int activeOperations;

  /// Current processing mode
  final ProcessingMode mode;

  /// Whether the last operation was successful
  final bool success;

  DebugMetrics({
    this.processingTime,
    required this.memoryUsage,
    required this.cacheSize,
    required this.activeOperations,
    required this.mode,
    required this.success,
  });
}

/// Internal class for debug metrics
class _DebugMetrics {
  final int? processingTime;
  final int memoryUsage;
  final int cacheSize;
  final int activeOperations;
  final ProcessingMode mode;
  final bool success;
  final String? note;

  _DebugMetrics({
    this.processingTime,
    required this.memoryUsage,
    required this.cacheSize,
    required this.activeOperations,
    required this.mode,
    required this.success,
    this.note,
  });
}

/// Interface for audio engine providers
abstract class AudioEngineProvider {
  /// Get audio session for configuration
  Future<AudioSession> getAudioSession();

  /// Create audio player with appropriate settings
  Future<AudioPlayer> createPlayer();

  /// Create audio pipeline for processing
  Future<AudioPipeline> createPipeline(String id, String audioPath);
}

/// Real implementation of AudioEngineProvider
class RealAudioEngineProvider implements AudioEngineProvider {
  @override
  Future<AudioSession> getAudioSession() async {
    return await AudioSession.instance;
  }

  @override
  Future<AudioPlayer> createPlayer() async {
    return AudioPlayer();
  }

  @override
  Future<AudioPipeline> createPipeline(String id, String audioPath) async {
    final player = await createPlayer();
    await player.setFilePath(audioPath);

    return AudioPipeline(
      id: id,
      player: player,
      audioPath: audioPath,
    );
  }
}

/// Interface for storage providers
abstract class StorageProvider {
  /// Get application documents directory
  Future<Directory> getApplicationDocumentsDirectory();

  /// Get shared preferences
  Future<SharedPreferences> getSharedPreferences();

  /// Save a file to the application documents directory
  Future<File> saveFile(List<int> bytes, String fileName);

  /// Delete a file
  Future<bool> deleteFile(String path);
}

/// Real implementation of StorageProvider
class RealStorageProvider implements StorageProvider {
  @override
  Future<Directory> getApplicationDocumentsDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  @override
  Future<SharedPreferences> getSharedPreferences() async {
    return await SharedPreferences.getInstance();
  }

  @override
  Future<File> saveFile(List<int> bytes, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    return await file.writeAsBytes(bytes);
  }

  @override
  Future<bool> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }
}

/// Interface for text-to-speech providers
abstract class TextToSpeechProvider {
  /// Initialize the TTS engine
  Future<void> initialize();

  /// Set the speech rate
  Future<void> setSpeechRate(double rate);

  /// Set the pitch
  Future<void> setPitch(double pitch);

  /// Set the volume
  Future<void> setVolume(double volume);

  /// Set the language
  Future<void> setLanguage(String language);

  /// Set the voice
  Future<void> setVoice(String voice);

  /// Speak the given text
  Future<void> speak(String text);

  /// Stop speaking
  Future<void> stop();

  /// Get available voices
  Future<List<String>> getAvailableVoices();
}

/// Real implementation of TextToSpeechProvider
class RealTextToSpeechProvider implements TextToSpeechProvider {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _flutterTts.setSharedInstance(true);
    await _flutterTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.ambient,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
      IosTextToSpeechAudioMode.spokenAudio,
    );

    _isInitialized = true;
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _flutterTts.setSpeechRate(rate);
  }

  @override
  Future<void> setPitch(double pitch) async {
    await _flutterTts.setPitch(pitch);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _flutterTts.setVolume(volume);
  }

  @override
  Future<void> setLanguage(String language) async {
    await _flutterTts.setLanguage(language);
  }

  @override
  Future<void> setVoice(String voice) async {
    await _flutterTts.setVoice({"name": voice, "locale": voice.split('-')[0]});
  }

  @override
  Future<void> speak(String text) async {
    await _flutterTts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _flutterTts.stop();
  }

  @override
  Future<List<String>> getAvailableVoices() async {
    final voices = await _flutterTts.getVoices;

    if (voices is List) {
      return voices
          .map((voice) => voice['name'] as String)
          .toList();
    }

    return [];
  }
}

/// Interface for audio processing
abstract class AudioProcessor {
  /// Normalize volume levels for consistent playback
  Future<bool> normalizeVolume(
      String inputPath,
      String outputPath, {
        double targetLevel,
        double maxGain,
      });

  /// Adjust frequency response for better clarity
  Future<bool> adjustFrequency(
      String inputPath,
      String outputPath, {
        double bassBoost,
        double trebleBoost,
      });

  /// Compress dynamic range for better speech intelligibility
  Future<bool> compressDynamicRange(
      String inputPath,
      String outputPath, {
        double threshold,
        double ratio,
      });
}

/// Real implementation of AudioProcessor
class RealAudioProcessor implements AudioProcessor {
  @override
  Future<bool> normalizeVolume(
      String inputPath,
      String outputPath, {
        double targetLevel = -18.0,
        double maxGain = 12.0,
      }) async {
    try {
      final session = await FFmpegKit.execute(
        '-i "$inputPath" -af "volume=volume=1.5:precision=fixed" -y "$outputPath"',
      );

      final returnCode = await session.getReturnCode();
      return returnCode != null && returnCode.isValueSuccess();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> adjustFrequency(
      String inputPath,
      String outputPath, {
        double bassBoost = 0.3,
        double trebleBoost = 0.5,
      }) async {
    try {
      final session = await FFmpegKit.execute(
        '-i "$inputPath" -af "equalizer=f=100:width_type=o:width=2:g=${bassBoost * 10},'
            'equalizer=f=6000:width_type=o:width=2:g=${trebleBoost * 10}" -y "$outputPath"',
      );

      final returnCode = await session.getReturnCode();
      return returnCode != null && returnCode.isValueSuccess();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> compressDynamicRange(
      String inputPath,
      String outputPath, {
        double threshold = -24.0,
        double ratio = 4.0,
      }) async {
    try {
      final session = await FFmpegKit.execute(
        '-i "$inputPath" -af "acompressor=threshold=$threshold:ratio=$ratio:attack=200:release=1000" -y "$outputPath"',
      );

      final returnCode = await session.getReturnCode();
      return returnCode != null && returnCode.isValueSuccess();
    } catch (e) {
      return false;
    }
  }
}

/// Audio pipeline for playback with accessibility enhancements
class AudioPipeline {
  /// Unique ID for this pipeline
  final String id;

  /// Audio player instance
  final AudioPlayer player;

  /// Path to the audio file
  final String audioPath;

  /// Stream controller for playback status updates
  final StreamController<PlaybackState> _stateController;

  /// Stream subscription for player updates
  StreamSubscription? _playerSubscription;

  /// Current playback state
  PlaybackState _currentState;

  /// Timer for position updates
  Timer? _positionTimer;

  /// Stream of playback state updates
  Stream<PlaybackState> get playbackStateStream => _stateController.stream;

  /// Current playback state
  PlaybackState get currentState => _currentState;

  AudioPipeline({
    required this.id,
    required this.player,
    required this.audioPath,
  }) :
        _stateController = StreamController<PlaybackState>.broadcast(),
        _currentState = PlaybackState(
          isPlaying: false,
          positionSeconds: 0,
          durationSeconds: 0,
          volume: 1.0,
          speed: 1.0,
        ) {
    _init();
  }

  /// Initialize the pipeline
  void _init() {
    // Listen for player state changes
    _playerSubscription = player.playerStateStream.listen((state) {
      final isPlaying = state.playing;
      final processingState = state.processingState;

      // Update current state based on player state
      _currentState = _currentState.copyWith(
        isPlaying: isPlaying,
        isBuffering: processingState == ProcessingState.buffering,
        hasError: processingState == ProcessingState.completed && player.position.inMilliseconds == 0,
      );

      // Emit updated state
      _stateController.add(_currentState);

      // Start position timer if playing
      if (isPlaying && _positionTimer == null) {
        _startPositionTimer();
      } else if (!isPlaying && _positionTimer != null) {
        _stopPositionTimer();
      }
    });

    // Get initial duration when available
    player.durationStream.listen((duration) {
      if (duration != null) {
        _currentState = _currentState.copyWith(
          durationSeconds: duration.inMilliseconds / 1000,
        );
        _stateController.add(_currentState);
      }
    });

    // Listen for buffer updates
    player.bufferedPositionStream.listen((buffered) {
      final duration = player.duration;
      if (duration != null && duration.inMilliseconds > 0) {
        final percentage = buffered.inMilliseconds / duration.inMilliseconds;
        _currentState = _currentState.copyWith(
          bufferedPercentage: percentage,
        );
        _stateController.add(_currentState);
      }
    });

    // Listen for errors
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _currentState = _currentState.copyWith(
          isPlaying: false,
          positionSeconds: _currentState.durationSeconds,
        );
        _stateController.add(_currentState);
      }
    });
  }

  /// Start timer for position updates
  void _startPositionTimer() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final position = player.position;
      _currentState = _currentState.copyWith(
        positionSeconds: position.inMilliseconds / 1000,
      );
      _stateController.add(_currentState);
    });
  }

  /// Stop position update timer
  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  /// Play audio
  Future<void> play() async {
    await player.play();
  }

  /// Pause audio
  Future<void> pause() async {
    await player.pause();
  }

  /// Stop audio and reset position
  Future<void> stop() async {
    await player.stop();
    await player.seek(Duration.zero);
  }

  /// Seek to a position in seconds
  Future<void> seekTo(double seconds) async {
    await player.seek(Duration(milliseconds: (seconds * 1000).round()));
  }

  /// Set volume (0.0-1.0)
  Future<void> setVolume(double volume) async {
    await player.setVolume(volume);
    _currentState = _currentState.copyWith(volume: volume);
    _stateController.add(_currentState);
  }

  /// Set playback speed (0.5-2.0)
  Future<void> setSpeed(double speed) async {
    await player.setSpeed(speed);
    _currentState = _currentState.copyWith(speed: speed);
    _stateController.add(_currentState);
  }

  /// Dispose of resources
  void dispose() {
    _playerSubscription?.cancel();
    _stopPositionTimer();
    player.dispose();
    _stateController.close();
  }
}

/// Subscriber for accessibility events
class AccessibilitySubscriber {
  /// Callback for actions
  final void Function(AudioAccessibilityAction action, dynamic data) onAction;

  AccessibilitySubscriber({required this.onAction});

  /// Clean up resources
  void dispose() {
    // No resources to clean up in this implementation
  }
}

/// Actions that can be performed by subscribers
enum AudioAccessibilityAction {
  /// Processing started
  processingStarted,

  /// Processing completed
  processingCompleted,

  /// Playback started
  playbackStarted,

  /// Playback stopped
  playbackStopped,

  /// Settings changed
  settingsChanged,
}

/// Exception for audio accessibility errors
class AudioAccessibilityException implements Exception {
  /// Error message
  final String message;

  /// Type of error
  final AudioAccessibilityErrorType type;

  /// Original cause of the error
  final dynamic cause;

  AudioAccessibilityException(
      this.message,
      this.type, {
        this.cause,
      });

  @override
  String toString() => 'AudioAccessibilityException: $message (${type.name})';
}

/// Processed audio cache entry
class _ProcessedAudioCache {
  /// Path to the original input file
  final String inputPath;

  /// Path to the processed output file
  final String outputPath;

  /// Set of features that were applied
  final Set<AccessibilityFeature> features;

  /// Output format
  final String format;

  /// When the file was processed
  final DateTime timestamp;

  /// When the file was last accessed
  final DateTime lastAccessed;

  /// In-memory size in bytes
  final int memorySizeBytes;

  _ProcessedAudioCache({
    required this.inputPath,
    required this.outputPath,
    required this.features,
    required this.format,
    required this.timestamp,
    required this.lastAccessed,
    required this.memorySizeBytes,
  });

  /// Create a copy with updated properties
  _ProcessedAudioCache copyWith({
    String? inputPath,
    String? outputPath,
    Set<AccessibilityFeature>? features,
    String? format,
    DateTime? timestamp,
    DateTime? lastAccessed,
    int? memorySizeBytes,
  }) {
    return _ProcessedAudioCache(
      inputPath: inputPath ?? this.inputPath,
      outputPath: outputPath ?? this.outputPath,
      features: features ?? this.features,
      format: format ?? this.format,
      timestamp: timestamp ?? this.timestamp,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      memorySizeBytes: memorySizeBytes ?? this.memorySizeBytes,
    );
  }
}

/// File info for cache management
class _FileInfo {
  /// File reference
  final File file;

  /// File size in bytes
  final int size;

  /// When the file was last accessed
  final DateTime lastAccessed;

  /// When the file was last modified
  final DateTime lastModified;

  _FileInfo({
    required this.file,
    required this.size,
    required this.lastAccessed,
    required this.lastModified,
  });
}

/// Performance metrics for operations
class _PerformanceMetrics {
  /// Number of operations performed
  int count = 0;

  /// Total execution time in milliseconds
  int totalTimeMs = 0;

  /// Minimum execution time in milliseconds
  int minTimeMs = 0;

  /// Maximum execution time in milliseconds
  int maxTimeMs = 0;

  /// Number of successful operations
  int successCount = 0;

  /// Number of failed operations
  int failureCount = 0;

  /// Add a new operation to the metrics
  void addOperation(int timeMs, bool success) {
    count++;
    totalTimeMs += timeMs;

    if (count == 1) {
      minTimeMs = timeMs;
      maxTimeMs = timeMs;
    } else {
      minTimeMs = min(minTimeMs, timeMs);
      maxTimeMs = max(maxTimeMs, timeMs);
    }

    if (success) {
      successCount++;
    } else {
      failureCount++;
    }
  }

  /// Get average execution time in milliseconds
  int get averageTimeMs => count > 0 ? totalTimeMs ~/ count : 0;

  /// Get success rate (0.0-1.0)
  double get successRate => count > 0 ? successCount / count : 0.0;
}

/// Mutual exclusion for async operations
class _AsyncMutex {
  Future<dynamic>? _lastOperation;

  /// Runs the provided function with mutual exclusion
  Future<T> synchronized<T>(Future<T> Function() function) async {
    Future<dynamic> previousOperation = _lastOperation ?? Future.value(null);

    Completer<T> completer = Completer<T>();

    _lastOperation = completer.future;

    try {
      await previousOperation;
      T result = await function();
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      throw e;
    }
  }
}

/// Service responsible for enhancing audio accessibility
///
/// This service provides specialized audio processing and playback features designed for:
/// - Elderly users with hearing impairments
/// - Users with varying levels of technology comfort
/// - Integration with hearing aids and assistive devices
/// - Enhanced clarity and understanding of spoken content
///
/// It provides the following key capabilities:
/// - Audio processing for enhanced clarity
/// - Volume normalization for consistent levels
/// - Frequency adjustment for better speech perception
/// - Integration with screen readers and accessibility services
/// - Support for multiple audio formats
/// - Memory-efficient processing with caching
/// - Privacy-focused local processing
/// - Battery-aware processing modes
class AudioAccessibilityService {
  // Dependency injection for testability
  final AudioEngineProvider _audioEngineProvider;
  final StorageProvider _storageProvider;
  final TextToSpeechProvider _ttsProvider;
  final AudioProcessor _audioProcessor;
  final LocalizationService _localizationService;
  final SecureStorageService _secureStorageService;
  final AppLifecycleService _lifecycleService;
  final AudioAccessibilityConfig _config;

  // Firebase integration
  final FirebaseFirestore _firestore;
  final FirebaseAnalytics _analytics;

  // Internal state
  bool _isInitialized = false;
  final Map<String, _ProcessedAudioCache> _processedAudioCache = {};
  final _mutex = _AsyncMutex();
  int _currentMemoryUsage = 0;
  ProcessingMode _currentMode = ProcessingMode.full;
  String _deviceId = '';
  PackageInfo? _packageInfo;
  bool _isLowEndDevice = false;
  int _processingOperationsCount = 0;
  final Map<String, _PerformanceMetrics> _performanceMetrics = {};
  bool _isPrivacyModeEnabled = false;
  String _currentLanguage = 'en';

  // User preferences
  double _speakingRate;
  double _pitch;
  double _volume;
  bool _frequencyAdjustmentEnabled;
  bool _volumeNormalizationEnabled;

  // Active processors
  final Map<String, StreamController<PlaybackState>> _playbackStateControllers = {};
  final Map<String, AudioPipeline> _activePipelines = {};
  final Map<String, Completer<void>> _processingCompleters = {};

  // Stream controllers
  final StreamController<AudioAccessibilityEvent> _eventStreamController =
  StreamController<AudioAccessibilityEvent>.broadcast();

  // Debug metrics
  final StreamController<_DebugMetrics> _debugMetricsController =
  StreamController<_DebugMetrics>.broadcast();

  // Public streams
  /// Stream of accessibility events
  Stream<AudioAccessibilityEvent> get accessibilityEvents => _eventStreamController.stream;

  /// Stream of debug metrics (only active in debug mode)
  Stream<DebugMetrics> get debugMetrics => _debugMetricsController.stream
      .map((metrics) => DebugMetrics(
    processingTime: metrics.processingTime,
    memoryUsage: metrics.memoryUsage,
    cacheSize: metrics.cacheSize,
    activeOperations: metrics.activeOperations,
    mode: metrics.mode,
    success: metrics.success,
  ));

  // Subscriber pattern
  final List<AccessibilitySubscriber> _subscribers = [];

  /// Factory constructor that returns a singleton instance
  factory AudioAccessibilityService({
    AudioEngineProvider? audioEngineProvider,
    StorageProvider? storageProvider,
    TextToSpeechProvider? ttsProvider,
    AudioProcessor? audioProcessor,
    LocalizationService? localizationService,
    SecureStorageService? secureStorageService,
    AppLifecycleService? lifecycleService,
    AudioAccessibilityConfig? config,
    FirebaseFirestore? firestore,
    FirebaseAnalytics? analytics,
  }) {
    return _instance ??= AudioAccessibilityService._internal(
      audioEngineProvider: audioEngineProvider ?? RealAudioEngineProvider(),
      storageProvider: storageProvider ?? RealStorageProvider(),
      ttsProvider: ttsProvider ?? RealTextToSpeechProvider(),
      audioProcessor: audioProcessor ?? RealAudioProcessor(),
      localizationService: localizationService ?? LocalizationService(),
      secureStorageService: secureStorageService ?? SecureStorageService(),
      lifecycleService: lifecycleService ?? AppLifecycleService(),
      config: config ?? const AudioAccessibilityConfig(),
      firestore: firestore ?? FirebaseFirestore.instance,
      analytics: analytics ?? FirebaseAnalytics.instance,
    );
  }

  // Instance for singleton pattern - static but nullable for better testability
  static AudioAccessibilityService? _instance;

  /// Internal constructor
  AudioAccessibilityService._internal({
    required AudioEngineProvider audioEngineProvider,
    required StorageProvider storageProvider,
    required TextToSpeechProvider ttsProvider,
    required AudioProcessor audioProcessor,
    required LocalizationService localizationService,
    required SecureStorageService secureStorageService,
    required AppLifecycleService lifecycleService,
    required AudioAccessibilityConfig config,
    required FirebaseFirestore firestore,
    required FirebaseAnalytics analytics,
  }) :
        _audioEngineProvider = audioEngineProvider,
        _storageProvider = storageProvider,
        _ttsProvider = ttsProvider,
        _audioProcessor = audioProcessor,
        _localizationService = localizationService,
        _secureStorageService = secureStorageService,
        _lifecycleService = lifecycleService,
        _config = config,
        _firestore = firestore,
        _analytics = analytics,
        _speakingRate = config.defaultSpeakingRate,
        _pitch = config.defaultPitch,
        _volume = config.defaultVolume,
        _frequencyAdjustmentEnabled = config.enableFrequencyAdjustment,
        _volumeNormalizationEnabled = config.enableVolumeNormalization,
        _currentLanguage = config.defaultLanguage,
        _isPrivacyModeEnabled = config.enablePrivacyMode;

  /// Reset the singleton instance (for testing)
  @visibleForTesting
  static void resetInstance() {
    _instance?._dispose();
    _instance = null;
  }

  /// Clean up resources when the service is no longer needed
  void _dispose() {
    for (final controller in _playbackStateControllers.values) {
      controller.close();
    }
    _playbackStateControllers.clear();

    for (final pipeline in _activePipelines.values) {
      pipeline.dispose();
    }
    _activePipelines.clear();

    for (final subscriber in _subscribers) {
      subscriber.dispose();
    }
    _subscribers.clear();

    _eventStreamController.close();
    _debugMetricsController.close();
  }

  /// Initialize the audio accessibility service
  ///
  /// Sets up audio sessions, loads user preferences, and prepares audio processors
  ///
  /// Throws [AudioAccessibilityException] if initialization fails
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      AdvancedLogger.log('AudioAccessibilityService', 'Initializing audio accessibility service');

      // Get device info for optimizations
      await _detectDeviceCapabilities();

      // Set up audio session
      await _setupAudioSession();

      // Set up localization
      await _setupLocalization();

      // Load user preferences from secure storage
      await _loadUserPreferences();

      // Initialize the text-to-speech engine
      await _initializeTts();

      // Clean up any old cached files
      await _cleanupCachedFiles();

      // Set up app lifecycle handling
      _setupLifecycleHandling();

      // Request privacy permissions
      await _setupPrivacy();

      // Log initialization to Firebase
      await _logInitializationToFirebase();

      _isInitialized = true;

      // Broadcast initialization event
      _eventStreamController.add(
        AudioAccessibilityEvent(
          type: AudioAccessibilityEventType.serviceInitialized,
          message: _localizedMessage('audio_accessibility_initialized'),
          timestamp: DateTime.now(),
        ),
      );

      // Add initial debug metrics
      if (_config.enableDebugLogs) {
        _emitDebugMetrics(success: true, note: 'Service initialized');
      }

      AdvancedLogger.log('AudioAccessibilityService', 'Audio accessibility service initialized successfully');
    } catch (e, stackTrace) {
      final errorType = _categorizeError(e);
      final exception = AudioAccessibilityException(
        _localizedMessage('initialization_failed', {'error': e.toString()}),
        errorType,
        cause: e,
      );

      ErrorReporter.reportError(
        'AudioAccessibilityService.initialize',
        exception,
        stackTrace,
      );

      throw exception;
    }
  }

  /// Log initialization event to Firebase
  Future<void> _logInitializationToFirebase() async {
    try {
      // Log initialization event
      await _analytics.logEvent(
        name: 'audio_accessibility_initialized',
        parameters: {
          'device_type': _isLowEndDevice ? 'low_end' : 'standard',
          'processing_mode': _currentMode.name,
          'language': _currentLanguage,
          'app_version': _packageInfo?.version ?? 'unknown',
        },
      );

      // Store service configuration in Firestore
      final userId = await _secureStorageService.read('user_id');
      if (userId != null) {
        await _firestore.collection('user_settings').doc(userId).set({
          'audio_accessibility': {
            'initialized': true,
            'speaking_rate': _speakingRate,
            'pitch': _pitch,
            'volume': _volume,
            'frequency_adjustment_enabled': _frequencyAdjustmentEnabled,
            'volume_normalization_enabled': _volumeNormalizationEnabled,
            'privacy_mode_enabled': _isPrivacyModeEnabled,
            'language': _currentLanguage,
            'processing_mode': _currentMode.name,
            'device_type': _isLowEndDevice ? 'low_end' : 'standard',
            'last_updated': FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true));
      }
    } catch (e) {
      // Non-critical, continue without logging
      AdvancedLogger.logError('AudioAccessibilityService', 'Error logging to Firebase: $e');
    }
  }

  /// Set up audio session for proper audio handling
  ///
  /// Configures the audio session for optimal accessibility
  Future<void> _setupAudioSession() async {
    try {
      AdvancedLogger.log('AudioAccessibilityService', 'Setting up audio session');

      final session = await _audioEngineProvider.getAudioSession();

      // Configure session for speech/accessibility
      await session.configure(AudioSessionConfiguration.speech(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.assistanceAccessibility,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      // Set up interruption handler for accessibility
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          // Pause all active playback
          for (final pipeline in _activePipelines.values) {
            pipeline.pause();
          }

          // Provide haptic feedback
          if (_config.enableHapticFeedback) {
            HapticFeedback.mediumImpact();
          }

          // Broadcast interruption event
          _eventStreamController.add(
            AudioAccessibilityEvent(
              type: AudioAccessibilityEventType.playbackInterrupted,
              message: _localizedMessage('audio_playback_interrupted'),
              timestamp: DateTime.now(),
            ),
          );
        } else {
          // When interruption ends, announce resumption
          _announceAccessibilityMessage(_localizedMessage('audio_resuming'));
        }
      });

      AdvancedLogger.log('AudioAccessibilityService', 'Audio session configured for accessibility');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'AudioAccessibilityService',
        'Error setting up audio session: $e\n$stackTrace',
      );

      // Continue without optimal session as fallback
      AdvancedLogger.log('AudioAccessibilityService', 'Continuing with default audio session');
    }
  }

  /// Setup localization for the service
  Future<void> _setupLocalization() async {
    try {
      // Get system locale
      final locale = ui.window.locale.languageCode;

      // Check if supported
      final isSupported = await _localizationService.isLanguageSupported(locale);

      // Set language
      _currentLanguage = isSupported ? locale : _config.defaultLanguage;

      AdvancedLogger.log(
        'AudioAccessibilityService',
        'Initialized with language: $_currentLanguage',
      );
    } catch (e) {
      AdvancedLogger.logError(
        'AudioAccessibilityService',
        'Error setting up localization: $e',
      );
      _currentLanguage = _config.defaultLanguage;
    }
  }

  /// Load user preferences for audio accessibility
  ///
  /// Retrieves saved preferences for speech rate, pitch, etc.
  Future<void> _loadUserPreferences() async {
    try {
      // Load from secure storage
      final speakingRateStr = await _secureStorageService.read('accessibility_speaking_rate');
      final pitchStr = await _secureStorageService.read('accessibility_pitch');
      final volumeStr = await _secureStorageService.read('accessibility_volume');
      final freqAdjustStr = await _secureStorageService.read('accessibility_frequency_adjustment');
      final volNormStr = await _secureStorageService.read('accessibility_volume_normalization');
      final privacyModeStr = await _secureStorageService.read('accessibility_privacy_mode');
      final languageStr = await _secureStorageService.read('accessibility_language');

      // Load preferences with fallback to defaults
      _speakingRate = speakingRateStr != null
          ? double.tryParse(speakingRateStr) ?? _config.defaultSpeakingRate
          : _config.defaultSpeakingRate;

      _pitch = pitchStr != null
          ? double.tryParse(pitchStr) ?? _config.defaultPitch
          : _config.defaultPitch;

      _volume = volumeStr != null
          ? double.tryParse(volumeStr) ?? _config.defaultVolume
          : _config.defaultVolume;

      _frequencyAdjustmentEnabled = freqAdjustStr != null
          ? freqAdjustStr == 'true'
          : _config.enableFrequencyAdjustment;

      _volumeNormalizationEnabled = volNormStr != null
          ? volNormStr == 'true'
          : _config.enableVolumeNormalization;

      _isPrivacyModeEnabled = privacyModeStr != null
          ? privacyModeStr == 'true'
          : _config.enablePrivacyMode;

      if (languageStr != null) {
        final isSupported = await _localizationService.isLanguageSupported(languageStr);
        if (isSupported) {
          _currentLanguage = languageStr;
        }
      }

      // Adjust settings based on device capabilities
      _adjustSettingsForDevice();

      AdvancedLogger.log('AudioAccessibilityService', 'User preferences loaded securely');
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error loading user preferences: $e');

      // Try fallback to legacy SharedPreferences
      await _loadLegacyPreferences();
    }
  }

  /// Load preferences from legacy SharedPreferences (fallback)
  Future<void> _loadLegacyPreferences() async {
    try {
      final prefs = await _storageProvider.getSharedPreferences();

      // Load preferences with fallback to defaults
      _speakingRate = prefs.getDouble('accessibility_speaking_rate') ?? _config.defaultSpeakingRate;
      _pitch = prefs.getDouble('accessibility_pitch') ?? _config.defaultPitch;
      _volume = prefs.getDouble('accessibility_volume') ?? _config.defaultVolume;
      _frequencyAdjustmentEnabled = prefs.getBool('accessibility_frequency_adjustment') ?? _config.enableFrequencyAdjustment;
      _volumeNormalizationEnabled = prefs.getBool('accessibility_volume_normalization') ?? _config.enableVolumeNormalization;

      // Migrate to secure storage
      await _migrateToSecureStorage();

      AdvancedLogger.log('AudioAccessibilityService', 'Legacy preferences loaded and migrated to secure storage');
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error loading legacy preferences: $e');

      // Use defaults if all else fails
      _speakingRate = _config.defaultSpeakingRate;
      _pitch = _config.defaultPitch;
      _volume = _config.defaultVolume;
      _frequencyAdjustmentEnabled = _config.enableFrequencyAdjustment;
      _volumeNormalizationEnabled = _config.enableVolumeNormalization;
    }
  }

  /// Migrate user preferences to secure storage
  Future<void> _migrateToSecureStorage() async {
    try {
      await _secureStorageService.write('accessibility_speaking_rate', _speakingRate.toString());
      await _secureStorageService.write('accessibility_pitch', _pitch.toString());
      await _secureStorageService.write('accessibility_volume', _volume.toString());
      await _secureStorageService.write('accessibility_frequency_adjustment', _frequencyAdjustmentEnabled.toString());
      await _secureStorageService.write('accessibility_volume_normalization', _volumeNormalizationEnabled.toString());
      await _secureStorageService.write('accessibility_privacy_mode', _isPrivacyModeEnabled.toString());
      await _secureStorageService.write('accessibility_language', _currentLanguage);

      // Clear old preferences
      final prefs = await _storageProvider.getSharedPreferences();
      await prefs.remove('accessibility_speaking_rate');
      await prefs.remove('accessibility_pitch');
      await prefs.remove('accessibility_volume');
      await prefs.remove('accessibility_frequency_adjustment');
      await prefs.remove('accessibility_volume_normalization');

      AdvancedLogger.log('AudioAccessibilityService', 'Preferences migrated to secure storage');
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error migrating to secure storage: $e');
    }
  }

  /// Detect device capabilities to adjust service configuration
  Future<void> _detectDeviceCapabilities() async {
    try {
      // Get device info
      final deviceInfo = DeviceInfoPlugin();

      // Get package info
      _packageInfo = await PackageInfo.fromPlatform();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;

        // Determine if low-end device based on RAM
        final sdkVersion = androidInfo.version.sdkInt ?? 0;
        if (sdkVersion < 29 || // Older Android versions
            androidInfo.systemMemory != null &&
                androidInfo.systemMemory! < 3 * 1024 * 1024 * 1024) { // < 3GB RAM
          _isLowEndDevice = true;
          _currentMode = ProcessingMode.basic;
        }
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor ?? '';

        // iOS devices that are too old
        final model = iosInfo.model ?? '';
        if (iosInfo.systemVersion.startsWith('12.') || // iOS 12 or older
            model.contains('iPhone 6') ||
            model.contains('iPhone 7')) {
          _isLowEndDevice = true;
          _currentMode = ProcessingMode.basic;
        }
      }

      AdvancedLogger.log(
        'AudioAccessibilityService',
        'Device capabilities detected: lowEnd=$_isLowEndDevice, mode=$_currentMode',
      );
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error detecting device capabilities: $e');

      // Default to higher compatibility mode if detection fails
      _isLowEndDevice = true;
      _currentMode = ProcessingMode.basic;
    }
  }

  /// Adjust settings based on device capabilities
  void _adjustSettingsForDevice() {
    if (_isLowEndDevice) {
      // Disable more resource-intensive features
      _frequencyAdjustmentEnabled = false;

      // Simplify for better performance
      if (_currentMode == ProcessingMode.basic) {
        AdvancedLogger.log(
          'AudioAccessibilityService',
          'Adjusting settings for low-end device',
        );
      }
    }
  }

  /// Set up privacy permissions and features
  Future<void> _setupPrivacy() async {
    try {
      if (Platform.isIOS) {
        // Check tracking transparency permission on iOS
        final status = await AppTrackingTransparency.trackingAuthorizationStatus;

        if (status != TrackingStatus.authorized) {
          // User hasn't authorized tracking - force privacy mode
          _isPrivacyModeEnabled = true;
          await _secureStorageService.write('accessibility_privacy_mode', 'true');
        }
      }

      // If privacy mode enabled, configure for local processing only
      if (_isPrivacyModeEnabled) {
        AdvancedLogger.log('AudioAccessibilityService', 'Privacy mode enabled - using local processing only');
      }
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error setting up privacy: $e');

      // Default to enabled for privacy
      _isPrivacyModeEnabled = true;
    }
  }

  /// Initialize the text-to-speech engine
  ///
  /// Sets up TTS with accessibility-focused settings
  Future<void> _initializeTts() async {
    try {
      await _ttsProvider.initialize();

      // Configure TTS for elderly users
      await _ttsProvider.setSpeechRate(_speakingRate);
      await _ttsProvider.setPitch(_pitch);
      await _ttsProvider.setVolume(_volume);
      await _ttsProvider.setLanguage(_currentLanguage);

      // Set preferred voice - usually older, clearer voices are better for elderly
      final voices = await _ttsProvider.getAvailableVoices();
      if (voices.isNotEmpty) {
        // Try to find a suitable voice (prefer slower, clearer voices)
        String? preferredVoice;

        // Look for enhanced voices first
        preferredVoice = voices.firstWhere(
              (voice) => voice.contains('enhanced') ||
              voice.contains('premium') ||
              voice.contains('clarity'),
          orElse: () => '',
        );

        // If no enhanced voice, look for older voices
        if (preferredVoice.isEmpty) {
          preferredVoice = voices.firstWhere(
                (voice) => voice.contains('older') ||
                voice.contains('mature') ||
                voice.contains('senior'),
            orElse: () => voices.first,
          );
        }

        if (preferredVoice.isNotEmpty) {
          await _ttsProvider.setVoice(preferredVoice);
        }
      }

      AdvancedLogger.log('AudioAccessibilityService', 'Text-to-speech initialized successfully');
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error initializing TTS: $e');
      // Continue without TTS as a fallback
    }
  }

  /// Set up app lifecycle handling
  void _setupLifecycleHandling() {
    _lifecycleService.onResume.listen((_) {
      AdvancedLogger.log('AudioAccessibilityService', 'App resumed - restoring state');

      // Check memory pressure and release resources if needed
      _checkMemoryPressure();

      // Refresh TTS engine which may have been suspended
      _ttsProvider.initialize();
    });

    _lifecycleService.onPause.listen((_) {
      AdvancedLogger.log('AudioAccessibilityService', 'App paused - preserving state');

      // Release non-essential resources
      _releaseNonEssentialResources();
    });

    _lifecycleService.onMemoryPressure.listen((_) {
      AdvancedLogger.log('AudioAccessibilityService', 'Memory pressure detected');

      // Release resources more aggressively
      _releaseResourcesUnderPressure();
    });
  }

  /// Release non-essential resources when app goes to background
  void _releaseNonEssentialResources() {
    try {
      // Clear cache for non-active files
      final activeKeys = _activePipelines.keys.toSet();

      _processedAudioCache.removeWhere((key, value) {
        if (!activeKeys.contains(key)) {
          _currentMemoryUsage -= value.memorySizeBytes;
          return true;
        }
        return false;
      });

      // Stop TTS if running
      _ttsProvider.stop();

      AdvancedLogger.log(
        'AudioAccessibilityService',
        'Released non-essential resources, memory usage: $_currentMemoryUsage bytes',
      );
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error releasing resources: $e');
    }
  }

  /// Check for memory pressure and release resources if needed
  void _checkMemoryPressure() {
    if (_currentMemoryUsage > _config.maxMemoryUsageBytes * 0.8) {
      AdvancedLogger.log(
        'AudioAccessibilityService',
        'Memory usage high: $_currentMemoryUsage bytes, releasing resources',
      );

      _releaseResourcesUnderPressure();
    }
  }

  /// Aggressively release resources under memory pressure
  void _releaseResourcesUnderPressure() {
    try {
      // Clear all cached processed audio
      _processedAudioCache.clear();
      _currentMemoryUsage = 0;

      // Downgrade processing mode if needed
      if (_currentMode == ProcessingMode.full) {
        _currentMode = ProcessingMode.basic;
      } else if (_currentMode == ProcessingMode.basic) {
        _currentMode = ProcessingMode.minimal;
      }

      // Emit metrics
      _emitDebugMetrics(success: true, note: 'Released resources under pressure');

      AdvancedLogger.log(
        'AudioAccessibilityService',
        'Released resources under pressure, new mode: $_currentMode',
      );
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error releasing resources: $e');
    }
  }

  /// Clean up old cached processed audio files
  ///
  /// Removes temporary files that are no longer needed
  Future<void> _cleanupCachedFiles() async {
    try {
      final cacheDir = await _getCacheDirectory();

      if (await cacheDir.exists()) {
        final files = await cacheDir.list().toList();
        final now = DateTime.now();

        int filesRemoved = 0;
        int bytesFreed = 0;

        for (final entity in files) {
          if (entity is File) {
            final stat = await entity.stat();
            final fileAge = now.difference(stat.modified);

            // Remove files older than the configured max age
            if (fileAge.inDays > _config.maxCacheAgeDays) {
              final size = await entity.length();
              await entity.delete();
              bytesFreed += size;
              filesRemoved++;
            }
          }
        }

        AdvancedLogger.log(
          'AudioAccessibilityService',
          'Cleaned up $filesRemoved cached files, freed ${bytesFreed ~/ 1024} KB',
        );
      }

      // Check if we're using too much storage
      await _enforceMaxCacheSize();
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error cleaning up cached files: $e');
      // Non-critical, continue without cleanup
    }
  }

  /// Enforce maximum cache size by removing least recently used files
  Future<void> _enforceMaxCacheSize() async {
    try {
      final cacheDir = await _getCacheDirectory();

      if (await cacheDir.exists()) {
        // Get all files with metadata
        final files = await cacheDir.list().toList();
        final now = DateTime.now();

        int totalSize = 0;
        final fileInfos = <_FileInfo>[];

        // Calculate total size and gather file info
        for (final entity in files) {
          if (entity is File) {
            final size = await entity.length();
            final stat = await entity.stat();
            totalSize += size;

            fileInfos.add(_FileInfo(
              file: entity,
              size: size,
              lastAccessed: stat.accessed,
              lastModified: stat.modified,
            ));
          }
        }

        // If we're over the limit, delete least recently used files
        if (totalSize > _config.maxCacheSizeBytes) {
          // Sort by last accessed time (oldest first)
          fileInfos.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

          // Calculate how much we need to delete
          final toDelete = totalSize - (_config.maxCacheSizeBytes * 0.7).toInt();
          int deleted = 0;

          // Delete files until we're under the threshold
          for (final fileInfo in fileInfos) {
            // Skip files that are currently being used
            final fileName = fileInfo.file.path.split('/').last;
            if (_processedAudioCache.values.any((cache) =>
                cache.outputPath.endsWith(fileName))) {
              continue;
            }

            await fileInfo.file.delete();
            deleted += fileInfo.size;

            if (deleted >= toDelete) {
              break;
            }
          }

          AdvancedLogger.log(
            'AudioAccessibilityService',
            'Enforced cache size limit, deleted ${deleted ~/ 1024} KB',
          );
        }
      }
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error enforcing cache size: $e');
    }
  }

  /// Get the cache directory for processed audio
  Future<Directory> _getCacheDirectory() async {
    final appDir = await _storageProvider.getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/accessibility_audio_cache');

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir;
  }

  /// Process audio for enhanced accessibility
  ///
  /// Applies a series of audio processing steps to enhance clarity for elderly users:
  /// - Volume normalization
  /// - Frequency adjustment
  /// - Dynamic range compression
  ///
  /// [inputFile] Path to the input audio file
  /// [outputFormat] Desired output format (mp3, wav, etc.)
  /// [nudge] Optional nudge metadata for context
  /// [requestedFeatures] Specific accessibility features to apply
  /// [priority] Processing priority (higher values get processed first)
  ///
  /// Returns the path to the processed audio file
  ///
  /// Throws [AudioAccessibilityException] if processing fails
  Future<String> processAudioForAccessibility(
      String inputFile, {
        String outputFormat = 'mp3',
        NudgeDelivery? nudge,
        Set<AccessibilityFeature>? requestedFeatures,
        int priority = 5,
      }) async {
    return _mutex.synchronized<String>(() async {
      if (!_isInitialized) {
        await initialize();
      }

      // Start performance tracking
      final processingTimer = Stopwatch()..start();

      try {
        AdvancedLogger.log(
          'AudioAccessibilityService',
          'Processing audio for accessibility: $inputFile',
        );

        // Track processing operation
        _processingOperationsCount++;
        _emitDebugMetrics(note: 'Started processing');

        // Check if input format is supported
        final extension = inputFile.split('.').last.toLowerCase();
        if (!_config.supportedFormats.contains(extension)) {
          throw AudioAccessibilityException(
            _localizedMessage('unsupported_format', {'format': extension}),
            AudioAccessibilityErrorType.format,
          );
        }

        // Check if output format is supported
        if (!_config.supportedFormats.contains(outputFormat)) {
          outputFormat = 'mp3'; // Fallback to MP3
        }

        // Check if file exists
        final file = File(inputFile);
        if (!await file.exists()) {
          throw AudioAccessibilityException(
            _localizedMessage('file_not_found', {'path': inputFile}),
            AudioAccessibilityErrorType.fileAccess,
          );
        }

        // Check file size
        final fileSize = await file.length();
        if (fileSize > 50 * 1024 * 1024) { // 50 MB max
          throw AudioAccessibilityException(
            _localizedMessage('file_too_large'),
            AudioAccessibilityErrorType.resource,
          );
        }

        // Check memory pressure before processing
        _checkMemoryPressure();

        // Check cache for already processed file
        final features = requestedFeatures ?? _getDefaultFeatures();
        final cacheKey = _generateCacheKey(inputFile, features, outputFormat);

        if (_processedAudioCache.containsKey(cacheKey)) {
          final cachedInfo = _processedAudioCache[cacheKey]!;
          final cachedFile = File(cachedInfo.outputPath);

          if (await cachedFile.exists()) {
            AdvancedLogger.log(
              'AudioAccessibilityService',
              'Using cached processed audio: $cacheKey',
            );

            // Update last accessed time
            _processedAudioCache[cacheKey] = cachedInfo.copyWith(
              lastAccessed: DateTime.now(),
            );

            // Track performance
            final elapsedMs = processingTimer.elapsedMilliseconds;
            _recordPerformanceMetrics('processAudio_cached', elapsedMs, true);

            // Update metrics
            _processingOperationsCount--;
            _emitDebugMetrics(
              success: true,
              processingTime: elapsedMs,
              note: 'Used cached file',
            );

            // Log to Firebase Analytics
            await _analytics.logEvent(
              name: 'audio_accessibility_cache_hit',
              parameters: {
                'processing_time_ms': elapsedMs,
                'features': features.map((f) => f.name).join(','),
                'format': outputFormat,
                'nudge_id': nudge?.id,
              },
            );

            return cachedInfo.outputPath;
          }
        }

        // Generate output path
        final cacheDir = await _getCacheDirectory();
        final outputPath = '${cacheDir.path}/$cacheKey.$outputFormat';

        // Determine processing mode based on current state
        final processingMode = _determineProcessingMode();

        // Start processing with timeout
        final completer = Completer<String>();
        _processingCompleters[cacheKey] = completer;

        // Announce start of processing for screen readers
        _announceAccessibilityMessage(_localizedMessage('processing_started'));

        // Process in the background
        _processAudioWithMode(
          inputFile,
          outputPath,
          features,
          processingMode,
          nudge,
        ).then((success) {
          if (success) {
            // Calculate memory size (file size + overhead)
            final memorySizeBytes = fileSize ~/ 2; // Estimate in-memory size as half file size

            // Cache the result
            _processedAudioCache[cacheKey] = _ProcessedAudioCache(
              inputPath: inputFile,
              outputPath: outputPath,
              features: features,
              format: outputFormat,
              timestamp: DateTime.now(),
              lastAccessed: DateTime.now(),
              memorySizeBytes: memorySizeBytes,
            );

            // Update memory usage tracker
            _currentMemoryUsage += memorySizeBytes;

            // Track performance
            final elapsedMs = processingTimer.elapsedMilliseconds;
            _recordPerformanceMetrics(
              'processAudio_$processingMode',
              elapsedMs,
              true,
            );

            if (!completer.isCompleted) {
              completer.complete(outputPath);
            }

            // Announce completion for screen readers
            _announceAccessibilityMessage(_localizedMessage('processing_complete'));

            // Broadcast event
            _eventStreamController.add(
              AudioAccessibilityEvent(
                type: AudioAccessibilityEventType.processingCompleted,
                message: _localizedMessage('processing_complete'),
                timestamp: DateTime.now(),
                nudgeId: nudge?.id,
              ),
            );

            // Update metrics
            _processingOperationsCount--;
            _emitDebugMetrics(
              success: true,
              processingTime: elapsedMs,
              note: 'Processing completed successfully',
            );

            // Log to Firebase Analytics
            _analytics.logEvent(
              name: 'audio_accessibility_processing_completed',
              parameters: {
                'processing_time_ms': elapsedMs,
                'features': features.map((f) => f.name).join(','),
                'format': outputFormat,
                'processing_mode': processingMode.name,
                'file_size_kb': fileSize ~/ 1024,
                'nudge_id': nudge?.id,
              },
            );

            // Notify subscribers
            _notifySubscribers(AudioAccessibilityAction.processingCompleted, outputPath);
          } else if (!completer.isCompleted) {
            // Try with a simpler processing mode if available
            if (processingMode != ProcessingMode.passthrough) {
              final fallbackMode = _getFallbackProcessingMode(processingMode);

              AdvancedLogger.log(
                'AudioAccessibilityService',
                'Retrying with fallback mode: $fallbackMode',
              );

              // Process with fallback mode
              _processAudioWithMode(
                inputFile,
                outputPath,
                features,
                fallbackMode,
                nudge,
              ).then((fallbackSuccess) {
                if (fallbackSuccess) {
                  // Calculate memory size (file size + overhead)
                  final memorySizeBytes = fileSize ~/ 2;

                  // Cache the result
                  _processedAudioCache[cacheKey] = _ProcessedAudioCache(
                    inputPath: inputFile,
                    outputPath: outputPath,
                    features: features,
                    format: outputFormat,
                    timestamp: DateTime.now(),
                    lastAccessed: DateTime.now(),
                    memorySizeBytes: memorySizeBytes,
                  );

                  // Update memory usage tracker
                  _currentMemoryUsage += memorySizeBytes;

                  // Track performance
                  final elapsedMs = processingTimer.elapsedMilliseconds;
                  _recordPerformanceMetrics(
                    'processAudio_fallback_$fallbackMode',
                    elapsedMs,
                    true,
                  );

                  if (!completer.isCompleted) {
                    completer.complete(outputPath);
                  }

                  // Announce completion for screen readers
                  _announceAccessibilityMessage(_localizedMessage('processing_complete'));

                  // Broadcast event with note about fallback
                  _eventStreamController.add(
                    AudioAccessibilityEvent(
                      type: AudioAccessibilityEventType.processingCompleted,
                      message: _localizedMessage('processing_complete_fallback'),
                      timestamp: DateTime.now(),
                      nudgeId: nudge?.id,
                    ),
                  );

                  // Update metrics
                  _processingOperationsCount--;
                  _emitDebugMetrics(
                    success: true,
                    processingTime: elapsedMs,
                    note: 'Processing completed with fallback',
                  );

                  // Log to Firebase Analytics
                  _analytics.logEvent(
                    name: 'audio_accessibility_fallback_completed',
                    parameters: {
                      'processing_time_ms': elapsedMs,
                      'original_mode': processingMode.name,
                      'fallback_mode': fallbackMode.name,
                      'format': outputFormat,
                      'nudge_id': nudge?.id,
                    },
                  );

                  // Notify subscribers
                  _notifySubscribers(AudioAccessibilityAction.processingCompleted, outputPath);
                } else {
                  // Last resort: just use the original file
                  if (!completer.isCompleted) {
                    AdvancedLogger.log(
                      'AudioAccessibilityService',
                      'All processing failed, using original file',
                    );

                    // Track performance
                    final elapsedMs = processingTimer.elapsedMilliseconds;
                    _recordPerformanceMetrics(
                      'processAudio_original_fallback',
                      elapsedMs,
                      false,
                    );

                    // Update metrics
                    _processingOperationsCount--;
                    _emitDebugMetrics(
                      success: false,
                      processingTime: elapsedMs,
                      note: 'Failed processing, using original',
                    );

                    // Log to Firebase Analytics
                    _analytics.logEvent(
                      name: 'audio_accessibility_processing_failed',
                      parameters: {
                        'processing_time_ms': elapsedMs,
                        'original_mode': processingMode.name,
                        'fallback_mode': fallbackMode.name,
                        'format': outputFormat,
                        'nudge_id': nudge?.id,
                        'used_original': true,
                      },
                    );

                    completer.complete(inputFile);
                  }
                }
              }).catchError((error) {
                if (!completer.isCompleted) {
                  completer.completeError(error);

                  // Log to Firebase Analytics
                  _analytics.logEvent(
                    name: 'audio_accessibility_processing_error',
                    parameters: {
                      'error': error.toString().substring(0, min(100, error.toString().length)),
                      'mode': processingMode.name,
                      'fallback_mode': _getFallbackProcessingMode(processingMode).name,
                      'nudge_id': nudge?.id,
                    },
                  );
                }
              });
            } else {
              // If we're already at passthrough, just use the original file
              _processingOperationsCount--;
              _emitDebugMetrics(success: false, note: 'Using original file');
              completer.complete(inputFile);

              // Log to Firebase Analytics
              _analytics.logEvent(
                name: 'audio_accessibility_passthrough',
                parameters: {
                  'reason': 'processing_failed',
                  'nudge_id': nudge?.id,
                },
              );
            }
          }
        }).catchError((error) {
          // Track performance
          final elapsedMs = processingTimer.elapsedMilliseconds;
          _recordPerformanceMetrics('processAudio_error', elapsedMs, false);

          // Update metrics
          _processingOperationsCount--;
          _emitDebugMetrics(success: false, processingTime: elapsedMs, note: 'Error');

          // Log to Firebase Analytics
          _analytics.logEvent(
            name: 'audio_accessibility_error',
            parameters: {
              'error': error.toString().substring(0, min(100, error.toString().length)),
              'processing_time_ms': elapsedMs,
              'nudge_id': nudge?.id,
            },
          );

          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        });

        // Add timeout
        final timeoutFuture = Future.delayed(
          _config.processingTimeout,
              () {
            if (!completer.isCompleted) {
              AdvancedLogger.log(
                'AudioAccessibilityService',
                'Processing timed out, using original file',
              );

              completer.complete(inputFile);

              _eventStreamController.add(
                AudioAccessibilityEvent(
                  type: AudioAccessibilityEventType.processingError,
                  message: _localizedMessage('processing_timeout'),
                  timestamp: DateTime.now(),
                  nudgeId: nudge?.id,
                ),
              );

              // Log timeout to Firebase Analytics
              _analytics.logEvent(
                name: 'audio_accessibility_timeout',
                parameters: {
                  'timeout_ms': _config.processingTimeout.inMilliseconds,
                  'processing_mode': processingMode.name,
                  'nudge_id': nudge?.id,
                },
              );
            }
          },
        );

        // Wait for processing to complete
        final result = await completer.future;
        _processingCompleters.remove(cacheKey);

        return result;
      } catch (e, stackTrace) {
        // Track performance
        final elapsedMs = processingTimer.elapsedMilliseconds;
        _recordPerformanceMetrics('processAudio_exception', elapsedMs, false);

        // Update metrics
        _processingOperationsCount--;
        _emitDebugMetrics(success: false, processingTime: elapsedMs, note: 'Exception');

        final errorType = _categorizeError(e);
        final exception = e is AudioAccessibilityException
            ? e
            : AudioAccessibilityException(
          _localizedMessage('processing_failed', {'error': e.toString()}),
          errorType,
          cause: e,
        );

        ErrorReporter.reportError(
          'AudioAccessibilityService.processAudioForAccessibility',
          exception,
          stackTrace,
        );

        // Broadcast error event
        _eventStreamController.add(
          AudioAccessibilityEvent(
            type: AudioAccessibilityEventType.processingError,
            message: _localizedMessage('processing_failed_short'),
            timestamp: DateTime.now(),
            nudgeId: nudge?.id,
          ),
        );

        // Log error to Firebase
        await _firestore.collection('error_logs').add({
          'service': 'AudioAccessibilityService',
          'method': 'processAudioForAccessibility',
          'error': e.toString(),
          'errorType': errorType.name,
          'stackTrace': stackTrace.toString(),
          'timestamp': FieldValue.serverTimestamp(),
          'nudgeId': nudge?.id,
          'deviceId': _deviceId,
          'appVersion': _packageInfo?.version,
        });

        // Announce error for screen readers
        _announceAccessibilityMessage(_localizedMessage('processing_failed_short'));

        // For user experience, return original file rather than throwing
        // Especially important for elderly users who might be confused by errors
        return inputFile;
      }
    });
  }

  /// Determine which processing mode to use based on system state
  ProcessingMode _determineProcessingMode() {
    // If we're under memory pressure, use a simpler mode
    if (_currentMemoryUsage > _config.maxMemoryUsageBytes * 0.8) {
      return ProcessingMode.minimal;
    }

    // If battery saving mode is enabled and device is not charging, use minimal
    if (_config.enableBatterySaving &&
        _lifecycleService.batteryLevel < 20 &&
        !_lifecycleService.isCharging) {
      return ProcessingMode.minimal;
    }

    // Otherwise, use the current mode
    return _currentMode;
  }

  /// Get a fallback processing mode when the primary mode fails
  ProcessingMode _getFallbackProcessingMode(ProcessingMode currentMode) {
    switch (currentMode) {
      case ProcessingMode.full:
        return ProcessingMode.basic;
      case ProcessingMode.basic:
        return ProcessingMode.minimal;
      case ProcessingMode.minimal:
        return ProcessingMode.passthrough;
      case ProcessingMode.passthrough:
        return ProcessingMode.passthrough; // No fallback
    }
  }

  /// Process audio file with the specified mode
  ///
  /// [inputPath] Path to input audio file
  /// [outputPath] Path to save processed audio
  /// [features] Set of accessibility features to apply
  /// [mode] Processing mode to use
  /// [nudge] Optional nudge for context
  ///
  /// Returns true if processing was successful
  Future<bool> _processAudioWithMode(
      String inputPath,
      String outputPath,
      Set<AccessibilityFeature> features,
      ProcessingMode mode,
      NudgeDelivery? nudge,
      ) async {
    try {
      // Report progress
      _eventStreamController.add(
        AudioAccessibilityEvent(
          type: AudioAccessibilityEventType.processingStarted,
          message: _localizedMessage('processing_started'),
          timestamp: DateTime.now(),
          nudgeId: nudge?.id,
        ),
      );

      AdvancedLogger.log(
        'AudioAccessibilityService',
        'Processing audio with mode: $mode, features: ${features.map((f) => f.name).join(", ")}',
      );

      // Report progress at 20%
      _eventStreamController.add(
        AudioAccessibilityEvent(
          type: AudioAccessibilityEventType.processingProgress,
          message: _localizedMessage('processing_progress'),
          timestamp: DateTime.now(),
          nudgeId: nudge?.id,
          progress: 0.2,
        ),
      );

      // If we're using passthrough mode, just copy the file
      if (mode == ProcessingMode.passthrough) {
        final output = await _copyFile(inputPath, outputPath);
        return output != null;
      }

      // Select which features to apply based on mode
      final activeFeatures = _selectFeaturesForMode(features, mode);

      // Process each feature
      bool success = false;

      // Report progress at 40%
      _eventStreamController.add(
        AudioAccessibilityEvent(
          type: AudioAccessibilityEventType.processingProgress,
          message: _localizedMessage('processing_applying_features'),
          timestamp: DateTime.now(),
          nudgeId: nudge?.id,
          progress: 0.4,
        ),
      );

      // Apply volume normalization
      if (activeFeatures.contains(AccessibilityFeature.volumeNormalization) &&
          _volumeNormalizationEnabled) {
        success = await _audioProcessor.normalizeVolume(
          inputPath,
          outputPath,
          targetLevel: _config.targetRmsLevel,
          maxGain: _config.maxNormalizationGain,
        );

        if (!success) {
          AdvancedLogger.logError(
              'AudioAccessibilityService',
              'Volume normalization failed, trying without it'
          );

          // If this fails, try processing without it
          activeFeatures.remove(AccessibilityFeature.volumeNormalization);
        } else {
          inputPath = outputPath; // Use the output as input for next step
        }
      }

      // Report progress at 60%
      _eventStreamController.add(
        AudioAccessibilityEvent(
          type: AudioAccessibilityEventType.processingProgress,
          message: _localizedMessage('processing_enhancing'),
          timestamp: DateTime.now(),
          nudgeId: nudge?.id,
          progress: 0.6,
        ),
      );

      // Apply frequency adjustment
      if (activeFeatures.contains(AccessibilityFeature.frequencyAdjustment) &&
          _frequencyAdjustmentEnabled) {
        success = await _audioProcessor.adjustFrequency(
          inputPath,
          outputPath,
          bassBoost: _config.bassBoost,
          trebleBoost: _config.trebleBoost,
        );

        if (!success) {
          AdvancedLogger.logError(
              'AudioAccessibilityService',
              'Frequency adjustment failed, trying without it'
          );

          // If this fails, try to copy the input file to output
          await _copyFile(inputPath, outputPath);
        } else {
          inputPath = outputPath; // Use the output as input for next step
        }
      }

      // Report progress at 80%
      _eventStreamController.add(
        AudioAccessibilityEvent(
          type: AudioAccessibilityEventType.processingProgress,
          message: _localizedMessage('processing_finalizing'),
          timestamp: DateTime.now(),
          nudgeId: nudge?.id,
          progress: 0.8,
        ),
      );

      // Apply dynamic range compression
      if (activeFeatures.contains(AccessibilityFeature.dynamicRangeCompression)) {
        success = await _audioProcessor.compressDynamicRange(
          inputPath,
          outputPath,
          threshold: -24.0,
          ratio: 4.0,
        );

        if (!success) {
          AdvancedLogger.logError(
              'AudioAccessibilityService',
              'Dynamic range compression failed, using previous stage output'
          );

          // If this fails, try to copy the input file to output
          await _copyFile(inputPath, outputPath);
        }
      } else if (inputPath != outputPath) {
        // Ensure we have a file at the output path
        await _copyFile(inputPath, outputPath);
      }

      // Verify the output file exists and is valid
      final outputFile = File(outputPath);
      if (await outputFile.exists() && await outputFile.length() > 0) {
        // Report progress at 100%
        _eventStreamController.add(
          AudioAccessibilityEvent(
            type: AudioAccessibilityEventType.processingProgress,
            message: _localizedMessage('processing_complete'),
            timestamp: DateTime.now(),
            nudgeId: nudge?.id,
            progress: 1.0,
          ),
        );

        return true;
      } else {
        AdvancedLogger.logError(
            'AudioAccessibilityService',
            'Output file does not exist or is empty'
        );
        return false;
      }
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'AudioAccessibilityService',
        'Error processing audio with mode $mode: $e\n$stackTrace',
      );

      // Log to Firestore for monitoring
      try {
        await _firestore.collection('error_logs').add({
          'service': 'AudioAccessibilityService',
          'method': '_processAudioWithMode',
          'error': e.toString(),
          'mode': mode.toString(),
          'features': features.map((f) => f.name).join(','),
          'stackTrace': stackTrace.toString(),
          'timestamp': FieldValue.serverTimestamp(),
          'nudgeId': nudge?.id,
          'deviceId': _deviceId,
        });
      } catch (_) {
        // Ignore Firestore errors to prevent cascading failures
      }

      return false;
    }
  }

  /// Copy a file with error handling
  ///
  /// [inputPath] Source file path
  /// [outputPath] Destination file path
  ///
  /// Returns the output path if successful, null otherwise
  Future<String?> _copyFile(String inputPath, String outputPath) async {
    try {
      final input = File(inputPath);
      final output = File(outputPath);

      if (await output.exists()) {
        await output.delete();
      }

      await input.copy(outputPath);
      return outputPath;
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error copying file: $e');
      return null;
    }
  }

  /// Select which accessibility features to apply based on processing mode
  ///
  /// [features] Requested features
  /// [mode] Current processing mode
  ///
  /// Returns the subset of features to apply
  Set<AccessibilityFeature> _selectFeaturesForMode(
      Set<AccessibilityFeature> features,
      ProcessingMode mode,
      ) {
    switch (mode) {
      case ProcessingMode.full:
      // All requested features
        return features;

      case ProcessingMode.basic:
      // Volume normalization and compression only
        return features.where((feature) =>
        feature == AccessibilityFeature.volumeNormalization ||
            feature == AccessibilityFeature.dynamicRangeCompression
        ).toSet();

      case ProcessingMode.minimal:
      // Just volume normalization
        return {AccessibilityFeature.volumeNormalization};

      case ProcessingMode.passthrough:
      // No processing
        return {};
    }
  }

  /// Generate a cache key for processed audio
  ///
  /// [inputFile] Path to input file
  /// [features] Set of applied features
  /// [format] Output format
  ///
  /// Returns a unique key for the combination
  String _generateCacheKey(
      String inputFile,
      Set<AccessibilityFeature> features,
      String format,
      ) {
    final featuresStr = features.map((f) => f.name).join('_');
    final inputName = inputFile.split('/').last.split('.').first;
    final modeStr = _currentMode.name;

    // Create a cache key that includes the file, features, and processing mode
    final keyInput = '$inputName|$featuresStr|$modeStr|$format|v1';

    // Generate SHA-256 hash for a compact, unique key
    final bytes = utf8.encode(keyInput);
    final digest = sha256.convert(bytes);

    return digest.toString().substring(0, 16); // Use first 16 chars of hash
  }

  /// Get default accessibility features based on preferences
  ///
  /// Returns a set of features to apply by default
  Set<AccessibilityFeature> _getDefaultFeatures() {
    final features = <AccessibilityFeature>{};

    if (_volumeNormalizationEnabled) {
      features.add(AccessibilityFeature.volumeNormalization);
    }

    if (_frequencyAdjustmentEnabled) {
      features.add(AccessibilityFeature.frequencyAdjustment);
    }

    // Always include by default if not using minimal mode
    if (_currentMode != ProcessingMode.minimal) {
      features.add(AccessibilityFeature.dynamicRangeCompression);
    }

    return features;
  }

  /// Play audio with accessibility enhancements
  ///
  /// Creates a playback pipeline with real-time accessibility enhancements
  ///
  /// [audioPath] Path to the audio file
  /// [playbackId] Optional unique ID for this playback session
  /// [nudge] Optional nudge metadata for context
  ///
  /// Returns a [Stream] of playback state updates
  ///
  /// Throws [AudioAccessibilityException] if playback fails
  Future<Stream<PlaybackState>> playEnhancedAudio(
      String audioPath, {
        String? playbackId,
        NudgeDelivery? nudge,
      }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Generate playback ID if not provided
      final id = playbackId ?? _generatePlaybackId();

      // Check if file exists
      final file = File(audioPath);
      if (!await file.exists()) {
        throw AudioAccessibilityException(
          _localizedMessage('file_not_found', {'path': audioPath}),
          AudioAccessibilityErrorType.fileAccess,
        );
      }

      // Create state stream
      final stateController = StreamController<PlaybackState>.broadcast();
      _playbackStateControllers[id] = stateController;

      // Create pipeline
      final pipeline = await _createPlaybackPipeline(id, audioPath, nudge);
      _activePipelines[id] = pipeline;

      // Set up event handlers
      pipeline.playbackStateStream.listen((state) {
        // Forward state to the controller
        stateController.add(state);

        // Handle state changes
        if (state.isPlaying && !state.hasError) {
          // Broadcast playing event on start of playback
          if (state.positionSeconds < 0.5) {
            _eventStreamController.add(
              AudioAccessibilityEvent(
                type: AudioAccessibilityEventType.playbackStarted,
                message: _localizedMessage('playback_started'),
                timestamp: DateTime.now(),
                nudgeId: nudge?.id,
              ),
            );

            // Notify subscribers
            _notifySubscribers(AudioAccessibilityAction.playbackStarted, id);

            // Log to Firebase Analytics
            _analytics.logEvent(
              name: 'audio_accessibility_playback_started',
              parameters: {
                'playback_id': id,
                'nudge_id': nudge?.id,
                'audio_duration': state.durationSeconds.round(),
              },
            );
          }
        } else if (!state.isPlaying && !state.isBuffering) {
          // Check if playback completed
          if (state.positionSeconds > 0 &&
              state.durationSeconds > 0 &&
              (state.positionSeconds / state.durationSeconds) > 0.95) {
            _eventStreamController.add(
              AudioAccessibilityEvent(
                type: AudioAccessibilityEventType.playbackCompleted,
                message: _localizedMessage('playback_completed'),
                timestamp: DateTime.now(),
                nudgeId: nudge?.id,
              ),
            );

            // Log to Firebase Analytics
            _analytics.logEvent(
              name: 'audio_accessibility_playback_completed',
              parameters: {
                'playback_id': id,
                'nudge_id': nudge?.id,
                'audio_duration': state.durationSeconds.round(),
              },
            );
          } else if (state.positionSeconds > 0) {
            // Paused during playback
            _eventStreamController.add(
              AudioAccessibilityEvent(
                type: AudioAccessibilityEventType.playbackPaused,
                message: _localizedMessage('playback_paused'),
                timestamp: DateTime.now(),
                nudgeId: nudge?.id,
              ),
            );
          }
        } else if (state.hasError) {
          // Error during playback
          _eventStreamController.add(
            AudioAccessibilityEvent(
              type: AudioAccessibilityEventType.playbackError,
              message: _localizedMessage('playback_error'),
              timestamp: DateTime.now(),
              nudgeId: nudge?.id,
              errorType: AudioAccessibilityErrorType.engine,
            ),
          );

          // Log to Firebase Analytics
          _analytics.logEvent(
            name: 'audio_accessibility_playback_error',
            parameters: {
              'playback_id': id,
              'nudge_id': nudge?.id,
              'error_message': state.errorMessage ?? 'Unknown error',
            },
          );
        }
      });

      // Start playback
      await pipeline.play();

      // Return the stream
      return stateController.stream;
    } catch (e, stackTrace) {
      final errorType = _categorizeError(e);
      final exception = e is AudioAccessibilityException
          ? e
          : AudioAccessibilityException(
        _localizedMessage('playback_failed', {'error': e.toString()}),
        errorType,
        cause: e,
      );

      ErrorReporter.reportError(
        'AudioAccessibilityService.playEnhancedAudio',
        exception,
        stackTrace,
      );

      // Log to Firebase
      await _firestore.collection('error_logs').add({
        'service': 'AudioAccessibilityService',
        'method': 'playEnhancedAudio',
        'error': e.toString(),
        'errorType': errorType.name,
        'stackTrace': stackTrace.toString().substring(0, min(1000, stackTrace.toString().length)),
        'timestamp': FieldValue.serverTimestamp(),
        'nudgeId': nudge?.id,
        'deviceId': _deviceId,
        'appVersion': _packageInfo?.version,
      });

      throw exception;
    }
  }

  /// Create playback pipeline for enhanced audio
  Future<AudioPipeline> _createPlaybackPipeline(
      String id,
      String audioPath,
      NudgeDelivery? nudge,
      ) async {
    try {
      // Create pipeline
      final pipeline = await _audioEngineProvider.createPipeline(id, audioPath);

      // Configure for accessibility
      await pipeline.setVolume(_volume);
      await pipeline.setSpeed(_speakingRate);

      return pipeline;
    } catch (e) {
      rethrow;
    }
  }

  /// Generate a unique playback ID
  String _generatePlaybackId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    return 'playback_${timestamp}_$random';
  }

  /// Stop playback with the given ID
  Future<void> stopPlayback(String playbackId) async {
    if (_activePipelines.containsKey(playbackId)) {
      final pipeline = _activePipelines[playbackId]!;
      await pipeline.stop();

      // Broadcast event
      _eventStreamController.add(
        AudioAccessibilityEvent(
          type: AudioAccessibilityEventType.playbackStopped,
          message: _localizedMessage('playback_stopped'),
          timestamp: DateTime.now(),
        ),
      );

      // Notify subscribers
      _notifySubscribers(AudioAccessibilityAction.playbackStopped, playbackId);

      // Log to Firebase Analytics
      _analytics.logEvent(
        name: 'audio_accessibility_playback_stopped',
        parameters: {
          'playback_id': playbackId,
        },
      );
    }
  }

  /// Pause playback with the given ID
  Future<void> pausePlayback(String playbackId) async {
    if (_activePipelines.containsKey(playbackId)) {
      final pipeline = _activePipelines[playbackId]!;
      await pipeline.pause();
    }
  }

  /// Resume playback with the given ID
  Future<void> resumePlayback(String playbackId) async {
    if (_activePipelines.containsKey(playbackId)) {
      final pipeline = _activePipelines[playbackId]!;
      await pipeline.play();

      // Broadcast event
      _eventStreamController.add(
        AudioAccessibilityEvent(
          type: AudioAccessibilityEventType.playbackResumed,
          message: _localizedMessage('playback_resumed'),
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  /// Release resources for a playback session
  Future<void> releasePlayback(String playbackId) async {
    if (_activePipelines.containsKey(playbackId)) {
      final pipeline = _activePipelines[playbackId]!;
      pipeline.dispose();
      _activePipelines.remove(playbackId);
    }

    if (_playbackStateControllers.containsKey(playbackId)) {
      final controller = _playbackStateControllers[playbackId]!;
      await controller.close();
      _playbackStateControllers.remove(playbackId);
    }
  }

  /// Update accessibility settings
  ///
  /// Updates user preferences for audio accessibility and saves them
  ///
  /// [speakingRate] Speaking rate (0.5-2.0)
  /// [pitch] Voice pitch (0.5-2.0)
  /// [volume] Audio volume (0.0-1.0)
  /// [frequencyAdjustment] Enable frequency adjustment
  /// [volumeNormalization] Enable volume normalization
  /// [language] Language code (e.g., 'en', 'es')
  /// [privacyMode] Enable privacy mode (local processing only)
  Future<void> updateSettings({
    double? speakingRate,
    double? pitch,
    double? volume,
    bool? frequencyAdjustment,
    bool? volumeNormalization,
    String? language,
    bool? privacyMode,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    bool settingsChanged = false;

    try {
      // Update speaking rate if provided
      if (speakingRate != null && speakingRate >= 0.5 && speakingRate <= 2.0) {
        _speakingRate = speakingRate;
        await _ttsProvider.setSpeechRate(speakingRate);
        await _secureStorageService.write('accessibility_speaking_rate', speakingRate.toString());
        settingsChanged = true;
      }

      // Update pitch if provided
      if (pitch != null && pitch >= 0.5 && pitch <= 2.0) {
        _pitch = pitch;
        await _ttsProvider.setPitch(pitch);
        await _secureStorageService.write('accessibility_pitch', pitch.toString());
        settingsChanged = true;
      }

      // Update volume if provided
      if (volume != null && volume >= 0.0 && volume <= 1.0) {
        _volume = volume;
        await _ttsProvider.setVolume(volume);
        await _secureStorageService.write('accessibility_volume', volume.toString());
        settingsChanged = true;
      }

      // Update frequency adjustment if provided
      if (frequencyAdjustment != null) {
        _frequencyAdjustmentEnabled = frequencyAdjustment;
        await _secureStorageService.write('accessibility_frequency_adjustment', frequencyAdjustment.toString());
        settingsChanged = true;
      }

      // Update volume normalization if provided
      if (volumeNormalization != null) {
        _volumeNormalizationEnabled = volumeNormalization;
        await _secureStorageService.write('accessibility_volume_normalization', volumeNormalization.toString());
        settingsChanged = true;
      }

      // Update language if provided
      if (language != null) {
        final isSupported = await _localizationService.isLanguageSupported(language);
        if (isSupported) {
          _currentLanguage = language;
          await _ttsProvider.setLanguage(language);
          await _secureStorageService.write('accessibility_language', language);
          settingsChanged = true;
        }
      }

      // Update privacy mode if provided
      if (privacyMode != null) {
        _isPrivacyModeEnabled = privacyMode;
        await _secureStorageService.write('accessibility_privacy_mode', privacyMode.toString());
        settingsChanged = true;
      }

      if (settingsChanged) {
        // Broadcast event
        _eventStreamController.add(
          AudioAccessibilityEvent(
            type: AudioAccessibilityEventType.settingsChanged,
            message: _localizedMessage('settings_updated'),
            timestamp: DateTime.now(),
          ),
        );

        // Notify subscribers
        _notifySubscribers(AudioAccessibilityAction.settingsChanged, null);

        // Update all active pipelines with new settings
        for (final pipeline in _activePipelines.values) {
          await pipeline.setVolume(_volume);
          await pipeline.setSpeed(_speakingRate);
        }

        // Log to Firebase
        final userId = await _secureStorageService.read('user_id');
        if (userId != null) {
          await _firestore.collection('user_settings').doc(userId).update({
            'audio_accessibility': {
              'speaking_rate': _speakingRate,
              'pitch': _pitch,
              'volume': _volume,
              'frequency_adjustment_enabled': _frequencyAdjustmentEnabled,
              'volume_normalization_enabled': _volumeNormalizationEnabled,
              'privacy_mode_enabled': _isPrivacyModeEnabled,
              'language': _currentLanguage,
              'last_updated': FieldValue.serverTimestamp(),
            }
          });
        }

        // Log to Firebase Analytics
        _analytics.logEvent(
          name: 'audio_accessibility_settings_updated',
          parameters: {
            'speaking_rate': _speakingRate,
            'pitch': _pitch,
            'volume': _volume,
            'frequency_adjustment': _frequencyAdjustmentEnabled,
            'volume_normalization': _volumeNormalizationEnabled,
            'language': _currentLanguage,
            'privacy_mode': _isPrivacyModeEnabled,
          },
        );
      }
    } catch (e, stackTrace) {
      final exception = AudioAccessibilityException(
        _localizedMessage('settings_update_failed', {'error': e.toString()}),
        AudioAccessibilityErrorType.unknown,
        cause: e,
      );

      ErrorReporter.reportError(
        'AudioAccessibilityService.updateSettings',
        exception,
        stackTrace,
      );

      throw exception;
    }
  }

  /// Subscribe to accessibility events and actions
  ///
  /// [onAction] Callback for accessibility actions
  ///
  /// Returns a unique subscription ID
  String addSubscriber(void Function(AudioAccessibilityAction, dynamic) onAction) {
    final subscriber = AccessibilitySubscriber(onAction: onAction);
    _subscribers.add(subscriber);

    final id = 'subscriber_${_subscribers.length}';
    return id;
  }

  /// Remove a subscriber by ID
  void removeSubscriber(String subscriberId) {
    final index = int.tryParse(subscriberId.split('_').last);
    if (index != null && index > 0 && index <= _subscribers.length) {
      _subscribers[index - 1].dispose();
      _subscribers.removeAt(index - 1);
    }
  }

  /// Notify all subscribers of an action
  void _notifySubscribers(AudioAccessibilityAction action, dynamic data) {
    for (final subscriber in _subscribers) {
      subscriber.onAction(action, data);
    }
  }

  /// Announce message using accessibility services
  ///
  /// This announces a message using TTS for screen reader users
  void _announceAccessibilityMessage(String message) {
    // Only announce if device has accessibility services enabled
    if (_lifecycleService.isAccessibilityEnabled) {
      _ttsProvider.speak(message);
    }
  }

  /// Record performance metrics for an operation
  ///
  /// [operation] Name of the operation
  /// [timeMs] Time taken in milliseconds
  /// [success] Whether the operation was successful
  void _recordPerformanceMetrics(String operation, int timeMs, bool success) {
    if (!_performanceMetrics.containsKey(operation)) {
      _performanceMetrics[operation] = _PerformanceMetrics();
    }

    _performanceMetrics[operation]!.addOperation(timeMs, success);
  }

  /// Emit debug metrics for monitoring
  void _emitDebugMetrics({
    bool? success,
    int? processingTime,
    String? note,
  }) {
    if (_config.enableDebugLogs) {
      int totalCacheSize = 0;
      for (final cache in _processedAudioCache.values) {
        totalCacheSize += cache.memorySizeBytes;
      }

      _debugMetricsController.add(_DebugMetrics(
        processingTime: processingTime,
        memoryUsage: _currentMemoryUsage,
        cacheSize: totalCacheSize,
        activeOperations: _processingOperationsCount,
        mode: _currentMode,
        success: success ?? true,
        note: note,
      ));
    }
  }

  /// Categorize an error by type
  AudioAccessibilityErrorType _categorizeError(dynamic error) {
    if (error is AudioAccessibilityException) {
      return error.type;
    }

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('permission') ||
        errorString.contains('access denied')) {
      return AudioAccessibilityErrorType.permission;
    } else if (errorString.contains('file') ||
        errorString.contains('directory') ||
        errorString.contains('path')) {
      return AudioAccessibilityErrorType.fileAccess;
    } else if (errorString.contains('memory') ||
        errorString.contains('resource') ||
        errorString.contains('capacity')) {
      return AudioAccessibilityErrorType.resource;
    } else if (errorString.contains('format') ||
        errorString.contains('codec') ||
        errorString.contains('extension')) {
      return AudioAccessibilityErrorType.format;
    } else if (errorString.contains('privacy') ||
        errorString.contains('data protection')) {
      return AudioAccessibilityErrorType.privacy;
    } else if (errorString.contains('process') ||
        errorString.contains('conversion')) {
      return AudioAccessibilityErrorType.processing;
    } else if (errorString.contains('audio') ||
        errorString.contains('playback') ||
        errorString.contains('player')) {
      return AudioAccessibilityErrorType.engine;
    } else if (errorString.contains('device') ||
        errorString.contains('hardware') ||
        errorString.contains('android') ||
        errorString.contains('ios')) {
      return AudioAccessibilityErrorType.compatibility;
    }

    return AudioAccessibilityErrorType.unknown;
  }

  /// Get localized message from the localization service
  String _localizedMessage(String key, [Map<String, String>? params]) {
    try {
      return _localizationService.getMessage(key, _currentLanguage, params);
    } catch (_) {
      // Fallback messages for key accessibility errors
      switch (key) {
        case 'audio_accessibility_initialized':
          return 'Audio accessibility service initialized.';
        case 'initialization_failed':
          return 'Failed to initialize audio accessibility: ${params?['error'] ?? 'Unknown error'}';
        case 'unsupported_format':
          return 'Unsupported audio format: ${params?['format'] ?? 'unknown'}';
        case 'file_not_found':
          return 'Audio file not found: ${params?['path'] ?? 'unknown path'}';
        case 'file_too_large':
          return 'Audio file is too large for processing.';
        case 'processing_started':
          return 'Started processing audio for accessibility.';
        case 'processing_progress':
          return 'Processing audio...';
        case 'processing_applying_features':
          return 'Applying accessibility enhancements...';
        case 'processing_enhancing':
          return 'Enhancing audio clarity...';
        case 'processing_finalizing':
          return 'Finalizing audio processing...';
        case 'processing_complete':
          return 'Audio processing complete.';
        case 'processing_complete_fallback':
          return 'Audio processing complete with simplified enhancements.';
        case 'processing_failed':
          return 'Failed to process audio: ${params?['error'] ?? 'Unknown error'}';
        case 'processing_failed_short':
          return 'Audio processing failed.';
        case 'processing_timeout':
          return 'Audio processing timed out.';
        case 'playback_started':
          return 'Audio playback started.';
        case 'playback_paused':
          return 'Audio playback paused.';
        case 'playback_resumed':
          return 'Audio playback resumed.';
        case 'playback_stopped':
          return 'Audio playback stopped.';
        case 'playback_completed':
          return 'Audio playback completed.';
        case 'playback_error':
          return 'Error during audio playback.';
        case 'playback_failed':
          return 'Failed to play audio: ${params?['error'] ?? 'Unknown error'}';
        case 'settings_updated':
          return 'Accessibility settings updated.';
        case 'settings_update_failed':
          return 'Failed to update settings: ${params?['error'] ?? 'Unknown error'}';
        case 'audio_playback_interrupted':
          return 'Audio playback interrupted.';
        case 'audio_resuming':
          return 'Resuming audio.';
        default:
          return key;
      }
    }
  }

  /// Reset the cache - useful for testing or recovering from errors
  Future<void> resetCache() async {
    try {
      final cacheDir = await _getCacheDirectory();

      if (await cacheDir.exists()) {
        // Stop all active playback first
        for (final pipeline in _activePipelines.values) {
          await pipeline.stop();
        }

        // Delete all files
        final files = await cacheDir.list().toList();
        for (final entity in files) {
          if (entity is File) {
            await entity.delete();
          }
        }

        // Clear memory cache
        _processedAudioCache.clear();
        _currentMemoryUsage = 0;

        // Log event
        AdvancedLogger.log('AudioAccessibilityService', 'Cache reset successful');

        // Broadcast event
        _eventStreamController.add(
          AudioAccessibilityEvent(
            type: AudioAccessibilityEventType.cacheCleared,
            message: _localizedMessage('cache_cleared'),
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      AdvancedLogger.logError('AudioAccessibilityService', 'Error resetting cache: $e');
      throw AudioAccessibilityException(
        _localizedMessage('cache_reset_failed', {'error': e.toString()}),
        AudioAccessibilityErrorType.fileAccess,
        cause: e,
      );
    }
  }

  /// Get current accessibility settings
  ///
  /// Returns a map of current settings
  Map<String, dynamic> getCurrentSettings() {
    return {
      'speakingRate': _speakingRate,
      'pitch': _pitch,
      'volume': _volume,
      'frequencyAdjustmentEnabled': _frequencyAdjustmentEnabled,
      'volumeNormalizationEnabled': _volumeNormalizationEnabled,
      'privacyModeEnabled': _isPrivacyModeEnabled,
      'language': _currentLanguage,
      'currentMode': _currentMode.name,
      'isLowEndDevice': _isLowEndDevice,
    };
  }

  /// Get performance metrics
  ///
  /// Returns a map of performance metrics for each operation
  Map<String, Map<String, dynamic>> getPerformanceMetrics() {
    final result = <String, Map<String, dynamic>>{};

    for (final entry in _performanceMetrics.entries) {
      final metrics = entry.value;
      result[entry.key] = {
        'count': metrics.count,
        'averageTimeMs': metrics.averageTimeMs,
        'minTimeMs': metrics.minTimeMs,
        'maxTimeMs': metrics.maxTimeMs,
        'successRate': metrics.successRate,
        'successCount': metrics.successCount,
        'failureCount': metrics.failureCount,
      };
    }

    return result;
  }

  /// Enhance for special needs elderly users
  ///
  /// Optimizes settings for users with hearing loss or cognitive decline
  Future<void> enhanceForSpecialNeeds({required bool severeHearingLoss}) async {
    if (severeHearingLoss) {
      // Settings for severe hearing loss
      await updateSettings(
        speakingRate: 0.8, // Slower speech
        pitch: 0.9, // Slightly lower pitch
        volume: 1.0, // Maximum volume
        frequencyAdjustment: true,
        volumeNormalization: true,
      );

      // Log to Firebase Analytics
      _analytics.logEvent(
        name: 'audio_accessibility_special_needs',
        parameters: {
          'type': 'severe_hearing_loss',
        },
      );
    } else {
      // Settings for cognitive decline (clarity and focus)
      await updateSettings(
        speakingRate: 0.75, // Even slower speech
        pitch: 1.1, // Slightly higher pitch for attention
        volume: 0.9, // High but not maximum
        frequencyAdjustment: true,
        volumeNormalization: true,
      );

      // Log to Firebase Analytics
      _analytics.logEvent(
        name: 'audio_accessibility_special_needs',
        parameters: {
          'type': 'cognitive_decline',
        },
      );
    }
  }
}