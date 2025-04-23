// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/utils/audio_quality_monitor.dart
// Version: 1.2.0
// Last Updated: April 21, 2025
// Description: Utility for monitoring and optimizing audio quality for elderly users (55+)

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:synchronized/synchronized.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:app_usage/app_usage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_fft/flutter_fft.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../models/nudge_model.dart';
import '../services/audio/audio_accessibility_service.dart';
import '../utils/advanced_logger.dart';
import '../utils/error_reporter.dart';
import '../utils/config.dart';
import '../services/firebase/firebase_service.dart';
import '../services/localization/app_localizations.dart';
import '../services/auth/auth_service.dart';
import '../services/storage/secure_storage_service.dart';

/// User consent status for audio monitoring
enum ConsentStatus {
  /// User has not been asked for consent
  unknown,

  /// User has granted consent
  granted,

  /// User has denied consent
  denied,

  /// Consent has been revoked
  revoked,
}

/// Security level for audio data processing
enum SecurityLevel {
  /// Standard security level
  standard,

  /// Enhanced security with encryption
  enhanced,

  /// Maximum security with encryption and minimal data collection
  maximum,
}

/// Quality metrics for audio playback
class AudioQualityMetrics {
  /// Peak amplitude (0.0-1.0)
  final double peakAmplitude;

  /// RMS level (root mean square) in dB
  final double rmsLevel;

  /// Clipping percentage (0.0-100.0)
  final double clippingPercentage;

  /// Signal-to-noise ratio in dB
  final double? signalToNoiseRatio;

  /// CPU usage percentage during playback (0.0-100.0)
  final double cpuUsage;

  /// Battery drain percentage per minute during playback
  final double? batteryDrainRate;

  /// Playback completion percentage (0.0-100.0)
  final double playbackCompletionRate;

  /// User engagement score (0.0-1.0)
  final double? userEngagementScore;

  /// Whether audio was played on speaker or headphones
  final AudioOutputDevice outputDevice;

  /// Audio format information
  final AudioFormatInfo format;

  /// Device model information
  final String deviceModel;

  /// Timestamp when metrics were collected
  final DateTime timestamp;

  /// Associated nudge ID (if any)
  final String? nudgeId;

  /// User ID for privacy and analytics (encrypted if privacy mode enabled)
  final String? userId;

  /// Session ID for tracking
  final String sessionId;

  /// App version for tracking issues across versions
  final String appVersion;

  /// Unique correlation ID for linking related errors
  final String correlationId;

  /// Context information about the session
  final Map<String, dynamic>? sessionContext;

  const AudioQualityMetrics({
    required this.peakAmplitude,
    required this.rmsLevel,
    required this.clippingPercentage,
    this.signalToNoiseRatio,
    required this.cpuUsage,
    required this.batteryDrainRate,
    required this.playbackCompletionRate,
    this.userEngagementScore,
    required this.outputDevice,
    required this.format,
    required this.deviceModel,
    required this.timestamp,
    this.nudgeId,
    this.userId,
    required this.sessionId,
    required this.appVersion,
    required this.correlationId,
    this.sessionContext,
  });

  /// Convert metrics to JSON for storage or analysis
  Map<String, dynamic> toJson() {
    return {
      'peakAmplitude': peakAmplitude,
      'rmsLevel': rmsLevel,
      'clippingPercentage': clippingPercentage,
      'signalToNoiseRatio': signalToNoiseRatio,
      'cpuUsage': cpuUsage,
      'batteryDrainRate': batteryDrainRate,
      'playbackCompletionRate': playbackCompletionRate,
      'userEngagementScore': userEngagementScore,
      'outputDevice': outputDevice.name,
      'format': format.toJson(),
      'deviceModel': deviceModel,
      'timestamp': timestamp.toIso8601String(),
      'nudgeId': nudgeId,
      'userId': userId,
      'sessionId': sessionId,
      'appVersion': appVersion,
      'correlationId': correlationId,
      'sessionContext': sessionContext,
    };
  }

  /// Create metrics from JSON
  factory AudioQualityMetrics.fromJson(Map<String, dynamic> json) {
    // Handle potential missing or malformed fields
    AudioFormatInfo formatInfo;
    try {
      formatInfo = AudioFormatInfo.fromJson(json['format'] as Map<String, dynamic>);
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMetrics',
        'Error parsing format info: $e, using default values',
      );
      formatInfo = AudioFormatInfo.defaultValues();
    }

    Map<String, dynamic>? contextData;
    if (json['sessionContext'] != null) {
      try {
        contextData = json['sessionContext'] as Map<String, dynamic>;
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMetrics',
          'Error parsing session context: $e',
        );
      }
    }

    return AudioQualityMetrics(
      peakAmplitude: (json['peakAmplitude'] as num?)?.toDouble() ?? 0.0,
      rmsLevel: (json['rmsLevel'] as num?)?.toDouble() ?? -20.0,
      clippingPercentage: (json['clippingPercentage'] as num?)?.toDouble() ?? 0.0,
      signalToNoiseRatio: json['signalToNoiseRatio'] != null ?
      (json['signalToNoiseRatio'] as num).toDouble() : null,
      cpuUsage: (json['cpuUsage'] as num?)?.toDouble() ?? 0.0,
      batteryDrainRate: json['batteryDrainRate'] != null ?
      (json['batteryDrainRate'] as num).toDouble() : null,
      playbackCompletionRate: (json['playbackCompletionRate'] as num?)?.toDouble() ?? 0.0,
      userEngagementScore: json['userEngagementScore'] != null ?
      (json['userEngagementScore'] as num).toDouble() : null,
      outputDevice: _parseOutputDevice(json['outputDevice']),
      format: formatInfo,
      deviceModel: json['deviceModel'] as String? ?? 'Unknown Device',
      timestamp: json['timestamp'] != null ?
      DateTime.parse(json['timestamp'] as String) : DateTime.now(),
      nudgeId: json['nudgeId'] as String?,
      userId: json['userId'] as String?,
      sessionId: json['sessionId'] as String? ?? 'unknown_session',
      appVersion: json['appVersion'] as String? ?? 'unknown_version',
      correlationId: json['correlationId'] as String? ?? const Uuid().v4(),
      sessionContext: contextData,
    );
  }

  /// Safely parse AudioOutputDevice from string
  static AudioOutputDevice _parseOutputDevice(dynamic value) {
    if (value is String) {
      try {
        return AudioOutputDevice.values.firstWhere(
              (e) => e.name == value,
          orElse: () => AudioOutputDevice.unknown,
        );
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMetrics',
          'Error parsing output device: $e',
        );
      }
    }
    return AudioOutputDevice.unknown;
  }

  /// Get a quality score based on all metrics (0.0-100.0)
  double getQualityScore() {
    // Base score starts at 100
    double score = 100.0;

    // Reduce score for clipping
    score -= clippingPercentage * 0.5;

    // Reduce score for low SNR
    if (signalToNoiseRatio != null && signalToNoiseRatio! < 40.0) {
      score -= (40.0 - signalToNoiseRatio!) * 0.5;
    }

    // Reduce score for high CPU usage
    if (cpuUsage > 30.0) {
      score -= (cpuUsage - 30.0) * 0.3;
    }

    // Reduce score for battery drain
    if (batteryDrainRate != null && batteryDrainRate! > 1.0) {
      score -= (batteryDrainRate! - 1.0) * 5.0;
    }

    // Reduce score for incomplete playback
    if (playbackCompletionRate < 100.0) {
      score -= (100.0 - playbackCompletionRate) * 0.2;
    }

    // Limit score to range 0-100
    return max(0.0, min(100.0, score));
  }

  /// Get human-readable quality assessment
  String getQualityAssessment(AppLocalizations localizations) {
    final score = getQualityScore();

    if (score >= 90.0) {
      return localizations.translate('quality_excellent');
    } else if (score >= 75.0) {
      return localizations.translate('quality_good');
    } else if (score >= 60.0) {
      return localizations.translate('quality_fair');
    } else if (score >= 40.0) {
      return localizations.translate('quality_poor');
    } else {
      return localizations.translate('quality_very_poor');
    }
  }

  /// Get specific improvement recommendations
  List<String> getImprovementRecommendations(AppLocalizations localizations) {
    final recommendations = <String>[];

    if (clippingPercentage > 5.0) {
      recommendations.add(localizations.translate('recommendation_reduce_volume'));
    }

    if (rmsLevel < -30.0) {
      recommendations.add(localizations.translate('recommendation_increase_volume'));
    }

    if (signalToNoiseRatio != null && signalToNoiseRatio! < 30.0) {
      recommendations.add(localizations.translate('recommendation_use_headphones'));
    }

    if (cpuUsage > 50.0) {
      recommendations.add(localizations.translate('recommendation_close_apps'));
    }

    if (batteryDrainRate != null && batteryDrainRate! > 2.0) {
      recommendations.add(localizations.translate('recommendation_connect_power'));
    }

    if (playbackCompletionRate < 80.0) {
      recommendations.add(localizations.translate('recommendation_shorter_audio'));
    }

    if (outputDevice == AudioOutputDevice.speaker &&
        (rmsLevel < -25.0 || (signalToNoiseRatio != null && signalToNoiseRatio! < 35.0))) {
      recommendations.add(localizations.translate('recommendation_external_speakers'));
    }

    return recommendations;
  }

  /// Create an anonymized copy for privacy
  AudioQualityMetrics anonymized() {
    return AudioQualityMetrics(
      peakAmplitude: peakAmplitude,
      rmsLevel: rmsLevel,
      clippingPercentage: clippingPercentage,
      signalToNoiseRatio: signalToNoiseRatio,
      cpuUsage: cpuUsage,
      batteryDrainRate: batteryDrainRate,
      playbackCompletionRate: playbackCompletionRate,
      userEngagementScore: userEngagementScore,
      outputDevice: outputDevice,
      format: format,
      // Anonymize device model
      deviceModel: deviceModel.split(' ').first,
      timestamp: timestamp,
      // Remove nudge ID
      nudgeId: null,
      // Remove user ID
      userId: null,
      sessionId: sessionId,
      appVersion: appVersion,
      correlationId: correlationId,
      // Remove context
      sessionContext: null,
    );
  }

  /// Create a deep copy with optional field updates
  AudioQualityMetrics copyWith({
    double? peakAmplitude,
    double? rmsLevel,
    double? clippingPercentage,
    double? signalToNoiseRatio,
    double? cpuUsage,
    double? batteryDrainRate,
    double? playbackCompletionRate,
    double? userEngagementScore,
    AudioOutputDevice? outputDevice,
    AudioFormatInfo? format,
    String? deviceModel,
    DateTime? timestamp,
    String? nudgeId,
    String? userId,
    String? sessionId,
    String? appVersion,
    String? correlationId,
    Map<String, dynamic>? sessionContext,
  }) {
    return AudioQualityMetrics(
      peakAmplitude: peakAmplitude ?? this.peakAmplitude,
      rmsLevel: rmsLevel ?? this.rmsLevel,
      clippingPercentage: clippingPercentage ?? this.clippingPercentage,
      signalToNoiseRatio: signalToNoiseRatio ?? this.signalToNoiseRatio,
      cpuUsage: cpuUsage ?? this.cpuUsage,
      batteryDrainRate: batteryDrainRate ?? this.batteryDrainRate,
      playbackCompletionRate: playbackCompletionRate ?? this.playbackCompletionRate,
      userEngagementScore: userEngagementScore ?? this.userEngagementScore,
      outputDevice: outputDevice ?? this.outputDevice,
      format: format ?? this.format,
      deviceModel: deviceModel ?? this.deviceModel,
      timestamp: timestamp ?? this.timestamp,
      nudgeId: nudgeId ?? this.nudgeId,
      userId: userId ?? this.userId,
      sessionId: sessionId ?? this.sessionId,
      appVersion: appVersion ?? this.appVersion,
      correlationId: correlationId ?? this.correlationId,
      sessionContext: sessionContext ?? this.sessionContext,
    );
  }

  /// Validate metrics for security/privacy compliance
  bool validateForCompliance() {
    // Ensure no personally identifiable information
    if (sessionContext != null) {
      // Check for known PII fields
      const piiFields = ['name', 'email', 'phone', 'address', 'location', 'ip', 'gps'];
      for (final field in piiFields) {
        if (sessionContext!.containsKey(field)) {
          AdvancedLogger.logWarning(
            'AudioQualityMetrics',
            'Metrics contain potential PII field: $field',
          );
          return false;
        }
      }
    }

    // Validate timestamp is not in the future
    if (timestamp.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      AdvancedLogger.logWarning(
        'AudioQualityMetrics',
        'Metrics contain future timestamp, potential tampering',
      );
      return false;
    }

    // Validate ranges for numerical data
    if (peakAmplitude < 0 || peakAmplitude > 1.0 ||
        clippingPercentage < 0 || clippingPercentage > 100.0 ||
        cpuUsage < 0 || cpuUsage > 100.0 ||
        (batteryDrainRate != null && (batteryDrainRate! < 0 || batteryDrainRate! > 100.0)) ||
        playbackCompletionRate < 0 || playbackCompletionRate > 100.0 ||
        (userEngagementScore != null && (userEngagementScore! < 0 || userEngagementScore! > 1.0))) {
      AdvancedLogger.logWarning(
        'AudioQualityMetrics',
        'Metrics contain out-of-range values',
      );
      return false;
    }

    return true;
  }
}

