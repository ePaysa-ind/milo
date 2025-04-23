// test/services/nudge_notification_helper_test.dart

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
import 'package:battery_plus/battery_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:logging/logging.dart';
import 'package:workmanager/workmanager.dart';
import 'package:milo/services/notification_service.dart';
import 'package:milo/services/nudge_notification_helper.dart';
import 'package:milo/services/nudge_service.dart';
import 'package:milo/models/nudge_model.dart';
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

  // Store notification data for verification
  Map<String, dynamic>? lastNotificationData;
  Map<String, dynamic>? lastScheduledNotificationData;

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

class MockAudioPlayer extends Mock implements AudioPlayer {
  bool _isPlaying = false;
  String? _currentUrl;
  StreamController<PlayerState> _playerStateController = StreamController<PlayerState>.broadcast();
  StreamController<ProcessingState> _processingStateController = StreamController<ProcessingState>.broadcast();

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<ProcessingState> get processingStateStream => _processingStateController.stream;

  @override
  Future<Duration?> setUrl(String url, {Map<String, String>? headers}) async {
    _currentUrl = url;
    return Duration(milliseconds: 500);
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _playerStateController.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    _isPlaying = false;
    _playerStateController.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> dispose() async {
    await _playerStateController.close();
    await _processingStateController.close();
  }

  // Helper methods for testing
  void completePlayback() {
    _isPlaying = false;
    _processingStateController.add(ProcessingState.completed);
    _playerStateController.add(PlayerState(false, ProcessingState.completed));
  }

  bool get isPlaying => _isPlaying;
  String? get currentUrl => _currentUrl;
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

class MockBattery extends Mock implements Battery {
  int _batteryLevel = 80;
  BatteryState _batteryState = BatteryState.discharging;
  final StreamController<BatteryState> _batteryStateController = StreamController<BatteryState>.broadcast();

  @override
  Future<int> get batteryLevel async => _batteryLevel;

  @override
  Future<BatteryState> get batteryState async => _batteryState;

  @override
  Stream<BatteryState> get onBatteryStateChanged => _batteryStateController.stream;

  // Helper methods for testing
  void setBatteryLevel(int level) {
    _batteryLevel = level;
  }

  void setBatteryState(BatteryState state) {
    _batteryState = state;
    _batteryStateController.add(state);
  }

  void dispose() {
    _batteryStateController.close();
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
  int _sdkInt = 30; // Android 11 by default

  FakeAndroidDeviceInfo() : super(FakeAndroidBuildVersion());

  // For testing different API levels
  void setSdkInt(int sdkInt) {
    _sdkInt = sdkInt;
  }

  int get sdkInt => _sdkInt;
}

class FakeAndroidBuildVersion implements AndroidBuildVersion {
  int _sdkInt = 30; // Android 11 by default

  @override
  int? get sdkInt => _sdkInt;

  // For testing different API levels
  set sdkInt(int value) {
    _sdkInt = value;
  }

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
  String _systemVersion = '15.0';

  // For testing different iOS versions
  void setSystemVersion(String version) {
    _systemVersion = version;
  }

  @override
  String get systemVersion => _systemVersion;

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

class MockNudgeService extends Mock implements NudgeService {
  @override
  Future<NudgeSettings?> getUserSettings() async {
    return NudgeSettings(
      userId: 'test_user',
      nudgesEnabled: true,
      enabledTimeWindows: {
        TimeWindow.morning: true,
        TimeWindow.midday: true,
        TimeWindow.evening: true,
      },
      enabledCategories: {
        NudgeCategory.gratitude: true,
        NudgeCategory.mindfulness: true,
        NudgeCategory.selfReflection: true,
        NudgeCategory.reassurance: true,
        NudgeCategory.cognitiveTip: true,
      },
      allowDeviceUnlockTrigger: true,
      allowTimeBasedTrigger: true,
      maxNudgesPerDay: 3,
      preferredVoice: 'nova',
      notificationSettings: NotificationSettings(
        showPreview: true,
        sound: true,
        vibration: true,
      ),
      privacySettings: PrivacySettings(
        storeAudioRecordings: true,
        allowAnalyticsCollection: true,
        shareAnonymizedData: false,
        storeSensitiveInfo: false,
      ),
      personalizationPreferences: PersonalizationPreferences(
        enablePersonalization: true,
        adaptationLevel: 3,
        trackMoodForPersonalization: true,
      ),
      updatedAt: DateTime.now(),
      settingsVersion: 1,
    );
  }

  @override
  Future<NudgeTemplate?> getNudgeTemplateById(String id) async {
    if (id == 'test_id' || id.startsWith('test_')) {
      return NudgeTemplate(
        id: id,
        content: 'This is a test nudge content',
        category: NudgeCategory.gratitude,
        metadata: NudgeMetadata(
          author: 'Test Author',
          emotionalTone: EmotionalTone.uplifting,
        ),
        audioUrl: 'https://example.com/audio/test.mp3',
        isActive: true,
        version: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
    return null;
  }

  @override
  Future<NudgeTemplate?> getRandomNudgeForTimeWindow(
      TimeWindow timeWindow, {
        List<NudgeCategory>? categories,
      }) async {
    return NudgeTemplate(
      id: 'random_${timeWindow.toString().split('.').last}',
      content: 'Random nudge for ${timeWindow.toString().split('.').last}',
      category: categories?.first ?? NudgeCategory.gratitude,
      metadata: NudgeMetadata(
        author: 'Test Author',
        emotionalTone: EmotionalTone.uplifting,
      ),
      audioUrl: 'https://example.com/audio/random.mp3',
      isActive: true,
      version: 1,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

class MockNotificationService extends Mock implements NotificationService {
  @override
  bool get isInitialized => true;

  @override
  Future<void> registerReservedIdRange(String start, String end) async {}
}

class MockWorkmanager extends Mock implements Workmanager {
  Map<String, dynamic> lastRegisteredTask = {};

  @override
  Future<void> initialize(Function(String, Map<String, dynamic>?)? callbackDispatcher, {bool isInDebugMode = false}) async {}

  @override
  Future<void> registerPeriodicTask(
      String uniqueName,
      String taskName, {
        Duration? frequency,
        Duration? initialDelay,
        Constraints? constraints,
        BackoffPolicy? backoffPolicy,
        BackoffPolicyDelay? backoffDelay,
        OutOfQuotaPolicy? outOfQuotaPolicy,
        ExistingWorkPolicy? existingWorkPolicy,
      }) async {
    lastRegisteredTask = {
      'uniqueName': uniqueName,
      'taskName': taskName,
      'frequency': frequency?.inMinutes,
      'initialDelay': initialDelay?.inMinutes,
    };
  }
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
  late NudgeNotificationHelper nudgeHelper;
  late MockFlutterLocalNotificationsPlugin mockNotificationsPlugin;
  late MockSharedPreferences mockPreferences;
  late MockLogger mockLogger;
  late MockAdvancedLogger mockAdvancedLogger;
  late MockAudioPlayer mockAudioPlayer;
  late MockBattery mockBattery;
  late MockDeviceInfoPlugin mockDeviceInfo;
  late MockNudgeService mockNudgeService;
  late MockWorkmanager mockWorkmanager;
  late MockNotificationService mockNotificationService;
  late MockPermissionHandler mockPermission;
  late FakeAndroidDeviceInfo fakeAndroidInfo;
  late FakeIosDeviceInfo fakeIosInfo;

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
    mockAudioPlayer = MockAudioPlayer();
    mockBattery = MockBattery();
    mockDeviceInfo = MockDeviceInfoPlugin();
    mockNudgeService = MockNudgeService();
    mockWorkmanager = MockWorkmanager();
    mockNotificationService = MockNotificationService();

    // Create helper with mocks
    nudgeHelper = NudgeNotificationHelper(
      notificationsPlugin: mockNotificationsPlugin,
      logger: mockLogger,
      advancedLogger: mockAdvancedLogger,
      audioPlayer: mockAudioPlayer,
      sharedPreferences: mockPreferences,
      nudgeService: mockNudgeService,
      battery: mockBattery,
      deviceInfo: mockDeviceInfo,
    );

    // Create fake device info classes for platform-specific tests
    fakeAndroidInfo = FakeAndroidDeviceInfo();
    fakeIosInfo = FakeIosDeviceInfo();

    // Register with GetIt for tests
    if (GetIt.instance.isRegistered<NudgeNotificationHelper>()) {
      await GetIt.instance.unregister<NudgeNotificationHelper>();
    }
    GetIt.instance.registerSingleton<NudgeNotificationHelper>(nudgeHelper);

    if (GetIt.instance.isRegistered<NudgeService>()) {
      await GetIt.instance.unregister<NudgeService>();
    }
    GetIt.instance.registerSingleton<NudgeService>(mockNudgeService);

    if (GetIt.instance.isRegistered<NotificationService>()) {
      await GetIt.instance.unregister<NotificationService>();
    }
    GetIt.instance.registerSingleton<NotificationService>(mockNotificationService);

    // Replace the real Workmanager with our mock
    GetIt.instance.registerSingleton<Workmanager>(mockWorkmanager, override: true);
  });

  tearDown(() async {
    // Clean up GetIt registrations
    if (GetIt.instance.isRegistered<NudgeNotificationHelper>()) {
      await GetIt.instance.unregister<NudgeNotificationHelper>();
    }
    if (GetIt.instance.isRegistered<NudgeService>()) {
      await GetIt.instance.unregister<NudgeService>();
    }
    if (GetIt.instance.isRegistered<NotificationService>()) {
      await GetIt.instance.unregister<NotificationService>();
    }
    if (GetIt.instance.isRegistered<Workmanager>()) {
      await GetIt.instance.unregister<Workmanager>();
    }

    // Dispose service to clean up resources
    await nudgeHelper.dispose();
    mockBattery.dispose();
  });

  // 1. MOCK DEPENDENCIES MORE THOROUGHLY
  group('1. Mock Dependencies Testing', () {
    test('helper uses all mocked dependencies correctly', () async {
      // Act
      await nudgeHelper.initialize();

      // Assert
      expect(mockAdvancedLogger.infoLogs, contains(any(startsWith('Initializing NudgeNotificationHelper'))));
      expect(mockLogger.infoLogs, isNotEmpty);

      // Verify battery monitoring was initialized
      expect(mockLogger.infoLogs, contains(any(contains('Registered battery monitoring'))));

      // Verify audio player is used
      await nudgeHelper._playAudioFile('https://example.com/test.mp3');
      expect(mockAudioPlayer.currentUrl, equals('https://example.com/test.mp3'));
    });

    test('logs errors appropriately when dependencies fail', () async {
      // Arrange - simulate battery access failure
      when(mockBattery.batteryLevel).thenThrow(Exception('Battery access error'));

      // Act
      await nudgeHelper.initialize();

      // Assert
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to register battery monitoring'))));

      // Service should still initialize despite battery failure
      expect(nudgeHelper.isInitialized, isTrue);
    });

    test('handles audio player failures gracefully', () async {
      // Arrange
      await nudgeHelper.initialize();
      when(mockAudioPlayer.setUrl(any)).thenThrow(Exception('Audio error'));

      // Act - try to play audio
      await nudgeHelper._playAudioFile('https://example.com/error.mp3');

      // Assert
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to play audio file'))));
    });
  });

  // 2. PLATFORM-SPECIFIC TESTING
  group('2. Platform-Specific Testing', () {
    testWidgets('initializes correctly on Android platform', (WidgetTester tester) async {
      // Arrange
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      // Act
      await nudgeHelper.initialize();

      // Assert
      // Verify Android channels were created
      expect(mockLogger.infoLogs, contains(any(contains('Created notification channel'))));

      // Reset platform
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    testWidgets('initializes correctly on iOS platform', (WidgetTester tester) async {
      // Arrange
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      // Act
      await nudgeHelper.initialize();

      // Assert
      // Verify iOS categories were created
      expect(mockLogger.infoLogs, contains(any(contains('Created iOS notification categories'))));

      // Reset platform
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    test('handles older Android versions with appropriate fallbacks', () async {
      // Arrange - mock older Android version
      when(mockDeviceInfo.androidInfo).thenAnswer((_) async {
        fakeAndroidInfo.setSdkInt(21); // Android 5.0 Lollipop
        return fakeAndroidInfo;
      });

      // Act
      await nudgeHelper.initialize();

      // Assert
      expect(mockAdvancedLogger.warningLogs, contains(any(contains('Android API level'))));

      // Verify it skips notification channel creation for older Android
      expect(mockLogger.infoLogs, contains(any(contains('Skipping notification channel creation'))));
    });

    test('handles older iOS versions with appropriate fallbacks', () async {
      // Arrange - mock older iOS version
      when(mockDeviceInfo.iosInfo).thenAnswer((_) async {
        fakeIosInfo.setSystemVersion('9.0');
        return fakeIosInfo;
      });

      // Act
      await nudgeHelper.initialize();

      // Assert
      expect(mockAdvancedLogger.warningLogs, contains(any(contains('iOS version'))));
    });

    test('adapts notifications for Android API level', () async {
      // Arrange - mock Android API level 21
      when(mockDeviceInfo.androidInfo).thenAnswer((_) async {
        fakeAndroidInfo.setSdkInt(21);
        return fakeAndroidInfo;
      });

      await nudgeHelper.initialize();

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      await nudgeHelper.showDeviceUnlockNudge(template!);

      // Assert - checks if notification was created without newer API features
      expect(mockNotificationsPlugin.lastNotificationData, isNotNull);

      // Should have logged about the API level
      expect(mockLogger.infoLogs, contains(any(contains('Android API level 21'))));
    });
  });

  // 3. ASYNCHRONOUS TESTING
  group('3. Asynchronous Testing', () {
    test('notification stream emits events properly', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act & Assert
      // Listen to the stream
      final receivedEvents = <Map<String, dynamic>>[];
      final subscription = nudgeHelper.notificationStream.listen((event) {
        receivedEvents.add(event);
      });

      // Simulate receiving notification
      final notificationResponse = NotificationResponse(
        id: 1001,
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'test_id:view',
      );

      await nudgeHelper._onDidReceiveNotificationResponse(notificationResponse);

      // Wait for async operations
      await Future.delayed(Duration(milliseconds: 100));

      // Verify events were emitted
      expect(receivedEvents, hasLength(1));
      expect(receivedEvents[0]['payload'], equals('test_id:view'));

      // Clean up
      await subscription.cancel();
    });

    test('audio playback manages resources asynchronously', () async {
      // Arrange
      await nudgeHelper.initialize();
      final audioUrl = 'https://example.com/test.mp3';

      // Act
      await nudgeHelper._playAudioFile(audioUrl);

      // Verify audio player is playing
      expect(mockAudioPlayer.isPlaying, isTrue);

      // Simulate playback completion
      mockAudioPlayer.completePlayback();

      // Wait for state propagation
      await Future.delayed(Duration(milliseconds: 100));

      // Assert
      expect(mockAudioPlayer.isPlaying, isFalse);
    });

    test('multiple async operations complete correctly', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act - start multiple async operations
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);

      final futures = await Future.wait([
        nudgeHelper.scheduleNudgeForTimeWindow(template!, TimeWindow.morning),
        nudgeHelper.showDeviceUnlockNudge(template),
        nudgeHelper._preloadAudioFile('https://example.com/test.mp3'),
      ]);

      // Assert
      expect(futures.whereType<bool>(), everyElement(isTrue));

      // Verify operations completed
      expect(mockNotificationsPlugin.lastScheduledNotificationData, isNotNull);
      expect(mockNotificationsPlugin.lastNotificationData, isNotNull);
      expect(mockAudioPlayer.currentUrl, equals('https://example.com/test.mp3'));
    });

    test('handles concurrent initialization attempts', () async {
      // Act - start multiple initializations concurrently
      final futures = await Future.wait([
        nudgeHelper.initialize(),
        nudgeHelper.initialize(),
        nudgeHelper.initialize(),
      ]);

      // Assert - all should return true, but initialization should only happen once
      expect(futures, everyElement(isTrue));

      // Verify initialize was only called once
      expect(mockLogger.infoLogs.where(
              (log) => log.contains('NudgeNotificationHelper initialized successfully')
      ), hasLength(1));
    });
  });

  // 4. LIFECYCLE TESTING
  group('4. Lifecycle Testing', () {
    test('handles app resume lifecycle event', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act - simulate app resume
      nudgeHelper._handleAppLifecycleStateChange(AppLifecycleState.resumed);

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('App lifecycle state changed to: AppLifecycleState.resumed'))));
    });

    test('handles app pause lifecycle event and saves state', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act - simulate app going to background
      nudgeHelper._handleAppLifecycleStateChange(AppLifecycleState.paused);

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('App lifecycle state changed to: AppLifecycleState.paused'))));

      // Verify state was saved
      expect(mockPreferences.data.containsKey('nudgeServiceState'), isTrue);
    });

    test('handles app detached lifecycle event', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act - simulate app termination
      nudgeHelper._handleAppLifecycleStateChange(AppLifecycleState.detached);

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('App lifecycle state changed to: AppLifecycleState.detached'))));

