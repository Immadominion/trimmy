import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/markets/discovery.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/market/live_order_flow.dart';
import 'package:trimmy/product/market/live_trading.dart';
import 'package:trimmy/product/market/market_models.dart';
import '../../support/account_data_fixtures.dart' as fixtures;

const _appleMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const _orderId = '44444444-4444-4444-8444-444444444444';
final _origin = Uri.parse('https://trimmy.example');

Map<String, Object?> _caps({bool enabled = true}) => {
  'enabled': enabled,
  'network': 'solana:mainnet-beta',
  'minimumSolBalanceLamports': '5000',
  'assets': [
    for (final asset in [
      ('apple', 'Apple', 'AAPLx', _appleMint),
      ('nvidia', 'NVIDIA', 'NVDAx', fixtures.nvidiaMint),
    ])
      {
        'assetId': asset.$1,
        'name': asset.$2,
        'symbol': asset.$3,
        'mint': asset.$4,
        'decimals': 8,
        'maxBuyInputRaw': '100000000',
        'maxSellInputRaw': '100000000',
      },
  ],
};
MarketCompany _company(String assetId, {bool unsupportedPrimary = false}) {
  final mint = assetId == 'apple' ? _appleMint : fixtures.nvidiaMint;
  Map<String, Object?> variant(String value) => {
    'variantId': '$assetId-$value',
    'mint': value,
    'chain': 'solana',
    'kind': 'tokenized-equity',
    'issuer': 'Backed',
    'label': 'stock',
    'name': 'Stock',
    'symbol': 'stock',
    'providerRedemptionTier': null,
    'advisory': null,
    'market': null,
  };
  return MarketCompany.fromDiscovery(
    StockDiscoveryAsset.fromJson({
      'assetId': assetId,
      'name': assetId == 'apple' ? 'Apple' : 'NVIDIA',
      'symbol': 'STOCK',
      'category': 'equity',
      'providerPrimaryVariantMint': unsupportedPrimary ? fixtures.wallet : mint,
      'variants': [
        if (unsupportedPrimary) variant(fixtures.wallet),
        variant(mint),
      ],
      'advisories': [],
    }),
  );
}