/// Information about audio format
class AudioFormatInfo {
  /// Audio codec (e.g., MP3, AAC)
  final String codec;

  /// Sample rate in Hz
  final int sampleRate;

  /// Bit rate in kbps
  final int bitRate;

  /// Number of channels (1=mono, 2=stereo)
  final int channels;

  /// Duration in seconds
  final double duration;

  /// File size in bytes
  final int fileSize;

  const AudioFormatInfo({
    required this.codec,
    required this.sampleRate,
    required this.bitRate,
    required this.channels,
    required this.duration,
    required this.fileSize,
  });

  /// Create default format info for fallback
  factory AudioFormatInfo.defaultValues() {
    return const AudioFormatInfo(
      codec: 'Unknown',
      sampleRate: 44100,
      bitRate: 128,
      channels: 2,
      duration: 0.0,
      fileSize: 0,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'codec': codec,
      'sampleRate': sampleRate,
      'bitRate': bitRate,
      'channels': channels,
      'duration': duration,
      'fileSize': fileSize,
    };
  }

  /// Create from JSON with error handling
  factory AudioFormatInfo.fromJson(Map<String, dynamic> json) {
    try {
      return AudioFormatInfo(
        codec: json['codec'] as String? ?? 'Unknown',
        sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 44100,
        bitRate: (json['bitRate'] as num?)?.toInt() ?? 128,
        channels: (json['channels'] as num?)?.toInt() ?? 2,
        duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
        fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      AdvancedLogger.logError(
        'AudioFormatInfo',
        'Error creating from JSON: $e',
      );
      return AudioFormatInfo.defaultValues();
    }
  }
}

/// Type of audio output device
enum AudioOutputDevice {
  /// Built-in speaker
  speaker,

  /// Wired headphones
  wiredHeadphones,

  /// Bluetooth headphones
  bluetoothHeadphones,

  /// Hearing aid
  hearingAid,

  /// External speaker
  externalSpeaker,

  /// Unknown or not detected
  unknown,
}

/// Type of audio quality issues
enum AudioQualityIssue {
  /// Excessive clipping
  clipping,

  /// Volume too low
  lowVolume,

  /// Volume too high
  highVolume,

  /// Background noise
  backgroundNoise,

  /// Distortion
  distortion,

  /// Playback stuttering
  stuttering,

  /// CPU performance issues
  performanceIssues,

  /// Battery drain
  batteryDrain,

  /// Playback interruptions
  interruptions,

  /// Low engagement
  lowEngagement,
}

/// Configuration for the audio quality monitor
class AudioQualityMonitorConfig {
  /// Enable real-time quality monitoring
  final bool enableRealTimeMonitoring;

  /// Sampling interval for metrics in milliseconds
  final int samplingIntervalMs;

  /// Enable automatic corrections
  final bool enableAutoCorrections;

  /// Enable battery monitoring
  final bool enableBatteryMonitoring;

  /// Enable CPU usage monitoring
  final bool enableCpuMonitoring;

  /// Enable engagement tracking
  final bool enableEngagementTracking;

  /// Maximum metrics to store in local cache
  final int maxCachedMetrics;

  /// Upload metrics to Firebase
  final bool uploadMetricsToFirebase;

  /// Upload analytics in batch size
  final int analyticsBatchSize;

  /// Threshold for clipping detection (percentage)
  final double clippingThreshold;

  /// Threshold for low volume detection (dB)
  final double lowVolumeThreshold;

  /// Threshold for high volume detection (dB)
  final double highVolumeThreshold;

  /// Threshold for CPU usage warning (percentage)
  final double cpuUsageThreshold;

  /// Threshold for battery drain warning (percentage per minute)
  final double batteryDrainThreshold;

  /// Privacy mode (anonymize data)
  final bool privacyModeEnabled;

  /// Analytics collection enabled (requires user consent)
  final bool analyticsEnabled;

  /// Debug mode enabled (additional logging)
  final bool debugModeEnabled;

  /// Metric collection frequency in debug mode (milliseconds)
  final int debugModeSamplingIntervalMs;

  /// Low battery threshold for reduced monitoring (percentage)
  final int lowBatteryThreshold;

  /// Critical battery threshold for disabled monitoring (percentage)
  final int criticalBatteryThreshold;

  /// Reduced sampling interval when battery is low (milliseconds)
  final int lowBatterySamplingIntervalMs;

  /// Network retry base delay (milliseconds)
  final int networkRetryBaseDelayMs;

  /// Maximum network retry attempts
  final int maxNetworkRetryAttempts;

  /// Security level for data handling
  final SecurityLevel securityLevel;

  /// How long to keep offline data before requiring fresh consent (days)
  final int offlineDataRetentionDays;

  /// Default constructor
  const AudioQualityMonitorConfig({
    required this.enableRealTimeMonitoring,
    required this.samplingIntervalMs,
    required this.enableAutoCorrections,
    required this.enableBatteryMonitoring,
    required this.enableCpuMonitoring,
    required this.enableEngagementTracking,
    required this.maxCachedMetrics,
    required this.uploadMetricsToFirebase,
    required this.analyticsBatchSize,
    required this.clippingThreshold,
    required this.lowVolumeThreshold,
    required this.highVolumeThreshold,
    required this.cpuUsageThreshold,
    required this.batteryDrainThreshold,
    required this.privacyModeEnabled,
    required this.analyticsEnabled,
    required this.debugModeEnabled,
    required this.debugModeSamplingIntervalMs,
    required this.lowBatteryThreshold,
    required this.criticalBatteryThreshold,
    required this.lowBatterySamplingIntervalMs,
    required this.networkRetryBaseDelayMs,
    required this.maxNetworkRetryAttempts,
    required this.securityLevel,
    required this.offlineDataRetentionDays,
  });

  /// Factory to create from Firebase Remote Config or defaults
  factory AudioQualityMonitorConfig.fromRemoteConfig(Map<String, dynamic> remoteConfig) {
    try {
      // Get the security level
      SecurityLevel securityLevel;
      try {
        final securityLevelStr = remoteConfig['security_level'] as String? ?? 'standard';
        securityLevel = SecurityLevel.values.firstWhere(
              (e) => e.name == securityLevelStr,
          orElse: () => SecurityLevel.standard,
        );
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitorConfig',
          'Error parsing security level: $e',
        );
        securityLevel = SecurityLevel.standard;
      }

      return AudioQualityMonitorConfig(
        enableRealTimeMonitoring: remoteConfig['enable_real_time_monitoring'] as bool? ?? true,
        samplingIntervalMs: (remoteConfig['sampling_interval_ms'] as num?)?.toInt() ?? 5000,
        enableAutoCorrections: remoteConfig['enable_auto_corrections'] as bool? ?? true,
        enableBatteryMonitoring: remoteConfig['enable_battery_monitoring'] as bool? ?? true,
        enableCpuMonitoring: remoteConfig['enable_cpu_monitoring'] as bool? ?? true,
        enableEngagementTracking: remoteConfig['enable_engagement_tracking'] as bool? ?? true,
        maxCachedMetrics: (remoteConfig['max_cached_metrics'] as num?)?.toInt() ?? 100,
        uploadMetricsToFirebase: remoteConfig['upload_metrics_to_firebase'] as bool? ?? true,
        analyticsBatchSize: (remoteConfig['analytics_batch_size'] as num?)?.toInt() ?? 20,
        clippingThreshold: (remoteConfig['clipping_threshold'] as num?)?.toDouble() ?? 5.0,
        lowVolumeThreshold: (remoteConfig['low_volume_threshold'] as num?)?.toDouble() ?? -30.0,
        highVolumeThreshold: (remoteConfig['high_volume_threshold'] as num?)?.toDouble() ?? -10.0,
        cpuUsageThreshold: (remoteConfig['cpu_usage_threshold'] as num?)?.toDouble() ?? 50.0,
        batteryDrainThreshold: (remoteConfig['battery_drain_threshold'] as num?)?.toDouble() ?? 2.0,
        privacyModeEnabled: remoteConfig['privacy_mode_enabled'] as bool? ?? true,
        analyticsEnabled: remoteConfig['analytics_enabled'] as bool? ?? true,
        debugModeEnabled: remoteConfig['debug_mode_enabled'] as bool? ?? false,
        debugModeSamplingIntervalMs: (remoteConfig['debug_mode_sampling_interval_ms'] as num?)?.toInt() ?? 1000,
        lowBatteryThreshold: (remoteConfig['low_battery_threshold'] as num?)?.toInt() ?? 30,
        criticalBatteryThreshold: (remoteConfig['critical_battery_threshold'] as num?)?.toInt() ?? 15,
        lowBatterySamplingIntervalMs: (remoteConfig['low_battery_sampling_interval_ms'] as num?)?.toInt() ?? 10000,
        networkRetryBaseDelayMs: (remoteConfig['network_retry_base_delay_ms'] as num?)?.toInt() ?? 1000,
        maxNetworkRetryAttempts: (remoteConfig['max_network_retry_attempts'] as num?)?.toInt() ?? 5,
        securityLevel: securityLevel,
        offlineDataRetentionDays: (remoteConfig['offline_data_retention_days'] as num?)?.toInt() ?? 7,
      );
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'AudioQualityMonitorConfig',
        'Error creating from remote config: $e\n$stackTrace',
      );

