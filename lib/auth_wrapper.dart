// lib/auth_wrapper.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:milo/screens/login_screen.dart';
import 'package:milo/services/auth_service.dart';  // Updated to use AuthService
import 'package:milo/utils/logger.dart';
import 'home_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();  // Using AuthService instead of AuthManager
  bool _isCheckingPersistentAuth = true;

  @override
  void initState() {
    super.initState();
    _checkPersistentAuth();
  }

  // Check for persistent authentication before showing the login screen
  Future<void> _checkPersistentAuth() async {
    Logger.info('AuthWrapper', 'Checking for persistent authentication');

    try {
      final hasValidCredentials = await _authService.hasValidCredentials();

      if (mounted) {
        setState(() {
          _isCheckingPersistentAuth = false;
        });
      }

      // Note: if hasValidCredentials is true, the user will already be
      // authenticated in Firebase, so the StreamBuilder will handle navigation
    } catch (e) {
      Logger.error('AuthWrapper', 'Error checking persistent auth: $e');
      if (mounted) {
        setState(() {
          _isCheckingPersistentAuth = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If still checking persistent auth, show loading screen
    if (_isCheckingPersistentAuth) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Once persistent auth check is complete, use StreamBuilder to listen for auth state changes
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData) {
          Logger.info('AuthWrapper', 'User authenticated, showing HomeScreen');
          // User is signed in, show the app
          return const HomeScreen();
        } else {
          Logger.info('AuthWrapper', 'User not authenticated, showing LoginScreen');
          // User is not signed in, show login screen
          return const LoginScreen();
        }
      },
    );
  }
}