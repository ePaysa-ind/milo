// File: lib/services/background_task_registrar.dart
// Copyright (c) 2025 Milo App. All rights reserved.
// Version: 1.3.0
// This file is part of the Milo therapeutic nudge system.

import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:synchronized/synchronized.dart';
import 'package:get_it/get_it.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../utils/advanced_logger.dart';
import '../utils/config.dart';
import '../models/nudge_model.dart';
import '../theme/app_theme.dart';
import 'nudge_trigger_handler.dart';
import 'nudge_service.dart';
import 'notification_service.dart';

/// Platform-specific implementation for device unlock detection
/// Separated from main implementation for better focus and testing
class PlatformUnlockDetector {
  static const MethodChannel _methodChannel = MethodChannel('com.milo.unlock_detector');
  static const EventChannel _eventChannel = EventChannel('com.milo.unlock_events');
  static StreamSubscription? _unlockSubscription;
  static bool _isInitialized = false;
  static final AdvancedLogger _logger = AdvancedLogger();

  /// Initialize the platform-specific unlock detection
  static Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Check if platform code is available
      final bool isSupported = await _methodChannel.invokeMethod('isUnlockDetectionSupported');

      if (!isSupported) {
        _logger.warn('Platform-specific unlock detection not supported on this device');
        return false;
      }

      // Request necessary permissions
      final bool permissionsGranted = await _methodChannel.invokeMethod('requestUnlockPermissions');

      if (!permissionsGranted) {
        _logger.warn('Platform-specific unlock permissions denied');
        return false;
      }

      _isInitialized = true;
      return true;
    } on PlatformException catch (e) {
      _logger.error('Failed to initialize platform unlock detection', e);
      return false;
    } catch (e) {
      _logger.error('Unexpected error initializing platform unlock detection', e);
      return false;
    }
  }

  /// Start listening for device unlock events
  static Future<bool> startListening(Function(DateTime) onUnlockDetected) async {
    if (!_isInitialized && !await initialize()) {
      return false;
    }

    try {
      // Cancel any existing subscription
      await stopListening();

      // Start native detector service
      final bool started = await _methodChannel.invokeMethod('startUnlockDetection');

      if (!started) {
        _logger.warn('Failed to start native unlock detection service');
        return false;
      }

      // Listen for unlock events
      _unlockSubscription = _eventChannel.receiveBroadcastStream().listen(
              (dynamic event) {
            try {
              if (event is Map) {
                final int timestamp = event['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
                onUnlockDetected(DateTime.fromMillisecondsSinceEpoch(timestamp));
              }
            } catch (e) {
              _logger.error('Error processing unlock event', e);
            }
          },
          onError: (dynamic error) {
            _logger.error('Error from unlock event stream', error);
          }
      );

      _logger.info('Platform-specific unlock detection started');
      return true;
    } catch (e) {
      _logger.error('Failed to start unlock detection', e);
      return false;
    }
  }

  /// Stop listening for device unlock events
  static Future<void> stopListening() async {
    try {
      if (_unlockSubscription != null) {
        await _unlockSubscription!.cancel();
        _unlockSubscription = null;
      }

      if (_isInitialized) {
        await _methodChannel.invokeMethod('stopUnlockDetection');
      }
    } catch (e) {
      _logger.error('Error stopping unlock detection', e);
    }
  }

  /// Check if unlock detection is currently running
  static Future<bool> isRunning() async {
    if (!_isInitialized) return false;

    try {
      return await _methodChannel.invokeMethod('isUnlockDetectionRunning');
    } catch (e) {
      _logger.error('Error checking if unlock detection is running', e);
      return false;
    }
  }

  /// Get the last unlock time if available
  static Future<DateTime?> getLastUnlockTime() async {
    if (!_isInitialized) return null;

    try {
      final int? timestamp = await _methodChannel.invokeMethod('getLastUnlockTimestamp');
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      _logger.error('Error getting last unlock time', e);
      return null;
    }
  }
}

/// Configuration provider for dynamically loading settings
/// from Firebase Remote Config or local defaults
class NudgeTaskConfiguration {
  // Default values - used when Remote Config is not available
  static const int DEFAULT_MORNING_HOUR = 8;
  static const int DEFAULT_NOON_HOUR = 13;
  static const int DEFAULT_EVENING_HOUR = 19;
  static const int DEFAULT_UNLOCK_CHECK_MINUTES = 30;
  static const int DEFAULT_MAINTENANCE_HOURS = 12;
  static const int DEFAULT_RECOVERY_HOURS = 2;
  static const int DEFAULT_MAX_DAILY_NUDGES = 3;
  static const int DEFAULT_MIN_MINUTES_BETWEEN_NUDGES = 120;
  static const int DEFAULT_NUDGE_TIMEOUT_SECONDS = 60;

  // Instance for singleton pattern
  static NudgeTaskConfiguration? _instance;

  // Firebase Remote Config instance
  final FirebaseRemoteConfig _remoteConfig;

  // Logger
  final AdvancedLogger _logger;

  // Last fetch time
  DateTime _lastFetchTime = DateTime.now().subtract(Duration(days: 1));

  // Constructor
  NudgeTaskConfiguration._(this._remoteConfig, this._logger);

  /// Get the singleton instance
  static Future<NudgeTaskConfiguration> getInstance() async {
    if (_instance == null) {
      final remoteConfig = FirebaseRemoteConfig.instance;
      final logger = AdvancedLogger();

      try {
        // Set default values
        await remoteConfig.setDefaults({
          'nudge_morning_hour': DEFAULT_MORNING_HOUR,
          'nudge_noon_hour': DEFAULT_NOON_HOUR,
          'nudge_evening_hour': DEFAULT_EVENING_HOUR,
          'nudge_unlock_check_minutes': DEFAULT_UNLOCK_CHECK_MINUTES,
          'nudge_maintenance_hours': DEFAULT_MAINTENANCE_HOURS,
          'nudge_recovery_hours': DEFAULT_RECOVERY_HOURS,
          'nudge_max_daily': DEFAULT_MAX_DAILY_NUDGES,
          'nudge_min_minutes_between': DEFAULT_MIN_MINUTES_BETWEEN_NUDGES,
          'nudge_timeout_seconds': DEFAULT_NUDGE_TIMEOUT_SECONDS,
        });

        // Set fetch interval to 6 hours
        await remoteConfig.setConfigSettings(RemoteConfigSettings(
          fetchTimeout: Duration(minutes: 1),
          minimumFetchInterval: Duration(hours: 6),
        ));

        // Fetch for the first time
        await remoteConfig.fetchAndActivate();

        _instance = NudgeTaskConfiguration._(remoteConfig, logger);
      } catch (e) {
        logger.error('Failed to initialize Remote Config, using defaults', e);
        _instance = NudgeTaskConfiguration._(remoteConfig, logger);
      }
    }

    return _instance!;
  }

  /// Refresh config values from Firebase
  Future<bool> refreshConfig() async {
    // Only fetch if more than 6 hours since last fetch
    final now = DateTime.now();
    if (now.difference(_lastFetchTime) < Duration(hours: 6)) {
      return false;
    }

    try {
      final bool updated = await _remoteConfig.fetchAndActivate();
      _lastFetchTime = now;
      _logger.info('Remote config ${updated ? "updated" : "already up to date"}');
      return updated;
    } catch (e) {
      _logger.error('Failed to refresh remote config', e);
      return false;
    }
  }

  // Configuration getters
  int get morningHour => _remoteConfig.getInt('nudge_morning_hour');
  int get noonHour => _remoteConfig.getInt('nudge_noon_hour');
  int get eveningHour => _remoteConfig.getInt('nudge_evening_hour');
  Duration get unlockCheckFrequency =>
      Duration(minutes: _remoteConfig.getInt('nudge_unlock_check_minutes'));
  Duration get maintenanceFrequency =>
      Duration(hours: _remoteConfig.getInt('nudge_maintenance_hours'));
  Duration get recoveryFrequency =>
      Duration(hours: _remoteConfig.getInt('nudge_recovery_hours'));
  int get maxDailyNudges => _remoteConfig.getInt('nudge_max_daily');
  Duration get minTimeBetweenNudges =>
      Duration(minutes: _remoteConfig.getInt('nudge_min_minutes_between'));
  Duration get nudgeTimeout =>
      Duration(seconds: _remoteConfig.getInt('nudge_timeout_seconds'));

  // Get time window hours
  Map<TimeWindow, int> get timeWindowHours => {
    TimeWindow.morning: morningHour,
    TimeWindow.midday: noonHour,
    TimeWindow.evening: eveningHour,
  };

  // For testing: reset to default values
  Future<void> resetToDefaults() async {
    try {
      await _remoteConfig.setDefaults({
        'nudge_morning_hour': DEFAULT_MORNING_HOUR,
        'nudge_noon_hour': DEFAULT_NOON_HOUR,
        'nudge_evening_hour': DEFAULT_EVENING_HOUR,
        'nudge_unlock_check_minutes': DEFAULT_UNLOCK_CHECK_MINUTES,
        'nudge_maintenance_hours': DEFAULT_MAINTENANCE_HOURS,
        'nudge_recovery_hours': DEFAULT_RECOVERY_HOURS,
        'nudge_max_daily': DEFAULT_MAX_DAILY_NUDGES,
        'nudge_min_minutes_between': DEFAULT_MIN_MINUTES_BETWEEN_NUDGES,
        'nudge_timeout_seconds': DEFAULT_NUDGE_TIMEOUT_SECONDS,
      });
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      _logger.error('Failed to reset remote config to defaults', e);
    }
  }
}

