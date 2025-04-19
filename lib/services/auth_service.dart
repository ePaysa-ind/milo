// lib/services/auth_service.dart
import 'dart:async';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:milo/utils/advanced_logger.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

class AuthException implements Exception {
  final String message;
  final String code;
  final bool isRecoverable;

  AuthException({
    required this.message,
    this.code = 'unknown_error',
    this.isRecoverable = true,
  });

  @override
  String toString() => 'AuthException: $message (Code: $code)';
}

class AuthService {
  static const String _tag = 'AuthService';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // Keys for secure storage
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _emailKey = 'auth_email';
  static const String _saltKey = 'auth_salt';
  static const String _authTimeKey = 'auth_time';
  static const String _sessionKey = 'auth_session';

  // Keys for shared preferences
  static const String _rememberMeKey = 'remember_me';
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _mfaEnabledKey = 'mfa_enabled';

  // MFA verification code settings
  static const String _mfaVerificationCodeKey = 'mfa_verification_code';
  static const String _mfaVerificationTimeKey = 'mfa_verification_time';
  static const int _mfaCodeValidityMinutes = 10; // How long codes remain valid

  // Authentication session timeout (8 hours)
  static const int _sessionTimeoutHours = 8;

  // Failed login attempts tracking
  static const int _maxFailedAttempts = 5;
  static const String _failedAttemptsKey = 'failed_login_attempts';
  static const String _lastFailedAttemptKey = 'last_failed_attempt';
  static const int _lockoutMinutes = 15;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Session id for tracking
  String? _sessionId;

  // MFA verification flow flag
  bool _isMfaVerificationFlow = false;
  String? _pendingMfaEmail;

  // Generate a unique session ID
  String _generateSessionId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  // Monitor authentication state - call this in main.dart
  void monitorAuthState() {
    _auth.authStateChanges().listen((User? user) {
      if (user == null) {
        AdvancedLogger.info(_tag, 'User is currently signed out');
      } else {
        // Mask the email for security in logs
        final emailParts = user.email?.split('@') ?? ['unknown'];
        final maskedEmail = emailParts.length > 1
            ? '${emailParts[0].substring(0, min(3, emailParts[0].length))}***@${emailParts[1]}'
            : 'unknown@email.com';

        AdvancedLogger.info(_tag, 'User is signed in',
            data: {'uid': user.uid, 'email': maskedEmail});

        // Create new session when user signs in
        _createAuthSession(user.uid);
      }
    });

    // Also listen for user token changes
    _auth.idTokenChanges().listen((User? user) {
      if (user != null) {
        AdvancedLogger.info(_tag, 'User token refreshed',
            data: {'uid': user.uid});
      }
    });
  }

