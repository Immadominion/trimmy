import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/l10n/l10n.dart';
import 'package:trimmy/markets/config.dart';
import 'package:trimmy/markets/stock_research_host.dart';
import 'package:trimmy/product/app/product_app.dart';
import 'package:trimmy/product/settings/language_settings.dart';
import 'package:trimmy/ui_review/review_feedback.dart';
import 'package:trimmy/ui_review/welcome_review_screen.dart';

import '../support/l10n_harness.dart';

void main() {
  setUp(() async {
    await ReviewFeedback.shared.load();
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  Future<SharedPreferences> preferences([String? language]) async {
    SharedPreferences.setMockInitialValues({
      AppLocaleController.storageKey: ?language,
    });
    return SharedPreferences.getInstance();
  }

  Widget product(SharedPreferences preferences) => StockResearchHost(
    config: StockResearchConfig.parse(apiUrl: ''),
    child: TrimmyProductApp(
      preferences: preferences,
      account: null,
      accountConfigurationFailed: false,
    ),
  );

  testWidgets('the product app follows the phone until a language is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(product(await preferences()));
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, isNull);
    expect(app.localizationsDelegates, AppLocalizations.localizationsDelegates);
    expect(app.supportedLocales, AppLocalizations.supportedLocales);
    final context = tester.element(find.byType(WelcomeReviewScreen));
    expect(Localizations.localeOf(context).languageCode, 'en');
    expect(AppLocalizations.of(context), isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a saved language opens the app in it and a change applies now', (
    tester,
  ) async {
    await tester.pumpWidget(product(await preferences('fr')));
    await tester.pump();

    var context = tester.element(find.byType(WelcomeReviewScreen));
    expect(Localizations.localeOf(context), const Locale('fr'));
    expect(context.l10n.commonContinue, 'Continuer');

    await AppLocaleScope.maybeOf(context)!.setLanguage(AppLanguage.portuguese);
    await tester.pump();
    context = tester.element(find.byType(WelcomeReviewScreen));
    expect(Localizations.localeOf(context), const Locale('pt', 'BR'));
    expect(context.formats.usdFixed(1234.5), 'US\$ 1.234,50');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the picker lists every language by its own name and switches', (
    tester,
  ) async {
    final controller = AppLocaleController(await preferences());
    await tester.pumpWidget(
      localizedTestApp(
        controller: controller,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showLanguagePicker(
                  context,
                  AppLocaleScope.maybeOf(context)!,
                ),
                child: Text(context.l10n.settingsLanguage),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    expect(find.text('Phone language'), findsOneWidget);
    for (final name in [
      'English',
      'Español (Latinoamérica)',
      'Português (Brasil)',
      'Français',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(controller.language, AppLanguage.french);
    expect(find.text('Langue'), findsOneWidget);

    await tester.tap(find.text('Langue'));
    await tester.pumpAndSettle();
    // Language names never change with the app's language.
    expect(find.text('Langue du téléphone'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('Langue du téléphone'));
    await tester.pumpAndSettle();
    expect(controller.language, AppLanguage.phone);
    expect(find.text('Language'), findsOneWidget);
    controller.dispose();
  });
}