/// Background task callback utilities
/// Moved to dedicated class for better organization and separation of concerns
class BackgroundTaskUtils {
  // Static counter to track and limit error logging frequency
  static int _errorCount = 0;
  static DateTime _lastErrorReset = DateTime.now();
  static const int _ERROR_LIMIT = 10; // Maximum errors to log in time window
  static const Duration _ERROR_RESET_WINDOW = Duration(hours: 1);

  // Track messages for deduplication
  static final Set<String> _processedMessageIds = {};
  static final Lock _messageProcessingLock = Lock();

  /// Entry point for background tasks execution
  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((taskName, inputData) async {
      // Initialize required services
      final prefs = await SharedPreferences.getInstance();
      final logger = AdvancedLogger();

      try {
        logger.info('Background task started: $taskName');

        // Handle different task types
        switch (taskName) {
          case BackgroundTaskRegistrar.MORNING_NUDGE_TASK:
            await handleScheduledNudge(TimeWindow.morning, prefs, logger);
            break;
          case BackgroundTaskRegistrar.NOON_NUDGE_TASK:
            await handleScheduledNudge(TimeWindow.midday, prefs, logger);
            break;
          case BackgroundTaskRegistrar.EVENING_NUDGE_TASK:
            await handleScheduledNudge(TimeWindow.evening, prefs, logger);
            break;
          case BackgroundTaskRegistrar.UNLOCK_DETECTION_TASK:
            await checkForDeviceUnlocks(prefs, logger);
            break;
          case BackgroundTaskRegistrar.MAINTENANCE_TASK:
            await performMaintenance(prefs, logger);
            break;
          case BackgroundTaskRegistrar.RECOVERY_TASK:
            await performRecovery(prefs, logger);
            break;
          default:
            logger.warn('Unknown task type: $taskName');
            break;
        }

        logger.info('Background task completed: $taskName');
        return true;
      } catch (e, stack) {
        // Apply error rate limiting to prevent log spam
        if (_shouldLogError()) {
          logger.error('Background task failed: $taskName', e, stack);
        }

        // Record failure for recovery mechanism
        await _recordTaskFailure(taskName, prefs, logger);

        return false;
      }
    });
  }

  /// Check if error should be logged based on rate limiting
  static bool _shouldLogError() {
    final now = DateTime.now();

    // Reset counter if we're outside the window
    if (now.difference(_lastErrorReset) > _ERROR_RESET_WINDOW) {
      _errorCount = 0;
      _lastErrorReset = now;
      return true;
    }

    // Increment counter and check if we should log
    _errorCount++;
    return _errorCount <= _ERROR_LIMIT;
  }

  /// Record task failure for recovery mechanism
  static Future<void> _recordTaskFailure(
      String taskName,
      SharedPreferences prefs,
      AdvancedLogger logger
      ) async {
    try {
      final int failureCount = prefs.getInt('${taskName}_failures') ?? 0;
      await prefs.setInt('${taskName}_failures', failureCount + 1);
      await prefs.setInt('${taskName}_last_failure', DateTime.now().millisecondsSinceEpoch);

      logger.info('Recorded task failure: $taskName, count: ${failureCount + 1}');

      // Trigger recovery if failures exceed threshold
      if (failureCount >= 3) {
        await prefs.setBool('recovery_needed', true);
      }
    } catch (e) {
      // Just log, don't throw from error handler
      logger.error('Failed to record task failure', e);
    }
  }

  /// Helper function to handle scheduled nudge delivery in background
  static Future<void> handleScheduledNudge(
      TimeWindow window,
      SharedPreferences prefs,
      AdvancedLogger logger
      ) async {
    final String userId = prefs.getString('userId') ?? '';
    if (userId.isEmpty) {
      logger.warn('Cannot deliver nudge: No authenticated user');
      return;
    }

    final bool nudgesEnabled = prefs.getBool('nudgesEnabled') ?? false;
    final List<String> enabledWindowsStr = prefs.getStringList('enabledTimeWindows') ?? [];

    // Convert string window names to TimeWindow values for comparison
    final List<TimeWindow> enabledWindows = enabledWindowsStr
        .map((name) => TimeWindow.values.firstWhere(
          (w) => w.name == name,
      orElse: () => TimeWindow.morning,
    ))
        .toList();

    if (!nudgesEnabled || !enabledWindows.contains(window)) {
      logger.info('Skipping ${window.name} nudge: Disabled by user settings');
      return;
    }

    // Load config for timeout values
    final config = await NudgeTaskConfiguration.getInstance();

    // Check daily limit
    final int today = _getDayKey();
    final int dailyCount = prefs.getInt('nudge_count_$today') ?? 0;

    if (dailyCount >= config.maxDailyNudges) {
      logger.info('Skipping ${window.name} nudge: Daily limit reached (${dailyCount}/${config.maxDailyNudges})');
      return;
    }

    // Check for duplicates - don't send if already delivered recently
    final int lastDeliveryTime = prefs.getInt('last_${window.name}_delivery') ?? 0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int minimumInterval = config.minTimeBetweenNudges.inMilliseconds;

    if (now - lastDeliveryTime < minimumInterval) {
      logger.info('Skipping ${window.name} nudge: Already delivered recently');
      return;
    }

    // Generate unique message ID for deduplication and acknowledgement
    final String messageId = '${window.name}_${now}_${userId.hashCode}_${DateTime.now().microsecondsSinceEpoch}';

    // Handle nudge delivery through main app
    final sendPort = IsolateNameServer.lookupPortByName('nudge_delivery_port');
    if (sendPort != null) {
      // Send message with sequence number for acknowledgement
      final completer = Completer<bool>();
      final messageReceived = await _sendWithAcknowledgement(
          sendPort,
          {
            'action': 'deliver_nudge',
            'window': window.name,
            'userId': userId,
            'timestamp': now,
            'messageId': messageId,
            'sequence': _getNextSequenceNumber()
          },
          logger,
          completer,
          timeout: config.nudgeTimeout
      );

      // Wait for acknowledgement with timeout
      bool delivered = false;
      try {
        delivered = messageReceived;
        logger.info('Requested ${window.name} nudge delivery via isolate: ${delivered ? "Acknowledged" : "Timed out"}');
      } catch (e) {
        logger.warn('Nudge delivery request failed: ${e.toString()}');
      }

      // Only record successful delivery
      if (delivered) {
        await prefs.setInt('last_${window.name}_delivery', now);
        await prefs.setString('last_delivery_id', messageId);
        await _incrementDailyCount(prefs);
      } else {
        // Fallback to notification if acknowledgement timed out
        final notificationDelivered = await _deliverViaPushNotification(window, messageId, prefs, logger);
        if (notificationDelivered) {
          await _incrementDailyCount(prefs);
        }
      }
    } else {
      // Fallback to notification if app is not running
      final notificationDelivered = await _deliverViaPushNotification(window, messageId, prefs, logger);
      if (notificationDelivered) {
        await _incrementDailyCount(prefs);
      }
    }
  }

  /// Increment the daily nudge count
  static Future<void> _incrementDailyCount(SharedPreferences prefs) async {
    final int today = _getDayKey();
    final int currentCount = prefs.getInt('nudge_count_$today') ?? 0;
    await prefs.setInt('nudge_count_$today', currentCount + 1);
  }

  /// Get day key for counting daily nudges (YYYYMMDD format)
  static int _getDayKey() {
    final now = DateTime.now();
    return now.year * 10000 + now.month * 100 + now.day;
  }

  // Sequence number for message ordering
  static int _messageSequence = 0;
  static final Lock _sequenceLock = Lock();

  /// Get next message sequence number (thread-safe)
  static int _getNextSequenceNumber() {
    return _sequenceLock.synchronized(() {
      return ++_messageSequence;
    });
  }

  /// Handle delivery via push notification when app is not running
  static Future<bool> _deliverViaPushNotification(
      TimeWindow window,
      String messageId,
      SharedPreferences prefs,
      AdvancedLogger logger
      ) async {
    try {
      final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

      // Initialize notifications if needed
      const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
        requestSoundPermission: false,
        requestBadgePermission: false,
        requestAlertPermission: false,
        // Settings for better accessibility
        presentAlert: true,
        presentSound: true,
      );

      final InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await notifications.initialize(initializationSettings);

      // Prepare user-friendly notification message based on time of day
      String notificationBody;
      switch (window) {
        case TimeWindow.morning:
          notificationBody = 'Good morning! Your daily message is ready.';
          break;
        case TimeWindow.midday:
          notificationBody = 'Time for your midday check-in message.';
          break;
        case TimeWindow.evening:
          notificationBody = 'Evening reflection message available.';
          break;
        default:
          notificationBody = 'Tap to view your therapeutic message';
      }

      // Get channel ID, name and description from AppTheme
      final String channelId = AppTheme.getNotificationChannelId('nudges');
      final String channelName = AppTheme.getNotificationChannelName('nudges');
      final String channelDescription = AppTheme.getNotificationChannelDescription('nudges');

      // Get the appropriate sound for this time window
      final String soundName = AppTheme.getNotificationSoundForTimeWindow(window.name);

      // Get appropriate vibration pattern
      final List<int> vibrationPattern = AppTheme.getVibrationPattern('default');

      // Send the notification using theme settings
      await notifications.show(
        window.index,
        'Milo Therapeutic Message',
        notificationBody,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            color: AppTheme.semanticColors['info'], // Use semantic color from theme
            playSound: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList(vibrationPattern),
            visibility: NotificationVisibility.public,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: soundName,
          ),
        ),
        payload: 'nudge|${window.name}|$messageId',
      );

      // Record the delivery time
      await prefs.setInt('last_${window.name}_delivery', DateTime.now().millisecondsSinceEpoch);
      await prefs.setString('last_nudge_notification_id', messageId);

      logger.info('Scheduled ${window.name} nudge notification (app not running)');
      return true;
    } catch (e, stack) {
      logger.error('Failed to deliver notification', e, stack);
      // Don't throw, just log the error
      return false;
    }
  }

  /// Send message with acknowledgement mechanism
  static Future<bool> _sendWithAcknowledgement(
      SendPort sendPort,
      Map<String, dynamic> message,
      AdvancedLogger logger,
      Completer<bool> completer, {
        Duration timeout = const Duration(seconds: 3)
      }) async {
    try {
      return await _messageProcessingLock.synchronized(() async {
        // Add message to pending acknowledgements
        final String messageId = message['messageId'] as String;

        // Check for duplicates
        if (_processedMessageIds.contains(messageId)) {
          logger.info('Skipping duplicate message: $messageId');
          completer.complete(false);
          return false;
        }

        // Store completer for this message
        _pendingAcknowledgements[messageId] = completer;

        // Add to processed set to prevent duplicates
        _processedMessageIds.add(messageId);

        // Set size limit for processed IDs to prevent memory bloat
        if (_processedMessageIds.length > 100) {
          _processedMessageIds.remove(_processedMessageIds.first);
        }

        // Send the message
        sendPort.send(message);

        // Set up timeout
        Timer(timeout, () {
          if (!completer.isCompleted) {
            _pendingAcknowledgements.remove(messageId);
            completer.complete(false);
          }
        });

        return completer.future;
      });
    } catch (e) {
      logger.error('Failed to send message with acknowledgement', e);
      completer.complete(false);
      return false;
    }
  }

  // Static map to track pending acknowledgements
  static final Map<String, Completer<bool>> _pendingAcknowledgements = {};

  /// Process acknowledgement from main app
  static void processAcknowledgement(String messageId) {
    final completer = _pendingAcknowledgements.remove(messageId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(true);
    }
  }

  /// Helper function to check for device unlocks and potentially trigger nudges
  static Future<void> checkForDeviceUnlocks(
      SharedPreferences prefs,
      AdvancedLogger logger
      ) async {
    final bool deviceUnlockEnabled = prefs.getBool('allowDeviceUnlockTrigger') ?? false;
    if (!deviceUnlockEnabled) {
      logger.info('Device unlock detection disabled by user settings');
      return;
    }

    // Check if platform-specific detection is available and initialized
    bool unlockDetected = false;

    try {
      // First try to use the platform-specific implementation
      if (await PlatformUnlockDetector.initialize()) {
        // Get the last unlock time from the platform
        final DateTime? lastUnlockTime = await PlatformUnlockDetector.getLastUnlockTime();

        if (lastUnlockTime != null) {
          // Get the last time we processed an unlock
          final int lastProcessedTime = prefs.getInt('lastProcessedUnlock') ?? 0;
          final int unlockTimestamp = lastUnlockTime.millisecondsSinceEpoch;

          // If we have a new unlock, process it
          if (unlockTimestamp > lastProcessedTime) {
            unlockDetected = true;
            await prefs.setInt('lastProcessedUnlock', unlockTimestamp);
          }
        }
      } else {
        // Fall back to the polling approach if platform-specific is not available
        logger.warn('Using fallback polling method for unlock detection');

        final int lastCheckTimestamp = prefs.getInt('lastUnlockCheck') ?? 0;
        final int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
        final int checkInterval = 60000; // 1 minute

        // This is a simple polling approach - check every minute and assume an unlock happened
        unlockDetected = (currentTimestamp - lastCheckTimestamp >= checkInterval);

        // Update last check timestamp
        await prefs.setInt('lastUnlockCheck', currentTimestamp);
      }
    } catch (e) {
      logger.error('Error detecting device unlock state', e);
      unlockDetected = false;
    }

    if (unlockDetected) {
      logger.info('Device unlock detected, checking nudge eligibility');

      // Load configuration
      final config = await NudgeTaskConfiguration.getInstance();

      // Check daily limit
      final int today = _getDayKey();
      final int dailyCount = prefs.getInt('nudge_count_$today') ?? 0;

      if (dailyCount >= config.maxDailyNudges) {
        logger.info('Skipping unlock nudge: Daily limit reached (${dailyCount}/${config.maxDailyNudges})');
        return;
      }

      // Check if we're within rate limits
      final int lastUnlockNudgeTime = prefs.getInt('last_unlock_nudge') ?? 0;
      final int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
      final int minimumInterval = config.minTimeBetweenNudges.inMilliseconds;

      if (currentTimestamp - lastUnlockNudgeTime < minimumInterval) {
        logger.info('Skipping unlock nudge: Rate limited');
        return;
      }

      // Create message ID for deduplication
      final String messageId = 'unlock_${currentTimestamp}_${DateTime.now().microsecondsSinceEpoch}';

      // Handle potential nudge delivery through main app
      final sendPort = IsolateNameServer.lookupPortByName('nudge_delivery_port');
      if (sendPort != null) {
        final completer = Completer<bool>();
        final acknowledged = await _sendWithAcknowledgement(
            sendPort,
            {
              'action': 'device_unlock',
              'timestamp': currentTimestamp,
              'messageId': messageId,
              'sequence': _getNextSequenceNumber()
            },
            logger,
            completer,
            timeout: config.nudgeTimeout
        );

        // Record successful delivery
        try {
          if (acknowledged) {
            await prefs.setInt('last_unlock_nudge', currentTimestamp);
            await _incrementDailyCount(prefs);
          }
        } catch (e) {
          logger.warn('Failed to deliver unlock nudge: ${e.toString()}');
        }
      }
    }
  }

  /// Helper function for maintenance tasks like cleanup and optimization
  static Future<void> performMaintenance(
      SharedPreferences prefs,
      AdvancedLogger logger
      ) async {
    // Clean up old nudge delivery logs (keep last 30 days)
    final int cleanupTimestamp = DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch;

    // Clean up old daily counts
    final List<String> keys = prefs.getKeys().where((key) => key.startsWith('nudge_count_')).toList();
    for (final key in keys) {
      try {
        final int day = int.parse(key.substring(12));
        final int currentDay = _getDayKey();

        // If the key is more than 7 days old, remove it
        if (currentDay - day > 7) {
          await prefs.remove(key);
        }
      } catch (e) {
        // Invalid key format, just remove it
        await prefs.remove(key);
      }
    }

    // Refresh remote configuration
    try {
      final config = await NudgeTaskConfiguration.getInstance();
      await config.refreshConfig();
    } catch (e) {
      logger.error('Failed to refresh remote configuration', e);
    }

    // Verify consistency between SharedPreferences and Firestore settings
    // by sending a request to the main app
    final sendPort = IsolateNameServer.lookupPortByName('nudge_delivery_port');
    if (sendPort != null) {
      final completer = Completer<bool>();
      final acknowledged = await _sendWithAcknowledgement(
          sendPort,
          {
            'action': 'verify_settings',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'messageId': 'maintenance_${DateTime.now().millisecondsSinceEpoch}',
            'sequence': _getNextSequenceNumber()
          },
          logger,
          completer
      );

      try {
        if (!acknowledged) {
          // If verification fails, mark settings as potentially out of sync
          await prefs.setBool('settings_sync_needed', true);
          logger.warn('Settings verification request failed, marked for sync');
        }
      } catch (e) {
        logger.warn('Settings verification request failed: ${e.toString()}');
      }
    } else {
      // If main app isn't running, mark for verification on next startup
      await prefs.setBool('settings_sync_needed', true);
    }

    // Ensure settings are consistent
    final List<String> allTimeWindows = prefs.getStringList('enabledTimeWindows') ?? [];
    final List<String> validWindows = ['morning', 'midday', 'evening'];

    // Filter out invalid window values
    final List<String> filteredWindows = allTimeWindows
        .where((window) => validWindows.contains(window))
        .toList();

    // Only update if there's a change
    if (filteredWindows.length != allTimeWindows.length) {
      await prefs.setStringList('enabledTimeWindows', filteredWindows);
      logger.info('Corrected invalid time window settings');
    }

    // Check task failure statistics and reset if needed
    await _checkAndResetFailureCounters(prefs, logger);

    // Clean up message tracking to prevent memory leaks
    _cleanupMessageTracking();

    // Check platform-specific unlock detection
    try {
      if (await PlatformUnlockDetector.isRunning()) {
        logger.info('Platform-specific unlock detection is running');
      } else {
        logger.warn('Platform-specific unlock detection is not running');

        // Try to restart if enabled
        final bool deviceUnlockEnabled = prefs.getBool('allowDeviceUnlockTrigger') ?? false;
        if (deviceUnlockEnabled) {
          await PlatformUnlockDetector.initialize();
        }
      }
    } catch (e) {
      logger.error('Error checking platform-specific unlock detection', e);
    }

    logger.info('Maintenance: System check completed');
  }

  /// Clean up message tracking data structures
  static void _cleanupMessageTracking() {
    // If we have too many processed message IDs, clean up older ones
    if (_processedMessageIds.length > 200) {
      // Keep only the most recent 100
      final List<String> sortedIds = _processedMessageIds.toList()
        ..sort((a, b) => b.compareTo(a)); // Sort descending

      _processedMessageIds.clear();
      _processedMessageIds.addAll(sortedIds.take(100));
    }

    // Clear any stale acknowledgements
    final now = DateTime.now();
    final List<String> staleKeys = [];

    for (final key in _pendingAcknowledgements.keys) {
      final completer = _pendingAcknowledgements[key]!;
      if (!completer.isCompleted) {
        completer.complete(false);
        staleKeys.add(key);
      }
    }

    for (final key in staleKeys) {
      _pendingAcknowledgements.remove(key);
    }
  }

  /// Check and reset failure counters as part of maintenance
  static Future<void> _checkAndResetFailureCounters(
      SharedPreferences prefs,
      AdvancedLogger logger
      ) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int resetThreshold = 24 * 60 * 60 * 1000; // 24 hours

    // List of all task types to check
    final taskTypes = [
      BackgroundTaskRegistrar.MORNING_NUDGE_TASK,
      BackgroundTaskRegistrar.NOON_NUDGE_TASK,
      BackgroundTaskRegistrar.EVENING_NUDGE_TASK,
      BackgroundTaskRegistrar.UNLOCK_DETECTION_TASK,
      BackgroundTaskRegistrar.MAINTENANCE_TASK,
    ];

    for (final taskType in taskTypes) {
      final int lastFailure = prefs.getInt('${taskType}_last_failure') ?? 0;
      final int failureCount = prefs.getInt('${taskType}_failures') ?? 0;

      // Reset counters if last failure was more than 24 hours ago
      if (now - lastFailure > resetThreshold) {
        await prefs.setInt('${taskType}_failures', 0);
      }
      // If too many failures, add backoff period
      else if (failureCount > 5) {
        // Calculate exponential backoff (in minutes)
        int backoffMinutes = 5 * (1 << (failureCount - 5).clamp(0, 6)); // Max 5h20m
        await prefs.setInt('${taskType}_backoff_until',
            now + backoffMinutes * 60 * 1000);

        logger.warn('Task $taskType has $failureCount failures, backing off for $backoffMinutes minutes');
      }
    }
  }

  /// Perform recovery after app restart or crash
  static Future<void> performRecovery(
      SharedPreferences prefs,
      AdvancedLogger logger
      ) async {
    logger.info('Performing system recovery checks');

    // Check when the app was last active
    final int lastActiveTime = prefs.getInt('app_last_active') ?? 0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int inactiveThreshold = 8 * 60 * 60 * 1000; // 8 hours

    if (now - lastActiveTime > inactiveThreshold) {
      logger.info('App inactive for extended period, checking for missed nudges');

      // Load configuration
      final config = await NudgeTaskConfiguration.getInstance();

      // Check for missed time windows
      final DateTime lastActive = DateTime.fromMillisecondsSinceEpoch(lastActiveTime);
      final DateTime current = DateTime.now();

      // Check if we missed any time windows
      final List<TimeWindow> missedWindows = [];

      // Get window hours from config
      final Map<TimeWindow, int> timeWindowHours = config.timeWindowHours;

      // Morning window
      if (_timeWindowMissed(lastActive, current,
          timeWindowHours[TimeWindow.morning]!, timeWindowHours[TimeWindow.morning]! + 2)) {
        missedWindows.add(TimeWindow.morning);
      }

      // Midday window
      if (_timeWindowMissed(lastActive, current,
          timeWindowHours[TimeWindow.midday]!, timeWindowHours[TimeWindow.midday]! + 2)) {
        missedWindows.add(TimeWindow.midday);
      }

      // Evening window
      if (_timeWindowMissed(lastActive, current,
          timeWindowHours[TimeWindow.evening]!, timeWindowHours[TimeWindow.evening]! + 2)) {
        missedWindows.add(TimeWindow.evening);
      }

      // If we missed windows and nudges are enabled, notify the main app
      if (missedWindows.isNotEmpty) {
        final bool nudgesEnabled = prefs.getBool('nudgesEnabled') ?? false;
        final List<String> enabledWindowsStr = prefs.getStringList('enabledTimeWindows') ?? [];

        // Convert string window names to TimeWindow values
        final List<TimeWindow> enabledWindows = enabledWindowsStr
            .map((name) => TimeWindow.values.firstWhere(
              (w) => w.name == name,
          orElse: () => TimeWindow.morning,
        ))
            .toList();

        // Filter to only enabled missed windows
        final List<TimeWindow> missedEnabledWindows = missedWindows
            .where((window) => enabledWindows.contains(window))
            .toList();

        // Check daily limit
        final int today = _getDayKey();
        final int dailyCount = prefs.getInt('nudge_count_$today') ?? 0;

        if (nudgesEnabled && missedEnabledWindows.isNotEmpty && dailyCount < config.maxDailyNudges) {
          logger.info('Detected missed nudge windows: ${missedEnabledWindows.map((w) => w.name).join(", ")}');

          // Notify main app about missed windows
          final sendPort = IsolateNameServer.lookupPortByName('nudge_delivery_port');
          if (sendPort != null) {
            final completer = Completer<bool>();
            final acknowledged = await _sendWithAcknowledgement(
                sendPort,
                {
                  'action': 'missed_windows',
                  'windows': missedEnabledWindows.map((w) => w.name).toList(),
                  'timestamp': now,
                  'messageId': 'recovery_${now}_${DateTime.now().microsecondsSinceEpoch}',
                  'sequence': _getNextSequenceNumber()
                },
                logger,
                completer,
                timeout: config.nudgeTimeout
            );

            try {
              if (acknowledged) {
                logger.info('Notified main app about missed nudge windows');
                await _incrementDailyCount(prefs);
              } else {
                // Store missed windows for later processing
                await prefs.setStringList(
                    'pending_missed_windows',
                    missedEnabledWindows.map((w) => w.name).toList()
                );
                logger.warn('Failed to notify about missed windows, stored for later processing');
              }
            } catch (e) {
              logger.warn('Failed to notify about missed windows: ${e.toString()}');
            }
          } else {
            // Store missed windows for later processing when app starts
            await prefs.setStringList(
                'pending_missed_windows',
                missedEnabledWindows.map((w) => w.name).toList()
            );
          }
        }
      }
    }

    // Check if settings sync is needed
    final bool syncNeeded = prefs.getBool('settings_sync_needed') ?? false;
    if (syncNeeded) {
      logger.info('Settings sync needed, scheduling verification');
      final sendPort = IsolateNameServer.lookupPortByName('nudge_delivery_port');
      if (sendPort != null) {
        final completer = Completer<bool>();
        final acknowledged = await _sendWithAcknowledgement(
            sendPort,
            {
              'action': 'verify_settings',
              'timestamp': now,
              'messageId': 'recovery_sync_${now}',
              'sequence': _getNextSequenceNumber()
            },
            logger,
            completer
        );

        if (acknowledged) {
          await prefs.setBool('settings_sync_needed', false);
        }
      }
    }

    // Check if recovery is needed (set by excessive failures)
    final bool recoveryNeeded = prefs.getBool('recovery_needed') ?? false;
    if (recoveryNeeded) {
      logger.info('System recovery needed, attempting task reset');

      // Send recovery signal to main app
      final sendPort = IsolateNameServer.lookupPortByName('nudge_delivery_port');
      if (sendPort != null) {
        final completer = Completer<bool>();
        final acknowledged = await _sendWithAcknowledgement(
            sendPort,
            {
              'action': 'system_recovery',
              'timestamp': now,
              'messageId': 'deep_recovery_${now}',
              'sequence': _getNextSequenceNumber()
            },
            logger,
            completer
        );

        if (acknowledged) {
          await prefs.setBool('recovery_needed', false);

          // Reset all failure counters
          final taskTypes = [
            BackgroundTaskRegistrar.MORNING_NUDGE_TASK,
            BackgroundTaskRegistrar.NOON_NUDGE_TASK,
            BackgroundTaskRegistrar.EVENING_NUDGE_TASK,
            BackgroundTaskRegistrar.UNLOCK_DETECTION_TASK,
            BackgroundTaskRegistrar.MAINTENANCE_TASK,
          ];

          for (final taskType in taskTypes) {
            await prefs.setInt('${taskType}_failures', 0);
            await prefs.remove('${taskType}_backoff_until');
          }
        }
      }
    }

    // Update last active time
    await prefs.setInt('app_last_active', now);
  }

  /// Check if a time window was missed between two timestamps
  static bool _timeWindowMissed(
      DateTime lastActive,
      DateTime current,
      int startHour,
      int endHour
      ) {
    // Create window times for last active day
    final lastActiveDay = DateTime(
        lastActive.year,
        lastActive.month,
        lastActive.day,
        startHour
    );

    // Create window times for current day
    final currentDay = DateTime(
        current.year,
        current.month,
        current.day,
        startHour
    );

    // Check if we were inactive during a window
    // 1. Last active before window and now after window (same day)
    if (lastActive.day == current.day &&
        lastActive.hour < startHour &&
        current.hour >= endHour) {
      return true;
    }

    // 2. Current day is after last active day and we're past the window
    if (current.day > lastActive.day && current.hour >= endHour) {
      return true;
    }

    // 3. Current day is at least 2 days after last active day
    if (current.difference(lastActive).inDays >= 2) {
      return true;
    }

    return false;
  }
}

