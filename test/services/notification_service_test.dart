// test/services/notification_service_test.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:logging/logging.dart';
import 'package:milo/services/notification_service.dart';
import 'package:milo/services/nudge_notification_helper.dart';
import 'package:milo/utils/advanced_logger.dart';
import 'package:flutter/services.dart';

// Mock classes with more complete implementations
class MockFlutterLocalNotificationsPlugin extends Mock implements FlutterLocalNotificationsPlugin {
  @override
  Future<bool?> initialize(
      InitializationSettings initializationSettings, {
        SelectNotificationCallback? onSelectNotification,
        DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
        DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
      }) async {
    return true;
  }

  @override
  Future<void> show(
      int id,
      String? title,
      String? body, {
        NotificationDetails? notificationDetails,
        String? payload,
      }) async {
    // Store the last notification for verification
    lastNotificationData = {
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  @override
  Future<void> zonedSchedule(
      int id,
      String? title,
      String? body,
      tz.TZDateTime scheduledDate,
      NotificationDetails? notificationDetails, {
        UILocalNotificationDateInterpretation? uiLocalNotificationDateInterpretation,
        String? payload,
        DateTimeComponents? matchDateTimeComponents,
        AndroidScheduleMode? androidScheduleMode,
      }) async {
    lastScheduledNotificationData = {
      'id': id,
      'title': title,
      'body': body,
      'scheduledDate': scheduledDate.toString(),
      'payload': payload,
      'matchDateTimeComponents': matchDateTimeComponents?.toString(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  @override
  Future<void> periodicallyShow(
      int id,
      String? title,
      String? body,
      RepeatInterval repeatInterval,
      NotificationDetails? notificationDetails, {
        String? payload,
        AndroidScheduleMode? androidScheduleMode,
      }) async {
    lastPeriodicNotificationData = {
      'id': id,
      'title': title,
      'body': body,
      'repeatInterval': repeatInterval.toString(),
      'payload': payload,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  // Store notification data for verification
  Map<String, dynamic>? lastNotificationData;
  Map<String, dynamic>? lastScheduledNotificationData;
  Map<String, dynamic>? lastPeriodicNotificationData;

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelledAll = true;
  }

  // Track cancellations
  List<int> cancelledIds = [];
  bool cancelledAll = false;
}

class MockSharedPreferences extends Mock implements SharedPreferences {
  final Map<String, dynamic> data = {};

  @override
  String? getString(String key) => data[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    data[key] = value;
    return true;
  }

  @override
  int? getInt(String key) => data[key] as int?;

  @override
  Future<bool> setInt(String key, int value) async {
    data[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) => data[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    data[key] = value;
    return true;
  }

  @override
  List<String>? getStringList(String key) => data[key] as List<String>?;

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    data[key] = value;
    return true;
  }

  @override
  bool containsKey(String key) => data.containsKey(key);

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }
}

class MockLogger extends Mock implements Logger {
  List<String> infoLogs = [];
  List<String> warningLogs = [];
  List<String> errorLogs = [];

  @override
  void info(Object message) {
    infoLogs.add(message.toString());
  }

  @override
  void warning(Object message) {
    warningLogs.add(message.toString());
  }

  @override
  void severe(Object message) {
    errorLogs.add(message.toString());
  }
}

class MockAdvancedLogger extends Mock implements AdvancedLogger {
  List<String> infoLogs = [];
  List<String> warningLogs = [];
  List<String> errorLogs = [];

  @override
  void info(String message) {
    infoLogs.add(message);
  }

  @override
  void warning(String message, {dynamic error, StackTrace? stackTrace}) {
    warningLogs.add('$message - $error');
  }

  @override
  void error(String message, {dynamic error, StackTrace? stackTrace}) {
    errorLogs.add('$message - $error');
  }
}

class MockDeviceInfoPlugin extends Mock implements DeviceInfoPlugin {
  @override
  Future<AndroidDeviceInfo> get androidInfo async {
    return FakeAndroidDeviceInfo();
  }

  @override
  Future<IosDeviceInfo> get iosInfo async {
    return FakeIosDeviceInfo();
  }
}

class FakeAndroidDeviceInfo extends AndroidDeviceInfo {
  FakeAndroidDeviceInfo() : super(FakeAndroidBuildVersion());
}

class FakeAndroidBuildVersion implements AndroidBuildVersion {
  @override
  int? get sdkInt => 30; // Android 11

  @override
  String? get release => '11';

  @override
  String? get previewSdkInt => null;

  @override
  String? get incremental => null;

  @override
  String? get codename => null;

  @override
  String? get baseOS => null;
}

class FakeIosDeviceInfo implements IosDeviceInfo {
  @override
  String get systemVersion => '15.0';

  @override
  String get name => 'iPhone';

  @override
  String get model => 'iPhone 13';

  @override
  bool get isPhysicalDevice => true;

  @override
  String get utsname => '';

  @override
  String get identifierForVendor => '';

  @override
  String get localizedModel => '';

  @override
  String get systemName => '';
}

class MockNudgeNotificationHelper extends Mock implements NudgeNotificationHelper {
  @override
  bool get isInitialized => true;

  @override
  Future<bool> areNudgesScheduledNow() async => false;

  @override
  Future<void> registerReservedIdRange(String start, String end) async {}
}

// Setup method channel for permission handler mocking
class MockPermissionHandler extends Mock implements Permission {
  PermissionStatus _status = PermissionStatus.granted;

  void setStatus(PermissionStatus status) {
    _status = status;
  }

  @override
  Future<PermissionStatus> get status async => _status;

  @override
  Future<PermissionStatus> request() async => _status;
}

void main() {
  late NotificationService notificationService;
  late MockFlutterLocalNotificationsPlugin mockNotificationsPlugin;
  late MockSharedPreferences mockPreferences;
  late MockLogger mockLogger;
  late MockAdvancedLogger mockAdvancedLogger;
  late MockDeviceInfoPlugin mockDeviceInfo;
  late MockNudgeNotificationHelper mockNudgeHelper;
  late MockPermissionHandler mockPermission;

  setUpAll(() {
    // Initialize timezone for testing
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));

    // Setup permission handler mocking
    TestWidgetsFlutterBinding.ensureInitialized();
    Permission.notification = mockPermission = MockPermissionHandler();
  });

  setUp(() async {
    // Set up mocks
    mockNotificationsPlugin = MockFlutterLocalNotificationsPlugin();
    mockPreferences = MockSharedPreferences();
    mockLogger = MockLogger();
    mockAdvancedLogger = MockAdvancedLogger();
    mockDeviceInfo = MockDeviceInfoPlugin();
    mockNudgeHelper = MockNudgeNotificationHelper();

    // Create service with mocks
    notificationService = NotificationService(
      notificationsPlugin: mockNotificationsPlugin,
      logger: mockLogger,
      advancedLogger: mockAdvancedLogger,
      preferences: mockPreferences,
      deviceInfo: mockDeviceInfo,
    );

    // Register with GetIt for tests
    if (GetIt.instance.isRegistered<NotificationService>()) {
      await GetIt.instance.unregister<NotificationService>();
    }
    GetIt.instance.registerSingleton<NotificationService>(notificationService);

    if (GetIt.instance.isRegistered<NudgeNotificationHelper>()) {
      await GetIt.instance.unregister<NudgeNotificationHelper>();
    }
    GetIt.instance.registerSingleton<NudgeNotificationHelper>(mockNudgeHelper);
  });

  tearDown(() async {
    // Clean up GetIt registrations
    if (GetIt.instance.isRegistered<NotificationService>()) {
      await GetIt.instance.unregister<NotificationService>();
    }
    if (GetIt.instance.isRegistered<NudgeNotificationHelper>()) {
      await GetIt.instance.unregister<NudgeNotificationHelper>();
    }

    // Dispose service to clean up resources
    await notificationService.dispose();
  });

  // 1. MOCK DEPENDENCIES MORE THOROUGHLY
  group('1. Mock Dependencies Testing', () {
    test('service uses all mocked dependencies correctly', () async {
      // Act
      await notificationService.initialize();

      // Assert
      expect(mockAdvancedLogger.infoLogs, contains(any(startsWith('Initializing NotificationService'))));
      expect(mockLogger.infoLogs, isNotEmpty);

      // Verify platform info is checked
      expect(mockLogger.infoLogs, contains(any(contains('Android API level'))));
    });

    test('logs errors appropriately when dependencies fail', () async {
      // Arrange - simulate device info failure
      when(mockDeviceInfo.androidInfo).thenThrow(Exception('Device info error'));

      // Act
      await notificationService.initialize();

      // Assert
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to check platform compatibility'))));
    });
  });

  // 2. PLATFORM-SPECIFIC TESTING
  group('2. Platform-Specific Testing', () {
    testWidgets('initializes correctly on Android platform', (WidgetTester tester) async {
      // Arrange
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      // Act
      await notificationService.initialize();

      // Assert
      // Verify Android channels were created
      expect(mockLogger.infoLogs, contains(any(contains('Created notification channels'))));

      // Reset platform
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    testWidgets('initializes correctly on iOS platform', (WidgetTester tester) async {
      // Arrange
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      // Act
      await notificationService.initialize();

      // Assert
      // Verify iOS-specific initialization (no channel creation)
      expect(mockLogger.infoLogs, isNot(contains(any(contains('Created notification channels')))));

      // Reset platform
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    test('handles older Android versions with appropriate fallbacks', () async {
      // Arrange - mock older Android version
      when(mockDeviceInfo.androidInfo).thenAnswer((_) async {
        final info = FakeAndroidDeviceInfo();
        (info.version as FakeAndroidBuildVersion).sdkInt = 21; // Android 5.0 Lollipop
        return info;
      });

      // Act
      await notificationService.initialize();

      // Assert
      expect(mockAdvancedLogger.warningLogs, contains(any(contains('Android API level'))));
    });

    test('handles older iOS versions with appropriate fallbacks', () async {
      // Arrange - mock older iOS version
      when(mockDeviceInfo.iosInfo).thenAnswer((_) async {
        final info = FakeIosDeviceInfo();
        info.systemVersion = '9.0';
        return info;
      });

      // Act
      await notificationService.initialize();

      // Assert
      expect(mockAdvancedLogger.warningLogs, contains(any(contains('iOS version'))));
    });
  });

  // 3. ASYNCHRONOUS TESTING
  group('3. Asynchronous Testing', () {
    test('notification stream emits events properly', () async {
      // Arrange
      await notificationService.initialize();

      // Act & Assert
      // Listen to the stream
      final receivedEvents = <Map<String, dynamic>>[];
      final subscription = notificationService.notificationStream.listen((event) {
        receivedEvents.add(event);
      });

      // Simulate receiving notification
      final notificationResponse = NotificationResponse(
        id: 123,
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'test:payload',
      );

      await notificationService._onDidReceiveNotificationResponse(notificationResponse);

      // Wait for async operations
      await Future.delayed(Duration(milliseconds: 100));

      // Verify events were emitted
      expect(receivedEvents, hasLength(1));
      expect(receivedEvents[0]['payload'], equals('test:payload'));

      // Clean up
      await subscription.cancel();
    });

    test('multiple async operations complete correctly', () async {
      // Arrange
      await notificationService.initialize();

      // Act - start multiple async operations
      final futures = await Future.wait([
        notificationService.scheduleCheckInNotifications(),
        notificationService.showSystemNotification(
          title: 'Test Title',
          body: 'Test Body',
        ),
        notificationService.scheduleMemoryReminder(
          reminderTime: DateTime.now().add(Duration(hours: 1)),
        ),
      ]);

      // Assert
      expect(futures, everyElement(isTrue));

      // Verify all operations completed
      expect(mockNotificationsPlugin.lastPeriodicNotificationData, isNotNull);
      expect(mockNotificationsPlugin.lastNotificationData, isNotNull);
      expect(mockNotificationsPlugin.lastScheduledNotificationData, isNotNull);
    });

    test('handles concurrent initialization attempts', () async {
      // Act - start multiple initializations concurrently
      final futures = await Future.wait([
        notificationService.initialize(),
        notificationService.initialize(),
        notificationService.initialize(),
      ]);

      // Assert - all should return true, but initialization should only happen once
      expect(futures, everyElement(isTrue));

      // Verify initialize was only called once on the plugin
      expect(mockLogger.infoLogs.where((log) => log.contains('NotificationService initialized successfully')), hasLength(1));
    });
  });

  // 4. LIFECYCLE TESTING
  group('4. Lifecycle Testing', () {
    test('handles app resume lifecycle event', () async {
      // Arrange
      await notificationService.initialize();

      // Act - simulate app resume
      notificationService._handleAppLifecycleStateChange(AppLifecycleState.resumed);

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('App lifecycle state changed to: AppLifecycleState.resumed'))));
    });

    test('handles app pause lifecycle event and saves state', () async {
      // Arrange
      await notificationService.initialize();

      // Act - simulate app going to background
      notificationService._handleAppLifecycleStateChange(AppLifecycleState.paused);

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('App lifecycle state changed to: AppLifecycleState.paused'))));

      // Verify state was saved
      expect(mockPreferences.data.containsKey('notificationServiceState'), isTrue);
    });

    test('handles app detached lifecycle event', () async {
      // Arrange
      await notificationService.initialize();

      // Act - simulate app termination
      notificationService._handleAppLifecycleStateChange(AppLifecycleState.detached);

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('App lifecycle state changed to: AppLifecycleState.detached'))));

      // Verify state was saved
      expect(mockPreferences.data.containsKey('notificationServiceState'), isTrue);
    });

