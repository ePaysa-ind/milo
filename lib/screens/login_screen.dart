//lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:milo/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:milo/theme/app_theme.dart';
import 'package:milo/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:milo/screens/verification_screen.dart';
import 'dart:async';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _localAuth = LocalAuthentication();
  final _secureStorage = const FlutterSecureStorage();

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _biometricsAvailable = false;
  String? _errorMessage;
  String? _infoMessage;
  bool _isDisposed = false;
  bool _obscurePassword = true;

  Timer? _infoMessageTimer;
  Timer? _sessionTimer; // Added session timer
  bool _isMounted = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    Logger.info('LoginScreen', 'Initializing LoginScreen');

    // Reset failed login attempts counter to prevent lockout issues
    AuthService().resetLoginAttempts();

    // Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // Delay authentication checks to ensure widget is fully initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isMounted) {
        _checkPersistentLogin();
        _checkBiometricAvailability();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Logger.info('LoginScreen', 'App lifecycle state changed: $state');

    // If the app is resumed and we're still mounted, check if biometrics are still valid
    if (state == AppLifecycleState.resumed && _isMounted) {
      _checkBiometricAvailability();
      _checkSessionValidity(); // Added session validity check on app resume
    }
  }

  @override
  void dispose() {
    Logger.info('LoginScreen', 'Disposing LoginScreen');
    // Set flags first to prevent any callbacks from running
    _isMounted = false;
    _isDisposed = true;

    // Cancel any pending timers
    _infoMessageTimer?.cancel();
    _sessionTimer?.cancel(); // Cancel session timer on dispose

    // Dispose of controllers
    _emailController.dispose();
    _passwordController.dispose();

    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  // New method to check session validity
  Future<void> _checkSessionValidity() async {
    if (!_isMounted) return;

    try {
      final isSessionValid = await _authService.isSessionValid();
      if (!isSessionValid) {
        // Session expired, log user out
        await _endSession(showMessage: true);
      }
    } catch (e) {
      Logger.error('LoginScreen', 'Error checking session validity: $e');
    }
  }

  // New method to start session timer
  void _startSessionTimer() {
    // Cancel any existing timer first
    _sessionTimer?.cancel();

    Logger.info('LoginScreen', 'Starting 5-minute session timer');

    // Create new timer for 5 minutes (300 seconds)
    _sessionTimer = Timer(const Duration(seconds: 300), () async {
      if (_isMounted && mounted && !_isDisposed) {
        Logger.info('LoginScreen', 'Session timer expired, ending session');
        await _endSession(showMessage: true);
      }
    });
  }

  // New method to end session
  Future<void> _endSession({bool showMessage = false}) async {
    if (!_isMounted) return;

    try {
      Logger.info('LoginScreen', 'Ending user session');

      // Cancel session timer
      _sessionTimer?.cancel();

      // Sign out user
      await _authService.signOut();

      if (showMessage && _isMounted && mounted && !_isDisposed) {
        _showSnackbar('Your freemium session has ended. Please log in again.');
      }
    } catch (e) {
      Logger.error('LoginScreen', 'Error ending session: $e');
    }
  }

  // Safe setState that checks if the widget is still mounted and not disposed
  void _safeSetState(VoidCallback fn) {
    if (_isMounted && mounted && !_isDisposed) {
      setState(fn);
    } else {
      Logger.warning('LoginScreen', 'Attempted to setState after dispose');
    }
  }

  // Show a temporary info message to the user
  void _showInfoMessage(String message, {int durationSeconds = 5}) {
    if (!_isMounted) return;

    _safeSetState(() {
      _infoMessage = message;
      _errorMessage = null; // Clear any existing error
    });

    // Cancel any existing timer
    _infoMessageTimer?.cancel();

    // Set timer to clear message after duration
    _infoMessageTimer = Timer(Duration(seconds: durationSeconds), () {
      _safeSetState(() {
        _infoMessage = null;
      });
    });
  }

  // Check if the user has saved credentials
  Future<void> _checkPersistentLogin() async {
    if (!_isMounted) return;

    Logger.info('LoginScreen', 'Checking for saved credentials');

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      // Check if user has valid credentials stored
      final hasValidCredentials = await _authService.hasValidCredentials();
      Logger.info('LoginScreen', 'Has valid credentials: $hasValidCredentials');

      if (!_isMounted) return;

      if (hasValidCredentials) {
        Logger.info('LoginScreen', 'Found valid credentials, auto-logging in');

        // Check login limit before allowing auto-login
        final hasReachedLimit = await _authService.hasReachedLoginLimit();
        if (hasReachedLimit) {
          Logger.info('LoginScreen', 'User has reached free login limit');

          _safeSetState(() {
            _errorMessage = 'You have reached your free login limit. Please upgrade to premium.';
            _isLoading = false;
          });
          return;
        }

        // If we're still mounted, track login and navigate to home
        if (_isMounted && mounted && !_isDisposed) {
          await _authService.trackLogin();
          _startSessionTimer(); // Start session timer after successful login
          Navigator.pushReplacementNamed(context, '/home');
          return; // Exit early after navigation
        }
      }

      // If we don't have valid credentials or couldn't auto-login:
      if (!_isMounted) return;

      // Try to load the "remember me" preference
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me') ?? false;
      Logger.info('LoginScreen', 'Remember me preference: $rememberMe');

      if (!_isMounted) return;

      // Check if email was saved (for auto-fill)
      final savedEmail = await _secureStorage.read(key: 'auth_email');

      if (!_isMounted) return;

      if (savedEmail != null && rememberMe) {
        _safeSetState(() {
          _emailController.text = savedEmail;
        });
        Logger.info('LoginScreen', 'Restored saved email address');
      }

      _safeSetState(() {
        _rememberMe = rememberMe;
      });
    } catch (e) {
      if (!_isMounted) return;
      Logger.error('LoginScreen', 'Error checking saved credentials: $e');

      _safeSetState(() {
        _errorMessage = 'There was a problem checking your saved login information.';
      });
    } finally {
      if (_isMounted) {
        _safeSetState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Check if biometric authentication is available
  Future<void> _checkBiometricAvailability() async {
    if (!_isMounted) return;

    try {
      Logger.info('LoginScreen', 'Checking biometric availability');

      // Check if biometrics are available on this device
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!_isMounted) return;

      Logger.info('LoginScreen', 'Can check biometrics: $canCheckBiometrics, Device supported: $isDeviceSupported');

      if (canCheckBiometrics && isDeviceSupported) {
        final availableBiometrics = await _localAuth.getAvailableBiometrics();
        Logger.info('LoginScreen', 'Available biometrics: $availableBiometrics');

        if (!_isMounted) return;

        _safeSetState(() {
          _biometricsAvailable = availableBiometrics.isNotEmpty;
        });

        // If biometrics are available and we have credentials, offer to login with biometrics
        if (_biometricsAvailable && await _authService.hasValidCredentials()) {
          if (!_isMounted) return;

          // Check login limit before offering biometric login
          final hasReachedLimit = await _authService.hasReachedLoginLimit();
          if (hasReachedLimit) {
            Logger.info('LoginScreen', 'User has reached free login limit');
            _safeSetState(() {
              _errorMessage = 'You have reached your free login limit. Please upgrade to premium.';
            });
            return;
          }

          // Small delay to ensure UI is ready
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_isMounted && mounted && !_isDisposed) {
              _authenticateWithBiometrics();
            }
          });
        }
      }
    } catch (e) {
      if (!_isMounted) return;
      Logger.error('LoginScreen', 'Error checking biometric availability: $e');
      // Don't show an error to the user, just disable biometric login
      _safeSetState(() {
        _biometricsAvailable = false;
      });
    }
  }

  // Authenticate with fingerprint or face ID
  Future<void> _authenticateWithBiometrics() async {
    if (!_isMounted) return;

    try {
      Logger.info('LoginScreen', 'Starting biometric authentication');

      // Check login limit before attempting biometric login
      final hasReachedLimit = await _authService.hasReachedLoginLimit();
      if (hasReachedLimit) {
        Logger.info('LoginScreen', 'User has reached free login limit');
        _showSnackbar('You have reached your free login limit. Please upgrade to premium.');
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Login to Milo with your biometric',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!_isMounted) return;

      Logger.info('LoginScreen', 'Biometric authentication result: $authenticated');

      if (authenticated) {
        _safeSetState(() {
          _isLoading = true;
        });

        // Track login after successful biometric authentication
        await _authService.trackLogin();

        // Start session timer
        _startSessionTimer();

        // Navigate to home screen if still mounted
        Logger.info('LoginScreen', 'Biometric auth successful, navigating to home');

        if (_isMounted && mounted && !_isDisposed) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e) {
      if (!_isMounted) return;
      Logger.error('LoginScreen', 'Biometric authentication error: $e');

      // Show error message if appropriate
      if (_isMounted && mounted && !_isDisposed) {
        _showSnackbar(
          'Biometric authentication failed. Please use email and password.',
          isError: true,
        );
      }
    }
  }

  // Show a snackbar message
  void _showSnackbar(String message, {bool isError = false}) {
    if (!_isMounted || !mounted || _isDisposed) return;

    final messenger = ScaffoldMessenger.of(context);
    // Clear any existing snackbars
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: AppTheme.fontSizeSmall),
        ),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppTheme.smallBorderRadius,
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // Handle login process
  Future<void> _login() async {
    if (!_isMounted) return;

    // Exit early if form is invalid
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      Logger.info('LoginScreen', 'Initiating login with email: ${email.split('@').first}@***');

      // Check login limit before attempting login
      final hasReachedLimit = await _authService.hasReachedLoginLimit();
      if (hasReachedLimit) {
        Logger.info('LoginScreen', 'User has reached free login limit');

        _safeSetState(() {
          _isLoading = false;
          _errorMessage = 'You have reached your free login limit. Please upgrade to premium.';
        });
        return;
      }

      // Use the two-step authentication process
      try {
        // First step: initiate sign-in (validate credentials)
        await _authService.initiateSignIn(email, password);

        if (!_isMounted) return;

        // Track login after successful authentication
        await _authService.trackLogin();

        // Start session timer
        _startSessionTimer();

        // Save email if remember me is checked
        await _authService.saveCredentials(email, _rememberMe);

        Logger.info('LoginScreen', 'First authentication step successful');

        if (!_isMounted) return;

        // If we get here without exception, move to verification screen or home
        if (_isMounted && mounted && !_isDisposed) {
          // Check if we need verification or can go straight to home
          Navigator.pushReplacementNamed(context, '/home');
        }
      } on AuthException catch (e) {
        if (!_isMounted) return;

        // Handle specific auth exceptions
        if (e.code == 'mfa_required') {
          // MFA is required - navigate to verification screen
          if (_isMounted && mounted && !_isDisposed) {
            Logger.info('LoginScreen', 'MFA required, navigating to verification screen');
            _showInfoMessage('Verification code sent to your email');

            final route = MaterialPageRoute(
              builder: (context) => VerificationScreen(email: email),
            );
            Navigator.push(context, route);
          }
        } else {
          // Other auth exception
          Logger.error('LoginScreen', 'Auth exception: ${e.code} - ${e.message}');
          _safeSetState(() {
            _errorMessage = e.message;
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!_isMounted) return;

      Logger.error('LoginScreen', 'Firebase Auth Error: ${e.code} - ${e.message}');

      _safeSetState(() {
        // User-friendly error messages based on Firebase error codes
        switch (e.code) {
          case 'invalid-credential':
          case 'wrong-password':
          case 'user-not-found':
            _errorMessage = 'Invalid email or password. Please try again or reset your password.';
            break;
          case 'invalid-email':
            _errorMessage = 'Please enter a valid email address.';
            break;
          case 'user-disabled':
            _errorMessage = 'This account has been disabled. Please contact support.';
            break;
          case 'too-many-requests':
            _errorMessage = 'Too many failed login attempts. Please try again later or reset your password.';
            break;
          case 'network-request-failed':
            _errorMessage = 'Network connection error. Please check your internet and try again.';
            break;
          default:
            _errorMessage = 'Login failed. Please check your credentials and try again.';
        }
      });
    } catch (e) {
      if (!_isMounted) return;

      Logger.error('LoginScreen', 'General Login Error: $e');

      _safeSetState(() {
        _errorMessage = 'Connection error. Please check your internet connection and try again.';
      });
    } finally {
      if (_isMounted) {
        _safeSetState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Handle back button press
      onWillPop: () async {
        // Don't allow back navigation during loading
        return !_isLoading;
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('Login to Milo'),
          backgroundColor: AppTheme.gentleTeal,
          foregroundColor: Colors.white,
        ),
        body: GestureDetector(
          // Dismiss keyboard when tapping outside
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              padding: AppTheme.paddingLarge,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Milo logo/image
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1), // Light cream background
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/images/milo_happy.gif',
                          height: 120,
                        ),
                      ),
                    ),
                    SizedBox(height: AppTheme.spacingLarge),

                    // Info message (success/information alerts)
                    if (_infoMessage != null)
                      Container(
                        padding: AppTheme.paddingSmall,
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withOpacity(0.1),
                          borderRadius: AppTheme.mediumBorderRadius,
                          border: Border.all(color: AppTheme.successColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: AppTheme.successColor),
                            SizedBox(width: AppTheme.spacingSmall),
                            Expanded(
                              child: Text(
                                _infoMessage!,
                                style: TextStyle(
                                  color: AppTheme.successColor,
                                  fontSize: AppTheme.fontSizeSmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Error message (place at top for visibility)
                    if (_errorMessage != null)
                      Container(
                        padding: AppTheme.paddingSmall,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withOpacity(0.1),
                          borderRadius: AppTheme.mediumBorderRadius,
                          border: Border.all(color: AppTheme.errorColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: AppTheme.errorColor),
                            SizedBox(width: AppTheme.spacingSmall),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: AppTheme.errorColor,
                                  fontSize: AppTheme.fontSizeSmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    SizedBox(height: AppTheme.spacingSmall),

                    // Email field
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        hintText: 'Enter your email address',
                        border: OutlineInputBorder(
                          borderRadius: AppTheme.mediumBorderRadius,
                        ),
                        prefixIcon: const Icon(Icons.email),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next, // Move to next field on submit
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeMedium,
                        color: AppTheme.textColor,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                      enabled: !_isLoading,
                    ),
                    SizedBox(height: AppTheme.spacingSmall),

                    // Password field
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Enter your password',
                        border: OutlineInputBorder(
                          borderRadius: AppTheme.mediumBorderRadius,
                        ),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: AppTheme.textSecondaryColor,
                          ),
                          onPressed: () {
                            _safeSetState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      obscureText: _obscurePassword,
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeMedium,
                        color: AppTheme.textColor,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _isLoading ? null : _login(),
                      enabled: !_isLoading,
                    ),

                    // Remember me checkbox
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: _isLoading
                                ? null
                                : (value) {
                              _safeSetState(() {
                                _rememberMe = value ?? false;
                              });
                            },
                            activeColor: AppTheme.gentleTeal,
                          ),
                          Text(
                            'Remember me',
                            style: TextStyle(
                              fontSize: AppTheme.fontSizeSmall,
                              color: AppTheme.textColor,
                            ),
                          ),

                          const Spacer(),

                          // Biometric login option
                          if (_biometricsAvailable)
                            TextButton.icon(
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Biometric login'),
                              onPressed: _isLoading ? null : _authenticateWithBiometrics,
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.gentleTeal,
                              ),
                            ),
                        ],
                      ),
                    ),

                    SizedBox(height: AppTheme.spacingMedium),

                    // Login button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gentleTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppTheme.mediumBorderRadius,
                        ),
                        disabledBackgroundColor: AppTheme.gentleTeal.withOpacity(0.6),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.0,
                        ),
                      )
                          : Text(
                        'Login',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeLarge,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    SizedBox(height: AppTheme.spacingMedium),

                    // Sign up link
                    Center(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                          Navigator.pushNamed(context, '/signup');
                        },
                        child: Text(
                          'New user? Create an account',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeMedium,
                            color: AppTheme.calmBlue,
                          ),
                        ),
                      ),
                    ),

                    // Forgot password link
                    Center(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                          showDialog(
                            context: context,
                            builder: (context) => _buildPasswordResetDialog(),
                          );
                        },
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeMedium,
                            color: AppTheme.calmBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordResetDialog() {
    final resetEmailController = TextEditingController();
    bool isLoading = false;
    String? resetErrorMessage;

    return StatefulBuilder(
        builder: (dialogContext, setState) {
          // Make a safe setDialogState function that's specific to the dialog
          void setDialogState(VoidCallback fn) {
            // Check if the main screen is still mounted before updating dialog state
            if (_isMounted && mounted && !_isDisposed) {
              setState(fn);
            }
          }

          Future<void> sendResetEmail() async {
            final email = resetEmailController.text.trim();
            if (email.isEmpty) {
              setDialogState(() {
                resetErrorMessage = 'Please enter your email address';
              });
              return;
            }

            if (!email.contains('@') || !email.contains('.')) {
              setDialogState(() {
                resetErrorMessage = 'Please enter a valid email address';
              });
              return;
            }

            setDialogState(() {
              isLoading = true;
              resetErrorMessage = null;
            });

            try {
              Logger.info('LoginScreen', 'Sending password reset email to: ${email.split('@').first}@***');
              await _authService.sendPasswordResetEmail(email);
              Logger.info('LoginScreen', 'Password reset email sent successfully');

              if (_isMounted && mounted && !_isDisposed) {
                Navigator.pop(dialogContext);
                _showSnackbar(
                  'Password reset email sent! Please check your inbox.',
                  isError: false,
                );
              }
            } on FirebaseAuthException catch (e) {
              Logger.error('LoginScreen', 'Firebase Auth Error during password reset: ${e.code} - ${e.message}');

              if (!_isMounted) return;

              setDialogState(() {
                isLoading = false;
                switch (e.code) {
                  case 'user-not-found':
                    resetErrorMessage = 'No account found with this email address';
                    break;
                  case 'invalid-email':
                    resetErrorMessage = 'Please enter a valid email address';
                    break;
                  case 'too-many-requests':
                    resetErrorMessage = 'Too many requests. Please try again later.';
                    break;
                  case 'network-request-failed':
                    resetErrorMessage = 'Network error. Please check your connection.';
                    break;
                  default:
                    resetErrorMessage = 'Error sending reset email. Please try again.';
                }
              });
            } catch (e) {
              Logger.error('LoginScreen', 'General error during password reset: $e');

              if (!_isMounted) return;

              setDialogState(() {
                isLoading = false;
                resetErrorMessage = 'Failed to send reset email. Please try again.';
              });
            }
          }

          return AlertDialog(
            title: Text(
              'Reset Password',
              style: TextStyle(
                fontSize: AppTheme.fontSizeLarge,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppTheme.largeBorderRadius,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter your email address and we\'ll send you a link to reset your password.',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                SizedBox(height: AppTheme.spacingSmall),
                TextField(
                  controller: resetEmailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email',
                    border: OutlineInputBorder(
                      borderRadius: AppTheme.mediumBorderRadius,
                    ),
                    prefixIcon: const Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textColor,
                  ),
                  onSubmitted: (_) => isLoading ? null : sendResetEmail(),
                  enabled: !isLoading,
                ),
                if (resetErrorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withOpacity(0.1),
                      borderRadius: AppTheme.smallBorderRadius,
                      border: Border.all(color: AppTheme.errorColor.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: AppTheme.errorColor, size: 16),
                        SizedBox(width: AppTheme.spacingSmall/1.5),
                        Expanded(
                          child: Text(
                            resetErrorMessage!,
                            style: TextStyle(
                              color: AppTheme.errorColor,
                              fontSize: AppTheme.fontSizeSmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: AppTheme.fontSizeMedium,
                  ),
                ),
              ),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: sendResetEmail,
                  child: Text(
                    'Send Email',
                    style: TextStyle(
                      color: AppTheme.gentleTeal,
                      fontSize: AppTheme.fontSizeMedium,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          );
        }
    );
  }
}