import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'paper_portfolio.dart';

typedef PaperPortfolioCacheWriter =
    Future<bool> Function(String key, String value);

/// A display-only, identity-scoped copy of the last server-confirmed paper
/// desk. Callers must never use this cache to authorize an order.
abstract final class PaperPortfolioCache {
  // Keep the original key so existing schema-one entries can be migrated.
  static const _prefix = 'trimmy.paper.portfolio-cache.v1.';
  static const _resetFloorPrefix = 'trimmy.paper.portfolio-reset-floor.v1.';
  static const _maximumSafeInteger = 9007199254740991;
  static final Map<String, Future<void>> _writeTails = {};
  static final Map<String, int> _epochs = {};

  static Future<PaperPortfolioSnapshot?> read(
    SharedPreferences preferences,
    String principalKey, {
    DateTime? now,
  }) async {
    final key = _key(principalKey);
    final raw = preferences.getString(key);
    if (raw == null) return null;
    try {
      final currentTime = (now ?? DateTime.now()).toUtc();
      final wrapper = _object(jsonDecode(raw), 3);
      final schemaVersion = wrapper['schemaVersion'];
      if (schemaVersion != 1 && schemaVersion != 2) _invalid();
      final cachedAt = _utc(wrapper['cachedAt']);
      if (cachedAt.isAfter(currentTime.add(const Duration(seconds: 5)))) {
        _invalid();
      }
      final snapshot = _snapshot(
        wrapper['portfolio'],
        schemaVersion: schemaVersion as int,
        cachedAt: cachedAt,
      );
      final resetFloor = preferences.getInt(_resetFloorKey(principalKey)) ?? 0;
      if (snapshot.revision < resetFloor) {
        await preferences.remove(key);
        return null;
      }
      return snapshot.withValuation(snapshot.valuation.currentAt(currentTime));
    } catch (_) {
      try {
        await preferences.remove(key);
      } catch (_) {
        // A corrupt display cache is ignored even when deletion fails.
      }
      return null;
    }
  }

  static Future<void> write(
    SharedPreferences preferences,
    String principalKey,
    PaperPortfolioSnapshot snapshot, {
    DateTime? now,
    PaperPortfolioCacheWriter? writerForTesting,
  }) async {
    final key = _key(principalKey);
    final writtenAt = (now ?? DateTime.now()).toUtc();
    late final String encoded;
    try {
      final currentSnapshot = snapshot.withValuation(
        snapshot.valuation.currentAt(writtenAt),
      );
      encoded = jsonEncode({
        'schemaVersion': 2,
        'cachedAt': _millisecondUtc(writtenAt),
        'portfolio': _encodeSnapshot(currentSnapshot),
      });
    } catch (_) {
      // The server remains authoritative. An invalid snapshot is not cached.
      return;
    }

    final previous = _writeTails[key] ?? Future<void>.value();
    final epoch = _epochs[key] ?? 0;
    final writer = writerForTesting ?? preferences.setString;
    final operation = previous.then((_) async {
      if ((_epochs[key] ?? 0) != epoch) return;
      int resetFloor;
      try {
        resetFloor = preferences.getInt(_resetFloorKey(principalKey)) ?? 0;
      } catch (_) {
        return;
      }
      if (snapshot.revision < resetFloor) return;
      final existing = await read(preferences, principalKey, now: writtenAt);
      if (existing != null && existing.revision > snapshot.revision) return;
      try {
        await writer(key, encoded);
      } catch (_) {
        // The server remains authoritative. Cache failure cannot fail a read.
      }
    });
    _writeTails[key] = operation;
    await operation;
    if (identical(_writeTails[key], operation)) {
      _writeTails.remove(key);
    }
  }

