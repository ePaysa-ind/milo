// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:milo/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        await _authService.signInWithEmailAndPassword(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

        if (mounted) {
          print("✅ Login successful, navigating to home");
          // Use pushReplacementNamed to replace the current screen
          Navigator.pushReplacementNamed(context, '/home');

        }
      } on FirebaseAuthException catch (e) {
        setState(() {
          // User-friendly error messages based on Firebase error codes
          switch (e.code) {
            case 'invalid-credential':
            case 'wrong-password':
            case 'user-not-found':
              _errorMessage = 'The password you entered is incorrect, please input the correct password or reset your password.';
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
            default:
              _errorMessage = 'Login failed. Please check your credentials and try again.';
          }
        });
        print('Firebase Auth Error: ${e.code} - ${e.message}');
      } catch (e) {
        setState(() {
          _errorMessage = 'Connection error. Please check your internet connection and try again.';
        });
        print('General Error: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login to Milo'),
        backgroundColor: Colors.teal,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/images/milo_happy.gif',
                  height: 150,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Login'),
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/signup');
                  },
                  child: const Text('New user? Create an account'),
                ),
                TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => _buildPasswordResetDialog(),
                    );
                  },
                  child: const Text('Forgot Password?'),
                ),
              ],
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
            title: const Text('Reset Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: resetEmailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                if (resetErrorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      resetErrorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
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

                    setState(() {
                      isLoading = true;
                      resetErrorMessage = null;
                    });

                    try {
                      await _authService.sendPasswordResetEmail(email);

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password reset email sent! Please check your inbox.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } on FirebaseAuthException catch (e) {
                      setState(() {
                        isLoading = false;
                        switch (e.code) {
                          case 'user-not-found':
                            resetErrorMessage = 'No account found with this email address';
                            break;
                          case 'invalid-email':
                            resetErrorMessage = 'Please enter a valid email address';
                            break;
                          default:
                            resetErrorMessage = 'Error sending reset email: ${e.message}';
                        }
                      });
                    } catch (e) {
                      setState(() {
                        isLoading = false;
                        resetErrorMessage = 'Failed to send reset email. Please try again.';
                      });
                    }
                  },
                  child: const Text('Send Email'),
                ),
            ],
          );
        }
    );
  }
}