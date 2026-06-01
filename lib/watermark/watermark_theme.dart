// lib/watermark/watermark_theme.dart
import 'package:flutter/material.dart';

enum WatermarkTheme { dark, light, redAccent, filmGold }

extension WatermarkThemeExtension on WatermarkTheme {
  // Flutter colors (untuk preview overlay di kamera)
  Color get bgColor {
    switch (this) {
      case WatermarkTheme.dark:       return const Color(0xDD0A0E1A);
      case WatermarkTheme.light:      return const Color(0xDDFFFFFF);
      case WatermarkTheme.redAccent:  return const Color(0xDD0A0E1A);
      case WatermarkTheme.filmGold:   return const Color(0xDD1A1200);
    }
  }

  Color get primaryColor {
    switch (this) {
      case WatermarkTheme.dark:       return Colors.white;
      case WatermarkTheme.light:      return const Color(0xFF0A0E1A);
      case WatermarkTheme.redAccent:  return Colors.white;
      case WatermarkTheme.filmGold:   return const Color(0xFFFFD95A);
    }
  }

  Color get accentColor {
    switch (this) {
      case WatermarkTheme.dark:       return const Color(0xFF1E90FF);
      case WatermarkTheme.light:      return const Color(0xFF1E90FF);
      case WatermarkTheme.redAccent:  return const Color(0xFFE63946);
      case WatermarkTheme.filmGold:   return const Color(0xFFFF9500);
    }
  }

  Color get secondaryColor {
    switch (this) {
      case WatermarkTheme.dark:       return const Color(0xFF8C92A0);
      case WatermarkTheme.light:      return const Color(0xFF5A6070);
      case WatermarkTheme.redAccent:  return const Color(0xFF8C92A0);
      case WatermarkTheme.filmGold:   return const Color(0xFFB89040);
    }
  }
}