/// Interface for testing the BackgroundTaskRegistrar
/// Allows for easy mocking and testing of the background task system
abstract class BackgroundTaskRegistrarInterface {
  /// Initialize the background task system
  Future<void> initialize();

  /// Register all tasks according to current settings
  Future<void> registerAllTasks(NudgeSettings settings);

  /// Pause all background tasks
  Future<void> pauseTasks();

  /// Resume tasks according to current settings
  Future<void> resumeTasks();

  /// Clean up resources
  Future<void> dispose();

  /// Check if the registrar is initialized
  bool get isInitialized;

  /// For testing: Get current task status
  Future<Map<String, dynamic>> getTaskStatus();

  /// For testing: Simulate a device unlock event
  Future<bool> simulateDeviceUnlock();

  /// For testing: Simulate a time window trigger
  Future<bool> simulateTimeWindow(TimeWindow window);

  /// For testing: Check if a task is currently registered
  Future<bool> isTaskRegistered(String taskName);
}

/// A service for registering and managing background tasks for the nudge feature.
///
/// This service handles:
/// - Registration of periodic and one-time background tasks
/// - Platform-specific optimizations for background processing
/// - Device unlock detection setup
/// - Battery optimization requests
/// - Handling task restart after device reboot
/// - Recovery after app crashes or force stops
class BackgroundTaskRegistrar implements BackgroundTaskRegistrarInterface {
  // Task identifiers
  static const String MORNING_NUDGE_TASK = 'com.milo.nudges.morning';
  static const String NOON_NUDGE_TASK = 'com.milo.nudges.noon';
  static const String EVENING_NUDGE_TASK = 'com.milo.nudges.evening';
  static const String UNLOCK_DETECTION_TASK = 'com.milo.nudges.unlock_detection';
  static const String MAINTENANCE_TASK = 'com.milo.nudges.maintenance';
  static const String RECOVERY_TASK = 'com.milo.nudges.recovery';