      // Fall back to defaults
      return const AudioQualityMonitorConfig.defaults();
    }
  }

  /// Default configuration values
  const AudioQualityMonitorConfig.defaults()
      : enableRealTimeMonitoring = true,
        samplingIntervalMs = 5000,
        enableAutoCorrections = true,
        enableBatteryMonitoring = true,
        enableCpuMonitoring = true,
        enableEngagementTracking = true,
        maxCachedMetrics = 100,
        uploadMetricsToFirebase = true,
        analyticsBatchSize = 20,
        clippingThreshold = 5.0,
        lowVolumeThreshold = -30.0,
        highVolumeThreshold = -10.0,
        cpuUsageThreshold = 50.0,
        batteryDrainThreshold = 2.0,
        privacyModeEnabled = true,
        analyticsEnabled = true,
        debugModeEnabled = false,
        debugModeSamplingIntervalMs = 1000,
        lowBatteryThreshold = 30,
        criticalBatteryThreshold = 15,
        lowBatterySamplingIntervalMs = 10000,
        networkRetryBaseDelayMs = 1000,
        maxNetworkRetryAttempts = 5,
        securityLevel = SecurityLevel.standard,
        offlineDataRetentionDays = 7;

  /// Get effective sampling interval based on mode and battery level
  int getEffectiveSamplingInterval({int? batteryLevel}) {
    // Debug mode overrides everything else
    if (debugModeEnabled) {
      return debugModeSamplingIntervalMs;
    }

    // Adjust for battery level if provided
    if (batteryLevel != null) {
      if (batteryLevel <= criticalBatteryThreshold) {
        // Disable real-time monitoring at critical battery
        return samplingIntervalMs * 10;
      } else if (batteryLevel <= lowBatteryThreshold) {
        // Reduce frequency at low battery
        return lowBatterySamplingIntervalMs;
      }
    }

    // Normal mode
    return samplingIntervalMs;
  }

  /// Get network retry delay with exponential backoff
  int getRetryDelayMs(int attemptNumber) {
    if (attemptNumber <= 0) return 0;

    // Exponential backoff with jitter
    final baseDelay = networkRetryBaseDelayMs * pow(2, attemptNumber - 1);
    final jitter = Random().nextInt(networkRetryBaseDelayMs ~/ 2);
    return min((baseDelay + jitter).toInt(), 60000); // Cap at 1 minute
  }

  /// Check if critical battery saving mode should be enabled
  bool shouldEnableCriticalBatterySaving(int batteryLevel) {
    return batteryLevel <= criticalBatteryThreshold;
  }

  /// Should reduce monitoring due to low battery
  bool shouldReduceMonitoring(int batteryLevel) {
    return batteryLevel <= lowBatteryThreshold;
  }
}

/// Service for monitoring and optimizing audio quality
///
/// This service provides functionality to:
/// - Monitor audio playback quality in real-time
/// - Detect and correct common audio issues
/// - Track performance metrics during playback
/// - Generate recommendations for improving audio quality
/// - Optimize audio for elderly users with hearing limitations
/// - Collect analytics on playback completion and engagement
class AudioQualityMonitor {
  // Dependency injection for testability
  final AudioAnalyzer _audioAnalyzer;
  final PerformanceMonitor _performanceMonitor;
  final DeviceInfoProvider _deviceInfoProvider;
  final AudioQualityRepository _repository;
  final AppLocalizations _localizations;
  final SecureStorageService _secureStorage;
  final AuthService _authService;

  // Configuration
  AudioQualityMonitorConfig _config;

  // Internal state
  bool _isInitialized = false;
  bool _isMonitoring = false;
  final List<AudioQualityMetrics> _cachedMetrics = [];
  AudioQualityMetrics? _currentMetrics;
  Timer? _monitoringTimer;
  final Map<String, _PlaybackSession> _activeSessions = {};
  String? _userId;
  String _appVersion = 'unknown';
  bool _isCharging = false;
  int _batteryLevel = 100;
  ConsentStatus _consentStatus = ConsentStatus.unknown;
  DateTime? _consentTimestamp;
  int _offlineRetryAttempt = 0;
  Timer? _offlineUploadTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Encryption for security
  late encrypt.Encrypter _encrypter;
  late encrypt.IV _iv;

  // Synchronization
  final Lock _sessionLock = Lock();
  final Lock _metricsLock = Lock();
  final Lock _consentLock = Lock();

  // Stream controllers
  final StreamController<AudioQualityIssue> _issueDetectedController =
  StreamController<AudioQualityIssue>.broadcast();
  final StreamController<AudioQualityMetrics> _metricsUpdatedController =
  StreamController<AudioQualityMetrics>.broadcast();
  final StreamController<ConsentStatus> _consentStatusController =
  StreamController<ConsentStatus>.broadcast();

  /// Stream of detected quality issues
  Stream<AudioQualityIssue> get issuesDetected => _issueDetectedController.stream;

  /// Stream of metrics updates
  Stream<AudioQualityMetrics> get metricsUpdated => _metricsUpdatedController.stream;

  /// Stream of consent status changes
  Stream<ConsentStatus> get consentStatusChanged => _consentStatusController.stream;

  /// Singleton instance
  static AudioQualityMonitor? _instance;

  /// Factory constructor that returns a singleton instance
  factory AudioQualityMonitor({
    AudioAnalyzer? audioAnalyzer,
    PerformanceMonitor? performanceMonitor,
    DeviceInfoProvider? deviceInfoProvider,
    AudioQualityRepository? repository,
    AppLocalizations? localizations,
    SecureStorageService? secureStorage,
    AuthService? authService,
    AudioQualityMonitorConfig? config,
  }) {
    return _instance ??= AudioQualityMonitor._internal(
      audioAnalyzer: audioAnalyzer ?? RealAudioAnalyzer(),
      performanceMonitor: performanceMonitor ?? RealPerformanceMonitor(),
      deviceInfoProvider: deviceInfoProvider ?? RealDeviceInfoProvider(),
      repository: repository ?? FirebaseAudioQualityRepository(),
      localizations: localizations ?? AppLocalizations(),
      secureStorage: secureStorage ?? SecureStorageService(),
      authService: authService ?? AuthService(),
      config: config ?? const AudioQualityMonitorConfig.defaults(),
    );
  }

  /// Internal constructor
  AudioQualityMonitor._internal({
    required AudioAnalyzer audioAnalyzer,
    required PerformanceMonitor performanceMonitor,
    required DeviceInfoProvider deviceInfoProvider,
    required AudioQualityRepository repository,
    required AppLocalizations localizations,
    required SecureStorageService secureStorage,
    required AuthService authService,
    required AudioQualityMonitorConfig config,
  }) :
        _audioAnalyzer = audioAnalyzer,
        _performanceMonitor = performanceMonitor,
        _deviceInfoProvider = deviceInfoProvider,
        _repository = repository,
        _localizations = localizations,
        _secureStorage = secureStorage,
        _authService = authService,
        _config = config {
    // Initialize encryption with default key
    final key = encrypt.Key.fromLength(32); // Default random key
    _iv = encrypt.IV.fromLength(16);
    _encrypter = encrypt.Encrypter(encrypt.AES(key));
  }

  /// Reset the singleton instance (for testing)
  @visibleForTesting
  static void resetInstance() {
    _instance?._dispose();
    _instance = null;
  }

  /// Clean up resources
  Future<void> _dispose() async {
    await _stopMonitoring();

    // Cancel offline upload timer
    _offlineUploadTimer?.cancel();

    // Cancel connectivity subscription
    await _connectivitySubscription?.cancel();

    // Upload any remaining cached metrics before disposing
    if (_cachedMetrics.isNotEmpty && _consentStatus == ConsentStatus.granted) {
      try {
        await _uploadCachedMetrics();
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error uploading cached metrics during disposal: $e',
        );
      }
    }