  /// Records the minimum valid revision after a confirmed reset. The epoch
  /// prevents a previously queued old-cycle write from restoring stale data.
  /// A cache already at or above the floor belongs to this or a newer cycle and
  /// is preserved.
  static Future<void> invalidate(
    SharedPreferences preferences,
    String principalKey, {
    required int minimumRevision,
  }) async {
    if (minimumRevision < 1 || minimumRevision > _maximumSafeInteger) {
      _invalid();
    }
    final key = _key(principalKey);
    final floorKey = _resetFloorKey(principalKey);
    final previousFloor = preferences.getInt(floorKey) ?? 0;
    if (minimumRevision > previousFloor) {
      final persisted = await preferences.setInt(floorKey, minimumRevision);
      if (!persisted) throw StateError('Paper reset floor was not persisted.');
    }
    _epochs[key] = (_epochs[key] ?? 0) + 1;
    final previous = _writeTails[key] ?? Future<void>.value();
    final operation = previous.then((_) async {
      await read(preferences, principalKey);
    });
    _writeTails[key] = operation;
    await operation;
    if (identical(_writeTails[key], operation)) {
      _writeTails.remove(key);
    }
  }

  /// Chooses whether a cached desk can be shown while repositories open.
  /// An unresolved reset can already have committed on the server. Cache at or
  /// before its base revision may belong to the old cycle, while a later
  /// server-confirmed revision remains safe to show.
  static PaperPortfolioSnapshot? selectForRestore({
    required PaperPortfolioSnapshot? cached,
    required PaperPortfolioSnapshot? current,
    required int? pendingResetBaseRevision,
  }) {
    if (cached == null) return null;
    if (pendingResetBaseRevision != null &&
        cached.revision <= pendingResetBaseRevision) {
      return null;
    }
    if (current != null && cached.revision <= current.revision) return null;
    return cached;
  }

