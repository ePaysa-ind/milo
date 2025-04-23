// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/services/audio_player_service.dart
// Version: 1.0.0
// Last Updated: April 22, 2025
// Description: Service for specialized playback of nudge audio files with optimizations for elderly users (55+)
// Change History:
// - 1.0.0: Initial implementation with core features and elderly-focused optimizations

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';

import '../models/nudge_model.dart';
import '../utils/advanced_logger.dart';
import '../utils/error_reporter.dart';
import '../theme/app_theme.dart';
import '../services/audio_accessibility_service.dart';
import '../services/audio_caching_service.dart';

/// Error types for audio player operations
enum AudioPlayerErrorType {
  /// File access errors
  fileAccess,

  /// Audio decoding issues
  decoding,

  /// Playback problems
  playback,

  /// Connectivity issues
  connectivity,

  /// Battery-related problems
  battery,

  /// Permission issues
  permission,

  /// Device limitations
  deviceLimit,

  /// Generic errors
  unknown
}

/// Configuration for the audio player service
///
/// This allows dynamic adjustments to the player behavior without code changes
class AudioPlayerConfig {
  /// Default volume level (0.0 - 1.0)
  final double defaultVolume;

  /// Default playback speed (0.5 - 2.0)
  final double defaultSpeed;

  /// Whether to automatically enable accessibility features
  final bool autoEnableAccessibility;

  /// Whether to cache audio files by default
  final bool cacheAudioByDefault;

  /// Whether to optimize for low battery situations
  final bool optimizeForBattery;

  /// Low battery threshold percentage
  final int lowBatteryThreshold;

  /// Battery critical threshold percentage
  final int criticalBatteryThreshold;

  /// Whether to reduce quality when battery is low
  final bool reduceBatteryUsage;

  /// Whether to enable offline mode automatically
  final bool autoOfflineMode;

  /// Auto-decrease volume level for evening hours
  final bool autoAdjustVolumeForTimeOfDay;

  /// Maximum retry attempts for playback
  final int maxRetryAttempts;

  /// Timeout for initialization of player
  final Duration initTimeout;

  /// Timeout for loading audio
  final Duration loadTimeout;

  /// Buffer size in milliseconds
  final int bufferSizeMs;

  /// Whether to normalize volume levels between different nudges
  final bool normalizeVolume;

  /// Target loudness level for normalization in dB
  final double targetLoudnessDb;

  const AudioPlayerConfig({
    this.defaultVolume = 0.8, // Higher default for elderly users
    this.defaultSpeed = 0.9, // Slightly slower for better comprehension
    this.autoEnableAccessibility = true,
    this.cacheAudioByDefault = true,
    this.optimizeForBattery = true,
    this.lowBatteryThreshold = 20,
    this.criticalBatteryThreshold = 10,
    this.reduceBatteryUsage = true,
    this.autoOfflineMode = true,
    this.autoAdjustVolumeForTimeOfDay = true,
    this.maxRetryAttempts = 3,
    this.initTimeout = const Duration(seconds: 10),
    this.loadTimeout = const Duration(seconds: 30),
    this.bufferSizeMs = 2000, // Higher buffer for more stable playback
    this.normalizeVolume = true,
    this.targetLoudnessDb = -16.0,
  });

  /// Create config for low-end devices
  factory AudioPlayerConfig.lowEndDevice() {
    return const AudioPlayerConfig(
      bufferSizeMs: 3000, // Larger buffer
      defaultSpeed: 0.95, // Almost normal speed
      autoEnableAccessibility: true,
      reduceBatteryUsage: true,
      maxRetryAttempts: 2,
    );
  }

  /// Create config for battery saving mode
  factory AudioPlayerConfig.batterySaving() {
    return const AudioPlayerConfig(
      defaultVolume: 0.7,
      optimizeForBattery: true,
      reduceBatteryUsage: true,
      autoOfflineMode: true,
      bufferSizeMs: 1000, // Smaller buffer to save memory
      normalizeVolume: false, // Skip normalization to save battery
    );
  }
}

/// Current state of the player
enum AudioPlayerState {
  /// Player is initializing
  initializing,

  /// Player is ready but no audio is loaded
  idle,

  /// Audio is loading
  loading,

  /// Audio is ready to play
  ready,

  /// Audio is playing
  playing,

  /// Audio is paused
  paused,

  /// Audio playback is completed
  completed,

  /// Player is stopped
  stopped,

  /// An error occurred
  error
}

/// Source of the audio
enum AudioSource {
  /// Audio from network URL
  network,

  /// Audio from local file system
  file,

  /// Audio from assets
  asset,

  /// Unknown source
  unknown
}

/// Detailed playback status
class PlaybackStatus {
  /// Current state of the player
  final AudioPlayerState state;

  /// Current position in milliseconds
  final int positionMs;

  /// Total duration in milliseconds
  final int durationMs;

  /// Current volume (0.0 - 1.0)
  final double volume;

  /// Current playback speed (0.5 - 2.0)
  final double speed;

  /// Whether audio is buffering
  final bool buffering;

  /// Buffer position in milliseconds
  final int bufferPositionMs;

  /// Source of the audio
  final AudioSource source;

  /// File path or URL
  final String? path;

  /// Associated nudge metadata
  final NudgeDelivery? nudge;

  /// Error message if applicable
  final String? errorMessage;

  /// Error type if applicable
  final AudioPlayerErrorType? errorType;

  /// Whether offline mode is active
  final bool offlineMode;

  /// Battery level percentage
  final int batteryLevel;

  /// Whether device is charging
  final bool isCharging;

  /// Whether volume normalization is active
  final bool volumeNormalized;

  PlaybackStatus({
    required this.state,
    this.positionMs = 0,
    this.durationMs = 0,
    this.volume = 0.8,
    this.speed = 1.0,
    this.buffering = false,
    this.bufferPositionMs = 0,
    this.source = AudioSource.unknown,
    this.path,
    this.nudge,
    this.errorMessage,
    this.errorType,
    this.offlineMode = false,
    this.batteryLevel = 100,
    this.isCharging = false,
    this.volumeNormalized = false,
  });

  /// Create a copy with updated fields
  PlaybackStatus copyWith({
    AudioPlayerState? state,
    int? positionMs,
    int? durationMs,
    double? volume,
    double? speed,
    bool? buffering,
    int? bufferPositionMs,
    AudioSource? source,
    String? path,
    NudgeDelivery? nudge,
    String? errorMessage,
    AudioPlayerErrorType? errorType,
    bool? offlineMode,
    int? batteryLevel,
    bool? isCharging,
    bool? volumeNormalized,
  }) {
    return PlaybackStatus(
      state: state ?? this.state,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      buffering: buffering ?? this.buffering,
      bufferPositionMs: bufferPositionMs ?? this.bufferPositionMs,
      source: source ?? this.source,
      path: path ?? this.path,
      nudge: nudge ?? this.nudge,
      errorMessage: errorMessage ?? this.errorMessage,
      errorType: errorType ?? this.errorType,
      offlineMode: offlineMode ?? this.offlineMode,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      volumeNormalized: volumeNormalized ?? this.volumeNormalized,
    );
  }

  /// Calculate progress percentage (0.0 - 1.0)
  double get progress {
    if (durationMs <= 0) return 0.0;
    return positionMs / durationMs;
  }

