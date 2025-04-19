import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:milo/services/auth_service.dart';
import 'package:milo/theme/app_theme.dart';
import 'package:milo/utils/logger.dart';

/// Screen for handling MFA verification code input
class VerificationScreen extends StatefulWidget {
  final String email;

  const VerificationScreen({
    Key? key,
    required this.email,
  }) : super(key: key);

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _authService = AuthService();
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  bool _isDisposed = false;
  String? _errorMessage;

  // Timer for countdown
  Timer? _timer;
  int _remainingSeconds = 60; // 1 minute countdown for resend button

  @override
  void initState() {
    super.initState();
    Logger.info('VerificationScreen', 'Initializing with email: ${_maskEmail(widget.email)}');

    // Start countdown timer
    _startTimer();

    // Add listeners to focus nodes and controllers
    _setupInputListeners();
  }

  @override
  void dispose() {
    Logger.info('VerificationScreen', 'Disposing VerificationScreen');
    _isDisposed = true;

    // Clean up controllers and focus nodes
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }

    // Cancel timer if active
    _timer?.cancel();

    super.dispose();
  }

  // Safe setState that checks if the widget is still mounted
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    } else {
      Logger.warning('VerificationScreen', 'Attempted to setState after dispose');
    }
  }

  // Starts the countdown timer for resend button
  void _startTimer() {
    _safeSetState(() {
      _remainingSeconds = 60;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _safeSetState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  // Setup listeners for input fields to improve UX
  void _setupInputListeners() {
    for (int i = 0; i < 6; i++) {
      // Listen for text changes to auto-advance focus
      _controllers[i].addListener(() {
        if (_controllers[i].text.length == 1) {
          // Auto-advance to next field
          if (i < 5) {
            _focusNodes[i + 1].requestFocus();
          } else {
            // Last field - hide keyboard
            _focusNodes[i].unfocus();

            // Auto-submit if all fields are filled
            _checkAndSubmitCode();
          }
        }
      });
    }
  }

  // Check if all fields are filled and submit
  void _checkAndSubmitCode() {
    bool allFilled = true;
    for (var controller in _controllers) {
      if (controller.text.isEmpty) {
        allFilled = false;
        break;
      }
    }

    if (allFilled) {
      _verifyCode();
    }
  }

  // Handle verification code submission
  Future<void> _verifyCode() async {
    // Combine the 6 digits into a single code
    final code = _controllers.map((c) => c.text).join();

    if (code.length != 6) {
      _safeSetState(() {
        _errorMessage = 'Please enter all 6 digits of the verification code';
      });
      return;
    }

    Logger.info('VerificationScreen', 'Verifying code');

    _safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Complete the sign-in process with the verification code
      await _authService.completeSignIn(code);

      Logger.info('VerificationScreen', 'Verification successful, completing login');

      if (mounted && !_isDisposed) {
        // Navigate to home screen on success
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } on AuthException catch (e) {
      Logger.error('VerificationScreen', 'Auth exception during verification: ${e.code}');

      _safeSetState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });

      // Clear input fields on error for retry
      if (e.code == 'invalid_mfa_code') {
        for (var controller in _controllers) {
          controller.clear();
        }
        // Focus the first field again
        _focusNodes[0].requestFocus();
      }
    } catch (e) {
      Logger.error('VerificationScreen', 'Error during verification: $e');

      _safeSetState(() {
        _isLoading = false;
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
    }
  }

  // Resend verification code
  Future<void> _resendCode() async {
    if (_remainingSeconds > 0) {
      return; // Still in cooldown
    }

    _safeSetState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      Logger.info('VerificationScreen', 'Resending verification code');

      // Send a new verification code to the email
      await _authService.sendMfaVerificationCode(widget.email);

      _safeSetState(() {
        _isResending = false;
      });

      // Show success message
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A new verification code has been sent to your email',
              style: TextStyle(fontSize: AppTheme.fontSizeSmall),
            ),
            backgroundColor: AppTheme.calmGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Reset the countdown
      _startTimer();

      // Clear current input fields
      for (var controller in _controllers) {
        controller.clear();
      }
      // Focus the first field again
      _focusNodes[0].requestFocus();

    } catch (e) {
      Logger.error('VerificationScreen', 'Error resending code: $e');

      _safeSetState(() {
        _isResending = false;
        _errorMessage = 'Failed to resend verification code. Please try again.';
      });
    }
  }

  // Mask email for privacy in logs
  String _maskEmail(String email) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Verification'),
        backgroundColor: AppTheme.gentleTeal,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Security icon/image
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: AppTheme.gentleTeal.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.security,
                  size: 60,
                  color: AppTheme.gentleTeal,
                ),
              ),
              const SizedBox(height: 32),

              // Title and explanation
              Text(
                'Verification Code',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeXLarge,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              Text(
                'Please enter the 6-digit code sent to your email',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeMedium,
                  color: AppTheme.textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Display masked email
              Text(
                _maskEmail(widget.email),
                style: TextStyle(
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gentleTeal,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // 6-digit code input
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  return Container(
                    width: 44,
                    height: 60,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                      border: Border.all(color: AppTheme.gentleTeal.withOpacity(0.3)),
                    ),
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeLarge,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textColor,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                      // Handle backspace to go back to previous field
                      onChanged: (value) {
                        if (value.isEmpty && index > 0) {
                          _focusNodes[index - 1].requestFocus();
                        }
                      },
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: AppTheme.mutedRed,
                      fontSize: AppTheme.fontSizeSmall,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Resend code button with timer
              TextButton(
                onPressed: _remainingSeconds == 0 && !_isResending ? _resendCode : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.calmBlue,
                  backgroundColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: _isResending
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.calmBlue),
                  ),
                )
                    : Text(
                  _remainingSeconds > 0
                      ? 'Resend code in ${_remainingSeconds}s'
                      : 'Resend Code',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: _remainingSeconds > 0
                        ? AppTheme.textLightColor
                        : AppTheme.calmBlue,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Verify button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyCode,
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
                    'Verify',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeLarge,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Back to login button
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(
                  'Back to Login',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}