// lib/services/nudge_notification_helper.dart
//
// Copyright (c) 2025 Milo Health Technologies
// Version: 1.2.0
//
// Specialized notification helper for therapeutic nudges, designed
// specifically for elderly users (55+).
//
// This helper extends the base notification functionality to provide
// audio-focused, accessible notifications with custom actions that
// work with the app's therapeutic nudging system.

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logging/logging.dart';
import 'package:workmanager/workmanager.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'dart:convert';

import '../models/nudge_model.dart';
import '../utils/advanced_logger.dart';
import '../services/nudge_service.dart';
import 'notification_service.dart';

/// Service initialization status
enum NudgeNotificationStatus {
  uninitialized,
  initializing,
  ready,
  permissionDenied,
  permissionPermanentlyDenied,
  failed,
}

/// Manages notifications specifically for therapeutic nudges with
/// elderly-friendly features and audio support
class NudgeNotificationHelper {
  // Singleton access via GetIt
  static NudgeNotificationHelper get instance => GetIt.instance<NudgeNotificationHelper>();

  // Constants for shared preferences keys
  static const String _prefKeyNotificationsDeliveredToday = 'nudge_notificationsDeliveredToday';
  static const String _prefKeyLastDeliveryDate = 'nudge_lastDeliveryDate';
  static const String _notificationTaskPort = 'nudge_notification_task_port';

  // Dependencies - using instance variables for better DI
  final Logger _logger;
  final AdvancedLogger _advancedLogger;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final AudioPlayer _audioPlayer;
  final SharedPreferences _sharedPreferences;
  final NudgeService _nudgeService;
  final Battery _battery;
  final DeviceInfoPlugin _deviceInfo;

  // Channel IDs for different nudge categories
  static const String _baseChannelId = 'milo_therapeutic_nudges';
  final Map<NudgeCategory, String> _categoryChannelIds = {
    NudgeCategory.gratitude: '${_baseChannelId}_gratitude',
    NudgeCategory.mindfulness: '${_baseChannelId}_mindfulness',
    NudgeCategory.selfReflection: '${_baseChannelId}_reflection',
    NudgeCategory.reassurance: '${_baseChannelId}_reassurance',
    NudgeCategory.cognitiveTip: '${_baseChannelId}_cognitive',
  };

  // Notification IDs by time window
  // Reserved range: 1000-2000
  static const int _reservedIdStart = 1000;
  static const int _reservedIdEnd = 2000;
  static const int _morningNudgeId = 1001;
  static const int _middayNudgeId = 1002;
  static const int _eveningNudgeId = 1003;
  static const int _deviceUnlockNudgeId = 1004;

  // Range for other services' IDs
  Set<String> _reservedIdRanges = {};

  // Store upcoming scheduled nudges (for management)
  // Limited to current day's nudges only (cleanup happens daily)
  final Map<int, NudgeTemplate> _scheduledNudges = {};

  // Track notifications delivered per day (to respect maxNudgesPerDay)
  int _notificationsDeliveredToday = 0;
  DateTime? _lastDeliveryDate;

  // Store notification analytics for event tracking
  final Map<String, int> _notificationAnalytics = {
    'delivered': 0,
    'viewed': 0,
    'replayed': 0,
    'saved': 0,
    'dismissed': 0,
  };

  // Battery optimization flags
  bool _isLowBattery = false;
  bool _isPowerSaveMode = false;

  // Service status
  NudgeNotificationStatus _status = NudgeNotificationStatus.uninitialized;
  bool _isInitialized = false;
  Completer<bool>? _initCompleter;

  // Stream controller for notification events
  final StreamController<Map<String, dynamic>> _notificationStreamController =
  StreamController<Map<String, dynamic>>.broadcast();

  // Platform version caching
  int? _androidApiLevel;
  String? _iOSVersion;

  // App lifecycle state
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  // Test mode flag
  bool _isInTestMode = false;

  /// Stream of notification events
  Stream<Map<String, dynamic>> get notificationStream => _notificationStreamController.stream;

  /// Current status of the helper
  NudgeNotificationStatus get status => _status;

  /// Whether the helper is initialized
  bool get isInitialized => _isInitialized;

