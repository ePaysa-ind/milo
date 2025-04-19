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

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService(); // Now using AuthService for all auth functions
  final _localAuth = LocalAuthentication();

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _biometricsAvailable = false;
  String? _errorMessage;
  String? _infoMessage;
  bool _isDisposed = false;
  bool _obscurePassword = true; // For password visibility toggle

  // Timer for auto-dismissing info messages
  Timer? _infoMessageTimer;

  @override
  void initState() {
    super.initState();
    Logger.info('LoginScreen', 'Initializing LoginScreen');
    _checkPersistentLogin();
    _checkBiometricAvailability();
  }

  @override
  void dispose() {
    Logger.info('LoginScreen', 'Disposing LoginScreen');
    _isDisposed = true;
    _emailController.dispose();
    _passwordController.dispose();
    _infoMessageTimer?.cancel();
    super.dispose();
  }

  // Safe setState that checks if the widget is still mounted and not disposed
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    } else {
      Logger.warning('LoginScreen', 'Attempted to setState after dispose');
    }
  }

  // Show a temporary info message to the user
  void _showInfoMessage(String message, {int durationSeconds = 5}) {
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
    Logger.info('LoginScreen', 'Checking for saved credentials');

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      // Check if user has valid credentials stored
      final hasValidCredentials = await _authService.hasValidCredentials();
      Logger.info('LoginScreen', 'Has valid credentials: $hasValidCredentials');

      if (hasValidCredentials) {
        Logger.info('LoginScreen', 'Found valid credentials, auto-logging in');

        // If we're still mounted, navigate to home
        if (mounted && !_isDisposed) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Try to load the "remember me" preference
        final prefs = await SharedPreferences.getInstance();
        final rememberMe = prefs.getBool('remember_me') ?? false;
        Logger.info('LoginScreen', 'Remember me preference: $rememberMe');

        // Check if email was saved (for auto-fill)
        final secureStorage = const FlutterSecureStorage();
        final savedEmail = await secureStorage.read(key: 'auth_email');

        if (savedEmail != null && rememberMe) {
          _safeSetState(() {
            _emailController.text = savedEmail;
            // Focus on password field since email is already filled
            FocusScope.of(context).nextFocus();
          });
          Logger.info('LoginScreen', 'Restored saved email address');
        }

        _safeSetState(() {
          _rememberMe = rememberMe;
        });
      }
    } catch (e) {
      Logger.error('LoginScreen', 'Error checking saved credentials: $e');
    } finally {
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }

  // Check if biometric authentication is available
  Future<void> _checkBiometricAvailability() async {
    try {
      Logger.info('LoginScreen', 'Checking biometric availability');

      // Check if biometrics are available on this device
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      Logger.info('LoginScreen', 'Can check biometrics: $canCheckBiometrics, Device supported: $isDeviceSupported');

      if (canCheckBiometrics && isDeviceSupported) {
        final availableBiometrics = await _localAuth.getAvailableBiometrics();
        Logger.info('LoginScreen', 'Available biometrics: $availableBiometrics');

        _safeSetState(() {
          _biometricsAvailable = availableBiometrics.isNotEmpty;
        });

        // If biometrics are available and we have credentials, offer to login with biometrics
        if (_biometricsAvailable && await _authService.hasValidCredentials()) {
          // Small delay to ensure UI is ready
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isDisposed) {
              _authenticateWithBiometrics();
            }
          });
        }
      }
    } catch (e) {
      Logger.error('LoginScreen', 'Error checking biometric availability: $e');
      // Don't set state here as it might be after dispose
    }
  }

  // Authenticate with fingerprint or face ID
  Future<void> _authenticateWithBiometrics() async {
    try {
      Logger.info('LoginScreen', 'Starting biometric authentication');

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Login to Milo with your biometric',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      Logger.info('LoginScreen', 'Biometric authentication result: $authenticated');

      if (authenticated) {
        if (mounted && !_isDisposed) {
          _safeSetState(() {
            _isLoading = true;
          });

          // Navigate to home screen if still mounted
          Logger.info('LoginScreen', 'Biometric auth successful, navigating to home');

          if (mounted && !_isDisposed) {
            Navigator.pushReplacementNamed(context, '/home');
          }
        }
      }
    } catch (e) {
      Logger.error('LoginScreen', 'Biometric authentication error: $e');

      // Show error message if appropriate
      if (mounted && !_isDisposed) {
        _showSnackbar(
          'Biometric authentication failed. Please use email and password.',
          isError: true,
        );
      }
    }
  }

  // Show a snackbar message
  void _showSnackbar(String message, {bool isError = false}) {
    if (mounted && !_isDisposed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(fontSize: AppTheme.fontSizeSmall),
          ),
          backgroundColor: isError ? AppTheme.mutedRed : AppTheme.calmGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
          ),
        ),
      );
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      _safeSetState(() {
        _isLoading = true;
        _errorMessage = null;
        _infoMessage = null;
      });

      try {
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();

        Logger.info('LoginScreen', 'Initiating login with email: ${email.split('@').first}@***');

        // Use the two-step authentication process
        try {
          // First step: initiate sign-in (validate credentials)
          await _authService.initiateSignIn(email, password);

          // Save email if remember me is checked
          await _authService.saveCredentials(email, _rememberMe);

          // MFA check will happen in initiateSignIn
          Logger.info('LoginScreen', 'First authentication step successful');

          // If we get here without exception, move to verification screen or home
          if (mounted && !_isDisposed) {
            // Navigate to verification screen
            final route = MaterialPageRoute(
              builder: (context) => VerificationScreen(email: email),
            );
            Navigator.push(context, route);
          }
        } on AuthException catch (e) {
          // Handle specific auth exceptions
          if (e.code == 'mfa_required') {
            // MFA is required - navigate to verification screen
            if (mounted && !_isDisposed) {
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
        Logger.error('LoginScreen', 'General Login Error: $e');

        _safeSetState(() {
          _errorMessage = 'Connection error. Please check your internet connection and try again.';
        });
      } finally {
        _safeSetState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            padding: const EdgeInsets.all(24.0),
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
                  const SizedBox(height: 32),

                  // Info message (success/information alerts)
                  if (_infoMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.calmGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                        border: Border.all(color: AppTheme.calmGreen),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: AppTheme.calmGreen),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _infoMessage!,
                              style: TextStyle(
                                color: AppTheme.calmGreen,
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
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.mutedRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                        border: Border.all(color: AppTheme.mutedRed),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppTheme.mutedRed),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: AppTheme.mutedRed,
                                fontSize: AppTheme.fontSizeSmall,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: 'Enter your email address',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
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
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
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
                    onFieldSubmitted: (_) => _login(), // Submit form when done
                  ),

                  // Remember me checkbox
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) {
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
                            onPressed: _authenticateWithBiometrics,
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.gentleTeal,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Login button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gentleTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
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

                  const SizedBox(height: 24),

                  // Sign up link
                  Center(
                    child: TextButton(
                      onPressed: () {
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
                      onPressed: () {
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
    );
  }

  Widget _buildPasswordResetDialog() {
    final resetEmailController = TextEditingController();
    bool isLoading = false;
    String? resetErrorMessage;

    return StatefulBuilder(
        builder: (context, setState) {
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
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge),
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
                const SizedBox(height: 16),
                TextField(
                  controller: resetEmailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                    ),
                    prefixIcon: const Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textColor,
                  ),
                ),
                if (resetErrorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.mutedRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                      border: Border.all(color: AppTheme.mutedRed.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: AppTheme.mutedRed, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            resetErrorMessage!,
                            style: TextStyle(
                              color: AppTheme.mutedRed,
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
                onPressed: () => Navigator.pop(context),
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
                  onPressed: () async {
                    final email = resetEmailController.text.trim();
                    if (email.isEmpty) {
                      setState(() {
                        resetErrorMessage = 'Please enter your email address';
                      });
                      return;
                    }

                    if (!email.contains('@') || !email.contains('.')) {
                      setState(() {
                        resetErrorMessage = 'Please enter a valid email address';
                      });
                      return;
                    }

                    setState(() {
                      isLoading = true;
                      resetErrorMessage = null;
                    });

                    try {
                      Logger.info('LoginScreen', 'Sending password reset email to: ${email.split('@').first}@***');
                      await _authService.sendPasswordResetEmail(email);
                      Logger.info('LoginScreen', 'Password reset email sent successfully');

                      if (mounted && !_isDisposed) {
                        Navigator.pop(context);
                        _showSnackbar(
                          'Password reset email sent! Please check your inbox.',
                          isError: false,
                        );
                      }
                    } on FirebaseAuthException catch (e) {
                      Logger.error('LoginScreen', 'Firebase Auth Error during password reset: ${e.code} - ${e.message}');

                      setState(() {
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

                      setState(() {
                        isLoading = false;
                        resetErrorMessage = 'Failed to send reset email. Please try again.';
                      });
                    }
                  },
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