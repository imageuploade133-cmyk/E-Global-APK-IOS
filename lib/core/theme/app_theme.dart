import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily:
          '.SF Pro Text', // Native iOS San Francisco system font compatibility
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryContainer,
        secondary: AppColors.secondary,
        surface: Colors.white,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textLight,
      ),
      scaffoldBackgroundColor: Colors.white, // Bleached background
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textLight),
        titleTextStyle: TextStyle(
          color: AppColors.textLight,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: '.SF Pro Display',
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppColors.textLight,
          fontFamily: '.SF Pro Display',
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.textLight,
          fontFamily: '.SF Pro Display',
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: AppColors.textLight,
          fontFamily: '.SF Pro Text',
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.textLight,
          fontFamily: '.SF Pro Text',
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily:
          '.SF Pro Text', // Native iOS San Francisco system font compatibility
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: Colors.white, // Keep bright bleached aesthetic
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textLight,
      ),
      scaffoldBackgroundColor: Colors.white, // Keep bright bleached aesthetic
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textLight),
        titleTextStyle: TextStyle(
          color: AppColors.textLight,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: '.SF Pro Display',
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppColors.textLight,
          fontFamily: '.SF Pro Display',
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.textLight,
          fontFamily: '.SF Pro Display',
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: AppColors.textLight,
          fontFamily: '.SF Pro Text',
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.textLight,
          fontFamily: '.SF Pro Text',
        ),
      ),
    );
  }
}
