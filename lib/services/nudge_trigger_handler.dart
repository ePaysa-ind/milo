// lib/services/nudge_trigger_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/nudge_model.dart';
import '../services/nudge_service.dart';
import '../services/openai_service.dart';
import '../services/tts_service.dart';
import '../utils/advanced_logger.dart';

/// Simple service locator for dependency injection
/// In a real app, you would use a library like get_it
class ServiceLocator {
  final Map<Type, Object> _instances = {};

  void registerSingleton<T>(T instance) {
    _instances[T] = instance;
  }

  T get<T>() {
    final instance = _instances[T];
    if (instance == null) {
      throw Exception('No instance registered for type $T');
    }
    return instance as T;
  }
}

/// Custom exception for nudge trigger issues
class NudgeTriggerException implements Exception {
  final String message;
  final Object? cause;
  final DateTime timestamp;
  final String? code;

  NudgeTriggerException(
      this.message, {
        this.cause,
        this.code,
        DateTime? timestamp,
      }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'NudgeTriggerException: $message${code != null ? ' [Code: $code]' : ''}${cause != null ? ' (Cause: $cause)' : ''} at $timestamp';
}

/// Class that handles background triggers for therapeutic nudges
class NudgeTriggerHandler {
  static const String _tag = 'NudgeTriggerHandler';

  // Constants for workmanager task names
  static const String morningNudgeTask = 'com.milo.MORNING_NUDGE_TASK';
  static const String middayNudgeTask = 'com.milo.MIDDAY_NUDGE_TASK';
  static const String eveningNudgeTask = 'com.milo.EVENING_NUDGE_TASK';
  static const String unlockCounterTask = 'com.milo.UNLOCK_COUNTER_TASK';
  static const String nudgeTriggerCheckTask = 'com.milo.NUDGE_TRIGGER_CHECK_TASK';

  // Private constants for internal use
  static const String _lastUnlockTimeKey = 'last_unlock_timestamp';
  static const String _unlockCountKey = 'device_unlock_count_today';
  static const String _lastNudgeDateKey = 'last_nudge_date';
  static const String _morningNudgeDeliveredKey = 'morning_nudge_delivered_today';
  static const String _middayNudgeDeliveredKey = 'midday_nudge_delivered_today';
  static const String _eveningNudgeDeliveredKey = 'evening_nudge_delivered_today';

  // Set minimum time between unlock triggers to prevent multiple triggers
  // when user repeatedly unlocks device in short period
  static const int _minUnlockIntervalMinutes = 15;

  // Unlock threshold to trigger a nudge (e.g. after 5 unlocks)
  static const int _unlockThreshold = 5;

  // Dependencies
  final NudgeService _nudgeService;
  final FirebaseAuth _auth;

  // Method channel for device unlock detection
  static const MethodChannel _channel = MethodChannel('com.milo.unlock_detector');

  // Flag to track initialization
  bool _isInitialized = false;

  // Stream controller for unlock events
  final _unlockController = StreamController<DateTime>.broadcast();
  Stream<DateTime> get onDeviceUnlock => _unlockController.stream;

  // Constructor with required dependency
  NudgeTriggerHandler({
    required NudgeService nudgeService,
    required FirebaseAuth auth,
  }) :
        _nudgeService = nudgeService,
        _auth = auth;

  /// Initialize the trigger handler
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      AdvancedLogger.info(_tag, 'Initializing NudgeTriggerHandler');

      // Use Future.wait to run initialization steps concurrently and
      // ensure all steps are attempted even if one fails
      final results = await Future.wait([
        _initializeWorkManager().then((_) => true).catchError((e) {
          AdvancedLogger.error(_tag, 'Workmanager initialization failed', error: e);
          return false;
        }),
        _setupUnlockListener().then((_) => true).catchError((e) {
          AdvancedLogger.error(_tag, 'Unlock listener setup failed', error: e);
          return false;
        }),
        _resetDailyCountersIfNeeded().then((_) => true).catchError((e) {
          AdvancedLogger.error(_tag, 'Daily counter reset failed', error: e);
          return false;
        }),
        _scheduleTimeBasedNudgeTriggers().then((_) => true).catchError((e) {
          AdvancedLogger.error(_tag, 'Nudge trigger scheduling failed', error: e);
          return false;
        }),
      ], eagerError: false);

