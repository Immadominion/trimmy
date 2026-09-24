import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/product/market/paper_portfolio.dart';
import 'package:trimmy/product/market/paper_portfolio_cache.dart';

const _principalA = '71000000-0000-4000-8000-000000000001';
const _principalB = '71000000-0000-4000-8000-000000000002';
const _keyA = 'trimmy.paper.portfolio-cache.v1.$_principalA';
const _mintA = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const _mintB = 'So11111111111111111111111111111111111111112';
final _now = DateTime.utc(2026, 9, 20, 12, 0, 5);
final _acceptedAt = DateTime.utc(2026, 9, 20, 12, 0, 4);
final _expiresAt = DateTime.utc(2026, 9, 20, 12, 0, 54);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round trips fresh v2 valuation only for the same identity', () async {
    final preferences = await SharedPreferences.getInstance();
    final snapshot = _snapshot();

    await PaperPortfolioCache.write(
      preferences,
      _principalA,
      snapshot,
      now: _now,
    );
    final restored = await PaperPortfolioCache.read(
      preferences,
      _principalA,
      now: _now.add(const Duration(seconds: 20)),
    );

    final raw =
        jsonDecode(preferences.getString(_keyA)!) as Map<String, dynamic>;
    expect(raw['schemaVersion'], 2);
    expect(
      (raw['portfolio'] as Map<String, dynamic>)['valuation'],
      isA<Map<String, dynamic>>(),
    );
    expect(restored?.revision, 2);
    expect(restored?.cashPaper, '9499.5');
    expect(restored?.positions.single.realizedGainPaper, '-0.25');
    expect(restored?.recentOrders.single.orderId, startsWith('44000000'));
    expect(restored?.valuation.sourceIncluded, isTrue);
    expect(restored?.valuation.status, PaperPortfolioValuationStatus.complete);
    expect(restored?.valuation.knownValuePaper, '10099.5');
    expect(restored?.valuation.totalPaper, '10099.5');
    expect(restored?.valuation.positions.single.marketValuePaper, '600');
    expect(
      restored?.valuation.positionFor('apple', _mintA)?.expiresAt,
      _expiresAt,
    );
    expect(await PaperPortfolioCache.read(preferences, _principalB), isNull);
  });

  test(
    'expiry boundary downgrades cached price without extending its TTL',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await PaperPortfolioCache.write(
        preferences,
        _principalA,
        _snapshot(),
        now: _now,
      );

      final restored = await PaperPortfolioCache.read(
        preferences,
        _principalA,
        now: _expiresAt,
      );

      expect(
        restored?.valuation.status,
        PaperPortfolioValuationStatus.unavailable,
      );
      expect(restored?.valuation.pricedPositionCount, 0);
      expect(restored?.valuation.knownValuePaper, '9499.5');
      expect(restored?.valuation.totalPaper, isNull);
      expect(
        restored?.valuation.positions.single.status,
        PaperPositionValuationStatus.unavailable,
      );
      expect(restored?.valuation.positions.single.expiresAt, isNull);

      final raw =
          jsonDecode(preferences.getString(_keyA)!) as Map<String, dynamic>;
      final portfolio = raw['portfolio'] as Map<String, dynamic>;
      final valuation = portfolio['valuation'] as Map<String, dynamic>;
      final rows = valuation['positions'] as List<dynamic>;
      expect(
        (rows.single as Map<String, dynamic>)['expiresAt'],
        '2026-09-20T12:00:54.000Z',
      );
      expect(raw['cachedAt'], '2026-09-20T12:00:05.000Z');
    },
  );

  test('reads schema-one wrapper as an honest unavailable valuation', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_keyA, jsonEncode(_legacyWrapper()));

    final restored = await PaperPortfolioCache.read(
      preferences,
      _principalA,
      now: _now,
    );

    expect(restored, isNotNull);
    expect(restored!.valuation.sourceIncluded, isFalse);
    expect(
      restored.valuation.status,
      PaperPortfolioValuationStatus.unavailable,
    );
    expect(restored.valuation.openPositionCount, 1);
    expect(restored.valuation.pricedPositionCount, 0);
    expect(restored.valuation.knownValuePaper, '9499.5');
    expect(restored.valuation.totalPaper, isNull);
    expect(restored.valuation.positions.single.key.assetId, 'apple');
    expect(restored.valuation.positions.single.key.variantMint, _mintA);
  });

  test('discards valuation joined to the wrong exact mint', () async {
    final preferences = await SharedPreferences.getInstance();
    await PaperPortfolioCache.write(
      preferences,
      _principalA,
      _snapshot(),
      now: _now,
    );
    final wrapper =
        jsonDecode(preferences.getString(_keyA)!) as Map<String, dynamic>;
    final portfolio = wrapper['portfolio'] as Map<String, dynamic>;
    final valuation = portfolio['valuation'] as Map<String, dynamic>;
    final rows = valuation['positions'] as List<dynamic>;
    (rows.single as Map<String, dynamic>)['variantMint'] = _mintB;
    await preferences.setString(_keyA, jsonEncode(wrapper));

    expect(
      await PaperPortfolioCache.read(preferences, _principalA, now: _now),
      isNull,
    );
    expect(preferences.getString(_keyA), isNull);
  });

  test('discards valuation with inexact fixed-point arithmetic', () async {
    final preferences = await SharedPreferences.getInstance();
    await PaperPortfolioCache.write(
      preferences,
      _principalA,
      _snapshot(),
      now: _now,
    );
    final wrapper =
        jsonDecode(preferences.getString(_keyA)!) as Map<String, dynamic>;
    final portfolio = wrapper['portfolio'] as Map<String, dynamic>;
    final valuation = portfolio['valuation'] as Map<String, dynamic>;
    final rows = valuation['positions'] as List<dynamic>;
    (rows.single as Map<String, dynamic>)['marketValuePaper'] = '600.000001';
    await preferences.setString(_keyA, jsonEncode(wrapper));

    expect(
      await PaperPortfolioCache.read(preferences, _principalA, now: _now),
      isNull,
    );
    expect(preferences.getString(_keyA), isNull);
  });

  test('round trips derived values beyond the stored ledger cap', () async {
    final preferences = await SharedPreferences.getInstance();

    await PaperPortfolioCache.write(
      preferences,
      _principalA,
      _maximumDerivedSnapshot(),
      now: _now,
    );
    final restored = await PaperPortfolioCache.read(
      preferences,
      _principalA,
      now: _now,
    );

    expect(
      restored?.valuation.positions.single.marketValuePaper,
      '999999999999998000',
    );
    expect(
      restored?.valuation.positions.single.unrealizedGainPaper,
      '999999999999988000.000001',
    );
    expect(restored?.valuation.totalPaper, '999999999999998000.000001');
  });

  test('discards 31-digit derived micros and 16-digit ledger micros', () async {
    final preferences = await SharedPreferences.getInstance();
    await PaperPortfolioCache.write(
      preferences,
      _principalA,
      _maximumDerivedSnapshot(),
      now: _now,
    );
    var wrapper =
        jsonDecode(preferences.getString(_keyA)!) as Map<String, dynamic>;
    var portfolio = wrapper['portfolio'] as Map<String, dynamic>;
    var valuation = portfolio['valuation'] as Map<String, dynamic>;
    var rows = valuation['positions'] as List<dynamic>;
    (rows.single as Map<String, dynamic>)['marketValuePaper'] = '1'.padRight(
      25,
      '0',
    );
    await preferences.setString(_keyA, jsonEncode(wrapper));

    expect(
      await PaperPortfolioCache.read(preferences, _principalA, now: _now),
      isNull,
    );

    await PaperPortfolioCache.write(
      preferences,
      _principalA,
      _maximumDerivedSnapshot(),
      now: _now,
    );
    wrapper = jsonDecode(preferences.getString(_keyA)!) as Map<String, dynamic>;
    portfolio = wrapper['portfolio'] as Map<String, dynamic>;
    final positions = portfolio['positions'] as List<dynamic>;
    (positions.single as Map<String, dynamic>)['quantity'] = '1000000000';
    await preferences.setString(_keyA, jsonEncode(wrapper));

    expect(
      await PaperPortfolioCache.read(preferences, _principalA, now: _now),
      isNull,
    );
  });

  test(
    'serializes writes per principal while other identities proceed',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondStarted = false;
      var otherPrincipalStarted = false;

      final first = PaperPortfolioCache.write(
        preferences,
        _principalA,
        _snapshot(revision: 1),
        now: _now,
        writerForTesting: (key, value) async {
          firstStarted.complete();
          await releaseFirst.future;
          return preferences.setString(key, value);
        },
      );
      await firstStarted.future;
      final second = PaperPortfolioCache.write(
        preferences,
        _principalA,
        _snapshot(revision: 2),
        now: _now,
        writerForTesting: (key, value) async {
          secondStarted = true;
          return preferences.setString(key, value);
        },
      );
      final otherPrincipal = PaperPortfolioCache.write(
        preferences,
        _principalB,
        _snapshot(revision: 3),
        now: _now,
        writerForTesting: (key, value) async {
          otherPrincipalStarted = true;
          return preferences.setString(key, value);
        },
      );
      await Future<void>.delayed(Duration.zero);

      expect(secondStarted, isFalse);
      expect(otherPrincipalStarted, isTrue);
      await otherPrincipal;
      releaseFirst.complete();
      await Future.wait([first, second]);

      expect(secondStarted, isTrue);
      expect(
        (await PaperPortfolioCache.read(
          preferences,
          _principalA,
          now: _now,
        ))?.revision,
        2,
      );
      expect(
        (await PaperPortfolioCache.read(
          preferences,
          _principalB,
          now: _now,
        ))?.revision,
        3,
      );
    },
  );

  test(
    'reset floor removes stale cache and rejects delayed old writes',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await PaperPortfolioCache.write(
        preferences,
        _principalA,
        _snapshot(revision: 2),
        now: _now,
      );

      await PaperPortfolioCache.invalidate(
        preferences,
        _principalA,
        minimumRevision: 3,
      );
      expect(await PaperPortfolioCache.read(preferences, _principalA), isNull);

      await PaperPortfolioCache.write(
        preferences,
        _principalA,
        _snapshot(revision: 2),
        now: _now,
      );
      expect(await PaperPortfolioCache.read(preferences, _principalA), isNull);

      await PaperPortfolioCache.write(
        preferences,
        _principalA,
        _snapshot(revision: 3),
        now: _now,
      );
      expect(
        (await PaperPortfolioCache.read(
          preferences,
          _principalA,
          now: _now,
        ))?.revision,
        3,
      );
    },
  );

  test('pending reset blocks only cache at or before its base revision', () {
    final oldCycle = _snapshot(revision: 4);
    final afterBase = _snapshot(revision: 5);

    expect(
      PaperPortfolioCache.selectForRestore(
        cached: oldCycle,
        current: null,
        pendingResetBaseRevision: 4,
      ),
      isNull,
    );
    expect(
      PaperPortfolioCache.selectForRestore(
        cached: afterBase,
        current: null,
        pendingResetBaseRevision: 4,
      ),
      same(afterBase),
    );
    expect(
      PaperPortfolioCache.selectForRestore(
        cached: afterBase,
        current: _snapshot(revision: 4),
        pendingResetBaseRevision: null,
      ),
      same(afterBase),
    );
    expect(
      PaperPortfolioCache.selectForRestore(
        cached: afterBase,
        current: _snapshot(revision: 5),
        pendingResetBaseRevision: null,
      ),
      isNull,
    );
  });

  test('reset floor preserves a newer cached desk', () async {
    final preferences = await SharedPreferences.getInstance();
    await PaperPortfolioCache.write(
      preferences,
      _principalA,
      _snapshot(revision: 5),
      now: _now,
    );

    await PaperPortfolioCache.invalidate(
      preferences,
      _principalA,
      minimumRevision: 4,
    );

    expect(
      (await PaperPortfolioCache.read(
        preferences,
        _principalA,
        now: _now,
      ))?.revision,
      5,
    );
  });

  test('an older cache write cannot replace a newer revision', () async {
    final preferences = await SharedPreferences.getInstance();
    await PaperPortfolioCache.write(
      preferences,
      _principalA,
      _snapshot(revision: 5),
      now: _now,
    );

    await PaperPortfolioCache.write(
      preferences,
      _principalA,
      _snapshot(revision: 4),
      now: _now,
    );

    expect(
      (await PaperPortfolioCache.read(
        preferences,
        _principalA,
        now: _now,
      ))?.revision,
      5,
    );
  });

  test(
    'current snapshot can be recached after reset cancels queued work',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final oldWriteStarted = Completer<void>();
      final releaseOldWrite = Completer<void>();
      final oldWrite = PaperPortfolioCache.write(
        preferences,
        _principalA,
        _snapshot(revision: 2),
        now: _now,
        writerForTesting: (key, value) async {
          oldWriteStarted.complete();
          await releaseOldWrite.future;
          return preferences.setString(key, value);
        },
      );
      await oldWriteStarted.future;
      final queuedNewerWrite = PaperPortfolioCache.write(
        preferences,
        _principalA,
        _snapshot(revision: 5),
        now: _now,
      );
      final invalidate = PaperPortfolioCache.invalidate(
        preferences,
        _principalA,
        minimumRevision: 4,
      );

      releaseOldWrite.complete();
      await Future.wait([oldWrite, queuedNewerWrite, invalidate]);
      expect(await PaperPortfolioCache.read(preferences, _principalA), isNull);

      await PaperPortfolioCache.write(
        preferences,
        _principalA,
        _snapshot(revision: 5),
        now: _now,
      );
      expect(
        (await PaperPortfolioCache.read(
          preferences,
          _principalA,
          now: _now,
        ))?.revision,
        5,
      );
    },
  );

  test('corrupt or noncanonical cache data is discarded', () async {
    final preferences = await SharedPreferences.getInstance();
    final wrapper = _legacyWrapper();
    final portfolio = wrapper['portfolio'] as Map<String, Object?>;
    portfolio['revision'] = 9007199254740992;
    portfolio['startingCashPaper'] = '10000.0';
    await preferences.setString(_keyA, jsonEncode(wrapper));

    expect(
      await PaperPortfolioCache.read(preferences, _principalA, now: _now),
      isNull,
    );
    expect(preferences.getString(_keyA), isNull);
  });
}