      // Verify state was saved
      expect(mockPreferences.data.containsKey('nudgeServiceState'), isTrue);
    });

    test('refreshes permission status on app resume', () async {
      // Arrange
      await nudgeHelper.initialize();
      mockPermission.setStatus(PermissionStatus.denied);

      // Initially denied
      nudgeHelper._status = NudgeNotificationStatus.permissionDenied;

      // Act - change permission status & simulate app resume
      mockPermission.setStatus(PermissionStatus.granted);
      nudgeHelper._handleAppLifecycleStateChange(AppLifecycleState.resumed);

      // Wait for async operations
      await Future.delayed(Duration(milliseconds: 100));

      // Assert
      expect(nudgeHelper.status, equals(NudgeNotificationStatus.ready));
    });

    test('refreshes battery status on app resume', () async {
      // Arrange
      await nudgeHelper.initialize();
      mockBattery.setBatteryLevel(15); // Low battery

      // Act - simulate app resume
      nudgeHelper._handleAppLifecycleStateChange(AppLifecycleState.resumed);

      // Wait for async operations
      await Future.delayed(Duration(milliseconds: 100));

      // Assert - should have updated battery state
      expect(mockLogger.infoLogs, contains(any(contains('Refreshed battery status'))));
    });
  });

  // 5. PERMISSION HANDLING
  group('5. Permission Handling', () {
    test('handles granted permissions correctly', () async {
      // Arrange
      mockPermission.setStatus(PermissionStatus.granted);

      // Act
      await nudgeHelper.initialize();

      // Assert
      expect(nudgeHelper.status, equals(NudgeNotificationStatus.ready));
      expect(nudgeHelper.isInitialized, isTrue);
    });

    test('handles denied permissions correctly', () async {
      // Arrange
      mockPermission.setStatus(PermissionStatus.denied);

      // Act
      await nudgeHelper.initialize();

      // Assert
      expect(nudgeHelper.status, equals(NudgeNotificationStatus.permissionDenied));
      expect(nudgeHelper.isInitialized, isFalse);

      // Verify flag was set to show explanation
      expect(mockPreferences.data['showPermissionExplanation'], isTrue);
    });

    test('handles permanently denied permissions correctly', () async {
      // Arrange
      mockPermission.setStatus(PermissionStatus.permanentlyDenied);

      // Act
      await nudgeHelper.initialize();

      // Assert
      expect(nudgeHelper.status, equals(NudgeNotificationStatus.permissionPermanentlyDenied));
      expect(nudgeHelper.isInitialized, isFalse);

      // Verify flag was set to show settings guidance
      expect(mockPreferences.data['showPermissionSettings'], isTrue);
    });

    test('provides guidance when permissions are permanently denied', () async {
      // Arrange
      mockPermission.setStatus(PermissionStatus.permanentlyDenied);
      await nudgeHelper.initialize();

      // Act
      final needsGuidance = await nudgeHelper.needsPermissionSettingsGuidance();

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
        await nudgeHelper.openNotificationSettings();
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
      final result = await nudgeHelper.initialize();

      // Assert
      expect(result, isFalse);
      expect(nudgeHelper.status, equals(NudgeNotificationStatus.failed));
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to initialize NudgeNotificationHelper'))));
    });

    test('handles notification scheduling failures', () async {
      // Arrange
      await nudgeHelper.initialize();
      when(mockNotificationsPlugin.zonedSchedule(any, any, any, any, any,
          androidScheduleMode: anyNamed('androidScheduleMode'),
          uiLocalNotificationDateInterpretation: anyNamed('uiLocalNotificationDateInterpretation'),
          payload: anyNamed('payload'),
          matchDateTimeComponents: anyNamed('matchDateTimeComponents')))
          .thenThrow(Exception('Scheduling error'));

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      final result = await nudgeHelper.scheduleNudgeForTimeWindow(template!, TimeWindow.morning);

      // Assert
      expect(result, isFalse);
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to schedule nudge notification'))));
    });

    test('handles notification display failures', () async {
      // Arrange
      await nudgeHelper.initialize();
      when(mockNotificationsPlugin.show(any, any, any, notificationDetails: anyNamed('notificationDetails'), payload: anyNamed('payload')))
          .thenThrow(Exception('Display error'));

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      final result = await nudgeHelper.showDeviceUnlockNudge(template!);

      // Assert
      expect(result, isFalse);
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to show device unlock nudge'))));
    });

    test('handles audio resource unavailability', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Make _isAudioResourceAvailable return false
      when(mockAudioPlayer.setUrl(any)).thenThrow(TimeoutException('Audio resource timeout'));

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      final result = await nudgeHelper.showDeviceUnlockNudge(template!);

      // Assert
      expect(result, isTrue); // The notification should still show without audio
      expect(mockLogger.warningLogs, contains(any(contains('Audio resource not available'))));
    });

    test('prevents operation if not initialized', () async {
      // Arrange - don't initialize

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      final result = await nudgeHelper.showDeviceUnlockNudge(template!);

      // Assert
      expect(result, isFalse);
      expect(mockLogger.warningLogs, contains(any(contains('Cannot show device unlock nudge: helper not initialized'))));
    });

    test('handles nudge service failures gracefully', () async {
      // Arrange
      await nudgeHelper.initialize();
      when(mockNudgeService.getUserSettings()).thenThrow(Exception('NudgeService error'));

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      final result = await nudgeHelper.showDeviceUnlockNudge(template!);

      // Assert
      expect(result, isFalse);
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Error in device unlock'))));
    });
  });

  // 7. INTEGRATION TESTING
  group('7. Integration Testing', () {
    test('coordinates with NotificationService when scheduling', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      await nudgeHelper.scheduleNudgeForTimeWindow(template!, TimeWindow.morning);

      // Assert
      // Verify ID range registration
      verify(mockNotificationService.registerReservedIdRange(any, any)).called(1);
    });

    test('respects notification conflicts', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Simulate a system notification conflict
      mockPreferences.data['hasActiveSystemNotification'] = true;

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      final result = await nudgeHelper._handleDeviceUnlockCheck({});

      // Assert
      expect(result, isTrue); // Task succeeds but does nothing
      expect(mockLogger.infoLogs, contains(any(contains('Skipping device unlock nudge due to notification conflict'))));
    });

    test('manages reserved ID ranges correctly', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Register an external range
      await nudgeHelper.registerReservedIdRange('500', '600');

      // Verify range was stored
      expect(mockPreferences.data.containsKey('nudgeReservedIdRanges'), isTrue);

      // Act - check if an ID in the reserved range conflicts
      final conflicts = nudgeHelper._isIdInReservedRange(550);

      // Assert
      expect(conflicts, isTrue);
    });

    test('continues operation when NotificationService is not registered', () async {
      // Arrange
      await GetIt.instance.unregister<NotificationService>();

      // Act
      final result = await nudgeHelper.initialize();

      // Assert
      expect(result, isTrue);
      expect(nudgeHelper.isInitialized, isTrue);
    });
  });

  // 8. TIMING TESTS
  group('8. Timing Tests', () {
    test('calculates correct scheduled time for time window', () async {
      // Arrange
      await nudgeHelper.initialize();
      final timeWindow = TimeWindow.morning;

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(timeWindow);
      await nudgeHelper.scheduleNudgeForTimeWindow(template!, timeWindow);

      // Assert
      expect(mockNotificationsPlugin.lastScheduledNotificationData, isNotNull);

      // Calculate expected time (8 AM for morning)
      final now = DateTime.now();
      final expectedHour = timeWindow.startHour + 1; // An hour after window starts

      // Verify time calculation was correct
      final scheduledTime = mockNotificationsPlugin.lastScheduledNotificationData!['scheduledDate'] as String;

      if (now.hour < expectedHour) {
        // Should be scheduled for today
        expect(scheduledTime, contains(now.year.toString()));
        expect(scheduledTime, contains(now.month.toString()));
        expect(scheduledTime, contains(now.day.toString()));
        expect(scheduledTime, contains(expectedHour.toString()));
      } else {
        // Should be scheduled for tomorrow
        final tomorrow = now.add(Duration(days: 1));
        expect(scheduledTime, contains(tomorrow.year.toString()));
        expect(scheduledTime, contains(tomorrow.month.toString()));
        expect(scheduledTime, contains(tomorrow.day.toString()));
        expect(scheduledTime, contains(expectedHour.toString()));
      }
    });

    test('handles custom time window settings', () async {
      // Arrange
      await nudgeHelper.initialize();
      final timeWindow = TimeWindow.morning;

      // Create a custom time window
      final customization = TimeWindowCustomization(
        startHour: 5, // Earlier morning
        endHour: 7,
      );

      // Act
      final calculatedTime = nudgeHelper._calculateTimeForWindow(timeWindow, customization);

      // Assert
      // Should be scheduled for 6 AM (custom start + 1)
      expect(calculatedTime.hour, equals(6));
    });

    test('uses timezone-aware scheduling', () async {
      // Arrange
      await nudgeHelper.initialize();
      final timeWindow = TimeWindow.evening;

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(timeWindow);
      await nudgeHelper.scheduleNudgeForTimeWindow(template!, timeWindow);

      // Assert
      expect(mockNotificationsPlugin.lastScheduledNotificationData, isNotNull);

      // Verify timezone was used
      final scheduledTime = mockNotificationsPlugin.lastScheduledNotificationData!['scheduledDate'] as String;
      expect(scheduledTime, contains('America/New_York'));
    });
  });

  // 9. STATE PERSISTENCE
  group('9. State Persistence', () {
    test('saves and recovers notification delivery counter', () async {
      // Arrange - initialize and deliver a notification
      await nudgeHelper.initialize();
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      await nudgeHelper.showDeviceUnlockNudge(template!);

      // Save state
      await nudgeHelper._saveServiceState();

      // Create a new instance
      final newHelper = NudgeNotificationHelper(
        notificationsPlugin: mockNotificationsPlugin,
        logger: mockLogger,
        advancedLogger: mockAdvancedLogger,
        audioPlayer: mockAudioPlayer,
        sharedPreferences: mockPreferences,
        nudgeService: mockNudgeService,
        battery: mockBattery,
        deviceInfo: mockDeviceInfo,
      );

      // Act - load state
      await newHelper._loadPersistedData();

      // Assert
      expect(newHelper._notificationsDeliveredToday, equals(1));
    });

    test('recovers scheduled nudges after crash', () async {
      // Arrange - simulate saved state with scheduled nudges
      await nudgeHelper.initialize();

      // Set up state with scheduled nudges
      final pastTimestamp = DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch;

      final scheduledNudgeIds = ['1001:morning_nudge', '1002:midday_nudge'];

      await mockPreferences.setString('nudgeServiceState', jsonEncode({
        'isInitialized': true,
        'status': NudgeNotificationStatus.ready.index,
        'scheduledNudgeIds': scheduledNudgeIds,
        'savedTimestamp': pastTimestamp,
      }));

      await mockPreferences.setInt('nudgeLastLoadTimestamp', pastTimestamp - 1000);

      // Mock the nudge service to return templates for these IDs
      when(mockNudgeService.getNudgeTemplateById('morning_nudge')).thenAnswer((_) async =>
          NudgeTemplate(
            id: 'morning_nudge',
            content: 'Recovered morning nudge',
            category: NudgeCategory.gratitude,
            isActive: true,
            version: 1,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )
      );

      // Act
      await nudgeHelper.initialize();

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Detected potential crash or unexpected termination'))));
      expect(mockLogger.infoLogs, contains(any(contains('Recovered nudge schedule'))));
    });

    test('handles corrupted persistent state', () async {
      // Arrange - set corrupted JSON
      await mockPreferences.setString('nudgeServiceState', '{corrupt-json');

      // Act
      await nudgeHelper.initialize();

      // Assert
      expect(mockAdvancedLogger.errorLogs, contains(any(contains('Failed to load service state'))));

      // Service should still initialize
      expect(nudgeHelper.isInitialized, isTrue);
    });

    test('resets daily counter at midnight', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Set a delivery date from yesterday
      final yesterday = DateTime.now().subtract(Duration(days: 1));
      nudgeHelper._lastDeliveryDate = yesterday;
      nudgeHelper._notificationsDeliveredToday = 5;

      // Act
      await nudgeHelper._resetDailyCounterIfNeeded();

      // Assert
      expect(nudgeHelper._notificationsDeliveredToday, equals(0));
      expect(nudgeHelper._lastDeliveryDate?.day, equals(DateTime.now().day));
    });
  });

  // 10. NOTIFICATION DELIVERY VERIFICATION
  group('10. Notification Delivery Verification', () {
    test('therapeutic nudge notifications contain correct content and category-specific styling', () async {
      // Arrange
      await nudgeHelper.initialize();
      final category = NudgeCategory.gratitude;

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      await nudgeHelper.showDeviceUnlockNudge(template!);

      // Assert
      expect(mockNotificationsPlugin.lastNotificationData, isNotNull);
      expect(mockNotificationsPlugin.lastNotificationData!['title'], contains('Gratitude'));
      expect(mockNotificationsPlugin.lastNotificationData!['body'], equals(template.content));
      expect(mockNotificationsPlugin.lastNotificationData!['payload'], contains('${template.id}:view'));
    });

    test('scheduled nudges include time window information', () async {
      // Arrange
      await nudgeHelper.initialize();
      final timeWindow = TimeWindow.evening;

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(timeWindow);
      await nudgeHelper.scheduleNudgeForTimeWindow(template!, timeWindow);

      // Assert
      expect(mockNotificationsPlugin.lastScheduledNotificationData, isNotNull);
      expect(mockNotificationsPlugin.lastScheduledNotificationData!['matchDateTimeComponents'], contains('time'));
    });

    test('delivery counter increments correctly', () async {
      // Arrange
      await nudgeHelper.initialize();
      final startCount = nudgeHelper._notificationsDeliveredToday;

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      await nudgeHelper.showDeviceUnlockNudge(template!);

      // Assert
      expect(nudgeHelper._notificationsDeliveredToday, equals(startCount + 1));

      // Verify counter was persisted
      final savedCount = mockPreferences.getInt('nudge_notificationsDeliveredToday');
      expect(savedCount, equals(startCount + 1));
    });

    test('respects daily notification limit', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Set counter to max
      nudgeHelper._notificationsDeliveredToday = 3;
      await mockPreferences.setInt('nudge_notificationsDeliveredToday', 3);

      // Act
      final template = await mockNudgeService.getRandomNudgeForTimeWindow(TimeWindow.morning);
      final result = await nudgeHelper.showDeviceUnlockNudge(template!);

      // Assert
      expect(result, isFalse);
      expect(mockLogger.infoLogs, contains(any(contains('Daily notification limit reached'))));
    });
  });

  // 11. ACCESSIBILITY TESTING
  group('11. Accessibility Testing', () {
    test('performs accessibility tests correctly', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act
      final results = await nudgeHelper.performAccessibilityTests();

      // Assert
      expect(results, isA<Map<String, bool>>());
      expect(results.keys, containsAll(['fontSizeAdequate', 'colorContrastSufficient', 'actionsEasilyTappable', 'audioQualityClear']));
    });

    test('adapts font size based on platform version', () async {
      // Arrange - mock older Android version
      when(mockDeviceInfo.androidInfo).thenAnswer((_) async {
        fakeAndroidInfo.setSdkInt(21);
        return fakeAndroidInfo;
      });

      await nudgeHelper.initialize();

      // Act
      final results = await nudgeHelper.performAccessibilityTests();

      // Assert
      expect(results['fontSizeAdequate'], isFalse);
    });

    test('adapts color contrast based on platform version', () async {
      // Arrange - mock newer Android version
      when(mockDeviceInfo.androidInfo).thenAnswer((_) async {
        fakeAndroidInfo.setSdkInt(28);
        return fakeAndroidInfo;
      });

      await nudgeHelper.initialize();

      // Act
      final results = await nudgeHelper.performAccessibilityTests();

      // Assert
      expect(results['colorContrastSufficient'], isTrue);
    });

    test('battery status affects audio quality assessment', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Set low battery
      mockBattery.setBatteryLevel(10);
      mockBattery.setBatteryState(BatteryState.discharging);

      // Act
      final results = await nudgeHelper.performAccessibilityTests();

      // Assert
      expect(results['audioQualityClear'], isFalse);
    });
  });

  // 12. CALLBACK TESTING
  group('12. Callback Testing', () {
    test('onDidReceiveNotificationResponse handles view action', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act
      await nudgeHelper._onDidReceiveNotificationResponse(
          NotificationResponse(
            id: 1001,
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: 'test_id:view',
          )
      );

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Notification tapped with payload: test_id:view'))));

      // Verify analytics was updated
      expect(mockPreferences.getInt('nudgeAnalytics_viewed'), equals(1));
    });

    test('onDidReceiveNotificationResponse handles replay action', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act
      await nudgeHelper._onDidReceiveNotificationResponse(
          NotificationResponse(
            id: 1001,
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: 'test_id:replay',
            actionId: 'replay',
          )
      );

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Replaying nudge audio for ID: test_id'))));

      // Verify audio player was used
      expect(mockAudioPlayer.isPlaying, isTrue);

      // Verify analytics was updated
      expect(mockPreferences.getInt('nudgeAnalytics_replayed'), equals(1));
    });

    test('onDidReceiveNotificationResponse handles save as memory action', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act
      await nudgeHelper._onDidReceiveNotificationResponse(
          NotificationResponse(
            id: 1001,
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: 'test_id:save_memory',
            actionId: 'save_memory',
          )
      );

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Saving nudge as memory: test_id'))));

      // Verify analytics was updated
      expect(mockPreferences.getInt('nudgeAnalytics_saved'), equals(1));
    });

    test('onDidReceiveNotificationResponse handles dismiss action', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act
      await nudgeHelper._onDidReceiveNotificationResponse(
          NotificationResponse(
            id: 1001,
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: 'test_id:dismiss',
            actionId: 'dismiss',
          )
      );

      // Assert
      expect(mockPreferences.getInt('nudgeAnalytics_dismissed'), equals(1));
    });

    test('onDidReceiveNotificationResponse handles missing payload', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act - should not throw
      await nudgeHelper._onDidReceiveNotificationResponse(
          NotificationResponse(
            id: 1001,
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: null,
          )
      );

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Notification tapped with payload: null'))));
    });

    test('onDidReceiveLocalNotification handles iOS foreground notifications', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Create event controller to capture stream events
      final receivedEvents = <Map<String, dynamic>>[];
      final subscription = nudgeHelper.notificationStream.listen((event) {
        receivedEvents.add(event);
      });

      // Act
      nudgeHelper._onDidReceiveLocalNotification(
          1001, 'Therapeutic Nudge', 'Nudge content', 'test_id:view'
      );

      // Wait for async
      await Future.delayed(Duration(milliseconds: 100));

      // Assert
      expect(mockLogger.infoLogs, contains(any(contains('Received iOS foreground notification'))));

      // Verify event was emitted to stream
      expect(receivedEvents, hasLength(1));
      expect(receivedEvents[0]['event'], equals('receivedForeground'));
      expect(receivedEvents[0]['title'], equals('Therapeutic Nudge'));

      // Verify analytics was updated
      expect(mockPreferences.getInt('nudgeAnalytics_delivered'), equals(1));

      // Clean up
      await subscription.cancel();
    });

    test('handles background notification response', () async {
      // This is a static method, so we need to test it differently
      // We'll verify it delegates to the instance method

      // Arrange
      await nudgeHelper.initialize();
      final response = NotificationResponse(
        id: 1001,
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'test_id:view',
      );

      // Act & Assert - this shouldn't throw
      // We can't directly test the delegation, but we can verify it doesn't crash
      expect(() => NudgeNotificationHelper._onDidReceiveBackgroundNotificationResponse(response),
          returnsNormally);
    });
  });

  // ADDITIONAL TEST: WORKMANAGER BACKGROUND TASKS
  group('Workmanager Background Tasks', () {
    test('registerDeviceUnlockTrigger schedules periodic task', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act
      final result = await nudgeHelper.registerDeviceUnlockTrigger();

      // Assert
      expect(result, isTrue);

      // Verify Workmanager task was registered
      expect(mockWorkmanager.lastRegisteredTask['uniqueName'], equals('deviceUnlockCheck'));
      expect(mockWorkmanager.lastRegisteredTask['taskName'], equals('checkDeviceUnlock'));
    });

    test('scheduleTimeBasedNudges registers daily task', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Act
      final result = await nudgeHelper.scheduleTimeBasedNudges();

      // Assert
      expect(result, isTrue);

      // Verify multiple tasks were registered
      expect(mockWorkmanager.lastRegisteredTask['uniqueName'], equals('dailyCleanup'));
      expect(mockWorkmanager.lastRegisteredTask['taskName'], equals('cleanupOldNudges'));
    });

    test('battery status affects task constraints', () async {
      // Arrange
      await nudgeHelper.initialize();

      // Set low battery
      mockBattery.setBatteryLevel(10);
      mockBattery.setBatteryState(BatteryState.discharging);

      // Act
      final result = await nudgeHelper.registerDeviceUnlockTrigger();

      // Assert
      expect(result, isTrue);

      // Verify battery constraints were used
      expect(mockLogger.infoLogs, contains(any(contains('Registered device unlock trigger'))));
    });
  });
}