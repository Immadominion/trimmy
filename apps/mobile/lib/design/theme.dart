import 'package:flutter/material.dart';

/// Art direction revision 2. Financial data must never rely on color alone.
abstract final class TrimmyColors {
  static const paper = Color(0xFFFAF9F6);
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF141316);
  static const pine = Color(0xFF006344);
  static const yellow = Color(0xFFF3BB2C);
  static const pink = Color(0xFFEF4B77);
  static const violet = Color(0xFF7460CF);
  static const muted = Color(0xFF65616B);
  static const line = Color(0xFFD9D5D0);
  static const loss = Color(0xFFA52B3C);
  static const paleGreen = Color(0xFFE8F0EB);
}

RoundedSuperellipseBorder squircle([double radius = 24]) =>
    RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));

ThemeData trimmyTheme() {
  const text = TrimmyColors.ink;
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: TrimmyColors.paper,
    colorScheme: const ColorScheme.light(
      primary: TrimmyColors.pine,
      onPrimary: Colors.white,
      secondary: TrimmyColors.yellow,
      onSecondary: text,
      surface: TrimmyColors.paper,
      onSurface: text,
      error: TrimmyColors.loss,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme
        .copyWith(
          displayLarge: const TextStyle(
            fontSize: 54,
            fontWeight: FontWeight.w800,
            height: 1.04,
            letterSpacing: -2.4,
            color: text,
          ),
          headlineLarge: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: -1.3,
            color: text,
          ),
          headlineMedium: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.18,
            letterSpacing: -.9,
            color: text,
          ),
          titleLarge: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.25,
            letterSpacing: -.6,
            color: text,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.4,
            color: text,
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.55,
            color: text,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.5,
            color: text,
          ),
          bodySmall: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.5,
            color: TrimmyColors.muted,
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        )
        .apply(fontFamily: 'Manrope'),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: squircle(18),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: const BorderSide(color: TrimmyColors.ink, width: 1.2),
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: squircle(18),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: text,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: TrimmyColors.line,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: TrimmyColors.muted),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: TrimmyColors.muted),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: TrimmyColors.pine, width: 2),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: text,
      shape: squircle(16),
    ),
  );
}