PaperPortfolioSnapshot _snapshot({int revision = 2}) {
  final position = PaperPortfolioPosition(
    assetId: 'apple',
    variantMint: _mintA,
    symbol: 'AAPLx',
    quantity: '1.5',
    costBasisPaper: '500.5',
    averageCostPaper: '333.666667',
    realizedGainPaper: '-0.25',
    lockedGainPaper: '0',
    updatedAt: _now,
  );
  return PaperPortfolioSnapshot(
    revision: revision,
    startingCashPaper: '10000',
    cashPaper: '9499.5',
    positions: [position],
    recentOrders: [
      PaperPortfolioOrder(
        orderId: '44000000-0000-4000-8000-000000000001',
        assetId: 'apple',
        variantMint: _mintA,
        symbol: 'AAPLx',
        action: 'buy',
        pricePaper: '333.666667',
        quantity: '1.5',
        cashAfterPaper: '9499.5',
        committedAt: _now,
      ),
    ],
    valuation: PaperPortfolioValuation(
      sourceIncluded: true,
      status: PaperPortfolioValuationStatus.complete,
      portfolioRevision: revision,
      openPositionCount: 1,
      pricedPositionCount: 1,
      cashPaper: '9499.5',
      knownValuePaper: '10099.5',
      totalPaper: '10099.5',
      positions: [
        PaperPositionValuation.priced(
          key: position.key,
          pricePaper: '400',
          marketValuePaper: '600',
          unrealizedGainPaper: '99.5',
          observedAt: _acceptedAt.subtract(const Duration(seconds: 2)),
          acceptedAt: _acceptedAt,
          expiresAt: _expiresAt,
        ),
      ],
    ),
    openedAt: DateTime.utc(2026, 9, 20, 12),
    updatedAt: _now,
  );
}