      // Check if all initialization steps succeeded
      final success = results.every((result) => result == true);

      if (success) {
        _isInitialized = true;
        AdvancedLogger.info(_tag, 'NudgeTriggerHandler initialized successfully');
        return true;
      } else {
        // If any step failed, clean up and return false
        await close();
        throw NudgeTriggerException(
          'One or more initialization steps failed',
          code: 'INIT_PARTIAL_FAILURE',
        );
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Failed to initialize NudgeTriggerHandler';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);
      // Clean up any resources that might have been initialized
      await close();
      throw NudgeTriggerException(
        errorMsg,
        cause: e,
        code: 'INIT_FAILURE',
      );
    }
  }

  /// Initialize workmanager for background tasks
  Future<void> _initializeWorkManager() async {
    try {
      AdvancedLogger.info(_tag, 'Initializing workmanager');

      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false, // Set to true only for development
      );

      AdvancedLogger.info(_tag, 'Workmanager initialized successfully');
    } catch (e, stackTrace) {
      final errorMsg = 'Failed to initialize workmanager';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);
      throw NudgeTriggerException(
        errorMsg,
        cause: e,
        code: 'WORKMANAGER_INIT_FAILURE',
      );
    }
  }

  /// Setup platform method channel listener for device unlock events
  Future<void> _setupUnlockListener() async {
    try {
      AdvancedLogger.info(_tag, 'Setting up unlock listener');

      // Set method call handler for the channel
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onDeviceUnlocked') {
          await _handleDeviceUnlock();
        }
      });

      // Register for unlock events with the platform side
      await _channel.invokeMethod('registerUnlockListener');

      AdvancedLogger.info(_tag, 'Unlock listener setup successfully');
    } catch (e, stackTrace) {
      final errorMsg = 'Failed to setup unlock listener';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);
      throw NudgeTriggerException(
        errorMsg,
        cause: e,
        code: 'UNLOCK_LISTENER_FAILURE',
      );
    }
  }

  /// Reset daily counters if it's a new day
  Future<void> _resetDailyCountersIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastNudgeDate = prefs.getString(_lastNudgeDateKey);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (lastNudgeDate != today) {
        AdvancedLogger.info(_tag, 'Resetting daily nudge counters',
            data: {'lastDate': lastNudgeDate, 'today': today});

        await prefs.setString(_lastNudgeDateKey, today);
        await prefs.setInt(_unlockCountKey, 0);
        await prefs.setBool(_morningNudgeDeliveredKey, false);
        await prefs.setBool(_middayNudgeDeliveredKey, false);
        await prefs.setBool(_eveningNudgeDeliveredKey, false);
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Error resetting daily counters';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);
      throw NudgeTriggerException(
        errorMsg,
        cause: e,
        code: 'COUNTER_RESET_FAILURE',
      );
    }
  }

  /// Schedule time-based nudge triggers for today
  Future<void> _scheduleTimeBasedNudgeTriggers() async {
    try {
      AdvancedLogger.info(_tag, 'Scheduling time-based nudge triggers');

      // Get user settings to check if time-based triggers are enabled
      final settings = _nudgeService.currentSettings;

      if (settings == null) {
        const errorMsg = 'User settings not available';
        AdvancedLogger.warning(_tag, errorMsg);
        throw NudgeTriggerException(
          errorMsg,
          code: 'SETTINGS_UNAVAILABLE',
        );
      }

      if (!settings.allowTimeBasedTrigger) {
        AdvancedLogger.info(_tag, 'Time-based triggers are disabled in user settings');
        return;
      }

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      int scheduledCount = 0;

      // Check for each time window
      for (final window in TimeWindow.values) {
        // Skip if this window's nudge was already delivered today
        final deliveredKey = _getDeliveredKeyForTimeWindow(window);
        final alreadyDelivered = prefs.getBool(deliveredKey) ?? false;

        if (alreadyDelivered) {
          AdvancedLogger.info(_tag, 'Nudge already delivered for time window',
              data: {'window': window.toString()});
          continue;
        }

        // Skip if this window is not enabled in user settings
        if (!(settings.enabledTimeWindows[window] ?? false)) {
          AdvancedLogger.info(_tag, 'Time window disabled in user settings',
              data: {'window': window.toString()});
          continue;
        }

        // Skip if this time window has already passed for today
        if (now.hour >= window.endHour) {
          AdvancedLogger.info(_tag, 'Time window already passed for today',
              data: {'window': window.toString(), 'currentHour': now.hour});
          continue;
        }

        // Schedule a one-time task for this window
        final taskName = _getTaskNameForTimeWindow(window);
        final initialDelayMinutes = _calculateInitialDelay(window, now);

        if (initialDelayMinutes > 0) {
          try {
            await Workmanager().registerOneOffTask(
              taskName,
              taskName,
              initialDelay: Duration(minutes: initialDelayMinutes),
              constraints: Constraints(
                networkType: NetworkType.connected,
                requiresBatteryNotLow: false,
              ),
              existingWorkPolicy: ExistingWorkPolicy.replace,
            );

            scheduledCount++;
            AdvancedLogger.info(_tag, 'Scheduled time-based nudge trigger',
                data: {
                  'window': window.toString(),
                  'taskName': taskName,
                  'initialDelayMinutes': initialDelayMinutes
                });
          } catch (e, stackTrace) {
            // Log error but continue with other windows
            AdvancedLogger.error(_tag, 'Failed to schedule task for time window',
                data: {'window': window.toString()}, error: e, stackTrace: stackTrace);
          }
        }
      }

      if (scheduledCount == 0) {
        AdvancedLogger.warning(_tag, 'No time-based nudge triggers were scheduled');
      } else {
        AdvancedLogger.info(_tag, 'Time-based nudge triggers scheduled successfully',
            data: {'scheduledCount': scheduledCount});
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Error scheduling time-based nudge triggers';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);
      throw NudgeTriggerException(
        errorMsg,
        cause: e,
        code: 'SCHEDULING_FAILURE',
      );
    }
  }

  /// Handle device unlock event
  Future<void> _handleDeviceUnlock() async {
    try {
      // Record the current time
      final now = DateTime.now();

      // Notify any listeners about the unlock event
      if (!_unlockController.isClosed) {
        _unlockController.add(now);
      }

      // Get preferences
      final prefs = await SharedPreferences.getInstance();

      // Check if enough time has passed since last unlock
      final lastUnlockTime = prefs.getInt(_lastUnlockTimeKey) ?? 0;
      final lastUnlock = DateTime.fromMillisecondsSinceEpoch(lastUnlockTime);

      final minutesSinceLastUnlock =
          now.difference(lastUnlock).inMinutes;

      if (minutesSinceLastUnlock < _minUnlockIntervalMinutes) {
        AdvancedLogger.info(_tag, 'Ignoring unlock event: too soon since last unlock',
            data: {'minutesSinceLastUnlock': minutesSinceLastUnlock});
        return;
      }

      // Update last unlock time
      await prefs.setInt(_lastUnlockTimeKey, now.millisecondsSinceEpoch);

      // Increment unlock counter
      final unlockCount = (prefs.getInt(_unlockCountKey) ?? 0) + 1;
      await prefs.setInt(_unlockCountKey, unlockCount);

      AdvancedLogger.info(_tag, 'Device unlock recorded',
          data: {'unlockCount': unlockCount});

      // Check if we should trigger a nudge based on unlock count
      if (unlockCount % _unlockThreshold == 0) {
        await _triggerUnlockBasedNudge();
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Error handling device unlock';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);
      // Non-fatal error in this case since it's triggered by system events
      // We don't want to crash the app, but we should report it
      _reportNonFatalError(errorMsg, e, 'UNLOCK_HANDLING_FAILURE');
    }
  }

  /// Report a non-fatal error that should be logged but not crash the app
  void _reportNonFatalError(String message, Object? error, String code) {
    // In a real app, this could send the error to a crash reporting service
    // or analytics platform for monitoring
    AdvancedLogger.error(_tag, 'Non-fatal error: $message',
        data: {'code': code}, error: error);
  }

  /// Trigger a nudge based on device unlock pattern
  Future<void> _triggerUnlockBasedNudge() async {
    try {
      AdvancedLogger.info(_tag, 'Triggering unlock-based nudge');

      // Check if user is logged in and nudge service is initialized
      if (_auth.currentUser == null) {
        const errorMsg = 'Cannot trigger nudge: user not logged in';
        AdvancedLogger.warning(_tag, errorMsg);
        throw NudgeTriggerException(
          errorMsg,
          code: 'USER_NOT_AUTHENTICATED',
        );
      }

      // Check if a nudge can be delivered now according to service rules
      final canDeliver = await _nudgeService.canDeliverNudgeNow();

      if (!canDeliver) {
        const errorMsg = 'Nudge cannot be delivered according to service rules';
        AdvancedLogger.info(_tag, errorMsg);
        throw NudgeTriggerException(
          errorMsg,
          code: 'DELIVERY_NOT_ALLOWED',
        );
      }

      // Deliver the nudge
      final result = await _nudgeService.handleDeviceUnlock();

      AdvancedLogger.info(_tag, 'Unlock-based nudge trigger processed',
          data: {'success': result != null});

      return result;
    } catch (e, stackTrace) {
      final errorMsg = 'Error triggering unlock-based nudge';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);

      // Determine if this is a critical error or expected behavior
      if (e is NudgeTriggerException &&
          (e.code == 'USER_NOT_AUTHENTICATED' || e.code == 'DELIVERY_NOT_ALLOWED')) {
        // These are expected conditions, not critical errors
        return null;
      }

      // For other errors, report as non-fatal
      _reportNonFatalError(errorMsg, e, 'UNLOCK_TRIGGER_FAILURE');
      return null;
    }
  }

  /// Trigger a nudge for a specific time window
  Future<bool> triggerTimeWindowNudge(TimeWindow window) async {
    try {
      AdvancedLogger.info(_tag, 'Triggering time window nudge',
          data: {'window': window.toString()});

      // Check if user is logged in
      if (_auth.currentUser == null) {
        AdvancedLogger.warning(_tag, 'Cannot trigger nudge: user not logged in');
        return false;
      }

      // Check if a nudge can be delivered now according to service rules
      final canDeliver = await _nudgeService.canDeliverNudgeNow();

      if (!canDeliver) {
        AdvancedLogger.info(_tag, 'Nudge cannot be delivered now according to service rules');
        return false;
      }

      // Deliver the nudge with the specified time window category
      final result = await _nudgeService.deliverNudge(
        triggerType: 'timeWindow_${window.toString().split('.').last}',
      );

      if (result.success && result.data != null) {
        // Mark this window's nudge as delivered for today
        final prefs = await SharedPreferences.getInstance();
        final deliveredKey = _getDeliveredKeyForTimeWindow(window);
        await prefs.setBool(deliveredKey, true);

        AdvancedLogger.info(_tag, 'Time window nudge delivered successfully',
            data: {'window': window.toString()});
        return true;
      } else {
        AdvancedLogger.warning(_tag, 'Failed to deliver time window nudge',
            data: {'window': window.toString(), 'error': result.errorMessage});
        return false;
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error triggering time window nudge',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Calculate initial delay for scheduling time-based nudge
  int _calculateInitialDelay(TimeWindow window, DateTime now) {
    // Get the target hour within the window (randomly chosen)
    final targetHour = window.startHour +
        (window.endHour - window.startHour) ~/ 2;

    // Get random minute within the hour (0-59)
    final random = DateTime.now().millisecondsSinceEpoch % 60;
    final targetMinute = random;

    // Create the target time for today
    final targetTime = DateTime(
        now.year, now.month, now.day, targetHour, targetMinute);

    // Calculate minutes until target time
    int minutesUntilTarget = targetTime.difference(now).inMinutes;

    // If target time has already passed today, return 0
    if (minutesUntilTarget < 0) {
      return 0;
    }

    return minutesUntilTarget;
  }

  /// Get task name for a specific time window
  String _getTaskNameForTimeWindow(TimeWindow window) {
    switch (window) {
      case TimeWindow.morning:
        return morningNudgeTask;
      case TimeWindow.midday:
        return middayNudgeTask;
      case TimeWindow.evening:
        return eveningNudgeTask;
    }
  }

  /// Get preference key for tracking delivery status for a time window
  String _getDeliveredKeyForTimeWindow(TimeWindow window) {
    switch (window) {
      case TimeWindow.morning:
        return _morningNudgeDeliveredKey;
      case TimeWindow.midday:
        return _middayNudgeDeliveredKey;
      case TimeWindow.evening:
        return _eveningNudgeDeliveredKey;
    }
  }

  /// Process background tasks
  static Future<void> processBackgroundTask(String taskName) async {
    AdvancedLogger.info(_tag, 'Processing background task',
        data: {'taskName': taskName});

    try {
      // Initialize services using service locator pattern
      final serviceLocator = await _initializeServiceLocator();
      final triggerHandler = serviceLocator.get<NudgeTriggerHandler>();

      switch (taskName) {
        case morningNudgeTask:
          await triggerHandler._processTimeWindowTask(TimeWindow.morning);
          break;
        case middayNudgeTask:
          await triggerHandler._processTimeWindowTask(TimeWindow.midday);
          break;
        case eveningNudgeTask:
          await triggerHandler._processTimeWindowTask(TimeWindow.evening);
          break;
        case unlockCounterTask:
          await triggerHandler._processUnlockCounterTask();
          break;
        case nudgeTriggerCheckTask:
          await triggerHandler._processNudgeTriggerCheck();
          break;
        default:
          AdvancedLogger.warning(_tag, 'Unknown task name',
              data: {'taskName': taskName});
      }

      AdvancedLogger.info(_tag, 'Background task processed successfully',
          data: {'taskName': taskName});
    } catch (e, stackTrace) {
      final errorMsg = 'Error processing background task';
      AdvancedLogger.error(_tag, errorMsg,
          data: {'taskName': taskName}, error: e, stackTrace: stackTrace);
      throw NudgeTriggerException(
        'Failed to process background task: $taskName',
        cause: e,
        code: 'BACKGROUND_TASK_FAILURE',
      );
    }
  }

  /// Initialize service locator for background tasks
  static Future<ServiceLocator> _initializeServiceLocator() async {
    // This is a placeholder - in a real app, you would use a service
    // locator library like get_it to initialize and access services
    // in the background context
    final locator = ServiceLocator();

    // Register services
    final firestore = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    final nudgeService = NudgeService(
      firestore: firestore,
      auth: auth,
      openAIService: locator.get<OpenAIService>(),
      ttsService: locator.get<TTSService>(),
    );
    await nudgeService.initialize();

    final triggerHandler = NudgeTriggerHandler(
      nudgeService: nudgeService,
      auth: auth,
    );

    // Register the trigger handler
    locator.registerSingleton<NudgeTriggerHandler>(triggerHandler);

    return locator;
  }

  /// Process a time window task
  Future<void> _processTimeWindowTask(TimeWindow window) async {
    try {
      AdvancedLogger.info(_tag, 'Processing time window task',
          data: {'window': window.toString()});

      // Trigger a nudge for this time window
      final result = await triggerTimeWindowNudge(window);

      AdvancedLogger.info(_tag, 'Time window task processed',
          data: {'window': window.toString(), 'success': result});
    } catch (e, stackTrace) {
      final errorMsg = 'Error processing time window task';
      AdvancedLogger.error(_tag, errorMsg,
          data: {'window': window.toString()}, error: e, stackTrace: stackTrace);
      throw NudgeTriggerException(
        '$errorMsg: ${window.toString()}',
        cause: e,
        code: 'TIME_WINDOW_TASK_FAILURE',
      );
    }
  }

  /// Process unlock counter task
  Future<void> _processUnlockCounterTask() async {
    try {
      AdvancedLogger.info(_tag, 'Processing unlock counter task');

      // Reset unlock counter at the start of the day
      final prefs = await SharedPreferences.getInstance();
      final lastNudgeDate = prefs.getString(_lastNudgeDateKey);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (lastNudgeDate != today) {
        await prefs.setInt(_unlockCountKey, 0);
        await prefs.setString(_lastNudgeDateKey, today);

        AdvancedLogger.info(_tag, 'Unlock counter reset for new day');
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Error processing unlock counter task';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);
      throw NudgeTriggerException(
        errorMsg,
        cause: e,
        code: 'UNLOCK_COUNTER_TASK_FAILURE',
      );
    }
  }

  /// Process nudge trigger check
  Future<void> _processNudgeTriggerCheck() async {
    try {
      AdvancedLogger.info(_tag, 'Processing nudge trigger check');

      // Check if conditions are right for triggering a nudge
      final canDeliver = await _nudgeService.canDeliverNudgeNow();

      if (canDeliver) {
        // Get the current time window if any
        final currentWindow = TimeWindow.currentTimeWindow();

        if (currentWindow != null) {
          // Check if this window's nudge has already been delivered today
          final prefs = await SharedPreferences.getInstance();
          final deliveredKey = _getDeliveredKeyForTimeWindow(currentWindow);
          final alreadyDelivered = prefs.getBool(deliveredKey) ?? false;

          if (!alreadyDelivered) {
            // Trigger a nudge for this time window
            await triggerTimeWindowNudge(currentWindow);
          }
        }
      }

      AdvancedLogger.info(_tag, 'Nudge trigger check completed',
          data: {'canDeliver': canDeliver});
    } catch (e, stackTrace) {
      final errorMsg = 'Error processing nudge trigger check';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);
      throw NudgeTriggerException(
        errorMsg,
        cause: e,
        code: 'TRIGGER_CHECK_FAILURE',
      );
    }
  }

  /// Close all resources
  Future<void> close() async {
    try {
      AdvancedLogger.info(_tag, 'Closing NudgeTriggerHandler');

      // Unregister platform channel listener
      try {
        await _channel.invokeMethod('unregisterUnlockListener');
      } catch (e) {
        AdvancedLogger.warning(_tag, 'Error unregistering unlock listener', error: e);
        // Continue with other cleanup
      }

      // Cancel any scheduled workmanager tasks
      try {
        await Workmanager().cancelAll();
      } catch (e) {
        AdvancedLogger.warning(_tag, 'Error canceling workmanager tasks', error: e);
        // Continue with other cleanup
      }

      // Close stream controllers
      if (!_unlockController.isClosed) {
        await _unlockController.close();
      }

      AdvancedLogger.info(_tag, 'NudgeTriggerHandler closed successfully');
    } catch (e, stackTrace) {
      final errorMsg = 'Error closing NudgeTriggerHandler';
      AdvancedLogger.error(_tag, errorMsg, error: e, stackTrace: stackTrace);
      throw NudgeTriggerException(
        errorMsg,
        cause: e,
        code: 'CLOSE_FAILURE',
      );
    }
  }
}

/// Background task callback function registered with Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Initialize services using the service locator
      await NudgeTriggerHandler.processBackgroundTask(taskName);
      return true;
    } catch (e, stackTrace) {
      AdvancedLogger.error('BackgroundTask', 'Background task failed',
          error: e, stackTrace: stackTrace);
      return false;
    }
  });
}