  // Port for communication with background tasks
  final ReceivePort _receivePort = ReceivePort();

  // Dependencies
  final AdvancedLogger _logger;
  final NudgeService _nudgeService;
  final NudgeTriggerHandler _triggerHandler;
  final NotificationService _notificationService;

  // Configuration provider
  late Future<NudgeTaskConfiguration> _configProvider;

  // State
  bool _isInitialized = false;
  bool _isDisposed = false;
  StreamSubscription? _unlockSubscription;

  // Synchronization lock for thread safety
  final Lock _initLock = Lock();
  final Lock _taskLock = Lock();

  /// Constructor with required dependencies
  ///
  /// Uses dependency injection pattern for better testability
  BackgroundTaskRegistrar({
    required AdvancedLogger logger,
    required NudgeService nudgeService,
    required NudgeTriggerHandler triggerHandler,
    required NotificationService notificationService,
  }) :
        _logger = logger,
        _nudgeService = nudgeService,
        _triggerHandler = triggerHandler,
        _notificationService = notificationService {
    _configProvider = NudgeTaskConfiguration.getInstance();
  }

  /// Check if the registrar is initialized
  @override
  bool get isInitialized => _isInitialized;

  /// Initialize the background task system.
  ///
  /// Must be called during app initialization before registering any tasks.
  /// Requests necessary permissions for reliable background operation.
  /// Thread-safe implementation using lock.
  @override
  Future<void> initialize() async {
    // Use lock to prevent concurrent initialization
    return _initLock.synchronized(() async {
      if (_isInitialized) {
        _logger.warn('BackgroundTaskRegistrar: Already initialized');
        return;
      }

      if (_isDisposed) {
        _logger.error('BackgroundTaskRegistrar: Cannot initialize after disposal');
        throw StateError('Cannot initialize BackgroundTaskRegistrar after disposal');
      }

      try {
        _logger.info('BackgroundTaskRegistrar: Initializing');

        // Initialize the notification system first
        await _notificationService.initialize();

        // Set up workmanager for background tasks
        await Workmanager().initialize(
          BackgroundTaskUtils.callbackDispatcher,
          isInDebugMode: kDebugMode,
        );

        // Set up communication channel for background tasks
        if (IsolateNameServer.lookupPortByName('nudge_delivery_port') != null) {
          // Clean up existing port registration to avoid conflicts
          IsolateNameServer.removePortNameMapping('nudge_delivery_port');
        }

        IsolateNameServer.registerPortWithName(
          _receivePort.sendPort,
          'nudge_delivery_port',
        );

        // Listen for messages from background tasks
        _receivePort.listen(_handleBackgroundMessage);

        // Initialize configuration
        await _configProvider;

        // Request necessary permissions
        final permissionsGranted = await _requestRequiredPermissions();
        if (!permissionsGranted) {
          _logger.warn('Some permissions were denied, functionality may be limited');
          // Continue initialization despite permission issues
        }

        // Request battery optimization exclusion if needed
        final batteryExcluded = await _requestBatteryOptimizationExclusion();
        if (!batteryExcluded && Platform.isAndroid) {
          _logger.warn('Battery optimization exclusion not granted, background reliability may be affected');
          // Continue initialization despite battery optimization issues
        }

        // Initialize platform-specific unlock detection
        try {
          final bool unlockDetectionInitialized = await PlatformUnlockDetector.initialize();
          if (unlockDetectionInitialized) {
            _logger.info('Platform-specific unlock detection initialized');

            // Set up event listener for device unlocks
            await PlatformUnlockDetector.startListening((DateTime unlockTime) {
              _handleDeviceUnlock(unlockTime);
            });
          } else {
            _logger.warn('Platform-specific unlock detection not available, will use fallback');
          }
        } catch (e, stack) {
          _logger.error('Failed to initialize platform-specific unlock detection', e, stack);
          _logger.info('Will use fallback mechanism for unlock detection');
        }

        // Schedule an immediate recovery check
        await _scheduleRecoveryCheck();

        // Record app active timestamp
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('app_last_active', DateTime.now().millisecondsSinceEpoch);

        _isInitialized = true;
        _logger.info('BackgroundTaskRegistrar: Initialized successfully');
      } catch (e, stack) {
        _logger.error('BackgroundTaskRegistrar: Initialization failed', e, stack);

        // Clean up resources in case of failure
        _cleanupResourcesOnFailure();

        rethrow;
      }
    });
  }

