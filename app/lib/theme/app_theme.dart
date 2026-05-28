import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Colors
  static const Color primaryCoral = Color(0xFFFF5A36);
  static const Color lightPeach = Color(0xFFFFF0ED);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color surfaceGray = Color(0xFFF8F9FA);
  
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textTertiary = Color(0xFFBDBDBD);
  
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color errorRed = Colors.red;
  static final Color shadowColor = Colors.black.withValues(alpha: 0.05);

  // Dimensions
  static const double pillRadius = 100.0;
  static const double cardRadius = 16.0;

  // Typography
  static const TextTheme _textTheme = TextTheme(
    displaySmall: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textPrimary), // H1
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary), // H2
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary), // Body Primary
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: textSecondary), // Body Secondary
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textPrimary), // Badges
  );

  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primaryCoral,
      scaffoldBackgroundColor: pureWhite,
      colorScheme: const ColorScheme.light(
        primary: primaryCoral,
        secondary: lightPeach,
        surface: pureWhite,
        error: Colors.red,
        onPrimary: pureWhite,
        onSecondary: textPrimary,
        onSurface: textPrimary,
        onError: pureWhite,
      ),
      textTheme: _textTheme,
      
      // Component Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryCoral,
          foregroundColor: pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)), // Pill-shaped
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: pureWhite,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceGray,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100), // Pill-shaped
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: textTertiary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: pureWhite,
        selectedItemColor: primaryCoral,
        unselectedItemColor: textSecondary,
      ),
    );
  }
}
