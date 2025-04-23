// lib/services/notification_service.dart
//
// Copyright (c) 2025 Milo Health Technologies
// Version: 1.2.0
//
// General notification service for the Milo app.
// Handles app-wide notifications except for therapeutic nudges,
// which are managed by NudgeNotificationHelper.

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:get_it/get_it.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import '../utils/advanced_logger.dart';
import 'nudge_notification_helper.dart';

/// Notification status for tracking
enum NotificationStatus {
  uninitialized,
  initializing,
  ready,
  permissionDenied,
  permissionPermanentlyDenied,
  failed,
}

/// General notification service that handles all non-therapeutic notifications
class NotificationService {
  // Singleton access via GetIt
  static NotificationService get instance => GetIt.instance<NotificationService>();

  // Notification plugin
  final FlutterLocalNotificationsPlugin _notificationsPlugin;

  // Loggers
  final Logger _logger;
  final AdvancedLogger _advancedLogger;

  // Shared preferences for persistence
  final SharedPreferences _preferences;

  // Dependencies
  final DeviceInfoPlugin _deviceInfo;

  // Service status
  NotificationStatus _status = NotificationStatus.uninitialized;
  bool _isInitialized = false;
  Completer<bool>? _initCompleter;

  // Reserved notification IDs
  static const int _reservedIdStart = 100;
  static const int _reservedIdEnd = 500;

  // Stream controller for notification events
  final StreamController<Map<String, dynamic>> _notificationStreamController =
  StreamController<Map<String, dynamic>>.broadcast();

  // Channel IDs for different notification types
  static const String _checkInChannelId = 'milo_checkin_channel';
  static const String _reminderChannelId = 'milo_reminder_channel';
  static const String _systemChannelId = 'milo_system_channel';

  // Notification IDs
  static const int _checkInNotificationId = 101;
  static const int _memoryReminderNotificationId = 102;
  static const int _systemNotificationId = 103;

  // Platform version caching
  int? _androidApiLevel;
  String? _iOSVersion;

  // App lifecycle state
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  // Test mode flag
  bool _isInTestMode = false;

  /// Stream of notification events
  Stream<Map<String, dynamic>> get notificationStream => _notificationStreamController.stream;

  /// Current status of the notification service
  NotificationStatus get status => _status;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Constructor with dependency injection
  NotificationService({
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    Logger? logger,
    AdvancedLogger? advancedLogger,
    SharedPreferences? preferences,
    DeviceInfoPlugin? deviceInfo,
  }) :
        _notificationsPlugin = notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
        _logger = logger ?? Logger('NotificationService'),
        _advancedLogger = advancedLogger ?? AdvancedLogger(tag: 'Notifications'),
        _preferences = preferences ?? SharedPreferences.getInstance() as SharedPreferences,
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  /// Register with GetIt service locator
  static Future<void> registerService() async {
    if (!GetIt.instance.isRegistered<NotificationService>()) {
      final sharedPrefs = await SharedPreferences.getInstance();

      GetIt.instance.registerSingleton<NotificationService>(
          NotificationService(preferences: sharedPrefs)
      );

      // Also check and register the NudgeNotificationHelper
      if (!GetIt.instance.isRegistered<NudgeNotificationHelper>()) {
        await NudgeNotificationHelper.registerService();
      }
    }
  }

  /// Initialize the notification service with robust error handling and lifecycle integration
  Future<bool> initialize() async {
    // Prevent double initialization
    if (_isInitialized) return true;

    // Handle concurrent initialization attempts
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<bool>();
    _status = NotificationStatus.initializing;

    try {
      _advancedLogger.info('Initializing NotificationService');

      // Check platform versions for compatibility
      await _checkPlatformCompatibility();

      // Register lifecycle observer
      WidgetsBinding.instance.addObserver(_AppLifecycleObserver(this));

      // Load saved state
      await _loadServiceState();

      // Define platform-specific initialization settings
      final AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
        requestAlertPermission: false, // We'll request permissions separately
        requestBadgePermission: false,
        requestSoundPermission: false,
        onDidReceiveLocalNotification: _onDidReceiveLocalNotification,
      );

      final InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      // Initialize the plugin with proper callback handling
      final initialized = await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      );

