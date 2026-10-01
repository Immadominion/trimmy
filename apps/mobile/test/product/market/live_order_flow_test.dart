import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/l10n/l10n.dart';
import 'package:trimmy/markets/discovery.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/product/design/product_components.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/market/live_order_flow.dart';
import 'package:trimmy/product/market/live_trading.dart';
import 'package:trimmy/product/market/market_models.dart';
import '../../support/account_data_fixtures.dart' as fixtures;
import '../../support/l10n_harness.dart';
import 'live_trading_test_support.dart';

const _appleMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const _orderId = '44444444-4444-4444-8444-444444444444';
final _origin = Uri.parse('https://trimmy.example');
final _termsKey = 'trimmy.issuer-terms.v1.${fixtures.account}';
String _accepted(String issuerId) => jsonEncode([issuerId, termsVersion]);

Map<String, Object?> _caps({
  bool enabled = true,
  String ondoSellLimit = '1000000000',
}) => capabilitiesV2Json(
  enabled: enabled,
  assets: [
    assetJson(
      assetId: 'apple',
      mint: _appleMint,
      symbol: 'AAPLx',
      name: 'Apple',
    ),
    assetJson(
      assetId: 'nvidia',
      mint: fixtures.nvidiaMint,
      symbol: 'NVDAx',
      name: 'NVIDIA',
    ),
    assetJson(
      assetId: 'nvidia',
      mint: ondoNvidiaMint,
      symbol: 'NVDAon',
      name: 'NVIDIA Ondo',
      issuerId: 'ondo',
      decimals: 9,
      maxSellInputRaw: ondoSellLimit,
    ),
    assetJson(
      assetId: 'nvidia',
      mint: backpackNvidiaMint,
      symbol: 'NVDAbp',
      name: 'NVIDIA Backpack',
      issuerId: 'backpack',
      decimals: 6,
    ),
    assetJson(
      assetId: 'spacex',
      mint: preStocksMint,
      symbol: 'SPACEX',
      name: 'SpaceX',
      issuerId: 'prestocks',
      decimals: 9,
      transferFeeBps: 300,
    ),
  ],
);