  /// Handle device unlock event from platform-specific detection
  Future<void> _handleDeviceUnlock(DateTime unlockTime) async {
    try {
      _logger.info('Platform-specific unlock detected at ${unlockTime.toIso8601String()}');

      // Get shared preferences
      final prefs = await SharedPreferences.getInstance();

      // Check if unlock triggers are enabled
      final bool deviceUnlockEnabled = prefs.getBool('allowDeviceUnlockTrigger') ?? false;
      if (!deviceUnlockEnabled) {
        _logger.info('Device unlock triggers disabled, ignoring unlock event');
        return;
      }

      // Get last processed unlock time
      final int lastProcessedTime = prefs.getInt('lastProcessedUnlock') ?? 0;
      final int unlockTimestamp = unlockTime.millisecondsSinceEpoch;

      // Check if this is a new unlock
      if (unlockTimestamp <= lastProcessedTime) {
        _logger.info('Already processed this unlock event, ignoring');
        return;
      }

      // Update last processed time
      await prefs.setInt('lastProcessedUnlock', unlockTimestamp);

      // Get configuration
      final config = await _configProvider;

      // Check if we're within rate limits
      final int lastUnlockNudgeTime = prefs.getInt('last_unlock_nudge') ?? 0;
      final int minimumInterval = config.minTimeBetweenNudges.inMilliseconds;

      if (unlockTimestamp - lastUnlockNudgeTime < minimumInterval) {
        _logger.info('Skipping unlock nudge: Rate limited');
        return;
      }

      // Check daily limit
      final int today = BackgroundTaskUtils._getDayKey();
      final int dailyCount = prefs.getInt('nudge_count_$today') ?? 0;

      if (dailyCount >= config.maxDailyNudges) {
        _logger.info('Skipping unlock nudge: Daily limit reached (${dailyCount}/${config.maxDailyNudges})');
        return;
      }

      // All checks passed, trigger nudge
      _logger.info('Processing unlock nudge');
      await _triggerHandler.handleDeviceUnlock();

      // Update timestamps and counters
      await prefs.setInt('last_unlock_nudge', unlockTimestamp);
      await BackgroundTaskUtils._incrementDailyCount(prefs);
    } catch (e, stack) {
      _logger.error('Error handling device unlock', e, stack);
    }
  }

  /// Clean up resources if initialization fails
  void _cleanupResourcesOnFailure() {
    try {
      // Remove port registration if it exists
      if (IsolateNameServer.lookupPortByName('nudge_delivery_port') != null) {
        IsolateNameServer.removePortNameMapping('nudge_delivery_port');
      }

      // Close the receive port
      if (!_isDisposed) {
        _receivePort.close();
      }

      // Stop platform-specific unlock detection
      PlatformUnlockDetector.stopListening();

      // Cancel any unlock subscription
      if (_unlockSubscription != null) {
        _unlockSubscription!.cancel();
        _unlockSubscription = null;
      }
    } catch (e) {
      // Just log, don't throw from cleanup
      _logger.error('Error during cleanup', e);
    }
  }