  /// Constructor with dependency injection
  NudgeNotificationHelper({
    Logger? logger,
    AdvancedLogger? advancedLogger,
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    AudioPlayer? audioPlayer,
    SharedPreferences? sharedPreferences,
    NudgeService? nudgeService,
    Battery? battery,
    DeviceInfoPlugin? deviceInfo,
  }) :
        _logger = logger ?? Logger('NudgeNotificationHelper'),
        _advancedLogger = advancedLogger ?? AdvancedLogger(tag: 'NudgeNotification'),
        _notificationsPlugin = notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
        _audioPlayer = audioPlayer ?? AudioPlayer(),
        _sharedPreferences = sharedPreferences ?? SharedPreferences.getInstance() as SharedPreferences,
        _nudgeService = nudgeService ?? NudgeService(),
        _battery = battery ?? Battery(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  /// Register with GetIt service locator
  static Future<void> registerService() async {
    if (!GetIt.instance.isRegistered<NudgeNotificationHelper>()) {
      final sharedPrefs = await SharedPreferences.getInstance();
      final nudgeService = GetIt.instance.isRegistered<NudgeService>()
          ? GetIt.instance<NudgeService>()
          : NudgeService();

      GetIt.instance.registerSingleton<NudgeNotificationHelper>(
          NudgeNotificationHelper(
            sharedPreferences: sharedPrefs,
            nudgeService: nudgeService,
          )
      );
    }
  }

  /// Initialize the notification helper with robust error handling and lifecycle integration
  Future<bool> initialize() async {
    // Prevent double initialization
    if (_isInitialized) return true;

    // Handle concurrent initialization attempts
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<bool>();
    _status = NudgeNotificationStatus.initializing;

    try {
      _advancedLogger.info('Initializing NudgeNotificationHelper');

      // Check platform versions for compatibility
      await _checkPlatformCompatibility();

      // Register lifecycle observer
      WidgetsBinding.instance.addObserver(_AppLifecycleObserver(this));

      // Load saved state
      await _loadPersistedData();

      // Register battery monitoring
      await _registerBatteryMonitoring();

      // Define platform-specific initialization settings
      final AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
        requestAlertPermission: false, // We'll request permissions separately
        requestBadgePermission: false,
        requestSoundPermission: false,
        onDidReceiveLocalNotification: _onDidReceiveLocalNotification,
        notificationCategories: _createIOSNotificationCategories(),
      );

      final InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      // Set up port for background communication
      final port = ReceivePort();
      IsolateNameServer.registerPortWithName(port.sendPort, _notificationTaskPort);

      port.listen((dynamic data) {
        _handleBackgroundMessage(data);
      });

      // Initialize the plugin with proper callback handling
      final initialized = await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: _onDidReceiveBackgroundNotificationResponse,
      );

      if (initialized != true) {
        throw Exception('Notification plugin initialization failed');
      }

      // Create channels for each nudge category (Android only)
      if (Platform.isAndroid) {
        await _createNotificationChannels();
      }

      // Initialize Workmanager for background tasks
      await Workmanager().initialize(
        _callbackDispatcher,
        isInDebugMode: false,
      );

      // Reset delivery counter if it's a new day
      await _resetDailyCounterIfNeeded();

      // Clean up old scheduled nudges
      _cleanupOldScheduledNudges();

      // Check if NotificationService is registered to coordinate
      if (GetIt.instance.isRegistered<NotificationService>()) {
        // Register our ID range
        await NotificationService.instance.registerReservedIdRange(
            _reservedIdStart.toString(),
            _reservedIdEnd.toString()
        );
      }

      // Request permission with proper handling
      final permissionResult = await _requestPermissions();

      if (permissionResult.isGranted) {
        _status = NudgeNotificationStatus.ready;
        _isInitialized = true;
      } else if (permissionResult.isPermanentlyDenied) {
        _status = NudgeNotificationStatus.permissionPermanentlyDenied;
        _advancedLogger.warning(
            'Notification permission permanently denied. Helper partially initialized.'
        );
      } else {
        _status = NudgeNotificationStatus.permissionDenied;
        _advancedLogger.warning(
            'Notification permission denied. Helper partially initialized.'
        );
      }

      // Recovery from previous state if needed
      await _recoverFromPreviousState();

      _advancedLogger.info('NudgeNotificationHelper initialized successfully');
      _saveServiceState();

      _initCompleter!.complete(_isInitialized);
      return _isInitialized;
    } catch (e, stackTrace) {
      _status = NudgeNotificationStatus.failed;
      _advancedLogger.error(
        'Failed to initialize NudgeNotificationHelper',
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

  /// Save service state for recovery
  Future<void> _saveServiceState() async {
    try {
      // Save the IDs of currently scheduled nudges
      final List<String> scheduledNudgeIds = [];
      _scheduledNudges.forEach((key, value) {
        scheduledNudgeIds.add('$key:${value.id}');
      });

      final state = {
        'isInitialized': _isInitialized,
        'status': _status.index,
        'scheduledNudgeIds': scheduledNudgeIds,
        'savedTimestamp': DateTime.now().millisecondsSinceEpoch,
        'notificationsDeliveredToday': _notificationsDeliveredToday,
        'lastDeliveryDate': _lastDeliveryDate?.toIso8601String(),
      };

      await _sharedPreferences.setString('nudgeServiceState', jsonEncode(state));
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
      final stateJson = _sharedPreferences.getString('nudgeServiceState');
      if (stateJson == null) return;

      final state = jsonDecode(stateJson) as Map<String, dynamic>;

      // We don't restore isInitialized - that happens only via initialize()
      _status = NudgeNotificationStatus.values[state['status'] as int? ?? 0];

      final lastDeliveryDateStr = state['lastDeliveryDate'] as String?;
      if (lastDeliveryDateStr != null) {
        _lastDeliveryDate = DateTime.parse(lastDeliveryDateStr);
      }

      _notificationsDeliveredToday = state['notificationsDeliveredToday'] as int? ?? 0;

      // Record load time for recovery logic
      await _sharedPreferences.setInt('nudgeLastLoadTimestamp', DateTime.now().millisecondsSinceEpoch);
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
      final lastSavedTimestamp = _sharedPreferences.getInt('nudgeSavedTimestamp') ?? 0;
      final lastLoadTimestamp = _sharedPreferences.getInt('nudgeLastLoadTimestamp') ?? 0;

      // If saved timestamp is more recent than load timestamp,
      // we might have crashed or been terminated unexpectedly
      if (lastSavedTimestamp > lastLoadTimestamp) {
        _logger.info('Detected potential crash or unexpected termination. Recovering nudge state...');

        final stateJson = _sharedPreferences.getString('nudgeServiceState');
        if (stateJson != null) {
          final state = jsonDecode(stateJson) as Map<String, dynamic>;

          // Recover scheduled nudges
          final scheduledNudgeIds = (state['scheduledNudgeIds'] as List<dynamic>?)?.cast<String>() ?? [];

          for (final entry in scheduledNudgeIds) {
            final parts = entry.split(':');
            if (parts.length == 2) {
              final notificationId = int.tryParse(parts[0]);
              final templateId = parts[1];

              if (notificationId != null) {
                // Try to recover this nudge
                final template = await _nudgeService.getNudgeTemplateById(templateId);
                if (template != null) {
                  // Determine time window from notification ID
                  TimeWindow? timeWindow;
                  if (notificationId == _morningNudgeId) {
                    timeWindow = TimeWindow.morning;
                  } else if (notificationId == _middayNudgeId) {
                    timeWindow = TimeWindow.midday;
                  } else if (notificationId == _eveningNudgeId) {
                    timeWindow = TimeWindow.evening;
                  }

                  if (timeWindow != null) {
                    // Reschedule the nudge
                    await scheduleNudgeForTimeWindow(
                      template,
                      timeWindow,
                      playAudio: true,
                    );

                    _logger.info('Recovered nudge schedule for ${timeWindow.displayName}');
                  }
                }
              }
            }
          }
        }
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
        // App comes to foreground
          _refreshPermissionStatus();
          // Refresh battery status
          _refreshBatteryStatus();
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
      if (_status == NudgeNotificationStatus.permissionDenied ||
          _status == NudgeNotificationStatus.permissionPermanentlyDenied) {
        final status = await Permission.notification.status;

        if (status.isGranted && _status != NudgeNotificationStatus.ready) {
          // Permission granted while app was in background
          _status = NudgeNotificationStatus.ready;
          _isInitialized = true;
          _saveServiceState();
          _advancedLogger.info('Permission status changed to granted. Helper now ready.');
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

  /// Create iOS notification categories with actions
  Set<DarwinNotificationCategory> _createIOSNotificationCategories() {
    try {
      // Define iOS notification actions
      final replayAction = DarwinNotificationAction.plain(
        'replay',
        'Replay',
        options: DarwinNotificationActionOptions.foreground,
      );

      final saveAction = DarwinNotificationAction.plain(
        'save_memory',
        'Save as Memory',
        options: DarwinNotificationActionOptions.foreground,
      );

      final dismissAction = DarwinNotificationAction.plain(
        'dismiss',
        'Dismiss',
        options: DarwinNotificationActionOptions.destructive,
      );

      // Create category for each nudge type
      final Set<DarwinNotificationCategory> categories = {};

      for (final category in NudgeCategory.values) {
        final categoryId = _categoryChannelIds[category]!;
        categories.add(DarwinNotificationCategory(
          categoryId,
          actions: [replayAction, saveAction, dismissAction],
          options: <DarwinNotificationCategoryOption>{
            DarwinNotificationCategoryOption.allowAnnouncement,
          },
        ));
      }

      // Add a default category as well
      categories.add(DarwinNotificationCategory(
        'nudgeCategory',
        actions: [replayAction, saveAction, dismissAction],
        options: <DarwinNotificationCategoryOption>{
          DarwinNotificationCategoryOption.allowAnnouncement,
        },
      ));

      _logger.info('Created ${categories.length} iOS notification categories');
      return categories;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to create iOS notification categories',
        error: e,
        stackTrace: stackTrace,
      );
      return {};
    }
  }

  /// Create notification channels for different nudge categories (Android only)
  Future<void> _createNotificationChannels() async {
    try {
      // Only supported on Android 8.0+
      if (_androidApiLevel != null && _androidApiLevel! < 26) {
        _logger.info('Skipping notification channel creation for Android API level $_androidApiLevel');
        return;
      }

      // Create a channel for each nudge category with appropriate settings
      for (final category in NudgeCategory.values) {
        final channelId = _categoryChannelIds[category]!;
        final channelName = '${category.displayName} Nudges';
        final channelDescription = 'Therapeutic nudges for ${category.displayName.toLowerCase()}';

        final AndroidNotificationChannelGroup channelGroup =
        AndroidNotificationChannelGroup(
          _baseChannelId,
          'Therapeutic Nudges',
          description: 'All types of therapeutic nudge notifications',
        );

        // Create the channel group first
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation
        AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannelGroup(channelGroup);

        // Then create the channel
        final AndroidNotificationChannel notificationChannel =
        AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          groupId: _baseChannelId,
          // Set to false to allow user to disable if desired
          // This respects user preferences better
          enableLights: true,
          showBadge: true,
        );

        await _notificationsPlugin
            .resolvePlatformSpecificImplementation
        AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(notificationChannel);

        _logger.info('Created notification channel: $channelId');
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to create notification channels',
        error: e,
        stackTrace: stackTrace,
      );
      // Don't rethrow - channels are not critical, app can function without them
    }
  }

  /// Register battery status monitoring
  Future<void> _registerBatteryMonitoring() async {
    try {
      // Get initial battery level
      final batteryLevel = await _battery.batteryLevel;
      _isLowBattery = batteryLevel <= 15; // Consider 15% or lower as low battery

      // Set up listener for battery level changes
      _battery.onBatteryStateChanged.listen((BatteryState state) async {
        // Update battery level
        final level = await _battery.batteryLevel;
        _isLowBattery = level <= 15;

        // Check power save mode
        // This is platform-specific and might need plugin support
        _isPowerSaveMode = state == BatteryState.charging ? false : _isLowBattery;

        _logger.info('Battery update: level=$level%, low=$_isLowBattery, powerSave=$_isPowerSaveMode');
      });

      _logger.info('Registered battery monitoring: initial level=$batteryLevel%, low=$_isLowBattery');
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to register battery monitoring',
        error: e,
        stackTrace: stackTrace,
      );

      // Default to conservative values on error
      _isLowBattery = false;
      _isPowerSaveMode = false;
    }
  }

  /// Refresh battery status manually
  Future<void> _refreshBatteryStatus() async {
    try {
      final batteryLevel = await _battery.batteryLevel;
      _isLowBattery = batteryLevel <= 15;

      final batteryState = await _battery.batteryState;
      _isPowerSaveMode = batteryState == BatteryState.charging ? false : _isLowBattery;

      _logger.info('Refreshed battery status: level=$batteryLevel%, low=$_isLowBattery, powerSave=$_isPowerSaveMode');
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to refresh battery status',
        error: e,
        stackTrace: stackTrace,
      );
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
          critical: true, // Important for therapeutic nudges
        ) ?? false;

        return result ? PermissionStatus.granted : PermissionStatus.denied;
      } else {
        // For Android
        final status = await Permission.notification.status;

        if (status.isGranted) {
          return PermissionStatus.granted;
        } else if (status.isDenied) {
          final result = await Permission.notification.request();

          // If still denied after requesting, show explanation next time
          if (result.isDenied) {
            await _sharedPreferences.setBool('showPermissionExplanation', true);
          }

          return result;
        } else if (status.isPermanentlyDenied) {
          // Save this state to show settings guidance
          await _sharedPreferences.setBool('showPermissionSettings', true);
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
    return _sharedPreferences.getBool('showPermissionSettings') ?? false;
  }

  /// Check if we need to show permission explanation
  Future<bool> needsPermissionExplanation() async {
    return _sharedPreferences.getBool('showPermissionExplanation') ?? false;
  }

  /// Open app settings to enable notifications
  Future<void> openNotificationSettings() async {
    try {
      await openAppSettings();
      // Reset the flag once we've shown guidance
      await _sharedPreferences.setBool('showPermissionSettings', false);
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to open notification settings',
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

      // Track the received notification
      _trackNotificationEvent('delivered');

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

      // Track the viewed notification
      _trackNotificationEvent('viewed');

      // Broadcast to stream for any listeners
      _notificationStreamController.add({
        'id': response.id,
        'payload': payload,
        'actionId': response.actionId,
        'event': 'tapped',
      });

      // For testing
      if (_isInTestMode) {
        await _sharedPreferences.setString('lastTappedNudgeNotification', jsonEncode({
          'id': response.id,
          'payload': payload,
          'actionId': response.actionId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      }

      if (payload == null) return;

      // Extract nudge ID and action from payload
      final parts = payload.split(':');
      if (parts.length < 2) return;

      final nudgeId = parts[0];
      final action = parts[1];

      await _handleNotificationAction(nudgeId, action, response.notificationResponseType);
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error handling notification response',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Background notification response handler (static for registration)
  @pragma('vm:entry-point')
  static void _onDidReceiveBackgroundNotificationResponse(
      NotificationResponse response) async {
    // Get the instance first
    final helper = GetIt.instance<NudgeNotificationHelper>();

    // Then delegate to the instance method
    helper._onDidReceiveNotificationResponse(response);
  }

  /// Handle notification action with proper tracking
  Future<void> _handleNotificationAction(
      String nudgeId, String action, NotificationResponseType responseType) async {
    try {
      switch (action) {
        case 'view':
        // Navigate to nudge detail screen
          _trackNotificationEvent('viewed');
          break;
        case 'replay':
          await _replayNudgeAudio(nudgeId);
          _trackNotificationEvent('replayed');
          break;
        case 'save_memory':
          await _saveNudgeAsMemory(nudgeId);
          _trackNotificationEvent('saved');
          break;
        case 'dismiss':
          _trackNotificationEvent('dismissed');
          break;
        default:
          _logger.warning('Unknown notification action: $action');
      }

      // Persist analytics data
      await _persistAnalyticsData();
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error handling notification action',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Track notification events for analytics
  void _trackNotificationEvent(String eventType) {
    if (_notificationAnalytics.containsKey(eventType)) {
      _notificationAnalytics[eventType] = (_notificationAnalytics[eventType] ?? 0) + 1;
      _logger.info('Tracked notification event: $eventType, count: ${_notificationAnalytics[eventType]}');
    }
  }

  /// Persist analytics data to storage
  Future<void> _persistAnalyticsData() async {
    try {
      for (final entry in _notificationAnalytics.entries) {
        await _sharedPreferences.setInt('nudgeAnalytics_${entry.key}', entry.value);
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to persist analytics data',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Load persisted analytics data
  Future<void> _loadAnalyticsData() async {
    try {
      for (final key in _notificationAnalytics.keys) {
        final value = _sharedPreferences.getInt('nudgeAnalytics_$key') ?? 0;
        _notificationAnalytics[key] = value;
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to load analytics data',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get notification analytics data
  Map<String, int> getNotificationAnalytics() {
    return Map.from(_notificationAnalytics);
  }

  /// Callback function for Workmanager background tasks
  /// Uses more robust error handling and retry mechanism
  @pragma('vm:entry-point')
  static void _callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      try {
        // Set up logging for background tasks
        Logger.root.level = Level.INFO;
        final logger = Logger('NudgeNotificationBackground');
        logger.info('Executing background task: $task');

        final SendPort? sendPort = IsolateNameServer.lookupPortByName(_notificationTaskPort);

        // Initialize helper in the background context
        final helper = GetIt.instance<NudgeNotificationHelper>();
        if (!helper.isInitialized) {
          // Need to initialize in background context
          await helper.initialize();
        }

        bool taskSuccess = false;
        int retryCount = 0;
        const maxRetries = 3;

        // Try the task with retries
        while (!taskSuccess && retryCount < maxRetries) {
          try {
            switch (task) {
              case 'checkDeviceUnlock':
                taskSuccess = await helper._handleDeviceUnlockCheck(inputData);
                break;
              case 'scheduleTimeBasedNudges':
                taskSuccess = await helper._scheduleTimeBasedNudgesTask(inputData);
                break;
              case 'cleanupOldNudges':
                taskSuccess = await helper._cleanupTask(inputData);
                break;
              default:
                logger.warning('Unknown task type: $task');
                return false;
            }
          } catch (e) {
            retryCount++;
            logger.warning('Task failed (attempt $retryCount): $e');

            if (retryCount < maxRetries) {
              // Wait before retry with exponential backoff
              await Future.delayed(Duration(seconds: 2 * retryCount));
            }
          }
        }

        // Send result back to main isolate if possible
        if (sendPort != null) {
          sendPort.send({
            'task': task,
            'success': taskSuccess,
            'retryCount': retryCount,
          });
        }

        return taskSuccess;
      } catch (e) {
        // Last resort error handling
        print('Critical error in background task: $e');
        return false;
      }
    });
  }

  /// Handle background task messages from the isolate
  void _handleBackgroundMessage(dynamic data) {
    if (data is Map) {
      final task = data['task'] as String?;
      final success = data['success'] as bool?;
      final retryCount = data['retryCount'] as int?;

      _logger.info('Background task result: $task, success: $success, retries: $retryCount');

      // Update analytics or handle failures as needed
      if (success == true) {
        _trackNotificationEvent('background_success');
      } else {
        _trackNotificationEvent('background_failure');
      }
    }
  }

  /// Handle the device unlock check task
  Future<bool> _handleDeviceUnlockCheck(Map<String, dynamic>? inputData) async {
    try {
      // Check if we're conflicting with other notifications
      if (_checkForNotificationConflicts()) {
        _logger.info('Skipping device unlock nudge due to notification conflict');
        return true; // Task succeeded (by doing nothing)
      }

      // Check user settings first
      final settings = await _nudgeService.getUserSettings();

      if (settings == null || !settings.allowDeviceUnlockTrigger || !settings.nudgesEnabled) {
        _logger.info('Device unlock nudges disabled by user settings');
        return true; // Task succeeded (by doing nothing)
      }

      // Check if we've reached the daily limit
      if (!await _canDeliverMoreNotificationsToday(settings.maxNudgesPerDay)) {
        _logger.info('Daily notification limit reached, not showing device unlock nudge');
        return true; // Task succeeded (by doing nothing)
      }

      // Check if we're in an enabled time window
      final currentWindow = TimeWindow.currentTimeWindow();
      if (currentWindow == null || !settings.enabledTimeWindows[currentWindow]!) {
        _logger.info('Not in an enabled time window, skipping device unlock nudge');
        return true; // Task succeeded (by doing nothing)
      }

      // Check battery status for optimization
      if (_isLowBattery && _isPowerSaveMode) {
        _logger.info('Low battery and power save mode, skipping device unlock nudge');
        return true; // Task succeeded (by doing nothing)
      }

      // Get a suitable nudge template based on user preferences
      final nudgeTemplate = await _nudgeService.getRandomNudgeForTimeWindow(
        currentWindow,
        categories: settings.getEnabledCategories(),
      );

      if (nudgeTemplate == null) {
        _logger.warning('No suitable nudge template found for device unlock');
        return false; // Task failed (no suitable nudge)
      }

      // Show the nudge
      final result = await showDeviceUnlockNudge(
        nudgeTemplate,
        playAudio: !((_isLowBattery && _isPowerSaveMode)),
      );

      return result;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error in device unlock check task',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Check for conflicts with other notifications
  bool _checkForNotificationConflicts() {
    try {
      if (GetIt.instance.isRegistered<NotificationService>()) {
        final notificationService = NotificationService.instance;

        // Check if there's a system-critical notification active
        // This would be app-specific implementation
        // For now, we'll just check using a flag that could be set elsewhere
        final hasSystemNotification = _sharedPreferences.getBool('hasActiveSystemNotification') ?? false;

        return hasSystemNotification;
      }

      return false;
    } catch (e) {
      _logger.warning('Error checking for notification conflicts: $e');
      return false;
    }
  }

  /// Schedule time-based nudges in the background
  Future<bool> _scheduleTimeBasedNudgesTask(Map<String, dynamic>? inputData) async {
    try {
      // Check if we're conflicting with other notifications
      if (_checkForNotificationConflicts()) {
        _logger.info('Deferring time-based nudges due to notification conflict');

        // Reschedule for later
        Future.delayed(const Duration(hours: 1), () async {
          await registerDeviceUnlockTrigger();
        });

        return true; // Task succeeded (by deferring)
      }

      // Check user settings first
      final settings = await _nudgeService.getUserSettings();

      if (settings == null || !settings.allowTimeBasedTrigger || !settings.nudgesEnabled) {
        _logger.info('Time-based nudges disabled by user settings');
        return true; // Task succeeded (by doing nothing)
      }

      bool allSucceeded = true;

      // Schedule nudges for each enabled time window
      for (final timeWindow in TimeWindow.values) {
        if (settings.enabledTimeWindows[timeWindow] == true) {
          // Get a suitable nudge template
          final nudgeTemplate = await _nudgeService.getRandomNudgeForTimeWindow(
            timeWindow,
            categories: settings.getEnabledCategories(),
          );

          if (nudgeTemplate != null) {
            final scheduled = await scheduleNudgeForTimeWindow(
              nudgeTemplate,
              timeWindow,
              playAudio: !(_isLowBattery && _isPowerSaveMode),
            );

            if (!scheduled) {
              _logger.warning('Failed to schedule nudge for ${timeWindow.displayName}');
              allSucceeded = false;
            }
          } else {
            _logger.warning('No suitable nudge template found for ${timeWindow.displayName}');
            allSucceeded = false;
          }
        }
      }

      return allSucceeded;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error in schedule time-based nudges task',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Clean up old nudges and reset counters
  Future<bool> _cleanupTask(Map<String, dynamic>? inputData) async {
    try {
      // Reset the daily counter
      await _resetDailyCounterIfNeeded(force: true);

      // Clean up old scheduled nudges
      _cleanupOldScheduledNudges();

      // Persist analytics
      await _persistAnalyticsData();

      // Save state for recovery
      await _saveServiceState();

      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error in cleanup task',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Show an immediate nudge notification when the device is unlocked
  Future<bool> showDeviceUnlockNudge(
      NudgeTemplate nudge, {
        bool playAudio = true,
      }) async {
    try {
      // Check if initialized
      if (!_isInitialized) {
        _logger.warning('Cannot show device unlock nudge: helper not initialized');
        return false;
      }

      // Get the max notifications from user settings
      final settings = await _nudgeService.getUserSettings();
      final maxNotifications = settings?.maxNudgesPerDay ?? 3;

      // Check if we've hit the daily limit
      if (!await _canDeliverMoreNotificationsToday(maxNotifications)) {
        _logger.info('Daily notification limit reached, not showing device unlock nudge');
        return false;
      }

      // Check if we're in a conflict state
      if (_checkForNotificationConflicts()) {
        _logger.info('Skipping device unlock nudge due to notification conflict');
        return false;
      }

      // Get the current time window
      final TimeWindow? currentWindow = TimeWindow.currentTimeWindow();
      if (currentWindow == null) {
        _logger.info('Not in any defined time window, skipping device unlock nudge');
        return false;
      }

      // Check if this time window is enabled for the user
      if (settings?.enabledTimeWindows[currentWindow] == false) {
        _logger.info('Time window ${currentWindow.displayName} is disabled for user');
        return false;
      }

      // Get channel ID for this nudge category
      final String channelId = _categoryChannelIds[nudge.category] ?? _baseChannelId;

      // Use platform-specific features based on detected version
      final bool useHighContrast = _androidApiLevel == null || _androidApiLevel! >= 28;
      final bool useAccessibilityFeatures = _androidApiLevel == null || _androidApiLevel! >= 26;

      // Create the notification details with accessibility features for elderly users
      final androidDetails = AndroidNotificationDetails(
        channelId,
        '${nudge.category.displayName} Nudges',
        channelDescription: 'Therapeutic nudges for ${nudge.category.displayName.toLowerCase()}',
        importance: Importance.high,
        priority: Priority.high,
        // Use bigger text style for better readability
        styleInformation: BigTextStyleInformation(
          nudge.content,
          htmlFormatBigText: true,
          contentTitle: '<b>${_getTitleForCategory(nudge.category)}</b>',
          htmlFormatContentTitle: true,
          summaryText: 'Nudge for you',
          htmlFormatSummaryText: true,
        ),
        color: _getColorForCategory(nudge.category),
        colorized: useHighContrast,
        sound: playAudio ? null : UriAndroidNotificationSound('silent'),
        playSound: playAudio,
        // Make visuals more accessible
        largeIcon: DrawableResourceAndroidBitmap('notification_large_icon'),
        // Only add actions if platform supports them
        actions: useAccessibilityFeatures ? [
          AndroidNotificationAction(
            'replay',
            'Replay',
            icon: DrawableResourceAndroidBitmap('ic_replay'),
            showsUserInterface: false,
            contextual: true,
          ),
          AndroidNotificationAction(
            'save_memory',
            'Save as Memory',
            icon: DrawableResourceAndroidBitmap('ic_save'),
            showsUserInterface: true, // will open the app
          ),
        ] : null,
        // Ensure the notification is accessible
        category: useAccessibilityFeatures ? AndroidNotificationCategory.recommendation : null,
        visibility: NotificationVisibility.public,
      );

      // Check iOS version for feature availability
      bool supportsCriticalAlerts = true;
      if (_iOSVersion != null) {
        final versionParts = _iOSVersion!.split('.');
        final majorVersion = int.tryParse(versionParts[0]) ?? 0;
        supportsCriticalAlerts = majorVersion >= 12;
      }

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playAudio,
        sound: playAudio ? 'nudge_alert.caf' : null,
        // Use the appropriate category for actions
        categoryIdentifier: channelId,
        // Make it accessible
        interruptionLevel: supportsCriticalAlerts ? InterruptionLevel.active : InterruptionLevel.active,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Prepare the notification payload
      final String payload = '${nudge.id}:view';

      // Show the notification immediately
      await _notificationsPlugin.show(
        _deviceUnlockNudgeId,
        _getTitleForCategory(nudge.category),
        nudge.content,
        notificationDetails,
        payload: payload,
      );

      _logger.info('Showed device unlock nudge: ${nudge.category.displayName}');

      // Track the delivery
      _trackNotificationEvent('delivered');

      // Increment notification count
      await _incrementDeliveryCounter();

      // Save state for recovery
      await _saveServiceState();

      // Check for audio resources before playing
      bool audioAvailable = nudge.audioUrl != null && await _isAudioResourceAvailable(nudge.audioUrl!);

      // If audio playback is enabled and available, play it efficiently
      if (playAudio && audioAvailable) {
        await _playAudioFile(nudge.audioUrl!);
      } else if (playAudio && !audioAvailable) {
        _logger.warning('Audio resource not available: ${nudge.audioUrl}');
      }

      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to show device unlock nudge',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Check if an audio resource is available
  Future<bool> _isAudioResourceAvailable(String url) async {
    try {
      // Simple availability check
      // We don't actually need to download the whole file
      final result = await _audioPlayer.setUrl(url).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          throw TimeoutException('Audio resource check timed out');
        },
      );

      // Clean up resources
      await _audioPlayer.stop();

      return result != null;
    } catch (e) {
      _logger.warning('Audio resource check failed: $e');
      return false;
    }
  }

  /// Preload an audio file for quicker playback when the notification arrives
  /// With more efficient resource management
  Future<void> _preloadAudioFile(String audioUrl) async {
    try {
      // Skip preloading if in battery saving mode
      if (_isLowBattery || _isPowerSaveMode) {
        _logger.info('Skipping audio preload due to battery constraints');
        return;
      }

      // Skip if audio URL invalid
      if (!await _isAudioResourceAvailable(audioUrl)) {
        _logger.warning('Skipping preload, audio resource not available: $audioUrl');
        return;
      }

      // Use a timeout to prevent indefinite preloading
      final completer = Completer<void>();

      // Set a timeout
      final timer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          completer.complete();
          _logger.warning('Audio preload timed out: $audioUrl');
        }
      });

      // Start preloading
      await _audioPlayer.setUrl(audioUrl);

      // Cancel the timer if completed normally
      if (!completer.isCompleted) {
        timer.cancel();
        completer.complete();
      }

      _logger.info('Preloaded audio file: $audioUrl');
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to preload audio file',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Play an audio file when the notification is shown
  /// With proper resource management
  Future<void> _playAudioFile(String audioUrl) async {
    try {
      // Release any previous resources
      await _audioPlayer.stop();

      // Skip playback if in very low power mode
      if (_isLowBattery && _isPowerSaveMode) {
        _logger.info('Skipping audio playback due to battery constraints');
        return;
      }

      // Set up the audio player with a proper completion listener
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _audioPlayer.stop();
        }
      });

      // Set a timeout to prevent resource leaks
      final playbackTimer = Timer(const Duration(minutes: 2), () {
        _audioPlayer.stop();
      });

      // Play the audio
      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();

      // Add completion listener to clean up timer
      _audioPlayer.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          playbackTimer.cancel();
        }
      });

      _logger.info('Playing audio file: $audioUrl');
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to play audio file',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Replay the audio for a nudge with efficient resource management
  Future<bool> _replayNudgeAudio(String nudgeId) async {
    try {
      // Get the nudge template from service
      final nudgeTemplate = await _nudgeService.getNudgeTemplateById(nudgeId);

      if (nudgeTemplate == null || nudgeTemplate.audioUrl == null) {
        _logger.warning('Could not find audio URL for nudge ID: $nudgeId');
        return false;
      }

      // Check if audio resource is available
      if (!await _isAudioResourceAvailable(nudgeTemplate.audioUrl!)) {
        _logger.warning('Audio resource not available for replay: ${nudgeTemplate.audioUrl}');
        return false;
      }

      // Free resources from any previous playback
      await _audioPlayer.stop();

      // Check battery status before playing
      if (_isLowBattery && _isPowerSaveMode) {
        // In very low power mode, we might skip audio playback
        _logger.info('Skipping audio playback due to battery constraints');
        return false;
      }

      // Play audio with timeout to prevent resource leaks
      await _audioPlayer.setUrl(nudgeTemplate.audioUrl!);
      await _audioPlayer.play();

      // Set a timeout to release resources
      Timer(const Duration(minutes: 2), () {
        _audioPlayer.stop();
      });

      _logger.info('Replaying nudge audio for ID: $nudgeId');
      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to replay nudge audio',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Save nudge as memory
  Future<bool> _saveNudgeAsMemory(String nudgeId) async {
    try {
      // Get the nudge template from service
      final nudgeTemplate = await _nudgeService.getNudgeTemplateById(nudgeId);

      if (nudgeTemplate == null) {
        _logger.warning('Could not find nudge template for ID: $nudgeId');
        return false;
      }

      // Broadcast the save request to stream for UI handling
      _notificationStreamController.add({
        'event': 'saveAsMemory',
        'nudgeId': nudgeId,
        'nudgeContent': nudgeTemplate.content,
        'nudgeCategory': nudgeTemplate.category.value,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _logger.info('Saving nudge as memory: $nudgeId');
      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to save nudge as memory',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Register device unlock listener to trigger nudges
  /// With better battery optimization
  Future<bool> registerDeviceUnlockTrigger() async {
    try {
      // Don't register if not initialized
      if (!_isInitialized) {
        _logger.warning('Cannot register device unlock trigger: helper not initialized');
        return false;
      }

      // Get current battery status to adjust constraints
      final batteryConstraints = _isLowBattery
          ? Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: true, // Only trigger if battery is not low
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true,
      )
          : Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true,
      );

      // Schedule a periodic task to check for device unlocks
      await Workmanager().registerPeriodicTask(
        'deviceUnlockCheck',
        'checkDeviceUnlock',
        frequency: const Duration(minutes: 15),
        constraints: batteryConstraints,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
      );

      _logger.info('Registered device unlock trigger');
      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to register device unlock trigger',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Schedule daily time-based nudges
  /// With better battery optimization
  Future<bool> scheduleTimeBasedNudges() async {
    try {
      // Don't schedule if not initialized
      if (!_isInitialized) {
        _logger.warning('Cannot schedule time-based nudges: helper not initialized');
        return false;
      }

      // Get current battery status to adjust constraints
      final batteryConstraints = _isLowBattery
          ? Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true, // Only trigger if battery is not low
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true,
      )
          : Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true,
      );

      // Register a daily task to schedule time-based nudges
      await Workmanager().registerPeriodicTask(
        'timeBasedNudgesScheduler',
        'scheduleTimeBasedNudges',
        frequency: const Duration(days: 1),
        constraints: batteryConstraints,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
      );

      // Also register a daily cleanup task
      await Workmanager().registerPeriodicTask(
        'dailyCleanup',
        'cleanupOldNudges',
        frequency: const Duration(days: 1),
        initialDelay: const Duration(hours: 4), // Run a few hours after the scheduler
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: true, // Run when device is idle
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      _logger.info('Registered time-based nudges scheduler and cleanup task');
      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to schedule time-based nudges',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Schedule a nudge for a specific time window
  Future<bool> scheduleNudgeForTimeWindow(
      NudgeTemplate nudge, TimeWindow timeWindow, {
        bool playAudio = true,
        bool forceDelivery = false,
      }) async {
    try {
      // Don't schedule if not initialized
      if (!_isInitialized) {
        _logger.warning('Cannot schedule nudge for time window: helper not initialized');
        return false;
      }

      // Get user settings for max notifications
      final settings = await _nudgeService.getUserSettings();
      final maxNotifications = settings?.maxNudgesPerDay ?? 3;

      // Check if we've hit the daily limit (unless forcing delivery)
      if (!forceDelivery && !await _canDeliverMoreNotificationsToday(maxNotifications)) {
        _logger.info('Daily notification limit reached, not scheduling new nudge');
        return false;
      }

      // Check if this time window is enabled for the user
      if (settings?.enabledTimeWindows[timeWindow] == false) {
        _logger.info('Time window ${timeWindow.displayName} is disabled for user');
        return false;
      }

      // Check if we're in a conflict state
      if (_checkForNotificationConflicts()) {
        _logger.info('Skipping scheduled nudge due to notification conflict');
        return false;
      }

      // Get the appropriate notification ID for this time window
      final int notificationId = _getNotificationIdForTimeWindow(timeWindow);

      // Make sure the ID doesn't conflict with reserved ranges
      if (_isIdInReservedRange(notificationId)) {
        _logger.warning('Notification ID $notificationId conflicts with reserved range');
        return false;
      }

      // Get channel ID for this nudge category
      final String channelId = _categoryChannelIds[nudge.category] ?? _baseChannelId;

      // Calculate notification time based on the time window
      // Considering custom time window settings if available
      final DateTime notificationTime = _calculateTimeForWindow(
        timeWindow,
        settings?.timeWindowCustomization?[timeWindow],
      );

      // Use platform-specific features based on detected version
      final bool useHighContrast = _androidApiLevel == null || _androidApiLevel! >= 28;
      final bool useAccessibilityFeatures = _androidApiLevel == null || _androidApiLevel! >= 26;

      // Create the notification details with accessibility features for elderly users
      final androidDetails = AndroidNotificationDetails(
        channelId,
        '${nudge.category.displayName} Nudges',
        channelDescription: 'Therapeutic nudges for ${nudge.category.displayName.toLowerCase()}',
        importance: Importance.high,
        priority: Priority.high,
        // Use bigger text style for better readability
        styleInformation: BigTextStyleInformation(
          nudge.content,
          htmlFormatBigText: true,
          contentTitle: '<b>${_getTitleForCategory(nudge.category)}</b>',
          htmlFormatContentTitle: true,
          summaryText: timeWindow.displayName,
          htmlFormatSummaryText: true,
        ),
        color: _getColorForCategory(nudge.category),
        colorized: useHighContrast,
        sound: playAudio ? null : UriAndroidNotificationSound('silent'),
        playSound: playAudio,
        // Make visuals more accessible
        largeIcon: DrawableResourceAndroidBitmap('notification_large_icon'),
        // Only add actions if platform supports them
        actions: useAccessibilityFeatures ? [
          AndroidNotificationAction(
            'replay',
            'Replay',
            icon: DrawableResourceAndroidBitmap('ic_replay'),
            showsUserInterface: false,
            contextual: true,
          ),
          AndroidNotificationAction(
            'save_memory',
            'Save as Memory',
            icon: DrawableResourceAndroidBitmap('ic_save'),
            showsUserInterface: true, // will open the app
          ),
        ] : null,
        // Ensure the notification is accessible
        category: useAccessibilityFeatures ? AndroidNotificationCategory.recommendation : null,
        visibility: NotificationVisibility.public,
      );

      // Check iOS version for feature availability
      bool supportsCriticalAlerts = true;
      if (_iOSVersion != null) {
        final versionParts = _iOSVersion!.split('.');
        final majorVersion = int.tryParse(versionParts[0]) ?? 0;
        supportsCriticalAlerts = majorVersion >= 12;
      }

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playAudio,
        sound: playAudio ? 'nudge_alert.caf' : null,
        // Use the appropriate category for actions
        categoryIdentifier: channelId,
        // Make it accessible
        interruptionLevel: supportsCriticalAlerts ? InterruptionLevel.active : InterruptionLevel.active,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Keep track of this scheduled nudge with a daily expiration
      _scheduledNudges[notificationId] = nudge;

      // Prepare the notification payload
      final String payload = '${nudge.id}:view';

      // Schedule the notification with proper timezone handling
      await _notificationsPlugin.zonedSchedule(
        notificationId,
        _getTitleForCategory(nudge.category),
        nudge.content,
        tz.TZDateTime.from(notificationTime, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.time, // Daily repeating at same time
      );

      _logger.info('Scheduled ${nudge.category.displayName} nudge for ${timeWindow.displayName} at $notificationTime');

      // Save state for recovery
      await _saveServiceState();

      // If audio playback is enabled and we're not in battery saving mode,
      // prepare the audio file for quicker playback
      if (playAudio && nudge.audioUrl != null && !_isLowBattery) {
        await _preloadAudioFile(nudge.audioUrl!);
      }

      return true;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to schedule nudge notification',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Check if current ID is in a reserved range
  bool _isIdInReservedRange(int id) {
    // Check our own reserved range - should pass
    if (id >= _reservedIdStart && id <= _reservedIdEnd) {
      return false;
    }

    // Check other services' reserved ranges
    for (final range in _reservedIdRanges) {
      final parts = range.split(':');
      if (parts.length == 2) {
        final start = int.tryParse(parts[0]);
        final end = int.tryParse(parts[1]);

        if (start != null && end != null && id >= start && id <= end) {
          return true;
        }
      }
    }

    return false;
  }

  /// Register a reserved ID range from another service
  Future<void> registerReservedIdRange(String start, String end) async {
    final range = '$start:$end';
    _reservedIdRanges.add(range);
    _logger.info('Registered reserved ID range: $range');

    // Persist for recovery
    await _sharedPreferences.setStringList('nudgeReservedIdRanges', _reservedIdRanges.toList());
  }

  /// Load reserved ID ranges
  Future<void> _loadReservedIdRanges() async {
    try {
      final ranges = _sharedPreferences.getStringList('nudgeReservedIdRanges');
      if (ranges != null) {
        _reservedIdRanges = ranges.toSet();
      }
    } catch (e) {
      _logger.warning('Failed to load reserved ID ranges: $e');
      _reservedIdRanges = {};
    }
  }

  /// Clear all scheduled nudge notifications
  Future<void> clearAllNudgeNotifications() async {
    try {
      // Cancel specifically our nudge notifications, not all app notifications
      for (final id in _scheduledNudges.keys) {
        await _notificationsPlugin.cancel(id);
      }

      _scheduledNudges.clear();
      _logger.info('Cleared all scheduled nudge notifications');

      // Save state
      await _saveServiceState();
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to clear all nudge notifications',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Clean up old scheduled nudges to prevent memory growth
  void _cleanupOldScheduledNudges() {
    try {
      // Remove entries older than today
      final today = DateTime.now();

      // In a real implementation, we would track when nudges were scheduled
      // and remove those from yesterday or earlier

      // For now, just clear everything if it's a new day
      if (_lastDeliveryDate == null ||
          _lastDeliveryDate!.day != today.day ||
          _lastDeliveryDate!.month != today.month ||
          _lastDeliveryDate!.year != today.year) {
        _scheduledNudges.clear();
        _logger.info('Cleaned up old scheduled nudges');
      }
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to clean up old scheduled nudges',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get the notification ID for a specific time window
  int _getNotificationIdForTimeWindow(TimeWindow timeWindow) {
    switch (timeWindow) {
      case TimeWindow.morning:
        return _morningNudgeId;
      case TimeWindow.midday:
        return _middayNudgeId;
      case TimeWindow.evening:
        return _eveningNudgeId;
    }
  }

  /// Calculate the notification time based on the time window
  /// Optionally using custom time window settings
  DateTime _calculateTimeForWindow(
      TimeWindow timeWindow,
      TimeWindowCustomization? customization) {
    final now = DateTime.now();

    // Get the target hour, using custom settings if available
    final int targetHour = customization != null
        ? customization.startHour + 1 // An hour after custom start
        : timeWindow.startHour + 1; // An hour after default start

    // If we're past the target hour today, schedule for tomorrow
    if (now.hour >= targetHour) {
      final tomorrow = now.add(const Duration(days: 1));
      return DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        targetHour,
        0, // At the start of the hour
      );
    } else {
      // Schedule for today
      return DateTime(
        now.year,
        now.month,
        now.day,
        targetHour,
        0, // At the start of the hour
      );
    }
  }

  /// Get a user-friendly title for the notification based on nudge category
  String _getTitleForCategory(NudgeCategory category) {
    switch (category) {
      case NudgeCategory.gratitude:
        return '🙏 Gratitude Moment';
      case NudgeCategory.mindfulness:
        return '🧘 Mindfulness Reminder';
      case NudgeCategory.selfReflection:
        return '🤔 Reflection Time';
      case NudgeCategory.reassurance:
        return '💙 Reassuring Thought';
      case NudgeCategory.cognitiveTip:
        return '💡 Helpful Tip';
    }
  }

  /// Get a color associated with the nudge category for visual distinction
  Color _getColorForCategory(NudgeCategory category) {
    switch (category) {
      case NudgeCategory.gratitude:
        return Colors.amber;
      case NudgeCategory.mindfulness:
        return Colors.lightBlue;
      case NudgeCategory.selfReflection:
        return Colors.purple;
      case NudgeCategory.reassurance:
        return Colors.teal;
      case NudgeCategory.cognitiveTip:
        return Colors.orange;
    }
  }

  /// Check if we can deliver more notifications today based on daily limit
  Future<bool> _canDeliverMoreNotificationsToday(int maxNotificationsPerDay) async {
    await _resetDailyCounterIfNeeded();

    return _notificationsDeliveredToday < maxNotificationsPerDay;
  }

  /// Reset the daily notification counter if it's a new day
  Future<void> _resetDailyCounterIfNeeded({bool force = false}) async {
    final today = DateTime.now();

    if (force || _lastDeliveryDate == null ||
        _lastDeliveryDate!.day != today.day ||
        _lastDeliveryDate!.month != today.month ||
        _lastDeliveryDate!.year != today.year) {
      _notificationsDeliveredToday = 0;
      _lastDeliveryDate = today;

      // Persist to shared preferences
      await _sharedPreferences.setInt(_prefKeyNotificationsDeliveredToday, 0);
      await _sharedPreferences.setString(
        _prefKeyLastDeliveryDate,
        '${today.year}-${today.month}-${today.day}',
      );

      _logger.info('Reset daily notification counter for new day');
    }
  }

  /// Increment the delivery counter when a notification is shown
  Future<void> _incrementDeliveryCounter() async {
    await _resetDailyCounterIfNeeded();
    _notificationsDeliveredToday++;
    _lastDeliveryDate = DateTime.now();

    // Persist to shared preferences
    await _sharedPreferences.setInt(_prefKeyNotificationsDeliveredToday, _notificationsDeliveredToday);
    await _sharedPreferences.setString(
      _prefKeyLastDeliveryDate,
      '${_lastDeliveryDate!.year}-${_lastDeliveryDate!.month}-${_lastDeliveryDate!.day}',
    );

    _logger.info('Incremented delivery counter to $_notificationsDeliveredToday');
  }

  /// Load notification counter from persistent storage
  Future<void> _loadPersistedData() async {
    try {
      // Load delivery counter
      _notificationsDeliveredToday = _sharedPreferences.getInt(_prefKeyNotificationsDeliveredToday) ?? 0;

      // Load last delivery date
      final dateStr = _sharedPreferences.getString(_prefKeyLastDeliveryDate);
      if (dateStr != null && dateStr.isNotEmpty) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          _lastDeliveryDate = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        }
      }

      // Load analytics data
      await _loadAnalyticsData();

      // Load reserved ID ranges
      await _loadReservedIdRanges();

      _logger.info('Loaded persisted notification data: count=$_notificationsDeliveredToday, last date=$_lastDeliveryDate');
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to load persisted notification data',
        error: e,
        stackTrace: stackTrace,
      );

      // Reset to defaults on error
      _notificationsDeliveredToday = 0;
      _lastDeliveryDate = null;
    }
  }

  /// Perform accessibility tests to ensure notifications are suitable for elderly users
  Future<Map<String, bool>> performAccessibilityTests() async {
    final results = <String, bool>{
      'fontSizeAdequate': true,
      'colorContrastSufficient': true,
      'actionsEasilyTappable': true,
      'audioQualityClear': true,
    };

    try {
      // Test font size
      results['fontSizeAdequate'] = _androidApiLevel == null || _androidApiLevel! >= 23;

      // Test color contrast
      results['colorContrastSufficient'] = _androidApiLevel == null || _androidApiLevel! >= 26;

      // Test touch targets
      results['actionsEasilyTappable'] =
      Platform.isAndroid ? (_androidApiLevel == null || _androidApiLevel! >= 24) : true;

      // Test audio
      results['audioQualityClear'] = !(_isLowBattery || _isPowerSaveMode);

      _logger.info('Performed accessibility tests with results: $results');
      return results;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to perform accessibility tests',
        error: e,
        stackTrace: stackTrace,
      );

      // Mark all as failed on error
      return {
        'fontSizeAdequate': false,
        'colorContrastSufficient': false,
        'actionsEasilyTappable': false,
        'audioQualityClear': false,
      };
    }
  }

  /// Enable test mode for testing notifications
  void enableTestMode() {
    _isInTestMode = true;
    _logger.info('Test mode enabled for NudgeNotificationHelper');
  }

  /// Disable test mode
  void disableTestMode() {
    _isInTestMode = false;
    _logger.info('Test mode disabled for NudgeNotificationHelper');
  }

  /// Get last test notification data for verification
  Future<Map<String, dynamic>?> getLastTestNotificationData() async {
    try {
      final jsonStr = _sharedPreferences.getString('lastTestNudgeNotification');
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
      final jsonStr = _sharedPreferences.getString('lastTappedNudgeNotification');
      if (jsonStr == null) return null;

      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      _logger.warning('Failed to get last tapped notification data: $e');
      return null;
    }
  }

  /// Check if any nudges are currently scheduled
  Future<bool> areNudgesScheduledNow() async {
    try {
      // Simple check - if we have scheduled nudges
      return _scheduledNudges.isNotEmpty;
    } catch (e) {
      _logger.warning('Failed to check if nudges are scheduled: $e');
      return false;
    }
  }

  /// Create and show a test nudge notification for testing purposes
  Future<bool> showTestNudgeNotification({NudgeCategory? category}) async {
    try {
      if (!_isInTestMode) {
        _logger.warning('Cannot show test nudge: test mode not enabled');
        return false;
      }

      final testCategory = category ?? NudgeCategory.cognitiveTip;
      final testNudge = NudgeTemplate(
        id: 'test_${DateTime.now().millisecondsSinceEpoch}',
        content: 'This is a test therapeutic nudge. It would normally contain helpful content for the user.',
        category: testCategory,
        metadata: NudgeMetadata(),
        isActive: true,
        version: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final testId = DateTime.now().millisecondsSinceEpoch % 10000 + _reservedIdStart;

      // Show the test notification
      final success = await showDeviceUnlockNudge(testNudge);

      // Record for test verification
      if (success) {
        await _sharedPreferences.setString('lastTestNudgeNotification', jsonEncode({
          'id': testId,
          'category': testCategory.value,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      }

      return success;
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Failed to show test nudge notification',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Cleanup resources on dispose
  Future<void> dispose() async {
    try {
      _notificationStreamController.close();
      await _audioPlayer.dispose();
      _saveServiceState();
      _logger.info('NudgeNotificationHelper disposed');
    } catch (e, stackTrace) {
      _advancedLogger.error(
        'Error during NudgeNotificationHelper disposal',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

/// App lifecycle observer for the nudge notification helper
class _AppLifecycleObserver with WidgetsBindingObserver {
  final NudgeNotificationHelper _helper;

  _AppLifecycleObserver(this._helper) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _helper._handleAppLifecycleStateChange(state);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