/// The shape served by servers from before issuer terms.
Map<String, Object?> _legacyCaps() => {
  'enabled': true,
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

/// NVIDIA as discovery lists it with all three issuers' tokens.
MarketCompany _nvidia() => discoveryCompany('nvidia', [
  (fixtures.nvidiaMint, 900000),
  (ondoNvidiaMint, 400000),
  (backpackNvidiaMint, 1000),
]);

Map<String, Object?> _order(
  String status, {
  String side = 'buy',
  String raw = '5000000',
  String mint = fixtures.nvidiaMint,
  int? confirmedSlot,
  String? quotedOutput,
  String? minimumOutput,
  String? multiplier,
  String? delivered,
  String? route,
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
    'quotedOutputAmountRaw':
        quotedOutput ?? (side == 'buy' ? '1234567' : '5000000'),
    'minimumOutputAmountRaw':
        minimumOutput ?? (side == 'buy' ? '1230000' : '4950000'),
    'totalLamportsUpperBound': '5000',
    'platformFeeBps': 0,
    'stockUiMultiplier': ?multiplier,
    'simulatedOutputReceivedRaw': ?delivered,
    'route': ?route,
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

  /// Adds a 9 decimal Ondo holding: 1 token that shows as 1.5 shares.
  void holdOndo({String display = '1.5'}) {
    final balances = (envelope['holdings'] as Map)['balances'] as Map;
    (balances['tokens'] as List).add({
      'assetId': 'nvidia',
      'name': 'NVIDIA Ondo',
      ...fixtures.tokenBalance(
        symbol: 'NVDAon',
        mint: ondoNvidiaMint,
        decimals: 9,
        amountRaw: '1000000000',
        slot: 447040361,
      ),
      'displayAmount': display,
      'availableToTradeRaw': '1000000000',
      'displayResolution': 'rpc_ui_amount',
      'displayUnits': 'token_units',
    });
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
    // Most orders here are xStocks; that issuer's current terms are ticked.
    SharedPreferences.setMockInitialValues({
      _termsKey: [_accepted('xstocks')],
    });
    LiveIssuerTerms.resetSession();
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
    String? variantMint,
    bool sell = false,
    Locale? locale,
  }) async {
    final flow = LiveOrderFlow(
      account: account,
      origin: _origin,
      company: company ?? _company('nvidia'),
      variantMint: variantMint,
      initialSell: sell,
      httpClient: MockClient(handler),
      onBack: () {},
      onAddMoney: () async {},
    );
    await tester.pumpWidget(
      locale == null
          ? MaterialApp(theme: productTheme(), home: flow)
          : localizedTestApp(locale: locale, home: flow),
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

  String field(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('live-order-amount')))
      .controller!
      .text;

  bool reviewEnabled(WidgetTester tester) =>
      tester
          .widget<ProductButton>(
            find.byKey(const ValueKey('live-order-review')),
          )
          .onPressed !=
      null;

  Future<http.Response> defaults(http.Request request) async =>
      request.url.path.endsWith('capabilities')
      ? _reply(_caps())
      : _reply({'order': null});

  void expectNoRawUnits() {
    expect(find.textContaining('raw units'), findsNothing);
    expect(find.textContaining('Raw token units'), findsNothing);
    expect(find.textContaining('raw token units'), findsNothing);
  }

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
        'termsAccepted': {'issuerId': 'xstocks', 'version': termsVersion},
      });
      // No reviewed multiplier from this server: plain token units.
      expect(find.text('0.012346 NVDAx'), findsOneWidget);
      expect(find.text('0.0123 NVDAx'), findsOneWidget);
      expect(find.text('AAPLx'), findsNothing);
      expectNoRawUnits();
      expect(account.signatures, 0);
      await clean(tester);
    },
  );

  testWidgets(
    'system back from a reviewed quote returns to the amount, keeping it',
    (tester) async {
      var previews = 0;
      await mount(tester, (request) async {
        if (request.url.path.endsWith('preview')) {
          previews++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _reply({
            'order': _order('reviewed', raw: body['amountRaw'] as String),
          });
        }
        return defaults(request);
      }, company: _company('nvidia', unsupportedPrimary: true));
      await tester.enterText(
        find.byKey(const ValueKey('live-order-amount')),
        '2.123456',
      );
      await tap(tester, 'live-order-review');
      expect(previews, 1);
      expect(find.text('Edit amount'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-order-amount')), findsNothing);
      await tester.binding.handlePopRoute();
      await pump(tester);
      expect(
        find.text('Edit amount'),
        findsNothing,
        reason: 'back left the review',
      );
      expect(field(tester), '2.123456', reason: 'and kept the amount');
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
              multiplier: '2',
            ),
          });
        }
        return defaults(request);
      }, sell: true);
      // 1 spendable token shows as 2 shares, as it does in Holdings.
      expect(find.text('2 NVDAx available'), findsOneWidget);
      expect(find.text('You sell'), findsOneWidget);
      expectNoRawUnits();
      await tap(tester, 'live-order-percent-25');
      expect(field(tester), '0.5');
      await tap(tester, 'live-order-max');
      expect(field(tester), '2');
      await tap(tester, 'live-order-review');
      expect(preview!['amountRaw'], '100000000');
      expect(preview!['side'], 'sell');
      expect(find.text('2 NVDAx'), findsOneWidget);
      expectNoRawUnits();
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

  testWidgets('a French buy takes a comma decimal and reads in French', (
    tester,
  ) async {
    Map<String, dynamic>? preview;
    var quotes = 0;
    await mount(tester, (request) async {
      if (request.url.path.endsWith('preview')) {
        quotes++;
        preview = jsonDecode(request.body) as Map<String, dynamic>;
        return _reply({
          'order': _order('reviewed', raw: preview!['amountRaw'] as String),
        });
      }
      return defaults(request);
    }, locale: const Locale('fr'));
    expect(find.text('Acheter NVDAx'), findsOneWidget);
    expect(find.text('Disponible\u00a0: 80 USDC'), findsOneWidget);
    expect(find.text('5\u00a0\$US'), findsOneWidget);
    expect(find.text('Vérifier l’achat'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('live-order-amount')),
      '1,0000001',
    );
    await tap(tester, 'live-order-review');
    expect(find.text('Saisis un montant valide en USDC.'), findsOneWidget);
    expect(quotes, 0);
    await tester.enterText(
      find.byKey(const ValueKey('live-order-amount')),
      '2,5',
    );
    await tap(tester, 'live-order-review');
    expect(preview!['amountRaw'], '2500000');
    expect(find.text('Vérifie ton achat'), findsOneWidget);
    expect(find.text('2,5 USDC'), findsOneWidget);
    expect(find.text('Frais de réseau et de compte'), findsOneWidget);
    expect(find.text('Confirmer l’achat'), findsOneWidget);
    expect(account.signatures, 0);
    await clean(tester);
  });

  testWidgets('newly bought token fills sell Max when holdings arrive late', (
    tester,
  ) async {
    final original = reader.envelope;
    reader.envelope = fixtures.holdingsEnvelopeV2();
    ((reader.envelope['holdings'] as Map)['balances'] as Map)['tokens'] = [];
    await mount(tester, defaults, sell: true);
    expect(field(tester), isEmpty);
    reader.envelope = original;
    await account.refreshPortfolio();
    await pump(tester);
    expect(field(tester), '2');
    expect(find.text('2 NVDAx available'), findsOneWidget);
    await clean(tester);
  });

  testWidgets('late holdings do not overwrite a sell amount the user entered', (
    tester,
  ) async {
    final original = reader.envelope;
    reader.envelope = fixtures.holdingsEnvelopeV2();
    ((reader.envelope['holdings'] as Map)['balances'] as Map)['tokens'] = [];
    await mount(tester, defaults, sell: true);
    final amount = find.byKey(const ValueKey('live-order-amount'));
    await tester.enterText(amount, '0.25');
    reader.envelope = original;
    await account.refreshPortfolio();
    await pump(tester);
    expect(field(tester), '0.25');
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

  test('trade-cap and terms rejections have actionable copy', () {
    expect(
      const LiveOrderFailure('TRADE_LIMIT').message(englishLocalizations),
      'This order is above the current trade limit.',
    );
    expect(
      const LiveOrderFailure('TERMS_REQUIRED').message(englishLocalizations),
      'Confirm the issuer terms to continue.',
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
      // Eligibility was ticked before the quote; the review asks nothing more.
      expect(find.byKey(const ValueKey('live-order-terms')), findsNothing);
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

  group('market state', () {
    testWidgets('a closed token says when it opens and cannot be reviewed', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        _termsKey: [_accepted('ondo')],
      });
      LiveIssuerTerms.resetSession();
      var quotes = 0;
      final caps = _caps();
      final assets = caps['assets'] as List;
      final ondo = assets.indexWhere(
        (asset) => (asset as Map)['mint'] == ondoNvidiaMint,
      );
      assets[ondo] = {
        ...(assets[ondo] as Map<String, Object?>),
        'minBuyInputRaw': '2000000',
        'market': {
          'hours': 'us_sessions',
          'sessions': ['overnight', 'premarket', 'regular', 'postmarket'],
          'status': 'closed',
          'reason': 'outside_sessions',
          'nextOpenAt': DateTime.now()
              .add(const Duration(hours: 3))
              .toUtc()
              .toIso8601String(),
        },
      };
      await mount(
        tester,
        (request) async {
          if (request.url.path.endsWith('capabilities')) return _reply(caps);
          if (request.url.path.endsWith('preview')) quotes++;
          return _reply({'order': null});
        },
        company: _nvidia(),
        variantMint: ondoNvidiaMint,
      );
      expect(
        find.byKey(const ValueKey('live-order-market-state')),
        findsOneWidget,
      );
      expect(find.textContaining('Closed · opens'), findsNWidgets(2));
      expect(
        find.text(
          'Trades 24 hours a day, Sunday evening to Friday evening (US Eastern).',
        ),
        findsOneWidget,
      );
      expect(reviewEnabled(tester), isFalse);
      await tap(tester, 'live-order-review');
      expect(quotes, 0);
      await clean(tester);
    });

    testWidgets(
      'the minimum shows before the first try, and a refusal closes the keyboard and comes into view',
      (tester) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({
          _termsKey: [_accepted('ondo')],
        });
        LiveIssuerTerms.resetSession();
        var quotes = 0;
        final caps = _caps();
        final assets = caps['assets'] as List;
        final ondo = assets.indexWhere(
          (asset) => (asset as Map)['mint'] == ondoNvidiaMint,
        );
        assets[ondo] = {
          ...(assets[ondo] as Map<String, Object?>),
          'minBuyInputRaw': '2000000',
        };
        await mount(
          tester,
          (request) async {
            if (request.url.path.endsWith('capabilities')) return _reply(caps);
            if (request.url.path.endsWith('preview')) quotes++;
            return _reply({'order': null});
          },
          company: _nvidia(),
          variantMint: ondoNvidiaMint,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('live-order-minimum')))
              .data,
          contains('start at'),
          reason: 'the minimum is known before the first try',
        );
        await tester.enterText(
          find.byKey(const ValueKey('live-order-amount')),
          '1',
        );
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>(),
          isNotNull,
        );
        await tap(tester, 'live-order-review');
        await tester.pump(const Duration(milliseconds: 300));
        expect(quotes, 0);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>(),
          isNull,
          reason: 'the keyboard closes before the message shows',
        );
        final notice = find.byKey(const ValueKey('live-order-notice'));
        expect(notice, findsOneWidget);
        final rect = tester.getRect(notice);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(
          rect.bottom,
          lessThanOrEqualTo(700),
          reason: 'the message is on screen',
        );
        await clean(tester);
      },
    );
  });

  group('issuer terms', () {
    testWidgets(
      'the issuer card gates Review until ticked and is remembered per version',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        var quotes = 0;
        Future<http.Response> handler(http.Request request) async {
          if (request.url.path.endsWith('preview')) quotes++;
          return defaults(request);
        }

        await mount(tester, handler);
        expect(find.text('xStocks'), findsOneWidget);
        expect(find.text('Tracker certificate'), findsOneWidget);
        expect(
          find.text('No voting rights. Dividends are reinvested.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Not for residents of United States, United Kingdom, Canada, Australia',
          ),
          findsOneWidget,
        );
        expect(find.text('I accept the xStocks terms.'), findsOneWidget);
        expect(find.text('Issuer terms ↗'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('live-order-issuer-fee')),
          findsNothing,
        );
        expect(reviewEnabled(tester), isFalse);
        await tap(tester, 'live-order-review');
        expect(quotes, 0);

        await tap(tester, 'live-order-terms');
        expect(reviewEnabled(tester), isTrue);
        expect(
          (await SharedPreferences.getInstance()).getStringList(_termsKey),
          [_accepted('xstocks')],
        );

        // A new flow in a later session is not asked again.
        await tester.pumpWidget(const SizedBox());
        LiveIssuerTerms.resetSession();
        await mount(tester, handler);
        expect(reviewEnabled(tester), isTrue);

        // Unticking withdraws the saved acceptance.
        await tap(tester, 'live-order-terms');
        expect(reviewEnabled(tester), isFalse);
        expect(
          (await SharedPreferences.getInstance()).getStringList(_termsKey),
          isEmpty,
        );
        await clean(tester);
      },
    );

    testWidgets(
      'a chosen Ondo token needs Ondo’s tick and sends it with the quote',
      (tester) async {
        Map<String, dynamic>? preview;
        await mount(
          tester,
          (request) async {
            if (request.url.path.endsWith('preview')) {
              preview = jsonDecode(request.body) as Map<String, dynamic>;
              return _reply({
                'order': _order(
                  'reviewed',
                  raw: preview!['amountRaw'] as String,
                  mint: ondoNvidiaMint,
                  quotedOutput: '29510000',
                  minimumOutput: '29000000',
                  multiplier: '5',
                  route: 'rfq',
                ),
              });
            }
            return defaults(request);
          },
          company: _nvidia(),
          variantMint: ondoNvidiaMint,
        );
        expect(find.text('Buy NVDAon'), findsOneWidget);
        expect(find.text('Ondo'), findsOneWidget);
        expect(find.text('Not for residents of United States'), findsOneWidget);
        // xStocks was accepted, but that does not cover another issuer.
        expect(reviewEnabled(tester), isFalse);
        await tap(tester, 'live-order-terms');
        await tap(tester, 'live-order-review');
        expect(preview, {
          'assetId': 'nvidia',
          'variantMint': ondoNvidiaMint,
          'side': 'buy',
          'amountRaw': '5000000',
          'termsAccepted': {'issuerId': 'ondo', 'version': termsVersion},
        });
        // The reviewed multiplier is 5: each token is five shares.
        expect(find.text('0.14755 NVDAon'), findsOneWidget);
        expect(find.text('0.145 NVDAon'), findsOneWidget);
        expect(find.text('Issuer'), findsOneWidget);
        expect(find.text('Issuer fee'), findsNothing);
        // Ondo fills come from a market maker at a fixed price.
        expect(find.text('Fixed quote from a market maker'), findsOneWidget);
        expectNoRawUnits();
        await clean(tester);
      },
    );

    testWidgets(
      'TERMS_REQUIRED clears the tick, rereads the terms and asks again',
      (tester) async {
        var capabilityReads = 0, quotes = 0;
        await mount(tester, (request) async {
          if (request.url.path.endsWith('capabilities')) {
            capabilityReads++;
            return _reply(_caps());
          }
          if (request.url.path.endsWith('preview')) {
            quotes++;
            return _reply({'code': 'TERMS_REQUIRED'}, status: 409);
          }
          return _reply({'order': null});
        });
        expect(reviewEnabled(tester), isTrue);
        await tap(tester, 'live-order-review');
        expect(quotes, 1);
        expect(
          find.text('Confirm the issuer terms to continue.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('live-order-terms')),
              )
              .value,
          isFalse,
        );
        expect(reviewEnabled(tester), isFalse);
        expect(capabilityReads, 2);
        expect(
          (await SharedPreferences.getInstance()).getStringList(_termsKey),
          isEmpty,
        );
        expect(find.byKey(const ValueKey('live-order-confirm')), findsNothing);
        expect(account.signatures, 0);
        await clean(tester);
      },
    );

    testWidgets(
      'a legacy server keeps the generic tick and gets no terms field',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        Map<String, dynamic>? preview;
        await mount(tester, (request) async {
          if (request.url.path.endsWith('capabilities')) {
            return _reply(_legacyCaps());
          }
          if (request.url.path.endsWith('preview')) {
            preview = jsonDecode(request.body) as Map<String, dynamic>;
            return _reply({'order': _order('reviewed')});
          }
          return _reply({'order': null});
        });
        expect(find.text('xStocks'), findsOneWidget);
        expect(
          find.text('I’m eligible under the issuer’s terms.'),
          findsOneWidget,
        );
        expect(find.text('Tracker certificate'), findsNothing);
        expect(reviewEnabled(tester), isFalse);
        await tap(tester, 'live-order-terms');
        await tap(tester, 'live-order-review');
        expect(preview, {
          'assetId': 'nvidia',
          'variantMint': fixtures.nvidiaMint,
          'side': 'buy',
          'amountRaw': '5000000',
        });
        expect(
          find.byKey(const ValueKey('live-order-confirm')),
          findsOneWidget,
        );
        await clean(tester);
      },
    );

    testWidgets('the issuer’s warning sits above the tick', (tester) async {
      const warning =
          'This product is not suitable for all investors. Read the terms.';
      await mount(tester, (request) async {
        if (request.url.path.endsWith('capabilities')) {
          final caps = _caps();
          ((caps['issuers'] as List).first as Map)['warning'] = warning;
          return _reply(caps);
        }
        return _reply({'order': null});
      });
      final shown = find.byKey(const ValueKey('live-order-issuer-warning'));
      expect(tester.widget<Text>(shown).data, warning);
      expect(
        tester.getTopLeft(shown).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('live-order-terms'))).dy,
        ),
      );
      await clean(tester);
    });

    testWidgets('the entry fits a 320px phone at 200% text', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        _termsKey: [_accepted('prestocks')],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LiveOrderFlow(
            account: account,
            origin: _origin,
            company: discoveryCompany('spacex', [
              (preStocksMint, null),
            ], name: 'SpaceX'),
            httpClient: MockClient((request) async {
              if (request.url.path.endsWith('capabilities')) {
                final caps = _caps();
                for (final issuer in caps['issuers'] as List) {
                  (issuer as Map)['warning'] =
                      'The issuer does not recognise wallet holders as '
                      'shareholders. Read the terms before you trade.';
                }
                return _reply(caps);
              }
              return _reply({'order': null});
            }),
            onBack: () {},
            onAddMoney: () async {},
          ),
        ),
      );
      await pump(tester);
      expect(tester.takeException(), isNull);
      final page = find.byType(SingleChildScrollView).first;
      for (var index = 0; index < 6; index++) {
        await tester.drag(page, const Offset(0, -300));
        await pump(tester);
        expect(tester.takeException(), isNull);
      }
      expect(
        find.byKey(const ValueKey('live-order-issuer-warning')),
        findsOneWidget,
      );
      await clean(tester);
    });

    testWidgets('a token of an issuer that is not offered gets no tick', (
      tester,
    ) async {
      await mount(
        tester,
        (request) async {
          if (request.url.path.endsWith('capabilities')) {
            final caps = _caps();
            final ondo =
                (caps['issuers'] as List).firstWhere(
                      (issuer) => (issuer as Map)['issuerId'] == 'ondo',
                    )
                    as Map;
            ondo
              ..['offered'] = false
              ..['notOfferedReason'] = 'Ondo is not offered in Trimmy yet.';
            return _reply(caps);
          }
          return _reply({'order': null});
        },
        company: _nvidia(),
        variantMint: ondoNvidiaMint,
      );
      expect(find.text('This token isn’t tradable here yet'), findsOneWidget);
      expect(find.text('Ondo is not offered in Trimmy yet.'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-order-terms')), findsNothing);
      expect(find.byKey(const ValueKey('live-order-review')), findsNothing);
      await clean(tester);
    });

    testWidgets('an issuer fee shows before the quote and in the review', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        _termsKey: [_accepted('prestocks')],
      });
      await mount(
        tester,
        (request) async {
          if (request.url.path.endsWith('preview')) {
            return _reply({
              'order': _order(
                'reviewed',
                mint: preStocksMint,
                quotedOutput: '48500000',
                minimumOutput: '48000000',
                multiplier: '1',
                delivered: '47000000',
              ),
            });
          }
          return defaults(request);
        },
        company: discoveryCompany('spacex', [
          (preStocksMint, null),
        ], name: 'SpaceX'),
      );
      expect(find.text('PreStocks'), findsOneWidget);
      expect(find.text('Issuer fee: 3% on every buy and sell'), findsOneWidget);
      await tap(tester, 'live-order-review');
      expect(find.text('Issuer fee'), findsOneWidget);
      expect(find.text('3%'), findsOneWidget);
      expect(find.text('PreStocks'), findsOneWidget);
      // After the 3% fee the simulation delivered less than the swap quote.
      expect(find.text('0.047 SPACEX'), findsOneWidget);
      expect(find.text('0.0485 SPACEX'), findsNothing);
      expect(find.text('0.048 SPACEX'), findsOneWidget);
      await clean(tester);
    });
  });

  group('shares', () {
    testWidgets(
      'a 9 decimal sell converts shares through the wallet multiplier',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          _termsKey: [_accepted('ondo')],
        });
        reader.holdOndo();
        Map<String, dynamic>? preview;
        await mount(
          tester,
          (request) async {
            if (request.url.path.endsWith('preview')) {
              preview = jsonDecode(request.body) as Map<String, dynamic>;
              return _reply({
                'order': _order(
                  'reviewed',
                  side: 'sell',
                  raw: preview!['amountRaw'] as String,
                  mint: ondoNvidiaMint,
                  multiplier: '1.5',
                ),
              });
            }
            return defaults(request);
          },
          company: _nvidia(),
          variantMint: ondoNvidiaMint,
          sell: true,
        );
        // 1 token shows as 1.5 shares.
        expect(find.text('1.5 NVDAon available'), findsOneWidget);
        expect(find.text('Order limit: 1.5 NVDAon'), findsOneWidget);
        expect(field(tester), '1.5');
        await tester.enterText(
          find.byKey(const ValueKey('live-order-amount')),
          '0.3',
        );
        await tap(tester, 'live-order-review');
        expect(preview!['amountRaw'], '200000000');
        expect(find.text('0.3 NVDAon'), findsOneWidget);
        expect(find.text('5 USDC'), findsOneWidget);
        expectNoRawUnits();
        await clean(tester);
      },
    );

    testWidgets('Max says when the order limit capped it', (tester) async {
      SharedPreferences.setMockInitialValues({
        _termsKey: [_accepted('ondo')],
      });
      reader.holdOndo();
      Map<String, dynamic>? preview;
      await mount(
        tester,
        (request) async {
          if (request.url.path.endsWith('capabilities')) {
            return _reply(_caps(ondoSellLimit: '500000000'));
          }
          if (request.url.path.endsWith('preview')) {
            preview = jsonDecode(request.body) as Map<String, dynamic>;
            return _reply({
              'order': _order(
                'reviewed',
                side: 'sell',
                raw: preview!['amountRaw'] as String,
                mint: ondoNvidiaMint,
              ),
            });
          }
          return _reply({'order': null});
        },
        company: _nvidia(),
        variantMint: ondoNvidiaMint,
        sell: true,
      );
      expect(find.text('1.5 NVDAon available'), findsOneWidget);
      await tap(tester, 'live-order-percent-25');
      expect(field(tester), '0.375');
      expect(find.text('Order limit: 0.75 NVDAon'), findsOneWidget);
      await tap(tester, 'live-order-percent-75');
      expect(field(tester), '0.75');
      expect(
        find.text('75% capped at the order limit of 0.75 NVDAon.'),
        findsOneWidget,
      );
      await tap(tester, 'live-order-max');
      expect(
        find.text('Max capped at the order limit of 0.75 NVDAon.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('live-order-amount')),
        '0.9',
      );
      // Let the field's caret scroll settle before tapping below it.
      await pump(tester);
      expect(find.text('Order limit: 0.75 NVDAon'), findsOneWidget);
      await tap(tester, 'live-order-review');
      expect(find.text('Up to 0.75 NVDAon per order.'), findsOneWidget);
      expect(preview, isNull);
      await tap(tester, 'live-order-max');
      await tap(tester, 'live-order-review');
      expect(preview!['amountRaw'], '500000000');
      await clean(tester);
    });

    testWidgets('the order limit note reads in Brazilian Portuguese', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        _termsKey: [_accepted('ondo')],
      });
      reader.holdOndo();
      await mount(
        tester,
        (request) async {
          if (request.url.path.endsWith('capabilities')) {
            return _reply(_caps(ondoSellLimit: '500000000'));
          }
          return _reply({'order': null});
        },
        company: _nvidia(),
        variantMint: ondoNvidiaMint,
        sell: true,
        locale: const Locale('pt', 'BR'),
      );
      expect(find.text('Disponível: 1,5 NVDAon'), findsOneWidget);
      await tap(tester, 'live-order-percent-25');
      expect(field(tester), '0,375');
      expect(find.text('Limite por ordem: 0,75 NVDAon'), findsOneWidget);
      await tap(tester, 'live-order-percent-75');
      expect(
        find.text('75% foi limitado a 0,75 NVDAon, o limite por ordem.'),
        findsOneWidget,
      );
      await tap(tester, 'live-order-max');
      expect(
        find.text('O máximo foi limitado a 0,75 NVDAon, o limite por ordem.'),
        findsOneWidget,
      );
      await clean(tester);
    });

    testWidgets('a 6 decimal token reads in its own precision', (tester) async {
      SharedPreferences.setMockInitialValues({
        _termsKey: [_accepted('backpack')],
      });
      await mount(
        tester,
        (request) async {
          if (request.url.path.endsWith('preview')) {
            return _reply({
              'order': _order(
                'reviewed',
                mint: backpackNvidiaMint,
                quotedOutput: '2500000',
                minimumOutput: '2475000',
              ),
            });
          }
          return defaults(request);
        },
        company: _nvidia(),
        variantMint: backpackNvidiaMint,
      );
      expect(find.text('Buy NVDAbp'), findsOneWidget);
      await tap(tester, 'live-order-review');
      expect(find.text('2.5 NVDAbp'), findsOneWidget);
      expect(find.text('2.475 NVDAbp'), findsOneWidget);
      expect(find.text('Backpack'), findsOneWidget);
      await clean(tester);
    });

    testWidgets('a chosen token that stops trading is never swapped out', (
      tester,
    ) async {
      await mount(
        tester,
        (request) async {
          if (request.url.path.endsWith('capabilities')) {
            final caps = _caps();
            (caps['assets'] as List).removeWhere(
              (asset) => (asset as Map)['mint'] == ondoNvidiaMint,
            );
            return _reply(caps);
          }
          return _reply({'order': null});
        },
        company: _nvidia(),
        variantMint: ondoNvidiaMint,
      );
      expect(find.text('This token isn’t tradable here yet'), findsOneWidget);
      expect(find.text('Buy NVDAx'), findsNothing);
      await clean(tester);
    });

    testWidgets('an unusable reviewed multiplier reads as token units', (
      tester,
    ) async {
      await mount(tester, (request) async {
        if (request.url.path.endsWith('preview')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _reply({
            'order': _order(
              'reviewed',
              side: 'sell',
              raw: body['amountRaw'] as String,
              multiplier: 'NaN',
            ),
          });
        }
        return defaults(request);
      }, sell: true);
      await tap(tester, 'live-order-max');
      await tap(tester, 'live-order-review');
      // The wallet counts 2 shares, but without a usable multiplier the
      // review shows the 1 token being sold, never a guess.
      expect(find.text('1 NVDAx'), findsOneWidget);
      expect(find.text('2 NVDAx'), findsNothing);
      await clean(tester);
    });

    testWidgets('a typed sell reads back unchanged through a real multiplier', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        _termsKey: [_accepted('ondo')],
      });
      // The wallet truncates 1.0009180758490996 shares per token.
      reader.holdOndo(display: '1.000918075');
      Map<String, dynamic>? preview;
      await mount(
        tester,
        (request) async {
          if (request.url.path.endsWith('preview')) {
            preview = jsonDecode(request.body) as Map<String, dynamic>;
            return _reply({
              'order': _order(
                'reviewed',
                side: 'sell',
                raw: preview!['amountRaw'] as String,
                mint: ondoNvidiaMint,
                multiplier: '1.0009180758490996',
              ),
            });
          }
          return defaults(request);
        },
        company: _nvidia(),
        variantMint: ondoNvidiaMint,
        sell: true,
      );
      await tester.enterText(
        find.byKey(const ValueKey('live-order-amount')),
        '0.5',
      );
      await tap(tester, 'live-order-review');
      expect(preview!['amountRaw'], '499541384');
      expect(find.text('0.5 NVDAon'), findsOneWidget);
      await clean(tester);
    });
  });
}