      if (initialized != true) {
        throw Exception('Notification plugin initialization failed');
      }

      // Create notification channels (Android only)
      if (Platform.isAndroid) {
        await _createNotificationChannels();
      }

      // Coordinate with NudgeNotificationHelper to ensure ID ranges don't conflict
      if (GetIt.instance.isRegistered<NudgeNotificationHelper>()) {
        await NudgeNotificationHelper.instance.registerReservedIdRange(
            _reservedIdStart,
            _reservedIdEnd
        );
      }

      // Request permission with proper handling
      final permissionResult = await _requestPermissions();

      if (permissionResult.isGranted) {
        _status = NotificationStatus.ready;
        _isInitialized = true;
        _saveServiceState();
        _advancedLogger.info('NotificationService initialized successfully');
      } else if (permissionResult.isPermanentlyDenied) {
        _status = NotificationStatus.permissionPermanentlyDenied;
        _advancedLogger.warning(
            'Notification permission permanently denied. Service partially initialized.'
        );
      } else {
        _status = NotificationStatus.permissionDenied;
        _advancedLogger.warning(
            'Notification permission denied. Service partially initialized.'
        );
      }

      // Recovery from previous state if needed
      await _recoverFromPreviousState();

      _initCompleter!.complete(_isInitialized);
      return _isInitialized;
    } catch (e, stackTrace) {
      _status = NotificationStatus.failed;
      _advancedLogger.error(
        'Failed to initialize NotificationService',
        error: e,
        stackTrace: stackTrace,
      );

      _initCompleter!.complete(false);
      return false;
    } finally {
      _initCompleter = null;
    }
  }

  /// Check platform versions for compatibility
  Future<void> _checkPlatformCompatibility() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        _androidApiLevel = androidInfo.version.sdkInt;

        if (_androidApiLevel! < 21) { // Lollipop
          _advancedLogger.warning(
              'Android API level $_androidApiLevel detected. Some notification features may not work.'
          );
        }
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _iOSVersion = iosInfo.systemVersion;

        final versionParts = _iOSVersion!.split('.');
        final majorVersion = int.tryParse(versionParts[0]) ?? 0;

        if (majorVersion < 10) {
          _advancedLogger.warning(
              'iOS version $_iOSVersion detected. Some notification features may not work.'
          );
        }
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to check platform compatibility',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    try {
      // Only supported on Android 8.0+
      if (_androidApiLevel != null && _androidApiLevel! < 26) {
        _logger.info('Skipping notification channel creation for Android API level $_androidApiLevel');
        return;
      }

      // Check-in channel
      final AndroidNotificationChannel checkInChannel = AndroidNotificationChannel(
        _checkInChannelId,
        'Milo Check-ins',
        description: 'Friendly Milo check-ins',
        importance: Importance.high,
      );

      // Reminder channel
      final AndroidNotificationChannel reminderChannel = AndroidNotificationChannel(
        _reminderChannelId,
        'Memory Reminders',
        description: 'Reminders to record memories',
        importance: Importance.high,
      );

      // System channel
      final AndroidNotificationChannel systemChannel = AndroidNotificationChannel(
        _systemChannelId,
        'System Notifications',
        description: 'Important system messages',
        importance: Importance.high,
      );

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation
      AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannels([
        checkInChannel,
        reminderChannel,
        systemChannel,
      ]);

      _logger.info('Created notification channels');
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to create notification channels',
        error: e,
        stackTrace: stackTrace,
      );
      // Don't rethrow - channels are not critical, app can function without them
    }
  }

  /// Request notification permission with comprehensive status handling
  Future<PermissionStatus> _requestPermissions() async {
    try {
      if (Platform.isIOS) {
        // For iOS, use the plugin's permission method
        final result = await _notificationsPlugin
            .resolvePlatformSpecificImplementation
        IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          critical: true,
        ) ?? false;

        return result ? PermissionStatus.granted : PermissionStatus.denied;
      } else {
        // For Android
        final status = await Permission.notification.status;

        if (status.isGranted) {
          return PermissionStatus.granted;
        } else if (status.isDenied) {
          final result = await Permission.notification.request();
          return result;
        } else if (status.isPermanentlyDenied) {
          // Save this state to show settings guidance
          await _preferences.setBool('showPermissionSettings', true);
          return PermissionStatus.permanentlyDenied;
        } else {
          return status;
        }
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to request notification permission',
        error: e,
        stackTrace: stackTrace,
      );
      return PermissionStatus.denied;
    }
  }

  /// Check if we need to show permission settings guidance
  Future<bool> needsPermissionSettingsGuidance() async {
    return _preferences.getBool('showPermissionSettings') ?? false;
  }

  /// Open app settings to enable notifications
  Future<void> openNotificationSettings() async {
    try {
      await openAppSettings();
      // Reset the flag once we've shown guidance
      await _preferences.setBool('showPermissionSettings', false);
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to open notification settings',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Save service state for recovery
  Future<void> _saveServiceState() async {
    try {
      final state = {
        'isInitialized': _isInitialized,
        'status': _status.index,
        'activeNotifications': [], // IDs of currently active notifications
        'savedTimestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await _preferences.setString('notificationServiceState', jsonEncode(state));
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to save service state',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Load service state
  Future<void> _loadServiceState() async {
    try {
      final stateJson = _preferences.getString('notificationServiceState');
      if (stateJson == null) return;

      final state = jsonDecode(stateJson) as Map<String, dynamic>;

      // We don't restore isInitialized - that happens only via initialize()
      _status = NotificationStatus.values[state['status'] as int? ?? 0];

      // Record load time for recovery logic
      await _preferences.setInt('lastLoadTimestamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to load service state',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Recover from previous state after crashes or unexpected terminations
  Future<void> _recoverFromPreviousState() async {
    try {
      // Check for crash or unexpected termination
      final lastSavedTimestamp = _preferences.getInt('savedTimestamp') ?? 0;
      final lastLoadTimestamp = _preferences.getInt('lastLoadTimestamp') ?? 0;

      // If saved timestamp is more recent than load timestamp,
      // we might have crashed or been terminated unexpectedly
      if (lastSavedTimestamp > lastLoadTimestamp) {
        _logger.info('Detected potential crash or unexpected termination. Recovering state...');

        // Reload any scheduled notifications
        // For simplicity, we'll just reschedule the check-in notification
        await scheduleCheckInNotifications();
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to recover from previous state',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle app lifecycle state changes
  void _handleAppLifecycleStateChange(AppLifecycleState state) {
    try {
      _appLifecycleState = state;
      _logger.info('App lifecycle state changed to: $state');

      switch (state) {
        case AppLifecycleState.resumed:
        // App comes to foreground - refresh permissions
          _refreshPermissionStatus();
          break;
        case AppLifecycleState.paused:
        // App goes to background - save state
          _saveServiceState();
          break;
        case AppLifecycleState.detached:
        // App is detached from UI (may be terminated)
          _saveServiceState();
          break;
        default:
        // Other states
          break;
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to handle app lifecycle state change',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Refresh permission status after app resume
  Future<void> _refreshPermissionStatus() async {
    try {
      if (_status == NotificationStatus.permissionDenied ||
          _status == NotificationStatus.permissionPermanentlyDenied) {
        final status = await Permission.notification.status;

        if (status.isGranted && _status != NotificationStatus.ready) {
          // Permission granted while app was in background
          _status = NotificationStatus.ready;
          _isInitialized = true;
          _saveServiceState();
          _advancedLogger.info('Permission status changed to granted. Service now ready.');
        }
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to refresh permission status',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// iOS notification received in foreground
  void _onDidReceiveLocalNotification(
      int id, String? title, String? body, String? payload) {
    try {
      _logger.info('Received iOS foreground notification: $id, $title');

      // Broadcast to stream for any listeners
      _notificationStreamController.add({
        'id': id,
        'title': title,
        'body': body,
        'payload': payload,
        'event': 'receivedForeground',
      });

      // For older iOS versions that don't show banner notifications in foreground
      if (_iOSVersion != null) {
        final versionParts = _iOSVersion!.split('.');
        final majorVersion = int.tryParse(versionParts[0]) ?? 0;

        if (majorVersion < 10) {
          // Would need to show a custom alert here for older iOS
          // This is implementation-specific and would be handled in UI
        }
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error handling iOS foreground notification',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Called when a notification is tapped by the user
  void _onDidReceiveNotificationResponse(
      NotificationResponse response) async {
    try {
      final String? payload = response.payload;
      _logger.info('Notification tapped with payload: $payload');

      // Broadcast to stream for any listeners
      _notificationStreamController.add({
        'id': response.id,
        'payload': payload,
        'actionId': response.actionId,
        'event': 'tapped',
      });

      // For testing
      if (_isInTestMode) {
        await _preferences.setString('lastTappedNotification', jsonEncode({
          'id': response.id,
          'payload': payload,
          'actionId': response.actionId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      }

      // Handle different notification types based on payload
      if (payload == null) return;

      if (payload.startsWith('checkin:')) {
        // Handle check-in notification taps
        _handleCheckInTap(payload);
      } else if (payload.startsWith('memory:')) {
        // Handle memory reminder notification taps
        _handleMemoryReminderTap(payload);
      } else if (payload.startsWith('system:')) {
        // Handle system notification taps
        _handleSystemNotificationTap(payload);
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error handling notification response',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle check-in notification tap
  Future<void> _handleCheckInTap(String payload) async {
    try {
      // Implementation would navigate to check-in screen
      // This is UI-specific and would be handled via the stream
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error handling check-in notification tap',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle memory reminder notification tap
  Future<void> _handleMemoryReminderTap(String payload) async {
    try {
      // Implementation would navigate to memory recording screen
      // This is UI-specific and would be handled via the stream
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error handling memory reminder notification tap',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle system notification tap
  Future<void> _handleSystemNotificationTap(String payload) async {
    try {
      // Implementation would handle system notification
      // This is UI-specific and would be handled via the stream
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error handling system notification tap',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Schedule periodic check-in notifications
  Future<bool> scheduleCheckInNotifications({
    Duration interval = const Duration(hours: 6),
  }) async {
    try {
      // Check if initialized
      if (!_isInitialized) {
        _logger.warning('Cannot schedule check-in notifications: service not initialized');
        return false;
      }

      // Check if nudges are scheduled to avoid conflicts
      if (_shouldDeconflictWithNudges()) {
        final nudgeService = NudgeNotificationHelper.instance;
        if (await nudgeService.areNudgesScheduledNow()) {
          _logger.info('Deferring check-in notification due to active nudge');

          // Reschedule for later
          Future.delayed(const Duration(hours: 1), () {
            scheduleCheckInNotifications(interval: interval);
          });

          return true;
        }
      }

      // Check platform version for compatibility
      RepeatInterval repeatInterval;

      if (Platform.isAndroid && _androidApiLevel != null && _androidApiLevel! >= 23) {
        // For Android 6.0+, we can use hourly intervals
        repeatInterval = RepeatInterval.hourly;
      } else {
        // For older versions, hourly is not reliable, use daily
        repeatInterval = RepeatInterval.daily;
      }

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _checkInChannelId,
        'Milo Check-ins',
        channelDescription: 'Friendly Milo check-ins',
        importance: Importance.high,
        priority: Priority.high,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.periodicallyShow(
        _checkInNotificationId,
        '🐾 Milo Check-in!',
        'Hey there! Want to talk or record a memory?',
        repeatInterval,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'checkin:general',
      );

      _logger.info('Scheduled check-in notifications with ${interval.inHours} hour interval');

      // Save for recovery
      await _saveServiceState();

      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to schedule check-in notifications',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Check if we should deconflict with nudge notifications
  bool _shouldDeconflictWithNudges() {
    return GetIt.instance.isRegistered<NudgeNotificationHelper>() &&
        NudgeNotificationHelper.instance.isInitialized;
  }

  /// Schedule a memory reminder notification
  Future<bool> scheduleMemoryReminder({
    required DateTime reminderTime,
    String? title,
    String? body,
  }) async {
    try {
      // Check if initialized
      if (!_isInitialized) {
        _logger.warning('Cannot schedule memory reminder: service not initialized');
        return false;
      }

      // Check platform compatibility
      if (Platform.isAndroid && _androidApiLevel != null && _androidApiLevel! < 23) {
        _logger.warning('Exact timing not reliable on Android API level $_androidApiLevel');
        // Continue anyway, but warn
      }

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _reminderChannelId,
        'Memory Reminders',
        channelDescription: 'Reminders to record memories',
        importance: Importance.high,
        priority: Priority.high,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final payload = 'memory:reminder';

      // Use timezone-aware scheduling
      final scheduledDate = TZDateTime.from(reminderTime, local);

      await _notificationsPlugin.zonedSchedule(
        _memoryReminderNotificationId,
        title ?? '📝 Memory Reminder',
        body ?? "It's time to record your memory!",
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );

      _logger.info('Scheduled memory reminder for $reminderTime');

      // Save for recovery
      await _saveServiceState();

      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to schedule memory reminder',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Show a system notification
  Future<bool> showSystemNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      // Check if initialized
      if (!_isInitialized) {
        _logger.warning('Cannot show system notification: service not initialized');
        return false;
      }

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _systemChannelId,
        'System Notifications',
        channelDescription: 'Important system messages',
        importance: Importance.high,
        priority: Priority.high,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        _systemNotificationId,
        title,
        body,
        notificationDetails,
        payload: payload ?? 'system:general',
      );

      _logger.info('Showed system notification: $title');

      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to show system notification',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Show immediate test notification for debugging and testing
  Future<bool> showImmediateTestNotification() async {
    try {
      // Check if initialized
      if (!_isInitialized) {
        _logger.warning('Cannot show test notification: service not initialized');
        return false;
      }

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _systemChannelId,
        'System Notifications',
        channelDescription: 'Important system messages',
        importance: Importance.max,
        priority: Priority.high,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final testId = DateTime.now().millisecondsSinceEpoch % 10000;

      await _notificationsPlugin.show(
        testId,
        '🐾 Milo Test Notification',
        'This is a quick test notification. ID: $testId',
        notificationDetails,
        payload: 'system:test:$testId',
      );

      _logger.info('Showed immediate test notification with ID: $testId');

      // For test mode
      if (_isInTestMode) {
        await _preferences.setString('lastTestNotification', jsonEncode({
          'id': testId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      }

      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to show test notification',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Cancel a specific notification
  Future<bool> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
      _logger.info('Cancelled notification with ID: $id');
      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to cancel notification',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Cancel all notifications
  Future<bool> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      _logger.info('Cancelled all notifications');
      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to cancel all notifications',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Enable test mode for testing notifications
  void enableTestMode() {
    _isInTestMode = true;
    _logger.info('Test mode enabled for NotificationService');
  }

  /// Disable test mode
  void disableTestMode() {
    _isInTestMode = false;
    _logger.info('Test mode disabled for NotificationService');
  }

  /// Get last test notification data for verification
  Future<Map<String, dynamic>?> getLastTestNotificationData() async {
    try {
      final jsonStr = _preferences.getString('lastTestNotification');
      if (jsonStr == null) return null;

      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      _logger.warning('Failed to get last test notification data: $e');
      return null;
    }
  }

  /// Get last tapped notification data for verification
  Future<Map<String, dynamic>?> getLastTappedNotificationData() async {
    try {
      final jsonStr = _preferences.getString('lastTappedNotification');
      if (jsonStr == null) return null;

      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      _logger.warning('Failed to get last tapped notification data: $e');
      return null;
    }
  }

  /// Check if notification permission is granted
  Future<bool> isPermissionGranted() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.notification.status;
        return status.isGranted;
      } else if (Platform.isIOS) {
        // For iOS, we need to check differently
        // This is an approximation
        return _status == NotificationStatus.ready;
      }
      return false;
    } catch (e) {
      _logger.warning('Failed to check permission status: $e');
      return false;
    }
  }

  /// Cleanup resources on dispose
  Future<void> dispose() async {
    try {
      _notificationStreamController.close();
      _saveServiceState();
      _logger.info('NotificationService disposed');
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error during NotificationService disposal',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

/// App lifecycle observer for the notification service
class _AppLifecycleObserver with WidgetsBindingObserver {
  final NotificationService _service;

  _AppLifecycleObserver(this._service) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _service._handleAppLifecycleStateChange(state);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}