  /// Schedule recovery check task
  Future<void> _scheduleRecoveryCheck() async {
    final config = await _configProvider;

    await _taskLock.synchronized(() async {
      await Workmanager().registerPeriodicTask(
        RECOVERY_TASK,
        RECOVERY_TASK,
        frequency: config.recoveryFrequency,
        initialDelay: Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    });

    _logger.info('Scheduled recovery check task');
  }

  /// Handle messages from background tasks
  void _handleBackgroundMessage(dynamic message) {
    if (_isDisposed) {
      _logger.warn('Ignoring background message, registrar is disposed');
      return;
    }

    if (message is! Map) {
      _logger.warn('Received invalid background message format');
      return;
    }

    try {
      final String action = message['action'] as String? ?? '';
      final String messageId = message['messageId'] as String? ?? '';
      final int? sequence = message['sequence'] as int?;

      _logger.info('Received background message: $action, id: $messageId, seq: $sequence');

      // Send acknowledgement first to prevent timeouts
      if (messageId.isNotEmpty) {
        _sendAcknowledgement(messageId);
      }

      switch (action) {
        case 'deliver_nudge':
          final String windowName = message['window'] as String? ?? '';
          final TimeWindow window = TimeWindow.values.firstWhere(
                (w) => w.name == windowName,
            orElse: () => TimeWindow.morning,
          );

          _triggerHandler.handleScheduledTime(window);
          break;

        case 'device_unlock':
          _triggerHandler.handleDeviceUnlock();
          break;

        case 'verify_settings':
          _syncSettings();
          break;

        case 'missed_windows':
          final List<dynamic> windowsData = message['windows'] as List<dynamic>? ?? [];
          final List<String> windowNames = windowsData.cast<String>();

          _handleMissedWindows(windowNames);
          break;

        case 'system_recovery':
          _performSystemRecovery();
          break;

        default:
          _logger.warn('Unknown background action: $action');
          break;
      }
    } catch (e, stack) {
      _logger.error('Error handling background message', e, stack);
    }
  }

  /// Send acknowledgement for received message
  void _sendAcknowledgement(String messageId) {
    try {
      BackgroundTaskUtils.processAcknowledgement(messageId);
    } catch (e) {
      _logger.error('Failed to send acknowledgement', e);
    }
  }

  /// Perform system recovery after critical failures
  Future<void> _performSystemRecovery() async {
    try {
      _logger.info('Performing deep system recovery');

      // Cancel all tasks
      await Workmanager().cancelAll();

      // Get current settings
      final settings = await _nudgeService.getSettings();

      // Re-register all tasks
      await registerAllTasks(settings);

      _logger.info('System recovery completed');
    } catch (e, stack) {
      _logger.error('Failed to perform system recovery', e, stack);
    }
  }

  /// Synchronize settings between Firestore and SharedPreferences
  Future<void> _syncSettings() async {
    try {
      // Get the latest settings from Firestore
      final settings = await _nudgeService.getSettings();

      // Update SharedPreferences with these settings
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('nudgesEnabled', settings.nudgesEnabled);
      await prefs.setStringList(
          'enabledTimeWindows',
          settings.enabledTimeWindows.map((w) => w.name).toList()
      );
      await prefs.setBool('allowDeviceUnlockTrigger', settings.allowDeviceUnlockTrigger);
      await prefs.setBool('allowTimeBasedTrigger', settings.allowTimeBasedTrigger);
      await prefs.setInt('maxNudgesPerDay', settings.maxNudgesPerDay);

      // Clear sync flag if it was set
      await prefs.setBool('settings_sync_needed', false);

      _logger.info('Settings synchronized successfully');
    } catch (e, stack) {
      _logger.error('Failed to synchronize settings', e, stack);
    }
  }

  /// Handle missed nudge windows after app restart
  Future<void> _handleMissedWindows(List<String> windowNames) async {
    try {
      _logger.info('Handling missed nudge windows: ${windowNames.join(", ")}');

      // Convert names to TimeWindow enums
      final List<TimeWindow> windows = windowNames
          .map((name) => TimeWindow.values.firstWhere(
            (w) => w.name == name,
        orElse: () => TimeWindow.morning,
      ))
          .toList();

      // Check rate limits before delivering anything
      final prefs = await SharedPreferences.getInstance();
      final int lastRecoveryDelivery = prefs.getInt('last_recovery_delivery') ?? 0;
      final int now = DateTime.now().millisecondsSinceEpoch;

      // Get configuration
      final config = await _configProvider;
      final int recoveryMinimumInterval = config.minTimeBetweenNudges.inMilliseconds;

      if (now - lastRecoveryDelivery < recoveryMinimumInterval) {
        _logger.info('Skipping recovery delivery: Rate limited');
        return;
      }

      // Check daily limit
      final int today = BackgroundTaskUtils._getDayKey();
      final int dailyCount = prefs.getInt('nudge_count_$today') ?? 0;

      if (dailyCount >= config.maxDailyNudges) {
        _logger.info('Skipping recovery delivery: Daily limit reached (${dailyCount}/${config.maxDailyNudges})');
        return;
      }

      // Limit to one nudge despite multiple missed windows
      if (windows.isNotEmpty) {
        // Choose the most recent window to deliver
        windows.sort((a, b) => a.index.compareTo(b.index));
        final TimeWindow windowToDeliver = windows.last;

        _logger.info('Delivering recovery nudge for ${windowToDeliver.name} window');
        await _triggerHandler.handleScheduledTime(windowToDeliver, isRecovery: true);

        // Record delivery time
        await prefs.setInt('last_recovery_delivery', now);
        await BackgroundTaskUtils._incrementDailyCount(prefs);

        // Clear the pending missed windows
        await prefs.remove('pending_missed_windows');
      }
    } catch (e, stack) {
      _logger.error('Failed to handle missed windows', e, stack);
    }
  }

  /// Register all necessary background tasks based on user settings.
  ///
  /// This should be called when the app starts and whenever
  /// user settings change related to nudge timing or frequency.
  @override
  Future<void> registerAllTasks(NudgeSettings settings) async {
    return _taskLock.synchronized(() async {
      if (!_isInitialized) {
        await initialize();
      }

      if (_isDisposed) {
        _logger.error('Cannot register tasks after disposal');
        throw StateError('Cannot register tasks after BackgroundTaskRegistrar disposal');
      }

      try {
        _logger.info('BackgroundTaskRegistrar: Registering tasks based on user settings');

        // Cancel any existing tasks to avoid duplicates
        await Workmanager().cancelAll();

        // Get configuration
        final config = await _configProvider;

        // Only proceed if nudges are enabled
        if (!settings.nudgesEnabled) {
          _logger.info('BackgroundTaskRegistrar: Nudges disabled, skipping task registration');

          // Even if nudges are disabled, still register maintenance and recovery
          await _registerPeriodicTask(
            MAINTENANCE_TASK,
            config.maintenanceFrequency,
            initialDelay: Duration(hours: 1),
          );

          await _scheduleRecoveryCheck();

          // Stop platform-specific unlock detection if it's running
          await PlatformUnlockDetector.stopListening();

          return;
        }

        // Register time-based nudge tasks
        if (settings.allowTimeBasedTrigger) {
          final Map<TimeWindow, int> timeWindowHours = config.timeWindowHours;

          if (settings.enabledTimeWindows.contains(TimeWindow.morning)) {
            await _registerDailyTask(MORNING_NUDGE_TASK, timeWindowHours[TimeWindow.morning]!);
          }

          if (settings.enabledTimeWindows.contains(TimeWindow.midday)) {
            await _registerDailyTask(NOON_NUDGE_TASK, timeWindowHours[TimeWindow.midday]!);
          }

          if (settings.enabledTimeWindows.contains(TimeWindow.evening)) {
            await _registerDailyTask(EVENING_NUDGE_TASK, timeWindowHours[TimeWindow.evening]!);
          }
        }

        // Register device unlock detection if enabled
        if (settings.allowDeviceUnlockTrigger) {
          // First try to use platform-specific implementation
          final bool platformDetectionStarted = await PlatformUnlockDetector.startListening((DateTime unlockTime) {
            _handleDeviceUnlock(unlockTime);
          });

          if (!platformDetectionStarted) {
            _logger.warn('Platform-specific unlock detection failed to start, using fallback');
            // Fall back to the workmanager-based approach
            await _registerDeviceUnlockDetection();
          } else {
            _logger.info('Platform-specific unlock detection started successfully');
          }
        } else {
          // Ensure platform detection is stopped if previously enabled
          await PlatformUnlockDetector.stopListening();
        }

        // Always register maintenance task
        await _registerPeriodicTask(
          MAINTENANCE_TASK,
          config.maintenanceFrequency,
          initialDelay: Duration(hours: 1),
        );

        // Always register recovery task
        await _scheduleRecoveryCheck();

        // Update settings in SharedPreferences
        await _updateSharedPreferencesSettings(settings);

        _logger.info('BackgroundTaskRegistrar: Task registration completed');
      } catch (e, stack) {
        _logger.error('BackgroundTaskRegistrar: Failed to register tasks', e, stack);
        rethrow;
      }
    });
  }

  /// Update settings in SharedPreferences for background tasks
  Future<void> _updateSharedPreferencesSettings(NudgeSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('nudgesEnabled', settings.nudgesEnabled);
      await prefs.setStringList(
          'enabledTimeWindows',
          settings.enabledTimeWindows.map((w) => w.name).toList()
      );
      await prefs.setBool('allowDeviceUnlockTrigger', settings.allowDeviceUnlockTrigger);
      await prefs.setBool('allowTimeBasedTrigger', settings.allowTimeBasedTrigger);
      await prefs.setInt('maxNudgesPerDay', settings.maxNudgesPerDay);

      // Clear settings sync flag
      await prefs.setBool('settings_sync_needed', false);

      // Update last active timestamp
      await prefs.setInt('app_last_active', DateTime.now().millisecondsSinceEpoch);
    } catch (e, stack) {
      _logger.error('Failed to update settings in SharedPreferences', e, stack);
    }
  }

  /// Register a task to run daily at a specific hour.
  /// Uses exponential backoff strategy for reliability.
  Future<void> _registerDailyTask(String taskName, int hour) async {
    // Calculate initial delay to next occurrence
    final now = DateTime.now();
    final scheduledTime = DateTime(now.year, now.month, now.day, hour);

    // If the time has already passed today, schedule for tomorrow
    final initialDelay = scheduledTime.isAfter(now)
        ? scheduledTime.difference(now)
        : scheduledTime.add(Duration(days: 1)).difference(now);

    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: Duration(days: 1),
      initialDelay: initialDelay,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    _logger.info('Registered daily task: $taskName at $hour:00');
  }