  // Create an authentication session
  Future<void> _createAuthSession(String userId) async {
    try {
      _sessionId = _generateSessionId();
      final authTime = DateTime.now().millisecondsSinceEpoch.toString();

      // Store session info
      await _secureStorage.write(key: _sessionKey, value: _sessionId);
      await _secureStorage.write(key: _authTimeKey, value: authTime);

      AdvancedLogger.info(_tag, 'Authentication session created',
          data: {'sessionId': _sessionId});

      // Log authentication event to Firestore for audit trail
      await _logAuthEvent(userId, 'login', {'sessionId': _sessionId});
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error creating auth session',
          error: e, stackTrace: stackTrace);
    }
  }

  // Log authentication events to Firestore
  Future<void> _logAuthEvent(String userId, String eventType, Map<String, dynamic> data) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('auth_logs')
          .add({
        'eventType': eventType,
        'timestamp': FieldValue.serverTimestamp(),
        'data': data,
        'platform': defaultTargetPlatform.toString(),
      });
    } catch (e) {
      AdvancedLogger.error(_tag, 'Failed to log auth event',
          data: {'eventType': eventType, 'userId': userId});
    }
  }

  // Check if the auth session is still valid
  Future<bool> isSessionValid() async {
    try {
      final authTimeString = await _secureStorage.read(key: _authTimeKey);
      if (authTimeString == null) return false;

      final authTime = int.tryParse(authTimeString) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Check if session has expired (8 hours)
      final elapsed = now - authTime;
      final hourInMillis = 60 * 60 * 1000;

      if (elapsed > _sessionTimeoutHours * hourInMillis) {
        AdvancedLogger.info(_tag, 'Auth session expired',
            data: {'elapsedHours': elapsed / hourInMillis});
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error checking session validity',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  // Check for account lockout due to failed attempts
  Future<bool> _isAccountLocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final attempts = prefs.getInt(_failedAttemptsKey) ?? 0;
      final lastAttemptTime = prefs.getInt(_lastFailedAttemptKey) ?? 0;

      if (attempts >= _maxFailedAttempts) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final minutesElapsed = (now - lastAttemptTime) / (1000 * 60);

        if (minutesElapsed < _lockoutMinutes) {
          AdvancedLogger.warning(_tag, 'Account temporarily locked due to failed attempts',
              data: {
                'attempts': attempts,
                'minutesRemaining': _lockoutMinutes - minutesElapsed.floor(),
              });
          return true;
        } else {
          // Reset counter if lockout period has passed
          await prefs.setInt(_failedAttemptsKey, 0);
        }
      }

      return false;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error checking account lockout',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  // Record a failed login attempt
  Future<void> _recordFailedAttempt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final attempts = prefs.getInt(_failedAttemptsKey) ?? 0;

      await prefs.setInt(_failedAttemptsKey, attempts + 1);
      await prefs.setInt(_lastFailedAttemptKey, DateTime.now().millisecondsSinceEpoch);

      AdvancedLogger.warning(_tag, 'Failed login attempt recorded',
          data: {'attemptCount': attempts + 1, 'maxAttempts': _maxFailedAttempts});
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error recording failed attempt',
          error: e, stackTrace: stackTrace);
    }
  }

  // Reset failed login attempts counter
  Future<void> _resetFailedAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_failedAttemptsKey, 0);
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error resetting failed attempts',
          error: e, stackTrace: stackTrace);
    }
  }

  // Sign up with email and password - FIXED method with error handling for type conversion
  Future<UserCredential> signUpWithEmailAndPassword(
      String email, String password, String name, int age) async {
    try {
      // Sanitize email for logging
      final maskedEmail = _maskEmail(email);
      AdvancedLogger.info(_tag, 'Attempting to create user',
          data: {'email': maskedEmail, 'name': name, 'age': age});

      // Check for existing user first
      try {
        final methods = await _auth.fetchSignInMethodsForEmail(email);
        if (methods.isNotEmpty) {
          AdvancedLogger.warning(_tag, 'Attempted to create account with existing email',
              data: {'email': maskedEmail});

          throw AuthException(
            message: 'This email address is already registered. Please sign in or use a different email.',
            code: 'email-already-in-use',
            isRecoverable: true,
          );
        }
      } catch (e) {
        AdvancedLogger.warning(_tag, 'Error checking existing email', error: e);
        // If the check fails, continue with account creation
        // The Firebase createUserWithEmailAndPassword will catch duplicates anyway
      }

      // Validate password strength
      _validatePasswordStrength(password);

      // Create user with email and password
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Add user details to Firestore after successful account creation
      if (userCredential.user != null) {
        final userId = userCredential.user!.uid;
        AdvancedLogger.info(_tag, 'User created successfully',
            data: {'uid': userId});

        try {
          // Store user profile in Firestore
          await _firestore.collection('users').doc(userId).set({
            'name': name,
            'email': email,
            'age': age,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
            'profileComplete': true,
            'mfaEnabled': false, // Starting with MFA disabled for simplicity
          });

          AdvancedLogger.info(_tag, 'User profile saved to Firestore');

          // Update display name
          await userCredential.user!.updateDisplayName(name);

          // Generate a secure salt for this user
          await _generateAndStoreSalt();

          // Set MFA preference
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_mfaEnabledKey, false);

          // Log signup event
          await _logAuthEvent(userId, 'signup', {
            'method': 'email',
            'age': age,
            'name': name.substring(0, min(3, name.length)) + '***'
          });
        } catch (firestoreError) {
          AdvancedLogger.error(_tag, 'Error saving user profile to Firestore',
              error: firestoreError);

          // Clean up: Delete the user if we can't save the profile
          try {
            await userCredential.user!.delete();
            AdvancedLogger.info(_tag, 'User account deleted after Firestore error');
          } catch (deleteError) {
            AdvancedLogger.error(_tag, 'Error deleting user after Firestore error',
                error: deleteError);
          }

          throw AuthException(
            message: 'Account created but profile could not be saved. Please try again.',
            code: 'profile_creation_error',
          );
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Firebase Auth Error during sign up',
          error: e, stackTrace: stackTrace,
          data: {'code': e.code, 'message': e.message});

      throw AuthException(
        message: _getReadableErrorMessage(e),
        code: e.code,
        isRecoverable: _isRecoverableError(e.code),
      );
    } on AuthException {
      // Pass through custom auth exceptions
      rethrow;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error during sign up',
          error: e, stackTrace: stackTrace);

      throw AuthException(
        message: 'An unexpected error occurred during sign up. Please try again.',
        code: 'unknown_error',
      );
    }
  }

  // Validate password strength
  void _validatePasswordStrength(String password) {
    List<String> weaknesses = [];
    // Check password length
    if (password.length < 8) {
      weaknesses.add('at least 8 characters long');
    }

    // Check for password complexity
    bool hasUppercase = password.contains(RegExp(r'[A-Z]'));
    bool hasLowercase = password.contains(RegExp(r'[a-z]'));
    bool hasDigits = password.contains(RegExp(r'[0-9]'));
    bool hasSpecialChars = password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));

    if (!hasUppercase) weaknesses.add('at least one uppercase letter');
    if (!hasLowercase) weaknesses.add('at least one lowercase letter');
    if (!hasDigits) weaknesses.add('at least one number');
    if (!hasSpecialChars) weaknesses.add('at least one special character (!@#\$%^&*(),.?":{}|<>)');

    if (weaknesses.isNotEmpty) {
      // Format the message nicely
      String message;
      if (weaknesses.length == 1) {
        message = 'Password must contain ${weaknesses[0]}';
      } else {
        final lastItem = weaknesses.removeLast();
        message = 'Password must contain ${weaknesses.join(", ")} and $lastItem';
      }
      throw AuthException(
        message: message,
        code: 'weak_password',
      );
    }
  }

  // Generate a more user-friendly error message
  String _getReadableErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email address is already registered. Please sign in or use a different email.';
      case 'invalid-email':
        return 'The email address format is invalid. Please check and try again.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled. Please contact support.';
      case 'weak-password':
        return 'The password provided is too weak. Please use a stronger password with at least 8 characters including uppercase letters, numbers, and special characters.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support for assistance';
      case 'user-not-found':
        return 'We couldn\'t find an account with this email. Please check your email or sign up.';
      case 'wrong-password':
        return 'Invalid email or password. Please try again with the correct email and password.';
      case 'too-many-requests':
        return 'Access to this account has been temporarily disabled due to many failed login attempts. Please try again later.';
      case 'network-request-failed':
        return 'A network error occurred. Please check your internet connection and try again.';
      case 'invalid-credential':
        return 'The login information you provided is incorrect. Please check your email and password.';
      default:
        return e.message ?? 'An unknown error occurred. Please try again.';
    }
  }

  // Determine if an error is potentially recoverable
  bool _isRecoverableError(String errorCode) {
    final nonRecoverableCodes = [
      'user-disabled',
      'operation-not-allowed',
    ];

    return !nonRecoverableCodes.contains(errorCode);
  }

  // MULTI-FACTOR AUTHENTICATION METHODS

  // Check if MFA is enabled for the current user
  Future<bool> isMfaEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_mfaEnabledKey) ?? false; // Default to false for better adoption
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error checking MFA status',
          error: e, stackTrace: stackTrace);
      return false; // Default to false to allow users to sign in
    }
  }

  // Enable or disable MFA
  Future<void> setMfaEnabled(bool enabled) async {
    try {
      if (currentUser == null) {
        throw AuthException(
          message: 'You must be signed in to change MFA settings',
          code: 'not_authenticated',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mfaEnabledKey, enabled);

      // Update user profile in Firestore
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'mfaEnabled': enabled,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      AdvancedLogger.info(_tag, 'MFA setting updated',
          data: {'enabled': enabled, 'uid': currentUser!.uid});

      // Log MFA setting change
      await _logAuthEvent(currentUser!.uid, 'mfa_setting_change', {'enabled': enabled});
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error updating MFA setting',
          error: e, stackTrace: stackTrace);
      throw AuthException(
        message: 'Failed to update MFA settings. Please try again.',
        code: 'mfa_setting_error',
      );
    }
  }

  // Generate a random 6-digit verification code
  String _generateVerificationCode() {
    final random = Random.secure();
    return (100000 + random.nextInt(900000)).toString(); // 6-digit code
  }

  // Send MFA verification code to user's email
  Future<void> sendMfaVerificationCode(String email) async {
    try {
      // Generate a 6-digit code
      final verificationCode = _generateVerificationCode();

      // Store the code securely (hashed) with a timestamp
      final secureCode = _hashVerificationCode(verificationCode);
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      await _secureStorage.write(key: _mfaVerificationCodeKey, value: secureCode);
      await _secureStorage.write(key: _mfaVerificationTimeKey, value: timestamp);

      // Set the email in pending verification
      _pendingMfaEmail = email;

      // Get user details if available for personalized email
      String userName = 'User';
      if (currentUser != null) {
        final userDoc = await _firestore.collection('users').doc(currentUser!.uid).get();
        if (userDoc.exists && userDoc.data()?['name'] != null) {
          userName = userDoc.data()!['name'];
        }
      }

      // Send verification code email (using your email service)
      await _sendVerificationEmail(email, verificationCode, userName);

      AdvancedLogger.info(_tag, 'MFA verification code sent',
          data: {'email': _maskEmail(email)});

      // Set MFA verification flow flag
      _isMfaVerificationFlow = true;

    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error sending MFA verification code',
          error: e, stackTrace: stackTrace);
      throw AuthException(
        message: 'Failed to send verification code. Please try again.',
        code: 'mfa_code_error',
      );
    }
  }

  // Send the verification email (implement with your email service)
  Future<void> _sendVerificationEmail(String email, String code, String userName) async {
    try {
      // Here you should integrate with your email sending service
      // For example, Firebase Cloud Functions, SendGrid, or another email service

      // For this example, we'll log this action and assume the email is sent
      AdvancedLogger.info(_tag, 'Sending verification email',
          data: {'email': _maskEmail(email), 'codeLength': code.length});

      // In a real implementation, you would send an actual email with the code
      // Example with Firebase Cloud Functions:
      /*
      await FirebaseFunctions.instance
          .httpsCallable('sendVerificationEmail')
          .call({
        'email': email,
        'code': code,
        'userName': userName,
      });
      */

      // For testing purposes, you might want to log the actual code in development
      // NEVER log actual codes in production!
      assert(() {
        // Only in debug mode
        AdvancedLogger.debug(_tag, 'TEST MODE: Generated verification code',
            data: {'code': code});
        return true;
      }());

    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error sending email',
          error: e, stackTrace: stackTrace);
      throw AuthException(
        message: 'Could not send verification email. Please try again.',
        code: 'email_send_error',
      );
    }
  }

  // Verify MFA code
  Future<bool> verifyMfaCode(String code) async {
    try {
      // Get stored verification code and timestamp
      final storedCodeHash = await _secureStorage.read(key: _mfaVerificationCodeKey);
      final timestampStr = await _secureStorage.read(key: _mfaVerificationTimeKey);

      if (storedCodeHash == null || timestampStr == null) {
        AdvancedLogger.warning(_tag, 'No verification code found');
        return false;
      }

      // Check if the code has expired
      final timestamp = int.tryParse(timestampStr) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final minutesElapsed = (now - timestamp) / (1000 * 60);

      if (minutesElapsed > _mfaCodeValidityMinutes) {
        AdvancedLogger.warning(_tag, 'Verification code expired',
            data: {'minutesElapsed': minutesElapsed.floor()});
        return false;
      }

      // Hash the provided code and compare with stored hash
      final hashedCode = _hashVerificationCode(code);
      final isValid = hashedCode == storedCodeHash;

      AdvancedLogger.info(_tag, 'MFA code verification',
          data: {'valid': isValid});

      // Clear verification data after verification
      if (isValid) {
        await _secureStorage.delete(key: _mfaVerificationCodeKey);
        await _secureStorage.delete(key: _mfaVerificationTimeKey);

        // Reset MFA verification flow flag
        _isMfaVerificationFlow = false;
      }

      return isValid;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error verifying MFA code',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  // Hash the verification code for secure storage
  String _hashVerificationCode(String code) {
    final bytes = utf8.encode(code);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  // The first step of sign-in process - SIMPLIFIED for easier adoption
  Future<void> initiateSignIn(String email, String password) async {
    try {
      // Check for account lockout
      if (await _isAccountLocked()) {
        final prefs = await SharedPreferences.getInstance();
        final lastAttemptTime = prefs.getInt(_lastFailedAttemptKey) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final minutesElapsed = (now - lastAttemptTime) / (1000 * 60);
        final minutesRemaining = _lockoutMinutes - minutesElapsed.floor();

        throw AuthException(
          message: 'Your account is temporarily locked due to too many failed login attempts. Please try again in $minutesRemaining minutes or reset your password.',
          code: 'account_locked',
          isRecoverable: false,
        );
      }

      // Sanitize email for logging
      final maskedEmail = _maskEmail(email);
      AdvancedLogger.info(_tag, 'Initiating sign in process',
          data: {'email': maskedEmail});

      // Simplified sign-in flow - try direct sign in
      try {
        final userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (userCredential.user != null) {
          final userId = userCredential.user!.uid;
          AdvancedLogger.info(_tag, 'User signed in successfully',
              data: {'uid': userId});

          // Reset failed attempts counter on successful login
          await _resetFailedAttempts();

          // Save remember me preference and email
          await saveCredentials(email, true);

          // Update last login timestamp
          await _firestore.collection('users').doc(userId).update({
            'lastLogin': FieldValue.serverTimestamp(),
          });

          // Create new auth session
          await _createAuthSession(userId);

          // Log login event
          await _logAuthEvent(userId, 'login', {
            'method': 'email',
          });
        }
      } on FirebaseAuthException catch (e) {
        AdvancedLogger.error(_tag, 'Firebase Auth Error during sign in',
            error: e, data: {'code': e.code, 'message': e.message});

        // Record failed attempt
        await _recordFailedAttempt();

        throw AuthException(
          message: _getReadableErrorMessage(e),
          code: e.code,
          isRecoverable: _isRecoverableError(e.code),
        );
      }
    } catch (e, stackTrace) {
      if (e is AuthException) {
        rethrow;
      }

      AdvancedLogger.error(_tag, 'Error during sign in',
          error: e, stackTrace: stackTrace);

      // Record failed attempt for unexpected errors
      await _recordFailedAttempt();

      throw AuthException(
        message: 'An unexpected error occurred during sign in. Please try again.',
        code: 'unknown_error',
      );
    }
  }

  // Sign in with email and password - SIMPLIFIED
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      // Sanitize email for logging
      final maskedEmail = _maskEmail(email);
      AdvancedLogger.info(_tag, 'Signing in with email and password',
          data: {'email': maskedEmail});

      // Direct Firebase sign in
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        final userId = credential.user!.uid;
        AdvancedLogger.info(_tag, 'User signed in successfully',
            data: {'uid': userId});

        // Reset failed attempts
        await _resetFailedAttempts();

        // Update last login timestamp
        await _firestore.collection('users').doc(userId).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });

        // Create auth session
        await _createAuthSession(userId);

        // Log login event
        await _logAuthEvent(userId, 'login', {'method': 'email'});
      }

      return credential;
    } on FirebaseAuthException catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Firebase Auth Error during sign in',
          error: e, stackTrace: stackTrace,
          data: {'code': e.code, 'message': e.message});

      // Record failed attempt
      await _recordFailedAttempt();

      throw AuthException(
        message: _getReadableErrorMessage(e),
        code: e.code,
        isRecoverable: _isRecoverableError(e.code),
      );
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error during sign in',
          error: e, stackTrace: stackTrace);

      // Record failed attempt
      await _recordFailedAttempt();

      throw AuthException(
        message: 'An unexpected error occurred during sign in. Please try again.',
        code: 'unknown_error',
      );
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      final userId = currentUser?.uid;

      // Clear stored credentials when signing out
      await clearStoredCredentials();

      // Log the sign-out event before actually signing out
      if (userId != null) {
        await _logAuthEvent(userId, 'logout', {'sessionId': _sessionId});
      }

      await _auth.signOut();

      AdvancedLogger.info(_tag, 'User signed out successfully');

      // Clear session
      _sessionId = null;
      await _secureStorage.delete(key: _sessionKey);
      await _secureStorage.delete(key: _authTimeKey);

    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error during sign out',
          error: e, stackTrace: stackTrace);

      throw AuthException(
        message: 'An error occurred while signing out. Please try again.',
        code: 'signout_error',
      );
    }
  }

  // Password reset
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      // Sanitize email for logging
      final maskedEmail = _maskEmail(email);
      AdvancedLogger.info(_tag, 'Sending password reset email',
          data: {'email': maskedEmail});

      await _auth.sendPasswordResetEmail(email: email);

      AdvancedLogger.info(_tag, 'Password reset email sent successfully');
    } on FirebaseAuthException catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Firebase Auth Error sending reset email',
          error: e, stackTrace: stackTrace,
          data: {'code': e.code, 'message': e.message});

      throw AuthException(
        message: _getReadableErrorMessage(e),
        code: e.code,
        isRecoverable: _isRecoverableError(e.code),
      );
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error sending password reset email',
          error: e, stackTrace: stackTrace);

      throw AuthException(
        message: 'An error occurred while sending the password reset email. Please try again.',
        code: 'reset_email_error',
      );
    }
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      if (currentUser != null) {
        final doc = await _firestore.collection('users').doc(currentUser!.uid).get();

        if (doc.exists) {
          AdvancedLogger.info(_tag, 'User profile retrieved successfully');
          return doc.data();
        } else {
          AdvancedLogger.warning(_tag, 'User profile document not found',
              data: {'uid': currentUser!.uid});
          return null;
        }
      }

      AdvancedLogger.warning(_tag, 'No current user, cannot retrieve profile');
      return null;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error getting user profile',
          error: e, stackTrace: stackTrace);

      throw AuthException(
        message: 'Failed to retrieve user profile. Please try again.',
        code: 'profile_retrieval_error',
      );
    }
  }

  // Update user profile
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    try {
      if (currentUser != null) {
        // Add last updated timestamp
        data['lastUpdated'] = FieldValue.serverTimestamp();

        await _firestore.collection('users').doc(currentUser!.uid).update(data);

        AdvancedLogger.info(_tag, 'User profile updated successfully',
            data: {'updatedFields': data.keys.toList()});

        // Update display name if provided
        if (data.containsKey('name')) {
          await currentUser!.updateDisplayName(data['name']);
          AdvancedLogger.info(_tag, 'Display name updated');
        }

        // Log profile update event
        await _logAuthEvent(currentUser!.uid, 'profile_update', {
          'updatedFields': data.keys.toList(),
        });
      } else {
        AdvancedLogger.warning(_tag, 'No current user, cannot update profile');
        throw AuthException(
          message: 'You must be signed in to update your profile.',
          code: 'not_authenticated',
        );
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error updating user profile',
          error: e, stackTrace: stackTrace);

      throw AuthException(
        message: 'Failed to update user profile. Please try again.',
        code: 'profile_update_error',
      );
    }
  }

  // PERSISTENT AUTHENTICATION METHODS

  /// Check if the user has valid credentials stored
  Future<bool> hasValidCredentials() async {
    try {
      final currentUser = _auth.currentUser;

      // If user is already logged in through Firebase, they're authenticated
      if (currentUser != null) {
        AdvancedLogger.info(_tag, 'User already authenticated in Firebase',
            data: {'uid': currentUser.uid});

        // Check if session is still valid
        if (!(await isSessionValid())) {
          AdvancedLogger.warning(_tag, 'Auth session expired, forcing re-login');
          await _auth.signOut();
          return false;
        }

        return true;
      }

      // Check for stored token (for future non-Firebase auth options)
      final token = await _secureStorage.read(key: _tokenKey);
      if (token != null) {
        AdvancedLogger.info(_tag, 'Found stored authentication token');

        // Here you could verify the token with your backend
        // and refresh it if needed

        // For now, we'll still check session validity
        if (!(await isSessionValid())) {
          AdvancedLogger.warning(_tag, 'Stored token session expired');
          await clearStoredCredentials();
          return false;
        }

        return true;
      }

      // Check if we have stored credentials and remember me is enabled
      final isRememberMeEnabled = await _isRememberMeEnabled();
      if (isRememberMeEnabled) {
        final email = await _secureStorage.read(key: _emailKey);

        if (email != null) {
          // Sanitize email for logging
          final maskedEmail = _maskEmail(email);
          AdvancedLogger.info(_tag, 'Found stored email, prompting for re-authentication',
              data: {'email': maskedEmail});

          // Return false to indicate manual login is required
          // But we'll pre-fill the email field for convenience
          return false;
        }
      }

      return false;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error checking credentials',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Save user email for auto-fill if remember me is enabled
  Future<void> saveCredentials(String email, bool rememberMe) async {
    try {
      // Always save the remember me preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberMeKey, rememberMe);

      if (rememberMe) {
        // Sanitize email for logging
        final maskedEmail = _maskEmail(email);
        AdvancedLogger.info(_tag, 'Saving email for later use',
            data: {'email': maskedEmail});

        // Save email in secure storage
        await _secureStorage.write(key: _emailKey, value: email);

        // If using Firebase Auth, also save the refresh token if available
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          final idTokenResult = await currentUser.getIdTokenResult();
          if (idTokenResult.token != null) {
            await _secureStorage.write(key: _tokenKey, value: idTokenResult.token);
            AdvancedLogger.info(_tag, 'Saved authentication token');
          }
        }
      } else {
        // If remember me is disabled, clear any stored credentials
        await clearStoredCredentials();
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error saving credentials',
          error: e, stackTrace: stackTrace);
    }
  }

  /// Clear all stored credentials
  Future<void> clearStoredCredentials() async {
    try {
      AdvancedLogger.info(_tag, 'Clearing stored credentials');

      await _secureStorage.delete(key: _tokenKey);
      await _secureStorage.delete(key: _refreshTokenKey);
      await _secureStorage.delete(key: _emailKey);
      await _secureStorage.delete(key: 'temp_password_hash');
      await _secureStorage.delete(key: 'temp_salt');
      // Don't delete the salt as it's used for password hashing

      // Do not clear the remember me preference itself
      AdvancedLogger.info(_tag, 'Credentials cleared successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error clearing credentials',
          error: e, stackTrace: stackTrace);
    }
  }

  /// Check if remember me is enabled
  Future<bool> _isRememberMeEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_rememberMeKey) ?? false;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error reading remember me preference',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Check if biometric authentication is enabled
  Future<bool> isBiometricEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_biometricEnabledKey) ?? false;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error reading biometric preference',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Enable or disable biometric authentication
  Future<void> setBiometricEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricEnabledKey, enabled);

      AdvancedLogger.info(_tag, 'Biometric authentication setting updated',
          data: {'enabled': enabled});
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error setting biometric preference',
          error: e, stackTrace: stackTrace);
    }
  }

  /// Generate a secure salt for password hashing
  Future<void> _generateAndStoreSalt() async {
    try {
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      final salt = base64Url.encode(values);

      await _secureStorage.write(key: _saltKey, value: salt);

      AdvancedLogger.info(_tag, 'Generated and stored new salt for password hashing');
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error generating salt',
          error: e, stackTrace: stackTrace);
    }
  }

  /// Get existing salt or create a new one
  Future<String> _getOrCreateSalt() async {
    final existingSalt = await _secureStorage.read(key: _saltKey);
    if (existingSalt != null) {
      return existingSalt;
    }

    // Generate new salt if none exists
    await _generateAndStoreSalt();
    return await _secureStorage.read(key: _saltKey) ?? '';
  }

  /// Hash the password with the salt using SHA-256
  String _hashPassword(String password, String salt) {
    final combinedBytes = utf8.encode(password + salt);
    final hash = sha256.convert(combinedBytes);
    return hash.toString();
  }

  /// Mask email for logging
  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length == 2) {
      final username = parts[0];
      final domain = parts[1];

      // Keep first 3 chars of username and mask the rest
      final maskedUsername = username.length <= 3
          ? username
          : '${username.substring(0, 3)}${'*' * (username.length - 3)}';

      return '$maskedUsername@$domain';
    }
    return email;
  }

  /// For testing: Get password from user - NOT USED in production
  Future<String> _getPasswordFromUser() async {
    // This is just a placeholder method to make the code compile
    // In a real app, you would have a UI prompt for the password
    // or some secure way to store and retrieve it
    throw AuthException(
      message: 'This method is not implemented in production',
      code: 'not_implemented',
    );
  }

  /// For testing: Complete sign-in - NOT USED in production
  Future<UserCredential> completeSignIn(String? verificationCode) async {
    // This is just a placeholder method to make the code compile
    // In a real app, this would be implemented differently
    throw AuthException(
      message: 'This method is not implemented in production',
      code: 'not_implemented',
    );
  }
}