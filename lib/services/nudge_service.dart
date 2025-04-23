// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// Version: 1.0.2
// Last Modified: 2025-04-21
// Change History:
// - 1.0.0: Initial implementation
// - 1.0.1: Added offline support and background execution improvements
// - 1.0.2: Enhanced security, error handling, and performance optimizations

import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:retry/retry.dart';

import '../models/nudge_model.dart';
import '../utils/advanced_logger.dart';
import '../utils/logger.dart';
import '../utils/config.dart';
import '../utils/analytics_service.dart';
import './openai_service.dart';
import './auth_service.dart';

/// Service responsible for managing therapeutic nudges in the Milo app.
///
/// This service handles:
/// - Nudge scheduling and delivery based on time windows
/// - Audio generation and playback
/// - User feedback collection and analytics
/// - Nudge history management
/// - Integration with Firebase services
/// - Secure storage and encryption of sensitive content
/// - Offline functionality
///
/// Design decisions:
/// - Singleton pattern ensures centralized management of nudges
/// - Cache-first approach for performance and offline support
/// - Separation of concerns between delivery, playback, and feedback
/// - Background execution constraints handled via periodic sync
///
/// The service uses a singleton pattern to ensure only one instance exists
/// throughout the application's lifecycle.
///
/// Example usage:
/// ```dart
/// // Initialize the service
/// await NudgeService().initialize();
///
/// // Check if a nudge can be delivered
/// final canDeliver = await NudgeService().canDeliverNudgeNow();
///
/// // Deliver a nudge
/// if (canDeliver) {
///   final nudge = await NudgeService().deliverNudgeNow();
/// }
///
/// // Play a nudge
/// await NudgeService().playNudge(nudgeDelivery);
/// ```
class NudgeService {
  // ======== SINGLETON INSTANCE ========
  static final NudgeService _instance = NudgeService._internal();

  /// Factory constructor that returns the singleton instance
  factory NudgeService() => _instance;

  /// Private constructor for singleton implementation
  NudgeService._internal();

  // ======== DEPENDENCIES ========
  /// Firestore database instance for data storage
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Firebase Authentication instance for user management
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Firebase Storage instance for audio file storage
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Audio player for nudge playback
  final AudioPlayer _audioPlayer = AudioPlayer();

  /// OpenAI service for TTS (Text-to-Speech) generation
  late OpenAIService _openAIService;

  /// Auth service for token validation and refresh
  late AuthService _authService;

