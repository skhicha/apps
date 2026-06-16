// lib/utils/app_theme.dart
// Peblo brand colors, typography, and reusable theme constants.

import 'package:flutter/material.dart';

class PebloColors {
  // ── Brand palette ──
  static const Color skyBlue = Color(0xFF4FC3F7);
  static const Color deepBlue = Color(0xFF1565C0);
  static const Color sunYellow = Color(0xFFFFD54F);
  static const Color grassGreen = Color(0xFF66BB6A);
  static const Color coralRed = Color(0xFFEF5350);
  static const Color softPurple = Color(0xFFCE93D8);
  static const Color warmOrange = Color(0xFFFF8A65);

  // ── Background gradients ──
  static const List<Color> skyGradient = [
    Color(0xFF1A237E), // Deep midnight
    Color(0xFF283593),
    Color(0xFF1565C0),
    Color(0xFF1976D2),
  ];

  // ── Story card ──
  static const Color storyCardBg = Color(0xFFFFF8E1);
  static const Color storyCardBorder = Color(0xFFFFD54F);

  // ── Quiz option colors ──
  static const Color optionDefault = Color(0xFFFFFFFF);
  static const Color optionCorrect = Color(0xFF81C784);
  static const Color optionWrong = Color(0xFFEF9A9A);

  // ── Text ──
  static const Color textDark = Color(0xFF1A237E);
  static const Color textLight = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF546E7A);
}

class PebloTextStyles {
  static const String fontFamily = 'Nunito'; // Fallback to system sans-serif

  static const TextStyle headline = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w900,
    color: PebloColors.textLight,
    letterSpacing: 0.5,
    height: 1.2,
  );

  static const TextStyle subheadline = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: PebloColors.sunYellow,
    letterSpacing: 0.3,
  );

  static const TextStyle storyText = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: PebloColors.textDark,
    height: 1.6,
    letterSpacing: 0.2,
  );

  static const TextStyle questionText = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: PebloColors.textLight,
    height: 1.4,
  );

  static const TextStyle optionText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: PebloColors.textDark,
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: PebloColors.textLight,
    letterSpacing: 0.5,
  );
}

class PebloSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

class PebloRadius {
  static const double sm = 12.0;
  static const double md = 20.0;
  static const double lg = 28.0;
  static const double xl = 36.0;
  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius button = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius option = BorderRadius.all(Radius.circular(sm));
}
