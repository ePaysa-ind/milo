import 'package:flutter/material.dart';
import 'package:milo/services/auth_service.dart';
import 'package:milo/screens/conversation_screen.dart';
import 'package:milo/utils/logger.dart';
import 'theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Bottom navigation current index
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    Logger.info('HomeScreen', 'HomeScreen initialized');

    // Check and log if user is authenticated
    final currentUser = AuthService().currentUser;
    if (currentUser != null) {
      Logger.info('HomeScreen', 'User is authenticated: ${currentUser.uid}');
    } else {
      Logger.warning('HomeScreen', 'Warning: No authenticated user on HomeScreen');
    }
  }

  // Handle navigation between tabs
  void _onTabTapped(int index) {
    Logger.info('HomeScreen', 'Tab changed to $index');

    // Special case for sign out (last tab)
    if (index == 4) {
      _signOut();
      return;
    }

    setState(() {
      _currentIndex = index;
    });

    // Navigate based on the tab index
    switch (index) {
      case 0:
      // Already on home
        break;
      case 1:
        Logger.info('HomeScreen', 'Navigating to Record screen');
        Navigator.pushNamed(context, '/record');
        break;
      case 2:
        Logger.info('HomeScreen', 'Navigating to Memories screen');
        Navigator.pushNamed(context, '/memories');
        break;
      case 3:
        Logger.info('HomeScreen', 'Starting new conversation');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ConversationScreen(),
          ),
        );
        break;
    }
  }

  // Sign out method
  Future<void> _signOut() async {
    Logger.info('HomeScreen', 'Signing out user');
    try {
      await AuthService().signOut();
      Logger.info('HomeScreen', 'User signed out successfully');
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      Logger.error('HomeScreen', 'Error signing out: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Logger.debug('HomeScreen', 'Building HomeScreen UI');
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(AppTheme.spacingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 🐶 Milo Image
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF), // Light cream background
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/images/milo_happy.gif',
                        height: 100,
                      ),
                    ),
                  ),
                  SizedBox(height: AppTheme.spacingMedium),

                  // 📝 Headline Text
                  Text(
                    'Howdy from Milo!',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeXLarge,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.gentleTeal,
                    ),
                  ),
                  SizedBox(height: AppTheme.spacingSmall),

                  // 📣 Sub Text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeMedium,
                          color: AppTheme.textColor,
                        ),
                        children: [
                          TextSpan(
                            text: 'Milo is your personal therapist, confidante & organizer! Your best friend!'
                                '\n\n With',
                          ),
                          WidgetSpan(
                            child: Icon(
                              Icons.favorite,
                              color: Colors.red,
                              size: AppTheme.fontSizeMedium,
                            ),
                            alignment: PlaceholderAlignment.middle,
                          ),
                          TextSpan(
                            text: ' for the 50+, by the 50+',
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: AppTheme.spacingLarge),

                  // Feature cards with Material icons
                  _buildFeatureCard(
                    icon: Icons.mic_rounded,
                    title: 'Reflective',
                    description: 'Record life stories, wisdom, and feelings',
                    iconColor: Colors.red.shade400,
                  ),
                  SizedBox(height: AppTheme.spacingMedium),

                  //_buildFeatureCard(
                   // icon: Icons.self_improvement_rounded,
                    //title: 'Calm',
                    //description: 'Take a deep breath and reflect.',
                    //iconColor: Colors.blue.shade400,
                  //),
                  //SizedBox(height: AppTheme.spacingMedium),

                  _buildFeatureCard(
                    icon: Icons.folder_special_rounded,
                    title: 'Organized',
                    description: 'Save precious memories in one simple folder.',
                    iconColor: Colors.amber.shade700,
                  ),
                  SizedBox(height: AppTheme.spacingMedium),

                  _buildFeatureCard(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Conversational',
                    description: 'Speak freely, AI responds with care.',
                    iconColor: Colors.green.shade600,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // Bottom navigation
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade200,
              width: 1.0,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  index: 0,
                ),
                _buildNavItem(
                  icon: Icons.mic_rounded,
                  label: 'Record',
                  index: 1,
                ),
                _buildNavItem(
                  icon: Icons.folder_rounded,
                  label: 'Memories',
                  index: 2,
                ),
                _buildNavItem(
                  icon: Icons.question_answer_rounded,
                  label: 'Ask Milo',
                  index: 3,
                ),
                _buildNavItem(
                  icon: Icons.logout,
                  label: 'Sign Out',
                  index: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Feature card widget with Material icon
  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color iconColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 32,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor, // Using textColor instead of textPrimaryColor
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Navigation item builder
  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final bool isSelected = _currentIndex == index;
    final Color activeColor = AppTheme.gentleTeal;
    final Color inactiveColor = Colors.grey.shade500;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 26,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}