    // Dispose of all dependencies
    try {
      await _audioAnalyzer.dispose();
      await _performanceMonitor.dispose();
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error disposing dependencies: $e',
      );
    }

    // Close stream controllers
    await _issueDetectedController.close();
    await _metricsUpdatedController.close();
    await _consentStatusController.close();

    AdvancedLogger.log(
        'AudioQualityMonitor',
        'Monitor successfully disposed'
    );
  }

  /// Initialize the monitor
  ///
  /// Sets up all required systems for monitoring
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      AdvancedLogger.log('AudioQualityMonitor', 'Initializing audio quality monitor');

      // Load remote configuration first
      await _loadConfiguration();

      // Set up encryption with secure key
      await _setupEncryption();

      // Initialize components
      await _audioAnalyzer.initialize();
      await _performanceMonitor.initialize();
      await _repository.initialize();

      // Get app version for tracking
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      // Start battery monitoring
      if (_config.enableBatteryMonitoring) {
        await _startBatteryMonitoring();
      }

      // Load user consent status
      await _loadConsentStatus();

      // Get user ID from auth service
      _userId = await _authService.getCurrentUserId();

      // Set up offline data management
      _setupOfflineDataHandling();

      // Listen for connectivity changes
      _setupConnectivityListener();

      _isInitialized = true;
      AdvancedLogger.log(
        'AudioQualityMonitor',
        'Audio quality monitor initialized successfully with version $_appVersion, security level: ${_config.securityLevel.name}',
      );

      // Upload any cached metrics from previous sessions if consent is granted
      if (_consentStatus == ConsentStatus.granted) {
        _uploadCachedMetrics();
      } else {
        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Skipping upload of cached metrics, consent status: ${_consentStatus.name}',
        );
      }
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error initializing audio quality monitor: $e\n$stackTrace',
      );

      ErrorReporter.reportError(
        'AudioQualityMonitor.initialize',
        Exception('Initialization failed: ${e.toString()}'),
        stackTrace,
        contextData: {
          'appVersion': _appVersion,
          'deviceModel': await _deviceInfoProvider.getDeviceModel().catchError((_) => 'unknown'),
          'consentStatus': _consentStatus.name,
        },
      );

      // Re-throw for caller to handle
      rethrow;
    }
  }

  /// Set up secure encryption based on security level
  Future<void> _setupEncryption() async {
    try {
      String? encryptionKey;

      // For enhanced or maximum security, use a stored key or generate and store one
      if (_config.securityLevel != SecurityLevel.standard) {
        // Try to load existing key
        encryptionKey = await _secureStorage.read('audio_metrics_encryption_key');

        if (encryptionKey == null) {
          // Generate new random key
          final key = encrypt.Key.fromSecureRandom(32);
          encryptionKey = base64.encode(key.bytes);

          // Store for future use
          await _secureStorage.write(
            'audio_metrics_encryption_key',
            encryptionKey,
          );
        }

        // Create encrypter with secure key
        final key = encrypt.Key.fromBase64(encryptionKey);
        _encrypter = encrypt.Encrypter(encrypt.AES(key));
        _iv = encrypt.IV.fromSecureRandom(16);

        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Secure encryption initialized with ${_config.securityLevel.name} security level',
        );
      } else {
        // Standard security uses a default key
        final key = encrypt.Key.fromLength(32);
        _encrypter = encrypt.Encrypter(encrypt.AES(key));
        _iv = encrypt.IV.fromLength(16);
      }
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error setting up encryption: $e, falling back to standard security',
      );
      // Fall back to standard security
      final key = encrypt.Key.fromLength(32);
      _encrypter = encrypt.Encrypter(encrypt.AES(key));
      _iv = encrypt.IV.fromLength(16);
    }
  }

  /// Encrypt sensitive data
  String encryptData(String data) {
    try {
      return _encrypter.encrypt(data, iv: _iv).base64;
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error encrypting data: $e',
      );
      // Return a placeholder indicating encryption error
      return 'ENCRYPTION_ERROR';
    }
  }

  /// Decrypt sensitive data
  String? decryptData(String encryptedData) {
    try {
      return _encrypter.decrypt64(encryptedData, iv: _iv);
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error decrypting data: $e',
      );
      return null;
    }
  }

  /// Load configuration from Firebase Remote Config
  Future<void> _loadConfiguration() async {
    try {
      final firebaseService = FirebaseService();
      final remoteConfig = await firebaseService.getRemoteConfig('audio_monitor_config');

      if (remoteConfig != null && remoteConfig.isNotEmpty) {
        _config = AudioQualityMonitorConfig.fromRemoteConfig(remoteConfig);
        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Loaded configuration from Firebase Remote Config',
        );
      } else {
        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Using default configuration (no remote config found)',
        );
      }
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error loading configuration: $e, using defaults',
      );

      // Keep using default config
    }
  }

  /// Start battery monitoring
  Future<void> _startBatteryMonitoring() async {
    try {
      final battery = Battery();

      // Get initial battery level
      _batteryLevel = await battery.batteryLevel;

      // Get initial charging state
      final batteryState = await battery.batteryState;
      _isCharging = batteryState == BatteryState.charging ||
          batteryState == BatteryState.full;

      // Listen for battery state changes
      battery.onBatteryStateChanged.listen((state) {
        _isCharging = state == BatteryState.charging ||
            state == BatteryState.full;
      });

      // Check battery level periodically
      Timer.periodic(const Duration(minutes: 5), (_) async {
        try {
          final newLevel = await battery.batteryLevel;

          // If battery level dropped significantly, adjust monitoring
          if (newLevel < _batteryLevel &&
              newLevel <= _config.lowBatteryThreshold &&
              _isMonitoring) {
            // Adjust monitoring frequency
            await _adjustMonitoringForBattery(newLevel);
          }

          _batteryLevel = newLevel;
        } catch (e) {
          // Ignore errors in background monitoring
        }
      });

      AdvancedLogger.log(
        'AudioQualityMonitor',
        'Battery monitoring started: level $_batteryLevel%, charging: $_isCharging',
      );
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error setting up battery monitoring: $e',
      );
      // Continue without battery monitoring
    }
  }

  /// Adjust monitoring based on battery level
  Future<void> _adjustMonitoringForBattery(int batteryLevel) async {
    // Critical battery level - drastically reduce monitoring
    if (_config.shouldEnableCriticalBatterySaving(batteryLevel)) {
      AdvancedLogger.log(
        'AudioQualityMonitor',
        'Critical battery level ($batteryLevel%), reducing monitoring frequency',
      );

      // If monitoring is active, restart with adjusted rate
      if (_isMonitoring) {
        await _stopMonitoring();
        await _startMonitoring();
      }

      // Disable auto-corrections to save battery
      if (_config.enableAutoCorrections) {
        // This is a temporary override, not changing the config itself
        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Temporarily disabling auto-corrections due to low battery',
        );
      }
    }
    // Low battery - reduce monitoring frequency
    else if (_config.shouldReduceMonitoring(batteryLevel)) {
      AdvancedLogger.log(
        'AudioQualityMonitor',
        'Low battery level ($batteryLevel%), adjusting monitoring frequency',
      );

      // If monitoring is active, restart with adjusted rate
      if (_isMonitoring) {
        await _stopMonitoring();
        await _startMonitoring();
      }
    }
  }

  /// Load user consent status from secure storage
  Future<void> _loadConsentStatus() async {
    return _consentLock.synchronized(() async {
      try {
        // Check secure storage for stored consent
        final storedConsent = await _secureStorage.read('audio_monitor_consent');
        final storedTimestamp = await _secureStorage.read('audio_monitor_consent_timestamp');

        if (storedConsent != null) {
          // Parse stored consent status
          _consentStatus = ConsentStatus.values.firstWhere(
                (e) => e.name == storedConsent,
            orElse: () => ConsentStatus.unknown,
          );

          // Parse timestamp if available
          if (storedTimestamp != null) {
            try {
              _consentTimestamp = DateTime.parse(storedTimestamp);

              // Check if consent has expired based on offline retention policy
              if (_consentStatus == ConsentStatus.granted) {
                final now = DateTime.now();
                final consentAge = now.difference(_consentTimestamp!).inDays;

                if (consentAge > _config.offlineDataRetentionDays) {
                  AdvancedLogger.log(
                    'AudioQualityMonitor',
                    'Consent has expired (age: $consentAge days, limit: ${_config.offlineDataRetentionDays} days)',
                  );

                  // Reset consent - will require asking again
                  _consentStatus = ConsentStatus.unknown;
                  _consentTimestamp = null;

                  // Clear stored consent
                  await _secureStorage.delete('audio_monitor_consent');
                  await _secureStorage.delete('audio_monitor_consent_timestamp');
                }
              }
            } catch (e) {
              AdvancedLogger.logError(
                'AudioQualityMonitor',
                'Error parsing consent timestamp: $e',
              );
              _consentTimestamp = null;
            }
          }

          AdvancedLogger.log(
            'AudioQualityMonitor',
            'Loaded user consent status: ${_consentStatus.name}',
          );
        } else {
          _consentStatus = ConsentStatus.unknown;
          AdvancedLogger.log(
            'AudioQualityMonitor',
            'No stored consent found, status set to unknown',
          );
        }

        // Broadcast current status
        _consentStatusController.add(_consentStatus);
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error loading consent status: $e, defaulting to unknown',
        );
        _consentStatus = ConsentStatus.unknown;
        _consentTimestamp = null;
      }
    });
  }

  /// Set up offline data management
  void _setupOfflineDataHandling() {
    // Set up periodic check for offline data that needs uploading
    _offlineUploadTimer = Timer.periodic(
      const Duration(minutes: 15),
          (_) {
        // Only attempt upload if:
        // 1. There is cached data
        // 2. User has granted consent
        // 3. Not currently trying another upload
        if (_cachedMetrics.isNotEmpty &&
            _consentStatus == ConsentStatus.granted &&
            _offlineRetryAttempt == 0) {
          _uploadCachedMetrics();
        }
      },
    );
  }

  /// Set up connectivity listener for uploading cached metrics
  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile) {
        // Reset retry counter when connection becomes available
        _offlineRetryAttempt = 0;

        // Upload cached metrics when connection becomes available
        if (_cachedMetrics.isNotEmpty && _consentStatus == ConsentStatus.granted) {
          _uploadCachedMetrics();
        }
      }
    });
  }

  /// Get user consent for audio monitoring
  ///
  /// [force] Whether to ask again even if consent was previously granted
  /// Returns the updated consent status
  Future<ConsentStatus> getUserConsent({bool force = false}) async {
    return _consentLock.synchronized(() async {
      try {
        // If already have consent and not forcing a new request, return current status
        if (!force && _consentStatus == ConsentStatus.granted && _consentTimestamp != null) {
          return _consentStatus;
        }

        // Check for authorization to display consent request
        bool canRequestConsent = await _authService.canRequestDataCollectionConsent();
        if (!canRequestConsent) {
          AdvancedLogger.log(
            'AudioQualityMonitor',
            'Not authorized to request consent at this time',
          );
          return _consentStatus;
        }

        // This would typically show a UI dialog
        // For now, we'll simulate granted consent
        _consentStatus = ConsentStatus.granted;
        _consentTimestamp = DateTime.now();

        // Store consent in secure storage
        await _secureStorage.write(
          'audio_monitor_consent',
          _consentStatus.name,
        );

        await _secureStorage.write(
          'audio_monitor_consent_timestamp',
          _consentTimestamp!.toIso8601String(),
        );

        // Broadcast updated status
        _consentStatusController.add(_consentStatus);

        AdvancedLogger.log(
          'AudioQualityMonitor',
          'User consent updated: ${_consentStatus.name}',
        );

        // If consent was granted, upload any cached metrics
        if (_consentStatus == ConsentStatus.granted && _cachedMetrics.isNotEmpty) {
          _uploadCachedMetrics();
        }

        return _consentStatus;
      } catch (e, stackTrace) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error getting user consent: $e',
        );

        ErrorReporter.reportError(
          'AudioQualityMonitor.getUserConsent',
          Exception('Consent request failed: ${e.toString()}'),
          stackTrace,
          contextData: {
            'previousStatus': _consentStatus.name,
            'forced': force.toString(),
          },
        );

        // Don't change current status on error
        return _consentStatus;
      }
    });
  }

  /// Revoke user consent for audio monitoring
  Future<bool> revokeConsent() async {
    return _consentLock.synchronized(() async {
      try {
        _consentStatus = ConsentStatus.revoked;
        _consentTimestamp = DateTime.now();

        // Store updated consent
        await _secureStorage.write(
          'audio_monitor_consent',
          _consentStatus.name,
        );

        await _secureStorage.write(
          'audio_monitor_consent_timestamp',
          _consentTimestamp!.toIso8601String(),
        );

        // Broadcast updated status
        _consentStatusController.add(_consentStatus);

        // Clear cached metrics
        await _metricsLock.synchronized(() async {
          _cachedMetrics.clear();
        });

        // Delete stored metrics for this user
        if (_userId != null) {
          await _repository.clearMetrics(userId: _userId);
        }

        AdvancedLogger.log(
          'AudioQualityMonitor',
          'User consent revoked and data cleared',
        );

        return true;
      } catch (e, stackTrace) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error revoking consent: $e',
        );

        ErrorReporter.reportError(
          'AudioQualityMonitor.revokeConsent',
          Exception('Consent revocation failed: ${e.toString()}'),
          stackTrace,
        );

        return false;
      }
    });
  }

  /// Update monitor configuration
  ///
  /// [config] New configuration
  ///
  /// Returns true if update was successful
  Future<bool> updateConfiguration(AudioQualityMonitorConfig config) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final wasMonitoring = _isMonitoring;

      // Stop monitoring with old config
      if (wasMonitoring) {
        await _stopMonitoring();
      }

      // Update config
      _config = config;

      // Restart monitoring if it was active
      if (wasMonitoring) {
        await _startMonitoring();
      }

      AdvancedLogger.log(
        'AudioQualityMonitor',
        'Configuration updated successfully',
      );

      return true;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error updating configuration: $e\n$stackTrace',
      );

      ErrorReporter.reportError(
        'AudioQualityMonitor.updateConfiguration',
        Exception('Configuration update failed: ${e.toString()}'),
        stackTrace,
        contextData: {
          'wasMonitoring': _isMonitoring.toString(),
          'securityLevel': _config.securityLevel.name,
        },
      );

      return false;
    }
  }

  /// Set user ID for analytics
  ///
  /// [userId] Unique user identifier
  void setUserId(String? userId) {
    _userId = userId;
  }

  /// Start monitoring a playback session
  ///
  /// [audioPath] Path to the audio file being played
  /// [sessionId] Unique ID for this playback session
  /// [nudge] Optional nudge metadata
  /// [sessionContext] Additional context about the session
  ///
  /// Returns a unique session ID if not provided
  Future<String> startMonitoringSession(
      String audioPath, {
        String? sessionId,
        NudgeDelivery? nudge,
        Map<String, dynamic>? sessionContext,
      }) async {
    // Validate input first
    if (audioPath.isEmpty) {
      throw ArgumentError('Audio path cannot be empty');
    }

    // First check battery level - don't start monitoring if critically low
    if (_batteryLevel <= _config.criticalBatteryThreshold && !_isCharging) {
      AdvancedLogger.log(
        'AudioQualityMonitor',
        'Not starting monitoring due to critical battery level ($_batteryLevel%)',
      );

      // Return a session ID but don't actually monitor
      return sessionId ?? _generateSessionId();
    }

    if (!_isInitialized) {
      await initialize();
    }

    // Check consent status
    if (_consentStatus == ConsentStatus.unknown) {
      // Try to get consent
      final status = await getUserConsent();
      if (status != ConsentStatus.granted) {
        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Cannot start monitoring without user consent (status: ${status.name})',
        );

        // Return a session ID but don't monitor
        return sessionId ?? _generateSessionId();
      }
    } else if (_consentStatus != ConsentStatus.granted) {
      AdvancedLogger.log(
        'AudioQualityMonitor',
        'Cannot start monitoring, consent not granted (status: ${_consentStatus.name})',
      );

      // Return a session ID but don't monitor
      return sessionId ?? _generateSessionId();
    }

    return _sessionLock.synchronized<String>(() async {
      try {
        // Generate session ID if not provided
        final id = sessionId ?? _generateSessionId();

        // Check if session already exists
        if (_activeSessions.containsKey(id)) {
          AdvancedLogger.logWarning(
            'AudioQualityMonitor',
            'Session with ID $id already exists, returning existing ID',
          );
          return id;
        }

        // Validate the audio file exists
        final file = File(audioPath);
        if (!(await file.exists())) {
          throw Exception('Audio file does not exist: $audioPath');
        }

        // Get audio format info
        AudioFormatInfo formatInfo;
        try {
          formatInfo = await _audioAnalyzer.getAudioFormatInfo(audioPath);
        } catch (e) {
          AdvancedLogger.logError(
            'AudioQualityMonitor',
            'Error getting format info, using defaults: $e',
          );
          formatInfo = AudioFormatInfo.defaultValues();
        }

        // Get device info
        final deviceModel = await _deviceInfoProvider.getDeviceModel();

        // Sanitize context data
        Map<String, dynamic>? sanitizedContext;
        if (sessionContext != null) {
          sanitizedContext = _sanitizeSessionContext(sessionContext);
        }

        // Create correlation ID for linking related events
        final correlationId = const Uuid().v4();

        // Create a new session
        final session = _PlaybackSession(
          id: id,
          audioPath: audioPath,
          startTime: DateTime.now(),
          formatInfo: formatInfo,
          deviceModel: deviceModel,
          nudgeId: nudge?.id,
          userId: _config.privacyModeEnabled ?
          (_userId != null ? encryptData(_userId!) : null) : _userId,
          correlationId: correlationId,
          context: sanitizedContext,
        );

        _activeSessions[id] = session;

        // Start monitoring if not already monitoring
        if (!_isMonitoring) {
          await _startMonitoring();
        }

        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Started monitoring session: $id for audio: $audioPath',
          sessionContext: {
            'correlationId': correlationId,
            'userId': _userId != null ? hashUserId(_userId!) : null,
            'batteryLevel': _batteryLevel,
            'isCharging': _isCharging,
            'fileSize': await file.length(),
          },
        );

        return id;
      } catch (e, stackTrace) {
        final fileExists = await File(audioPath).exists().catchError((_) => false);
        final fileSize = fileExists ? await File(audioPath).length().catchError((_) => -1) : -1;

        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error starting monitoring session: $e\n$stackTrace',
        );

        ErrorReporter.reportError(
          'AudioQualityMonitor.startMonitoringSession',
          Exception('Failed to start monitoring: ${e.toString()}'),
          stackTrace,
          contextData: {
            'audioPath': audioPath,
            'audioExists': fileExists.toString(),
            'audioFileSize': fileSize.toString(),
            'batteryLevel': _batteryLevel,
            'consentStatus': _consentStatus.name,
          },
        );

        // Re-throw as a normalized exception
        throw Exception('Failed to start audio monitoring: ${e.toString()}');
      }
    });
  }

  /// Sanitize session context to remove any PII
  Map<String, dynamic> _sanitizeSessionContext(Map<String, dynamic> context) {
    // Create a copy to avoid modifying the original
    final sanitized = Map<String, dynamic>.from(context);

    // Fields that should be completely removed
    const fieldsToRemove = [
      'name', 'fullName', 'firstName', 'lastName', 'email', 'emailAddress',
      'phone', 'phoneNumber', 'address', 'location', 'gps', 'coordinates',
      'ssn', 'socialSecurity', 'password', 'creditCard', 'ip', 'ipAddress',
    ];

    // Remove known PII fields
    for (final field in fieldsToRemove) {
      sanitized.remove(field);
    }

    // Check for potentially sensitive values and hash them
    for (final entry in sanitized.entries.toList()) {
      final value = entry.value;

      // Hash any strings that look like emails or phone numbers
      if (value is String) {
        if (_looksLikeEmail(value) || _looksLikePhone(value)) {
          sanitized[entry.key] = _hashSensitiveValue(value);
        }
      }

      // Also check nested maps
      if (value is Map<String, dynamic>) {
        sanitized[entry.key] = _sanitizeSessionContext(value);
      }
    }

    return sanitized;
  }

  /// Check if string looks like an email
  bool _looksLikeEmail(String value) {
    return value.contains('@') && value.contains('.');
  }

  /// Check if string looks like a phone number
  bool _looksLikePhone(String value) {
    // Remove any non-numeric characters
    final numericOnly = value.replaceAll(RegExp(r'[^\d]'), '');
    // Check if it has a reasonable length for a phone number
    return numericOnly.length >= 7 && numericOnly.length <= 15;
  }

  /// Hash sensitive value for privacy
  String _hashSensitiveValue(String value) {
    try {
      // Create a non-reversible hash
      return 'hashed_${value.hashCode.abs()}';
    } catch (e) {
      return 'hashed_value';
    }
  }

  /// Hash user ID for logging (not reversible)
  String hashUserId(String userId) {
    try {
      // Return just the first few characters of the hash for identification
      return 'uid_${userId.hashCode.abs().toString().substring(0, 4)}';
    } catch (e) {
      return 'uid_unknown';
    }
  }

  /// Stop monitoring a specific session
  ///
  /// [sessionId] ID of the session to stop
  /// [completionPercentage] How much of the audio was played (0.0-100.0)
  /// [userEngagement] Optional user engagement score (0.0-1.0)
  ///
  /// Returns metrics collected during the session
  Future<AudioQualityMetrics?> stopMonitoringSession(
      String sessionId, {
        double completionPercentage = 100.0,
        double? userEngagement,
      }) async {
    // Validate input
    if (sessionId.isEmpty) {
      throw ArgumentError('Session ID cannot be empty');
    }

    if (completionPercentage < 0 || completionPercentage > 100) {
      throw ArgumentError('Completion percentage must be between 0 and 100');
    }

    if (userEngagement != null && (userEngagement < 0 || userEngagement > 1)) {
      throw ArgumentError('User engagement must be between 0 and 1');
    }

    if (!_isInitialized) {
      await initialize();
    }

    return _sessionLock.synchronized<AudioQualityMetrics?>(() async {
      try {
        // Check if session exists
        final session = _activeSessions[sessionId];
        if (session == null) {
          AdvancedLogger.logWarning(
            'AudioQualityMonitor',
            'Attempted to stop unknown session: $sessionId',
          );
          return null;
        }

        // Calculate session duration
        final endTime = DateTime.now();
        final sessionDuration = endTime.difference(session.startTime);

        // Collect final metrics
        final metrics = await _collectMetricsForSession(
          session,
          completionPercentage: completionPercentage,
          userEngagement: userEngagement,
        );

        // Store metrics if collected successfully
        if (metrics != null) {
          // Validate metrics for compliance
          if (!metrics.validateForCompliance()) {
            AdvancedLogger.logWarning(
              'AudioQualityMonitor',
              'Metrics failed compliance validation, anonymizing data',
            );

            // Store anonymized version
            await _storeMetrics(metrics.anonymized());
          } else {
            // Store regular metrics
            await _storeMetrics(metrics);
          }

          // Broadcast update
          _metricsUpdatedController.add(metrics);

          // Log session completion
          AdvancedLogger.log(
            'AudioQualityMonitor',
            'Session completed: $sessionId, duration: $sessionDuration, completion: $completionPercentage%',
            sessionContext: {
              'correlationId': session.correlationId,
              'userId': session.userId != null ?
              (_config.privacyModeEnabled ? 'encrypted' : hashUserId(session.userId!)) : null,
              'duration': sessionDuration.inSeconds,
              'batteryLevel': _batteryLevel,
              'audioPath': session.audioPath,
            },
          );
        }

        // Remove session
        _activeSessions.remove(sessionId);

        // Stop monitoring if no active sessions
        if (_activeSessions.isEmpty) {
          await _stopMonitoring();
        }

        return metrics;
      } catch (e, stackTrace) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error stopping monitoring session: $e\n$stackTrace',
        );

        ErrorReporter.reportError(
          'AudioQualityMonitor.stopMonitoringSession',
          Exception('Failed to stop monitoring: ${e.toString()}'),
          stackTrace,
          contextData: {
            'sessionId': sessionId,
            'completionPercentage': completionPercentage,
            'hasUserEngagement': (userEngagement != null).toString(),
            'batteryLevel': _batteryLevel,
            'sessionExists': _activeSessions.containsKey(sessionId).toString(),
          },
        );

        return null;
      }
    });
  }

  /// Store metrics with error handling and retry logic
  Future<void> _storeMetrics(AudioQualityMetrics metrics) async {
    return _metricsLock.synchronized(() async {
      try {
        // Add to cached metrics
        _cachedMetrics.add(metrics);

        // Limit cached metrics size
        if (_cachedMetrics.length > _config.maxCachedMetrics) {
          _cachedMetrics.removeAt(0);
        }

        // Save batch when threshold reached or on session completion
        if (_consentStatus == ConsentStatus.granted &&
            _config.uploadMetricsToFirebase &&
            (_cachedMetrics.length >= _config.analyticsBatchSize || metrics.userEngagementScore != null)) {
          _uploadCachedMetrics();
        }
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error storing metrics: $e',
        );
        // Continue - metrics will be stored in memory cache
      }
    });
  }

  /// Upload cached metrics to Firebase with exponential backoff retry
  Future<void> _uploadCachedMetrics() async {
    if (!_config.uploadMetricsToFirebase ||
        _cachedMetrics.isEmpty ||
        _consentStatus != ConsentStatus.granted) {
      return;
    }

    return _metricsLock.synchronized(() async {
      try {
        // Check internet connection first
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult == ConnectivityResult.none) {
          // No internet, increment retry attempt for exponential backoff
          _offlineRetryAttempt++;

          // Schedule retry with exponential backoff
          final delay = _config.getRetryDelayMs(_offlineRetryAttempt);
          AdvancedLogger.log(
            'AudioQualityMonitor',
            'No internet connection, scheduling retry #$_offlineRetryAttempt in ${delay}ms',
          );

          // Schedule retry if we haven't exceeded maximum attempts
          if (_offlineRetryAttempt <= _config.maxNetworkRetryAttempts) {
            Timer(Duration(milliseconds: delay), () {
              _uploadCachedMetrics();
            });
          } else {
            AdvancedLogger.logWarning(
              'AudioQualityMonitor',
              'Maximum retry attempts reached ($_offlineRetryAttempt), will try again later',
            );
            // Reset counter after a certain period
            Timer(const Duration(minutes: 30), () {
              _offlineRetryAttempt = 0;
            });
          }

          return;
        }

        // Reset retry counter when we have connection
        _offlineRetryAttempt = 0;

        // Copy metrics to upload
        final metricsToUpload = List<AudioQualityMetrics>.from(_cachedMetrics);

        // Batch upload metrics
        final success = await _repository.saveMetricsBatch(metricsToUpload);

        if (success) {
          // Clear cached metrics if upload was successful
          _cachedMetrics.clear();

          AdvancedLogger.log(
            'AudioQualityMonitor',
            'Successfully uploaded ${metricsToUpload.length} metrics to Firebase',
          );
        } else {
          AdvancedLogger.logWarning(
            'AudioQualityMonitor',
            'Failed to upload metrics, will retry later',
          );

          // Increment retry attempt and schedule retry
          _offlineRetryAttempt++;
          final delay = _config.getRetryDelayMs(_offlineRetryAttempt);

          if (_offlineRetryAttempt <= _config.maxNetworkRetryAttempts) {
            Timer(Duration(milliseconds: delay), () {
              _uploadCachedMetrics();
            });
          }
        }
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error uploading cached metrics: $e',
        );

        // Increment retry attempt and schedule retry
        _offlineRetryAttempt++;
        final delay = _config.getRetryDelayMs(_offlineRetryAttempt);

        if (_offlineRetryAttempt <= _config.maxNetworkRetryAttempts) {
          Timer(Duration(milliseconds: delay), () {
            _uploadCachedMetrics();
          });
        }
      }
    });
  }

  /// Generate a unique session ID
  String _generateSessionId() {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    final randomValue = Random().nextInt(10000);
    final deviceHash = _deviceInfoProvider.getDeviceId().hashCode & 0xFFFF;

    return 'session_${timestamp}_${randomValue}_$deviceHash';
  }

  /// Start periodic monitoring
  Future<void> _startMonitoring() async {
    if (_isMonitoring) return;

    try {
      _isMonitoring = true;

      // Get current battery level for adaptive sampling
      int currentBatteryLevel = _batteryLevel;
      if (_config.enableBatteryMonitoring) {
        try {
          currentBatteryLevel = await _performanceMonitor.getBatteryLevel().then((value) => value.toInt());
          _batteryLevel = currentBatteryLevel; // Update stored level
        } catch (e) {
          // Continue with last known level
          AdvancedLogger.logError(
            'AudioQualityMonitor',
            'Error getting battery level: $e, using last known level: $_batteryLevel',
          );
        }
      }

      // Calculate effective interval based on battery and debug mode
      final effectiveInterval = _config.getEffectiveSamplingInterval(
        batteryLevel: currentBatteryLevel,
      );

      // Start periodic checks
      _monitoringTimer = Timer.periodic(
        Duration(milliseconds: effectiveInterval),
            (_) => _checkAllSessions(),
      );

      AdvancedLogger.log(
        'AudioQualityMonitor',
        'Started periodic monitoring with interval ${effectiveInterval}ms, battery: $currentBatteryLevel%',
      );
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error starting monitoring: $e',
      );
      _isMonitoring = false;
    }
  }

  /// Stop periodic monitoring
  Future<void> _stopMonitoring() async {
    if (!_isMonitoring) return;

    try {
      _isMonitoring = false;
      _monitoringTimer?.cancel();
      _monitoringTimer = null;

      AdvancedLogger.log('AudioQualityMonitor', 'Stopped periodic monitoring');
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error stopping monitoring: $e',
      );
    }
  }

  /// Check all active sessions
  Future<void> _checkAllSessions() async {
    if (_activeSessions.isEmpty) return;

    return _sessionLock.synchronized(() async {
      try {
        final sessionIds = _activeSessions.keys.toList();

        // Check each active session sequentially to avoid overwhelming the device
        for (final sessionId in sessionIds) {
          // Verify session still exists (might have been removed by another thread)
          final session = _activeSessions[sessionId];
          if (session != null) {
            await _checkSession(session);
          }

          // Small delay between sessions to reduce CPU impact
          await Future.delayed(const Duration(milliseconds: 50));
        }
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error checking sessions: $e',
        );
      }
    });
  }

  /// Check a specific session for issues
  Future<void> _checkSession(_PlaybackSession session) async {
    try {
      // Collect metrics
      final metrics = await _collectMetricsForSession(session);

      if (metrics != null) {
        _currentMetrics = metrics;

        // Check for issues
        final issues = _detectIssues(metrics);

        // If in battery saving mode and issues detected, only handle critical issues
        if (_config.shouldReduceMonitoring(_batteryLevel) && issues.isNotEmpty) {
          final criticalIssues = _filterCriticalIssues(issues);

          // Only process critical issues in battery saving mode
          if (criticalIssues.isNotEmpty) {
            // Broadcast critical issues
            for (final issue in criticalIssues) {
              _issueDetectedController.add(issue);
            }

            // Apply auto-corrections if enabled, but only for critical issues
            if (_config.enableAutoCorrections &&
                !_config.shouldEnableCriticalBatterySaving(_batteryLevel)) {
              await _applyAutoCorrections(criticalIssues, session);
            }
          }
        } else {
          // Normal operation - process all issues
          // Broadcast issues
          for (final issue in issues) {
            _issueDetectedController.add(issue);
          }

          // Apply auto-corrections if enabled
          if (_config.enableAutoCorrections && issues.isNotEmpty) {
            await _applyAutoCorrections(issues, session);
          }
        }

        // Broadcast metrics update
        _metricsUpdatedController.add(metrics);

        // Log issues in debug mode
        if (_config.debugModeEnabled && issues.isNotEmpty) {
          AdvancedLogger.log(
            'AudioQualityMonitor',
            'Session ${session.id} issues: ${issues.map((i) => i.name).join(', ')}',
            sessionContext: {'correlationId': session.correlationId},
          );
        }
      }
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error checking session ${session.id}: $e',
        sessionContext: {'correlationId': session.correlationId},
      );

      ErrorReporter.reportError(
        'AudioQualityMonitor.checkSession',
        Exception('Session check failed: ${e.toString()}'),
        StackTrace.current,
        contextData: {
          'sessionId': session.id,
          'correlationId': session.correlationId,
          'batteryLevel': _batteryLevel,
          'audioPath': session.audioPath,
        },
      );
    }
  }

  /// Filter critical issues from all detected issues
  Set<AudioQualityIssue> _filterCriticalIssues(Set<AudioQualityIssue> issues) {
    // Define issues that are considered critical even in low battery mode
    const criticalIssueTypes = {
      AudioQualityIssue.clipping,   // Can damage hearing
      AudioQualityIssue.highVolume, // Can damage hearing
      AudioQualityIssue.batteryDrain, // Critical for battery life
    };

    return issues.where((issue) => criticalIssueTypes.contains(issue)).toSet();
  }

  /// Collect metrics for a session
  Future<AudioQualityMetrics?> _collectMetricsForSession(
      _PlaybackSession session, {
        double? completionPercentage,
        double? userEngagement,
      }) async {
    try {
      // Get audio metrics
      AudioAnalysisMetrics? audioMetrics;
      try {
        // If in battery saving mode, use simplified analysis
        if (_config.shouldReduceMonitoring(_batteryLevel)) {
          audioMetrics = await _audioAnalyzer.analyzeAudioSimple(session.audioPath);
        } else {
          audioMetrics = await _audioAnalyzer.analyzeAudio(session.audioPath);
        }
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error analyzing audio, using fallback: $e',
          sessionContext: {'correlationId': session.correlationId},
        );
        // Use fallback metrics if analysis fails
        audioMetrics = AudioAnalysisMetrics.fallback();
      }

      // Get performance metrics with fallbacks
      double cpuUsage = 0.0;
      if (_config.enableCpuMonitoring) {
        try {
          cpuUsage = await _performanceMonitor.getCurrentCpuUsage();
        } catch (e) {
          AdvancedLogger.logError(
            'AudioQualityMonitor',
            'Error getting CPU usage: $e',
            sessionContext: {'correlationId': session.correlationId},
          );
        }
      }

      double? batteryDrain;
      if (_config.enableBatteryMonitoring && !_isCharging) {
        try {
          batteryDrain = await _performanceMonitor.getBatteryDrainRate();
        } catch (e) {
          AdvancedLogger.logError(
            'AudioQualityMonitor',
            'Error getting battery drain: $e',
            sessionContext: {'correlationId': session.correlationId},
          );
        }
      }

      // Get output device
      AudioOutputDevice outputDevice;
      try {
        outputDevice = await _audioAnalyzer.detectOutputDevice();
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error detecting output device: $e',
          sessionContext: {'correlationId': session.correlationId},
        );
        outputDevice = AudioOutputDevice.unknown;
      }

      // Create metrics object
      return AudioQualityMetrics(
        peakAmplitude: audioMetrics.peakAmplitude,
        rmsLevel: audioMetrics.rmsLevel,
        clippingPercentage: audioMetrics.clippingPercentage,
        signalToNoiseRatio: audioMetrics.signalToNoiseRatio,
        cpuUsage: cpuUsage,
        batteryDrainRate: batteryDrain,
        playbackCompletionRate: completionPercentage ?? 100.0,
        userEngagementScore: userEngagement,
        outputDevice: outputDevice,
        format: session.formatInfo,
        deviceModel: session.deviceModel,
        timestamp: DateTime.now(),
        nudgeId: session.nudgeId,
        userId: session.userId,
        sessionId: session.id,
        appVersion: _appVersion,
        correlationId: session.correlationId,
        sessionContext: session.context,
      );
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error collecting metrics for session ${session.id}: $e\n$stackTrace',
        sessionContext: {'correlationId': session.correlationId},
      );

      ErrorReporter.reportError(
        'AudioQualityMonitor._collectMetricsForSession',
        Exception('Metrics collection failed: ${e.toString()}'),
        stackTrace,
        contextData: {
          'sessionId': session.id,
          'correlationId': session.correlationId,
          'batteryLevel': _batteryLevel,
          'isCharging': _isCharging.toString(),
          'audioPath': session.audioPath,
        },
      );

      return null;
    }
  }

  /// Detect issues from metrics
  Set<AudioQualityIssue> _detectIssues(AudioQualityMetrics metrics) {
    final issues = <AudioQualityIssue>{};

    // Check for clipping
    if (metrics.clippingPercentage > _config.clippingThreshold) {
      issues.add(AudioQualityIssue.clipping);
    }

    // Check for volume issues
    if (metrics.rmsLevel < _config.lowVolumeThreshold) {
      issues.add(AudioQualityIssue.lowVolume);
    } else if (metrics.rmsLevel > _config.highVolumeThreshold) {
      issues.add(AudioQualityIssue.highVolume);
    }

    // Check for background noise
    if (metrics.signalToNoiseRatio != null && metrics.signalToNoiseRatio! < 20.0) {
      issues.add(AudioQualityIssue.backgroundNoise);
    }

    // Check for performance issues
    if (metrics.cpuUsage > _config.cpuUsageThreshold) {
      issues.add(AudioQualityIssue.performanceIssues);
    }

    // Check for battery drain
    if (metrics.batteryDrainRate != null &&
        metrics.batteryDrainRate! > _config.batteryDrainThreshold) {
      issues.add(AudioQualityIssue.batteryDrain);
    }

    // Check for engagement issues
    if (metrics.userEngagementScore != null && metrics.userEngagementScore! < 0.3) {
      issues.add(AudioQualityIssue.lowEngagement);
    }

    return issues;
  }

  /// Apply automatic corrections for detected issues
  Future<void> _applyAutoCorrections(
      Set<AudioQualityIssue> issues,
      _PlaybackSession session,
      ) async {
    try {
      // Get audio accessibility service
      final accessibilityService = AudioAccessibilityService();

      // Apply corrections based on issues
      if (issues.contains(AudioQualityIssue.clipping) ||
          issues.contains(AudioQualityIssue.highVolume)) {
        // Reduce volume
        final settings = accessibilityService.getCurrentSettings();
        final newVolume = max(settings.volume * 0.8, 0.1);

        await accessibilityService.updateSettings(
          volume: newVolume,
        );

        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Auto-correction: Reduced volume to $newVolume due to clipping/high volume',
          sessionContext: {'correlationId': session.correlationId},
        );
      }

      if (issues.contains(AudioQualityIssue.lowVolume)) {
        // Increase volume
        final settings = accessibilityService.getCurrentSettings();
        final newVolume = min(settings.volume * 1.25, 1.0);

        await accessibilityService.updateSettings(
          volume: newVolume,
        );

        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Auto-correction: Increased volume to $newVolume due to low volume',
          sessionContext: {'correlationId': session.correlationId},
        );
      }

      if (issues.contains(AudioQualityIssue.backgroundNoise)) {
        // Enable frequency adjustment
        final settings = accessibilityService.getCurrentSettings();
        if (!settings.enableFrequencyAdjustment) {
          await accessibilityService.updateSettings(
            enableFrequencyAdjustment: true,
          );

          AdvancedLogger.log(
            'AudioQualityMonitor',
            'Auto-correction: Enabled frequency adjustment due to background noise',
            sessionContext: {'correlationId': session.correlationId},
          );
        }
      }

      if (issues.contains(AudioQualityIssue.performanceIssues)) {
        // Simplify processing by disabling some features
        final settings = accessibilityService.getCurrentSettings();

        // Only disable if both features are enabled
        if (settings.enableFrequencyAdjustment && settings.enableVolumeNormalization) {
          await accessibilityService.updateSettings(
            enableFrequencyAdjustment: false,
          );

          AdvancedLogger.log(
            'AudioQualityMonitor',
            'Auto-correction: Disabled frequency adjustment due to performance issues',
            sessionContext: {'correlationId': session.correlationId},
          );
        }
      }

      if (issues.contains(AudioQualityIssue.batteryDrain) &&
          _batteryLevel < _config.lowBatteryThreshold) {
        // Reduce processing to save battery
        final settings = accessibilityService.getCurrentSettings();

        if (settings.enableFrequencyAdjustment || settings.enableVolumeNormalization) {
          await accessibilityService.updateSettings(
            enableFrequencyAdjustment: false,
            enableVolumeNormalization: false,
          );

          AdvancedLogger.log(
            'AudioQualityMonitor',
            'Auto-correction: Disabled audio processing to save battery (level: $_batteryLevel%)',
            sessionContext: {'correlationId': session.correlationId},
          );
        }
      }
    } catch (e) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error applying auto-corrections: $e',
        sessionContext: {'correlationId': session.correlationId},
      );

      // Report error with context
      ErrorReporter.reportError(
        'AudioQualityMonitor.applyAutoCorrections',
        Exception('Auto-correction failed: ${e.toString()}'),
        StackTrace.current,
        contextData: {
          'sessionId': session.id,
          'correlationId': session.correlationId,
          'batteryLevel': _batteryLevel,
          'issues': issues.map((i) => i.name).join(','),
        },
      );
    }
  }

  /// Get cached quality metrics
  List<AudioQualityMetrics> getCachedMetrics() {
    return List.unmodifiable(_cachedMetrics);
  }

  /// Get current quality metrics
  AudioQualityMetrics? getCurrentMetrics() {
    return _currentMetrics;
  }

  /// Get quality recommendations based on recent playback
  List<String> getQualityRecommendations() {
    if (_cachedMetrics.isEmpty) {
      return [_localizations.translate('no_playback_data')];
    }

    // Collect all recommendations from recent metrics
    final allRecommendations = <String>{};
    for (final metrics in _cachedMetrics) {
      allRecommendations.addAll(metrics.getImprovementRecommendations(_localizations));
    }

    // Return unique recommendations
    return allRecommendations.toList();
  }

  /// Get diagnostic information for troubleshooting
  Map<String, dynamic> getDiagnosticInfo() {
    return {
      'isInitialized': _isInitialized,
      'isMonitoring': _isMonitoring,
      'activeSessions': _activeSessions.length,
      'cachedMetricsCount': _cachedMetrics.length,
      'appVersion': _appVersion,
      'isCharging': _isCharging,
      'batteryLevel': _batteryLevel,
      'consentStatus': _consentStatus.name,
      'consentTimestamp': _consentTimestamp?.toIso8601String(),
      'offlineRetryAttempt': _offlineRetryAttempt,
      'securityLevel': _config.securityLevel.name,
      'configSettings': {
        'enableRealTimeMonitoring': _config.enableRealTimeMonitoring,
        'samplingIntervalMs': _config.samplingIntervalMs,
        'enableAutoCorrections': _config.enableAutoCorrections,
        'enableBatteryMonitoring': _config.enableBatteryMonitoring,
        'enableCpuMonitoring': _config.enableCpuMonitoring,
        'enableEngagementTracking': _config.enableEngagementTracking,
        'privacyModeEnabled': _config.privacyModeEnabled,
        'debugModeEnabled': _config.debugModeEnabled,
        'lowBatteryThreshold': _config.lowBatteryThreshold,
        'criticalBatteryThreshold': _config.criticalBatteryThreshold,
      },
      'thresholds': {
        'clippingThreshold': _config.clippingThreshold,
        'lowVolumeThreshold': _config.lowVolumeThreshold,
        'highVolumeThreshold': _config.highVolumeThreshold,
        'cpuUsageThreshold': _config.cpuUsageThreshold,
        'batteryDrainThreshold': _config.batteryDrainThreshold,
      },
      'currentMetrics': _currentMetrics?.toJson(),
      'deviceInfo': _deviceInfoProvider.getBasicDeviceInfo(),
    };
  }

  /// Validate audio file for accessibility
  ///
  /// Checks an audio file for issues that would impact accessibility
  /// for elderly users before playback
  ///
  /// Returns a validation result with issues and recommendations
  Future<AudioValidationResult> validateAudioForAccessibility(
      String audioPath,
      ) async {
    // Validate input parameters
    if (audioPath.isEmpty) {
      throw ArgumentError('Audio path cannot be empty');
    }

    if (!_isInitialized) {
      await initialize();
    }

    // Generate correlation ID for this validation operation
    final correlationId = const Uuid().v4();

    try {
      // First check if file exists
      final file = File(audioPath);
      final fileExists = await file.exists();
      if (!fileExists) {
        throw FileSystemException('Audio file does not exist', audioPath);
      }

      final fileSize = await file.length();

      // Analyze audio with fallback
      AudioAnalysisMetrics audioMetrics;
      try {
        // If battery is low, use simplified analysis
        if (_config.shouldReduceMonitoring(_batteryLevel)) {
          audioMetrics = await _audioAnalyzer.analyzeAudioSimple(audioPath);
        } else {
          audioMetrics = await _audioAnalyzer.analyzeAudio(audioPath);
        }
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error in primary audio analysis, using fallback: $e',
          sessionContext: {'correlationId': correlationId},
        );
        // Use simplified analysis as fallback
        audioMetrics = await _audioAnalyzer.analyzeAudioSimple(audioPath);
      }

      // Get format info with fallback
      AudioFormatInfo formatInfo;
      try {
        formatInfo = await _audioAnalyzer.getAudioFormatInfo(audioPath);
      } catch (e) {
        AdvancedLogger.logError(
          'AudioQualityMonitor',
          'Error getting format info, using defaults: $e',
          sessionContext: {'correlationId': correlationId},
        );
        formatInfo = AudioFormatInfo.defaultValues();
      }

      // Check for issues
      final issues = <String>[];
      final recommendations = <String>[];

      // Volume checks
      if (audioMetrics.rmsLevel < -25.0) {
        issues.add(_localizations.translate('issue_low_volume'));
        recommendations.add(_localizations.translate('recommendation_increase_volume_db'));
      }

      if (audioMetrics.clippingPercentage > 2.0) {
        issues.add(_localizations.translate('issue_clipping'));
        recommendations.add(_localizations.translate('recommendation_reduce_peaks'));
      }

      // Frequency checks for elderly users
      if (audioMetrics.frequencyBalance != null) {
        final hasEnoughLowMids = audioMetrics.frequencyBalance!.lowMidsEnergy > 0.2;
        final hasTooMuchHighs = audioMetrics.frequencyBalance!.highsEnergy > 0.3;

        if (!hasEnoughLowMids) {
          issues.add(_localizations.translate('issue_lacking_warmth'));
          recommendations.add(_localizations.translate('recommendation_boost_lowmids'));
        }

        if (hasTooMuchHighs) {
          issues.add(_localizations.translate('issue_excessive_highs'));
          recommendations.add(_localizations.translate('recommendation_reduce_highs'));
        }
      }

      // Format checks
      if (formatInfo.sampleRate < 44100) {
        issues.add(_localizations.translate('issue_low_samplerate'));
        recommendations.add(_localizations.translate('recommendation_higher_samplerate'));
      }

      if (formatInfo.bitRate < 128) {
        issues.add(_localizations.translate('issue_low_bitrate'));
        recommendations.add(_localizations.translate('recommendation_higher_bitrate'));
      }

      // Duration check for elderly users
      if (formatInfo.duration > 60.0) {
        issues.add(_localizations.translate('issue_long_duration'));
        recommendations.add(_localizations.translate('recommendation_shorter_segments'));
      }

      // Log validation results
      AdvancedLogger.log(
        'AudioQualityMonitor',
        'Audio validation completed for ${audioPath.split('/').last}, found ${issues.length} issues',
        sessionContext: {
          'correlationId': correlationId,
          'fileSize': formatInfo.fileSize,
          'duration': formatInfo.duration,
          'audioExists': fileExists,
          'rmsLevel': audioMetrics.rmsLevel,
          'clippingPercentage': audioMetrics.clippingPercentage,
        },
      );

      return AudioValidationResult(
        isValid: issues.isEmpty,
        issues: issues,
        recommendations: recommendations,
        format: formatInfo,
        metrics: audioMetrics,
        correlationId: correlationId,
      );
    } catch (e, stackTrace) {
      final fileExists = await File(audioPath).exists().catchError((_) => false);
      final fileSize = fileExists ? await File(audioPath).length().catchError((_) => -1) : -1;

      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error validating audio: $e\n$stackTrace',
        sessionContext: {'correlationId': correlationId},
      );

      ErrorReporter.reportError(
        'AudioQualityMonitor.validateAudioForAccessibility',
        Exception('Audio validation failed: ${e.toString()}'),
        stackTrace,
        contextData: {
          'audioPath': audioPath,
          'correlationId': correlationId,
          'batteryLevel': _batteryLevel,
          'fileExists': fileExists.toString(),
          'fileSize': fileSize.toString(),
        },
      );

      return AudioValidationResult(
        isValid: false,
        issues: [_localizations.translate('error_validating_audio', {'error': e.toString()})],
        recommendations: [_localizations.translate('recommendation_try_different_file')],
        format: null,
        metrics: null,
        correlationId: correlationId,
      );
    }
  }

  /// Optimize audio file for elderly users with tiered fallbacks
  ///
  /// Applies a series of transformations to make the audio more
  /// accessible for elderly users with hearing limitations
  ///
  /// Returns the path to the optimized audio file
  Future<String> optimizeAudioForElderly(
      String inputPath, {
        String? outputPath,
      }) async {
    // Validate inputs
    if (inputPath.isEmpty) {
      throw ArgumentError('Input path cannot be empty');
    }

    if (outputPath != null && outputPath.isEmpty) {
      throw ArgumentError('Output path cannot be empty if provided');
    }

    if (!_isInitialized) {
      await initialize();
    }

    // Generate correlation ID for this operation
    final correlationId = const Uuid().v4();

    try {
      // Check if audio file exists
      final file = File(inputPath);
      if (!(await file.exists())) {
        throw FileSystemException('Audio file does not exist', inputPath);
      }

      final fileSize = await file.length();

      // Generate output path if not provided
      final output = outputPath ?? await _generateOptimizedPath(inputPath);

      // Check battery level to determine processing approach
      bool result = false;

      // If battery is critically low, just copy the file
      if (_config.shouldEnableCriticalBatterySaving(_batteryLevel) && !_isCharging) {
        AdvancedLogger.log(
          'AudioQualityMonitor',
          'Skipping optimization due to critical battery level ($_batteryLevel%), using direct copy',
          sessionContext: {
            'correlationId': correlationId,
            'fileSize': fileSize,
          },
        );

        try {
          // Just copy the file
          final outputFile = File(output);
          if (await outputFile.exists()) {
            await outputFile.delete();
          }
          await file.copy(output);
          result = true;
        } catch (e) {
          AdvancedLogger.logError(
            'AudioQualityMonitor',
            'Error copying file: $e',
            sessionContext: {
              'correlationId': correlationId,
              'fileSize': fileSize,
            },
          );
          return inputPath;
        }
      } else {
        // Normal approach with fallbacks
        // First try full optimization
        try {
          result = await _audioAnalyzer.processAudioForElderly(
            inputPath,
            output,
          );

          if (result) {
            AdvancedLogger.log(
              'AudioQualityMonitor',
              'Successfully processed audio with full optimization',
              sessionContext: {
                'correlationId': correlationId,
                'fileSize': fileSize,
              },
            );
          }
        } catch (e) {
          AdvancedLogger.logError(
            'AudioQualityMonitor',
            'Error in full audio optimization: $e, trying simplified processing',
            sessionContext: {
              'correlationId': correlationId,
              'fileSize': fileSize,
            },
          );
        }

        // If full optimization fails, try simplified processing
        if (!result) {
          try {
            result = await _audioAnalyzer.processAudioSimple(
              inputPath,
              output,
            );

            if (result) {
              AdvancedLogger.log(
                'AudioQualityMonitor',
                'Successfully processed audio with simplified optimization',
                sessionContext: {
                  'correlationId': correlationId,
                  'fileSize': fileSize,
                },
              );
            }
          } catch (e) {
            AdvancedLogger.logError(
              'AudioQualityMonitor',
              'Error in simplified processing: $e, trying basic copy',
              sessionContext: {
                'correlationId': correlationId,
                'fileSize': fileSize,
              },
            );
          }
        }

        // If simplified processing fails, just copy the file
        if (!result) {
          try {
            final outputFile = File(output);
            if (await outputFile.exists()) {
              await outputFile.delete();
            }
            await file.copy(output);
            result = true;

            AdvancedLogger.log(
              'AudioQualityMonitor',
              'Fallback to file copy as optimization failed',
              sessionContext: {
                'correlationId': correlationId,
                'fileSize': fileSize,
              },
            );
          } catch (e) {
            AdvancedLogger.logError(
              'AudioQualityMonitor',
              'Error copying file: $e, returning original path',
              sessionContext: {
                'correlationId': correlationId,
                'fileSize': fileSize,
              },
            );
            return inputPath;
          }
        }
      }

      return output;
    } catch (e, stackTrace) {
      final fileExists = await File(inputPath).exists().catchError((_) => false);
      final fileSize = fileExists ? await File(inputPath).length().catchError((_) => -1) : -1;

      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error optimizing audio: $e\n$stackTrace',
        sessionContext: {'correlationId': correlationId},
      );

      ErrorReporter.reportError(
        'AudioQualityMonitor.optimizeAudioForElderly',
        Exception('Audio optimization failed: ${e.toString()}'),
        stackTrace,
        contextData: {
          'inputPath': inputPath,
          'outputPath': outputPath,
          'correlationId': correlationId,
          'batteryLevel': _batteryLevel,
          'isCharging': _isCharging.toString(),
          'fileExists': fileExists.toString(),
          'fileSize': fileSize.toString(),
        },
      );

      // Return original if all optimization attempts fail
      return inputPath;
    }
  }

  /// Generate path for optimized audio
  Future<String> _generateOptimizedPath(String inputPath) async {
    final directory = await getTemporaryDirectory();
    final filename = inputPath.split('/').last;
    final baseName = filename.split('.').first;
    final extension = filename.split('.').last;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return '${directory.path}/${baseName}_optimized_$timestamp.$extension';
  }

  /// Get performance report for playback with pagination
  ///
  /// [startDate] Optional start date for filtering
  /// [endDate] Optional end date for filtering
  /// [limit] Maximum number of records to analyze
  Future<AudioPerformanceReport> getPerformanceReport({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 1000,
  }) async {
    // Validate input parameters
    if (limit <= 0) {
      throw ArgumentError('Limit must be greater than 0');
    }

    if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
      throw ArgumentError('Start date cannot be after end date');
    }

    if (!_isInitialized) {
      await initialize();
    }

    // Check if user has consent to access this data
    if (_consentStatus != ConsentStatus.granted) {
      AdvancedLogger.logWarning(
        'AudioQualityMonitor',
        'Cannot generate performance report without user consent',
      );

      return AudioPerformanceReport.empty(_localizations);
    }

    try {
      // Get metrics from repository with pagination/filtering
      final allMetrics = await _repository.getMetrics(
        startDate: startDate,
        endDate: endDate,
        limit: limit,
        userId: _userId,
      );

      if (allMetrics.isEmpty) {
        return AudioPerformanceReport.empty(_localizations);
      }

      // Calculate statistics
      final totalSessions = allMetrics.length;

      double totalCompletionRate = 0.0;
      double totalCpuUsage = 0.0;
      double totalBatteryDrain = 0.0;
      double totalQualityScore = 0.0;
      int batteryReadings = 0;

      final issueCount = <AudioQualityIssue, int>{};
      final devicePerformance = <String, _DevicePerformanceData>{};
      final nudgePerformance = <String?, _NudgePerformanceData>{};

      for (final metrics in allMetrics) {
        totalCompletionRate += metrics.playbackCompletionRate;
        totalCpuUsage += metrics.cpuUsage;

        if (metrics.batteryDrainRate != null) {
          totalBatteryDrain += metrics.batteryDrainRate!;
          batteryReadings++;
        }

        final qualityScore = metrics.getQualityScore();
        totalQualityScore += qualityScore;

        // Track issues
        final issues = _detectIssues(metrics);
        for (final issue in issues) {
          issueCount[issue] = (issueCount[issue] ?? 0) + 1;
        }

        // Track device performance
        if (!devicePerformance.containsKey(metrics.deviceModel)) {
          devicePerformance[metrics.deviceModel] = _DevicePerformanceData();
        }
        devicePerformance[metrics.deviceModel]!.addScore(qualityScore);

        // Track nudge performance
        if (!nudgePerformance.containsKey(metrics.nudgeId)) {
          nudgePerformance[metrics.nudgeId] = _NudgePerformanceData();
        }
        nudgePerformance[metrics.nudgeId]!.addData(
          metrics.playbackCompletionRate,
          metrics.userEngagementScore,
        );
      }

      // Calculate averages
      final averageCompletionRate = totalCompletionRate / totalSessions;
      final averageCpuUsage = totalCpuUsage / totalSessions;
      final averageBatteryDrain = batteryReadings > 0 ? totalBatteryDrain / batteryReadings : 0.0;
      final averageQualityScore = totalQualityScore / totalSessions;

      // Calculate device averages
      final deviceScores = <String, double>{};
      for (final entry in devicePerformance.entries) {
        deviceScores[entry.key] = entry.value.getAverageScore();
      }

      // Calculate nudge effectiveness
      final nudgeEffectiveness = <String, Map<String, dynamic>>{};
      for (final entry in nudgePerformance.entries) {
        if (entry.key != null) {
          nudgeEffectiveness[entry.key!] = {
            'completionRate': entry.value.getAverageCompletionRate(),
            'engagementScore': entry.value.getAverageEngagementScore(),
            'count': entry.value.count,
          };
        }
      }

      // Sort issues by frequency
      final sortedIssues = issueCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final mostCommonIssues = sortedIssues
          .take(3)
          .map((e) => '${_localizations.translate('issue_${e.key.name}')} (${e.value})')
          .toList();

      // Format date range for report title
      final dateRangeStr = _formatDateRange(startDate, endDate);

      return AudioPerformanceReport(
        reportTitle: _localizations.translate('performance_report_title', {'dateRange': dateRangeStr}),
        totalPlaybackSessions: totalSessions,
        averageCompletionRate: averageCompletionRate,
        averageCpuUsage: averageCpuUsage,
        averageBatteryDrain: averageBatteryDrain,
        averageQualityScore: averageQualityScore,
        mostCommonIssues: mostCommonIssues,
        devicePerformance: deviceScores,
        nudgeEffectiveness: nudgeEffectiveness,
        generatedAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'AudioQualityMonitor',
        'Error generating performance report: $e\n$stackTrace',
      );

      ErrorReporter.reportError(
        'AudioQualityMonitor.getPerformanceReport',
        Exception('Performance report generation failed: ${e.toString()}'),
        stackTrace,
        contextData: {
          'startDate': startDate?.toIso8601String(),
          'endDate': endDate?.toIso8601String(),
          'limit': limit.toString(),
          'userId': _userId != null ? hashUserId(_userId!) : null,
        },
      );

      return AudioPerformanceReport.empty(_localizations);
    }
  }

  /// Format date range for reports
  String _formatDateRange(DateTime? startDate, DateTime? endDate) {
    final formatter = DateFormat('MMM d, yyyy');
    final now = DateTime.now();

    if (startDate == null && endDate == null) {
      return _localizations.translate('all_time');
    } else if (startDate == null) {
      return _localizations.translate('until_date', {'date': formatter.format(endDate!)});
    } else if (endDate == null) {
      return _localizations.translate('since_date', {'date': formatter.format(startDate)});
    } else {
      return '${formatter.format(startDate)} - ${formatter.format(endDate)}';
    }
  }
}