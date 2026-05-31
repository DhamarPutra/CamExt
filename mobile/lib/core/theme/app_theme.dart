import 'package:flutter/material.dart';

class AppTheme {
  static const Color darkBg = Color(0xFF0D0E12);
  static const Color cardBg = Color(0xFF161822);
  static const Color accentNeonGreen = Color(0xFF39FF14);
  static const Color accentNeonCyan = Color(0xFF00E5FF);
  static const Color textMain = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color borderGlow = Color(0xFF282B3E);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: accentNeonCyan,
      colorScheme: const ColorScheme.dark(
        primary: accentNeonCyan,
        secondary: accentNeonGreen,
        background: darkBg,
        surface: cardBg,
      ),
      cardTheme: const CardThemeData(
        color: cardBg,
        elevation: 8,
        margin: EdgeInsets.all(0),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderGlow, width: 1.5),
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF1C1F2E),
        hintStyle: TextStyle(color: textMuted),
        labelStyle: TextStyle(color: textMain),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: borderGlow),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: borderGlow),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: accentNeonCyan, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentNeonCyan,
          foregroundColor: darkBg,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
