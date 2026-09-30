import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/l10n/app_locale.dart';
import 'package:trimmy/l10n/app_formats.dart';
import 'package:trimmy/core/paper_decimal.dart';

void main() {
  test('formatting preserves every digit of ledger-sized decimal strings', () {
    const raw = '9007199254740993.123456';
    final micros = paperMicros(raw);
    expect(paperDecimal(micros), raw);
    expect(
      AppFormats.english.number('9,007,199,254,740,993.123456'),
      '9,007,199,254,740,993.123456',
    );
    final fr = AppFormats.forLocale(const Locale('fr'));
    expect(
      fr
          .number('9,007,199,254,740,993.123456')
          .replaceAll(fr.groupSeparator, ''),
      '9007199254740993,123456',
    );
    expect(tryPaperMicros('0.0000001'), isNull);
    expect(tryPaperMicros('NaN'), isNull);
  });
  test(
    'comma input converts once; a point never silently multiplies money',
    () {
      final pt = AppFormats.forLocale(const Locale('pt', 'BR'));
      expect(pt.normalizeDecimalInput('1.234,56'), '1234.56');
      expect(pt.normalizeDecimalInput('1.250'), '1.250');
      expect(pt.normalizeDecimalInput('12,5'), '12.5');
      expect(pt.normalizeDecimalInput('1,2,3'), '1,2,3');
      expect(AppFormats.english.normalizeDecimalInput('12.5'), '12.5');
    },
  );
  test(
    'language preference survives restart and unknown choices follow the phone',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final c = AppLocaleController(preferences);
      await c.setLanguage(AppLanguage.portuguese);
      expect(AppLocaleController(preferences).language, AppLanguage.portuguese);
      await c.setLanguage(AppLanguage.phone);
      expect(preferences.containsKey(AppLocaleController.storageKey), false);
      expect(
        resolveAppLocale(
          [const Locale('ja')],
          [const Locale('en'), const Locale('fr')],
        ),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(
          [const Locale('fr', 'CA')],
          [const Locale('en'), const Locale('fr')],
          device: [],
        ),
        const Locale('fr', 'CA'),
      );
      c.dispose();
    },
  );
}
