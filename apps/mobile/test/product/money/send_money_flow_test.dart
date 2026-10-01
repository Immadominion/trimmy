import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/account/wallet_trade_signer.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/money/real_holdings.dart';
import 'package:trimmy/product/money/send_money_flow.dart';
import '../../support/account_data_fixtures.dart' as fixtures;
import '../../support/l10n_harness.dart';

const _friend = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
const _ondoMint = 'GbfDNU3Mx1nHrGdDqWhk3kqVtbzbx9frxMV8Srb6vEtd';
final _policyFixtures =
    jsonDecode(
          File(
            '../../tool/testing/fixtures/client-send-policy.json',
          ).readAsStringSync(),
        )
        as List;
String _wire(String name) =>
    _policyFixtures.firstWhere(
          (item) => item['name'] == name,
        )['envelope']['unsignedTransaction']
        as String;
final _origin = Uri.parse('https://trimmy.example');

class _Reader implements AccountPortfolioReader {
  Map<String, Object?> envelope = fixtures.holdingsEnvelopeV2();
  _Reader() {
    final balances = (envelope['holdings'] as Map)['balances'] as Map;
    final usdc = balances['usdc'] as Map;
    usdc['amountRaw'] = '100000000';
    usdc['availableToTradeRaw'] = '80000000';
    usdc['hasFrozenAccounts'] = false;
    (balances['nativeSol'] as Map)['amountRaw'] = '50000000';
    // One token that shows as 1.5 shares.
    (balances['tokens'] as List).add({
      'assetId': 'nvidia',
      'name': 'NVIDIA Ondo',
      ...fixtures.tokenBalance(
        symbol: 'NVDAon',
        mint: _ondoMint,
        decimals: 9,
        amountRaw: '1000000000',
        slot: 447040361,
      ),
      'displayAmount': '1.5',
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
  }) async => AccountHoldingsSnapshot.fromEnvelope(
    envelope,
    expectedUserId: fixtures.account,
  );
  @override
  void cancelPending() {}
  @override
  void close() {}
}

class _Account extends ChangeNotifier implements AccountController {
  _Account(this.portfolio);
  final AccountPortfolioRepository portfolio;
  int signatures = 0, refreshes = 0;
  String? cancelWith;
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
  }

  @override
  Future<String> signReviewedStockTransaction({
    required String wallet,
    required String transaction,
    required DateTime expiresAt,
  }) async {
    if (cancelWith != null) throw WalletTradeException(cancelWith!);
    signatures++;
    return 'c2lnbmVk${'A' * 120}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response _reply(Object? value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _review({
  String destination = _friend,
  String amountRaw = '5000000',
  String? mint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
  String symbol = 'USDC',
  int decimals = 6,
  String received = '5000000',
}) => {
  'id': '77777777-7777-4777-8777-777777777777',
  'review': {
    'asset': {
      'kind': mint == null ? 'sol' : 'token',
      'mint': mint,
      'symbol': symbol,
      'decimals': decimals,
      'uiMultiplier': mint == _ondoMint ? '1.5' : '1',
    },
    'from': fixtures.wallet,
    'destination': destination,
    'amountRaw': amountRaw,
    'receivedRaw': received,
    'createsAccount': true,
    'accountRentLamports': '2039280',
    'networkFeeLamports': '8000',
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 1))
        .toIso8601String(),
  },
  'unsignedTransaction': _wire(
    mint == null
        ? 'sol'
        : mint == _ondoMint
        ? 'stock'
        : 'usdc',
  ),
  'reviewToken': 'payload.mac',
};

