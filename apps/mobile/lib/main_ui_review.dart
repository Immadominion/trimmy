import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui_review/ui_review_app.dart';
import 'ui_review/review_feedback.dart';

/// A deterministic, local-only entry point for reviewing Trimmy's mobile UI.
///
/// It does not create an account, open the API, or read production preferences.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) WidgetsBinding.instance.ensureSemantics();

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope',
    ], await rootBundle.loadString('assets/fonts/manrope/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Bricolage Grotesque',
    ], await rootBundle.loadString('assets/fonts/bricolage/OFL.txt'));
  });

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: UiReviewColor.paper,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: UiReviewColor.paper,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: UiReviewColor.paper,
    ),
  );

  await ReviewFeedback.shared.load();
  // Prepare the entrance cue while the animated splash is visible. On a cold
  // iPhone launch, preparing the button sound first could outlast the former
  // two-second splash gate and make the first coin entrance silent.
  final feedback = ReviewFeedback.shared;
  final entranceReady = feedback.prepareEntrance().timeout(
    const Duration(seconds: 6),
    onTimeout: () => debugPrint('Trimmy entrance audio startup timed out'),
  );
  unawaited(entranceReady.then((_) => feedback.prepareTap()));
  runApp(TrimmyUiReviewApp(startupReady: entranceReady));
}
