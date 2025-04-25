// Copyright © 2025 Milo Team. All rights reserved.
// lib/services/auth_service.dart
// 1.1.3, Created: April 24, 2025
// fixed <type> due to FB limitations, stacktrace, cookies
// Updated sign-in methods to use set(merge: true) for robustness

import 'dart:async';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:milo/utils/logger.dart';
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

  // Freemium session timeout (5 minutes)
  static const int _freemiumSessionTimeoutMinutes = 5;
  static const int _freemiumMaxLogins = 4;

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

  // Session timer reference
  Timer? _sessionTimer;

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
        Logger.info(_tag, 'User is currently signed out');
        _sessionTimer?.cancel(); // Ensure timer stops on external sign out
        // Clear local session data if needed on external sign out
        _clearSessionData();
      } else {
        // Mask the email for security in logs
        final emailParts = user.email?.split('@') ?? ['unknown'];
        final maskedEmail = emailParts.length > 1
            ? '${emailParts[0].substring(0, min(3, emailParts[0].length))}***@${emailParts[1]}'
            : 'unknown@email.com';

        Logger.info(_tag, 'User is signed in with UID: ${user.uid}, email: $maskedEmail');

        // Create new session when user signs in (if not already created by login flow)
        // Check if session exists before creating a new one might be better
        _createAuthSession(user.uid);
      }
    });

    // Also listen for user token changes
    _auth.idTokenChanges().listen((User? user) {
      if (user != null) {
        Logger.info(_tag, 'User token refreshed with UID: ${user.uid}');
        // Optionally refresh stored token if needed
      }
    });
  }

  // Create an authentication session
  Future<void> _createAuthSession(String userId) async {
    // Consider adding a check if a session already exists and is valid
    // if (_sessionId != null && await isAuthSessionValid()) return;

    try {
      _sessionId = _generateSessionId();
      final authTime = DateTime.now().millisecondsSinceEpoch.toString();

      // Store session info
      await _secureStorage.write(key: _sessionKey, value: _sessionId);
      await _secureStorage.write(key: _authTimeKey, value: authTime);

      Logger.info(_tag, 'Authentication session created with session ID: $_sessionId');

      // Log authentication event to Firestore for audit trail
      // Moved this logging into the sign-in methods themselves to ensure it happens after specific login actions
      // await _logAuthEvent(userId, 'login', {'sessionId': _sessionId});
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error creating auth session: $e\n$stackTrace');
    }
  }

  // Helper to clear local session data
  Future<void> _clearSessionData() async {
    _sessionId = null;
    await _secureStorage.delete(key: _sessionKey);
    await _secureStorage.delete(key: _authTimeKey);
    // Consider if other secure storage keys should be cleared on sign out
    // await clearStoredCredentials(); // Maybe call this instead?
  }

  // Log authentication events to Firestore
  Future<void> _logAuthEvent(String userId, String eventType, Map<String, dynamic> eventData) async {
    try {
      // Ensure eventData is not null and potentially add session ID automatically
      final dataToLog = Map<String, dynamic>.from(eventData); // Create mutable copy
      dataToLog['sessionId'] ??= _sessionId; // Add session ID if not already present

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('auth_logs')
          .add({
        'eventType': eventType,
        'timestamp': FieldValue.serverTimestamp(),
        'eventData': dataToLog, // Use the potentially modified map
        'platform': defaultTargetPlatform.toString(),
      });
    } catch (e) {
      // Consider propagating this error or handling it more visibly if logs are critical
      Logger.error(_tag, 'Failed to log auth event ($eventType) for user $userId: $e');
    }
  }

  // ==========================================================================
  // FREEMIUM SESSION MANAGEMENT
  // ==========================================================================

  Future<void> trackLogin() async {
    // This function likely needs to be called explicitly after a successful login
    // from initiateSignIn or signInWithEmailAndPassword if freemium tracking is needed.
    try {
      final user = currentUser; // Use the getter
      if (user == null) return;

      final userId = user.uid;

      final isPremium = await _isPremiumUser(userId);
      if (isPremium) {
        Logger.info(_tag, 'Premium user login - not tracking usage limits');
        return;
      }

      final metricsRef = _firestore.collection('userMetrics').doc(userId);

      // Use a transaction for reliable read-modify-write
      await _firestore.runTransaction((transaction) async {
        final metricsDoc = await transaction.get(metricsRef);

        if (metricsDoc.exists) {
          final currentCount = metricsDoc.data()?['loginCount'] ?? 0;
          transaction.update(metricsRef, {
            'loginCount': currentCount + 1,
            'lastLogin': FieldValue.serverTimestamp()
          });
          Logger.info(_tag, 'Login count updated to ${currentCount + 1} of $_freemiumMaxLogins maximum');
          if (currentCount + 1 >= _freemiumMaxLogins) {
            Logger.warning(_tag, 'User has reached free login limit');
          }
        } else {
          transaction.set(metricsRef, {
            'loginCount': 1,
            'lastLogin': FieldValue.serverTimestamp()
          });
          Logger.info(_tag, 'First login recorded');
        }
      });

      await _startSessionTimer(); // Start timer after successful tracking

    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error tracking login: $e\n$stackTrace');
    }
  }

  Future<bool> _isPremiumUser(String userId) async {
    try {
      final premiumDoc = await _firestore.collection('premiumUsers').doc(userId).get();
      return premiumDoc.exists;
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error checking premium status: $e\n$stackTrace');
      return false; // Assume not premium on error
    }
  }

  Future<void> _startSessionTimer() async {
    try {
      final user = currentUser;
      if (user == null) return;

      // Don't start timer for premium users
      if (await _isPremiumUser(user.uid)) return;

      _sessionTimer?.cancel(); // Cancel existing timer

      final userId = user.uid; // Use user.uid directly

      final expirationTime = DateTime.now().add(
          Duration(minutes: _freemiumSessionTimeoutMinutes)
      ).millisecondsSinceEpoch;

      // Record session start time and expiration in Firestore
      // Consider if this write is necessary or if client-side timer is sufficient
      await _firestore.collection('userSessions').doc(userId).set({
        'lastLogin': FieldValue.serverTimestamp(),
        'expiresAt': expirationTime
      }, SetOptions(merge: true)); // Use set merge here too potentially

      Logger.info(_tag, 'Freemium session started with timeout of $_freemiumSessionTimeoutMinutes minutes');

      _sessionTimer = Timer(
          Duration(minutes: _freemiumSessionTimeoutMinutes),
              () {
            // Check if the SAME user is still logged in before logging out
            if (currentUser != null && currentUser!.uid == userId) {
              Logger.info(_tag, 'Freemium session timeout - logging out user $userId');
              signOut(); // Call sign out
            } else {
              Logger.info(_tag, 'Freemium session timer expired, but user already changed/logged out.');
            }
          }
      );
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error starting session timer: $e\n$stackTrace');
    }
  }

  Future<bool> hasReachedLoginLimit() async {
    try {
      final user = currentUser;
      if (user == null) return false; // No user, no limit reached

      final isPremium = await _isPremiumUser(user.uid);
      if (isPremium) {
        Logger.info(_tag, 'Premium user - no login limits');
        return false;
      }

      final metricsDoc = await _firestore.collection('userMetrics')
          .doc(user.uid).get();

      if (!metricsDoc.exists) {
        Logger.info(_tag, 'No metrics found, limit not reached.');
        return false;
      }

      final loginCount = metricsDoc.data()?['loginCount'] ?? 0;
      final hasReachedLimit = loginCount >= _freemiumMaxLogins;

      if (hasReachedLimit) {
        Logger.warning(_tag, 'User ${user.uid} has reached free login limit of $_freemiumMaxLogins');
      }
      return hasReachedLimit;
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error checking login limit: $e\n$stackTrace');
      return false; // Default to false on error
    }
  }

  Future<bool> isSessionValid() async {
    // This checks the freemium 5-minute timer, NOT the main 8-hour auth session
    try {
      final user = currentUser;
      if (user == null) return false;

      final isPremium = await _isPremiumUser(user.uid);
      if (isPremium) {
        Logger.info(_tag, 'Premium user - freemium session always valid');
        return true;
      }

      // Client-side check is likely sufficient if timer is running
      if (_sessionTimer != null && _sessionTimer!.isActive) {
        return true;
      }

      // Optional: Check Firestore as fallback (adds latency)
      /*
      final sessionDoc = await _firestore.collection('userSessions')
          .doc(user.uid).get();
      if (!sessionDoc.exists) {
        Logger.warning(_tag, 'No session record found in Firestore for freemium check.');
        return false;
      }
      final expiresAt = sessionDoc.data()?['expiresAt'] as int?;
      if (expiresAt == null) {
         Logger.warning(_tag, 'Session missing expiration timestamp.');
         return false;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final isValid = now < expiresAt;
       if (!isValid) {
         Logger.info(_tag, 'Freemium session expired based on Firestore record.');
       }
       return isValid;
       */

      // If timer isn't active, assume session expired
      Logger.info(_tag, 'Freemium session timer not active.');
      return false;

    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error checking freemium session validity: $e\n$stackTrace');
      return false; // Default to invalid on error
    }
  }

  // ==========================================================================
  // STANDARD SESSION / LOCKOUT / CREDENTIALS
  // ==========================================================================

  Future<bool> isAuthSessionValid() async {
    // Checks the main 8-hour session based on secure storage time
    try {
      final authTimeString = await _secureStorage.read(key: _authTimeKey);
      if (authTimeString == null) {
        Logger.info(_tag, 'No auth time found in secure storage.');
        return false;
      }

      final authTime = int.tryParse(authTimeString);
      if (authTime == null) {
        Logger.warning(_tag, 'Invalid auth time format found.');
        await _secureStorage.delete(key: _authTimeKey); // Clean up invalid data
        return false;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - authTime;
      final sessionDurationMillis = _sessionTimeoutHours * 60 * 60 * 1000;

      if (elapsed > sessionDurationMillis) {
        Logger.info(_tag, 'Auth session expired after ${elapsed / (60 * 60 * 1000)} hours');
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error checking auth session validity: $e\n$stackTrace');
      return false; // Default to invalid on error
    }
  }

  Future<bool> _isAccountLocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final attempts = prefs.getInt(_failedAttemptsKey) ?? 0;
      final lastAttemptTime = prefs.getInt(_lastFailedAttemptKey); // Can be null

      if (attempts >= _maxFailedAttempts && lastAttemptTime != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final lockoutDurationMillis = _lockoutMinutes * 60 * 1000;

        if ((now - lastAttemptTime) < lockoutDurationMillis) {
          final minutesRemaining = _lockoutMinutes - ((now - lastAttemptTime) / (1000 * 60)).floor();
          Logger.warning(_tag, 'Account temporarily locked. Attempts: $attempts. Minutes remaining: $minutesRemaining');
          return true;
        } else {
          // Lockout period has passed, reset counter before allowing login attempt
          Logger.info(_tag, 'Lockout period expired, resetting attempts.');
          await _resetFailedAttempts(); // Use the reset method
        }
      }
      return false;
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error checking account lockout: $e\n$stackTrace');
      return false; // Default to not locked on error
    }
  }

  Future<void> _recordFailedAttempt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Use null-aware operator and default value
      final attempts = (prefs.getInt(_failedAttemptsKey) ?? 0) + 1;
      await prefs.setInt(_failedAttemptsKey, attempts);
      await prefs.setInt(_lastFailedAttemptKey, DateTime.now().millisecondsSinceEpoch);
      Logger.warning(_tag, 'Failed login attempt recorded: $attempts of $_maxFailedAttempts maximum');
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error recording failed attempt: $e\n$stackTrace');
    }
  }

  Future<void> _resetFailedAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_failedAttemptsKey); // Use remove instead of setting to 0
      await prefs.remove(_lastFailedAttemptKey);
      Logger.info(_tag, 'Failed login attempts counter reset successfully');
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error resetting failed attempts: $e\n$stackTrace');
    }
  }

  Future<void> resetLoginAttempts() async {
    // Public access to reset logic
    await _resetFailedAttempts();
  }

  // ===================================================================
  // SIGN UP METHOD
  // ===================================================================
  Future<UserCredential> signUpWithEmailAndPassword(
      String email, String password, String name, int age) async {
    // Note: This method is kept largely as provided, assuming its logic is intended.
    // The primary fix was needed in the sign-in methods.
    try {
      final maskedEmail = _maskEmail(email);
      Logger.info(_tag, 'Attempting sign up: $maskedEmail, name: $name');

      // Check for existing user first
      try {
        final methods = await _auth.fetchSignInMethodsForEmail(email);
        if (methods.isNotEmpty) {
          Logger.warning(_tag, 'Sign up attempt with existing email: $maskedEmail');
          throw AuthException(
            message: 'This email address is already registered. Please sign in or use a different email.',
            code: 'email-already-in-use',
            isRecoverable: true,
          );
        }
      } on FirebaseAuthException catch (e) {
        // Handle specific auth exceptions during check if necessary
        Logger.warning(_tag, 'FirebaseAuthException checking existing email ($maskedEmail): ${e.code}');
        // Decide if specific codes should halt signup (e.g., network error)
        if (e.code == 'invalid-email') throw AuthException(message: _getReadableErrorMessage(e), code: e.code);
        // Otherwise, proceed, createUserWithEmailAndPassword will handle 'email-already-in-use' definitively.
      } catch (e) {
        Logger.warning(_tag, 'Non-Firebase error checking existing email ($maskedEmail): $e');
        // Proceed with caution, createUserWithEmailAndPassword is the final check.
      }

      _validatePasswordStrength(password);

      UserCredential? userCredential; // Make nullable
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        // Catch specific auth errors during creation itself
        Logger.error(_tag, 'FirebaseAuthException during createUser: ${e.code}');
        throw AuthException(message: _getReadableErrorMessage(e), code: e.code, isRecoverable: _isRecoverableError(e.code));
      } on TypeError catch (e, stackTrace) {
        // This catch block specifically handles the Pigeon type error if it occurs during creation
        Logger.error(_tag, 'Type error during user creation (Pigeon?): $e\n$stackTrace');
        throw AuthException(
          message: 'Authentication system error during user creation. Please try again later.',
          code: 'auth_type_error',
        );
      }
      // Note: removed the outer generic try-catch for userCredential assignment

      // Process successful creation
      final user = userCredential.user; // Nullable User?

      if (user != null) {
        final userId = user.uid; // Safe access inside null check
        Logger.info(_tag, 'User created successfully with UID: $userId');

        // Removed delay, generally not needed unless specific timing issue known
        // await Future.delayed(const Duration(milliseconds: 500));

        try {
          // Set user profile in Firestore - this uses .set() which is correct for creation
          await _firestore.collection('users').doc(userId).set({
            'name': name,
            'email': email, // Use original email from args, as user.email might be null briefly
            'age': age,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(), // Set initial lastLogin
            'lastUpdated': FieldValue.serverTimestamp(),
            'profileComplete': true, // Example field
            'mfaEnabled': false, // Default
          });
          Logger.info(_tag, 'User profile saved to Firestore for $userId');

          // Update display name (best effort)
          try {
            await user.updateDisplayName(name);
          } catch (e) {
            Logger.warning(_tag, 'Failed to update display name for $userId: $e');
          }

          // Generate salt (best effort)
          try {
            await _generateAndStoreSalt();
          } catch (e) {
            Logger.warning(_tag, 'Failed to generate/store salt for $userId: $e');
          }

          // Set local prefs (best effort)
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_mfaEnabledKey, false);
          } catch (e) {
            Logger.warning(_tag, 'Failed to save MFA pref for $userId: $e');
          }

          // Log signup event
          await _logAuthEvent(userId, 'signup', {
            'method': 'email',
            'age': age, // Consider privacy implications of logging age
            'namePrefix': name.isNotEmpty ? name.substring(0, min(3, name.length)) + '***' : '***'
          });

        } catch (firestoreError, stackTrace) { // Catch specific Firestore errors during set
          Logger.error(_tag, 'Error saving user profile to Firestore for $userId: $firestoreError\n$stackTrace');
          // Clean up: Attempt to delete the Auth user since profile failed
          try {
            await user.delete();
            Logger.info(_tag, 'User account $userId deleted after Firestore profile save error');
          } catch (deleteError) {
            Logger.error(_tag, 'CRITICAL: Error deleting user $userId after Firestore error: $deleteError. Manual cleanup needed.');
            // Throw a more critical error?
          }
          // Throw specific exception indicating profile save failure
          throw AuthException(
            message: 'Your account was created, but saving your profile failed. Please try signing up again.',
            code: 'profile_creation_error',
          );
        }
      } else {
        // This case should ideally not be reached if createUser returns without error but null user
        Logger.error(_tag, 'User creation successful but User object is null.');
        throw AuthException(
          message: 'Account creation failed unexpectedly. Please try again.',
          code: 'unknown_creation_error',
        );
      }

      return userCredential; // Return the original credential

    } on FirebaseAuthException catch (e, stackTrace) {
      // Handle exceptions specifically from initial email check or createUser
      Logger.error(_tag, 'FirebaseAuthException during sign up process: ${e.code}\n$stackTrace');
      throw AuthException(
        message: _getReadableErrorMessage(e),
        code: e.code,
        isRecoverable: _isRecoverableError(e.code),
      );
    } on AuthException {
      // Re-throw custom exceptions (like email-already-in-use, weak_password, profile_creation_error)
      rethrow;
    } on TypeError catch (e, stackTrace) {
      // Catch TypeErrors that might occur outside the specific creation block
      Logger.error(_tag, 'Type casting error during sign up: $e\n$stackTrace');
      throw AuthException(
        message: 'A technical issue occurred during signup. Please try again later.',
        code: 'type_error', // Generic type error code
        isRecoverable: true,
      );
    } catch (e, stackTrace) {
      // Catch-all for other unexpected errors
      Logger.error(_tag, 'Unexpected error during sign up: $e\n$stackTrace');
      throw AuthException(
        message: 'An unexpected error occurred during sign up. Please try again.',
        code: 'unknown_signup_error', // More specific code
      );
    }
  }

  // ===================================================================
  // SIGN UP HELPER METHODS
  // ===================================================================

  void _validatePasswordStrength(String password) {
    List<String> weaknesses = [];
    if (password.length < 8) weaknesses.add('at least 8 characters long');
    if (!password.contains(RegExp(r'[A-Z]'))) weaknesses.add('at least one uppercase letter');
    if (!password.contains(RegExp(r'[a-z]'))) weaknesses.add('at least one lowercase letter');
    if (!password.contains(RegExp(r'[0-9]'))) weaknesses.add('at least one number');
    if (!password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) weaknesses.add('at least one special character (!@#\$%^&*(),.?":{}|<>)');

    if (weaknesses.isNotEmpty) {
      String message;
      if (weaknesses.length == 1) {
        message = 'Password must contain ${weaknesses[0]}.';
      } else {
        final lastItem = weaknesses.removeLast();
        message = 'Password must contain ${weaknesses.join(", ")}, and $lastItem.';
      }
      throw AuthException(message: message, code: 'weak-password');
    }
  }

  String _getReadableErrorMessage(FirebaseAuthException e) {
    // Kept as provided, seems reasonable
    switch (e.code) {
      case 'email-already-in-use': return 'This email address is already registered. Please sign in or use a different email.';
      case 'invalid-email': return 'The email address format is invalid. Please check and try again.';
      case 'operation-not-allowed': return 'Email/password accounts are not enabled. Please contact support.';
      case 'weak-password': return 'The password provided is too weak. Please use a stronger password with at least 8 characters including uppercase letters, numbers, and special characters.';
      case 'user-disabled': return 'This account has been disabled. Please contact support for assistance.';
      case 'user-not-found': return 'We couldn\'t find an account with this email. Please check your email or sign up.';
      case 'wrong-password': return 'Invalid email or password. Please try again with the correct email and password.';
      case 'too-many-requests': return 'Access to this account has been temporarily disabled due to many failed login attempts. Please try again later or reset your password.';
      case 'network-request-failed': return 'A network error occurred. Please check your internet connection and try again.';
      case 'invalid-credential': return 'The login information you provided is incorrect. Please check your email and password.';
    // Add more specific cases if needed based on Firebase docs
      default: return e.message ?? 'An unknown authentication error occurred. Please try again.';
    }
  }

  bool _isRecoverableError(String errorCode) {
    // Kept as provided
    final nonRecoverableCodes = ['user-disabled', 'operation-not-allowed'];
    return !nonRecoverableCodes.contains(errorCode);
  }


  // ==========================================================================
  // MFA METHODS - Kept as provided, review if MFA flow is used
  // ==========================================================================

  Future<bool> isMfaEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_mfaEnabledKey) ?? false; // Default to false for better adoption
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error checking MFA status: $e\n$stackTrace');
      return false; // Default to false to allow users to sign in
    }
  }

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

      Logger.info(_tag, 'MFA setting updated to: $enabled for user: ${currentUser!.uid}');

      // Log MFA setting change
      await _logAuthEvent(currentUser!.uid, 'mfa_setting_change', {'enabled': enabled});
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error updating MFA setting: $e\n$stackTrace');
      throw AuthException(
        message: 'Failed to update MFA settings. Please try again.',
        code: 'mfa_setting_error',
      );
    }
  }

  String _generateVerificationCode() {
    final random = Random.secure();
    return (100000 + random.nextInt(900000)).toString(); // 6-digit code
  }

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
          userName = userDoc.data()!['name'] as String;
        }
      }

      // Send verification code email (using your email service)
      await _sendVerificationEmail(email, verificationCode, userName);

      Logger.info(_tag, 'MFA verification code sent to: ${_maskEmail(email)}');

      // Set MFA verification flow flag
      _isMfaVerificationFlow = true;

    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error sending MFA verification code: $e\n$stackTrace');
      throw AuthException(
        message: 'Failed to send verification code. Please try again.',
        code: 'mfa_code_error',
      );
    }
  }

  Future<void> _sendVerificationEmail(String email, String code, String userName) async {
    try {
      // Here you should integrate with your email sending service
      // For example, Firebase Cloud Functions, SendGrid, or another email service

      // For this example, we'll log this action and assume the email is sent
      Logger.info(_tag, 'Sending verification email to: ${_maskEmail(email)}, code length: ${code.length}');

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
        Logger.debug(_tag, 'TEST MODE: Generated verification code: $code');
        return true;
      }());

    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error sending email: $e\n$stackTrace');
      throw AuthException(
        message: 'Could not send verification email. Please try again.',
        code: 'email_send_error',
      );
    }
  }

  Future<bool> verifyMfaCode(String code) async {
    try {
      // Get stored verification code and timestamp
      final storedCodeHash = await _secureStorage.read(key: _mfaVerificationCodeKey);
      final timestampStr = await _secureStorage.read(key: _mfaVerificationTimeKey);

      if (storedCodeHash == null || timestampStr == null) {
        Logger.warning(_tag, 'No verification code found');
        return false;
      }

      // Check if the code has expired
      final timestamp = int.tryParse(timestampStr) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final minutesElapsed = (now - timestamp) / (1000 * 60);

      if (minutesElapsed > _mfaCodeValidityMinutes) {
        Logger.warning(_tag, 'Verification code expired after $minutesElapsed minutes');
        return false;
      }

      // Hash the provided code and compare with stored hash
      final hashedCode = _hashVerificationCode(code);
      final isValid = hashedCode == storedCodeHash;

      Logger.info(_tag, 'MFA code verification result: $isValid');

      // Clear verification data after verification
      if (isValid) {
        await _secureStorage.delete(key: _mfaVerificationCodeKey);
        await _secureStorage.delete(key: _mfaVerificationTimeKey);

        // Reset MFA verification flow flag
        _isMfaVerificationFlow = false;
      }

      return isValid;
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error verifying MFA code: $e\n$stackTrace');
      return false;
    }
  }

  String _hashVerificationCode(String code) {
    final bytes = utf8.encode(code);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  // ==========================================================================
  // SIGN IN METHODS - UPDATED
  // ==========================================================================

  // Use this as the primary sign-in method now? Or keep both? Assuming initiateSignIn is preferred.
  Future<void> initiateSignIn(String email, String password) async {
    try {
      if (await _isAccountLocked()) {
        // Logic to calculate remaining time and throw specific locked exception
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

      final maskedEmail = _maskEmail(email);
      Logger.info(_tag, 'Initiating sign in process for email: $maskedEmail');

      // Direct sign-in attempt
      UserCredential? userCredential; // Make nullable
      try {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        // Handle AUTH errors during sign-in attempt
        Logger.error(_tag, 'FirebaseAuthException during signIn: ${e.code} - ${e.message}');
        await _recordFailedAttempt(); // Record failure
        throw AuthException( message: _getReadableErrorMessage(e), code: e.code, isRecoverable: _isRecoverableError(e.code));
      } on TypeError catch (e, stackTrace) {
        // Handle specific type errors during sign-in (Pigeon?)
        Logger.error(_tag, 'Type error during sign in: $e\n$stackTrace');
        await _recordFailedAttempt(); // Record failure
        throw AuthException( message: 'Authentication system error during sign in. Please try again later.', code: 'auth_type_error');
      }

      // Process successful sign-in credential
      final user = userCredential?.user; // Use null-aware access

      if (user != null) {
        final userId = user.uid; // Safe access inside check
        Logger.info(_tag, 'User signed in successfully with UID: $userId');

        await _resetFailedAttempts(); // Reset on success
        await Future.delayed(const Duration(milliseconds: 100)); // Reduced delay slightly

        // Save credentials if remember me is used (consider if needed here)
        // This depends on where rememberMe preference is set by the UI
        // Assuming it's handled elsewhere or default true for now:
        await saveCredentials(email, true);

        // <<<<< START: FIXED Firestore Interaction >>>>>
        try {
          // Directly use set with a map literal instead of building updateData
          // This avoids the type error by keeping the email assignment inside the map literal
          await _firestore.collection('users').doc(userId).set({
            'lastLogin': FieldValue.serverTimestamp(),
            if (user.email != null) 'email': user.email
          }, SetOptions(merge: true));

          Logger.info(_tag, 'Updated lastLogin for user $userId');
        } catch (e, stackTrace) {
          // Log error but don't necessarily block login if only timestamp fails
          Logger.error(_tag, 'Failed to update Firestore on login for $userId: $e\n$stackTrace');
          // Could potentially throw a non-fatal warning or custom exception here if needed
        }
        // <<<<< END: FIXED Firestore Interaction >>>>>

        // Create session and log event (best effort)
        try {
          await _createAuthSession(userId); // Uses userId
          await _logAuthEvent(userId, 'login', {'method': 'email'}); // Uses userId
        } catch (e) {
          Logger.error(_tag, 'Error during post-login session/logging for $userId: $e');
        }

        // Call freemium tracking if needed for this flow
        // await trackLogin();

      } else {
        // Should not happen if signInWithEmailAndPassword returns successfully without user
        // But handle defensively
        Logger.error(_tag, 'Sign in successful but User object is null.');
        // We likely threw an exception already in the try/catch block above if auth failed
        // If we reach here, it's an unexpected state.
        throw AuthException(message: 'Sign in failed unexpectedly.', code: 'unknown_signin_error');
      }

    } on AuthException {
      // Re-throw specific AuthExceptions (locked, auth errors, type errors)
      rethrow;
    } catch (e, stackTrace) {
      // Catch-all for other unexpected errors during the process
      Logger.error(_tag, 'Unexpected error during initiateSignIn: $e\n$stackTrace');
      // Don't record failed attempt here if it was already recorded in specific catches
      throw AuthException(
        message: 'An unexpected error occurred during sign in. Please try again.',
        code: 'unknown_error', // Generic code
      );
    }
  }


  // Consider if this separate method is still needed or if initiateSignIn covers all cases.
  // If kept, it needs the same Firestore robustness update.
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      // Check for account lockout (duplicate logic from initiateSignIn - maybe refactor?)
      if (await _isAccountLocked()) {
        final prefs = await SharedPreferences.getInstance();
        final lastAttemptTime = prefs.getInt(_lastFailedAttemptKey) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final minutesElapsed = (now - lastAttemptTime) / (1000 * 60);
        final minutesRemaining = _lockoutMinutes - minutesElapsed.floor();
        throw AuthException( message: 'Your account is temporarily locked...', code: 'account_locked', isRecoverable: false );
      }

      final maskedEmail = _maskEmail(email);
      Logger.info(_tag, 'Executing signInWithEmailAndPassword for: $maskedEmail');

      UserCredential? credential; // Make nullable
      try {
        credential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        Logger.error(_tag, 'FirebaseAuthException during direct signIn: ${e.code}');
        await _recordFailedAttempt();
        throw AuthException(message: _getReadableErrorMessage(e), code: e.code, isRecoverable: _isRecoverableError(e.code));
      } on TypeError catch (e, stackTrace) {
        Logger.error(_tag, 'Type error during direct sign in: $e\n$stackTrace');
        await _recordFailedAttempt();
        throw AuthException(message: 'Authentication system error.', code: 'auth_type_error');
      }

      final user = credential?.user; // Use null-aware access

      if (user != null) {
        final userId = user.uid; // Safe access
        Logger.info(_tag, 'Direct sign in successful with UID: $userId');

        await Future.delayed(const Duration(milliseconds: 100)); // Reduced delay
        await _resetFailedAttempts();

        // <<<<< START: FIXED Firestore Interaction >>>>>
        try {
          // Directly use set with a map literal instead of building updateData
          // This avoids the type error by keeping the email assignment inside the map literal
          await _firestore.collection('users').doc(userId).set({
            'lastLogin': FieldValue.serverTimestamp(),
            if (user.email != null) 'email': user.email
          }, SetOptions(merge: true));

          Logger.info(_tag, 'Updated lastLogin for user $userId');
        } catch (e, stackTrace) {
          Logger.error(_tag, 'Failed to update Firestore on direct login for $userId: $e\n$stackTrace');
          // Decide if this should block returning the credential
        }
        // <<<<< END: FIXED Firestore Interaction >>>>>

        // Create session and log event (best effort)
        try {
          await _createAuthSession(userId);
          await _logAuthEvent(userId, 'login', {'method': 'email'});
        } catch (e) {
          Logger.error(_tag, 'Error during post-login session/logging for $userId: $e');
        }

        // Call freemium tracking if needed for this flow
        // await trackLogin();

      } else {
        // If user is null after successful call (shouldn't happen)
        Logger.error(_tag, 'Direct sign in successful but User object is null.');
        throw AuthException(message: 'Sign in failed unexpectedly.', code: 'unknown_signin_error');
      }

      // Return the original credential, which might have a null user if sign-in failed
      // The calling code should handle the credential.user check again if needed
      // However, exceptions are thrown on failure, so credential should be non-null with non-null user if reached here without error.
      return credential!; // Can assert non-null if exceptions guarantee success

    } on AuthException {
      rethrow; // Pass through known auth exceptions
    } catch (e, stackTrace) {
      // Catch-all for other unexpected errors
      Logger.error(_tag, 'Unexpected error during signInWithEmailAndPassword: $e\n$stackTrace');
      // Don't record failed attempt here if already recorded
      throw AuthException(
        message: 'An unexpected error occurred during sign in. Please try again.',
        code: 'unknown_error',
      );
    }
  }

  // ==========================================================================
  // SIGN OUT / PASSWORD RESET
  // ==========================================================================

  Future<void> signOut() async {
    try {
      _sessionTimer?.cancel(); // Cancel freemium timer if active

      final userId = currentUser?.uid; // Get UID before signing out

      // Log the sign-out event before actually signing out (best effort)
      if (userId != null) {
        try {
          await _logAuthEvent(userId, 'logout', {'sessionId': _sessionId});
        } catch (e) {
          Logger.error(_tag, 'Failed to log signout event for $userId: $e');
        }
      }

      await _auth.signOut(); // Perform Firebase sign out

      Logger.info(_tag, 'User signed out successfully.');

      // Clear local session data AFTER successful sign out
      await _clearSessionData();
      await clearStoredCredentials(); // Clear email/token etc.

    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error during sign out: $e\n$stackTrace');
      // Don't throw AuthException if sign out itself failed, maybe just log?
      // Or rethrow a generic exception if needed by UI
      // throw AuthException( message: 'An error occurred while signing out.', code: 'signout_error');
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    // Validate email format client-side first?
    if (!_isValidEmail(email)) {
      throw AuthException(message: 'Invalid email format.', code: 'invalid-email');
    }
    try {
      final maskedEmail = _maskEmail(email);
      Logger.info(_tag, 'Sending password reset email to: $maskedEmail');

      await _auth.sendPasswordResetEmail(email: email);

      Logger.info(_tag, 'Password reset email sent successfully to $maskedEmail');
    } on FirebaseAuthException catch (e, stackTrace) {
      Logger.error(_tag, 'Firebase Auth Error sending reset email to $email: ${e.code}\n$stackTrace');
      throw AuthException(
        message: _getReadableErrorMessage(e), // Use readable message
        code: e.code, // Propagate original code
        isRecoverable: _isRecoverableError(e.code),
      );
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error sending password reset email to $email: $e\n$stackTrace');
      throw AuthException(
        message: 'An error occurred sending the password reset email. Please try again.',
        code: 'reset_email_error',
      );
    }
  }

  // Simple email validation helper
  bool _isValidEmail(String email) {
    // Basic regex, consider using a package for more robust validation if needed
    return RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(email);
  }


  // ==========================================================================
  // USER PROFILE METHODS
  // ==========================================================================

  Future<Map<String, dynamic>?> getUserProfile() async {
    final user = currentUser; // Use getter
    if (user == null) {
      Logger.warning(_tag, 'No current user, cannot retrieve profile.');
      return null;
    }

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        Logger.info(_tag, 'User profile retrieved successfully for ${user.uid}');
        return doc.data();
      } else {
        // This case might indicate an issue (like signup profile save failure)
        Logger.warning(_tag, 'User profile document not found in Firestore for UID: ${user.uid}');
        return null;
      }
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error getting user profile for ${user.uid}: $e\n$stackTrace');
      // Throw specific exception?
      throw AuthException(
        message: 'Failed to retrieve user profile. Please try again later.',
        code: 'profile_retrieval_error',
      );
    }
  }

  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    final user = currentUser;
    if (user == null) {
      Logger.warning(_tag, 'No current user, cannot update profile');
      throw AuthException( message: 'You must be signed in to update your profile.', code: 'not_authenticated');
    }

    try {
      // Add last updated timestamp
      data['lastUpdated'] = FieldValue.serverTimestamp();

      await _firestore.collection('users').doc(user.uid).update(data);
      Logger.info(_tag, 'User profile updated successfully for ${user.uid} with fields: ${data.keys.toList()}');

      // Update display name if provided ('name' key)
      if (data.containsKey('name') && data['name'] is String) {
        try {
          await user.updateDisplayName(data['name']);
          Logger.info(_tag, 'Display name updated for ${user.uid}');
        } catch (e) {
          Logger.warning(_tag, 'Failed to update display name for ${user.uid}: $e');
        }
      }

      // Log profile update event (best effort)
      try {
        await _logAuthEvent(user.uid, 'profile_update', { 'updatedFields': data.keys.toList() });
      } catch(e) {
        Logger.error(_tag, 'Failed to log profile update event for ${user.uid}: $e');
      }

    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error updating user profile for ${user.uid}: $e\n$stackTrace');
      // Check for specific Firestore errors (e.g., permission denied)
      if (e is FirebaseException && e.code == 'permission-denied') {
        throw AuthException(message: 'Permission denied to update profile.', code: e.code);
      }
      throw AuthException( message: 'Failed to update user profile. Please try again.', code: 'profile_update_error');
    }
  }

  // ==========================================================================
  // PERSISTENT AUTH / CREDENTIALS / HELPERS
  // ==========================================================================

  Future<bool> hasValidCredentials() async {
    // This seems more about checking if a user session *might* be resumable
    try {
      // If user object exists in auth state, check session validity
      if (currentUser != null) {
        Logger.info(_tag, 'User authenticated via Firebase state: ${currentUser!.uid}');
        // Combine checks: standard session AND freemium session (if applicable)
        final bool standardSessionOk = await isAuthSessionValid();
        final bool freemiumSessionOk = await isSessionValid(); // Checks premium status internally

        if (!standardSessionOk) {
          Logger.warning(_tag, 'Standard auth session expired, forcing sign out.');
          await signOut(); // Sign out if main session expired
          return false;
        }
        if (!freemiumSessionOk) {
          // Only sign out if freemium expired AND they are not premium
          final isPremium = await _isPremiumUser(currentUser!.uid);
          if (!isPremium) {
            Logger.warning(_tag, 'Freemium session expired, forcing sign out.');
            await signOut();
            return false;
          }
        }
        return true; // Both sessions OK (or premium)
      }

      // Fallback: Check stored credentials (e.g., for 'Remember Me')
      final bool rememberMe = await _isRememberMeEnabled();
      final String? storedEmail = await _secureStorage.read(key: _emailKey);

      if (rememberMe && storedEmail != null) {
        Logger.info(_tag, 'Found stored email (${_maskEmail(storedEmail)}) for re-authentication hint.');
        // Indicate that login is required, but we have credentials to pre-fill
        return false; // Requires manual login
      }

      // Check for legacy token? (Seems less relevant if using Firebase Auth primarily)
      /*
      final token = await _secureStorage.read(key: _tokenKey);
      if (token != null) { ... verify token ... }
      */

      Logger.info(_tag, 'No valid Firebase session or stored credentials found.');
      return false; // No valid session or credentials found

    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error checking credentials: $e\n$stackTrace');
      return false; // Default to false on error
    }
  }

  Future<void> saveCredentials(String email, bool rememberMe) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberMeKey, rememberMe);

      if (rememberMe) {
        final maskedEmail = _maskEmail(email);
        Logger.info(_tag, 'Saving email for remember me: $maskedEmail');
        await _secureStorage.write(key: _emailKey, value: email);

        // Storing Firebase ID token directly might have security implications
        // and they expire. Refresh tokens are handled internally by SDK.
        // Consider if storing the token is necessary for your use case.
        /*
        final user = currentUser;
        if (user != null) {
          final idTokenResult = await user.getIdTokenResult(true); // Force refresh?
          if (idTokenResult.token != null) {
            await _secureStorage.write(key: _tokenKey, value: idTokenResult.token);
            Logger.info(_tag, 'Saved authentication token');
          }
        }
        */
      } else {
        Logger.info(_tag, 'Remember me disabled, clearing stored email.');
        await _secureStorage.delete(key: _emailKey);
        // Also clear token if you were storing it
        // await _secureStorage.delete(key: _tokenKey);
      }
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error saving credentials: $e\n$stackTrace');
    }
  }

  Future<void> clearStoredCredentials() async {
    // Clears credentials potentially used for 'Remember Me'
    try {
      Logger.info(_tag, 'Clearing stored credentials (email/token)');
      await _secureStorage.delete(key: _emailKey);
      await _secureStorage.delete(key: _tokenKey); // If storing token
      await _secureStorage.delete(key: _refreshTokenKey); // If storing refresh token (unlikely needed)

      // Clear temporary hashes if used elsewhere (consider if needed)
      // await _secureStorage.delete(key: 'temp_password_hash');
      // await _secureStorage.delete(key: 'temp_salt');

      // Keep the main salt used for password hashing if needed globally?
      // await _secureStorage.delete(key: _saltKey); // Decide if salt is user-specific or global

      // Note: Doesn't clear SharedPreferences (_rememberMeKey itself)

      Logger.info(_tag, 'Stored credentials cleared.');
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error clearing credentials: $e\n$stackTrace');
    }
  }

  Future<bool> _isRememberMeEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_rememberMeKey) ?? false;
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error reading remember me preference: $e\n$stackTrace');
      return false; // Default to false on error
    }
  }

  Future<bool> isBiometricEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_biometricEnabledKey) ?? false;
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error reading biometric preference: $e\n$stackTrace');
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricEnabledKey, enabled);
      Logger.info(_tag, 'Biometric authentication setting updated to: $enabled');
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error setting biometric preference: $e\n$stackTrace');
      // Optionally throw or handle
    }
  }

  // Password hashing/salt methods - seem okay but ensure salt management strategy is correct
  Future<void> _generateAndStoreSalt() async {
    try {
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      final salt = base64Url.encode(values);

      await _secureStorage.write(key: _saltKey, value: salt);

      Logger.info(_tag, 'Generated and stored new salt for password hashing');
    } catch (e, stackTrace) {
      Logger.error(_tag, 'Error generating salt: $e\n$stackTrace');
    }
  }

  Future<String> _getOrCreateSalt() async {
    final existingSalt = await _secureStorage.read(key: _saltKey);
    if (existingSalt != null) {
      return existingSalt;
    }

    // Generate new salt if none exists
    await _generateAndStoreSalt();
    return await _secureStorage.read(key: _saltKey) ?? '';
  }

  String _hashPassword(String password, String salt) {
    final combinedBytes = utf8.encode(password + salt);
    final hash = sha256.convert(combinedBytes);
    return hash.toString();
  }

  // Email masking - seems okay
  String _maskEmail(String email) {
    try {
      final parts = email.split('@');
      if (parts.length == 2) {
        final username = parts[0];
        final domain = parts[1];
        final maskedUsername = username.length <= 3
            ? username
            : '${username.substring(0, 3)}${'*' * (username.length - 3)}';
        return '$maskedUsername@$domain';
      }
      return email;
    } catch (_) {
      return 'invalid.email.format';
    }
  }

  // Placeholder methods - kept as provided
  Future<String> _getPasswordFromUser() async {
    throw AuthException(message: 'Not implemented', code: 'not_implemented');
  }

  Future<UserCredential> completeSignIn(String? verificationCode) async {
    throw AuthException(message: 'Not implemented', code: 'not_implemented');
  }
}