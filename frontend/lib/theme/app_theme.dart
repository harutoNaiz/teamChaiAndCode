import 'package:flutter/material.dart';

class AppTheme {
  // Apple-grade dark palette. True-black OLED base, layered system grays and a
  // single system-blue accent. Token NAMES are unchanged so the whole app
  // recolours from these values alone.
  static const Color darkBg = Color(0xFF000000); // systemBackground (base)
  static const Color darkSurface = Color(0xFF1C1C1E); // drawer / raised sheet
  static const Color darkCard = Color(0xFF1C1C1E); // secondarySystemBackground
  static const Color darkInputBg = Color(0xFF1C1C1E);
  static const Color darkBorder = Color(0xFF38383A); // opaque separator
  static const Color darkTextPrimary = Color(0xFFFFFFFF); // label
  static const Color darkTextSecondary = Color(0xFF98989F); // secondaryLabel
  static const Color brandAccent = Color(0xFF0A84FF); // systemBlue (dark)
  static const Color brandSecondary = Color(0xFF409CFF);
  static const Color warningOrange = Color(0xFFFF9F0A); // systemOrange (dark)
  static const Color dangerRed = Color(0xFFFF453A); // systemRed (dark)
  static const Color userBubbleDark = Color(0xFF2C2C2E); // tertiarySystemBackground
  static const Color assistantBubbleDark = Colors.transparent;

  // Layered elevation + accent tints (same names as before).
  static const Color darkElevated = Color(0xFF1C1C1E); // grouped cell surface
  static const Color darkInset = Color(0xFF2C2C2E); // nested control in a cell
  static const Color darkTextTertiary = Color(0xFF636366); // tertiaryLabel
  static const Color hairline = Color(0xFF2C2C2E); // hairline separator on black
  static const Color accentSubtle = Color(0x1F0A84FF); // systemBlue ~12% fill
  static const Color accentRing = Color(0x660A84FF); // systemBlue ~40% border

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
      cardTheme: CardThemeData(
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: darkTextSecondary, fontSize: 15),
      ),
      textTheme: const TextTheme(
        bodyLarge:
            TextStyle(color: darkTextPrimary, fontSize: 16, height: 1.45),
        bodyMedium:
            TextStyle(color: darkTextPrimary, fontSize: 14.5, height: 1.4),
        bodySmall: TextStyle(color: darkTextSecondary, fontSize: 12.5),
        titleMedium: TextStyle(
            color: darkTextPrimary, fontSize: 15, fontWeight: FontWeight.w600),
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
      cardTheme: CardThemeData(
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Color(0xFF8E8EA0), fontSize: 15),
      ),
    );
  }
}
