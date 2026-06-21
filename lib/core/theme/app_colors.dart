import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Background layers (near-black, ultra-premium dark)
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF161616);
  static const Color surfaceVariant = Color(0xFF212121);
  static const Color card = Color(0xFF1A1A1A);
  static const Color surfaceElevated = Color(0xFF242424);

  // Brand / Accent (Purple primary)
  static const Color primary = Color(0xFF6C5CE7); // Modern purple
  static const Color primaryLight = Color(0xFF8B7CEE);
  static const Color primaryDim = Color(0xFF5A4DB8);
  static const Color secondary = Color(0xFF1498DA); // Teal accent
  static const Color secondaryLight = Color(0xFF34B8E8);

  // Status
  static const Color success = Color(0xFF1DB854);
  static const Color warning = Color(0xFFFFB800);
  static const Color error = Color(0xFFFF4B55);

  // Text layers
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8A8A8A);
  static const Color textDisabled = Color(0xFF505050);
  static const Color textTertiary = Color(0xFF6B6B6B);

  // Timer ring
  static const Color timerRingBg = Color(0xFF242424);
  static const Color timerRingFill = primary;

  // Divider / Border
  static const Color divider = Color(0xFF252525);
  static const Color dividerLight = Color(0xFF2D2D2D);
}
