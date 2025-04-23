import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// AppTheme provides global styling for the Milo app
/// Specifically designed for users 55+ with accessibility in mind
/// Optimized high contrast dark theme with readability improvements
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation

  // IMPROVEMENT 1: Changed pure black to softer dark gray to reduce eye strain
  static const Color backgroundColor = Color(0xFF1A1A1A); // Dark gray background instead of pure black

  // IMPROVEMENT 2: Slightly softened the pure white to reduce eye strain
  static const Color textColor = Color(0xFFF0F0F0); // Slightly off-white text
  static const Color textPrimaryColor = Color(0xFFF0F0F0); // Matching primary text
  static const Color textSecondaryColor = Color(0xFFCCCCCC); // Light gray but still high contrast

  // IMPROVEMENT 3: Adjusted accent colors for better contrast ratios
  static const Color calmBlue = Color(0xFF60AFFF); // Adjusted blue for 4.5:1 minimum contrast
  static const Color gentleTeal = Color(0xFF40E0D0); // Adjusted teal for better contrast (4.5:1 ratio)
  static const Color mutedRed = Color(0xFFFF6B6B); // Brighter red for errors with better contrast
  static const Color calmGreen = Color(0xFF4AE290); // Adjusted green for better contrast

  // Status colors - ensured all meet WCAG AA standards (4.5:1 contrast ratio)
  static const Color successColor = Color(0xFF4AE290); // Same as calmGreen
  static const Color errorColor = Color(0xFFFF6B6B); // Same as mutedRed
  static const Color warningColor = Color(0xFFFFD76E); // Adjusted for better contrast

  // IMPROVEMENT 4: Added additional UI colors for dark mode adaptations
  static const Color surfaceColor = Color(0xFF242424); // Slightly lighter than background
  static const Color cardColor = Color(0xFF2C2C2C); // Lighter than surface for elevation
  static const Color elevatedSurfaceColor = Color(0xFF353535); // For higher elevation elements
  static const Color dividerColor = Color(0xFF494949); // More visible on dark background
  static const Color focusIndicatorColor = Color(0xFF40E0D0); // Using teal for focus indicators

  // Font selection for better readability for 55+ users
  // IMPROVEMENT 10: Added font family specifications optimized for older users
  static const String primaryFontFamily = 'Roboto'; // Clean sans-serif, highly readable
  static const String secondaryFontFamily = 'Open Sans'; // Alternative clean sans-serif

  // Font sizes - INCREASED for better readability for seniors
  static const double fontSizeXSmall = 16.0; // Minimum for readability
  static const double fontSizeSmall = 18.0;
  static const double fontSizeMedium = 21.0; // Slightly increased from 20
  static const double fontSizeLarge = 24.0;
  static const double fontSizeXLarge = 28.0;
  static const double fontSizeXXLarge = 32.0;

  // Spacing - INCREASED for better visual clarity
  static const double spacingSmall = 16.0;
  static const double spacingMedium = 24.0;
  static const double spacingLarge = 32.0;

  // Border radius - more rounded corners
  static const double borderRadiusSmall = 10.0;
  static const double borderRadiusMedium = 16.0;
  static const double borderRadiusLarge = 24.0;
  static const double borderRadiusCircular = 100.0; // For circular buttons

  // Icon sizes - INCREASED for better visibility
  static const double iconSizeSmall = 28.0;
  static const double iconSizeMedium = 36.0;
  static const double iconSizeLarge = 48.0;

  // Padding and margin
  static const EdgeInsets paddingSmall = EdgeInsets.all(spacingSmall);
  static const EdgeInsets paddingMedium = EdgeInsets.all(spacingMedium);
  static const EdgeInsets paddingLarge = EdgeInsets.all(spacingLarge);

  // Accessibility-focused constants for 55+ users
  static const double touchTargetMinSize = 48.0; // Minimum touch target size
  static const double buttonMinHeight = 56.0;    // Taller buttons are easier to tap
  static const double buttonMinWidth = 120.0;    // Wider buttons are easier to tap
  static const double listItemMinHeight = 64.0;  // Taller list items easier to tap

  // IMPROVEMENT 7: Implemented consistent elevation model with corresponding colors
  static const Map<int, Color> elevationColors = {
    0: Color(0xFF1A1A1A), // Background
    1: Color(0xFF242424), // Surface
    2: Color(0xFF2C2C2C), // Cards
    4: Color(0xFF353535), // Dialogs, menus
    8: Color(0xFF3D3D3D), // App bar, navigation drawer
    16: Color(0xFF454545), // Floating action button
    24: Color(0xFF4D4D4D), // Modal bottom sheet
  };

  // IMPROVEMENT 9: Added semantic colors for better differentiation
  static const Map<String, Color> semanticColors = {
    'info': Color(0xFF60AFFF),      // Information (blue)
    'success': Color(0xFF4AE290),   // Success actions/status (green)
    'warning': Color(0xFFFFD76E),   // Warning status (amber)
    'error': Color(0xFFFF6B6B),     // Error status (red)
    'action': Color(0xFF40E0D0),    // Primary actions (teal)
    'highlight': Color(0xFFE5B8FF), // Highlighting content (purple)
    'inactive': Color(0xFF8A8A8A),  // Inactive elements (gray)
  };

  // NEW IMPROVEMENT: Added notification settings for better integration
  static const Map<String, dynamic> notificationSettings = {
    // Sound configurations - select based on context
    'sounds': {
      'default': 'notification_sound.wav',
      'gentle': 'gentle_notification.wav',
      'morning': 'morning_notification.wav',
      'midday': 'midday_notification.wav',
      'evening': 'evening_notification.wav',
    },
    // Vibration patterns - optimized for elderly users
    'vibrationPatterns': {
      'default': [0, 500, 200, 500],
      'gentle': [0, 300, 100, 300],
      'attention': [0, 500, 200, 500, 200, 500],
    },
    // Notification channel IDs
    'channelIds': {
      'nudges': 'nudge_channel',
      'reminders': 'reminder_channel',
      'memories': 'memory_channel',
      'system': 'system_channel',
    },
    // Notification channel names
    'channelNames': {
      'nudges': 'Therapeutic Nudges',
      'reminders': 'Daily Reminders',
      'memories': 'Memory Notifications',
      'system': 'System Notifications',
    },
    // Channel descriptions
    'channelDescriptions': {
      'nudges': 'Therapeutic nudge messages from Milo',
      'reminders': 'Daily mindfulness reminders',
      'memories': 'Notifications about your memories',
      'system': 'Important system notifications',
    },
    // Notification timeouts in milliseconds
    'timeouts': {
      'short': 5000,
      'medium': 10000,
      'long': 15000,
      'persistent': 0, // 0 means no timeout
    },
  };

  // Text styles with increased line height and adjusted weights for better readability
  static const TextStyle accessibleBodyText = TextStyle(
    fontFamily: primaryFontFamily,
    fontSize: fontSizeMedium,
    fontWeight: FontWeight.w500, // Medium weight for better visibility on dark background
    color: textColor,
    height: 1.5, // Increased line height for better readability
    letterSpacing: 0.15, // Slightly increased letter spacing
  );

  static var accentColor;

  /// The main ThemeData for the app
  static ThemeData get theme {
    return ThemeData(
      // General theming
      primaryColor: gentleTeal,
      scaffoldBackgroundColor: backgroundColor,
      fontFamily: primaryFontFamily,

      colorScheme: ColorScheme.dark(
        primary: gentleTeal,
        secondary: calmBlue,
        background: backgroundColor,
        error: errorColor,
        surface: surfaceColor,
        onPrimary: Colors.black, // Dark text on bright colors for contrast
        onSecondary: Colors.black, // Dark text on bright colors for contrast
        onBackground: textColor,
        onSurface: textColor,
        onError: Colors.black, // Dark text on bright error color
        brightness: Brightness.dark,
      ),

      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: elevationColors[8],
        foregroundColor: textColor,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light, // Status bar icons white
        titleTextStyle: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeXLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.25,
        ),
        iconTheme: const IconThemeData(
          color: textColor,
          size: iconSizeMedium,
        ),
        toolbarHeight: 72, // Increased toolbar height for better tappability
      ),

      // Text theme - INCREASED font sizes and weights
      textTheme: TextTheme(
        // Headings
        headlineLarge: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeXXLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
          height: 1.3,
          letterSpacing: 0.25,
        ),
        headlineMedium: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeXLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
          height: 1.3,
          letterSpacing: 0.25,
        ),
        headlineSmall: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
          height: 1.3,
          letterSpacing: 0.25,
        ),
        // Body text - IMPROVEMENT 10: Increased weight for better visibility
        bodyLarge: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeMedium,
          fontWeight: FontWeight.w500, // Medium weight instead of regular
          color: textColor,
          height: 1.5,
          letterSpacing: 0.15,
        ),
        bodyMedium: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeSmall,
          fontWeight: FontWeight.w500, // Medium weight instead of regular
          color: textColor,
          height: 1.5,
          letterSpacing: 0.15,
        ),
        labelLarge: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeMedium,
          fontWeight: FontWeight.w600, // Semi-bold for labels
          color: textColor,
          letterSpacing: 0.1,
        ),
      ),

      // Button themes - INCREASED size and padding
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gentleTeal,
          foregroundColor: Colors.black, // Dark text on bright button
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          minimumSize: const Size(buttonMinWidth, buttonMinHeight),
          // IMPROVEMENT 4: Added border for better definition
          side: BorderSide(color: gentleTeal.withOpacity(0.2), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadiusMedium),
          ),
          textStyle: TextStyle(
            fontFamily: primaryFontFamily,
            fontSize: fontSizeMedium,
            fontWeight: FontWeight.w600, // Semi-bold for buttons
            letterSpacing: 0.5, // Increased for better readability
          ),
          elevation: 4,
          shadowColor: gentleTeal.withOpacity(0.3), // Visible shadow
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gentleTeal, // Made consistent with primary color
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          minimumSize: const Size(buttonMinWidth, 48),
          textStyle: TextStyle(
            fontFamily: primaryFontFamily,
            fontSize: fontSizeSmall,
            fontWeight: FontWeight.w600, // Semi-bold
            letterSpacing: 0.5,
          ),
        ),
      ),

      // IconButton theme
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(touchTargetMinSize, touchTargetMinSize),
          padding: const EdgeInsets.all(12.0),
          iconSize: iconSizeMedium,
          foregroundColor: textColor,
          // IMPROVEMENT 8: Added focus indicator
          focusColor: focusIndicatorColor.withOpacity(0.2),
          highlightColor: focusIndicatorColor.withOpacity(0.3),
        ),
      ),

      // IMPROVEMENT 8: Focus theme for better keyboard navigation
      focusTheme: FocusThemeData(
        glowFactor: 0.0, // Disable glow
        highlightColor: focusIndicatorColor,
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor, // IMPROVEMENT 4: Using surface color
        contentPadding: const EdgeInsets.all(20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          borderSide: BorderSide(color: gentleTeal.withOpacity(0.5), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          borderSide: BorderSide(color: gentleTeal.withOpacity(0.5), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          borderSide: const BorderSide(color: gentleTeal, width: 2.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          borderSide: const BorderSide(color: errorColor, width: 2.0),
        ),
        hintStyle: TextStyle(
          fontFamily: primaryFontFamily,
          color: textColor.withOpacity(0.6),
          fontSize: fontSizeMedium,
          fontWeight: FontWeight.normal,
        ),
        labelStyle: TextStyle(
          fontFamily: primaryFontFamily,
          color: textColor.withOpacity(0.8),
          fontSize: fontSizeMedium,
          fontWeight: FontWeight.w500, // Medium weight
        ),
        errorStyle: TextStyle(
          fontFamily: primaryFontFamily,
          color: errorColor,
          fontSize: fontSizeSmall,
          fontWeight: FontWeight.w600, // Semi-bold error text
        ),
        prefixIconColor: textColor.withOpacity(0.7),
        isDense: false,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      ),

      // Card theme - IMPROVEMENT 7: Using elevation color system
      cardTheme: CardTheme(
        color: elevationColors[2], // Card elevation color
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          // IMPROVEMENT 4: Added subtle border
          side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        clipBehavior: Clip.antiAlias,
        shadowColor: Colors.black.withOpacity(0.4),
      ),

      // ListTile theme
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minVerticalPadding: 16.0,
        minLeadingWidth: 36,
        iconColor: gentleTeal, // Made consistent with primary color
        textColor: textColor,
        dense: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusSmall),
          // IMPROVEMENT 4: Added subtle highlight for boundaries
          side: BorderSide(color: Colors.transparent),
        ),
        selectedTileColor: gentleTeal.withOpacity(0.15), // Subtle selection
        selectedColor: gentleTeal, // Selected text color
      ),

      // Divider theme
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1.5,
        space: 24,
      ),

      // SnackBar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevationColors[4], // Using elevation system
        contentTextStyle: TextStyle(
          fontFamily: primaryFontFamily,
          color: textColor,
          fontSize: fontSizeMedium,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          // IMPROVEMENT 4: Added subtle border
          side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        elevation: 6,
        actionTextColor: gentleTeal,
      ),

      // Dialog theme - IMPROVEMENT 7: Using elevation system
      dialogTheme: DialogTheme(
        backgroundColor: elevationColors[4],
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusMedium),
          // IMPROVEMENT 4: Added subtle border
          side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        titleTextStyle: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.25,
        ),
        contentTextStyle: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeMedium,
          fontWeight: FontWeight.w500, // Medium weight
          color: textColor,
          height: 1.5, // Increased line height
        ),
      ),

      // Bottom Navigation Bar theme - IMPROVEMENT 7: Using elevation system
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: elevationColors[8],
        selectedItemColor: gentleTeal,
        unselectedItemColor: textColor.withOpacity(0.7),
        selectedLabelStyle: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeSmall,
          fontWeight: FontWeight.w600, // Semi-bold for selected
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: primaryFontFamily,
          fontSize: fontSizeSmall,
          letterSpacing: 0.5,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        landscapeLayout: BottomNavigationBarLandscapeLayout.spread,
      ),

      // Slider theme
      sliderTheme: SliderThemeData(
        activeTrackColor: gentleTeal,
        inactiveTrackColor: dividerColor,
        thumbColor: gentleTeal,
        overlayColor: gentleTeal.withOpacity(0.2),
        trackHeight: 8.0, // Thicker track for better visibility
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 16.0, // Larger thumb for easier targeting
          elevation: 4.0,
          pressedElevation: 8.0,
        ),
        overlayShape: const RoundSliderOverlayShape(
          overlayRadius: 30.0, // Larger overlay for better touch
        ),
        // IMPROVEMENT 8: Improved focus visualization
        valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
        valueIndicatorColor: gentleTeal,
        valueIndicatorTextStyle: TextStyle(
          fontFamily: primaryFontFamily,
          color: Colors.black,
          fontSize: fontSizeSmall,
          fontWeight: FontWeight.bold,
        ),
      ),

      // Switch theme - IMPROVEMENT 4: Improved visibility with borders
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
          if (states.contains(MaterialState.selected)) {
            return gentleTeal;
          }
          return Colors.white;
        }),
        trackColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
          if (states.contains(MaterialState.selected)) {
            return gentleTeal.withOpacity(0.5);
          }
          return Colors.grey.withOpacity(0.5);
        }),
        trackOutlineColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
          if (states.contains(MaterialState.selected)) {
            return gentleTeal.withOpacity(0.2);
          }
          return Colors.grey.withOpacity(0.2);
        }),
        trackOutlineWidth: MaterialStateProperty.all(1.0),
        thumbIcon: MaterialStateProperty.resolveWith<Icon?>((Set<MaterialState> states) {
          if (states.contains(MaterialState.selected)) {
            return const Icon(Icons.check, size: 12.0, color: Colors.black);
          }
          return null;
        }),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),

      // IMPROVEMENT 6: Set platform brightness to dark
      brightness: Brightness.dark,
    );
  }

  // IMPROVEMENT 5: Theme toggle helpers
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  // Method to get the theme based on preference
  static ThemeData getThemeForPreference(ThemePreference preference) {
    switch (preference) {
      case ThemePreference.light:
        return _getLightTheme();
      case ThemePreference.dark:
        return theme; // This is our optimized dark theme
      case ThemePreference.highContrast:
        return _getHighContrastTheme();
      case ThemePreference.system:
      // System would be handled at app level by checking platform brightness
        return theme;
    }
  }

  // Light theme implementation
  static ThemeData _getLightTheme() {
    // This would be the original light theme implementation
    // Simplified placeholder for now
    return ThemeData.light().copyWith(
      primaryColor: gentleTeal,
      // Other customizations would go here
    );
  }

  // High contrast theme with even more contrast
  static ThemeData _getHighContrastTheme() {
    return theme.copyWith(
      scaffoldBackgroundColor: Colors.black,
      colorScheme: theme.colorScheme.copyWith(
        background: Colors.black,
        surface: const Color(0xFF121212),
        onBackground: Colors.white,
        onSurface: Colors.white,
      ),
    );
  }

  // Helper method to get notification sound based on time window
  static String getNotificationSoundForTimeWindow(String timeWindow) {
    switch (timeWindow) {
      case 'morning':
        return notificationSettings['sounds']['morning'];
      case 'midday':
        return notificationSettings['sounds']['midday'];
      case 'evening':
        return notificationSettings['sounds']['evening'];
      default:
        return notificationSettings['sounds']['gentle'];
    }
  }

  // Helper method to get vibration pattern based on importance
  static List<int> getVibrationPattern(String importance) {
    return List<int>.from(notificationSettings['vibrationPatterns'][importance] ??
        notificationSettings['vibrationPatterns']['default']);
  }

  // Helper method to get notification channel ID
  static String getNotificationChannelId(String channelType) {
    return notificationSettings['channelIds'][channelType] ??
        notificationSettings['channelIds']['system'];
  }

  // Helper method to get notification channel name
  static String getNotificationChannelName(String channelType) {
    return notificationSettings['channelNames'][channelType] ??
        notificationSettings['channelNames']['system'];
  }

  // Helper method to get notification channel description
  static String getNotificationChannelDescription(String channelType) {
    return notificationSettings['channelDescriptions'][channelType] ??
        notificationSettings['channelDescriptions']['system'];
  }
}

// IMPROVEMENT 5: Theme preference enum
enum ThemePreference {
  light,
  dark,
  highContrast,
  system,
}