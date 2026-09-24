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

/// Normal builds open the stocks-first Trimmy product.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) WidgetsBinding.instance.ensureSemantics();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Manrope',
    ], await rootBundle.loadString('assets/fonts/manrope/OFL.txt'));
  });
  final preferences = await SharedPreferences.getInstance();
  final feedback = ReviewFeedback.shared;
  await feedback.load();
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
        ),
      ),
    ),
  );
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
