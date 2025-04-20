import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

// Import Firebase options
import 'firebase_options.dart';

// Import EnvService for Firebase API keys
import 'services/env_service.dart';

// Theme
import 'theme/app_theme.dart';

// Screens - Using current file structure
import 'home_screen.dart';
import 'record_memory_screen.dart' as app_record;
import 'memories_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/conversation_screen.dart';
import 'screens/memory_detail_screen.dart';
import 'services/security_provider_initializer.dart';

// Services
import 'notification_service.dart';
import 'services/auth_service.dart';
import 'services/openai_service.dart';
import 'services/memory_service.dart' show MemoryService;
import '../utils/advanced_logger.dart';

// Utils
import 'utils/config.dart';
import 'utils/logger.dart';

// Flag to track Firebase initialization status globally
bool _isFirebaseInitialized = false;

void main() async {
  // This needs to be called only once
  WidgetsFlutterBinding.ensureInitialized();
  Logger.info('App', 'Flutter binding initialized');

  // Initialize security provider early
  await SecurityProviderInitializer.initialize();

  // FIRST: Load environment variables BEFORE Firebase initialization
  try {
    Logger.info('App', 'Loading environment variables...');
    await dotenv.load();
    Logger.info('App', 'Environment variables loaded successfully');

    // Add debug logging to verify API keys are loaded
    final androidKeyStatus = EnvService.firebaseAndroidApiKey.isNotEmpty
        ? 'available' : 'missing';
    final iosKeyStatus = EnvService.firebaseIosApiKey.isNotEmpty
        ? 'available' : 'missing';

    Logger.info('App', 'Android Firebase API Key: $androidKeyStatus');
    Logger.info('App', 'iOS Firebase API Key: $iosKeyStatus');

    // Show warning if keys are missing
    if (EnvService.firebaseAndroidApiKey.isEmpty || EnvService.firebaseIosApiKey.isEmpty) {
      Logger.warning('App', 'One or more Firebase API keys are missing in .env file');
    }
  } catch (e) {
    Logger.error('App', 'Failed to load environment variables: $e');
    Logger.error('App', 'This may cause Firebase initialization to fail');
  }

  // FIREBASE INITIALIZATION - SIMPLIFIED APPROACH
  try {
    Logger.info('App', 'Initializing Firebase...');

    if (Firebase.apps.isNotEmpty) {
      // Already initialized - just use existing app
      Logger.info('App', 'Firebase already initialized, using existing app');
      _isFirebaseInitialized = true;
    } else {
      // Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      Logger.info('App', 'Firebase initialization successful');
      _isFirebaseInitialized = true;
    }

    // Log Firebase info if initialized
    if (_isFirebaseInitialized) {
      Logger.info('App', 'Firebase project ID: ${DefaultFirebaseOptions.currentPlatform.projectId}');
      Logger.info('App', 'Firebase app ID: ${DefaultFirebaseOptions.currentPlatform.appId}');
    }
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      Logger.warning('App', 'Duplicate Firebase initialization detected, continuing with existing app');
      _isFirebaseInitialized = true;
    } else {
      Logger.error('App', 'Firebase initialization failed: $e');
    }
  }

  // Request app permissions
  try {
    Logger.info('App', 'Requesting app permissions...');
    await requestRequiredPermissions();
    Logger.info('App', 'App permissions requested');
  } catch (e) {
    Logger.error('App', 'Failed to request permissions: $e');
  }

  // Initialize security provider (helps with the dynamite module issue)
  try {
    Logger.info('App', 'Attempting to initialize security provider');
    // This is a workaround to trigger the security provider initialization
    await http.get(Uri.parse('https://www.google.com')).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        Logger.warning('App', 'Security provider check timed out');
        return http.Response('Timeout', 408);
      },
    );
    Logger.info('App', 'Security provider check completed');
  } catch (e) {
    Logger.warning('App', 'Unable to initialize security provider: $e');
    // Non-critical, app can continue
  }

  // Initialize app configuration
  try {
    await AppConfig().initialize();
    Logger.info('App', 'App configuration initialized');

    // Log if OpenAI API key is configured
    if (AppConfig().isOpenAIConfigured) {
      Logger.info('App', 'OpenAI API key is configured');
    } else {
      Logger.warning('App', 'OpenAI API key is not configured - AI features may not work properly');
    }
  } catch (e) {
    Logger.error('App', 'Failed to initialize app configuration: $e');
  }

  // Initialize notifications
  try {
    await NotificationService.init();
    Logger.info('App', 'Notification service initialized');
  } catch (e) {
    Logger.error('App', 'Failed to initialize notifications: $e');
  }

  // After Firebase.initializeApp()
  if (_isFirebaseInitialized) {
    Logger.info('App', 'Starting auth state monitoring...');
    try {
      AuthService().monitorAuthState();
      Logger.info('App', 'Auth state monitoring started');
    } catch (e) {
      Logger.error('App', 'Failed to start auth monitoring: $e');
    }
  }

  // Run the app regardless of Firebase status
  Logger.info('App', 'Launching app...');
  runApp(const MiloApp());
}

