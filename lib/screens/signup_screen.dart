// lib/screens/signup_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:milo/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:milo/theme/app_theme.dart';
import 'package:milo/utils/logger.dart';
import 'package:milo/utils/advanced_logger.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _ageController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;
  bool _isDisposed = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  static const String _tag = 'SignupScreen';

  @override
  void initState() {
    super.initState();
    Logger.info(_tag, 'Initializing SignupScreen');
  }

  @override
  void dispose() {
    Logger.info(_tag, 'Disposing SignupScreen');
    _isDisposed = true;
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _ageController.dispose();
    if (_scrollController.hasClients) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  // Safe setState that checks if the widget is still mounted and not disposed
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    } else {
      Logger.warning(_tag, 'Attempted to setState after dispose');
    }
  }

  // Show a temporary info message to the user
  void _setInfoMessage(String message) {
    _safeSetState(() {
      _infoMessage = message;
      _errorMessage = null; // Clear any existing error
    });

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          if (_infoMessage == message) { // Only clear if it hasn't been changed
            _infoMessage = null;
          }
        });
      }
    });
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

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

  Future<void> _signup() async {
    if (_formKey.currentState!.validate()) {
      _safeSetState(() {
        _isLoading = true;
        _errorMessage = null;
        _infoMessage = null;
      });

      try {
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();
        final confirmPassword = _confirmPasswordController.text.trim();
        final name = _nameController.text.trim();
        final age = int.tryParse(_ageController.text.trim()) ?? 0;

        // Additional validation checks
        if (password != confirmPassword) {
          _safeSetState(() {
            _isLoading = false;
            _errorMessage = 'Passwords do not match. Please try again.';
          });
          _scrollToTop();
          return;
        }

        if (age < 55 || age > 120) {
          _safeSetState(() {
            _isLoading = false;
            _errorMessage = age < 55
                ? 'Milo is designed for users 55 and older.'
                : 'Please enter a valid age.';
          });
          _scrollToTop();
          return;
        }

        // Log the signup attempt with masked email for privacy
        final maskedEmail = email.split('@').first.substring(0, min(3, email.length)) + '***@' + email.split('@').last;
        Logger.info(_tag, 'Attempting to sign up: $maskedEmail');
        AdvancedLogger.info(_tag, 'Creating new account',
            data: {'email': maskedEmail, 'name': name, 'age': age});

        // Create the user with Firebase
        final authResult = await _authService.signUpWithEmailAndPassword(
          email,
          password,
          name,
          age,
        );

        Logger.info(_tag, 'Sign up successful: ${authResult.user?.uid}');
        AdvancedLogger.info(_tag, 'Account created successfully',
            data: {'uid': authResult.user?.uid});

        // Show success message and navigate
        if (mounted && !_isDisposed) {
          _showSnackbar('Account created successfully!', isError: false);

          // Navigate to home after successful signup
          Navigator.pushReplacementNamed(context, '/home');
        }
      } on AuthException catch (e) {
        Logger.error(_tag, 'Auth service error during signup: ${e.code}');
        AdvancedLogger.error(_tag, 'Auth service error during signup',
            error: e, data: {'code': e.code, 'recoverable': e.isRecoverable});

        _safeSetState(() {
          _isLoading = false;
          _errorMessage = e.message;
        });

        // Scroll to the error message
        _scrollToTop();
      } on FirebaseAuthException catch (e) {
        Logger.error(_tag, 'Firebase Auth Error: ${e.code} - ${e.message}');
        AdvancedLogger.error(_tag, 'Firebase Auth Error during signup',
            error: e, data: {'code': e.code, 'message': e.message});

        _safeSetState(() {
          _isLoading = false;
          switch (e.code) {
            case 'email-already-in-use':
              _errorMessage = 'This email is already registered. Please sign in or use a different email.';
              break;
            case 'invalid-email':
              _errorMessage = 'Please enter a valid email address.';
              break;
            case 'weak-password':
              _errorMessage = 'Password is too weak. Please use a stronger password with at least 8 characters, including uppercase letters, numbers, and special characters.';
              break;
            case 'operation-not-allowed':
              _errorMessage = 'Account creation is currently disabled. Please try again later or contact support.';
              break;
            case 'network-request-failed':
              _errorMessage = 'Network error. Please check your internet connection and try again.';
              break;
            default:
              _errorMessage = 'Failed to create account: ${e.message}';
          }
        });

        // Scroll to the error message
        _scrollToTop();
      } catch (e) {
        Logger.error(_tag, 'General signup error: $e');
        AdvancedLogger.error(_tag, 'Unexpected error during signup', error: e);

        _safeSetState(() {
          _isLoading = false;
          _errorMessage = 'Connection error. Please check your internet connection and try again.';
        });

        // Scroll to the error message
        _scrollToTop();
      }
    } else {
      // Form validation failed
      _scrollToTop();
    }
  }

  Widget _buildErrorMessage() {
    if (_errorMessage == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.mutedRed.withOpacity(0.1),
        border: Border.all(color: AppTheme.mutedRed),
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: AppTheme.mutedRed, size: 20),
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
    );
  }

  Widget _buildInfoMessage() {
    if (_infoMessage == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.calmGreen.withOpacity(0.1),
        border: Border.all(color: AppTheme.calmGreen),
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppTheme.calmGreen, size: 20),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Dismiss keyboard when tapping outside
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('Sign Up for Milo'),
          backgroundColor: AppTheme.gentleTeal,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo/Image
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
                  const SizedBox(height: 24),

                  // Error and info messages
                  _buildErrorMessage(),
                  _buildInfoMessage(),

                  // Name field
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                      ),
                      prefixIcon: const Icon(Icons.person),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      color: AppTheme.textColor,
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your name';
                      }
                      if (value.length < 2) {
                        return 'Name must be at least 2 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                      ),
                      prefixIcon: const Icon(Icons.email),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      color: AppTheme.textColor,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      // More robust email validation
                      if (!value.contains('@') || !value.contains('.') || value.length < 5) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Age field
                  TextFormField(
                    controller: _ageController,
                    decoration: InputDecoration(
                      labelText: 'Age',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                      ),
                      prefixIcon: const Icon(Icons.calendar_today),
                      helperText: 'Milo is designed for users age 55 and older',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      color: AppTheme.textColor,
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your age';
                      }
                      final age = int.tryParse(value);
                      if (age == null || age < 1 || age > 120) {
                        return 'Please enter a valid age';
                      }
                      if (age < 55) {
                        return 'Milo is designed for users 55 and older';
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
                      helperText: 'Password must be at least 8 characters with uppercase, lowercase, number, and special character',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      color: AppTheme.textColor,
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (value.length < 8) {
                        return 'Password must be at least 8 characters';
                      }

                      // Check for password complexity
                      bool hasUppercase = value.contains(RegExp(r'[A-Z]'));
                      bool hasLowercase = value.contains(RegExp(r'[a-z]'));
                      bool hasDigits = value.contains(RegExp(r'[0-9]'));
                      bool hasSpecialChars = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

                      List<String> missing = [];
                      if (!hasUppercase) missing.add('uppercase letter');
                      if (!hasLowercase) missing.add('lowercase letter');
                      if (!hasDigits) missing.add('number');
                      if (!hasSpecialChars) missing.add('special character');

                      if (missing.isNotEmpty) {
                        if (missing.length == 1) {
                          return 'Password must include at least one ${missing[0]}';
                        } else {
                          final lastItem = missing.removeLast();
                          return 'Password must include at least one ${missing.join(", ")} and one $lastItem';
                        }
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm Password field
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                      ),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.textSecondaryColor,
                        ),
                        onPressed: () {
                          _safeSetState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      color: AppTheme.textColor,
                    ),
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _signup(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Signup button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _signup,
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
                      'Create Account',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeLarge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Sign in link
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed('/login');
                      },
                      child: Text(
                        'Already have an account? Sign in',
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
}