PaperPortfolioSnapshot _maximumDerivedSnapshot() {
  final position = PaperPortfolioPosition(
    assetId: 'apple',
    variantMint: _mintA,
    symbol: 'AAPLx',
    quantity: '999999999.999999',
    costBasisPaper: '9999.999999',
    averageCostPaper: '0.00001',
    realizedGainPaper: '0',
    lockedGainPaper: '0',
    updatedAt: _now,
  );
  return PaperPortfolioSnapshot(
    revision: 2,
    startingCashPaper: '10000',
    cashPaper: '0.000001',
    positions: [position],
    recentOrders: [
      PaperPortfolioOrder(
        orderId: '44000000-0000-4000-8000-000000000001',
        assetId: 'apple',
        variantMint: _mintA,
        symbol: 'AAPLx',
        action: 'buy',
        pricePaper: '0.00001',
        quantity: '999999999.999999',
        cashAfterPaper: '0.000001',
        committedAt: _now,
      ),
    ],
    valuation: PaperPortfolioValuation(
      sourceIncluded: true,
      status: PaperPortfolioValuationStatus.complete,
      portfolioRevision: 2,
      openPositionCount: 1,
      pricedPositionCount: 1,
      cashPaper: '0.000001',
      knownValuePaper: '999999999999998000.000001',
      totalPaper: '999999999999998000.000001',
      positions: [
        PaperPositionValuation.priced(
          key: position.key,
          pricePaper: '999999999.999999',
          marketValuePaper: '999999999999998000',
          unrealizedGainPaper: '999999999999988000.000001',
          observedAt: _acceptedAt.subtract(const Duration(seconds: 2)),
          acceptedAt: _acceptedAt,
          expiresAt: _expiresAt,
        ),
      ],
    ),
    openedAt: DateTime.utc(2026, 9, 20, 12),
    updatedAt: _now,
  );
}