  /// Convert position to human-readable string
  String get positionString {
    final duration = Duration(milliseconds: positionMs);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Convert duration to human-readable string
  String get durationString {
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Return a human-readable status message
  String get statusMessage {
    switch (state) {
      case AudioPlayerState.initializing:
        return 'Getting ready';
      case AudioPlayerState.idle:
        return 'Ready to play';
      case AudioPlayerState.loading:
        return 'Loading audio';
      case AudioPlayerState.ready:
        return 'Ready to start';
      case AudioPlayerState.playing:
        return 'Playing';
      case AudioPlayerState.paused:
        return 'Paused';
      case AudioPlayerState.completed:
        return 'Finished playing';
      case AudioPlayerState.stopped:
        return 'Stopped';
      case AudioPlayerState.error:
        return 'Error: ${errorMessage ?? 'Unknown error'}';
    }
  }

  /// Return a user-friendly error message
  String get friendlyErrorMessage {
    if (state != AudioPlayerState.error || errorMessage == null) {
      return 'No error';
    }

    switch (errorType) {
      case AudioPlayerErrorType.fileAccess:
        return 'Could not access the audio file. Please try again.';
      case AudioPlayerErrorType.decoding:
        return 'There was a problem with the audio format. Please try another audio.';
      case AudioPlayerErrorType.playback:
        return 'Could not play the audio. Please try again.';
      case AudioPlayerErrorType.connectivity:
        return 'Internet connection issue. Using saved audio when possible.';
      case AudioPlayerErrorType.battery:
        return 'Battery is low. Consider charging your device.';
      case AudioPlayerErrorType.permission:
        return 'Missing permission to access audio. Please check app settings.';
      case AudioPlayerErrorType.deviceLimit:
        return 'Your device cannot play this audio. Please try a different audio.';
      case AudioPlayerErrorType.unknown:
      default:
        return 'Something went wrong with the audio player. Please try again.';
    }
  }
}

/// Exception for audio player errors
class AudioPlayerException implements Exception {
  /// Error message
  final String message;

  /// Type of error
  final AudioPlayerErrorType type;

  /// Original cause
  final dynamic cause;

  AudioPlayerException(this.message, this.type, {this.cause});

  @override
  String toString() => 'AudioPlayerException: $message';
}

/// Information about a player event
class PlayerEvent {
  /// Type of event
  final String eventType;

  /// Message describing the event
  final String message;

  /// When the event occurred
  final DateTime timestamp;

  /// Additional data related to the event
  final Map<String, dynamic>? data;

  PlayerEvent({
    required this.eventType,
    required this.message,
    required this.timestamp,
    this.data,
  });
}

/// Simplified battery state used by player
enum BatteryState {
  /// Battery is at a normal level
  normal,

  /// Battery is low
  low,

  /// Battery is critical
  critical,

  /// Device is charging
  charging,

  /// Battery state unknown
  unknown
}

/// Interface for audio accessibility services
abstract class AudioAccessibilityProvider {
  Future<void> initialize();
  Future<String> processAudioForAccessibility(String inputFile);
  Future<Stream<PlaybackState>> playEnhancedAudio(String audioPath, {String? playbackId, NudgeDelivery? nudge});
  Future<void> stopPlayback(String playbackId);
  Future<void> pausePlayback(String playbackId);
  Future<void> resumePlayback(String playbackId);
  Future<void> releasePlayback(String playbackId);
  Future<void> updateSettings({double? speakingRate, double? volume});
}

/// Real implementation of AudioAccessibilityProvider
class RealAudioAccessibilityProvider implements AudioAccessibilityProvider {
  final AudioAccessibilityService _service;

  RealAudioAccessibilityProvider(this._service);

  @override
  Future<void> initialize() => _service.initialize();

  @override
  Future<String> processAudioForAccessibility(String inputFile) {
    return _service.processAudioForAccessibility(inputFile);
  }

  @override
  Future<Stream<PlaybackState>> playEnhancedAudio(String audioPath, {String? playbackId, NudgeDelivery? nudge}) {
    return _service.playEnhancedAudio(audioPath, playbackId: playbackId, nudge: nudge);
  }

  @override
  Future<void> stopPlayback(String playbackId) => _service.stopPlayback(playbackId);

  @override
  Future<void> pausePlayback(String playbackId) => _service.pausePlayback(playbackId);

  @override
  Future<void> resumePlayback(String playbackId) => _service.resumePlayback(playbackId);

  @override
  Future<void> releasePlayback(String playbackId) => _service.releasePlayback(playbackId);

  @override
  Future<void> updateSettings({double? speakingRate, double? volume}) {
    return _service.updateSettings(speakingRate: speakingRate, volume: volume);
  }
}

/// Interface for audio caching services
abstract class AudioCachingProvider {
  Future<void> initialize();
  Future<File?> getCachedFile(String url, {bool highPriority, NudgeDelivery? nudge, bool forceRefresh});
  Future<Stream<DownloadProgress>?> prefetchFile(String url, {NudgeDelivery? nudge, int importance});
  Future<void> waitForPriorityDownloads({Duration timeout});
}

/// Real implementation of AudioCachingProvider
class RealAudioCachingProvider implements AudioCachingProvider {
  final AudioCachingService _service;

  RealAudioCachingProvider(this._service);

  @override
  Future<void> initialize() => _service.initialize();

  @override
  Future<File?> getCachedFile(String url, {bool highPriority = false, NudgeDelivery? nudge, bool forceRefresh = false}) {
    return _service.getCachedFile(
        url,
        highPriority: highPriority,
        nudge: nudge,
        forceRefresh: forceRefresh
    );
  }

  @override
  Future<Stream<DownloadProgress>?> prefetchFile(String url, {NudgeDelivery? nudge, int importance = 5}) {
    return _service.prefetchFile(url, nudge: nudge, importance: importance);
  }

  @override
  Future<void> waitForPriorityDownloads({Duration timeout = const Duration(seconds: 30)}) {
    return _service.waitForPriorityDownloads(timeout: timeout);
  }
}

/// Interface for storage services
abstract class StorageProvider {
  Future<Directory> getApplicationDocumentsDirectory();
  Future<SharedPreferences> getSharedPreferences();
  Future<String?> secureRead(String key);
  Future<void> secureWrite(String key, String value);
}

/// Real implementation of StorageProvider
class RealStorageProvider implements StorageProvider {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  Future<Directory> getApplicationDocumentsDirectory() {
    return getApplicationDocumentsDirectory();
  }

  @override
  Future<SharedPreferences> getSharedPreferences() {
    return SharedPreferences.getInstance();
  }

  @override
  Future<String?> secureRead(String key) {
    return _secureStorage.read(key: key);
  }

  @override
  Future<void> secureWrite(String key, String value) {
    return _secureStorage.write(key: key, value: value);
  }
}

/// Interface for battery services
abstract class BatteryProvider {
  Future<int> get batteryLevel;
  Future<bool> get isCharging;
  Stream<int> get onBatteryLevelChanged;
  Stream<bool> get onChargingStatusChanged;
  BatteryState getBatteryState(int level, bool isCharging, AudioPlayerConfig config);
}

/// Real implementation of BatteryProvider
class RealBatteryProvider implements BatteryProvider {
  final Battery _battery = Battery();

  @override
  Future<int> get batteryLevel => _battery.batteryLevel;

  @override
  Future<bool> get isCharging async {
    final state = await _battery.batteryState;
    return state == BatteryState.charging || state == BatteryState.full;
  }

  @override
  Stream<int> get onBatteryLevelChanged {
    return Stream.periodic(const Duration(minutes: 2))
        .asyncMap((_) => _battery.batteryLevel);
  }

  @override
  Stream<bool> get onChargingStatusChanged {
    return _battery.onBatteryStateChanged.map(
          (state) => state == BatteryState.charging || state == BatteryState.full,
    );
  }

  @override
  BatteryState getBatteryState(int level, bool isCharging, AudioPlayerConfig config) {
    if (isCharging) {
      return BatteryState.charging;
    }

    if (level <= config.criticalBatteryThreshold) {
      return BatteryState.critical;
    } else if (level <= config.lowBatteryThreshold) {
      return BatteryState.low;
    } else {
      return BatteryState.normal;
    }
  }
}

/// Interface for connectivity services
abstract class ConnectivityProvider {
  Future<ConnectivityResult> checkConnectivity();
  Stream<ConnectivityResult> get onConnectivityChanged;
  bool isOffline(ConnectivityResult result);
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

  @override
  bool isOffline(ConnectivityResult result) {
    return result == ConnectivityResult.none;
  }
}

/// Utility class to handle mutual exclusion for async operations
class _AsyncMutex {
  Completer<void>? _completer;

  Future<T> synchronized<T>(Future<T> Function() fn) async {
    // Wait for any ongoing operation
    while (_completer != null) {
      await _completer!.future;
    }

    // Create a new completer
    _completer = Completer<void>();

    try {
      // Execute the operation
      final result = await fn();
      return result;
    } finally {
      // Complete the completer to allow the next operation
      final completer = _completer;
      _completer = null;
      completer!.complete();
    }
  }
}

/// Service responsible for playing audio with optimizations for elderly users
///
/// This service specializes in playing audio nudges with features designed for:
/// - Elderly users with potential hearing impairments
/// - Simple, intuitive playback controls with error recovery
/// - Battery and connectivity awareness
/// - Volume normalization between different nudges
/// - Integration with accessibility and caching services
class AudioPlayerService {
  // Dependencies
  final AudioAccessibilityProvider _accessibilityProvider;
  final AudioCachingProvider _cachingProvider;
  final StorageProvider _storageProvider;
  final BatteryProvider _batteryProvider;
  final ConnectivityProvider _connectivityProvider;
  final AudioPlayerConfig _config;
  final Logger _logger;

  // Internal state
  bool _isInitialized = false;
  final AudioPlayer _player = AudioPlayer();
  final Map<String, Stream<PlaybackState>> _enhancedPlaybacks = {};
  final Map<String, StreamSubscription> _enhancedPlaybackSubscriptions = {};
  String? _currentEnhancedPlaybackId;
  final _mutex = _AsyncMutex();

  // Status tracking
  final BehaviorSubject<PlaybackStatus> _statusSubject = BehaviorSubject<PlaybackStatus>();
  StreamSubscription? _playerPositionSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _batteryLevelSubscription;
  StreamSubscription? _chargingStatusSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _positionUpdateTimer;

  // Resource tracking
  bool _useAccessibilityService = true;
  bool _useEnhancedPlayback = true;
  bool _offlineMode = false;
  int _batteryLevel = 100;
  bool _isCharging = true;
  ConnectivityResult _connectivityResult = ConnectivityResult.wifi;

  // User settings
  double _volume;
  double _speed;
  bool _volumeNormalization;

  // Event stream
  final StreamController<PlayerEvent> _eventStreamController =
  StreamController<PlayerEvent>.broadcast();

  // Public API
  /// Stream of playback status updates
  Stream<PlaybackStatus> get status => _statusSubject.stream;

  /// Current playback status
  PlaybackStatus get currentStatus => _statusSubject.value;

  /// Stream of player events
  Stream<PlayerEvent> get events => _eventStreamController.stream;

  /// Whether the player is currently playing
  bool get isPlaying => currentStatus.state == AudioPlayerState.playing;

  /// Whether the player is in offline mode
  bool get isOfflineMode => _offlineMode;

  /// Factory constructor that returns a singleton instance
  factory AudioPlayerService({
    AudioAccessibilityProvider? accessibilityProvider,
    AudioCachingProvider? cachingProvider,
    StorageProvider? storageProvider,
    BatteryProvider? batteryProvider,
    ConnectivityProvider? connectivityProvider,
    AudioPlayerConfig? config,
    Logger? logger,
  }) {
    return _instance ??= AudioPlayerService._internal(
      accessibilityProvider: accessibilityProvider ??
          RealAudioAccessibilityProvider(AudioAccessibilityService()),
      cachingProvider: cachingProvider ??
          RealAudioCachingProvider(AudioCachingService()),
      storageProvider: storageProvider ?? RealStorageProvider(),
      batteryProvider: batteryProvider ?? RealBatteryProvider(),
      connectivityProvider: connectivityProvider ?? RealConnectivityProvider(),
      config: config ?? const AudioPlayerConfig(),
      logger: logger ?? Logger(),
    );
  }

  // Instance for singleton pattern
  static AudioPlayerService? _instance;

  /// Internal constructor
  AudioPlayerService._internal({
    required AudioAccessibilityProvider accessibilityProvider,
    required AudioCachingProvider cachingProvider,
    required StorageProvider storageProvider,
    required BatteryProvider batteryProvider,
    required ConnectivityProvider connectivityProvider,
    required AudioPlayerConfig config,
    required Logger logger,
  }) :
        _accessibilityProvider = accessibilityProvider,
        _cachingProvider = cachingProvider,
        _storageProvider = storageProvider,
        _batteryProvider = batteryProvider,
        _connectivityProvider = connectivityProvider,
        _config = config,
        _logger = logger,
        _volume = config.defaultVolume,
        _speed = config.defaultSpeed,
        _volumeNormalization = config.normalizeVolume {
    _statusSubject.add(PlaybackStatus(
      state: AudioPlayerState.initializing,
      volume: config.defaultVolume,
      speed: config.defaultSpeed,
      volumeNormalized: config.normalizeVolume,
    ));
  }

  /// Reset the singleton instance (for testing)
  @visibleForTesting
  static void resetInstance() {
    _instance?._dispose();
    _instance = null;
  }

  /// Clean up resources
  void _dispose() {
    _player.dispose();
    _positionUpdateTimer?.cancel();
    _playerPositionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _batteryLevelSubscription?.cancel();
    _chargingStatusSubscription?.cancel();
    _connectivitySubscription?.cancel();

    for (final subscription in _enhancedPlaybackSubscriptions.values) {
      subscription.cancel();
    }
    _enhancedPlaybackSubscriptions.clear();
    _enhancedPlaybacks.clear();

    _statusSubject.close();
    _eventStreamController.close();

    _isInitialized = false;
  }

  /// Initialize the audio player service
  ///
  /// Sets up audio session, loads user preferences, and prepares player
  ///
  /// Returns a Future that completes when initialization is done
  Future<void> initialize() async {
    return _mutex.synchronized(() async {
      if (_isInitialized) return;

      try {
        _logger.i('Initializing AudioPlayerService');

        // Update status
        _updateStatus(state: AudioPlayerState.initializing);

        // Set up audio session
        await _setupAudioSession();

        // Load user preferences
        await _loadUserPreferences();

        // Initialize services
        if (_useAccessibilityService) {
          await _accessibilityProvider.initialize();
        }
        await _cachingProvider.initialize();

        // Set up device monitoring
        await _setupDeviceMonitoring();

        // Set up player event listeners
        _setupPlayerListeners();

        // Update service status
        _isInitialized = true;
        _updateStatus(state: AudioPlayerState.idle);

        // Log initialization event
        _logEvent(
          eventType: 'initialization_complete',
          message: 'AudioPlayerService initialized successfully',
        );

        _logger.i('AudioPlayerService initialized successfully');
      } catch (e, stackTrace) {
        _logger.e('Failed to initialize AudioPlayerService', e, stackTrace);

        final errorType = _categorizeError(e);
        final exception = AudioPlayerException(
          'Failed to initialize audio player: ${e.toString()}',
          errorType,
          cause: e,
        );

        // Report error
        ErrorReporter.reportError(
          'AudioPlayerService.initialize',
          exception,
          stackTrace,
        );

        // Update status to error
        _updateStatus(
          state: AudioPlayerState.error,
          errorMessage: exception.message,
          errorType: errorType,
        );

        // Log error event
        _logEvent(
          eventType: 'initialization_error',
          message: 'Failed to initialize: ${e.toString()}',
          data: {'errorType': errorType.toString()},
        );

        throw exception;
      }
    });
  }

  /// Set up audio session for playback
  Future<void> _setupAudioSession() async {
    try {
      // Get the audio session
      final session = await AudioSession.instance;

      // Configure for speech playback (optimize for spoken content)
      await session.configure(AudioSessionConfiguration.speech(
        // For Android
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
        // For iOS
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      ));

      // Listen for audio interruptions (phone calls, etc.)
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          // Audio was interrupted
          if (isPlaying) {
            // Automatically pause playback
            pause();

            // Log interruption event
            _logEvent(
              eventType: 'audio_interrupted',
              message: 'Audio playback interrupted',
              data: {'type': event.type.toString()},
            );
          }
        } else {
          // Interruption ended
          if (event.type == AudioInterruptionType.duck) {
            // Resume normal volume if we were just ducked
            _player.setVolume(_volume);
          }
          // Note: We don't auto-resume as that could be confusing for elderly users

          // Log interruption ended event
          _logEvent(
            eventType: 'audio_interruption_ended',
            message: 'Audio interruption ended',
            data: {'type': event.type.toString()},
          );
        }
      });

      _logger.i('Audio session configured successfully');
    } catch (e, stackTrace) {
      _logger.e('Error setting up audio session', e, stackTrace);
      // Continue without optimal audio session as fallback

      // Log error but don't fail initialization
      _logEvent(
        eventType: 'audio_session_error',
        message: 'Failed to configure audio session: ${e.toString()}',
      );
    }
  }

  /// Load user preferences for playback
  Future<void> _loadUserPreferences() async {
    try {
      // Try to load from secure storage first
      final volumeStr = await _storageProvider.secureRead('audio_player_volume');
      final speedStr = await _storageProvider.secureRead('audio_player_speed');
      final normalizeStr = await _storageProvider.secureRead('audio_player_normalize');
      final accessibilityStr = await _storageProvider.secureRead('audio_player_accessibility');

      // Apply settings with fallbacks to defaults
      _volume = volumeStr != null ? double.tryParse(volumeStr) ?? _config.defaultVolume : _config.defaultVolume;
      _speed = speedStr != null ? double.tryParse(speedStr) ?? _config.defaultSpeed : _config.defaultSpeed;
      _volumeNormalization = normalizeStr != null ? normalizeStr == 'true' : _config.normalizeVolume;
      _useAccessibilityService = accessibilityStr != null ? accessibilityStr == 'true' : _config.autoEnableAccessibility;

      // Apply settings to player
      await _player.setVolume(_volume);
      await _player.setSpeed(_speed);

      // Check if we're in a low battery situation
      final batteryLevel = await _batteryProvider.batteryLevel;
      final isCharging = await _batteryProvider.isCharging;

      if (_config.optimizeForBattery &&
          batteryLevel <= _config.lowBatteryThreshold &&
          !isCharging) {
        // Adjust for low battery
        _useEnhancedPlayback = false;

        // Log battery saving mode
        _logEvent(
          eventType: 'battery_saving_mode',
          message: 'Entered battery saving mode due to low battery',
          data: {'batteryLevel': batteryLevel, 'isCharging': isCharging},
        );
      }

      // Check connectivity
      final connectivity = await _connectivityProvider.checkConnectivity();
      _offlineMode = _connectivityProvider.isOffline(connectivity);

      if (_offlineMode && _config.autoOfflineMode) {
        // Log offline mode
        _logEvent(
          eventType: 'offline_mode',
          message: 'Entered offline mode due to no connectivity',
        );
      }

      _logger.i('User preferences loaded: volume=$_volume, speed=$_speed, normalize=$_volumeNormalization');
    } catch (e) {
      _logger.e('Error loading user preferences', e);

      // Continue with defaults
      _volume = _config.defaultVolume;
      _speed = _config.defaultSpeed;
      _volumeNormalization = _config.normalizeVolume;

      // Log error but don't fail initialization
      _logEvent(
        eventType: 'preferences_error',
        message: 'Failed to load preferences: ${e.toString()}',
      );
    }
  }

  /// Set up monitoring for device state (battery, connectivity)
  Future<void> _setupDeviceMonitoring() async {
    try {
      // Get initial battery level
      _batteryLevel = await _batteryProvider.batteryLevel;
      _isCharging = await _batteryProvider.isCharging;

      // Subscribe to battery level changes
      _batteryLevelSubscription = _batteryProvider.onBatteryLevelChanged.listen((level) {
        _batteryLevel = level;
        _updateStatus(batteryLevel: level);

        // Check if we need to adjust playback based on battery level
        _handleBatteryChange(level, _isCharging);
      });

      // Subscribe to charging status changes
      _chargingStatusSubscription = _batteryProvider.onChargingStatusChanged.listen((charging) {
        _isCharging = charging;
        _updateStatus(isCharging: charging);

        // Check if we need to adjust playback based on charging status
        _handleBatteryChange(_batteryLevel, charging);
      });

      // Get initial connectivity status
      _connectivityResult = await _connectivityProvider.checkConnectivity();
      _offlineMode = _connectivityProvider.isOffline(_connectivityResult);

      // Subscribe to connectivity changes
      _connectivitySubscription = _connectivityProvider.onConnectivityChanged.listen((result) {
        _connectivityResult = result;
        final wasOffline = _offlineMode;
        _offlineMode = _connectivityProvider.isOffline(result);

        // Update status
        _updateStatus(offlineMode: _offlineMode);

        // Log connectivity change
        if (wasOffline != _offlineMode) {
          _logEvent(
            eventType: _offlineMode ? 'offline_mode' : 'online_mode',
            message: _offlineMode
                ? 'Device went offline'
                : 'Device is back online',
            data: {'connectivityResult': result.toString()},
          );

          // If we're back online, maybe adjust enhanced playback
          if (!_offlineMode && !_useEnhancedPlayback && _config.autoEnableAccessibility) {
            _useEnhancedPlayback = true;
          }
        }
      });

      _logger.i('Device monitoring set up successfully');
    } catch (e) {
      _logger.e('Error setting up device monitoring', e);

      // Continue without monitoring as fallback
      _logEvent(
        eventType: 'monitoring_error',
        message: 'Failed to set up device monitoring: ${e.toString()}',
      );
    }
  }

  /// Set up listeners for player events
  void _setupPlayerListeners() {
    // Listen for playback status changes
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      AudioPlayerState newState;

      // Convert just_audio state to our state
      switch (state.processingState) {
        case ProcessingState.idle:
          newState = AudioPlayerState.idle;
          break;
        case ProcessingState.loading:
          newState = AudioPlayerState.loading;
          break;
        case ProcessingState.buffering:
        // Keep current state but update buffering flag
          newState = _statusSubject.value.state;
          _updateStatus(buffering: true);
          return;
        case ProcessingState.ready:
          newState = state.playing ? AudioPlayerState.playing : AudioPlayerState.ready;
          break;
        case ProcessingState.completed:
          newState = AudioPlayerState.completed;

          // Log completion
          _logEvent(
            eventType: 'playback_completed',
            message: 'Audio playback completed naturally',
            data: {
              'path': _statusSubject.value.path,
              'nudgeId': _statusSubject.value.nudge?.id,
            },
          );
          break;
        default:
          newState = AudioPlayerState.error;
          break;
      }

      // Update state
      _updateStatus(
        state: newState,
        buffering: state.processingState == ProcessingState.buffering,
      );

      // Handle position timer based on playing state
      if (state.playing) {
        _startPositionTimer();
      } else {
        _stopPositionTimer();
      }
    });

    // Listen for player errors
    _player.playbackEventStream.listen((event) {
      // No action needed for normal events
    }, onError: (error) {
      // Handle player errors
      _handlePlayerError(error);
    });

    // Get duration when available
    _player.durationStream.listen((duration) {
      if (duration != null) {
        _updateStatus(durationMs: duration.inMilliseconds);
      }
    });

    // Get buffered position
    _player.bufferedPositionStream.listen((position) {
      _updateStatus(bufferPositionMs: position.inMilliseconds);
    });

    _logger.i('Player listeners set up successfully');
  }

  /// Handle changes in battery level
  void _handleBatteryChange(int level, bool charging) {
    if (!_config.optimizeForBattery) return;

    // Get battery state
    final batteryState = _batteryProvider.getBatteryState(level, charging, _config);

    // Take actions based on battery state
    switch (batteryState) {
      case BatteryState.normal:
      // If previously in battery saving mode, maybe restore features
        if (!_useEnhancedPlayback && _config.autoEnableAccessibility) {
          _useEnhancedPlayback = true;

          // Log event
          _logEvent(
            eventType: 'battery_normal',
            message: 'Restored normal playback features',
            data: {'batteryLevel': level, 'isCharging': charging},
          );
        }
        break;

      case BatteryState.low:
        if (_config.reduceBatteryUsage && _useEnhancedPlayback) {
          // Reduce features to save battery
          _useEnhancedPlayback = false;

          // Log event
          _logEvent(
            eventType: 'battery_low',
            message: 'Reduced features due to low battery',
            data: {'batteryLevel': level, 'isCharging': charging},
          );
        }
        break;

      case BatteryState.critical:
      // Aggressively reduce features
        _useEnhancedPlayback = false;
        _volumeNormalization = false;

        // Log event
        _logEvent(
          eventType: 'battery_critical',
          message: 'Disabled enhanced features due to critical battery',
          data: {'batteryLevel': level, 'isCharging': charging},
        );

        // Maybe auto-pause if playing to save more battery
        if (isPlaying && level <= (_config.criticalBatteryThreshold / 2)) {
          pause();

          // Log event
          _logEvent(
            eventType: 'auto_pause',
            message: 'Auto-paused due to very low battery',
            data: {'batteryLevel': level},
          );
        }
        break;

      case BatteryState.charging:
      // Restore features if they were reduced
        if (!_useEnhancedPlayback && _config.autoEnableAccessibility) {
          _useEnhancedPlayback = true;
          _volumeNormalization = _config.normalizeVolume;

          // Log event
          _logEvent(
            eventType: 'charging',
            message: 'Restored features while charging',
            data: {'batteryLevel': level},
          );
        }
        break;

      case BatteryState.unknown:
      default:
      // No change
        break;
    }
  }

  /// Handle player errors with appropriate recovery
  void _handlePlayerError(dynamic error) {
    _logger.e('Player error', error);

    final errorType = _categorizeError(error);
    final errorMessage = error.toString();

    // Update status
    _updateStatus(
      state: AudioPlayerState.error,
      errorMessage: errorMessage,
      errorType: errorType,
    );

    // Log error event
    _logEvent(
      eventType: 'playback_error',
      message: 'Error during playback: $errorMessage',
      data: {
        'errorType': errorType.toString(),
        'path': _statusSubject.value.path,
        'nudgeId': _statusSubject.value.nudge?.id,
      },
    );

    // Try error recovery based on type
    switch (errorType) {
      case AudioPlayerErrorType.connectivity:
      // Try to switch to cached version if available
        final path = _statusSubject.value.path;
        final nudge = _statusSubject.value.nudge;
        if (path != null && path.startsWith('http') && nudge != null) {
          _offlineMode = true;
          _updateStatus(offlineMode: true);

          // Try to play from cache
          _playFromCache(path, nudge);
        }
        break;

      case AudioPlayerErrorType.fileAccess:
      case AudioPlayerErrorType.decoding:
      // If using accessibility, try without it
        if (_useEnhancedPlayback) {
          _useEnhancedPlayback = false;

          // Try to replay the current audio without enhancement
          final path = _statusSubject.value.path;
          final nudge = _statusSubject.value.nudge;
          if (path != null) {
            Future.delayed(const Duration(milliseconds: 500), () {
              playUrl(path, nudge: nudge);
            });
          }
        }
        break;

      case AudioPlayerErrorType.battery:
      // Already handled in battery monitoring
        break;

      case AudioPlayerErrorType.deviceLimit:
      case AudioPlayerErrorType.playback:
      case AudioPlayerErrorType.permission:
      case AudioPlayerErrorType.unknown:
      default:
      // Just report the error, no recovery
        break;
    }
  }

  /// Play audio from a URL or file path
  ///
  /// This is the main method to play audio. It handles:
  /// - Caching for network URLs
  /// - Accessibility processing if enabled
  /// - Fallback playback if enhanced playback fails
  /// - Battery and connectivity awareness
  ///
  /// [url] URL or file path to play
  /// [nudge] Optional nudge metadata for tracking
  /// [autoPlay] Whether to start playing immediately
  /// [forceRefresh] Whether to force refresh cached content
  ///
  /// Returns a Future that completes when playback is ready
  Future<void> playUrl(String url, {
    NudgeDelivery? nudge,
    bool autoPlay = true,
    bool forceRefresh = false,
  }) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      try {
        // Update status to loading
        _updateStatus(
          state: AudioPlayerState.loading,
          path: url,
          nudge: nudge,
        );

        // Log event
        _logEvent(
          eventType: 'playback_requested',
          message: 'Playback requested',
          data: {'url': url, 'nudgeId': nudge?.id, 'autoPlay': autoPlay},
        );

        // Stop any current playback
        await stop();

        // Determine source type
        final isNetworkUrl = url.startsWith('http');
        final source = isNetworkUrl ? AudioSource.network : AudioSource.file;

        // Handle offline mode for network URLs
        if (isNetworkUrl && (_offlineMode || !_connectivityProvider.isOffline(_connectivityResult))) {
          return _playFromCache(url, nudge, autoPlay: autoPlay, forceRefresh: forceRefresh);
        }

        // Check if we should use enhanced playback
        if (_useEnhancedPlayback && _useAccessibilityService) {
          try {
            return await _playWithAccessibility(url, nudge, autoPlay);
          } catch (e) {
            _logger.w('Enhanced playback failed, falling back to normal playback', e);

            // Log fallback
            _logEvent(
              eventType: 'accessibility_fallback',
              message: 'Falling back to normal playback after accessibility error',
              data: {'error': e.toString()},
            );

            // Continue with normal playback
          }
        }

        // Regular playback
        String audioPath = url;

        // If it's a network URL and we're not in offline mode, maybe cache it
        if (isNetworkUrl && _config.cacheAudioByDefault && !_offlineMode) {
          final file = await _cachingProvider.getCachedFile(
            url,
            highPriority: true,
            nudge: nudge,
            forceRefresh: forceRefresh,
          );

          if (file != null) {
            audioPath = file.path;
          }
        }

        // Update status with source info
        _updateStatus(source: source);

        // Load the audio
        await _player.setFilePath(audioPath);

        // Start playing if requested
        if (autoPlay) {
          await _player.play();
        }

        // Log success
        _logEvent(
          eventType: 'playback_ready',
          message: 'Playback ready',
          data: {
            'path': audioPath,
            'nudgeId': nudge?.id,
            'source': source.toString(),
          },
        );

        return;
      } catch (e, stackTrace) {
        _logger.e('Failed to play audio', e, stackTrace);

        final errorType = _categorizeError(e);
        final exception = e is AudioPlayerException
            ? e
            : AudioPlayerException(
          'Failed to play audio: ${e.toString()}',
          errorType,
          cause: e,
        );

        // Report error
        ErrorReporter.reportError(
          'AudioPlayerService.playUrl',
          exception,
          stackTrace,
        );

        // Update status to error
        _updateStatus(
          state: AudioPlayerState.error,
          errorMessage: exception.message,
          errorType: errorType,
        );

        // Log error event
        _logEvent(
          eventType: 'playback_failed',
          message: 'Failed to play audio: ${e.toString()}',
          data: {
            'url': url,
            'nudgeId': nudge?.id,
            'errorType': errorType.toString(),
          },
        );

        // Try error recovery
        if (isNetworkUrl && !_offlineMode) {
          // Maybe network issue, try offline mode
          _offlineMode = true;
          _updateStatus(offlineMode: true);

          _logEvent(
            eventType: 'auto_offline_mode',
            message: 'Switching to offline mode after playback failure',
          );

          return _playFromCache(url, nudge, autoPlay: autoPlay);
        }

        throw exception;
      }
    });
  }

  /// Play from cache with appropriate fallbacks
  Future<void> _playFromCache(String url, NudgeDelivery? nudge, {
    bool autoPlay = true,
    bool forceRefresh = false,
  }) async {
    try {
      // Try to get from cache
      final file = await _cachingProvider.getCachedFile(
        url,
        highPriority: true,
        nudge: nudge,
        forceRefresh: forceRefresh,
      );

      if (file != null) {
        // We have a cached version, use it
        _logEvent(
          eventType: 'using_cached_audio',
          message: 'Using cached audio file',
          data: {'url': url, 'path': file.path, 'nudgeId': nudge?.id},
        );

        // Play with accessibility if enabled
        if (_useEnhancedPlayback && _useAccessibilityService) {
          return await _playWithAccessibility(file.path, nudge, autoPlay);
        } else {
          // Regular playback
          await _player.setFilePath(file.path);

          _updateStatus(
            source: AudioSource.file,
            path: file.path,
          );

          if (autoPlay) {
            await _player.play();
          }

          return;
        }
      } else {
        // No cached version available
        throw AudioPlayerException(
          'Cannot play in offline mode: no cached version available',
          AudioPlayerErrorType.connectivity,
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to play from cache', e, stackTrace);

      final errorType = _categorizeError(e);
      final exception = e is AudioPlayerException
          ? e
          : AudioPlayerException(
        'Failed to play from cache: ${e.toString()}',
        errorType,
        cause: e,
      );

      // Report error
      ErrorReporter.reportError(
        'AudioPlayerService._playFromCache',
        exception,
        stackTrace,
      );

      // Update status to error
      _updateStatus(
        state: AudioPlayerState.error,
        errorMessage: exception.message,
        errorType: errorType,
      );

      // Log error event
      _logEvent(
        eventType: 'cache_playback_failed',
        message: 'Failed to play from cache: ${e.toString()}',
        data: {
          'url': url,
          'nudgeId': nudge?.id,
          'errorType': errorType.toString(),
        },
      );

      throw exception;
    }
  }

  /// Play with accessibility enhancements
  Future<void> _playWithAccessibility(String path, NudgeDelivery? nudge, bool autoPlay) async {
    try {
      // Process the audio for accessibility if needed
      String processedPath = path;

      // If volume normalization is enabled and this is a file
      if (_volumeNormalization && !path.startsWith('http')) {
        processedPath = await _accessibilityProvider.processAudioForAccessibility(path);

        _updateStatus(volumeNormalized: true);

        _logEvent(
          eventType: 'audio_processed',
          message: 'Audio processed for accessibility',
          data: {'originalPath': path, 'processedPath': processedPath},
        );
      }

      // Play with enhanced accessibility
      final playbackId = 'play_${DateTime.now().millisecondsSinceEpoch}';

      // Release any previous enhanced playback
      if (_currentEnhancedPlaybackId != null) {
        await _accessibilityProvider.releasePlayback(_currentEnhancedPlaybackId!);
        _enhancedPlaybackSubscriptions[_currentEnhancedPlaybackId!]?.cancel();
        _enhancedPlaybackSubscriptions.remove(_currentEnhancedPlaybackId);
        _enhancedPlaybacks.remove(_currentEnhancedPlaybackId);
      }

      // Get enhanced playback stream
      final playbackStream = await _accessibilityProvider.playEnhancedAudio(
        processedPath,
        playbackId: playbackId,
        nudge: nudge,
      );

      // Store for later access
      _enhancedPlaybacks[playbackId] = playbackStream;
      _currentEnhancedPlaybackId = playbackId;

      // Listen to playback state
      final subscription = playbackStream.listen((state) {
        // Convert to our status
        _updateStatus(
          state: state.playing ? AudioPlayerState.playing :
          state.processingState == ProcessingState.completed ?
          AudioPlayerState.completed : AudioPlayerState.paused,
          positionMs: state.position.inMilliseconds,
          durationMs: state.duration?.inMilliseconds ?? 0,
          volume: state.volume,
          speed: state.speed,
          buffering: state.processingState == ProcessingState.buffering,
          source: AudioSource.file,
          path: processedPath,
          nudge: nudge,
          volumeNormalized: _volumeNormalization,
        );
      });

      // Store subscription
      _enhancedPlaybackSubscriptions[playbackId] = subscription;

      // Start playing if requested
      if (!autoPlay) {
        await _accessibilityProvider.pausePlayback(playbackId);
      }

      _logEvent(
        eventType: 'enhanced_playback_started',
        message: 'Enhanced playback started',
        data: {
          'path': processedPath,
          'nudgeId': nudge?.id,
          'playbackId': playbackId,
        },
      );

      return;
    } catch (e) {
      _logger.e('Enhanced playback failed', e);

      // Log error event
      _logEvent(
        eventType: 'enhanced_playback_failed',
        message: 'Enhanced playback failed: ${e.toString()}',
        data: {'path': path, 'nudgeId': nudge?.id},
      );

      // Rethrow to fallback to normal playback
      throw e;
    }
  }

  /// Play or resume playback
  ///
  /// If nothing is loaded, does nothing
  /// If paused, resumes playback
  /// If stopped, starts from beginning
  Future<void> play() async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      try {
        if (_currentEnhancedPlaybackId != null) {
          // Resume enhanced playback
          await _accessibilityProvider.resumePlayback(_currentEnhancedPlaybackId!);

          _logEvent(
            eventType: 'enhanced_playback_resumed',
            message: 'Enhanced playback resumed',
            data: {'playbackId': _currentEnhancedPlaybackId},
          );
        } else {
          // Resume normal playback
          await _player.play();

          _logEvent(
            eventType: 'playback_resumed',
            message: 'Playback resumed',
          );
        }
      } catch (e, stackTrace) {
        _logger.e('Failed to play/resume', e, stackTrace);

        final errorType = _categorizeError(e);
        final exception = AudioPlayerException(
          'Failed to play/resume: ${e.toString()}',
          errorType,
          cause: e,
        );

        // Report error
        ErrorReporter.reportError(
          'AudioPlayerService.play',
          exception,
          stackTrace,
        );

        // Update status to error
        _updateStatus(
          state: AudioPlayerState.error,
          errorMessage: exception.message,
          errorType: errorType,
        );

        // Log error event
        _logEvent(
          eventType: 'resume_failed',
          message: 'Failed to resume playback: ${e.toString()}',
          data: {'errorType': errorType.toString()},
        );

        throw exception;
      }
    });
  }

  /// Pause playback
  Future<void> pause() async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      try {
        if (_currentEnhancedPlaybackId != null) {
          // Pause enhanced playback
          await _accessibilityProvider.pausePlayback(_currentEnhancedPlaybackId!);

          _logEvent(
            eventType: 'enhanced_playback_paused',
            message: 'Enhanced playback paused',
            data: {'playbackId': _currentEnhancedPlaybackId},
          );
        } else {
          // Pause normal playback
          await _player.pause();

          _logEvent(
            eventType: 'playback_paused',
            message: 'Playback paused',
          );
        }
      } catch (e, stackTrace) {
        _logger.e('Failed to pause', e, stackTrace);

        // Non-critical error, just log it
        _logEvent(
          eventType: 'pause_failed',
          message: 'Failed to pause playback: ${e.toString()}',
        );
      }
    });
  }

  /// Stop playback and reset position
  Future<void> stop() async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      try {
        if (_currentEnhancedPlaybackId != null) {
          // Stop enhanced playback
          await _accessibilityProvider.stopPlayback(_currentEnhancedPlaybackId!);

          _logEvent(
            eventType: 'enhanced_playback_stopped',
            message: 'Enhanced playback stopped',
            data: {'playbackId': _currentEnhancedPlaybackId},
          );
        } else {
          // Stop normal playback
          await _player.stop();

          _logEvent(
            eventType: 'playback_stopped',
            message: 'Playback stopped',
          );
        }

        // Update status
        _updateStatus(
          state: AudioPlayerState.stopped,
          positionMs: 0,
        );
      } catch (e, stackTrace) {
        _logger.e('Failed to stop', e, stackTrace);

        // Non-critical error, just log it
        _logEvent(
          eventType: 'stop_failed',
          message: 'Failed to stop playback: ${e.toString()}',
        );
      }
    });
  }

  /// Seek to a position
  ///
  /// [positionMs] Position in milliseconds
  Future<void> seekTo(int positionMs) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      try {
        await _player.seek(Duration(milliseconds: positionMs));

        // Update status
        _updateStatus(positionMs: positionMs);

        _logEvent(
          eventType: 'seek',
          message: 'Seeked to position',
          data: {'positionMs': positionMs},
        );
      } catch (e, stackTrace) {
        _logger.e('Failed to seek', e, stackTrace);

        // Non-critical error, just log it
        _logEvent(
          eventType: 'seek_failed',
          message: 'Failed to seek: ${e.toString()}',
          data: {'positionMs': positionMs},
        );
      }
    });
  }

  /// Set volume level
  ///
  /// [volume] Volume level (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      // Clamp volume to valid range
      volume = volume.clamp(0.0, 1.0);

      try {
        // Set volume on player
        await _player.setVolume(volume);

        // Set volume on accessibility service if using it
        if (_currentEnhancedPlaybackId != null) {
          await _accessibilityProvider.updateSettings(volume: volume);
        }

        // Update internal state
        _volume = volume;

        // Update status
        _updateStatus(volume: volume);

        // Save preference
        await _storageProvider.secureWrite('audio_player_volume', volume.toString());

        _logEvent(
          eventType: 'volume_changed',
          message: 'Volume changed',
          data: {'volume': volume},
        );
      } catch (e, stackTrace) {
        _logger.e('Failed to set volume', e, stackTrace);

        // Non-critical error, just log it
        _logEvent(
          eventType: 'volume_change_failed',
          message: 'Failed to change volume: ${e.toString()}',
          data: {'volume': volume},
        );
      }
    });
  }

  /// Set playback speed
  ///
  /// [speed] Playback speed (0.5 - 2.0)
  Future<void> setSpeed(double speed) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      // Clamp speed to valid range
      speed = speed.clamp(0.5, 2.0);

      try {
        // Set speed on player
        await _player.setSpeed(speed);

        // Set speed on accessibility service if using it
        if (_currentEnhancedPlaybackId != null) {
          await _accessibilityProvider.updateSettings(speakingRate: speed);
        }

        // Update internal state
        _speed = speed;

        // Update status
        _updateStatus(speed: speed);

        // Save preference
        await _storageProvider.secureWrite('audio_player_speed', speed.toString());

        _logEvent(
          eventType: 'speed_changed',
          message: 'Playback speed changed',
          data: {'speed': speed},
        );
      } catch (e, stackTrace) {
        _logger.e('Failed to set speed', e, stackTrace);

        // Non-critical error, just log it
        _logEvent(
          eventType: 'speed_change_failed',
          message: 'Failed to change speed: ${e.toString()}',
          data: {'speed': speed},
        );
      }
    });
  }

  /// Set volume normalization
  ///
  /// [enabled] Whether to enable volume normalization
  Future<void> setVolumeNormalization(bool enabled) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      try {
        // Update internal state
        _volumeNormalization = enabled;

        // Update status
        _updateStatus(volumeNormalized: enabled);

        // Save preference
        await _storageProvider.secureWrite('audio_player_normalize', enabled.toString());

        _logEvent(
          eventType: 'normalization_changed',
          message: 'Volume normalization setting changed',
          data: {'enabled': enabled},
        );

        // If currently playing, we'll need to reload to apply normalization
        if (isPlaying) {
          final path = _statusSubject.value.path;
          final nudge = _statusSubject.value.nudge;
          if (path != null) {
            _logEvent(
              eventType: 'reload_for_normalization',
              message: 'Reloading audio to apply normalization change',
            );

            await playUrl(path, nudge: nudge);
          }
        }
      } catch (e, stackTrace) {
        _logger.e('Failed to set normalization', e, stackTrace);

        // Non-critical error, just log it
        _logEvent(
          eventType: 'normalization_change_failed',
          message: 'Failed to change normalization: ${e.toString()}',
          data: {'enabled': enabled},
        );
      }
    });
  }

  /// Set accessibility enhancements
  ///
  /// [enabled] Whether to enable accessibility enhancements
  Future<void> setAccessibilityEnabled(bool enabled) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      try {
        // Update internal state
        _useAccessibilityService = enabled;

        // Save preference
        await _storageProvider.secureWrite('audio_player_accessibility', enabled.toString());

        _logEvent(
          eventType: 'accessibility_changed',
          message: 'Accessibility setting changed',
          data: {'enabled': enabled},
        );

        // If we're enabling and battery allows, also enable enhanced playback
        if (enabled && !_batteryProvider.getBatteryState(_batteryLevel, _isCharging, _config).toString().contains('critical')) {
          _useEnhancedPlayback = true;
        }

        // If currently playing, we'll need to reload to apply accessibility
        if (isPlaying) {
          final path = _statusSubject.value.path;
          final nudge = _statusSubject.value.nudge;
          if (path != null) {
            _logEvent(
              eventType: 'reload_for_accessibility',
              message: 'Reloading audio to apply accessibility change',
            );

            await playUrl(path, nudge: nudge);
          }
        }
      } catch (e, stackTrace) {
        _logger.e('Failed to set accessibility', e, stackTrace);

        // Non-critical error, just log it
        _logEvent(
          eventType: 'accessibility_change_failed',
          message: 'Failed to change accessibility: ${e.toString()}',
          data: {'enabled': enabled},
        );
      }
    });
  }

  /// Toggle offline mode
  ///
  /// [enabled] Whether to enable offline mode
  Future<void> setOfflineMode(bool enabled) async {
    return _mutex.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      // Update internal state
      _offlineMode = enabled;

      // Update status
      _updateStatus(offlineMode: enabled);

      _logEvent(
        eventType: enabled ? 'offline_mode_enabled' : 'offline_mode_disabled',
        message: enabled ? 'Offline mode enabled' : 'Offline mode disabled',
      );
    });
  }

  /// Prefetch a URL for later playback
  ///
  /// This downloads the audio in the background for faster playback later
  ///
  /// [url] URL to prefetch
  /// [nudge] Optional nudge metadata for tracking
  /// [importance] Importance level (0-10, higher = more important)
  Future<void> prefetch(String url, {NudgeDelivery? nudge, int importance = 5}) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Skip if offline mode
    if (_offlineMode) return;

    // Skip if not a network URL
    if (!url.startsWith('http')) return;

    try {
      // Start prefetching in the background
      _cachingProvider.prefetchFile(url, nudge: nudge, importance: importance);

      _logEvent(
        eventType: 'prefetch_started',
        message: 'Started prefetching audio',
        data: {'url': url, 'nudgeId': nudge?.id, 'importance': importance},
      );
    } catch (e) {
      _logger.e('Failed to prefetch', e);

      // Non-critical error, just log it
      _logEvent(
        eventType: 'prefetch_failed',
        message: 'Failed to prefetch audio: ${e.toString()}',
        data: {'url': url, 'nudgeId': nudge?.id},
      );
    }
  }

  /// Wait for all high-priority downloads to complete
  ///
  /// This is useful before going offline
  ///
  /// [timeout] Maximum time to wait
  Future<void> waitForDownloads({Duration timeout = const Duration(seconds: 30)}) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      await _cachingProvider.waitForPriorityDownloads(timeout: timeout);

      _logEvent(
        eventType: 'downloads_completed',
        message: 'All high-priority downloads completed',
      );
    } catch (e) {
      _logger.e('Failed to wait for downloads', e);

      // Non-critical error, just log it
      _logEvent(
        eventType: 'downloads_timeout',
        message: 'Timed out waiting for downloads',
      );
    }
  }

  /// Get current volume level
  double getVolume() => _volume;

  /// Get current playback speed
  double getSpeed() => _speed;

  /// Check if volume normalization is enabled
  bool isVolumeNormalizationEnabled() => _volumeNormalization;

  /// Check if accessibility enhancements are enabled
  bool isAccessibilityEnabled() => _useAccessibilityService;

  /// Start position update timer
  void _startPositionTimer() {
    // Cancel any existing timer
    _stopPositionTimer();

    // Start a new timer
    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_player.position != null) {
        _updateStatus(positionMs: _player.position.inMilliseconds);
      }
    });
  }

  /// Stop position update timer
  void _stopPositionTimer() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
  }

  /// Update playback status
  void _updateStatus({
    AudioPlayerState? state,
    int? positionMs,
    int? durationMs,
    double? volume,
    double? speed,
    bool? buffering,
    int? bufferPositionMs,
    AudioSource? source,
    String? path,
    NudgeDelivery? nudge,
    String? errorMessage,
    AudioPlayerErrorType? errorType,
    bool? offlineMode,
    int? batteryLevel,
    bool? isCharging,
    bool? volumeNormalized,
  }) {
    final current = _statusSubject.valueOrNull ?? PlaybackStatus(
      state: AudioPlayerState.initializing,
      volume: _volume,
      speed: _speed,
      batteryLevel: _batteryLevel,
      isCharging: _isCharging,
      offlineMode: _offlineMode,
      volumeNormalized: _volumeNormalization,
    );

    final updated = current.copyWith(
      state: state,
      positionMs: positionMs,
      durationMs: durationMs,
      volume: volume,
      speed: speed,
      buffering: buffering,
      bufferPositionMs: bufferPositionMs,
      source: source,
      path: path,
      nudge: nudge,
      errorMessage: errorMessage,
      errorType: errorType,
      offlineMode: offlineMode,
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      volumeNormalized: volumeNormalized,
    );

    _statusSubject.add(updated);
  }

  /// Log an event
  void _logEvent({
    required String eventType,
    required String message,
    Map<String, dynamic>? data,
  }) {
    // Create event
    final event = PlayerEvent(
      eventType: eventType,
      message: message,
      timestamp: DateTime.now(),
      data: data,
    );

    // Log to console
    _logger.d('AudioPlayerEvent: $eventType - $message');

    // Send to event stream
    _eventStreamController.add(event);
  }

  /// Categorize an error
  AudioPlayerErrorType _categorizeError(dynamic error) {
    if (error is AudioPlayerException) {
      return error.type;
    }

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('file') ||
        errorString.contains('path') ||
        errorString.contains('directory') ||
        errorString.contains('not found')) {
      return AudioPlayerErrorType.fileAccess;
    }

    if (errorString.contains('codec') ||
        errorString.contains('format') ||
        errorString.contains('decode')) {
      return AudioPlayerErrorType.decoding;
    }

    if (errorString.contains('network') ||
        errorString.contains('connect') ||
        errorString.contains('internet') ||
        errorString.contains('offline') ||
        errorString.contains('timeout')) {
      return AudioPlayerErrorType.connectivity;
    }

    if (errorString.contains('battery')) {
      return AudioPlayerErrorType.battery;
    }

    if (errorString.contains('permission')) {
      return AudioPlayerErrorType.permission;
    }

    if (errorString.contains('device') ||
        errorString.contains('hardware') ||
        errorString.contains('resource')) {
      return AudioPlayerErrorType.deviceLimit;
    }

    if (errorString.contains('play') ||
        errorString.contains('audio')) {
      return AudioPlayerErrorType.playback;
    }

    return AudioPlayerErrorType.unknown;
  }
}

/// Extension on AudioPlayerState to convert to string
extension AudioPlayerStateExtension on AudioPlayerState {
  /// Convert AudioPlayerState to a user-friendly string
  String toDisplayString() {
    switch (this) {
      case AudioPlayerState.initializing:
        return 'Getting Ready';
      case AudioPlayerState.idle:
        return 'Ready';
      case AudioPlayerState.loading:
        return 'Loading';
      case AudioPlayerState.ready:
        return 'Ready to Play';
      case AudioPlayerState.playing:
        return 'Playing';
      case AudioPlayerState.paused:
        return 'Paused';
      case AudioPlayerState.completed:
        return 'Completed';
      case AudioPlayerState.stopped:
        return 'Stopped';
      case AudioPlayerState.error:
        return 'Error';
    }
  }
}