  /// Register periodic task with specified frequency.
  Future<void> _registerPeriodicTask(
      String taskName,
      Duration frequency, {
        Duration initialDelay = Duration.zero,
      }) async {
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: frequency,
      initialDelay: initialDelay,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: Duration(minutes: 5),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    _logger.info('Registered periodic task: $taskName with frequency ${frequency.inMinutes} minutes');
  }

  /// Register device unlock detection using workmanager
  /// This is a fallback when platform-specific detection isn't available
  Future<void> _registerDeviceUnlockDetection() async {
    try {
      // Get configuration
      final config = await _configProvider;

      // Check device capabilities to determine optimal strategy
      Duration checkFrequency = config.unlockCheckFrequency;

      // Apply device-specific adjustments to optimize battery
      if (Platform.isAndroid) {
        final deviceInfo = await DeviceInfoPlugin().androidInfo;
        final sdkVersion = deviceInfo.version.sdkInt;

        // Newer Android versions have better background capabilities
        // but we still need to be battery-conscious for elderly users
        if (sdkVersion >= 29) { // Android 10+
          checkFrequency = Duration(minutes: 30);
        } else if (sdkVersion >= 26) { // Android 8+
          checkFrequency = Duration(minutes: 45);
        } else { // Older Android
          checkFrequency = Duration(minutes: 60);
        }
      } else if (Platform.isIOS) {
        // iOS has stricter background restrictions
        checkFrequency = Duration(minutes: 60);
      }

      await Workmanager().registerPeriodicTask(
        UNLOCK_DETECTION_TASK,
        UNLOCK_DETECTION_TASK,
        frequency: checkFrequency,
        initialDelay: Duration(minutes: 1),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: Duration(minutes: 5),
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      _logger.info('Registered workmanager-based device unlock detection with frequency: ${checkFrequency.inMinutes} minutes');
      _logger.warn('WARNING: Using inefficient polling for unlock detection. This is a fallback implementation.');
    } catch (e, stack) {
      _logger.error('Failed to register device unlock detection', e, stack);
      rethrow;
    }
  }

  /// Request necessary permissions for background operation
  /// Returns true if all critical permissions are granted
  Future<bool> _requestRequiredPermissions() async {
    bool allCriticalPermissionsGranted = true;

    try {
      // Request notification permissions
      final NotificationSettings notificationSettings = await _notificationService.requestPermissions();

      if (notificationSettings.authorizationStatus != AuthorizationStatus.authorized) {
        _logger.warn('Notification permissions not granted');

        // For elderly users, show a more prominent permission request on next app start
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('show_notification_permission_dialog', true);

        allCriticalPermissionsGranted = false;
      }

      // Request other necessary permissions
      if (Platform.isAndroid) {
        final androidPermissionsGranted = await _requestAndroidPermissions();
        allCriticalPermissionsGranted = allCriticalPermissionsGranted && androidPermissionsGranted;
      } else if (Platform.isIOS) {
        final iosPermissionsGranted = await _requestIOSPermissions();
        allCriticalPermissionsGranted = allCriticalPermissionsGranted && iosPermissionsGranted;
      }

      // If permissions are denied, adjust app behavior accordingly
      if (!allCriticalPermissionsGranted) {
        _handlePermissionDenial();
      }

      return allCriticalPermissionsGranted;
    } catch (e, stack) {
      _logger.error('Error requesting permissions', e, stack);
      return false;
    }
  }

  /// Handle graceful degradation when permissions are denied
  Future<void> _handlePermissionDenial() async {
    try {
      // Store flag to show friendly explanation on next app start
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('permission_explanation_needed', true);

      // Adjust settings to work with limited permissions
      // For example, disable device unlock triggers if we don't have necessary permissions
      final currentSettings = await _nudgeService.getSettings();

      if (currentSettings.allowDeviceUnlockTrigger) {
        // Create modified settings that don't rely on denied permissions
        final adjustedSettings = NudgeSettings(
          nudgesEnabled: currentSettings.nudgesEnabled,
          enabledTimeWindows: currentSettings.enabledTimeWindows,
          allowTimeBasedTrigger: currentSettings.allowTimeBasedTrigger,
          // Disable device unlock trigger since we lack permissions
          allowDeviceUnlockTrigger: false,
          maxNudgesPerDay: currentSettings.maxNudgesPerDay,
        );

        // Update settings
        await _nudgeService.updateSettings(adjustedSettings);

        _logger.info('Adjusted settings to work with limited permissions');
      }
    } catch (e) {
      _logger.error('Failed to handle permission denial gracefully', e);
    }
  }

  /// Request Android-specific permissions
  /// Returns true if all critical permissions are granted
  Future<bool> _requestAndroidPermissions() async {
    bool allGranted = true;

    try {
      // Check Android version for appropriate permissions
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      final sdkVersion = deviceInfo.version.sdkInt;

      // For Android 10+ (SDK 29+)
      if (sdkVersion >= 29) {
        final activityStatus = await Permission.activityRecognition.request();
        if (!activityStatus.isGranted) {
          _logger.warn('Activity recognition permission not granted');
          // Not critical, can continue without it
        }
      }

      // For all Android versions
      final notificationStatus = await Permission.notification.request();
      if (!notificationStatus.isGranted) {
        _logger.warn('Notification permission not granted');
        allGranted = false;
      }

      // Request storage permission if needed for saving audio
      final storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) {
        _logger.warn('Storage permission not granted');
        // Not critical, can continue without it
      }

      // Request foreground service permission if available (Android 9+)
      if (sdkVersion >= 28) {
        if (await Permission.ignoreBatteryOptimizations.isGranted) {
          final foregroundStatus = await Permission.systemAlertWindow.request();
          if (!foregroundStatus.isGranted) {
            _logger.warn('Foreground service permission not granted');
            // Not critical, but may impact unlock detection
          }
        }
      }

      return allGranted;
    } catch (e, stack) {
      _logger.error('Error requesting Android permissions', e, stack);
      return false;
    }
  }

  /// Request iOS-specific permissions
  /// Returns true if all critical permissions are granted
  Future<bool> _requestIOSPermissions() async {
    bool allGranted = true;

    try {
      final notificationStatus = await Permission.notification.request();
      if (!notificationStatus.isGranted) {
        _logger.warn('Notification permission not granted');
        allGranted = false;
      }

      // Request background refresh capability
      if (await Permission.appTrackingTransparency.isGranted) {
        // This isn't an actual permission, but we use it here as a proxy for
        // representing whether the app can refresh in background on iOS
        _logger.info('iOS background refresh capability appears to be available');
      } else {
        _logger.warn('iOS background capabilities may be limited');
        // Not critical, but may impact functionality
      }

      return allGranted;
    } catch (e, stack) {
      _logger.error('Error requesting iOS permissions', e, stack);
      return false;
    }
  }

  /// Request exclusion from battery optimization for better background reliability
  /// Returns true if battery optimization exclusion is granted
  Future<bool> _requestBatteryOptimizationExclusion() async {
    if (Platform.isAndroid) {
      try {
        final bool isIgnoring = await Permission.ignoreBatteryOptimizations.isGranted;

        if (!isIgnoring) {
          _logger.info('Requesting battery optimization exclusion');
          final status = await Permission.ignoreBatteryOptimizations.request();

          // If denied, adjust background tasks for better battery efficiency
          if (!status.isGranted) {
            _adjustForBatteryOptimization();
          }

          return status.isGranted;
        }

        return true;
      } catch (e, stack) {
        _logger.error('Error requesting battery optimization exclusion', e, stack);

        // In case of error, assume we're battery optimized
        _adjustForBatteryOptimization();
        return false;
      }
    }

    // Not applicable on iOS
    return true;
  }

  /// Adjust task frequencies for better battery life when optimization is enabled
  Future<void> _adjustForBatteryOptimization() async {
    try {
      _logger.info('Adjusting background tasks for battery optimization');

      // Store the battery optimization state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('battery_optimized', true);

      // The rest of the optimization will happen when tasks are registered
    } catch (e) {
      _logger.error('Failed to adjust for battery optimization', e);
    }
  }

  /// Clean up resources when the service is no longer needed.
  @override
  Future<void> dispose() async {
    return _initLock.synchronized(() async {
      if (_isDisposed) {
        return;
      }

      try {
        // Close receive port
        _receivePort.close();

        // Clean up port mapping
        if (IsolateNameServer.lookupPortByName('nudge_delivery_port') != null) {
          IsolateNameServer.removePortNameMapping('nudge_delivery_port');
        }

        // Stop platform-specific unlock detection
        await PlatformUnlockDetector.stopListening();

        // Cancel any unlock subscription
        if (_unlockSubscription != null) {
          await _unlockSubscription!.cancel();
          _unlockSubscription = null;
        }

        _isDisposed = true;
        _isInitialized = false;

        _logger.info('BackgroundTaskRegistrar resources cleaned up');
      } catch (e, stack) {
        _logger.error('Error during BackgroundTaskRegistrar disposal', e, stack);
      }
    });
  }

  /// Temporarily pause all background tasks.
  @override
  Future<void> pauseTasks() async {
    return _taskLock.synchronized(() async {
      if (_isDisposed) {
        throw StateError('Cannot pause tasks after disposal');
      }

      try {
        await Workmanager().cancelAll();

        // Stop platform-specific unlock detection
        await PlatformUnlockDetector.stopListening();

        _logger.info('All background tasks paused');
      } catch (e, stack) {
        _logger.error('Error pausing background tasks', e, stack);
        rethrow;
      }
    });
  }

