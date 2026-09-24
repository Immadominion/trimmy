import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/desk/wall_street_clock.dart';

void main() {
  group('WallStreetClock', () {
    test('uses the regular 9:30 to 16:00 session in winter and summer', () {
      expect(
        WallStreetClock.label(DateTime.utc(2026, 1, 6, 15)),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
      expect(
        WallStreetClock.label(DateTime.utc(2026, 7, 6, 14)),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
      expect(
        WallStreetClock.label(DateTime.utc(2026, 7, 6, 13, 29)),
        'Stocks trade here 24/7. Wall Street opens in 1m.',
      );
      expect(
        WallStreetClock.label(DateTime.utc(2026, 7, 6, 20)),
        'Stocks trade here 24/7. Wall Street opens in 17h 30m.',
      );
    });

    test(
      'weekend countdown uses elapsed time through the spring DST change',
      () {
        expect(
          WallStreetClock.label(DateTime.utc(2026, 3, 6, 21)),
          'Stocks trade here 24/7. Wall Street opens in 2d 16h.',
        );
      },
    );

    test(
      'weekend countdown uses elapsed time through the autumn DST change',
      () {
        expect(
          WallStreetClock.label(DateTime.utc(2026, 10, 30, 20)),
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
          WallStreetClock.label(holiday),
          startsWith('Stocks trade here 24/7. Wall Street opens in '),
          reason: '$holiday should be an exchange holiday',
        );
      }
    });

    test('keeps federal-only holidays open when NYSE is open', () {
      expect(
        WallStreetClock.label(DateTime.utc(2026, 10, 12, 14)),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
      expect(
        WallStreetClock.label(DateTime.utc(2026, 11, 11, 15)),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
    });

    test('honors all three scheduled early-close rules', () {
      expect(
        WallStreetClock.label(DateTime.utc(2028, 7, 3, 16, 30)),
        'Stocks trade here 24/7. Wall Street closes in 30m.',
      );
      expect(
        WallStreetClock.label(DateTime.utc(2026, 11, 27, 17, 30)),
        'Stocks trade here 24/7. Wall Street closes in 30m.',
      );
      expect(
        WallStreetClock.label(DateTime.utc(2026, 12, 24, 17)),
        'Stocks trade here 24/7. Wall Street closes in 1h.',
      );
      expect(
        WallStreetClock.label(DateTime.utc(2026, 12, 24, 18)),
        startsWith('Stocks trade here 24/7. Wall Street opens in '),
      );
    });

    test(
      'does not invent an early close when July 3 is the observed holiday',
      () {
        expect(
          WallStreetClock.label(DateTime.utc(2026, 7, 3, 16)),
          startsWith('Stocks trade here 24/7. Wall Street opens in '),
        );
        expect(
          WallStreetClock.label(DateTime.utc(2026, 7, 2, 18)),
          'Stocks trade here 24/7. Wall Street closes in 2h.',
        );
      },
    );

    test('handles Saturday New Year exception from the published calendar', () {
      expect(WallStreetClock.verifiedScheduleThroughYear, 2028);
      expect(
        WallStreetClock.label(DateTime.utc(2027, 12, 31, 15)),
        'Stocks trade here 24/7. Wall Street closes in 6h.',
      );
    });

    test('includes the known 2025 national day of mourning closure', () {
      expect(
        WallStreetClock.label(DateTime.utc(2025, 1, 9, 15)),
        startsWith('Stocks trade here 24/7. Wall Street opens in '),
      );
    });
  });
}
