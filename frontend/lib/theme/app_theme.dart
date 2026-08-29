import 'package:flutter/material.dart';

class AppTheme {
  // ChatGPT Dark Color Palette
  static const Color darkBg = Color(0xFF212121);
  static const Color darkSurface = Color(0xFF171717);
  static const Color darkCard = Color(0xFF2F2F2F);
  static const Color darkInputBg = Color(0xFF2F2F2F);
  static const Color darkBorder = Color(0xFF383838);
  static const Color darkTextPrimary = Color(0xFFECECEC);
  static const Color darkTextSecondary = Color(0xFFB4B4B4);
  static const Color brandAccent = Color(0xFF10A37F); // OpenAI/Gemini sleek green/teal
  static const Color brandSecondary = Color(0xFF19C37D);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color userBubbleDark = Color(0xFF2F2F2F);
  static const Color assistantBubbleDark = Colors.transparent;

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: brandAccent,
      colorScheme: const ColorScheme.dark(
        primary: brandAccent,
        secondary: brandSecondary,
        surface: darkBg,
        error: dangerRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: darkTextPrimary),
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: darkSurface,
      ),
      cardTheme: CardTheme(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: darkBorder, width: 0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: darkTextSecondary, fontSize: 15),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: darkTextPrimary, fontSize: 16, height: 1.45),
        bodyMedium: TextStyle(color: darkTextPrimary, fontSize: 14.5, height: 1.4),
        bodySmall: TextStyle(color: darkTextSecondary, fontSize: 12.5),
        titleMedium: TextStyle(color: darkTextPrimary, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      primaryColor: brandAccent,
      colorScheme: const ColorScheme.light(
        primary: brandAccent,
        secondary: brandSecondary,
        surface: Color(0xFFF7F7F8),
        error: dangerRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.black87),
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Color(0xFFF9F9F9),
      ),
      cardTheme: CardTheme(
        color: const Color(0xFFF7F7F8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE5E5E5), width: 0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF4F4F4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Color(0xFF8E8EA0), fontSize: 15),
      ),
    );
  }
}