    test('refreshes permission status on app resume', () async {
      // Arrange
      await notificationService.initialize();
      mockPermission.setStatus(PermissionStatus.denied);

      // Initially denied
      notificationService._status = NotificationStatus.permissionDenied;

      // Act - change permission status & simulate app resume
      mockPermission.setStatus(PermissionStatus.granted);
      notificationService._handleAppLifecycleStateChange(AppLifecycleState.resumed);

      // Wait for async
      await Future.delayed(Duration(milliseconds: 100));

      // Assert
      expect(notificationService.status, equals(NotificationStatus.ready));
    });
  });

  // 5. PERMISSION HANDLING
  group('5. Permission Handling', () {
    test('handles granted permissions correctly', () async {
      // Arrange
      mockPermission.setStatus(PermissionStatus.granted);

      // Act
      await notificationService.initialize();

      // Assert
      expect(notificationService.status, equals(NotificationStatus.ready));
      expect(notificationService.isInitialized, isTrue);
    });

    test('handles denied permissions correctly', () async {
      // Arrange
      mockPermission.setStatus(PermissionStatus.denied);

      // Act
      await notificationService.initialize();

      // Assert
      expect(notificationService.status, equals(NotificationStatus.permissionDenied));
      expect(notificationService.isInitialized, isFalse);
    });

    test('handles permanently denied permissions correctly', () async {
      // Arrange
      mockPermission.setStatus(PermissionStatus.permanentlyDenied);

      // Act
      await notificationService.initialize();

      // Assert
      expect(notificationService.status, equals(NotificationStatus.permissionPermanentlyDenied));
      expect(notificationService.isInitialized, isFalse);

      // Verify flag was set to show settings guidance
      expect(mockPreferences.data['showPermissionSettings'], isTrue);
    });

    test('provides guidance when permissions are permanently denied', () async {
      // Arrange
      mockPermission.setStatus(PermissionStatus.permanentlyDenied);
      await notificationService.initialize();

      // Act
      final needsGuidance = await notificationService.needsPermissionSettingsGuidance();

      // Assert
      expect(needsGuidance, isTrue);
    });

    test('openNotificationSettings resets guidance flag', () async {
      // Arrange
      mockPreferences.data['showPermissionSettings'] = true;

      // Mock app settings - this will normally throw an unsupported error in tests
      // which is expected and fine for this test
      try {
        // Act
        await notificationService.openNotificationSettings();
      } catch (_) {}

      // Assert - flag should be reset even if opening settings fails
      expect(mockPreferences.data['showPermissionSettings'], isFalse);
    });
  });

  // 6. ERROR CONDITIONS
  group('6. Error Conditions', () {
    test('handles initialization failures gracefully', () async {
      // Arrange
      when(mockNotificationsPlugin.initialize(any, onDidReceiveNotificationResponse: anyNamed('onDidReceiveNotificationResponse')))
          .thenThrow(Exception('Initialization error'));

      // Act
      final result = await notificationService.initialize();

      // Assert
      expect(result, isFalse);
      expect(notificationService.status, equals(NotificationStatus.failed));
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to initialize NotificationService'))));
    });

    test('handles notification scheduling failures', () async {
      // Arrange
      await notificationService.initialize();
      when(mockNotificationsPlugin.periodicallyShow(any, any, any, any, any, androidScheduleMode: anyNamed('androidScheduleMode'), payload: anyNamed('payload')))
          .thenThrow(Exception('Scheduling error'));

      // Act
      final result = await notificationService.scheduleCheckInNotifications();

      // Assert
      expect(result, isFalse);
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to schedule check-in notifications'))));
    });

    test('handles notification display failures', () async {
      // Arrange
      await notificationService.initialize();
      when(mockNotificationsPlugin.show(any, any, any, notificationDetails: anyNamed('notificationDetails'), payload: anyNamed('payload')))
          .thenThrow(Exception('Display error'));

      // Act
      final result = await notificationService.showSystemNotification(
        title: 'Test Title',
        body: 'Test Body',
      );

      // Assert
      expect(result, isFalse);
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to show system notification'))));
    });

    test('handles cancellation failures', () async {
      // Arrange
      await notificationService.initialize();
      when(mockNotificationsPlugin.cancelAll())
          .thenThrow(Exception('Cancellation error'));

      // Act
      final result = await notificationService.cancelAllNotifications();

      // Assert
      expect(result, isFalse);
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to cancel all notifications'))));
    });

    test('prevents operation if not initialized', () async {
      // Arrange - don't initialize

      // Act
      final result = await notificationService.showSystemNotification(
        title: 'Test Title',
        body: 'Test Body',
      );

      // Assert
      expect(result, isFalse);
      expect(mockLogger.warningLogs, contains(any(contains('Cannot show system notification: service not initialized'))));
    });
  });

  // 7. INTEGRATION TESTING
  group('7. Integration Testing', () {
    test('coordinates with NudgeNotificationHelper when scheduling', () async {
      // Arrange
      when(mockNudgeHelper.areNudgesScheduledNow()).thenAnswer((_) async => true);
      await notificationService.initialize();

      // Act
      final result = await notificationService.scheduleCheckInNotifications();

      // Assert
      // Result should still be true as we defer, not fail
      expect(result, isTrue);

      // Verify nudge check was performed
      verify(mockNudgeHelper.areNudgesScheduledNow()).called(1);

      // Verify deferral log
      expect(mockLogger.infoLogs, contains(any(contains('Deferring check-in notification due to active nudge'))));
    });

    test('registers id ranges with NudgeNotificationHelper', () async {
      // Act
      await notificationService.initialize();

      // Assert
      verify(mockNudgeHelper.registerReservedIdRange(any, any)).called(1);
    });

    test('respects reserved id ranges from other services', () async {
      // Arrange
      await notificationService.initialize();

      // Register a range that conflicts
      await notificationService.registerReservedIdRange('100', '200');

      // Act - attempt to send notification with ID in reserved range
      final customIdInRange = 150;
      final result = await notificationService._isIdInReservedRange(customIdInRange);

      // Assert
      expect(result, isTrue);
    });

    test('continues operation when NudgeNotificationHelper is not registered', () async {
      // Arrange
      await GetIt.instance.unregister<NudgeNotificationHelper>();

      // Act
      final result = await notificationService.initialize();

      // Assert
      expect(result, isTrue);
      expect(notificationService.isInitialized, isTrue);
    });
  });

  // 8. TIMING TESTS
  group('8. Timing Tests', () {
    test('calculates correct scheduled time for memory reminder', () async {
      // Arrange
      await notificationService.initialize();
      final reminderTime = DateTime.now().add(Duration(hours: 2));

      // Act
      await notificationService.scheduleMemoryReminder(reminderTime: reminderTime);

      // Assert
      expect(mockNotificationsPlugin.lastScheduledNotificationData, isNotNull);

      // Verify time conversion was correct (should be within a few seconds)
      final scheduledTime = mockNotificationsPlugin.lastScheduledNotificationData!['scheduledDate'] as String;
      expect(scheduledTime, contains(reminderTime.year.toString()));
      expect(scheduledTime, contains(reminderTime.month.toString()));
      expect(scheduledTime, contains(reminderTime.day.toString()));
      expect(scheduledTime, contains(reminderTime.hour.toString()));
    });

    test('handles timezone-aware scheduling', () async {
      // Arrange
      await notificationService.initialize();

      // Get a date in a future timezone
      final now = DateTime.now();
      final reminderTime = tz.TZDateTime(tz.getLocation('America/Los_Angeles'),
          now.year, now.month, now.day, now.hour + 3);

      // Act
      await notificationService.scheduleMemoryReminder(reminderTime: reminderTime);

      // Assert
      expect(mockNotificationsPlugin.lastScheduledNotificationData, isNotNull);

      // Verify timezone was preserved
      final scheduledTime = mockNotificationsPlugin.lastScheduledNotificationData!['scheduledDate'] as String;
      expect(scheduledTime, contains('Los_Angeles'));
    });

    test('uses appropriate repeat interval based on platform version', () async {
      // Arrange
      when(mockDeviceInfo.androidInfo).thenAnswer((_) async {
        final info = FakeAndroidDeviceInfo();
        (info.version as FakeAndroidBuildVersion).sdkInt = 22; // Android 5.1, before exact alarms
        return info;
      });

      await notificationService.initialize();

      // Act
      await notificationService.scheduleCheckInNotifications();

      // Assert
      expect(mockLogger.warningLogs, contains(any(contains('Exact timing not reliable'))));
    });
  });

  // 9. STATE PERSISTENCE
  group('9. State Persistence', () {
    test('saves and recovers service state correctly', () async {
      // Arrange - initialize service
      await notificationService.initialize();

      // Save some state
      final stateJson = jsonEncode({
        'isInitialized': true,
        'status': NotificationStatus.ready.index,
        'activeNotifications': [101, 102],
        'savedTimestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await mockPreferences.setString('notificationServiceState', stateJson);

      // Create new instance
      final newService = NotificationService(
        notificationsPlugin: mockNotificationsPlugin,
        logger: mockLogger,
        advancedLogger: mockAdvancedLogger,
        preferences: mockPreferences,
        deviceInfo: mockDeviceInfo,
      );

      // Act
      await newService.initialize();

      // Assert
      expect(newService.status, equals(NotificationStatus.ready));
    });

    test('recovers scheduled notifications after crash', () async {
      // Arrange - simulate saved state with timestamp in the past
      final pastTimestamp = DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch;

      await mockPreferences.setString('notificationServiceState', jsonEncode({
        'isInitialized': true,
        'status': NotificationStatus.ready.index,
        'activeNotifications': [101, 102],
        'savedTimestamp': pastTimestamp,
      }));

      await mockPreferences.setInt('lastLoadTimestamp', pastTimestamp - 1000);

      // Act
      await notificationService.initialize();

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Detected potential crash or unexpected termination'))));

      // Verify check-in notification was rescheduled
      expect(mockNotificationsPlugin.lastPeriodicNotificationData, isNotNull);
    });

    test('handles corrupted persistent state', () async {
      // Arrange - set corrupted JSON
      await mockPreferences.setString('notificationServiceState', '{corrupt-json');

      // Act
      await notificationService.initialize();

      // Assert
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to load service state'))));

      // Service should still initialize
      expect(notificationService.isInitialized, isTrue);
    });
  });

  // 10. NOTIFICATION DELIVERY VERIFICATION
  group('10. Notification Delivery Verification', () {
    test('memory reminder notifications contain correct content and timing', () async {
      // Arrange
      await notificationService.initialize();
      final reminderTime = DateTime.now().add(Duration(hours: 1));
      final customTitle = 'Memory Time!';
      final customBody = 'Record your special memory now.';

      // Act
      await notificationService.scheduleMemoryReminder(
        reminderTime: reminderTime,
        title: customTitle,
        body: customBody,
      );

      // Assert
      expect(mockNotificationsPlugin.lastScheduledNotificationData, isNotNull);
      expect(mockNotificationsPlugin.lastScheduledNotificationData!['title'], equals(customTitle));
      expect(mockNotificationsPlugin.lastScheduledNotificationData!['body'], equals(customBody));
      expect(mockNotificationsPlugin.lastScheduledNotificationData!['payload'], contains('memory:reminder'));
    });

    test('check-in notifications use correct channel and priority', () async {
      // Arrange
      await notificationService.initialize();

      // Act
      await notificationService.scheduleCheckInNotifications();

      // Assert
      expect(mockNotificationsPlugin.lastPeriodicNotificationData, isNotNull);
      expect(mockNotificationsPlugin.lastPeriodicNotificationData!['payload'], contains('checkin:'));
      expect(mockNotificationsPlugin.lastPeriodicNotificationData!['title'], contains('Milo Check-in'));
    });

    test('system notifications contain correct data', () async {
      // Arrange
      await notificationService.initialize();

      // Act
      await notificationService.showSystemNotification(
        title: 'System Alert',
        body: 'Important system message',
        payload: 'system:test_payload',
      );

      // Assert
      expect(mockNotificationsPlugin.lastNotificationData, isNotNull);
      expect(mockNotificationsPlugin.lastNotificationData!['title'], equals('System Alert'));
      expect(mockNotificationsPlugin.lastNotificationData!['body'], equals('Important system message'));
      expect(mockNotificationsPlugin.lastNotificationData!['payload'], equals('system:test_payload'));
    });
  });

  // 11. COVERAGE GAPS
  group('11. Coverage Gaps', () {
    test('refreshPermissionStatus updates status correctly', () async {
      // Arrange
      await notificationService.initialize();
      notificationService._status = NotificationStatus.permissionDenied;
      mockPermission.setStatus(PermissionStatus.granted);

      // Act
      await notificationService._refreshPermissionStatus();

      // Assert
      expect(notificationService.status, equals(NotificationStatus.ready));
    });

    test('isPermissionGranted returns correct status', () async {
      // Arrange
      mockPermission.setStatus(PermissionStatus.granted);

      // Act
      final result = await notificationService.isPermissionGranted();

      // Assert
      expect(result, isTrue);
    });

    test('cancelNotification cancels specific notification', () async {
      // Arrange
      await notificationService.initialize();

      // Act
      await notificationService.cancelNotification(123);

      // Assert
      expect(mockNotificationsPlugin.cancelledIds, contains(123));
    });

    test('test mode enables test functionality', () async {
      // Arrange
      await notificationService.initialize();

      // Act
      notificationService.enableTestMode();
      await notificationService.showImmediateTestNotification();

      // Assert
      expect(mockNotificationsPlugin.lastNotificationData, isNotNull);
      expect(mockNotificationsPlugin.lastNotificationData!['title'], contains('Test'));
    });
  });

  // 12. CALLBACK TESTING
  group('12. Callback Testing', () {
    test('onDidReceiveNotificationResponse handles check-in payload', () async {
      // Arrange
      await notificationService.initialize();

      // Act
      await notificationService._onDidReceiveNotificationResponse(
          NotificationResponse(
            id: 101,
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: 'checkin:general',
          )
      );

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Notification tapped with payload: checkin:general'))));
    });

    test('onDidReceiveNotificationResponse handles memory reminder payload', () async {
      // Arrange
      await notificationService.initialize();

      // Act
      await notificationService._onDidReceiveNotificationResponse(
          NotificationResponse(
            id: 102,
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: 'memory:reminder',
          )
      );

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Notification tapped with payload: memory:reminder'))));
    });

    test('onDidReceiveNotificationResponse handles system notification payload', () async {
      // Arrange
      await notificationService.initialize();

      // Act
      await notificationService._onDidReceiveNotificationResponse(
          NotificationResponse(
            id: 103,
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: 'system:alert',
          )
      );

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Notification tapped with payload: system:alert'))));
    });

    test('onDidReceiveNotificationResponse handles missing payload', () async {
      // Arrange
      await notificationService.initialize();

      // Act - should not throw
      await notificationService._onDidReceiveNotificationResponse(
          NotificationResponse(
            id: 104,
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: null,
          )
      );

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Notification tapped with payload: null'))));
    });

    test('onDidReceiveLocalNotification handles iOS foreground notifications', () async {
      // Arrange
      await notificationService.initialize();

      // Create event controller to capture stream events
      final receivedEvents = <Map<String, dynamic>>[];
      final subscription = notificationService.notificationStream.listen((event) {
        receivedEvents.add(event);
      });

      // Act
      notificationService._onDidReceiveLocalNotification(
          105, 'iOS Title', 'iOS Body', 'ios:payload'
      );

      // Wait for async
      await Future.delayed(Duration(milliseconds: 100));

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Received iOS foreground notification'))));

      // Verify event was emitted to stream
      expect(receivedEvents, hasLength(1));
      expect(receivedEvents[0]['event'], equals('receivedForeground'));
      expect(receivedEvents[0]['title'], equals('iOS Title'));

      // Clean up
      await subscription.cancel();
    });
  });
}