import 'package:flutter/material.dart';

/// Dejanire Sans carries controls and reading text. Bricolage appears only for major
/// display moments, so the interface keeps a calm reading rhythm.
abstract final class ProductColor {
  static const paper = Color(0xFFFFFFFF);
  static const paperRaised = Color(0xFFF8F8FB);
  static const ink = Color(0xFF251B38);
  static const muted = Color(0xFF787383);
  static const line = Color(0xFFEAE8EF);
  static const pine = Color(0xFF075D43);
  static const pineDark = Color(0xFF034631);
  static const mint = Color(0xFFDDEFE5);
  static const yellow = Color(0xFFFFC845);
  static const yellowDark = Color(0xFFD89500);
  static const violet = Color(0xFF7455E8);
  static const violetDark = Color(0xFF5336BA);
  static const gain = Color(0xFF087957);
  static const gainWash = Color(0xFFDCF2E8);
  static const loss = Color(0xFFB73549);
  static const lossWash = Color(0xFFF8E1E5);
}

RoundedSuperellipseBorder productSquircle([double radius = 24]) =>
    RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));

Duration productDuration(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

ThemeData productTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Dejanire Sans',
    scaffoldBackgroundColor: ProductColor.paper,
    colorScheme: const ColorScheme.light(
      primary: ProductColor.violet,
      onPrimary: Colors.white,
      secondary: ProductColor.yellow,
      onSecondary: ProductColor.ink,
      surface: ProductColor.paper,
      onSurface: ProductColor.ink,
      error: ProductColor.loss,
      onError: Colors.white,
    ),
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: ProductColor.paper,
      foregroundColor: ProductColor.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: ProductColor.paper,
      modalBackgroundColor: ProductColor.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: false,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ProductColor.paper,
      surfaceTintColor: Colors.transparent,
      shape: productSquircle(28),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ProductColor.violet,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        shape: productSquircle(20),
      ),
    ),
    textTheme: base.textTheme
        .apply(fontFamily: 'Dejanire Sans')
        .copyWith(
          displayLarge: const TextStyle(
            fontFamily: 'Bricolage Grotesque',
            fontSize: 48,
            height: .98,
            letterSpacing: -2.3,
            fontWeight: FontWeight.w800,
            color: ProductColor.ink,
          ),
          headlineLarge: const TextStyle(
            fontFamily: 'Bricolage Grotesque',
            fontSize: 32,
            height: 1.06,
            letterSpacing: -1.15,
            fontWeight: FontWeight.w800,
            color: ProductColor.ink,
          ),
          headlineMedium: const TextStyle(
            fontFamily: 'Dejanire Sans',
            fontSize: 25,
            height: 1.12,
            letterSpacing: -.75,
            fontWeight: FontWeight.w800,
            color: ProductColor.ink,
          ),
          titleLarge: const TextStyle(
            fontFamily: 'Dejanire Sans',
            fontSize: 20,
            height: 1.2,
            letterSpacing: -.35,
            fontWeight: FontWeight.w800,
            color: ProductColor.ink,
          ),
          titleMedium: const TextStyle(
            fontFamily: 'Dejanire Sans',
            fontSize: 16,
            height: 1.28,
            fontWeight: FontWeight.w700,
            color: ProductColor.ink,
          ),
          bodyLarge: const TextStyle(
            fontFamily: 'Dejanire Sans',
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: ProductColor.ink,
          ),
          bodyMedium: const TextStyle(
            fontFamily: 'Dejanire Sans',
            fontSize: 14,
            height: 1.42,
            fontWeight: FontWeight.w500,
            color: ProductColor.ink,
          ),
          bodySmall: const TextStyle(
            fontFamily: 'Dejanire Sans',
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: ProductColor.muted,
          ),
          labelLarge: const TextStyle(
            fontFamily: 'Dejanire Sans',
            fontSize: 15,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
          labelMedium: const TextStyle(
            fontFamily: 'Dejanire Sans',
            fontSize: 12,
            height: 1.2,
            letterSpacing: .25,
            fontWeight: FontWeight.w800,
          ),
        ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: ProductColor.paper,
      indicatorColor: ProductColor.mint,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Dejanire Sans',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: ProductColor.ink,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: ProductColor.line,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ProductColor.paperRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      hintStyle: const TextStyle(color: ProductColor.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: ProductColor.violet, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ProductColor.ink,
      shape: productSquircle(18),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}