Map<String, Object?> _legacyWrapper() => {
  'schemaVersion': 1,
  'cachedAt': '2026-09-20T12:00:05.000Z',
  'portfolio': <String, Object?>{
    'revision': 2,
    'startingCashPaper': '10000',
    'cashPaper': '9499.5',
    'openedAt': '2026-09-20T12:00:00.000Z',
    'updatedAt': '2026-09-20T12:00:05.000Z',
    'positions': <Object?>[
      <String, Object?>{
        'assetId': 'apple',
        'variantMint': _mintA,
        'symbol': 'AAPLx',
        'quantity': '1.5',
        'costBasisPaper': '500.5',
        'averageCostPaper': '333.666667',
        'realizedGainPaper': '-0.25',
        'lockedGainPaper': '0',
        'updatedAt': '2026-09-20T12:00:05.000Z',
      },
    ],
    'recentOrders': <Object?>[
      <String, Object?>{
        'orderId': '44000000-0000-4000-8000-000000000001',
        'assetId': 'apple',
        'variantMint': _mintA,
        'symbol': 'AAPLx',
        'action': 'buy',
        'pricePaper': '333.666667',
        'quantity': '1.5',
        'cashAfterPaper': '9499.5',
        'committedAt': '2026-09-20T12:00:05.000Z',
      },
    ],
  },
};
