import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account/account_host.dart';
import 'design/theme.dart';
import 'core/calendar_scope.dart';
import 'features/office/office_shell.dart';
import 'features/practice/practice_controller.dart';
import 'markets/stock_research_host.dart';
import 'product/app/product_app.dart';
import 'ui_review/review_feedback.dart';
import 'account/config.dart';
import 'product/analytics/product_events.dart'
    show ProductEvents, SharedPreferencesEventsStore;
import 'product/analytics/usage_scope.dart' show UsageLocale;

/// Normal builds open the stocks-first Trimmy product.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) WidgetsBinding.instance.ensureSemantics();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope',
    ], await rootBundle.loadString('assets/fonts/manrope/OFL.txt'));
  });
  // Screens are laid out for a phone held upright: in landscape a 91% sheet
  // plus the keyboard leaves almost no room. Tablets keep every orientation.
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  if (!kIsWeb &&
      view != null &&
      view.physicalSize.shortestSide / view.devicePixelRatio < 600) {
    // Not awaited: startup never waits on the platform to answer.
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
  }
  final preferences = await SharedPreferences.getInstance();
  final feedback = ReviewFeedback.shared;
  await feedback.load();
  final usage = await _usage(preferences);
  // The actual Settings screen controls these persisted device preferences.
  runApp(
    StockResearchHost(
      child: PracticeAccountHost(
        preferences: preferences,
        builder: (context, account, configurationFailed) => TrimmyProductApp(
          preferences: preferences,
          account: account,
          accountConfigurationFailed: configurationFailed,
          showStartupSplash: true,
          usage: usage,
        ),
      ),
    ),
  );
}

/// First-party usage events for phone builds that know their API (see
/// product/analytics). None for other builds; never blocks startup.
Future<ProductEvents?> _usage(SharedPreferences preferences) async {
  final origin = PracticeAccountConfig.fromEnvironment().apiUri;
  final platform = switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
  if (kIsWeb || origin == null || platform == null) return null;
  try {
    final usage = ProductEvents(
      origin: origin,
      platform: platform,
      appVersion: ProductEvents.buildVersion,
      locale: () => UsageLocale.tag,
      store: SharedPreferencesEventsStore(preferences),
    );
    await usage.load().timeout(const Duration(seconds: 2));
    return usage;
  } catch (_) {
    return null;
  }
}

/// Retained for migration tests and the explicit legacy entry point.
Future<void> runLegacyApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the browser preview's real controls available to assistive technology.
  if (kIsWeb) WidgetsBinding.instance.ensureSemantics();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope',
    ], await rootBundle.loadString('assets/fonts/manrope/OFL.txt'));
  });
  final controller = await PracticeController.load();
  runApp(TrimmyApp(controller: controller));
}

class TrimmyApp extends StatelessWidget {
  const TrimmyApp({super.key, required this.controller});
  final PracticeController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Trimmy: Mobile office',
    debugShowCheckedModeBanner: false,
    theme: trimmyTheme(),
    builder: (context, child) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              controller.reduceMotion ||
              MediaQuery.disableAnimationsOf(context),
        ),
        child: CalendarScope(
          readDate: () => controller.currentLocalDate,
          child: child!,
        ),
      ),
    ),
    home: OfficeShell(controller: controller),
  );
}
