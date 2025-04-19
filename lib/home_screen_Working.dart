import 'package:flutter/material.dart';
import 'package:milo/services/auth_service.dart';
import 'package:milo/screens/conversation_screen.dart'; // Add this import
import 'package:milo/utils/logger.dart'; // Add this import for logger

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _recordScale = 1.0;
  double _viewScale = 1.0;
  double _chatScale = 1.0; // Add scale for chat button

  @override
  void initState() {
    super.initState();
    // Update to use Logger instead of print
    Logger.info('HomeScreen', 'HomeScreen initialized');

    // Check and log if user is authenticated
    final currentUser = AuthService().currentUser;
    if (currentUser != null) {
      Logger.info('HomeScreen', 'User is authenticated: ${currentUser.uid}');
    } else {
      Logger.warning('HomeScreen', 'Warning: No authenticated user on HomeScreen');
    }
  }

  // Add this method to start a new conversation
  void _startNewConversation() {
    Logger.info('HomeScreen', 'Starting new conversation');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ConversationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Logger.debug('HomeScreen', 'Building HomeScreen UI');
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
                    'Record a memory, listen to your memories, or chat with me!',
                    style: TextStyle(
                      fontFamily: 'Helvetica',
                      fontSize: 22,
                      color: Colors.deepOrange,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // 🎤 📁 💬 Action Buttons Row
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
                          Logger.info('HomeScreen', 'Navigating to Record screen');
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
                          Logger.info('HomeScreen', 'Navigating to Memories screen');
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

                  // Add Chat with Milo button
                  const SizedBox(height: 40),
                  GestureDetector(
                    onTapDown: (_) {
                      setState(() {
                        _chatScale = 1.1;
                      });
                    },
                    onTapUp: (_) {
                      setState(() {
                        _chatScale = 1.0;
                      });
                      _startNewConversation();
                    },
                    onTapCancel: () {
                      setState(() {
                        _chatScale = 1.0;
                      });
                    },
                    child: AnimatedScale(
                      scale: _chatScale,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.teal,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 30,
                              color: Colors.white,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Ask Milo Anything',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Add a sign out button for debugging
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: () async {
                      Logger.info('HomeScreen', 'Signing out user');
                      try {
                        await AuthService().signOut();
                        Logger.info('HomeScreen', 'User signed out successfully');
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/login');
                        }
                      } catch (e) {
                        Logger.error('HomeScreen', 'Error signing out: $e');
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