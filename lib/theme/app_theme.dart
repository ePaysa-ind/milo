import 'package:flutter/material.dart';

/// AppTheme provides global styling for the Milo app
/// Specifically designed for users 55+ with accessibility in mind
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation

  // Color Palette from Design Guidelines
  static const Color backgroundColor = Color(0xFFFAF9F6); // Soft cream background
  static const Color textColor = Color(0xFF222222); // Dark gray text for high contrast

  // Add textPrimaryColor and make it identical to textColor for now
  static const Color textPrimaryColor = Color(0xFF222222); // Primary text color
  static const Color textSecondaryColor = Color(0xFF555555); // Secondary text

  static const Color calmBlue = Color(0xFF2F80ED); // Accent 1
  static const Color gentleTeal = Color(0xFF1ABC9C); // Accent 2
  static const Color mutedRed = Color(0xFFD9534F); // Error text
  static const Color calmGreen = Color(0xFF28A745); // Success message

  // Adding these missing color constants
  static const Color successColor = Color(0xFF28A745); // Same as calmGreen
  static const Color errorColor = Color(0xFFD9534F); // Same as mutedRed
  static const Color warningColor = Color(0xFFEFC050); // Warning color (amber)

  // Additional colors for ui elements
  static const Color textLightColor = Color(0xFF777777); // Lighter text, still accessible
  static const Color cardColor = Color(0xFFFEFDFC); // Almost white but still soft
  static const Color dividerColor = Color(0xFFEEEEEE); // Soft divider color

  // Font sizes - larger for better readability for seniors
  static const double fontSizeXSmall = 14.0; // Added missing fontSizeXSmall
  static const double fontSizeSmall = 16.0;
  static const double fontSizeMedium = 18.0;
  static const double fontSizeLarge = 20.0;
  static const double fontSizeXLarge = 24.0;
  static const double fontSizeXXLarge = 28.0;

  // Spacing - more generous spacing for better visual clarity
  static const double spacingSmall = 12.0;
  static const double spacingMedium = 20.0;
  static const double spacingLarge = 28.0;

  // Border radius - more rounded corners
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 12.0;
  static const double borderRadiusLarge = 20.0;
  static const double borderRadiusCircular = 100.0; // For circular buttons

  // Icon sizes
  static const double iconSizeSmall = 24.0;
  static const double iconSizeMedium = 32.0;
  static const double iconSizeLarge = 40.0;

  // Padding and margin
  static const EdgeInsets paddingSmall = EdgeInsets.all(spacingSmall);
  static const EdgeInsets paddingMedium = EdgeInsets.all(spacingMedium);
  static const EdgeInsets paddingLarge = EdgeInsets.all(spacingLarge);

  // Create standard border radius objects for easy access
  static final BorderRadius smallBorderRadius = BorderRadius.circular(borderRadiusSmall);
  static final BorderRadius mediumBorderRadius = BorderRadius.circular(borderRadiusMedium);
  static final BorderRadius largeBorderRadius = BorderRadius.circular(borderRadiusLarge);
  static final BorderRadius circularBorderRadius = BorderRadius.circular(borderRadiusCircular);

  /// The main ThemeData for the app
  static ThemeData get theme {
    return ThemeData(
      // General theming
      primaryColor: gentleTeal,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: ColorScheme.light(
        primary: gentleTeal,
        secondary: calmBlue,
        surface: cardColor,
        background: backgroundColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textColor,
        onBackground: textColor,
        onError: Colors.white,
      ),

      // AppBar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: fontSizeXLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        iconTheme: IconThemeData(
          color: textColor,
          size: iconSizeMedium,
        ),
      ),

      // Text theme
      textTheme: const TextTheme(
        // Headings
        headlineLarge: TextStyle(
          fontSize: fontSizeXXLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        headlineMedium: TextStyle(
          fontSize: fontSizeXLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        headlineSmall: TextStyle(
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        // Other text styles
        bodyLarge: TextStyle(
          fontSize: fontSizeMedium,
          color: textColor,
        ),
        bodyMedium: TextStyle(
          fontSize: fontSizeSmall,
          color: textColor,
        ),
        labelLarge: TextStyle(
          fontSize: fontSizeMedium,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
        titleLarge: TextStyle(
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        titleMedium: TextStyle(
          fontSize: fontSizeMedium,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),

      // Button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gentleTeal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: mediumBorderRadius,
          ),
          textStyle: const TextStyle(
            fontSize: fontSizeMedium,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: calmBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(
            fontSize: fontSizeSmall,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: mediumBorderRadius,
          borderSide: BorderSide(color: gentleTeal.withOpacity(0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: mediumBorderRadius,
          borderSide: BorderSide(color: gentleTeal.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: mediumBorderRadius,
          borderSide: const BorderSide(color: gentleTeal, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: mediumBorderRadius,
          borderSide: const BorderSide(color: errorColor),
        ),
        hintStyle: TextStyle(
          color: textLightColor,
          fontSize: fontSizeMedium,
        ),
        labelStyle: TextStyle(
          color: textSecondaryColor,
          fontSize: fontSizeMedium,
        ),
        errorStyle: const TextStyle(
          color: errorColor,
          fontSize: fontSizeSmall,
        ),
        prefixIconColor: textSecondaryColor,
      ),

      // Card theme
      cardTheme: CardTheme(
        color: cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: mediumBorderRadius,
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      ),

      // Divider theme
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 16,
      ),

      // SnackBar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: calmBlue,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: fontSizeSmall,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: smallBorderRadius,
        ),
      ),

      // Dialog theme
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(
          borderRadius: largeBorderRadius,
        ),
        backgroundColor: backgroundColor,
        elevation: 4,
        titleTextStyle: const TextStyle(
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        contentTextStyle: const TextStyle(
          fontSize: fontSizeMedium,
          color: textColor,
        ),
      ),

      // PopupMenu theme
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: mediumBorderRadius,
        ),
        elevation: 4,
        textStyle: const TextStyle(
          fontSize: fontSizeMedium,
          color: textColor,
        ),
      ),
    );
  }

  // Helper methods to get border radius for different components
  static BorderRadius getBorderRadiusForCard() => mediumBorderRadius;
  static BorderRadius getBorderRadiusForButton() => mediumBorderRadius;
  static BorderRadius getBorderRadiusForTextField() => mediumBorderRadius;
  static BorderRadius getBorderRadiusForDialog() => largeBorderRadius;
  static BorderRadius getBorderRadiusForAlert() => mediumBorderRadius;

  // Helper method for getting values from shapes
  static BorderRadius? getShapeBorderRadius(ShapeBorder? shape) {
    if (shape is RoundedRectangleBorder) {
      return shape.borderRadius as BorderRadius?;
    }
    return null;
  }

  // Helper method to get radius value
  static double getRadiusValue(BorderRadius? radius) {
    return radius?.topLeft.x ?? borderRadiusMedium;
  }
}