  /// Notification plugin for displaying local notifications
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  /// Secure storage for sensitive data
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlockAfterFirstUnlock,
    ),
  );

  /// Encryption key for local data
  encrypt.Key? _encryptionKey;

  /// Connectivity service to monitor network status
  final Connectivity _connectivity = Connectivity();

  // ======== STATE MANAGEMENT ========
  /// Stream controller for broadcasting nudge events
  final _nudgeStreamController = StreamController<NudgeDelivery>.broadcast();

  /// Stream of nudge delivery events
  Stream<NudgeDelivery> get nudgeStream => _nudgeStreamController.stream;

  /// Cached user settings
  NudgeSettings? _userSettings;

  /// Cache expiration timestamp for user settings
  DateTime? _userSettingsCacheExpires;

  /// Cache of nudge templates by category
  final Map<NudgeCategory, List<NudgeTemplate>> _templateCache = {};

  /// Cache expiration timestamp for templates
  DateTime? _templateCacheExpires;

  /// Currently playing nudge ID
  String? _currentlyPlayingNudgeId;

  /// Flag to track initialization status
  bool _isInitialized = false;

  /// Flag to track audio session initialization
  bool _isAudioSessionInitialized = false;

  /// Flag to track offline status
  bool _isOffline = false;

  /// Retry configuration for network operations
  final RetryOptions _retryOptions = const RetryOptions(
    maxAttempts: 3,
    delayFactor: Duration(seconds: 1),
    maxDelay: Duration(seconds: 5),
  );

  /// Pending operations queue for offline mode
  final List<Map<String, dynamic>> _pendingOperations = [];

  /// Subscription for connectivity changes
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  /// App state subscription
  StreamSubscription<AppLifecycleState>? _appLifecycleSubscription;

  /// Authentication state subscription
  StreamSubscription<User?>? _authStateSubscription;

  // ======== TIME WINDOW DEFINITIONS ========
  /// Start times for each time window
  final Map<TimeWindow, TimeOfDay> _timeWindowStartTimes = {
    TimeWindow.morning: const TimeOfDay(hour: 7, minute: 0),
    TimeWindow.noon: const TimeOfDay(hour: 12, minute: 0),
    TimeWindow.evening: const TimeOfDay(hour: 18, minute: 0),
  };

  /// End times for each time window
  final Map<TimeWindow, TimeOfDay> _timeWindowEndTimes = {
    TimeWindow.morning: const TimeOfDay(hour: 9, minute: 0),
    TimeWindow.noon: const TimeOfDay(hour: 14, minute: 0),
    TimeWindow.evening: const TimeOfDay(hour: 20, minute: 0),
  };

  // ======== USER ACCESS ========
  /// Current authenticated user
  User? get _currentUser => _auth.currentUser;

  /// Check if user is authenticated
  bool get isUserAuthenticated => _currentUser != null;

  /// Check if service is properly initialized
  bool get isInitialized => _isInitialized;

  /// Check if device is in offline mode
  bool get isOffline => _isOffline;

  // ======== INITIALIZATION ========
  /// Initialize the nudge service with required dependencies
  ///
  /// This method sets up:
  /// - OpenAI service for TTS
  /// - Auth service for token management
  /// - Secure storage and encryption
  /// - Notifications for nudge delivery
  /// - User settings
  /// - Audio player listeners
  /// - Connectivity monitoring
  /// - Offline support
  ///
  /// [openAIService] Optional OpenAI service instance. If not provided,
  /// a new instance will be created using the API key from app config.
  /// [authService] Optional Auth service instance. If not provided,
  /// a new instance will be created.
  ///
  /// Throws [StateError] if initialization fails.
  Future<void> initialize({
    OpenAIService? openAIService,
    AuthService? authService,
  }) async {
    if (_isInitialized) {
      AdvancedLogger.log('NudgeService', 'Service already initialized');
      return;
    }

    try {
      AdvancedLogger.log('NudgeService', 'Initializing nudge service');

      // Initialize services
      _openAIService = openAIService ?? OpenAIService(apiKey: AppConfig().openAIApiKey ?? '');
      _authService = authService ?? AuthService();

      // Set up encryption
      await _setupEncryption();

      // Check connectivity status
      await _checkConnectivity();

      // Initialize audio session
      await _initializeAudioSession();

      // Initialize notifications
      await _initializeNotifications();

      // Load user settings
      await loadUserSettings(forceRefresh: false);

      // Initialize audio player
      _setupAudioPlayer();

      // Set up authentication state monitoring
      _setupAuthStateMonitoring();

      // Set up connectivity monitoring
      _setupConnectivityMonitoring();

      // Set up app lifecycle monitoring
      _setupAppLifecycleMonitoring();

      // Process any pending operations
      if (!_isOffline) {
        await _processPendingOperations();
      }

      _isInitialized = true;
      AnalyticsService.logEvent('nudge_service_initialized');
      AdvancedLogger.log('NudgeService', 'Nudge service initialized successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error initializing nudge service: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to initialize: $e');

      // Track initialization failure
      AnalyticsService.logError('nudge_service_init_failed', e.toString());

      throw StateError('We couldn\'t set up your reminders. Please try again later.');
    }
  }

  /// Set up encryption for secure storage
  ///
  /// Generates or retrieves an encryption key for local data security
  Future<void> _setupEncryption() async {
    try {
      AdvancedLogger.log('NudgeService', 'Setting up encryption');

      // Check if we already have an encryption key
      String? keyString = await _secureStorage.read(key: 'nudge_encryption_key');

      if (keyString == null) {
        // Generate a new encryption key if none exists
        final keyGen = encrypt.Key.fromSecureRandom(32);
        keyString = base64Encode(keyGen.bytes);

        // Store the encryption key securely
        await _secureStorage.write(key: 'nudge_encryption_key', value: keyString);
      }

      // Convert key string back to Key object
      _encryptionKey = encrypt.Key(base64Decode(keyString));

      AdvancedLogger.log('NudgeService', 'Encryption setup complete');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error setting up encryption: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to setup encryption: $e');

      // Continue without encryption as fallback
      AdvancedLogger.log('NudgeService', 'Continuing without encryption');
    }
  }

  /// Initialize audio session for proper background audio handling
  Future<void> _initializeAudioSession() async {
    try {
      AdvancedLogger.log('NudgeService', 'Initializing audio session');

      final session = await AudioSession.instance;
      final configuration = const AudioSessionConfiguration.speech()
          .copyWith(
        androidWillPauseWhenDucked: true,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.assistanceAccessibility,
        ),
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
      );

      await session.configure(configuration);

      // Handle interruptions
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          // Audio session was interrupted
          if (_audioPlayer.playing) {
            _audioPlayer.pause();
          }
        } else {
          // Interruption ended - optionally resume
          switch (event.type) {
            case AudioInterruptionType.duck:
            // Lower volume during temporary interruption
              _audioPlayer.setVolume(0.3);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
            // Stay paused
              break;
          }
        }
      });

      _isAudioSessionInitialized = true;
      AdvancedLogger.log('NudgeService', 'Audio session initialized successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error initializing audio session: $e\n$stackTrace',
      );
      Logger.warning('NudgeService', 'Audio session initialization failed: $e');
      // We can continue without proper audio session, but with reduced functionality
    }
  }

  /// Initialize notifications for nudge delivery
  ///
  /// Sets up notification channels and permissions.
  Future<void> _initializeNotifications() async {
    try {
      AdvancedLogger.log('NudgeService', 'Initializing notifications for nudges');

      // Android notification settings
      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS notification settings
      const DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // Combined settings
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialize with tap handler
      final initialized = await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (!initialized) {
        throw StateError('Notification plugin failed to initialize');
      }

      // Request notification permissions
      if (Platform.isIOS) {
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      } else if (Platform.isAndroid) {
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestPermission();
      }

      // Create notification channels for Android
      if (Platform.isAndroid) {
        await _createNotificationChannels();
      }

      AdvancedLogger.log('NudgeService', 'Notifications initialized successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error initializing notifications: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to initialize notifications: $e');
      // Continue without notifications as a fallback
    }
  }

  /// Create notification channels for Android
  ///
  /// Creates separate channels for:
  /// - Immediate nudges (high priority)
  /// - Scheduled nudges (normal priority)
  Future<void> _createNotificationChannels() async {
    try {
      // Channel for immediate nudges (therapeutic content)
      const AndroidNotificationChannel nudgeChannel = AndroidNotificationChannel(
        'nudge_channel',
        'Therapeutic Nudges',
        description: 'Timely therapeutic nudges from Milo',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      // Channel for scheduled nudges (reminders)
      const AndroidNotificationChannel scheduleChannel = AndroidNotificationChannel(
        'nudge_schedule_channel',
        'Scheduled Nudges',
        description: 'Scheduled therapeutic nudges from Milo',
        importance: Importance.high,
        enableLights: true,
        ledColor: Color(0xFF0A84FF),
      );

      // Channel for service alerts (lower priority)
      const AndroidNotificationChannel serviceChannel = AndroidNotificationChannel(
        'nudge_service_channel',
        'Milo Service Alerts',
        description: 'Important alerts about the Milo service',
        importance: Importance.low,
      );

      // Create channels
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(nudgeChannel);

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(scheduleChannel);

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(serviceChannel);

      AdvancedLogger.log('NudgeService', 'Notification channels created successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error creating notification channels: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to create notification channels: $e');
    }
  }

  /// Set up audio player configuration and event listeners
  void _setupAudioPlayer() {
    try {
      AdvancedLogger.log('NudgeService', 'Setting up audio player');

      // Configure audio player
      _audioPlayer.setLoopMode(LoopMode.off);

      // Set up automatic error recovery
      _audioPlayer.setAutomaticallyWaitsToMinimizeStalling(true);

      // Add player state listener
      _audioPlayer.playerStateStream.listen(_handlePlayerStateChange);

      // Add error listener
      _audioPlayer.playbackEventStream.listen(
            (event) {
          // Track playback progress for analytics
          if (_currentlyPlayingNudgeId != null &&
              event.processingState == ProcessingState.ready) {
            final position = event.position;
            final duration = event.duration;

            if (duration != null && position.inMilliseconds > 0) {
              final progress = position.inMilliseconds / duration.inMilliseconds;
              if (progress >= 0.9) {
                // Track completion for analytics
                AnalyticsService.logEvent(
                  'nudge_playback_completed',
                  parameters: {'nudge_id': _currentlyPlayingNudgeId!},
                );
              }
            }
          }
        },
        onError: (Object e, StackTrace stackTrace) {
          AdvancedLogger.logError(
            'NudgeService',
            'Audio player error: $e\n$stackTrace',
          );
          _handlePlaybackError(e);
        },
      );

      AdvancedLogger.log('NudgeService', 'Audio player setup complete');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error setting up audio player: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to set up audio player: $e');
    }
  }

  /// Set up authentication state monitoring
  void _setupAuthStateMonitoring() {
    try {
      AdvancedLogger.log('NudgeService', 'Setting up auth state monitoring');

      _authStateSubscription = _authService.authStateChanges.listen((User? user) {
        if (user == null) {
          // User signed out, clear sensitive data
          AdvancedLogger.log('NudgeService', 'User signed out, clearing sensitive data');
          _clearUserData();
        } else if (_currentUser?.uid != user.uid) {
          // User changed, reload settings
          AdvancedLogger.log('NudgeService', 'User changed, reloading settings');
          loadUserSettings(forceRefresh: true);
        }
      });

      AdvancedLogger.log('NudgeService', 'Auth state monitoring setup complete');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error setting up auth state monitoring: $e\n$stackTrace',
      );
    }
  }

  /// Clear user data when signing out
  void _clearUserData() {
    _userSettings = null;
    _userSettingsCacheExpires = null;
    _templateCache.clear();
    _templateCacheExpires = null;
    stopPlayback();
  }

  /// Set up connectivity monitoring
  void _setupConnectivityMonitoring() {
    try {
      AdvancedLogger.log('NudgeService', 'Setting up connectivity monitoring');

      _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
        final wasOffline = _isOffline;
        _isOffline = result == ConnectivityResult.none;

        AdvancedLogger.log(
          'NudgeService',
          'Connectivity changed: ${result.toString()}, offline: $_isOffline',
        );

        // If we're coming back online, sync pending operations
        if (wasOffline && !_isOffline) {
          AdvancedLogger.log('NudgeService', 'Back online, processing pending operations');
          _processPendingOperations();
        }
      });

      AdvancedLogger.log('NudgeService', 'Connectivity monitoring setup complete');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error setting up connectivity monitoring: $e\n$stackTrace',
      );
    }
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isOffline = result == ConnectivityResult.none;
      AdvancedLogger.log('NudgeService', 'Initial connectivity status: ${result.toString()}');
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error checking connectivity: $e');
      _isOffline = false; // Assume online as default
    }
  }

  /// Set up app lifecycle monitoring
  void _setupAppLifecycleMonitoring() {
    try {
      AdvancedLogger.log('NudgeService', 'Setting up app lifecycle monitoring');

      // Subscribe to app state changes
      final binding = WidgetsBinding.instance;

      binding.addObserver(
        LifecycleEventHandler(
          resumeCallBack: () async {
            AdvancedLogger.log('NudgeService', 'App resumed');

            // Refresh connectivity status
            await _checkConnectivity();

            // Validate auth token
            if (isUserAuthenticated) {
              final isTokenValid = await _authService.validateToken();
              if (!isTokenValid) {
                AdvancedLogger.log('NudgeService', 'Auth token expired, refreshing');
                await _authService.refreshToken();
              }
            }

            // Process any pending operations
            if (!_isOffline && _pendingOperations.isNotEmpty) {
              _processPendingOperations();
            }

            // Refresh settings if cache expired
            if (_userSettingsCacheExpires != null &&
                DateTime.now().isAfter(_userSettingsCacheExpires!)) {
              loadUserSettings(forceRefresh: true);
            }

            // Re-establish audio session if needed
            if (!_isAudioSessionInitialized) {
              _initializeAudioSession();
            }
          },
          pauseCallBack: () async {
            AdvancedLogger.log('NudgeService', 'App paused');

            // Save any pending changes
            await _persistPendingOperations();
          },
        ),
      );

      AdvancedLogger.log('NudgeService', 'App lifecycle monitoring setup complete');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error setting up app lifecycle monitoring: $e\n$stackTrace',
      );
    }
  }

  /// Process operations that were pending while offline
  Future<void> _processPendingOperations() async {
    if (_pendingOperations.isEmpty) {
      return;
    }

    AdvancedLogger.log(
      'NudgeService',
      'Processing ${_pendingOperations.length} pending operations',
    );

    final operations = List<Map<String, dynamic>>.from(_pendingOperations);
    _pendingOperations.clear();

    for (final operation in operations) {
      try {
        final type = operation['type'] as String;
        final data = operation['data'] as Map<String, dynamic>;

        switch (type) {
          case 'feedback':
            await submitNudgeFeedback(
              data['nudgeId'] as String,
              data['isHelpful'] as bool,
            );
            break;
          case 'save_memory':
            await saveNudgeAsMemory(data['nudgeId'] as String);
            break;
          default:
            AdvancedLogger.log('NudgeService', 'Unknown operation type: $type');
        }
      } catch (e) {
        AdvancedLogger.logError(
          'NudgeService',
          'Error processing pending operation: $e',
        );
        // Add back to pending queue if still failing
        _pendingOperations.add(operation);
      }
    }

    // Persist any remaining operations
    if (_pendingOperations.isNotEmpty) {
      await _persistPendingOperations();
    }

    AdvancedLogger.log(
      'NudgeService',
      'Pending operations processed, ${_pendingOperations.length} remaining',
    );
  }

  /// Save pending operations to secure storage
  Future<void> _persistPendingOperations() async {
    if (_pendingOperations.isEmpty) {
      await _secureStorage.delete(key: 'nudge_pending_operations');
      return;
    }

    try {
      final jsonData = jsonEncode(_pendingOperations);
      await _secureStorage.write(
        key: 'nudge_pending_operations',
        value: jsonData,
      );

      AdvancedLogger.log(
        'NudgeService',
        'Saved ${_pendingOperations.length} pending operations',
      );
    } catch (e) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error saving pending operations: $e',
      );
    }
  }

  /// Load pending operations from secure storage
  Future<void> _loadPendingOperations() async {
    try {
      final jsonData = await _secureStorage.read(key: 'nudge_pending_operations');

      if (jsonData != null && jsonData.isNotEmpty) {
        final decoded = jsonDecode(jsonData) as List<dynamic>;
        _pendingOperations.addAll(
          decoded.map((item) => item as Map<String, dynamic>).toList(),
        );

        AdvancedLogger.log(
          'NudgeService',
          'Loaded ${_pendingOperations.length} pending operations',
        );
      }
    } catch (e) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error loading pending operations: $e',
      );
    }
  }

  // ======== EVENT HANDLERS ========
  /// Handle notification tap events
  ///
  /// When a user taps on a nudge notification, this method:
  /// 1. Extracts the nudge ID from the payload
  /// 2. Fetches the nudge details
  /// 3. Adds the nudge to the stream for UI updates
  /// 4. Plays the nudge audio
  void _onNotificationTapped(NotificationResponse response) async {
    try {
      AdvancedLogger.log('NudgeService', 'Notification tapped: ${response.payload}');

      if (response.payload != null) {
        final nudgeId = response.payload!;

        // Track notification tap for analytics
        AnalyticsService.logEvent(
          'nudge_notification_tapped',
          parameters: {'nudge_id': nudgeId},
        );

        // Validate authentication before proceeding
        if (!isUserAuthenticated) {
          Logger.warning('NudgeService', 'User not authenticated, cannot load nudge');
          _showServiceNotification(
            'Please sign in to access your nudges',
            'Authentication required',
          );
          return;
        }

        // Validate token before proceeding
        final isTokenValid = await _authService.validateToken();
        if (!isTokenValid) {
          AdvancedLogger.log('NudgeService', 'Auth token expired, refreshing');
          await _authService.refreshToken();
        }

        // Fetch nudge and play it
        NudgeDelivery? nudgeDelivery;

        // Try to get from local cache first
        nudgeDelivery = await _getCachedNudgeDelivery(nudgeId);

        // If not in cache and online, fetch from Firestore
        if (nudgeDelivery == null && !_isOffline) {
          nudgeDelivery = await getNudgeDeliveryById(nudgeId);

          // Cache the nudge if found
          if (nudgeDelivery != null) {
            await _cacheNudgeDelivery(nudgeDelivery);
          }
        }

        if (nudgeDelivery != null) {
          _nudgeStreamController.add(nudgeDelivery);
          await playNudge(nudgeDelivery);
        } else {
          Logger.warning('NudgeService', 'Tapped nudge not found: $nudgeId');
          _showServiceNotification(
            'The requested nudge could not be found',
            'Nudge not available',
          );
        }
      }
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error handling notification tap: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to handle notification tap: $e');

      // Show friendly error notification
      _showServiceNotification(
        'We couldn\'t load your nudge. Please try again later.',
        'Something went wrong',
      );
    }
  }

  /// Handle player state changes
  ///
  /// Monitors the audio player state and takes appropriate actions:
  /// - Completed: Stop the player and reset
  /// - Error: Log and handle the error
  void _handlePlayerStateChange(PlayerState state) {
    AdvancedLogger.log(
      'NudgeService',
      'Player state changed: ${state.processingState}, playing: ${state.playing}',
    );

    if (state.processingState == ProcessingState.completed) {
      AdvancedLogger.log('NudgeService', 'Nudge playback completed');

      if (_currentlyPlayingNudgeId != null) {
        AnalyticsService.logEvent(
          'nudge_playback_completed',
          parameters: {'nudge_id': _currentlyPlayingNudgeId!},
        );
      }

      _audioPlayer.stop();
      _currentlyPlayingNudgeId = null;
    } else if (state.processingState == ProcessingState.buffering) {
      // Could show a loading indicator in the UI
    }
  }

  /// Handle playback errors
  ///
  /// Provides user-friendly error handling for audio playback issues.
  /// Categorizes errors and provides appropriate recovery actions.
  void _handlePlaybackError(Object error) {
    Logger.error('NudgeService', 'Audio playback error: $error');

    String userMessage = 'Could not play audio. Please try again later.';
    String errorCategory = 'unknown';

    if (error is PlayerException) {
      // Handle specific player exceptions
      if (error.code == 'network') {
        userMessage = 'Network issue. Please check your connection and try again.';
        errorCategory = 'network';
      } else if (error.code == 'format') {
        userMessage = 'Audio format not supported. Please try a different nudge.';
        errorCategory = 'format';
      } else if (error.code == 'source') {
        userMessage = 'Could not load audio. The file may be missing or corrupted.';
        errorCategory = 'source';
      } else if (error.code == 'interrupted') {
        userMessage = 'Audio playback was interrupted by another app.';
        errorCategory = 'interrupted';
      }
    } else if (error is SocketException || error.toString().contains('connection')) {
      userMessage = 'Network issue. Please check your connection and try again.';
      errorCategory = 'network';
    } else if (error is TimeoutException) {
      userMessage = 'The audio is taking too long to load. Please try again.';
      errorCategory = 'timeout';
    } else if (error.toString().contains('permission')) {
      userMessage = 'Milo doesn\'t have permission to play audio. Please check your settings.';
      errorCategory = 'permission';
    }

    // Track error for analytics
    AnalyticsService.logError('nudge_playback_error',
      '$errorCategory: ${error.toString()}',
    );

    // Reset player state
    _audioPlayer.stop();
    _currentlyPlayingNudgeId = null;

    // Show error notification
    _showServiceNotification(
      userMessage,
      'Audio Playback Issue',
    );

    // Broadcast error message to UI
    final errorEvent = NudgeErrorEvent(
      errorType: errorCategory,
      message: userMessage,
      timestamp: DateTime.now(),
    );

    // In a real implementation, we would have a dedicated error stream
    // Here we're logging it for demonstration
    AdvancedLogger.logError('NudgeService', 'User-facing error: $userMessage');
  }

  /// Show a service notification
  ///
  /// Displays a notification for service-related messages.
  Future<void> _showServiceNotification(String message, String title) async {
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'nudge_service_channel',
        'Milo Service Alerts',
        channelDescription: 'Important alerts about the Milo service',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        title,
        message,
        notificationDetails,
      );
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error showing service notification: $e');
    }
  }

  // ======== USER SETTINGS ========
  /// Load user settings from Firestore
  ///
  /// Fetches the user's nudge preferences from Firestore and caches them.
  /// If no settings exist, creates default settings.
  ///
  /// [forceRefresh] If true, bypasses the cache and fetches fresh data.
  ///
  /// Returns [NudgeSettings] object with user preferences.
  ///
  /// Throws [StateError] if the user is not authenticated.
  Future<NudgeSettings> loadUserSettings({bool forceRefresh = false}) async {
    try {
      AdvancedLogger.log('NudgeService', 'Loading user nudge settings');

      // Check cache first unless forced refresh
      if (!forceRefresh &&
          _userSettings != null &&
          _userSettingsCacheExpires != null &&
          DateTime.now().isBefore(_userSettingsCacheExpires!)) {
        AdvancedLogger.log('NudgeService', 'Using cached user settings');
        return _userSettings!;
      }

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // If offline, try to load from secure storage
      if (_isOffline) {
        final cachedSettings = await _loadSettingsFromSecureStorage();
        if (cachedSettings != null) {
          _userSettings = cachedSettings;
          // Shorter cache expiry for offline mode
          _userSettingsCacheExpires = DateTime.now().add(const Duration(hours: 12));
          return _userSettings!;
        }

        // If no cached settings, create default settings
        AdvancedLogger.log('NudgeService', 'No cached settings found in offline mode');
      } else {
        // In online mode, load from Firestore
        final doc = await _retryOptions.retry(() async {
          return await _firestore
              .collection('users')
              .doc(_currentUser!.uid)
              .collection('settings')
              .doc('nudges')
              .get();
        }, retryIf: (e) => _shouldRetry(e));

        if (doc.exists) {
          // Validate data before parsing
          final data = doc.data()!;
          if (_validateSettingsData(data)) {
            _userSettings = NudgeSettings.fromMap(data);
            await _saveSettingsToSecureStorage(_userSettings!);
            AdvancedLogger.log(
              'NudgeService',
              'User settings loaded from Firestore',
            );
          } else {
            // Invalid data - create default settings
            AdvancedLogger.log('NudgeService', 'Invalid settings data in Firestore');
            _userSettings = _createDefaultSettings();
            await saveUserSettings(_userSettings!);
          }
        } else {
          // Create default settings
          AdvancedLogger.log('NudgeService', 'No settings found in Firestore');
          _userSettings = _createDefaultSettings();
          await saveUserSettings(_userSettings!);
        }
      }

      // Set cache expiration (24 hours)
      _userSettingsCacheExpires = DateTime.now().add(const Duration(hours: 24));

      return _userSettings!;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error loading user settings: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to load user settings: $e');

      // Return default settings in case of error for graceful degradation
      return _createDefaultSettings();
    }
  }

  /// Create default user settings
  NudgeSettings _createDefaultSettings() {
    return NudgeSettings(
      enabled: true,
      enabledTimeWindows: {
        TimeWindow.morning: true,
        TimeWindow.noon: true,
        TimeWindow.evening: true,
      },
      enabledCategories: {
        NudgeCategory.gratitude: true,
        NudgeCategory.mindfulness: true,
        NudgeCategory.selfReflection: true,
        NudgeCategory.reassurance: true,
        NudgeCategory.cognitive: true,
      },
      volume: 0.8,
      voicePreference: 'nova',
      maxDailyNudges: 3,
    );
  }

  /// Validate settings data structure
  bool _validateSettingsData(Map<String, dynamic> data) {
    try {
      // Check required fields
      if (!data.containsKey('enabled') ||
          !data.containsKey('enabledTimeWindows') ||
          !data.containsKey('enabledCategories')) {
        return false;
      }

      // Check types
      if (data['enabled'] is! bool) {
        return false;
      }

      // Additional validations as needed
      return true;
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error validating settings data: $e');
      return false;
    }
  }

  /// Load settings from secure storage
  Future<NudgeSettings?> _loadSettingsFromSecureStorage() async {
    try {
      final data = await _secureStorage.read(key: 'nudge_user_settings');
      if (data != null && data.isNotEmpty) {
        final decrypted = _decryptData(data);
        if (decrypted != null) {
          final jsonData = jsonDecode(decrypted) as Map<String, dynamic>;
          return NudgeSettings.fromMap(jsonData);
        }
      }
      return null;
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error loading settings from secure storage: $e');
      return null;
    }
  }

  /// Save settings to secure storage
  Future<void> _saveSettingsToSecureStorage(NudgeSettings settings) async {
    try {
      final jsonData = jsonEncode(settings.toMap());
      final encrypted = _encryptData(jsonData);
      if (encrypted != null) {
        await _secureStorage.write(key: 'nudge_user_settings', value: encrypted);
        AdvancedLogger.log('NudgeService', 'Settings saved to secure storage');
      }
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error saving settings to secure storage: $e');
    }
  }

  /// Encrypt data for secure storage
  String? _encryptData(String data) {
    try {
      if (_encryptionKey == null) {
        return data; // Fallback to unencrypted if no key
      }

      final encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey!));
      final iv = encrypt.IV.fromLength(16);

      final encrypted = encrypter.encrypt(data, iv: iv);
      return '${encrypted.base64}|${iv.base64}';
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error encrypting data: $e');
      return null;
    }
  }

  /// Decrypt data from secure storage
  String? _decryptData(String encryptedData) {
    try {
      if (_encryptionKey == null) {
        return encryptedData; // Assume unencrypted if no key
      }

      final parts = encryptedData.split('|');
      if (parts.length != 2) {
        return encryptedData; // Not in our encrypted format
      }

      final encrypted = encrypt.Encrypted.fromBase64(parts[0]);
      final iv = encrypt.IV.fromBase64(parts[1]);

      final encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey!));
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error decrypting data: $e');
      return null;
    }
  }

  /// Save user settings to Firestore
  ///
  /// Updates the user's nudge preferences in Firestore and updates the cache.
  ///
  /// [settings] The settings object to save.
  ///
  /// Throws [StateError] if the user is not authenticated.
  Future<void> saveUserSettings(NudgeSettings settings) async {
    try {
      AdvancedLogger.log('NudgeService', 'Saving user nudge settings');

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // Update local cache immediately
      _userSettings = settings;
      _userSettingsCacheExpires = DateTime.now().add(const Duration(hours: 24));

      // Save to secure storage for offline access
      await _saveSettingsToSecureStorage(settings);

      // If offline, queue the operation for later
      if (_isOffline) {
        AdvancedLogger.log('NudgeService', 'Device offline, settings saved locally only');

        // Settings updates are special - they don't use the pending operations queue
        // because they're immediately applied locally
        return;
      }

      // Sanitize data before saving
      final sanitizedData = _sanitizeSettingsData(settings.toMap());

      // Save to Firestore with retry logic
      await _retryOptions.retry(() async {
        await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('settings')
            .doc('nudges')
            .set(sanitizedData);
      }, retryIf: (e) => _shouldRetry(e));

      AdvancedLogger.log('NudgeService', 'User settings saved successfully');

      // Track settings change for analytics
      AnalyticsService.logEvent('nudge_settings_updated');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error saving user settings: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to save user settings: $e');
      throw StateError('Your settings couldn\'t be saved. Please try again later.');
    }
  }

  /// Sanitize settings data before saving to Firestore
  Map<String, dynamic> _sanitizeSettingsData(Map<String, dynamic> data) {
    final sanitized = Map<String, dynamic>.from(data);

    // Ensure only valid fields are included
    final validKeys = [
      'enabled',
      'enabledTimeWindows',
      'enabledCategories',
      'volume',
      'voicePreference',
      'maxDailyNudges',
    ];

    sanitized.removeWhere((key, value) => !validKeys.contains(key));

    // Additional sanitization as needed
    if (sanitized.containsKey('volume')) {
      final volume = sanitized['volume'];
      if (volume is num) {
        // Ensure volume is between 0 and 1
        sanitized['volume'] = volume.clamp(0.0, 1.0);
      }
    }

    if (sanitized.containsKey('maxDailyNudges')) {
      final maxNudges = sanitized['maxDailyNudges'];
      if (maxNudges is num) {
        // Ensure max nudges is reasonable
        sanitized['maxDailyNudges'] = maxNudges.clamp(1, 10);
      }
    }

    return sanitized;
  }

  // ======== TEMPLATE MANAGEMENT ========
  /// Get all available nudge templates
  ///
  /// Fetches all nudge templates from Firestore.
  /// Uses caching for performance and offline support.
  ///
  /// Returns a [List] of [NudgeTemplate] objects.
  Future<List<NudgeTemplate>> getAvailableNudgeTemplates() async {
    try {
      AdvancedLogger.log('NudgeService', 'Fetching available nudge templates');

      // Check if cache is valid
      if (_templateCacheExpires != null &&
          DateTime.now().isBefore(_templateCacheExpires!) &&
          _templateCache.isNotEmpty) {
        // Combine all templates from cache
        final templates = <NudgeTemplate>[];
        for (final categoryTemplates in _templateCache.values) {
          templates.addAll(categoryTemplates);
        }

        AdvancedLogger.log('NudgeService', 'Using ${templates.length} cached templates');
        return templates;
      }

      // If offline, return whatever is in cache even if expired
      if (_isOffline && _templateCache.isNotEmpty) {
        final templates = <NudgeTemplate>[];
        for (final categoryTemplates in _templateCache.values) {
          templates.addAll(categoryTemplates);
        }

        AdvancedLogger.log('NudgeService', 'Offline mode: using ${templates.length} cached templates');
        return templates;
      }

      // Otherwise, fetch from Firestore
      final querySnapshot = await _retryOptions.retry(() async {
        return await _firestore
            .collection('nudge_templates')
            .get();
      }, retryIf: (e) => _shouldRetry(e));

      final templates = <NudgeTemplate>[];

      // Clear existing cache
      _templateCache.clear();

      // Process results
      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();

          // Validate data before parsing
          if (data.containsKey('text') && data.containsKey('category')) {
            final template = NudgeTemplate.fromMap(data, doc.id);
            templates.add(template);

            // Add to category cache
            if (!_templateCache.containsKey(template.category)) {
              _templateCache[template.category] = [];
            }
            _templateCache[template.category]!.add(template);
          } else {
            AdvancedLogger.logError(
              'NudgeService',
              'Invalid template data in document ${doc.id}',
            );
          }
        } catch (e) {
          AdvancedLogger.logError(
            'NudgeService',
            'Error parsing template ${doc.id}: $e',
          );
        }
      }

      // Set cache expiration (12 hours)
      _templateCacheExpires = DateTime.now().add(const Duration(hours: 12));

      // Save templates to secure storage for offline use
      await _saveTemplatesToSecureStorage();

      AdvancedLogger.log('NudgeService', 'Fetched ${templates.length} templates');
      return templates;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error fetching templates: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to fetch nudge templates: $e');

      // Try to load from secure storage as fallback
      final cachedTemplates = await _loadTemplatesFromSecureStorage();
      if (cachedTemplates.isNotEmpty) {
        return cachedTemplates;
      }

      return [];
    }
  }

  /// Save templates to secure storage for offline use
  Future<void> _saveTemplatesToSecureStorage() async {
    try {
      if (_templateCache.isEmpty) {
        return;
      }

      final templates = <NudgeTemplate>[];
      for (final categoryTemplates in _templateCache.values) {
        templates.addAll(categoryTemplates);
      }

      final jsonData = jsonEncode(
        templates.map((t) => t.toMap()).toList(),
      );

      final encrypted = _encryptData(jsonData);
      if (encrypted != null) {
        await _secureStorage.write(key: 'nudge_templates', value: encrypted);
        AdvancedLogger.log('NudgeService', 'Templates saved to secure storage');
      }
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error saving templates to secure storage: $e');
    }
  }

  /// Load templates from secure storage
  Future<List<NudgeTemplate>> _loadTemplatesFromSecureStorage() async {
    try {
      final encrypted = await _secureStorage.read(key: 'nudge_templates');
      if (encrypted != null && encrypted.isNotEmpty) {
        final decrypted = _decryptData(encrypted);
        if (decrypted != null) {
          final List<dynamic> jsonData = jsonDecode(decrypted);

          final templates = <NudgeTemplate>[];
          for (final item in jsonData) {
            try {
              if (item is Map<String, dynamic>) {
                final template = NudgeTemplate.fromMap(
                  item,
                  item['id'] as String? ?? const Uuid().v4(),
                );
                templates.add(template);
              }
            } catch (e) {
              AdvancedLogger.logError('NudgeService', 'Error parsing cached template: $e');
            }
          }

          // Rebuild category cache
          _templateCache.clear();
          for (final template in templates) {
            if (!_templateCache.containsKey(template.category)) {
              _templateCache[template.category] = [];
            }
            _templateCache[template.category]!.add(template);
          }

          AdvancedLogger.log('NudgeService', 'Loaded ${templates.length} templates from secure storage');
          return templates;
        }
      }
      return [];
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error loading templates from secure storage: $e');
      return [];
    }
  }

  /// Get nudge templates by category
  ///
  /// Fetches nudge templates from Firestore filtered by category.
  /// Uses caching for performance and offline support.
  ///
  /// [category] The category to filter by.
  ///
  /// Returns a [List] of [NudgeTemplate] objects in the specified category.
  Future<List<NudgeTemplate>> getTemplatesByCategory(NudgeCategory category) async {
    try {
      AdvancedLogger.log('NudgeService', 'Fetching templates for category: ${category.name}');

      // Check if we have this category in cache and it's still valid
      if (_templateCacheExpires != null &&
          DateTime.now().isBefore(_templateCacheExpires!) &&
          _templateCache.containsKey(category) &&
          _templateCache[category]!.isNotEmpty) {
        AdvancedLogger.log(
          'NudgeService',
          'Using ${_templateCache[category]!.length} cached templates for ${category.name}',
        );
        return List<NudgeTemplate>.from(_templateCache[category]!);
      }

      // If offline and we have cached templates for this category
      if (_isOffline &&
          _templateCache.containsKey(category) &&
          _templateCache[category]!.isNotEmpty) {
        AdvancedLogger.log(
          'NudgeService',
          'Offline mode: using ${_templateCache[category]!.length} cached templates for ${category.name}',
        );
        return List<NudgeTemplate>.from(_templateCache[category]!);
      }

      // Otherwise, fetch from Firestore
      final querySnapshot = await _retryOptions.retry(() async {
        return await _firestore
            .collection('nudge_templates')
            .where('category', isEqualTo: category.name)
            .get();
      }, retryIf: (e) => _shouldRetry(e));

      final templates = <NudgeTemplate>[];

      // Clear existing cache for this category
      _templateCache[category] = [];

      // Process results
      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();

          // Validate before parsing
          if (data.containsKey('text') && data.containsKey('category')) {
            final template = NudgeTemplate.fromMap(data, doc.id);
            templates.add(template);
            _templateCache[category]!.add(template);
          }
        } catch (e) {
          AdvancedLogger.logError(
            'NudgeService',
            'Error parsing template ${doc.id}: $e',
          );
        }
      }

      // Update cache expiration if not already set
      if (_templateCacheExpires == null || DateTime.now().isAfter(_templateCacheExpires!)) {
        _templateCacheExpires = DateTime.now().add(const Duration(hours: 12));
      }

      // Save updated templates to secure storage
      await _saveTemplatesToSecureStorage();

      AdvancedLogger.log('NudgeService', 'Fetched ${templates.length} templates for ${category.name}');
      return templates;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error fetching templates by category: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to fetch templates by category: $e');

      // Return cached templates if any (even if cache is expired)
      if (_templateCache.containsKey(category) && _templateCache[category]!.isNotEmpty) {
        return List<NudgeTemplate>.from(_templateCache[category]!);
      }

      return [];
    }
  }

  // ======== NUDGE HISTORY ========
  /// Get user's nudge delivery history
  ///
  /// Fetches the most recent nudge deliveries for the current user.
  ///
  /// [limit] Maximum number of deliveries to fetch (default: 10).
  ///
  /// Returns a [List] of [NudgeDelivery] objects sorted by timestamp.
  ///
  /// Throws [StateError] if the user is not authenticated.
  Future<List<NudgeDelivery>> getNudgeHistory({int limit = 10}) async {
    try {
      AdvancedLogger.log('NudgeService', 'Fetching nudge history, limit: $limit');

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // If offline, try to get from cache
      if (_isOffline) {
        final cachedHistory = await _getCachedNudgeHistory();

        // Apply limit
        if (cachedHistory.length > limit) {
          return cachedHistory.sublist(0, limit);
        }

        return cachedHistory;
      }

      // Otherwise, fetch from Firestore
      final querySnapshot = await _retryOptions.retry(() async {
        return await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('nudge_deliveries')
            .orderBy('timestamp', descending: true)
            .limit(limit)
            .get();
      }, retryIf: (e) => _shouldRetry(e));

      final nudges = <NudgeDelivery>[];

      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();

          // Validate before parsing
          if (_validateNudgeDeliveryData(data)) {
            final nudge = NudgeDelivery.fromMap(data, doc.id);
            nudges.add(nudge);

            // Cache the nudge
            await _cacheNudgeDelivery(nudge);
          }
        } catch (e) {
          AdvancedLogger.logError(
            'NudgeService',
            'Error parsing nudge delivery ${doc.id}: $e',
          );
        }
      }

      // Ensure cached history is up to date
      await _updateCachedHistory(nudges);

      AdvancedLogger.log('NudgeService', 'Fetched ${nudges.length} nudge history items');
      return nudges;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error fetching nudge history: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to fetch nudge history: $e');

      // Try to get from cache as fallback
      return await _getCachedNudgeHistory();
    }
  }

  /// Validate nudge delivery data structure
  bool _validateNudgeDeliveryData(Map<String, dynamic> data) {
    try {
      // Check required fields
      final requiredFields = [
        'templateId',
        'timestamp',
        'text',
        'audioUrl',
        'category',
        'timeWindow',
      ];

      for (final field in requiredFields) {
        if (!data.containsKey(field)) {
          return false;
        }
      }

      // Check types
      if (data['timestamp'] is! Timestamp) {
        return false;
      }

      if (data['text'] is! String) {
        return false;
      }

      if (data['audioUrl'] is! String) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get nudge deliveries for a specific day
  ///
  /// Fetches all nudge deliveries that occurred on the specified day.
  ///
  /// [day] The day to fetch deliveries for.
  ///
  /// Returns a [List] of [NudgeDelivery] objects for the specified day.
  ///
  /// Throws [StateError] if the user is not authenticated.
  Future<List<NudgeDelivery>> getNudgeDeliveriesForDay(DateTime day) async {
    try {
      final dayFormatted = DateFormat('yyyy-MM-dd').format(day);
      AdvancedLogger.log('NudgeService', 'Fetching nudges for day: $dayFormatted');

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }
      // Get start and end of the day in Timestamp format
      final startOfDay = Timestamp.fromDate(
        DateTime(day.year, day.month, day.day, 0, 0, 0),
      );

      final endOfDay = Timestamp.fromDate(
        DateTime(day.year, day.month, day.day, 23, 59, 59),
      );

      // If offline, filter cached history
      if (_isOffline) {
        final cachedHistory = await _getCachedNudgeHistory();

        return cachedHistory.where((nudge) {
          final nudgeTime = nudge.timestamp.toDate();
          return nudgeTime.isAfter(startOfDay.toDate()) &&
              nudgeTime.isBefore(endOfDay.toDate());
        }).toList();
      }

      // Otherwise, fetch from Firestore
      final querySnapshot = await _retryOptions.retry(() async {
        return await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('nudge_deliveries')
            .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
            .where('timestamp', isLessThanOrEqualTo: endOfDay)
            .get();
      }, retryIf: (e) => _shouldRetry(e));

      final nudges = <NudgeDelivery>[];

      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          if (_validateNudgeDeliveryData(data)) {
            final nudge = NudgeDelivery.fromMap(data, doc.id);
            nudges.add(nudge);

            // Cache the nudge
            await _cacheNudgeDelivery(nudge);
          }
        } catch (e) {
          AdvancedLogger.logError(
            'NudgeService',
            'Error parsing nudge delivery ${doc.id}: $e',
          );
        }
      }

      // Update cached history
      await _updateCachedHistory(nudges);

      AdvancedLogger.log('NudgeService', 'Fetched ${nudges.length} nudges for $dayFormatted');
      return nudges;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error fetching nudges for day: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to fetch nudges for day: $e');

      // Try from cache as fallback
      if (_isOffline) {
        try {
          final cachedHistory = await _getCachedNudgeHistory();

          return cachedHistory.where((nudge) {
            final nudgeTime = nudge.timestamp.toDate();
            return nudgeTime.year == day.year &&
                nudgeTime.month == day.month &&
                nudgeTime.day == day.day;
          }).toList();
        } catch (e) {
          AdvancedLogger.logError('NudgeService', 'Error filtering cached history: $e');
        }
      }

      return [];
    }
  }

  /// Get a specific nudge delivery by ID
  ///
  /// Fetches a single nudge delivery by its unique ID.
  /// Tries local cache first, then Firestore if online.
  ///
  /// [id] The ID of the nudge delivery to fetch.
  ///
  /// Returns the [NudgeDelivery] object if found, null otherwise.
  ///
  /// Throws [StateError] if the user is not authenticated.
  Future<NudgeDelivery?> getNudgeDeliveryById(String id) async {
    try {
      AdvancedLogger.log('NudgeService', 'Fetching nudge delivery by ID: $id');

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // Try to get from cache first
      final cachedNudge = await _getCachedNudgeDelivery(id);
      if (cachedNudge != null) {
        AdvancedLogger.log('NudgeService', 'Found nudge in cache: $id');
        return cachedNudge;
      }

      // If offline and not in cache, we can't fetch it
      if (_isOffline) {
        AdvancedLogger.log('NudgeService', 'Device offline and nudge not in cache: $id');
        return null;
      }

      // Otherwise, fetch from Firestore
      final doc = await _retryOptions.retry(() async {
        return await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('nudge_deliveries')
            .doc(id)
            .get();
      }, retryIf: (e) => _shouldRetry(e));

      if (doc.exists) {
        final data = doc.data()!;

        if (_validateNudgeDeliveryData(data)) {
          final nudge = NudgeDelivery.fromMap(data, doc.id);

          // Cache the nudge
          await _cacheNudgeDelivery(nudge);

          return nudge;
        } else {
          AdvancedLogger.logError('NudgeService', 'Invalid nudge data for ID: $id');
          return null;
        }
      } else {
        AdvancedLogger.log('NudgeService', 'Nudge delivery not found: $id');
        return null;
      }
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error fetching nudge by ID: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to fetch nudge by ID: $e');
      return null;
    }
  }

  /// Cache a nudge delivery locally
  ///
  /// Stores a nudge delivery in secure storage for offline access.
  ///
  /// [nudge] The nudge delivery to cache.
  Future<void> _cacheNudgeDelivery(NudgeDelivery nudge) async {
    try {
      // Get existing cache
      final cachedNudges = await _getCachedNudgeHistory();

      // Check if already cached
      final existingIndex = cachedNudges.indexWhere((n) => n.id == nudge.id);
      if (existingIndex >= 0) {
        // Update existing entry
        cachedNudges[existingIndex] = nudge;
      } else {
        // Add new entry
        cachedNudges.add(nudge);
      }

      // Sort by timestamp (newest first)
      cachedNudges.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Limit cache size (keep latest 50)
      if (cachedNudges.length > 50) {
        cachedNudges.removeRange(50, cachedNudges.length);
      }

      // Save updated cache
      await _updateCachedHistory(cachedNudges);

    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error caching nudge delivery: $e');
    }
  }

  /// Get cached nudge delivery by ID
  ///
  /// Retrieves a nudge delivery from the local cache.
  ///
  /// [id] The ID of the nudge to retrieve.
  ///
  /// Returns the [NudgeDelivery] if found in cache, null otherwise.
  Future<NudgeDelivery?> _getCachedNudgeDelivery(String id) async {
    try {
      final cachedNudges = await _getCachedNudgeHistory();
      return cachedNudges.firstWhere(
            (nudge) => nudge.id == id,
        orElse: () => null as NudgeDelivery, // Will be caught and return null
      );
    } catch (e) {
      return null;
    }
  }

  /// Get cached nudge history
  ///
  /// Retrieves the cached nudge history from secure storage.
  ///
  /// Returns a [List] of [NudgeDelivery] objects from the cache.
  Future<List<NudgeDelivery>> _getCachedNudgeHistory() async {
    try {
      final data = await _secureStorage.read(key: 'nudge_history');
      if (data != null && data.isNotEmpty) {
        final decrypted = _decryptData(data);
        if (decrypted != null) {
          final List<dynamic> jsonData = jsonDecode(decrypted);

          final nudges = <NudgeDelivery>[];
          for (final item in jsonData) {
            try {
              if (item is Map<String, dynamic>) {
                final nudge = NudgeDelivery.fromMap(
                  item,
                  item['id'] as String? ?? const Uuid().v4(),
                );
                nudges.add(nudge);
              }
            } catch (e) {
              AdvancedLogger.logError('NudgeService', 'Error parsing cached nudge: $e');
            }
          }

          return nudges;
        }
      }
      return [];
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error getting cached nudge history: $e');
      return [];
    }
  }

  /// Update cached nudge history
  ///
  /// Updates the cached nudge history in secure storage.
  ///
  /// [nudges] The list of nudges to cache.
  Future<void> _updateCachedHistory(List<NudgeDelivery> nudges) async {
    try {
      if (nudges.isEmpty) {
        return;
      }

      final jsonData = jsonEncode(
        nudges.map((n) => n.toMap()).toList(),
      );

      final encrypted = _encryptData(jsonData);
      if (encrypted != null) {
        await _secureStorage.write(key: 'nudge_history', value: encrypted);
      }
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error updating cached history: $e');
    }
  }

  // ======== NUDGE DELIVERY LOGIC ========
  /// Check if a nudge can be delivered now
  ///
  /// Determines if a nudge can be delivered based on:
  /// - Service initialization
  /// - Authentication status
  /// - User settings (enabled/disabled)
  /// - Current time window
  /// - Previous deliveries in the current time window
  /// - Maximum daily nudges
  /// - Network connectivity (if offline mode not allowed)
  ///
  /// Returns true if a nudge can be delivered, false otherwise.
  Future<bool> canDeliverNudgeNow({bool allowOffline = false}) async {
    try {
      AdvancedLogger.log('NudgeService', 'Checking if nudge can be delivered now');

      if (!isInitialized) {
        AdvancedLogger.log('NudgeService', 'Service not initialized');
        return false;
      }

      if (!isUserAuthenticated) {
        AdvancedLogger.log('NudgeService', 'User not authenticated');
        return false;
      }

      // Check connectivity if offline mode not allowed
      if (_isOffline && !allowOffline) {
        AdvancedLogger.log('NudgeService', 'Device offline and offline delivery not allowed');
        return false;
      }

      // Load settings if not already loaded
      if (_userSettings == null) {
        await loadUserSettings();
      }

      // Check if nudges are enabled
      if (_userSettings?.enabled != true) {
        AdvancedLogger.log('NudgeService', 'Nudges are disabled in user settings');
        return false;
      }

      // Get current time window
      final currentTimeWindow = _getCurrentTimeWindow();
      if (currentTimeWindow == null) {
        AdvancedLogger.log('NudgeService', 'Current time is not within any time window');
        return false;
      }

      // Check if current time window is enabled
      if (_userSettings?.enabledTimeWindows[currentTimeWindow] != true) {
        AdvancedLogger.log('NudgeService', 'Current time window is disabled: ${currentTimeWindow.name}');
        return false;
      }

      // Check if we've already delivered a nudge in this time window
      final todayNudges = await getNudgeDeliveriesForDay(DateTime.now());

      // Count nudges in current time window
      final nudgesInCurrentWindow = todayNudges.where((nudge) {
        final nudgeTime = nudge.timestamp.toDate();
        final nudgeTimeWindow = _getTimeWindowForDateTime(nudgeTime);
        return nudgeTimeWindow == currentTimeWindow;
      }).length;

      if (nudgesInCurrentWindow > 0) {
        AdvancedLogger.log('NudgeService', 'Already delivered a nudge in the current time window');
        return false;
      }

      // Check if we've reached max daily nudges
      final maxDailyNudges = _userSettings?.maxDailyNudges ?? 3;
      if (todayNudges.length >= maxDailyNudges) {
        AdvancedLogger.log('NudgeService', 'Reached max daily nudges: ${todayNudges.length}/$maxDailyNudges');
        return false;
      }

      AdvancedLogger.log('NudgeService', 'Nudge can be delivered now');
      return true;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error checking if nudge can be delivered: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to check nudge delivery status: $e');
      return false;
    }
  }

  /// Get the current time window based on the current time
  ///
  /// Determines which time window (morning, noon, evening) the current time falls into.
  ///
  /// Returns the [TimeWindow] if current time is within a defined window, null otherwise.
  TimeWindow? _getCurrentTimeWindow() {
    final now = TimeOfDay.now();

    for (final window in TimeWindow.values) {
      final start = _timeWindowStartTimes[window]!;
      final end = _timeWindowEndTimes[window]!;

      // Convert to minutes for easy comparison
      final nowMinutes = now.hour * 60 + now.minute;
      final startMinutes = start.hour * 60 + start.minute;
      final endMinutes = end.hour * 60 + end.minute;

      if (nowMinutes >= startMinutes && nowMinutes <= endMinutes) {
        return window;
      }
    }

    return null;
  }

  /// Get the time window for a specific date/time
  ///
  /// Determines which time window a given datetime falls into.
  ///
  /// [dateTime] The datetime to check.
  ///
  /// Returns the [TimeWindow] if the time is within a defined window, null otherwise.
  TimeWindow? _getTimeWindowForDateTime(DateTime dateTime) {
    final timeOfDay = TimeOfDay.fromDateTime(dateTime);

    for (final window in TimeWindow.values) {
      final start = _timeWindowStartTimes[window]!;
      final end = _timeWindowEndTimes[window]!;

      // Convert to minutes for easy comparison
      final timeMinutes = timeOfDay.hour * 60 + timeOfDay.minute;
      final startMinutes = start.hour * 60 + start.minute;
      final endMinutes = end.hour * 60 + end.minute;

      if (timeMinutes >= startMinutes && timeMinutes <= endMinutes) {
        return window;
      }
    }

    return null;
  }

  /// Select an appropriate nudge template for delivery
  ///
  /// Chooses a template based on:
  /// - Current time window
  /// - Enabled categories in user settings
  /// - Recent history (to avoid repetition)
  /// - Offline availability
  ///
  /// Returns a [NudgeTemplate] if a suitable template is found, null otherwise.
  Future<NudgeTemplate?> _selectNudgeTemplate() async {
    try {
      AdvancedLogger.log('NudgeService', 'Selecting nudge template');

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // Load settings if not already loaded
      if (_userSettings == null) {
        await loadUserSettings();
      }

      // Get current time window
      final currentTimeWindow = _getCurrentTimeWindow();
      if (currentTimeWindow == null) {
        AdvancedLogger.log('NudgeService', 'No valid time window for template selection');
        return null;
      }

      // Get enabled categories
      final enabledCategories = _userSettings?.enabledCategories.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList() ?? [];

      if (enabledCategories.isEmpty) {
        AdvancedLogger.log('NudgeService', 'No enabled categories found');
        return null;
      }

      // If we have valid categories, select one at random
      final random = Random();

      // Shuffle categories for more randomness
      enabledCategories.shuffle(random);

      // Try each category until we find available templates
      for (final category in enabledCategories) {
        final templates = await getTemplatesByCategory(category);
        if (templates.isEmpty) {
          AdvancedLogger.log('NudgeService', 'No templates found for category: ${category.name}');
          continue;
        }

        // Get history to avoid repeating recent nudges
        final history = await getNudgeHistory(limit: 10);
        final recentTemplateIds = history.map((nudge) => nudge.templateId).toSet();

        // Filter out recently used templates if possible
        var availableTemplates = templates.where((t) => !recentTemplateIds.contains(t.id)).toList();

        // If all templates were recently used, fall back to all templates
        if (availableTemplates.isEmpty) {
          availableTemplates = templates;
        }

        // If we have templates, select one randomly
        if (availableTemplates.isNotEmpty) {
          // Randomize selection
          availableTemplates.shuffle(random);

          // Prioritize templates with pre-generated audio if offline
          if (_isOffline) {
            // Try to find a template with audio URL
            final templatesWithAudio = availableTemplates
                .where((t) => t.audioUrl != null && t.audioUrl!.isNotEmpty)
                .toList();

            if (templatesWithAudio.isNotEmpty) {
              final selectedTemplate = templatesWithAudio.first;
              AdvancedLogger.log(
                'NudgeService',
                'Selected offline-compatible template: ${selectedTemplate.id} (${selectedTemplate.category.name})',
              );
              return selectedTemplate;
            }
          }

          // Otherwise, just use the first template after shuffling
          final selectedTemplate = availableTemplates.first;
          AdvancedLogger.log(
            'NudgeService',
            'Selected template: ${selectedTemplate.id} (${selectedTemplate.category.name})',
          );
          return selectedTemplate;
        }
      }

      // If we get here, we couldn't find a suitable template
      AdvancedLogger.log('NudgeService', 'No suitable template found');
      return null;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error selecting nudge template: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to select nudge template: $e');
      return null;
    }
  }

  /// Deliver a nudge now
  ///
  /// This method:
  /// 1. Checks if a nudge can be delivered
  /// 2. Selects an appropriate template
  /// 3. Generates audio if needed (and online)
  /// 4. Creates a nudge delivery record
  /// 5. Shows a notification
  /// 6. Adds the nudge to the stream
  /// 7. Schedules the next nudge
  ///
  /// [allowOffline] Whether to allow delivery in offline mode (default: false)
  ///
  /// Returns the [NudgeDelivery] object if successful, null otherwise.
  Future<NudgeDelivery?> deliverNudgeNow({bool allowOffline = false}) async {
    try {
      AdvancedLogger.log('NudgeService', 'Attempting to deliver nudge now');

      if (!isInitialized) {
        throw StateError('Service not initialized');
      }

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // Check if we can deliver a nudge now
      final canDeliver = await canDeliverNudgeNow(allowOffline: allowOffline);
      if (!canDeliver) {
        AdvancedLogger.log('NudgeService', 'Cannot deliver nudge now');
        return null;
      }

      // Select a template
      final template = await _selectNudgeTemplate();
      if (template == null) {
        AdvancedLogger.log('NudgeService', 'No template available for delivery');
        return null;
      }

      // Get or generate audio URL
      String? audioUrl = template.audioUrl;

      // If no pre-recorded audio and we're online, generate using OpenAI TTS
      if ((audioUrl == null || audioUrl.isEmpty) && !_isOffline) {
        audioUrl = await _generateTTSAudio(template);

        // If we couldn't generate audio, abort
        if (audioUrl == null) {
          Logger.error('NudgeService', 'Failed to generate audio for nudge');
          return null;
        }
      } else if ((audioUrl == null || audioUrl.isEmpty) && _isOffline) {
        // We're offline and no audio available
        AdvancedLogger.log(
          'NudgeService',
          'Template has no audio and device is offline, cannot deliver',
        );
        return null;
      }

      // Create nudge delivery object
      final nudgeId = const Uuid().v4();
      final nudgeDelivery = NudgeDelivery(
        id: nudgeId,
        templateId: template.id,
        timestamp: Timestamp.now(),
        text: template.text,
        audioUrl: audioUrl!,
        category: template.category,
        timeWindow: _getCurrentTimeWindow() ?? TimeWindow.other,
        userFeedback: null,
        saved: false,
      );

      // If offline, cache locally and queue for upload later
      if (_isOffline) {
        await _cacheNudgeDelivery(nudgeDelivery);

        // Add to pending operations to save to Firestore later
        _pendingOperations.add({
          'type': 'save_nudge',
          'data': nudgeDelivery.toMap(),
        });

        await _persistPendingOperations();

        AdvancedLogger.log(
          'NudgeService',
          'Nudge cached locally in offline mode: ${nudgeDelivery.id}',
        );
      } else {
        // Save to Firestore
        await _saveNudgeDelivery(nudgeDelivery);
      }

      // Show notification
      await _showNudgeNotification(nudgeDelivery);

      // Add to stream
      _nudgeStreamController.add(nudgeDelivery);

      // Track delivery for analytics
      AnalyticsService.logEvent(
        'nudge_delivered',
        parameters: {
          'nudge_id': nudgeDelivery.id,
          'category': nudgeDelivery.category.name,
          'time_window': nudgeDelivery.timeWindow.name,
        },
      );

      // Schedule next nudge
      await scheduleNextNudge();

      AdvancedLogger.log('NudgeService', 'Nudge delivered successfully: ${nudgeDelivery.id}');
      return nudgeDelivery;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error delivering nudge: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to deliver nudge: $e');

      // Show error notification
      _showServiceNotification(
        'We couldn\'t deliver your nudge right now. Please try again later.',
        'Nudge Delivery Error',
      );

      return null;
    }
  }

  // ======== AUDIO GENERATION ========
  /// Generate TTS audio for a template
  ///
  /// Uses OpenAI's text-to-speech API to generate audio for a template,
  /// then uploads the audio to Firebase Storage.
  /// Implements retry logic for resilience.
  ///
  /// [template] The template to generate audio for.
  ///
  /// Returns the download URL for the generated audio file,
  /// or null if generation failed.
  ///
  /// Throws [StateError] if the user is not authenticated.
  Future<String?> _generateTTSAudio(NudgeTemplate template) async {
    try {
      AdvancedLogger.log('NudgeService', 'Generating TTS audio for template: ${template.id}');

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      if (_isOffline) {
        throw StateError('Cannot generate TTS audio in offline mode');
      }

      // Get user's voice preference
      final voicePreference = _userSettings?.voicePreference ?? 'nova';

      // Generate audio file using OpenAI with retry logic
      final audioBytes = await _retryOptions.retry(() async {
        return await _openAIService.generateTTS(
          text: template.text,
          voice: voicePreference,
        );
      }, retryIf: (e) => _shouldRetry(e));

      if (audioBytes == null || audioBytes.isEmpty) {
        Logger.error('NudgeService', 'Failed to generate TTS audio: empty response');
        return null;
      }

      // Format filename with date
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'nudge_${template.id}_$dateStr.mp3';

      // Save local copy for offline use
      await _saveAudioFile(audioBytes, filename);

      // Upload to Firebase Storage with retry logic
      final storageRef = _storage
          .ref()
          .child('users/${_currentUser!.uid}/nudge_audio/$filename');

      await _retryOptions.retry(() async {
        await storageRef.putData(audioBytes);
      }, retryIf: (e) => _shouldRetry(e));

      // Get download URL
      final downloadUrl = await _retryOptions.retry(() async {
        return await storageRef.getDownloadURL();
      }, retryIf: (e) => _shouldRetry(e));

      AdvancedLogger.log('NudgeService', 'TTS audio generated and uploaded: $downloadUrl');
      return downloadUrl;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error generating TTS audio: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to generate TTS audio: $e');
      return null;
    }
  }

  /// Save audio file locally for offline use
  ///
  /// Stores audio data in the app's documents directory.
  ///
  /// [audioBytes] The raw audio data.
  /// [filename] The filename to use.
  ///
  /// Returns the local file path if successful, null otherwise.
  Future<String?> _saveAudioFile(Uint8List audioBytes, String filename) async {
    try {
      // Get the app's documents directory
      final directory = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${directory.path}/nudge_audio');

      // Create directory if it doesn't exist
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }

      // Create the file
      final file = File('${audioDir.path}/$filename');
      await file.writeAsBytes(audioBytes);

      AdvancedLogger.log('NudgeService', 'Audio file saved locally: ${file.path}');
      return file.path;
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error saving audio file locally: $e');
      return null;
    }
  }

  // ======== PERSISTENCE ========
  /// Save nudge delivery to Firestore
  ///
  /// Persists a nudge delivery record to the user's collection.
  /// Implements retry logic for resilience.
  ///
  /// [nudgeDelivery] The nudge delivery to save.
  ///
  /// Throws [StateError] if the user is not authenticated.
  Future<void> _saveNudgeDelivery(NudgeDelivery nudgeDelivery) async {
    try {
      AdvancedLogger.log('NudgeService', 'Saving nudge delivery: ${nudgeDelivery.id}');

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // Sanitize data before saving
      final sanitizedData = _sanitizeNudgeData(nudgeDelivery.toMap());

      // Save to Firestore with retry logic
      await _retryOptions.retry(() async {
        await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('nudge_deliveries')
            .doc(nudgeDelivery.id)
            .set(sanitizedData);
      }, retryIf: (e) => _shouldRetry(e));

      // Cache locally for offline access
      await _cacheNudgeDelivery(nudgeDelivery);

      AdvancedLogger.log('NudgeService', 'Nudge delivery saved successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error saving nudge delivery: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to save nudge delivery: $e');

      // If still authenticated but other error occurred, cache for later retry
      if (isUserAuthenticated) {
        AdvancedLogger.log('NudgeService', 'Caching nudge for later upload');
        await _cacheNudgeDelivery(nudgeDelivery);

        _pendingOperations.add({
          'type': 'save_nudge',
          'data': nudgeDelivery.toMap(),
        });

        await _persistPendingOperations();
      }

      throw StateError('Failed to save nudge delivery: $e');
    }
  }

  /// Sanitize nudge data before saving to Firestore
  ///
  /// Removes any potentially harmful or invalid data.
  ///
  /// [data] The nudge data to sanitize.
  ///
  /// Returns sanitized data map.
  Map<String, dynamic> _sanitizeNudgeData(Map<String, dynamic> data) {
    final sanitized = Map<String, dynamic>.from(data);

    // Ensure only valid fields are included
    final validKeys = [
      'id',
      'templateId',
      'timestamp',
      'text',
      'audioUrl',
      'category',
      'timeWindow',
      'userFeedback',
      'saved',
    ];

    sanitized.removeWhere((key, value) => !validKeys.contains(key));

    // Ensure text is not too long
    if (sanitized.containsKey('text') && sanitized['text'] is String) {
      final text = sanitized['text'] as String;
      if (text.length > 500) {
        sanitized['text'] = text.substring(0, 500);
      }
    }

    return sanitized;
  }

  /// Determine if an operation should be retried
  ///
  /// Evaluates an error to decide if a retry attempt should be made.
  ///
  /// [e] The error to evaluate.
  ///
  /// Returns true if the operation should be retried, false otherwise.
  bool _shouldRetry(Exception e) {
    final errorString = e.toString().toLowerCase();

    // Retry network errors
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('unavailable')) {
      return true;
    }

    // Retry rate limiting errors
    if (errorString.contains('too many requests') ||
        errorString.contains('rate limit') ||
        errorString.contains('resource exhausted')) {
      return true;
    }

    // Do not retry authentication/permission errors
    if (errorString.contains('permission') ||
        errorString.contains('unauthorized') ||
        errorString.contains('unauthenticated')) {
      return false;
    }

    // Default to not retrying
    return false;
  }

  // ======== NOTIFICATIONS ========
  /// Show notification for delivered nudge
  ///
  /// Creates and displays a notification for a nudge delivery.
  /// The notification includes category-specific icons and titles.
  ///
  /// [nudgeDelivery] The nudge delivery to show a notification for.
  Future<void> _showNudgeNotification(NudgeDelivery nudgeDelivery) async {
    try {
      AdvancedLogger.log('NudgeService', 'Showing notification for nudge: ${nudgeDelivery.id}');

      // Get category-specific icon and title
      String icon;
      String title;
      String channelId = 'nudge_channel';

      // Set category-specific notification content
      switch (nudgeDelivery.category) {
        case NudgeCategory.gratitude:
          icon = 'ic_gratitude';
          title = 'Gratitude Moment';
          break;
        case NudgeCategory.mindfulness:
          icon = 'ic_mindfulness';
          title = 'Mindfulness Check-in';
          break;
        case NudgeCategory.selfReflection:
          icon = 'ic_reflection';
          title = 'Self-Reflection';
          break;
        case NudgeCategory.reassurance:
          icon = 'ic_reassurance';
          title = 'Reassurance';
          break;
        case NudgeCategory.cognitive:
          icon = 'ic_cognitive';
          title = 'Thought Exercise';
          break;
        default:
          icon = 'ic_notification';
          title = 'Milo Nudge';
      }

      // Create notification details for Android
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        channelId,
        'Therapeutic Nudges',
        channelDescription: 'Timely therapeutic nudges from Milo',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('nudge_sound'),
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        icon: icon,
        category: AndroidNotificationCategory.reminder,

        // Accessibility features
        ticker: 'New therapeutic nudge from Milo',

        // Style for large text
        styleInformation: BigTextStyleInformation(
          _truncateText(nudgeDelivery.text, 80),
          htmlFormatBigText: false,
          contentTitle: title,
          htmlFormatContentTitle: false,
          summaryText: 'Tap to listen',
          htmlFormatSummaryText: false,
        ),

        // Keep for longer
        timeoutAfter: 300000, // 5 minutes

        // Actions
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            'listen',
            'Listen Now',
            icon: DrawableResourceAndroidBitmap('ic_play'),
            contextual: true,
          ),
          const AndroidNotificationAction(
            'save',
            'Save',
            icon: DrawableResourceAndroidBitmap('ic_save'),
          ),
        ],
      );

      // Create notification details for iOS
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'nudge_sound.aiff',
        interruptionLevel: InterruptionLevel.active,
        categoryIdentifier: 'nudgeCategory',
      );

      // Combined notification details
      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show notification
      await _notificationsPlugin.show(
        nudgeDelivery.id.hashCode,
        title,
        _truncateText(nudgeDelivery.text, 80),
        notificationDetails,
        payload: nudgeDelivery.id,
      );

      AdvancedLogger.log('NudgeService', 'Notification displayed successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error showing notification: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to show notification: $e');
      // Continue without showing notification - not critical
    }
  }

  /// Truncate text to a maximum length with ellipsis
  ///
  /// [text] The text to truncate.
  /// [maxLength] The maximum length to allow.
  ///
  /// Returns the truncated text with ellipsis if needed.
  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) {
      return text;
    }

    return '${text.substring(0, maxLength - 3)}...';
  }

  // ======== PLAYBACK ========
  /// Play a nudge's audio
  ///
  /// Loads and plays the audio for a nudge delivery.
  /// Sets volume based on user settings.
  /// Handles offline mode by using cached audio files.
  ///
  /// [nudgeDelivery] The nudge delivery to play.
  ///
  /// Returns true if playback started successfully, false otherwise.
  Future<bool> playNudge(NudgeDelivery nudgeDelivery) async {
    try {
      AdvancedLogger.log('NudgeService', 'Playing nudge: ${nudgeDelivery.id}');

      // Stop any currently playing audio
      await _audioPlayer.stop();

      // Set volume based on user settings
      await _audioPlayer.setVolume(_userSettings?.volume ?? 0.8);

      // Track current nudge ID
      _currentlyPlayingNudgeId = nudgeDelivery.id;

      // Check if we're offline
      if (_isOffline) {
        // Try to use cached file
        final localPath = await _getLocalAudioPath(nudgeDelivery.audioUrl);
        if (localPath != null) {
          AdvancedLogger.log('NudgeService', 'Using cached audio file: $localPath');
          await _audioPlayer.setFilePath(localPath);
        } else {
          // If no cached file and we're offline, we can't play
          throw StateError('Audio file not available offline');
        }
      } else {
        // Online mode - use URL directly
        await _audioPlayer.setUrl(nudgeDelivery.audioUrl);
      }

      // Play the audio with error handling
      await _audioPlayer.play();

      // Track playback start for analytics
      AnalyticsService.logEvent(
        'nudge_playback_started',
        parameters: {'nudge_id': nudgeDelivery.id},
      );

      AdvancedLogger.log('NudgeService', 'Nudge playback started');
      return true;
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error playing nudge: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to play nudge: $e');
      _handlePlaybackError(e);
      return false;
    }
  }

  /// Get local audio file path if available
  ///
  /// Checks if the audio file is available locally for offline playback.
  ///
  /// [audioUrl] The remote URL of the audio file.
  ///
  /// Returns the local file path if available, null otherwise.
  Future<String?> _getLocalAudioPath(String audioUrl) async {
    try {
      // Extract filename from URL
      final uri = Uri.parse(audioUrl);
      final filename = uri.pathSegments.last;

      // Check if file exists locally
      final directory = await getApplicationDocumentsDirectory();
      final audioDir = '${directory.path}/nudge_audio';
      final file = File('$audioDir/$filename');

      if (await file.exists()) {
        return file.path;
      }

      return null;
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error getting local audio path: $e');
      return null;
    }
  }

  /// Stop playing the current nudge
  ///
  /// Stops any currently playing nudge audio.
  Future<void> stopPlayback() async {
    try {
      AdvancedLogger.log('NudgeService', 'Stopping nudge playback');
      await _audioPlayer.stop();
      _currentlyPlayingNudgeId = null;
    } catch (e) {
      AdvancedLogger.logError('NudgeService', 'Error stopping playback: $e');
    }
  }

  /// Get the current playback position
  ///
  /// Returns a stream of the current audio position.
  Stream<Duration> get playbackPositionStream => _audioPlayer.positionStream;

  /// Get the current playback state
  ///
  /// Returns a stream of the current playback state.
  Stream<PlayerState> get playbackStateStream => _audioPlayer.playerStateStream;

  /// Get the total duration of the current audio
  ///
  /// Returns a stream of the audio duration.
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;

  /// Check if audio is currently playing
  ///
  /// Returns true if audio is playing, false otherwise.
  bool get isPlaying => _audioPlayer.playing;

  /// Get the ID of the currently playing nudge
  ///
  /// Returns the ID of the currently playing nudge, or null if none.
  String? get currentlyPlayingNudgeId => _currentlyPlayingNudgeId;

  // ======== USER FEEDBACK ========
  /// Submit user feedback for a nudge
  ///
  /// Updates the nudge delivery record with user feedback and
  /// saves aggregated feedback for analytics.
  /// Handles offline mode by queuing operations.
  ///
  /// [nudgeId] The ID of the nudge to submit feedback for.
  /// [isHelpful] Whether the nudge was helpful.
  ///
  /// Throws [StateError] if the user is not authenticated.
  Future<void> submitNudgeFeedback(String nudgeId, bool isHelpful) async {
    try {
      AdvancedLogger.log('NudgeService', 'Submitting feedback for nudge: $nudgeId (helpful: $isHelpful)');

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // Update local cache first
      final cachedNudge = await _getCachedNudgeDelivery(nudgeId);
      if (cachedNudge != null) {
        // Create updated nudge
        final updatedNudge = NudgeDelivery(
          id: cachedNudge.id,
          templateId: cachedNudge.templateId,
          timestamp: cachedNudge.timestamp,
          text: cachedNudge.text,
          audioUrl: cachedNudge.audioUrl,
          category: cachedNudge.category,
          timeWindow: cachedNudge.timeWindow,
          userFeedback: isHelpful,
          saved: cachedNudge.saved,
        );

        // Update cache
        await _cacheNudgeDelivery(updatedNudge);
      }

      // Track feedback for analytics
      AnalyticsService.logEvent(
        'nudge_feedback',
        parameters: {
          'nudge_id': nudgeId,
          'is_helpful': isHelpful.toString(),
        },
      );

      // If offline, queue for later
      if (_isOffline) {
        _pendingOperations.add({
          'type': 'feedback',
          'data': {
            'nudgeId': nudgeId,
            'isHelpful': isHelpful,
          },
        });

        await _persistPendingOperations();
        AdvancedLogger.log('NudgeService', 'Feedback queued for later submission');
        return;
      }

      // If online, update Firestore
      await _retryOptions.retry(() async {
        // Update the nudge delivery record
        await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('nudge_deliveries')
            .doc(nudgeId)
            .update({
          'userFeedback': isHelpful,
        });

        // Also update analytics collection for aggregated feedback
        await _firestore
            .collection('nudge_analytics')
            .doc('feedback')
            .collection('entries')
            .add({
          'nudgeId': nudgeId,
          'userId': _currentUser!.uid,
          'isHelpful': isHelpful,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }, retryIf: (e) => _shouldRetry(e));

      AdvancedLogger.log('NudgeService', 'Feedback submitted successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error submitting feedback: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to submit feedback: $e');

      // If we're still authenticated, queue for later
      if (isUserAuthenticated) {
        _pendingOperations.add({
          'type': 'feedback',
          'data': {
            'nudgeId': nudgeId,
            'isHelpful': isHelpful,
          },
        });

        await _persistPendingOperations();
        AdvancedLogger.log('NudgeService', 'Feedback queued after error');
      }
    }
  }

  // ======== MEMORY SAVING ========
  /// Save a nudge as a memory
  ///
  /// Marks a nudge as saved and creates a memory entry for it.
  /// Handles offline mode by queuing operations.
  ///
  /// [nudgeId] The ID of the nudge to save as a memory.
  ///
  /// Throws [StateError] if the user is not authenticated or the nudge is not found.
  Future<void> saveNudgeAsMemory(String nudgeId) async {
    try {
      AdvancedLogger.log('NudgeService', 'Saving nudge as memory: $nudgeId');

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // Get the nudge details from cache first
      NudgeDelivery? nudgeDelivery = await _getCachedNudgeDelivery(nudgeId);

      // If not in cache and online, try to fetch from Firestore
      if (nudgeDelivery == null && !_isOffline) {
        nudgeDelivery = await getNudgeDeliveryById(nudgeId);

        if (nudgeDelivery == null) {
          throw StateError('Nudge not found');
        }
      }

      // If we have the nudge, update local cache
      if (nudgeDelivery != null) {
        // Create updated nudge
        final updatedNudge = NudgeDelivery(
          id: nudgeDelivery.id,
          templateId: nudgeDelivery.templateId,
          timestamp: nudgeDelivery.timestamp,
          text: nudgeDelivery.text,
          audioUrl: nudgeDelivery.audioUrl,
          category: nudgeDelivery.category,
          timeWindow: nudgeDelivery.timeWindow,
          userFeedback: nudgeDelivery.userFeedback,
          saved: true,
        );

        // Update cache
        await _cacheNudgeDelivery(updatedNudge);

        // Track event for analytics
        AnalyticsService.logEvent(
          'nudge_saved_as_memory',
          parameters: {'nudge_id': nudgeId},
        );
      }

      // If offline, queue for later
      if (_isOffline) {
        _pendingOperations.add({
          'type': 'save_memory',
          'data': {'nudgeId': nudgeId},
        });

        await _persistPendingOperations();
        AdvancedLogger.log('NudgeService', 'Memory save queued for later');
        return;
      }

      // If online, update Firestore
      await _retryOptions.retry(() async {
        // Update the nudge record
        await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('nudge_deliveries')
            .doc(nudgeId)
            .update({
          'saved': true,
        });

        // Only continue if we have nudge details
        if (nudgeDelivery == null) {
          return;
        }

        // Format the title based on category
        String memoryTitle;
        switch (nudgeDelivery.category) {
          case NudgeCategory.gratitude:
            memoryTitle = 'Gratitude Moment';
            break;
          case NudgeCategory.mindfulness:
            memoryTitle = 'Mindfulness Check-in';
            break;
          case NudgeCategory.selfReflection:
            memoryTitle = 'Self-Reflection Thought';
            break;
          case NudgeCategory.reassurance:
            memoryTitle = 'Reassurance Note';
            break;
          case NudgeCategory.cognitive:
            memoryTitle = 'Cognitive Exercise';
            break;
          default:
            memoryTitle = 'Milo Nudge';
        }

        // Create a memory entry (in memories collection)
        await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('memories')
            .add({
          'title': memoryTitle,
          'content': nudgeDelivery.text,
          'audioUrl': nudgeDelivery.audioUrl,
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'nudge',
          'tags': [
            'nudge',
            nudgeDelivery.category.name.toLowerCase(),
          ],
          'nudgeId': nudgeId,
        });
      }, retryIf: (e) => _shouldRetry(e));

      AdvancedLogger.log('NudgeService', 'Nudge saved as memory successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error saving nudge as memory: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to save nudge as memory: $e');

      // If we're still authenticated, queue for later
      if (isUserAuthenticated) {
        _pendingOperations.add({
          'type': 'save_memory',
          'data': {'nudgeId': nudgeId},
        });

        await _persistPendingOperations();
        AdvancedLogger.log('NudgeService', 'Memory save queued after error');
      }

      throw StateError('We couldn\'t save this nudge to your memories. Please try again later.');
    }
  }

  // ======== SCHEDULING ========
  /// Schedule notification for next time window
  ///
  /// Schedules a notification for the next enabled time window.
  Future<void> scheduleNextNudge() async {
    try {
      AdvancedLogger.log('NudgeService', 'Scheduling next nudge notification');

      if (!isInitialized) {
        throw StateError('Service not initialized');
      }

      if (!isUserAuthenticated) {
        throw StateError('User not authenticated');
      }

      // Load settings if not already loaded
      if (_userSettings == null) {
        await loadUserSettings();
      }

      // Check if nudges are enabled
      if (_userSettings?.enabled != true) {
        AdvancedLogger.log('NudgeService', 'Nudges are disabled, not scheduling');
        return;
      }

      // Get current time window
      final currentTimeWindow = _getCurrentTimeWindow();

      // Find next enabled time window
      TimeWindow? nextWindow;
      if (currentTimeWindow == null) {
        // If not in any window, find the next one today
        final now = TimeOfDay.now();
        final nowMinutes = now.hour * 60 + now.minute;

        // Sort time windows by start time
        final sortedWindows = TimeWindow.values.toList()
          ..sort((a, b) {
            final aMinutes = _timeWindowStartTimes[a]!.hour * 60 + _timeWindowStartTimes[a]!.minute;
            final bMinutes = _timeWindowStartTimes[b]!.hour * 60 + _timeWindowStartTimes[b]!.minute;
            return aMinutes.compareTo(bMinutes);
          });

        // Find next window today
        for (final window in sortedWindows) {
          final windowStartMinutes = _timeWindowStartTimes[window]!.hour * 60 +
              _timeWindowStartTimes[window]!.minute;

          if (windowStartMinutes > nowMinutes &&
              _userSettings?.enabledTimeWindows[window] == true) {
            nextWindow = window;
            break;
          }
        }

        // If no window found today, schedule for tomorrow morning
        if (nextWindow == null && _userSettings?.enabledTimeWindows[TimeWindow.morning] == true) {
          nextWindow = TimeWindow.morning;
        }
      } else {
        // If in a window, schedule the next one
        final windows = TimeWindow.values.toList();
        final currentIndex = windows.indexOf(currentTimeWindow);

        // Try windows after current one
        for (int i = currentIndex + 1; i < windows.length; i++) {
          if (_userSettings?.enabledTimeWindows[windows[i]] == true) {
            nextWindow = windows[i];
            break;
          }
        }

        // If no next window today, schedule for tomorrow morning
        if (nextWindow == null && _userSettings?.enabledTimeWindows[TimeWindow.morning] == true) {
          nextWindow = TimeWindow.morning;
        }
      }

      // If no enabled window found, don't schedule
      if (nextWindow == null) {
        AdvancedLogger.log('NudgeService', 'No enabled time windows found for scheduling');
        return;
      }

      // Calculate next window start time
      final now = DateTime.now();
      final nextWindowStart = _timeWindowStartTimes[nextWindow]!;

      DateTime scheduledTime;
      if (currentTimeWindow == null || nextWindow.index > currentTimeWindow.index) {
        // Later today
        scheduledTime = DateTime(
          now.year,
          now.month,
          now.day,
          nextWindowStart.hour,
          nextWindowStart.minute,
        );
      } else {
        // Tomorrow
        final tomorrow = now.add(const Duration(days: 1));
        scheduledTime = DateTime(
          tomorrow.year,
          tomorrow.month,
          tomorrow.day,
          nextWindowStart.hour,
          nextWindowStart.minute,
        );
      }

      // Add randomness to avoid exact scheduling (within 5 minutes)
      final random = Random();
      scheduledTime = scheduledTime.add(Duration(minutes: random.nextInt(5)));

      // Make sure the time is in the future
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      // Schedule the notification
      final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

      // Create notification details
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'nudge_schedule_channel',
        'Scheduled Nudges',
        channelDescription: 'Scheduled therapeutic nudges from Milo',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        // Accessibility features
        ticker: 'Time for your Milo nudge',
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

      // Create a friendly message based on time window
      String message;
      switch (nextWindow) {
        case TimeWindow.morning:
          message = 'Start your day with a moment of reflection';
          break;
        case TimeWindow.noon:
          message = 'Take a mindful break in your day';
          break;
        case TimeWindow.evening:
          message = 'Wind down with an evening check-in';
          break;
        default:
          message = 'Time for your Milo check-in';
      }

      // Schedule notification
      await _notificationsPlugin.zonedSchedule(
        nextWindow.hashCode,
        'Milo Nudge',
        message,
        tzScheduledTime,
        notificationDetails,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      // Track scheduling for analytics
      AnalyticsService.logEvent(
        'nudge_scheduled',
        parameters: {
          'time_window': nextWindow.name,
          'scheduled_time': scheduledTime.toString(),
        },
      );

      AdvancedLogger.log(
        'NudgeService',
        'Scheduled next nudge for ${nextWindow.name} at ${scheduledTime.toString()}',
      );
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error scheduling next nudge: $e\n$stackTrace',
      );
      Logger.error('NudgeService', 'Failed to schedule next nudge: $e');
    }
  }

  // ======== RESOURCE MANAGEMENT ========
  /// Clean up resources used by the service
  ///
  /// Releases audio player resources and closes streams.
  /// Cancels all subscriptions and persists pending operations.
  Future<void> dispose() async {
    try {
      AdvancedLogger.log('NudgeService', 'Disposing resources');

      // Stop playback
      await stopPlayback();

      // Release audio player
      _audioPlayer.dispose();

      // Save any pending operations
      await _persistPendingOperations();

      // Cancel subscriptions
      _connectivitySubscription?.cancel();
      _authStateSubscription?.cancel();
      _appLifecycleSubscription?.cancel();

      // Close stream controllers
      if (!_nudgeStreamController.isClosed) {
        await _nudgeStreamController.close();
      }

      _isInitialized = false;
      AdvancedLogger.log('NudgeService', 'Resources disposed successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.logError(
        'NudgeService',
        'Error disposing resources: $e\n$stackTrace',
      );
    }
  }
}

/// Helper class for app lifecycle events
class LifecycleEventHandler extends WidgetsBindingObserver {
  final Function? resumeCallBack;
  final Function? pauseCallBack;

  LifecycleEventHandler({
    this.resumeCallBack,
    this.pauseCallBack,
  });

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        if (resumeCallBack != null) {
          await resumeCallBack!();
        }
        break;
      case AppLifecycleState.paused:
        if (pauseCallBack != null) {
          await pauseCallBack!();
        }
        break;
      default:
        break;
    }
  }
}

/// Data class for nudge error events
class NudgeErrorEvent {
  final String errorType;
  final String message;
  final DateTime timestamp;

  NudgeErrorEvent({
    required this.errorType,
    required this.message,
    required this.timestamp,
  });
}