// Function to request all required permissions for the app
Future<void> requestRequiredPermissions() async {
  // For all Android versions, request storage permission
  if (Platform.isAndroid) {
    if (await Permission.storage.status != PermissionStatus.granted) {
      await Permission.storage.request();
      Logger.info('App', 'Storage permission requested');
    } else {
      Logger.info('App', 'Storage permission already granted');
    }

    // For Android 11+ (API 30+), request MANAGE_EXTERNAL_STORAGE permission
    try {
      if (!await Permission.manageExternalStorage.isGranted) {
        Logger.info('App', 'Requesting MANAGE_EXTERNAL_STORAGE permission');
        await Permission.manageExternalStorage.request();

        // Log the status after request
        final isGranted = await Permission.manageExternalStorage.isGranted;
        Logger.info('App', 'MANAGE_EXTERNAL_STORAGE permission status after request: ${isGranted ? 'granted' : 'denied'}');
      } else {
        Logger.info('App', 'MANAGE_EXTERNAL_STORAGE permission already granted');
      }
    } catch (e) {
      Logger.error('App', 'Error requesting permissions: $e');
    }
  }
}

class MiloApp extends StatefulWidget {
  const MiloApp({super.key});

  @override
  State<MiloApp> createState() => _MiloAppState();
}

class _MiloAppState extends State<MiloApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();

    // Register for app lifecycle events to improve error handling
    WidgetsBinding.instance.addObserver(this);

    // Check Google Play Services availability - but only if Firebase is initialized
    if (_isFirebaseInitialized) {
      // Add delay to avoid potential initialization conflicts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 2), () {
          _checkGooglePlayServices();
          _runFirebaseTests();
        });
      });
    }
  }

  @override
  void dispose() {
    // Unregister from app lifecycle events
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Log app lifecycle changes for debugging
    Logger.info('App', 'App lifecycle state changed to: $state');

    // Re-initialize services if the app is resumed
    if (state == AppLifecycleState.resumed) {
      Logger.info('App', 'App resumed, checking services...');
      _checkServicesOnResume();

      // Check permissions on resume as they might have changed
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkPermissionsOnResume();
      });
    }
  }

  // Check if all services are still operational after app resume
  void _checkServicesOnResume() async {
    try {
      // Verify Firebase connection is still active
      if (Firebase.apps.isNotEmpty) {
        Logger.info('App', 'Firebase is initialized');

        // Check authentication status
        final currentUser = FirebaseAuth.instance.currentUser;
        Logger.info('App', 'Current user: ${currentUser?.uid ?? 'Not signed in'}');
      } else {
        Logger.warning('App', 'Firebase is not initialized on resume');
      }
    } catch (e) {
      Logger.error('App', 'Error checking services on resume: $e');
    }
  }

  // Check permissions on app resume
  void _checkPermissionsOnResume() async {
    try {
      if (Platform.isAndroid) {
        final isStorageGranted = await Permission.storage.isGranted;
        Logger.info('App', 'Storage permission status on resume: ${isStorageGranted ? 'granted' : 'denied'}');

        final isManageStorageGranted = await Permission.manageExternalStorage.isGranted;
        Logger.info('App', 'MANAGE_EXTERNAL_STORAGE permission status on resume: ${isManageStorageGranted ? 'granted' : 'denied'}');

        // If permissions are still not granted, we might need to handle this
        if (!isManageStorageGranted && !isStorageGranted) {
          Logger.warning('App', 'Storage permissions still not granted on resume');
        }
      }
    } catch (e) {
      Logger.error('App', 'Error checking permissions on resume: $e');
    }
  }

  void _checkGooglePlayServices() async {
    if (kDebugMode && _isFirebaseInitialized) {
      try {
        // Simple test to check if we can access Firebase Analytics
        // This will indirectly test Google Play Services
        await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
        Logger.info('App', 'Google Play Services check succeeded');
      } catch (e) {
        Logger.error('App', 'Google Play Services check failed: $e');
        Logger.error('App', 'Google Play Services error details: ${e.toString()}');

        // Try to recover gracefully
        _attemptGooglePlayServicesRecovery();
      }
    }
  }

  void _attemptGooglePlayServicesRecovery() async {
    // This is a simple recovery mechanism for Google Play Services issues
    Logger.info('App', 'Attempting to recover from Google Play Services issue');

    try {
      // Make a simple Firebase query to test connectivity
      await FirebaseFirestore.instance.collection('_milo_system').doc('app_status').get();
      Logger.info('App', 'Basic Firebase functionality appears to be working despite Google Play Services issue');
    } catch (e) {
      Logger.error('App', 'Firebase connectivity also affected: $e');

      // Wait a moment and try initializing security provider again
      await Future.delayed(const Duration(seconds: 1));
      try {
        await http.get(Uri.parse('https://www.googleapis.com')).timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            return http.Response('Timeout', 408);
          },
        );
        Logger.info('App', 'Secondary security provider check completed');
      } catch (e) {
        Logger.warning('App', 'Secondary security provider initialization also failed: $e');
      }
    }
  }

  void _runFirebaseTests() async {
    if (kDebugMode && _isFirebaseInitialized) {
      Logger.info('App', 'Testing Firebase Analytics...');
      try {
        await FirebaseAnalytics.instance.logEvent(
          name: 'milo_app_launch',
          parameters: {
            'timestamp': DateTime.now().toString(),
            'app_version': '1.0.0',
          },
        );
        Logger.info('App', 'Analytics event logged successfully');
      } catch (e) {
        Logger.error('App', 'Analytics test failed: $e');
        Logger.error('App', 'Analytics error details: ${e.toString()}');
      }

      Logger.info('App', 'Testing Firestore connection...');
      try {
        await FirebaseFirestore.instance
            .collection('_milo_system')
            .doc('connectivity_test')
            .set({
          'last_test': FieldValue.serverTimestamp(),
          'device_info': 'Flutter debug build',
          'status': 'connected',
        });
        Logger.info('App', 'Firestore write successful');
      } catch (e) {
        Logger.error('App', 'Firestore test failed: $e');
        Logger.error('App', 'Firestore error details: ${e.toString()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Schedule Notifications when app launches - wrapped in try-catch
    try {
      NotificationService.scheduleCheckInNotifications();
      Logger.info('App', 'Scheduled notifications');
    } catch (e) {
      Logger.error('App', 'Failed to schedule notifications: $e');
    }

    return MultiProvider(
      providers: [
        // Auth service provider
        Provider<AuthService>(
          create: (_) => AuthService(),
        ),

        // OpenAI service provider
        Provider<OpenAIService>(
          create: (_) {
            final apiKey = AppConfig().openAIApiKey;
            if (apiKey == null || apiKey.isEmpty) {
              Logger.warning('App', 'OpenAI service initialized without API key');
              return OpenAIService(apiKey: '');
            }
            Logger.info('App', 'OpenAI service initialized with API key');
            return OpenAIService(apiKey: apiKey);
          },
        ),

        // Memory service provider
        Provider<MemoryService>(
          create: (context) => MemoryService(
            firestore: FirebaseFirestore.instance,
            storage: FirebaseStorage.instance,
            openAIService: Provider.of<OpenAIService>(context, listen: false),
          ),
          lazy: false,
        ),

        // Firebase providers
        Provider<FirebaseFirestore>(
          create: (_) => FirebaseFirestore.instance,
        ),
        Provider<FirebaseStorage>(
          create: (_) => FirebaseStorage.instance,
        ),

        // Auth state stream
        StreamProvider<User?>(
          create: (context) => Provider.of<AuthService>(context, listen: false).authStateChanges,
          initialData: null,
        ),
      ],
      child: MaterialApp(
        title: 'Milo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme, // Use our custom theme
        initialRoute: '/',
        routes: {
          '/': (context) => const AuthWrapper(),
          '/login': (context) => const LoginScreen(),
          '/signup': (context) => const SignupScreen(),
          '/record': (context) => const app_record.RecordMemoryScreen(),
          '/memories': (context) => const MemoriesScreen(),
          '/home': (context) => const HomeScreen(),
          '/conversation': (context) => const ConversationScreen(),
        },
        onGenerateRoute: (settings) {
          // Add debug logging for routes
          Logger.info('App', 'Navigating to: ${settings.name}');

          // Handle memory_detail route with parameter
          if (settings.name?.startsWith('/memory_detail/') == true) {
            // Extract memory ID from the route
            final memoryId = settings.name!.split('/').last;
            Logger.info('App', 'Opening memory detail for ID: $memoryId');

            return MaterialPageRoute(
              builder: (context) => MemoryDetailScreen(memoryId: memoryId),
            );
          }

          return null;
        },
        builder: (context, child) {
          // Add an error boundary for the whole app
          ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
            Logger.error('App', 'Caught Flutter error: ${errorDetails.exception}');
            Logger.error('App', 'Stack trace: ${errorDetails.stack}');

            // Return a custom error widget in release mode
            return kDebugMode
                ? ErrorWidget(errorDetails.exception)
                : Material(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: AppTheme.mutedRed, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Something went wrong',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeLarge,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please try again or restart the app',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeMedium,
                          color: AppTheme.textSecondaryColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.gentleTeal,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Return to Start'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          };

          return child!;
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Logger.debug('AuthWrapper', 'Build method called');

    return Consumer<User?>(
      builder: (context, user, _) {
        Logger.debug('AuthWrapper', 'Auth state updated, user: ${user?.uid}');

        // Always redirect to login if not authenticated
        if (user == null) {
          Logger.info('AuthWrapper', 'User not logged in, showing LoginScreen');
          return const LoginScreen();
        } else {
          Logger.info('AuthWrapper', 'User is logged in, showing HomeScreen. User ID: ${user.uid}');
          return const HomeScreen();
        }
      },
    );
  }
}