  static String _key(String principalKey) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(principalKey)) {
      _invalid();
    }
    return '$_prefix$principalKey';
  }

  static String _resetFloorKey(String principalKey) {
    _key(principalKey);
    return '$_resetFloorPrefix$principalKey';
  }

  static Map<String, Object?> _encodeSnapshot(PaperPortfolioSnapshot value) => {
    'revision': value.revision,
    'startingCashPaper': value.startingCashPaper,
    'cashPaper': value.cashPaper,
    'openedAt': value.openedAt == null
        ? null
        : _millisecondUtc(value.openedAt!),
    'updatedAt': value.updatedAt == null
        ? null
        : _millisecondUtc(value.updatedAt!),
    'positions': [
      for (final position in value.positions)
        {
          'assetId': position.assetId,
          'variantMint': position.variantMint,
          'symbol': position.symbol,
          'quantity': position.quantity,
          'costBasisPaper': position.costBasisPaper,
          'averageCostPaper': position.averageCostPaper,
          'realizedGainPaper': position.realizedGainPaper,
          'lockedGainPaper': position.lockedGainPaper,
          'updatedAt': _millisecondUtc(position.updatedAt),
        },
    ],
    'recentOrders': [
      for (final order in value.recentOrders)
        {
          'orderId': order.orderId,
          'assetId': order.assetId,
          'variantMint': order.variantMint,
          'symbol': order.symbol,
          'action': order.action,
          'pricePaper': order.pricePaper,
          'quantity': order.quantity,
          'cashAfterPaper': order.cashAfterPaper,
          'committedAt': _millisecondUtc(order.committedAt),
        },
    ],
    'valuation': _encodeValuation(value.valuation),
  };

  static Map<String, Object?> _encodeValuation(PaperPortfolioValuation value) =>
      {
        'sourceIncluded': value.sourceIncluded,
        'status': _valuationStatusName(value.status),
        'portfolioRevision': value.portfolioRevision,
        'openPositionCount': value.openPositionCount,
        'pricedPositionCount': value.pricedPositionCount,
        'cashPaper': value.cashPaper,
        'knownValuePaper': value.knownValuePaper,
        'totalPaper': value.totalPaper,
        'positions': [
          for (final position in value.positions)
            {
              'assetId': position.key.assetId,
              'variantMint': position.key.variantMint,
              'status': position.status == PaperPositionValuationStatus.priced
                  ? 'priced'
                  : 'unavailable',
              'pricePaper': position.pricePaper,
              'marketValuePaper': position.marketValuePaper,
              'unrealizedGainPaper': position.unrealizedGainPaper,
              'observedAt': position.observedAt == null
                  ? null
                  : _millisecondUtc(position.observedAt!),
              'acceptedAt': position.acceptedAt == null
                  ? null
                  : _millisecondUtc(position.acceptedAt!),
              'expiresAt': position.expiresAt == null
                  ? null
                  : _millisecondUtc(position.expiresAt!),
            },
        ],
      };

  static PaperPortfolioSnapshot _snapshot(
    Object? input, {
    required int schemaVersion,
    required DateTime cachedAt,
  }) {
    final value = _object(input, schemaVersion == 1 ? 7 : 8);
    final revision = value['revision'];
    if (revision is! int || revision < 0 || revision > _maximumSafeInteger) {
      _invalid();
    }
    final positions = _list(
      value['positions'],
      1000,
    ).map(_position).toList(growable: false);
    if (positions
            .map((item) => '${item.assetId}\u0000${item.variantMint}')
            .toSet()
            .length !=
        positions.length) {
      _invalid();
    }
    final orders = _list(
      value['recentOrders'],
      100,
    ).map(_order).toList(growable: false);
    for (var index = 1; index < orders.length; index++) {
      if (orders[index].committedAt.isAfter(orders[index - 1].committedAt)) {
        _invalid();
      }
    }
    final openedAt = _nullableUtc(value['openedAt']);
    final updatedAt = _nullableUtc(value['updatedAt']);
    if ((openedAt == null) != (updatedAt == null) ||
        openedAt != null && updatedAt!.isBefore(openedAt)) {
      _invalid();
    }
    final startingCashPaper = _amount(value['startingCashPaper']);
    final cashPaper = _amount(value['cashPaper']);
    final openPositions = positions
        .where((position) => position.quantity != '0')
        .toList(growable: false);
    final valuation = schemaVersion == 1
        ? PaperPortfolioValuation.notIncluded(
            portfolioRevision: revision,
            cashPaper: cashPaper,
            openPositions: openPositions,
          )
        : _valuation(
            value['valuation'],
            revision: revision,
            cashPaper: cashPaper,
            openPositions: openPositions,
            cachedAt: cachedAt,
          );
    return PaperPortfolioSnapshot(
      revision: revision,
      startingCashPaper: startingCashPaper,
      cashPaper: cashPaper,
      positions: positions,
      recentOrders: orders,
      valuation: valuation,
      openedAt: openedAt,
      updatedAt: updatedAt,
    );
  }

  static PaperPortfolioValuation _valuation(
    Object? input, {
    required int revision,
    required String cashPaper,
    required List<PaperPortfolioPosition> openPositions,
    required DateTime cachedAt,
  }) {
    final value = _object(input, 9);
    final sourceIncluded = value['sourceIncluded'];
    final portfolioRevision = value['portfolioRevision'];
    final openPositionCount = value['openPositionCount'];
    final pricedPositionCount = value['pricedPositionCount'];
    if (sourceIncluded is! bool ||
        portfolioRevision != revision ||
        openPositionCount is! int ||
        openPositionCount != openPositions.length ||
        pricedPositionCount is! int ||
        pricedPositionCount < 0 ||
        pricedPositionCount > openPositionCount ||
        _amount(value['cashPaper']) != cashPaper) {
      _invalid();
    }
    final rows = _list(value['positions'], 1000);
    if (rows.length != openPositions.length) _invalid();

    final parsedRows = <PaperPositionValuation>[];
    var parsedPriced = 0;
    var knownMicros = _toMicros(cashPaper);
    for (var index = 0; index < rows.length; index++) {
      final row = _object(rows[index], 9);
      final expected = openPositions[index];
      final key = PaperPositionKey(
        assetId: _assetId(row['assetId']),
        variantMint: _mint(row['variantMint']),
      );
      if (key != expected.key) _invalid();

      switch (row['status']) {
        case 'priced':
          if (!sourceIncluded) _invalid();
          final pricePaper = _amount(row['pricePaper'], positive: true);
          final marketValuePaper = _derivedAmount(row['marketValuePaper']);
          final unrealizedGainPaper = _derivedAmount(
            row['unrealizedGainPaper'],
            signed: true,
          );
          final observedAt = _utc(row['observedAt']);
          final acceptedAt = _utc(row['acceptedAt']);
          final expiresAt = _utc(row['expiresAt']);
          if (acceptedAt.isAfter(cachedAt.add(const Duration(seconds: 5))) ||
              observedAt.isBefore(
                acceptedAt.subtract(const Duration(seconds: 10)),
              ) ||
              observedAt.isAfter(acceptedAt.add(const Duration(seconds: 5))) ||
              !expiresAt.isAfter(acceptedAt) ||
              expiresAt.isAfter(acceptedAt.add(const Duration(seconds: 60)))) {
            _invalid();
          }
          final expectedMarket =
              _toMicros(expected.quantity) *
              _toMicros(pricePaper) ~/
              BigInt.from(1000000);
          final marketMicros = _toMicros(marketValuePaper);
          if (marketMicros != expectedMarket ||
              _toMicros(unrealizedGainPaper) !=
                  marketMicros - _toMicros(expected.costBasisPaper)) {
            _invalid();
          }
          parsedRows.add(
            PaperPositionValuation.priced(
              key: key,
              pricePaper: pricePaper,
              marketValuePaper: marketValuePaper,
              unrealizedGainPaper: unrealizedGainPaper,
              observedAt: observedAt,
              acceptedAt: acceptedAt,
              expiresAt: expiresAt,
            ),
          );
          parsedPriced++;
          knownMicros += marketMicros;
          continue;
        case 'unavailable':
          for (final field in const [
            'pricePaper',
            'marketValuePaper',
            'unrealizedGainPaper',
            'observedAt',
            'acceptedAt',
            'expiresAt',
          ]) {
            if (row[field] != null) _invalid();
          }
          parsedRows.add(PaperPositionValuation.unavailable(key: key));
          continue;
        default:
          _invalid();
      }
    }
    if (parsedPriced != pricedPositionCount ||
        _derivedAmount(value['knownValuePaper']) != _fromMicros(knownMicros)) {
      _invalid();
    }
    final status = switch (value['status']) {
      'complete' => PaperPortfolioValuationStatus.complete,
      'partial' => PaperPortfolioValuationStatus.partial,
      'unavailable' => PaperPortfolioValuationStatus.unavailable,
      _ => _invalid(),
    };
    final expectedStatus =
        openPositionCount == 0 || pricedPositionCount == openPositionCount
        ? PaperPortfolioValuationStatus.complete
        : pricedPositionCount == 0
        ? PaperPortfolioValuationStatus.unavailable
        : PaperPortfolioValuationStatus.partial;
    if (status != expectedStatus) _invalid();

    final totalValue = value['totalPaper'];
    final totalPaper = totalValue == null ? null : _derivedAmount(totalValue);
    final knownPaper = _fromMicros(knownMicros);
    if (status == PaperPortfolioValuationStatus.complete
        ? totalPaper != knownPaper
        : totalPaper != null) {
      _invalid();
    }
    return PaperPortfolioValuation(
      sourceIncluded: sourceIncluded,
      status: status,
      portfolioRevision: revision,
      openPositionCount: openPositionCount,
      pricedPositionCount: pricedPositionCount,
      cashPaper: cashPaper,
      knownValuePaper: knownPaper,
      totalPaper: totalPaper,
      positions: parsedRows,
    );
  }

  static PaperPortfolioPosition _position(Object? input) {
    final value = _object(input, 9);
    return PaperPortfolioPosition(
      assetId: _assetId(value['assetId']),
      variantMint: _mint(value['variantMint']),
      symbol: _text(value['symbol'], 30),
      quantity: _amount(value['quantity']),
      costBasisPaper: _amount(value['costBasisPaper']),
      averageCostPaper: _amount(value['averageCostPaper']),
      realizedGainPaper: _amount(value['realizedGainPaper'], signed: true),
      lockedGainPaper: _amount(value['lockedGainPaper']),
      updatedAt: _utc(value['updatedAt']),
    );
  }

  static PaperPortfolioOrder _order(Object? input) {
    final value = _object(input, 9);
    final action = _text(value['action'], 8);
    if (action != 'buy' && action != 'sell' && action != 'trim') _invalid();
    return PaperPortfolioOrder(
      orderId: _uuid(value['orderId']),
      assetId: _assetId(value['assetId']),
      variantMint: _mint(value['variantMint']),
      symbol: _text(value['symbol'], 30),
      action: action,
      pricePaper: _amount(value['pricePaper'], positive: true),
      quantity: _amount(value['quantity'], positive: true),
      cashAfterPaper: _amount(value['cashAfterPaper']),
      committedAt: _utc(value['committedAt']),
    );
  }

  static Map<String, dynamic> _object(Object? value, int length) {
    if (value is! Map<String, dynamic> || value.length != length) _invalid();
    return value;
  }

  static List<Object?> _list(Object? value, int maximum) {
    if (value is! List<Object?> || value.length > maximum) _invalid();
    return value;
  }

  static String _text(Object? value, int maximum) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maximum ||
        value.trim() != value ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      _invalid();
    }
    return value;
  }

  static String _assetId(Object? value) {
    final text = _text(value, 100);
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(text)) _invalid();
    return text;
  }

  static String _mint(Object? value) {
    final text = _text(value, 44);
    if (!RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(text)) _invalid();
    return text;
  }

  static String _uuid(Object? value) {
    final text = _text(value, 36).toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(text)) {
      _invalid();
    }
    return text;
  }

  static String _amount(
    Object? value, {
    bool signed = false,
    bool positive = false,
  }) {
    if (value is! String ||
        !RegExp(
          r'^(?:0|-?[1-9][0-9]{0,8}|-?(?:0|[1-9][0-9]{0,8})\.[0-9]{1,6})$',
        ).hasMatch(value)) {
      _invalid();
    }
    final micros = _toMicros(value);
    if (micros.isNegative && !signed ||
        micros.abs() > BigInt.from(999999999999999) ||
        _fromMicros(micros) != value ||
        positive && micros <= BigInt.zero) {
      _invalid();
    }
    return value;
  }

  static String _derivedAmount(Object? value, {bool signed = false}) {
    if (value is! String ||
        !RegExp(
          r'^(?:0|-?[1-9][0-9]{0,23}|-?(?:0|[1-9][0-9]{0,23})\.[0-9]{1,6})$',
        ).hasMatch(value)) {
      _invalid();
    }
    final micros = _toMicros(value);
    if (micros.isNegative && !signed ||
        micros.abs() > BigInt.parse('999999999999999999999999999999') ||
        _fromMicros(micros) != value) {
      _invalid();
    }
    return value;
  }

  static BigInt _toMicros(String value) {
    final negative = value.startsWith('-');
    final absolute = negative ? value.substring(1) : value;
    final parts = absolute.split('.');
    final micros =
        BigInt.parse(parts[0]) * BigInt.from(1000000) +
        BigInt.parse(
          (parts.length == 1 ? '' : parts[1]).padRight(6, '0').padLeft(1, '0'),
        );
    return negative ? -micros : micros;
  }

  static String _fromMicros(BigInt value) {
    final negative = value.isNegative;
    final absolute = value.abs();
    final whole = absolute ~/ BigInt.from(1000000);
    final fraction = (absolute % BigInt.from(1000000))
        .toString()
        .padLeft(6, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '${negative ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
  }

  static DateTime _utc(Object? value) {
    final text = _text(value, 24);
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
    ).hasMatch(text)) {
      _invalid();
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != text) {
      _invalid();
    }
    return parsed;
  }

  static DateTime? _nullableUtc(Object? value) =>
      value == null ? null : _utc(value);

  static String _millisecondUtc(DateTime value) {
    final utc = value.toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      utc.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
  }

  static String _valuationStatusName(PaperPortfolioValuationStatus status) =>
      switch (status) {
        PaperPortfolioValuationStatus.complete => 'complete',
        PaperPortfolioValuationStatus.partial => 'partial',
        PaperPortfolioValuationStatus.unavailable => 'unavailable',
      };

  static Never _invalid() => throw const FormatException('CACHE_INVALID');
}