  /// Resume tasks according to current settings.
  @override
  Future<void> resumeTasks() async {
    return _taskLock.synchronized(() async {
      if (_isDisposed) {
        throw StateError('Cannot resume tasks after disposal');
      }

      try {
        // Update active timestamp when resuming tasks
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('app_last_active', DateTime.now().millisecondsSinceEpoch);

        // First check for settings sync issues
        final bool syncNeeded = prefs.getBool('settings_sync_needed') ?? false;
        if (syncNeeded) {
          await _syncSettings();
        }

        // Load current settings and register tasks
        final settings = await _nudgeService.getSettings();
        await registerAllTasks(settings);

        // Check for pending missed windows
        final List<String> pendingWindows = prefs.getStringList('pending_missed_windows') ?? [];
        if (pendingWindows.isNotEmpty) {
          await _handleMissedWindows(pendingWindows);
        }

        _logger.info('Background tasks resumed according to current settings');
      } catch (e, stack) {
        _logger.error('Error resuming background tasks', e, stack);
        rethrow;
      }
    });
  }

  /// For testing: Get current task status
  @override
  Future<Map<String, dynamic>> getTaskStatus() async {
    if (_isDisposed) {
      throw StateError('Cannot get task status after disposal');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final config = await _configProvider;

      // Check platform-specific unlock detection status
      bool platformUnlockDetectionRunning = false;
      try {
        platformUnlockDetectionRunning = await PlatformUnlockDetector.isRunning();
      } catch (e) {
        _logger.error('Error checking platform unlock detection status', e);
      }

      // Collect relevant information about task state
      final Map<String, dynamic> status = {
        'initialized': _isInitialized,
        'disposed': _isDisposed,
        'nudgesEnabled': prefs.getBool('nudgesEnabled') ?? false,
        'timeBasedEnabled': prefs.getBool('allowTimeBasedTrigger') ?? false,
        'unlockEnabled': prefs.getBool('allowDeviceUnlockTrigger') ?? false,
        'platformUnlockDetection': platformUnlockDetectionRunning,
        'batteryOptimized': prefs.getBool('battery_optimized') ?? false,
        'lastActive': prefs.getInt('app_last_active') ?? 0,
        'remoteConfig': {
          'morningHour': config.morningHour,
          'noonHour': config.noonHour,
          'eveningHour': config.eveningHour,
          'unlockCheckMinutes': config.unlockCheckFrequency.inMinutes,
          'maintenanceHours': config.maintenanceFrequency.inHours,
          'recoveryHours': config.recoveryFrequency.inHours,
          'maxDailyNudges': config.maxDailyNudges,
          'minMinutesBetween': config.minTimeBetweenNudges.inMinutes,
        },
        'windowDeliveries': <String, dynamic>{},
        'failures': <String, dynamic>{},
        'pendingSync': prefs.getBool('settings_sync_needed') ?? false,
        'recoveryNeeded': prefs.getBool('recovery_needed') ?? false,
        'dailyCounts': <String, dynamic>{},
      };

      // Collect delivery timestamps for each window
      for (final window in TimeWindow.values) {
        status['windowDeliveries'][window.name] = prefs.getInt('last_${window.name}_delivery') ?? 0;
      }

      // Collect daily counts
      final today = BackgroundTaskUtils._getDayKey();
      status['dailyCounts']['today'] = prefs.getInt('nudge_count_$today') ?? 0;

      // Collect failure counts for tasks
      final taskTypes = [
        MORNING_NUDGE_TASK,
        NOON_NUDGE_TASK,
        EVENING_NUDGE_TASK,
        UNLOCK_DETECTION_TASK,
        MAINTENANCE_TASK,
        RECOVERY_TASK,
      ];

      for (final taskType in taskTypes) {
        status['failures'][taskType] = {
          'count': prefs.getInt('${taskType}_failures') ?? 0,
          'lastFailure': prefs.getInt('${taskType}_last_failure') ?? 0,
          'backoffUntil': prefs.getInt('${taskType}_backoff_until') ?? 0,
        };
      }

      return status;
    } catch (e, stack) {
      _logger.error('Failed to get task status', e, stack);
      throw e;
    }
  }

  /// For testing: Simulate a device unlock event
  @override
  Future<bool> simulateDeviceUnlock() async {
    if (_isDisposed) {
      throw StateError('Cannot simulate events after disposal');
    }

    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Check if device unlock triggers are enabled
      final prefs = await SharedPreferences.getInstance();
      final bool unlockEnabled = prefs.getBool('allowDeviceUnlockTrigger') ?? false;

      if (!unlockEnabled) {
        _logger.warn('Device unlock triggers are disabled');
        return false;
      }

      // Create unlock time
      final DateTime unlockTime = DateTime.now();

      // Call device unlock handler directly
      await _handleDeviceUnlock(unlockTime);

      return true;
    } catch (e, stack) {
      _logger.error('Error simulating device unlock', e, stack);
      return false;
    }
  }

  /// For testing: Simulate a time window trigger
  @override
  Future<bool> simulateTimeWindow(TimeWindow window) async {
    if (_isDisposed) {
      throw StateError('Cannot simulate events after disposal');
    }

    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Check if time-based triggers are enabled
      final prefs = await SharedPreferences.getInstance();
      final bool timeBasedEnabled = prefs.getBool('allowTimeBasedTrigger') ?? false;

      if (!timeBasedEnabled) {
        _logger.warn('Time-based triggers are disabled');
        return false;
      }

      // Check if this specific window is enabled
      final List<String> enabledWindowsStr = prefs.getStringList('enabledTimeWindows') ?? [];
      final List<TimeWindow> enabledWindows = enabledWindowsStr
          .map((name) => TimeWindow.values.firstWhere(
            (w) => w.name == name,
        orElse: () => TimeWindow.morning,
      ))
          .toList();

      if (!enabledWindows.contains(window)) {
        _logger.warn('${window.name} window is not enabled');
        return false;
      }

      // Get current daily count
      final config = await _configProvider;
      final int today = BackgroundTaskUtils._getDayKey();
      final int dailyCount = prefs.getInt('nudge_count_$today') ?? 0;

      if (dailyCount >= config.maxDailyNudges) {
        _logger.warn('Daily limit reached (${dailyCount}/${config.maxDailyNudges})');
        return false;
      }

      // Call the trigger handler directly
      await _triggerHandler.handleScheduledTime(window, isSimulation: true);

      // Update the count
      await BackgroundTaskUtils._incrementDailyCount(prefs);

      return true;
    } catch (e, stack) {
      _logger.error('Error simulating time window', e, stack);
      return false;
    }
  }

  /// For testing: Check if a task is currently registered
  @override
  Future<bool> isTaskRegistered(String taskName) async {
    if (_isDisposed) {
      throw StateError('Cannot check task status after disposal');
    }

    // Note: Workmanager doesn't provide a direct API to check if a task is registered
    // This is a best-effort attempt based on our own tracking

    try {
      final prefs = await SharedPreferences.getInstance();

      // Different logic based on task type
      switch (taskName) {
        case MORNING_NUDGE_TASK:
        case NOON_NUDGE_TASK:
        case EVENING_NUDGE_TASK:
        // Time-based tasks
          final bool timeEnabled = prefs.getBool('allowTimeBasedTrigger') ?? false;
          final List<String> enabledWindows = prefs.getStringList('enabledTimeWindows') ?? [];

          if (taskName == MORNING_NUDGE_TASK) {
            return timeEnabled && enabledWindows.contains(TimeWindow.morning.name);
          } else if (taskName == NOON_NUDGE_TASK) {
            return timeEnabled && enabledWindows.contains(TimeWindow.midday.name);
          } else {
            return timeEnabled && enabledWindows.contains(TimeWindow.evening.name);
          }

        case UNLOCK_DETECTION_TASK:
          final bool unlockViaWorkmanager = prefs.getBool('allowDeviceUnlockTrigger') ?? false;

          // If we're using platform-specific detection, the workmanager task might not be registered
          if (unlockViaWorkmanager) {
            try {
              final bool platformRunning = await PlatformUnlockDetector.isRunning();
              // If platform detection is running, we don't need the workmanager task
              return !platformRunning && unlockViaWorkmanager;
            } catch (e) {
              // If there's an error checking, assume we're using workmanager
              return unlockViaWorkmanager;
            }
          }
          return false;

        case MAINTENANCE_TASK:
        case RECOVERY_TASK:
        // These should always be registered
          return true;

        default:
          return false;
      }
    } catch (e, stack) {
      _logger.error('Error checking if task is registered', e, stack);
      return false;
    }
  }
}

// Extension to add factory methods for better dependency management
extension BackgroundTaskRegistrarExtension on BackgroundTaskRegistrar {
  /// Factory method using GetIt service locator
  static BackgroundTaskRegistrar fromServiceLocator() {
    return BackgroundTaskRegistrar(
      logger: GetIt.instance<AdvancedLogger>(),
      nudgeService: GetIt.instance<NudgeService>(),
      triggerHandler: GetIt.instance<NudgeTriggerHandler>(),
      notificationService: GetIt.instance<NotificationService>(),
    );
  }

  /// Factory method for testing with mocks
  static BackgroundTaskRegistrar forTesting({
    AdvancedLogger? logger,
    NudgeService? nudgeService,
    NudgeTriggerHandler? triggerHandler,
    NotificationService? notificationService,
  }) {
    return BackgroundTaskRegistrar(
      logger: logger ?? MockAdvancedLogger(),
      nudgeService: nudgeService ?? MockNudgeService(),
      triggerHandler: triggerHandler ?? MockNudgeTriggerHandler(),
      notificationService: notificationService ?? MockNotificationService(),
    );
  }
}

/// Mock classes for testing
class MockAdvancedLogger implements AdvancedLogger {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockNudgeService implements NudgeService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockNudgeTriggerHandler implements NudgeTriggerHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockNotificationService implements NotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}