import 'package:flutter/material.dart';
import 'package:milo/services/auth_service.dart'; // Add this import

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _recordScale = 1.0;
  double _viewScale = 1.0;

  @override
  void initState() {
    super.initState();
    // Add debug logging
    print('🏠 HomeScreen initialized');

    // Check and log if user is authenticated
    final currentUser = AuthService().currentUser;
    if (currentUser != null) {
      print('🏠 User is authenticated: ${currentUser.uid}');
    } else {
      print('🏠 Warning: No authenticated user on HomeScreen');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🏠 Building HomeScreen UI');
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // 🐶 Milo Image
                  Image.asset(
                    'assets/images/milo_happy.gif',
                    height: 150,
                  ),
                  const SizedBox(height: 20),

                  // 📝 Headline Text
                  const Text(
                    'Howdy from Milo!',
                    style: TextStyle(
                      fontFamily: 'Helvetica',
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 📣 Sub Text
                  const Text(
                    'Record a memory or listen to your memories.',
                    style: TextStyle(
                      fontFamily: 'Helvetica',
                      fontSize: 22,
                      color: Colors.deepOrange,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // 🎤 📁 Icon Buttons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 🎤 Record Memory Button
                      GestureDetector(
                        onTapDown: (_) {
                          setState(() {
                            _recordScale = 1.1;
                          });
                        },
                        onTapUp: (_) {
                          setState(() {
                            _recordScale = 1.0;
                          });
                          print('🎤 Navigating to Record screen');
                          Navigator.pushNamed(context, '/record');
                        },
                        onTapCancel: () {
                          setState(() {
                            _recordScale = 1.0;
                          });
                        },
                        child: AnimatedScale(
                          scale: _recordScale,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.mic,
                              size: 50,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),

                      // 📁 View Memories Button
                      GestureDetector(
                        onTapDown: (_) {
                          setState(() {
                            _viewScale = 1.1;
                          });
                        },
                        onTapUp: (_) {
                          setState(() {
                            _viewScale = 1.0;
                          });
                          print('📁 Navigating to Memories screen');
                          Navigator.pushNamed(context, '/memories');
                        },
                        onTapCancel: () {
                          setState(() {
                            _viewScale = 1.0;
                          });
                        },
                        child: AnimatedScale(
                          scale: _viewScale,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.folder_open,
                              size: 50,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Add a sign out button for debugging
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: () async {
                      print('👋 Signing out user');
                      try {
                        await AuthService().signOut();
                        print('👋 User signed out successfully');
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/login');
                        }
                      } catch (e) {
                        print('❌ Error signing out: $e');
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
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