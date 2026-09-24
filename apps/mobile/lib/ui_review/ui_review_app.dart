import 'package:flutter/material.dart';

import 'review_journey.dart';

abstract final class UiReviewColor {
  static const lemon = Color(0xFFF8F37B);
  static const ink = Color(0xFF251B38);
  static const pine = Color(0xFF006344);
  static const pineDark = Color(0xFF004B34);
  static const violet = Color(0xFF7455E8);
  static const lilac = Color(0xFFEBE6FF);
  static const pink = Color(0xFFF55984);
  static const mint = Color(0xFFBCE8C8);
  static const paper = Color(0xFFFFFCF2);
}

class TrimmyUiReviewApp extends StatelessWidget {
  const TrimmyUiReviewApp({super.key, this.startupReady});

  final Future<void>? startupReady;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Trimmy UI Review',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: UiReviewColor.pine,
        onPrimary: Colors.white,
        secondary: UiReviewColor.violet,
        onSecondary: Colors.white,
        surface: UiReviewColor.paper,
        onSurface: UiReviewColor.ink,
      ),
      fontFamily: 'Dejanire Sans',
      splashFactory: InkSparkle.splashFactory,
    ),
    home: ReviewJourney(startupReady: startupReady),
  );
}

Duration uiReviewDuration(BuildContext context, int milliseconds) {
  final media = MediaQuery.of(context);
  if (media.disableAnimations || media.accessibleNavigation) {
    return Duration.zero;
  }
  return Duration(milliseconds: milliseconds);
}
