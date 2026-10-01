import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/l10n/l10n.dart';
import 'package:trimmy/product/desk/wall_street_clock.dart';

void main() {
  group('WallStreetClock', () {
    test('uses the regular 9:30 to 16:00 session in winter and summer', () {
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 1, 6, 15),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 7, 6, 14),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 7, 6, 13, 29),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street opens in 1m.',
      );
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 7, 6, 20),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street opens in 17h 30m.',
      );
    });

    test(
      'weekend countdown uses elapsed time through the spring DST change',
      () {
        expect(
          WallStreetClock.label(
            DateTime.utc(2026, 3, 6, 21),
            englishLocalizations,
          ),
          'Stocks trade here 24/7. Wall Street opens in 2d 16h.',
        );
      },
    );

    test(
      'weekend countdown uses elapsed time through the autumn DST change',
      () {
        expect(
          WallStreetClock.label(
            DateTime.utc(2026, 10, 30, 20),
            englishLocalizations,
          ),
          'Stocks trade here 24/7. Wall Street opens in 2d 18h.',
        );
      },
    );

    test('closes for the published 2026 exchange holidays', () {
      final holidaysAtTenInNewYork = <DateTime>[
        DateTime.utc(2026, 1, 1, 15),
        DateTime.utc(2026, 1, 19, 15),
        DateTime.utc(2026, 2, 16, 15),
        DateTime.utc(2026, 4, 3, 14),
        DateTime.utc(2026, 5, 25, 14),
        DateTime.utc(2026, 6, 19, 14),
        DateTime.utc(2026, 7, 3, 14),
        DateTime.utc(2026, 9, 7, 14),
        DateTime.utc(2026, 11, 26, 15),
        DateTime.utc(2026, 12, 25, 15),
      ];

      for (final holiday in holidaysAtTenInNewYork) {
        expect(
          WallStreetClock.label(holiday, englishLocalizations),
          startsWith('Stocks trade here 24/7. Wall Street opens in '),
          reason: '$holiday should be an exchange holiday',
        );
      }
    });

    test('keeps federal-only holidays open when NYSE is open', () {
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 10, 12, 14),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 11, 11, 15),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
    });

    test('honors all three scheduled early-close rules', () {
      expect(
        WallStreetClock.label(
          DateTime.utc(2028, 7, 3, 16, 30),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street closes in 30m.',
      );
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 11, 27, 17, 30),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street closes in 30m.',
      );
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 12, 24, 17),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street closes in 1h.',
      );
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 12, 24, 18),
          englishLocalizations,
        ),
        startsWith('Stocks trade here 24/7. Wall Street opens in '),
      );
    });

    test(
      'does not invent an early close when July 3 is the observed holiday',
      () {
        expect(
          WallStreetClock.label(
            DateTime.utc(2026, 7, 3, 16),
            englishLocalizations,
          ),
          startsWith('Stocks trade here 24/7. Wall Street opens in '),
        );
        expect(
          WallStreetClock.label(
            DateTime.utc(2026, 7, 2, 18),
            englishLocalizations,
          ),
          'Stocks trade here 24/7. Wall Street closes in 2h.',
        );
      },
    );

    test('handles Saturday New Year exception from the published calendar', () {
      expect(WallStreetClock.verifiedScheduleThroughYear, 2028);
      expect(
        WallStreetClock.label(
          DateTime.utc(2027, 12, 31, 15),
          englishLocalizations,
        ),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
    });

    test('includes the known 2025 national day of mourning closure', () {
      expect(
        WallStreetClock.label(
          DateTime.utc(2025, 1, 9, 15),
          englishLocalizations,
        ),
        startsWith('Stocks trade here 24/7. Wall Street opens in '),
      );
    });

    test('reads in the app language with its own short units', () {
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 7, 6, 20),
          lookupAppLocalizations(const Locale('fr')),
        ),
        'Ici, les actions s’échangent 24\u00a0h/24, 7\u00a0j/7. '
        'Wall Street ouvre dans 17\u00a0h 30\u00a0min.',
      );
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 3, 6, 21),
          lookupAppLocalizations(const Locale('es')),
        ),
        'Aquí las acciones se negocian 24/7. Wall Street abre en 2\u00a0d 16\u00a0h.',
      );
      expect(
        WallStreetClock.label(
          DateTime.utc(2026, 1, 6, 15),
          lookupAppLocalizations(const Locale('pt')),
        ),
        'Aqui as ações são negociadas 24/7. Wall Street fecha em 6\u00a0h.',
      );
    });
  });
}