void main() {
  late _Account account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final portfolio = AccountPortfolioRepository(
      reader: _Reader(),
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    await portfolio.refresh();
    account = _Account(portfolio);
  });

  Future<void> pump(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<List<http.Request>> mount(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    String? asset,
    bool handleRecovery = false,
    Locale? locale,
  }) async {
    final requests = <http.Request>[];
    final flow = SendMoneyFlow(
      account: account,
      origin: _origin,
      initialAsset: asset,
      pollInterval: const Duration(milliseconds: 10),
      httpClient: MockClient((request) {
        if (!handleRecovery && request.url.path.endsWith('/recovery')) {
          return Future.value(_reply({'transfer': null}));
        }
        requests.add(request);
        return handler(request);
      }),
      onBack: () {},
    );
    await tester.pumpWidget(
      locale == null
          ? MaterialApp(theme: productTheme(), home: flow)
          : localizedTestApp(locale: locale, home: flow),
    );
    await pump(tester);
    return requests;
  }

  Future<void> fill(WidgetTester tester, String to, String amount) async {
    await tester.enterText(find.byKey(const ValueKey('send-destination')), to);
    await tester.enterText(find.byKey(const ValueKey('send-amount')), amount);
    await tester.tap(find.byKey(const ValueKey('send-review')));
    await pump(tester);
  }

  testWidgets(
    'sends USDC after the review, signed once, and shows it confirmed',
    (tester) async {
      final requests = await mount(tester, (request) async {
        if (request.url.path.endsWith('/preview')) return _reply(_review());
        if (request.url.path.endsWith('/execute')) {
          return _reply({'signature': '5' * 88});
        }
        return _reply({'status': 'confirmed', 'slot': 9});
      });
      await fill(tester, _friend, '5');
      expect(jsonDecode(requests.single.body), {
        'asset': 'USDC',
        'destination': _friend,
        'amountRaw': '5000000',
      });
      expect(requests.single.headers['authorization'], 'Bearer test-token');
      expect(
        find.byKey(const ValueKey('send-review-destination')),
        findsOneWidget,
      );
      expect(find.text('5 USDC'), findsOneWidget);
      expect(find.text('Opens their USDC account (once)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('send-confirm')));
      await pump(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await pump(tester);
      expect(account.signatures, 1);
      expect(jsonDecode(requests[1].body), {
        'reviewToken': 'payload.mac',
        'signedTransaction': 'c2lnbmVk${'A' * 120}',
      });
      expect(find.text('Sent'), findsOneWidget);
      expect(account.refreshes, greaterThan(0));
    },
  );

  testWidgets('a French send takes a comma decimal and reads in French', (
    tester,
  ) async {
    final requests = await mount(tester, (request) async {
      if (request.url.path.endsWith('/preview')) {
        return _reply(_review(amountRaw: '2500000', received: '2500000'));
      }
      return _reply({'status': 'pending'});
    }, locale: const Locale('fr'));
    expect(find.text('Envoyer vers un portefeuille Solana'), findsOneWidget);
    await fill(tester, fixtures.wallet, '5');
    expect(
      find.text('C’est ton propre portefeuille. Saisis une autre adresse.'),
      findsOneWidget,
    );
    await fill(tester, _friend, '2,5');
    expect(jsonDecode(requests.single.body)['amountRaw'], '2500000');
    expect(find.text('Vérifie ton envoi'), findsOneWidget);
    expect(find.text('2,5 USDC'), findsOneWidget);
    expect(find.text('Frais de réseau'), findsOneWidget);
    expect(find.text('Envoyer maintenant'), findsOneWidget);
    expect(account.signatures, 0);
  });

  testWidgets('never shows a review for a different send than was asked', (
    tester,
  ) async {
    await mount(
      tester,
      (request) async => _reply(_review(destination: fixtures.nvidiaMint)),
    );
    await fill(tester, _friend, '5');
    expect(find.byKey(const ValueKey('send-confirm')), findsNothing);
    expect(find.byKey(const ValueKey('send-notice')), findsOneWidget);
    expect(account.signatures, 0);
  });

  testWidgets('checks the address and amount before asking the server', (
    tester,
  ) async {
    final requests = await mount(
      tester,
      (_) async => _reply({'code': 'DESTINATION_NOT_WALLET'}, status: 409),
    );
    await fill(tester, fixtures.wallet, '5');
    expect(
      find.text('That’s your own wallet. Enter another address.'),
      findsOneWidget,
    );
    await fill(tester, _friend, '81');
    expect(find.textContaining('ready to send.'), findsWidgets);
    expect(requests, isEmpty);
    await fill(tester, _friend, '5');
    expect(find.textContaining('That address isn’t a wallet.'), findsOneWidget);
  });

  testWidgets(
    'a pasted address is read exactly: trimmed, from a plain solana: link, never stripped',
    (tester) async {
      final requests = await mount(tester, (request) async {
        return _reply(_review());
      });
      // A leading space and a line break no longer cost the last character.
      await fill(tester, ' $_friend\n', '5');
      expect(jsonDecode(requests.single.body)['destination'], _friend);
    },
  );

  testWidgets(
    'a solana: link gives its address; a character outside it is refused',
    (tester) async {
      final requests = await mount(tester, (_) async => _reply(_review()));
      // 'l' is not in the address alphabet: refused, not quietly removed.
      await fill(tester, '${_friend}l', '5');
      expect(requests, isEmpty);
      expect(find.byKey(const ValueKey('send-notice')), findsOneWidget);
      await fill(tester, 'solana:$_friend', '5');
      expect(jsonDecode(requests.single.body)['destination'], _friend);
    },
  );

  testWidgets('the sheet can close while it checks for an earlier send', (
    tester,
  ) async {
    final recovery = Completer<http.Response>();
    var closed = 0;
    final flow = SendMoneyFlow(
      account: account,
      origin: _origin,
      httpClient: MockClient((request) => recovery.future),
      onBack: () => closed++,
    );
    await tester.pumpWidget(MaterialApp(theme: productTheme(), home: flow));
    await tester.pump();
    final back = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
    );
    expect(
      back.onPressed,
      isNotNull,
      reason: 'closing never waits on the check',
    );
    back.onPressed!();
    expect(closed, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('send-amount')))
          .enabled,
      isFalse,
      reason: 'the form waits for the check',
    );
    recovery.complete(_reply({'transfer': null}));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sends stock tokens in shares, and cancelling sends nothing', (
    tester,
  ) async {
    final requests = await mount(tester, (request) async {
      return _reply(
        _review(
          mint: _ondoMint,
          symbol: 'NVDAon',
          decimals: 9,
          amountRaw: '1000000000',
          received: '1000000000',
        ),
      );
    }, asset: _ondoMint);
    await tester.tap(find.byKey(const ValueKey('send-max')));
    await tester.pump();
    expect(find.widgetWithText(TextField, '1.5'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('send-destination')),
      _friend,
    );
    await tester.tap(find.byKey(const ValueKey('send-review')));
    await pump(tester);
    expect(
      (jsonDecode(requests.single.body) as Map)['amountRaw'],
      '1000000000',
    );
    expect(find.text('1.5 NVDAon'), findsOneWidget);
    account.cancelWith = 'SIGNING_CANCELLED';
    await tester.tap(find.byKey(const ValueKey('send-confirm')));
    await pump(tester);
    expect(
      find.text('Signing was cancelled. Nothing was sent.'),
      findsOneWidget,
    );
    expect(requests, hasLength(1));
  });

  testWidgets('hidden extra transfer is rejected before the wallet signs', (
    tester,
  ) async {
    final requests = await mount(
      tester,
      (_) async => _reply({
        ..._review(),
        'unsignedTransaction': _wire('usdc/extra-sol'),
      }),
    );
    await fill(tester, _friend, '5');
    await tester.tap(find.byKey(const ValueKey('send-confirm')));
    await pump(tester);
    expect(find.textContaining('doesn’t match your review'), findsOneWidget);
    expect(account.signatures, 0);
    expect(requests.length, 1);
  });

  test('Max keeps SOL for fees and lists only what can be sent', () async {
    final holdings = realWalletHoldings(account)!;
    final assets = sendableAssets(holdings);
    expect(assets.map((a) => a.id).take(2), ['USDC', 'SOL']);
    expect(assets.map((a) => a.id), contains(_ondoMint));
    expect(assets[0].availableRaw, '80000000');
    expect(assets[1].maxRaw, '48000000');
  });
  testWidgets(
    'lost acknowledgement and reopening recover the same send without signing again',
    (tester) async {
      var broadcasts = 0;
      Future<http.Response> handler(http.Request request) async {
        if (request.url.path.endsWith('/recovery')) {
          return _reply({
            'transfer': broadcasts == 0
                ? null
                : {..._review(), 'status': 'pending', 'signature': '5' * 88},
          });
        }
        if (request.url.path.endsWith('/preview')) return _reply(_review());
        if (request.url.path.endsWith('/execute')) {
          broadcasts++;
          throw Exception('reply lost');
        }
        return _reply({'status': 'pending', 'slot': null});
      }

      await mount(tester, handler, handleRecovery: true);
      await fill(tester, _friend, '5');
      await tester.tap(find.byKey(const ValueKey('send-confirm')));
      await pump(tester);
      expect(find.text('Sending'), findsOneWidget);
      expect(account.signatures, 1);
      expect(broadcasts, 1);
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      await mount(tester, handler, handleRecovery: true);
      expect(find.text('Sending'), findsOneWidget);
      expect(account.signatures, 1);
      expect(broadcasts, 1);
      expect(find.byKey(const ValueKey('send-confirm')), findsNothing);
    },
  );
}