Map<String, Object?> _order(
  String status, {
  String side = 'buy',
  String raw = '5000000',
  String mint = fixtures.nvidiaMint,
  int? confirmedSlot,
}) => {
  'id': _orderId,
  'status': status,
  'wallet': fixtures.wallet,
  'signature': status == 'confirmed' ? 'test-signature' : null,
  'confirmedSlot': ?confirmedSlot,
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 2))
      .toIso8601String(),
  'reviewDigest': 'a' * 64,
  'transaction': 'test-unsigned',
  'terms': {
    'side': side,
    'inputMint': side == 'buy' ? liveUsdcMint : mint,
    'outputMint': side == 'buy' ? mint : liveUsdcMint,
    'inputAmountRaw': raw,
    'quotedOutputAmountRaw': side == 'buy' ? '1234567' : '5000000',
    'minimumOutputAmountRaw': side == 'buy' ? '1230000' : '4950000',
    'totalLamportsUpperBound': '5000',
    'platformFeeBps': 0,
  },
};
http.Response _reply(Object? value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

class _Reader implements AccountPortfolioReader {
  Map<String, Object?> envelope = fixtures.holdingsEnvelopeV2();
  bool unavailable = false;
  _Reader() {
    final usdc =
        ((envelope['holdings'] as Map)['balances'] as Map)['usdc'] as Map;
    usdc['amountRaw'] = '100000000';
    usdc['availableToTradeRaw'] = '80000000';
    usdc['hasFrozenAccounts'] = false;
  }
  @override
  String get accountId => fixtures.account;
  @override
  Future<AccountContextSnapshot> readContext() async =>
      AccountContextSnapshot.fromEnvelope(
        fixtures.contextEnvelope(),
        expectedUserId: fixtures.account,
      );
  @override
  Future<AccountHoldingsSnapshot> readHoldings({
    int? minimumObservedSlot,
  }) async {
    if (unavailable) {
      throw const AccountDataException(AccountDataFailure.unavailable);
    }
    return AccountHoldingsSnapshot.fromEnvelope(
      envelope,
      expectedUserId: fixtures.account,
    );
  }

  @override
  void cancelPending() {}
  @override
  void close() {}
}

class _Account extends ChangeNotifier implements AccountController {
  _Account(this.portfolio);
  final AccountPortfolioRepository portfolio;
  int refreshes = 0, signatures = 0;
  final List<int?> confirmedSlots = [];
  @override
  String? accountId = fixtures.account;
  @override
  int navigationEpoch = 0;
  @override
  AccountPhase get phase => AccountPhase.active;
  @override
  AccountPortfolioState get portfolioState => portfolio.state;
  @override
  Future<PracticeAccessToken> freshAccessToken() async =>
      PracticeAccessToken(accountId: accountId!, token: 'test-token');
  @override
  Future<void> refreshPortfolio() async {
    refreshes++;
    await portfolio.refresh();
    notifyListeners();
  }

  @override
  Future<void> refreshPortfolioAfterTrade({int? confirmedSlot}) async {
    confirmedSlots.add(confirmedSlot);
    refreshes++;
    await portfolio.refreshAfterMutation(minimumObservedSlot: confirmedSlot);
    notifyListeners();
  }

  @override
  Future<String> signReviewedStockTransaction({
    required String wallet,
    required String transaction,
    required DateTime expiresAt,
  }) async {
    signatures++;
    return 'fake-signed-transaction';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Reader reader;
  late AccountPortfolioRepository portfolio;
  late _Account account;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reader = _Reader();
    portfolio = AccountPortfolioRepository(
      reader: reader,
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    account = _Account(portfolio);
  });
  Future<void> pump(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> mount(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    MarketCompany? company,
    bool sell = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: LiveOrderFlow(
          account: account,
          origin: _origin,
          company: company ?? _company('nvidia'),
          initialSell: sell,
          httpClient: MockClient(handler),
          onBack: () {},
          onAddMoney: () async {},
        ),
      ),
    );
    await pump(tester);
  }

  Future<void> clean(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    portfolio.dispose();
    account.dispose();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await pump(tester);
  }

  Future<http.Response> defaults(http.Request request) async =>
      request.url.path.endsWith('capabilities')
      ? _reply(_caps())
      : _reply({'order': null});

  testWidgets(
    'buys capability matched variant even when discovery primary is different',
    (tester) async {
      Map<String, dynamic>? preview;
      await mount(tester, (request) async {
        if (request.url.path.endsWith('preview')) {
          preview = jsonDecode(request.body) as Map<String, dynamic>;
          return _reply({
            'order': _order('reviewed', raw: preview!['amountRaw'] as String),
          });
        }
        return defaults(request);
      }, company: _company('nvidia', unsupportedPrimary: true));
      expect(find.text('Buy NVDAx'), findsOneWidget);
      expect(find.text('80 USDC available'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('live-order-amount')),
        '2.123456',
      );
      await tap(tester, 'live-order-review');
      expect(preview, {
        'assetId': 'nvidia',
        'variantMint': fixtures.nvidiaMint,
        'side': 'buy',
        'amountRaw': '2123456',
      });
      expect(find.text('0.01234567 NVDAx raw units'), findsOneWidget);
      expect(find.text('AAPLx'), findsNothing);
      expect(account.signatures, 0);
      await clean(tester);
    },
  );

  testWidgets(
    'sell percentages and Max use only spendable ATA quantity and exact precision',
    (tester) async {
      Map<String, dynamic>? preview;
      await mount(tester, (request) async {
        if (request.url.path.endsWith('preview')) {
          preview = jsonDecode(request.body) as Map<String, dynamic>;
          return _reply({
            'order': _order(
              'reviewed',
              side: 'sell',
              raw: preview!['amountRaw'] as String,
            ),
          });
        }
        return defaults(request);
      }, sell: true);
      expect(find.text('1 NVDAx raw units available'), findsOneWidget);
      expect(find.text('Raw token units'), findsOneWidget);
      expect(
        find.textContaining('Orders use raw token units.'),
        findsOneWidget,
      );
      await tap(tester, 'live-order-percent-25');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('live-order-amount')))
            .controller!
            .text,
        '0.25',
      );
      await tap(tester, 'live-order-max');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('live-order-amount')))
            .controller!
            .text,
        '1',
      );
      await tap(tester, 'live-order-review');
      expect(preview!['amountRaw'], '100000000');
      expect(preview!['side'], 'sell');
      await clean(tester);
    },
  );

  testWidgets(
    'overprecision and more than spendable balance never request a quote',
    (tester) async {
      var quotes = 0;
      await mount(tester, (request) async {
        if (request.url.path.endsWith('preview')) quotes++;
        return defaults(request);
      });
      await tester.enterText(
        find.byKey(const ValueKey('live-order-amount')),
        '1.0000001',
      );
      await tap(tester, 'live-order-review');
      expect(find.text('Enter a valid USDC amount.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('live-order-amount')),
        '81',
      );
      await tap(tester, 'live-order-review');
      expect(
        find.text('Add USDC to your Solana wallet first.'),
        findsOneWidget,
      );
      expect(quotes, 0);
      await clean(tester);
    },
  );

  testWidgets('newly bought token fills sell Max when holdings arrive late', (
    tester,
  ) async {
    final original = reader.envelope;
    reader.envelope = fixtures.holdingsEnvelopeV2();
    ((reader.envelope['holdings'] as Map)['balances'] as Map)['tokens'] = [];
    await mount(tester, defaults, sell: true);
    final field = find.byKey(const ValueKey('live-order-amount'));
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    reader.envelope = original;
    await account.refreshPortfolio();
    await pump(tester);
    expect(tester.widget<TextField>(field).controller!.text, '1');
    expect(find.text('1 NVDAx raw units available'), findsOneWidget);
    await clean(tester);
  });

  testWidgets('late holdings do not overwrite a sell amount the user entered', (
    tester,
  ) async {
    final original = reader.envelope;
    reader.envelope = fixtures.holdingsEnvelopeV2();
    ((reader.envelope['holdings'] as Map)['balances'] as Map)['tokens'] = [];
    await mount(tester, defaults, sell: true);
    final field = find.byKey(const ValueKey('live-order-amount'));
    await tester.enterText(field, '0.25');
    reader.envelope = original;
    await account.refreshPortfolio();
    await pump(tester);
    expect(tester.widget<TextField>(field).controller!.text, '0.25');
    await clean(tester);
  });

  testWidgets(
    'retained zero holdings cannot reject a fresh server sell quote',
    (tester) async {
      ((reader.envelope['holdings'] as Map)['balances'] as Map)['tokens'] = [];
      var quotes = 0;
      await mount(tester, (request) async {
        if (request.url.path.endsWith('preview')) {
          quotes++;
          return _reply({
            'order': _order('reviewed', side: 'sell', raw: '25000000'),
          });
        }
        return defaults(request);
      }, sell: true);
      reader.unavailable = true;
      await tester.enterText(
        find.byKey(const ValueKey('live-order-amount')),
        '0.25',
      );
      await tap(tester, 'live-order-review');
      expect(account.portfolioState.portfolioIsFresh, isFalse);
      expect(quotes, 1);
      expect(find.byKey(const ValueKey('live-order-confirm')), findsOneWidget);
      expect(
        find.text('You don’t have enough of this token to sell.'),
        findsNothing,
      );
      await clean(tester);
    },
  );

  testWidgets(
    'capability outage retries without telling a funded user to add money',
    (tester) async {
      var reads = 0;
      await mount(tester, (request) async {
        if (request.url.path.endsWith('capabilities') && reads++ == 0) {
          return _reply({}, status: 503);
        }
        return defaults(request);
      });
      expect(find.text('Trading couldn’t connect'), findsOneWidget);
      expect(find.text('Add money'), findsNothing);
      await tap(tester, 'live-order-unavailable-action');
      expect(find.text('Buy NVDAx'), findsOneWidget);
      await clean(tester);
    },
  );

  testWidgets(
    'unsupported company is a stock selection state, not a funding CTA',
    (tester) async {
      await mount(tester, defaults, company: _company('unsupported'));
      expect(find.text('This token isn’t tradable here yet'), findsOneWidget);
      expect(find.text('Back to stocks'), findsOneWidget);
      expect(find.text('Add money'), findsNothing);
      await clean(tester);
    },
  );

  testWidgets(
    'saved pending order restores and confirms while new execution is paused',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'trimmy.pending-live-order.${fixtures.account}': _orderId,
      });
      var checks = 0;
      await mount(tester, (request) async {
        if (request.url.path.endsWith('capabilities')) {
          return _reply(_caps(enabled: false));
        }
        return _reply({
          'order': _order(
            checks++ == 0 ? 'pending' : 'confirmed',
            confirmedSlot: checks > 1 ? 447040359 : null,
          ),
        });
      });
      expect(find.text('Confirming your trade'), findsOneWidget);
      expect(find.text('Trading is temporarily paused'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await pump(tester);
      expect(find.text('Trade confirmed'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'trimmy.pending-live-order.${fixtures.account}',
        ),
        isNull,
      );
      expect(account.refreshes, greaterThanOrEqualTo(2));
      expect(account.confirmedSlots, [447040359]);
      expect(account.signatures, 0);
      await clean(tester);
    },
  );

  testWidgets(
    'restored confirmed order refreshes holdings and clears the pending marker',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'trimmy.pending-live-order.${fixtures.account}': _orderId,
      });
      await mount(tester, (request) async {
        if (request.url.path.endsWith('capabilities')) return _reply(_caps());
        return _reply({'order': _order('confirmed')});
      });
      expect(find.text('Trade confirmed'), findsOneWidget);
      expect(account.refreshes, greaterThanOrEqualTo(2));
      expect(account.confirmedSlots, [null]);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'trimmy.pending-live-order.${fixtures.account}',
        ),
        isNull,
      );
      await clean(tester);
    },
  );

  testWidgets('mismatched quote cannot enter review or enable signing', (
    tester,
  ) async {
    await mount(tester, (request) async {
      if (request.url.path.endsWith('preview')) {
        return _reply({'order': _order('reviewed', mint: _appleMint)});
      }
      return defaults(request);
    });
    await tap(tester, 'live-order-review');
    expect(find.text('This order needs a fresh quote.'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-order-confirm')), findsNothing);
    expect(account.signatures, 0);
    await clean(tester);
  });

  test('request account change blocks authenticated dispatch', () async {
    var requests = 0;
    final transport = MockClient((request) async {
      requests++;
      return _reply({'order': null});
    });
    final client = LiveOrderClient(_origin, account, client: transport);
    account.navigationEpoch++;
    await expectLater(
      client.request('order'),
      throwsA(
        isA<LiveOrderFailure>().having(
          (e) => e.code,
          'code',
          'ACCOUNT_REQUIRED',
        ),
      ),
    );
    expect(requests, 0);
    client.close();
    portfolio.dispose();
    account.dispose();
  });

  testWidgets(
    'changing accounts removes an old account review before signing',
    (tester) async {
      await mount(tester, (request) async {
        if (request.url.path.endsWith('preview')) {
          return _reply({'order': _order('reviewed')});
        }
        return defaults(request);
      });
      await tap(tester, 'live-order-review');
      expect(find.byKey(const ValueKey('live-order-confirm')), findsOneWidget);
      account.navigationEpoch++;
      account.notifyListeners();
      await pump(tester);
      expect(find.text('Your account changed'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-order-confirm')), findsNothing);
      expect(account.signatures, 0);
      await clean(tester);
    },
  );

  test(
    'malformed confirmed slots cannot cross the order API boundary',
    () async {
      for (final slot in [0, -1, 1.5, '447040359', 9007199254740992]) {
        final transport = MockClient(
          (request) async => _reply({
            'order': {..._order('confirmed'), 'confirmedSlot': slot},
          }),
        );
        final client = LiveOrderClient(_origin, account, client: transport);
        await expectLater(
          client.request('order'),
          throwsA(isA<LiveOrderFailure>()),
        );
        client.close();
      }
      portfolio.dispose();
      account.dispose();
    },
  );

  test('a trade-cap rejection has actionable copy', () {
    expect(
      const LiveOrderFailure('TRADE_LIMIT').message,
      'This order is above the current trade limit.',
    );
    portfolio.dispose();
    account.dispose();
  });

  test(
    'malformed review amounts never reach the presentation or signer',
    () async {
      final order = _order('reviewed');
      (order['terms'] as Map)['quotedOutputAmountRaw'] = 123;
      final transport = MockClient((request) async => _reply({'order': order}));
      final client = LiveOrderClient(_origin, account, client: transport);
      await expectLater(
        client.request('order'),
        throwsA(isA<LiveOrderFailure>()),
      );
      expect(account.signatures, 0);
      client.close();
      portfolio.dispose();
      account.dispose();
    },
  );

  testWidgets(
    'lost execute reply reconciles one signed order without another dispatch',
    (tester) async {
      var dispatched = 0;
      await mount(tester, (request) async {
        if (request.url.path.endsWith('preview')) {
          return _reply({'order': _order('reviewed')});
        }
        if (request.url.path.endsWith('execute')) {
          dispatched++;
          throw http.ClientException('Connection closed');
        }
        if (request.url.path.endsWith('order/$_orderId')) {
          return _reply({'order': _order('confirmed')});
        }
        return defaults(request);
      });
      await tap(tester, 'live-order-review');
      await tap(tester, 'live-order-terms');
      await tap(tester, 'live-order-confirm');
      expect(find.text('Confirming your trade'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'trimmy.pending-live-order.${fixtures.account}',
        ),
        _orderId,
      );
      expect(dispatched, 1);
      expect(account.signatures, 1);
      await tester.pump(const Duration(seconds: 3));
      await pump(tester);
      expect(find.text('Trade confirmed'), findsOneWidget);
      expect(dispatched, 1);
      expect(account.signatures, 1);
      await clean(tester);
    },
  );

  testWidgets('expired quote exits review before any signing', (tester) async {
    await mount(tester, (request) async {
      if (request.url.path.endsWith('preview')) {
        return _reply({
          'order': {
            ..._order('reviewed'),
            'expiresAt': DateTime.now()
                .toUtc()
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
          },
        });
      }
      return defaults(request);
    });
    await tap(tester, 'live-order-review');
    expect(find.text('Quote expired'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-order-confirm')), findsNothing);
    expect(account.signatures, 0);
    await clean(tester);
  });
}
