import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand orange — the app identity
  static constColor primary = Color(0xFFFF6B00);
  static constColor primaryDark = Color(0xFFE05500);
  static constColor primaryLight = Color(0xFFFF9A40);

  // Deep dark background
  static constColor background = Color(0xFF0D0D0D);
  static constColor surface = Color(0xFF1A1A1A);
  static constColor surfaceVariant = Color(0xFF262626);

  // Text
  static constColor onPrimary = Color(0xFFFFFFFF);
  static constColor onBackground = Color(0xFFFFFFFF);
  static constColor onSurface = Color(0xFFE0E0E0);
  static constColor textMuted = Color(0xFF888888);

  // Error / offline
  static constColor error = Color(0xFFCF6679);
  static constColor errorDark = Color(0xFF9B2C2C);
  static constColor offlineGradientStart = Color(0xFF1A1A2E);
  static constColor offlineGradientEnd = Color(0xFF16213E);

  // Success
  static constColor success = Color(0xFF4CAF50);
  static constColor successLight = Color(0xFF81C784);
}
