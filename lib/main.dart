// 📄 lib/main.dart
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'record_memory_screen.dart';
import 'memories_screen.dart';
import 'notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Added for direct access
import 'package:milo/screens/login_screen.dart';
import 'package:milo/screens/signup_screen.dart';
import 'package:milo/services/auth_service.dart';

void main() async {
  // This needs to be called only once
  WidgetsFlutterBinding.ensureInitialized();
  print('🔍 Flutter binding initialized');

  // Initialize notifications first
  try {
    await NotificationService.init();
    print('✅ Notification service initialized');
  } catch (e) {
    print('❌ Failed to initialize notifications: $e');
  }

  // Initialize Firebase with error handling
  bool firebaseInitialized = false;
  try {
    print('🔍 Attempting to initialize Firebase...');
    await Firebase.initializeApp();
    firebaseInitialized = true;
    print('✅ Firebase core initialized successfully');

    // Force sign out for testing
    try {
      await FirebaseAuth.instance.signOut();
      print('🔑 Forced user sign out for testing');
    } catch (e) {
      print('⚠️ Error during forced sign out: $e');
    }

    // After Firebase.initializeApp()
    print('🔍 Starting auth state monitoring...');
    try {
      AuthService().monitorAuthState();
      print('✅ Auth state monitoring started');
    } catch (e) {
      print('❌ Failed to start auth monitoring: $e');
    }

    // Test Analytics only if Firebase is initialized
    if (firebaseInitialized && kDebugMode) {
      print('🔍 Testing Firebase Analytics...');
      try {
        await FirebaseAnalytics.instance.logEvent(
          name: 'milo_app_launch',
          parameters: {
            'timestamp': DateTime.now().toString(),
            'app_version': '1.0.0',
          },
        );
        print('✅ Analytics event logged successfully');

        print('🔍 Testing Firestore connection...');
        try {
          await FirebaseFirestore.instance
              .collection('_milo_system')
              .doc('connectivity_test')
              .set({
            'last_test': FieldValue.serverTimestamp(),
            'device_info': 'Flutter debug build',
            'status': 'connected',
          });
          print('✅ Firestore write successful');
        } catch (e) {
          print('❌ Firestore test failed: $e');
          print('❌ Firestore error details: ${e.toString()}');
        }
      } catch (e) {
        print('❌ Analytics test failed: $e');
        print('❌ Analytics error details: ${e.toString()}');
      }
    }
  } catch (e) {
    print('❌ Failed to initialize Firebase: $e');
    print('❌ Firebase error details: ${e.toString()}');
  }

  // Run the app regardless of Firebase status
  print('🔍 Launching app...');
  runApp(const MiloApp());
}

class MiloApp extends StatelessWidget {
  const MiloApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Schedule Notifications when app launches - wrapped in try-catch
    try {
      NotificationService.scheduleCheckInNotifications();
      print('✅ Scheduled notifications');
    } catch (e) {
      print('❌ Failed to schedule notifications: $e');
    }

    return MaterialApp(
      title: 'Milo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFE8F6F3),
      ),
      // You can't have both initialRoute and home
      // home: const LoginScreen(),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/record': (context) => const RecordMemoryScreen(),
        '/memories': (context) => const MemoriesScreen(),
        '/home': (context) => const HomeScreen(),
      },
      onGenerateRoute: (settings) {
        // Add debug logging for routes
        print('🚀 Navigating to: ${settings.name}');
        return null;
      },
    );
  }
}

// Debug version of AuthWrapper - keeping for reference
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print('🔍 AuthWrapper build method called');

    // For debugging: temporary direct route to login
    // Enable this for direct access to login screen
    // return const LoginScreen();

    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        print('🔍 Auth state snapshot: ${snapshot.connectionState}, hasData: ${snapshot.hasData}');

        if (snapshot.connectionState == ConnectionState.waiting) {
          print('🔍 Auth state is waiting');
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Checking login status...'),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          print('❌ Auth stream error: ${snapshot.error}');
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Authentication Error', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 8),
                  Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    child: const Text('Go to Login'),
                  ),
                ],
              ),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          print('🔍 User is not logged in, showing LoginScreen');
          return const LoginScreen();
        } else {
          print('✅ User is logged in, showing HomeScreen. User ID: ${user.uid}');
          return const HomeScreen();
        }
      },
    );
  }
}