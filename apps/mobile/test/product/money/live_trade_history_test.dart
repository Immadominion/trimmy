import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/market/live_trading.dart';
import 'package:trimmy/product/money/live_trade_history.dart';

import '../../support/account_data_fixtures.dart' as fixtures;

final _origin = Uri.parse('https://trimmy.example');
String _id(int value) =>
    '11111111-1111-4111-8111-${value.toString().padLeft(12, '0')}';
Map<String, Object?> _trade(
  int id, {
  String status = 'confirmed',
  bool buy = true,
}) => {
  'id': _id(id),
  'wallet': fixtures.wallet,
  'status': status,
  'signature': '2' * 88,
  'createdAt': '2026-09-25T13:00:00.123456Z',
  'updatedAt': '2026-09-25T13:00:10.123456Z',
  'asset': {
    'assetId': 'nvidia',
    'mint': fixtures.nvidiaMint,
    'symbol': 'NVDAx',
    'name': 'NVIDIA',
    'decimals': 8,
  },
  'terms': <String, Object?>{
    'side': buy ? 'buy' : 'sell',
    'inputMint': buy ? liveUsdcMint : fixtures.nvidiaMint,
    'outputMint': buy ? fixtures.nvidiaMint : liveUsdcMint,
    'inputAmountRaw': buy ? '5000000' : '12345678',
    'quotedOutputAmountRaw': buy ? '12345678' : '5000000',
    'minimumOutputAmountRaw': buy ? '12000000' : '4900000',
  },
  'amountUnits': 'raw_token_units',
  'amountsStatus': 'reviewed_quote',
};
Map<String, Object?> _page(List<Map<String, Object?>> rows, {String? cursor}) =>
    {
      'schemaVersion': 1,
      'network': 'solana:mainnet-beta',
      'orders': rows,
      'nextCursor': cursor,
    };
http.Response _reply(Object? value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

class _Account extends ChangeNotifier implements AccountController {
  @override
  String? accountId = fixtures.account;
  @override
  int navigationEpoch = 0;
  @override
  AccountPhase phase = AccountPhase.active;
  Completer<PracticeAccessToken>? tokenCompleter;
  @override
  Future<PracticeAccessToken> freshAccessToken() async =>
      tokenCompleter?.future ??
      PracticeAccessToken(accountId: accountId!, token: 'test-token');
  void changeAccount() {
    accountId = 'another-account';
    navigationEpoch++;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump(const Duration(milliseconds: 1800));
}

Future<void> _mount(
  WidgetTester tester,
  _Account account,
  http.Client client, {
  Future<bool> Function(Uri)? explorer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: productTheme(),
      home: LiveTradeHistoryScreen(
        account: account,
        origin: _origin,
        onBack: () {},
        httpClient: client,
        openExplorer: explorer,
      ),
    ),
  );
  await _pump(tester);
}

Future<void> _close(WidgetTester tester, _Account account) async {
  await tester.pumpWidget(const SizedBox());
  account.dispose();
}

void main() {
  test(
    'history preserves exact quantities and labels quotes instead of fills',
    () {
      final page = LiveTradeHistoryPage.fromJson(
        _page([_trade(1), _trade(2, buy: false)]),
      );
      expect(page.orders.first.inputLabel, '5 USDC');
      expect(page.orders.first.quotedOutputLabel, '0.12345678 NVDAx raw units');
      expect(page.orders.last.inputLabel, '0.12345678 NVDAx raw units');
      expect(page.orders.last.minimumOutputLabel, '4.9 USDC');
      expect(page.orders.first.createdAt.microsecond, 456);
      expect(page.orders.first.explorer.host, 'solscan.io');
    },
  );

  test(
    'malformed amounts, sides, networks and duplicate records fail closed',
    () {
      final mutations = <void Function(Map<String, Object?>)>[
        (row) => row['status'] = 'reviewed',
        (row) => row['signature'] = null,
        (row) => row['signature'] = 'https://other.test',
        (row) => row['amountsStatus'] = 'final_fill',
        (row) => (row['terms'] as Map)['inputMint'] = fixtures.wallet,
        (row) => (row['terms'] as Map)['inputAmountRaw'] = 5000000,
        (row) =>
            (row['terms'] as Map)['inputAmountRaw'] = '18446744073709551616',
        (row) => (row['terms'] as Map)['minimumOutputAmountRaw'] = '999999999',
        (row) => (row['asset'] as Map)['decimals'] = 19,
        (row) => row['createdAt'] = '2026-09-25T13:00:00',
      ];
      for (final mutate in mutations) {
        final row = _trade(1);
        mutate(row);
        expect(
          () => LiveTradeHistoryPage.fromJson(_page([row])),
          throwsFormatException,
        );
      }
      expect(
        () => LiveTradeHistoryPage.fromJson({
          ..._page([]),
          'network': 'solana:devnet',
        }),
        throwsFormatException,
      );
      expect(
        () => LiveTradeHistoryPage.fromJson(_page([_trade(1), _trade(1)])),
        throwsFormatException,
      );
      expect(
        () => LiveTradeHistoryPage.fromJson(_page([], cursor: 'more')),
        throwsFormatException,
      );
    },
  );

  test(
    'history is authenticated GET with escaped cursor and never follows redirects',
    () async {
      final account = _Account();
      final client = LiveTradeHistoryClient(
        account: account,
        origin: _origin,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/v1/trading/history');
          expect(request.url.queryParameters, {
            'limit': '20',
            'cursor': 'opaque+/=cursor',
          });
          expect(request.headers['authorization'], 'Bearer test-token');
          expect(request.followRedirects, isFalse);
          return _reply(_page([_trade(1)]));
        }),
      );
      expect((await client.read(cursor: 'opaque+/=cursor')).orders.length, 1);
      client.close();
      account.dispose();
    },
  );

  test(
    'account switch during token acquisition prevents authenticated dispatch',
    () async {
      final account = _Account()
        ..tokenCompleter = Completer<PracticeAccessToken>();
      var dispatched = 0;
      final client = LiveTradeHistoryClient(
        account: account,
        origin: _origin,
        client: MockClient((_) async {
          dispatched++;
          return _reply(_page([]));
        }),
      );
      final result = client.read();
      final failure = expectLater(
        result,
        throwsA(
          isA<LiveTradeHistoryFailure>().having(
            (e) => e.code,
            'code',
            'ACCOUNT_REQUIRED',
          ),
        ),
      );
      account.changeAccount();
      account.tokenCompleter!.complete(
        PracticeAccessToken(accountId: fixtures.account, token: 'old-token'),
      );
      await failure;
      expect(dispatched, 0);
      client.close();
      account.dispose();
    },
  );

  test(
    'old account response is discarded after an in-flight account switch',
    () async {
      final account = _Account();
      final reply = Completer<http.Response>();
      final sent = Completer<void>();
      final client = LiveTradeHistoryClient(
        account: account,
        origin: _origin,
        client: MockClient((_) {
          sent.complete();
          return reply.future;
        }),
      );
      final failure = expectLater(
        client.read(),
        throwsA(
          isA<LiveTradeHistoryFailure>().having(
            (e) => e.code,
            'code',
            'ACCOUNT_REQUIRED',
          ),
        ),
      );
      await sent.future;
      account.changeAccount();
      reply.complete(_reply(_page([_trade(1)])));
      await failure;
      client.close();
      account.dispose();
    },
  );

  test('oversized responses and nonadvancing cursors are rejected', () async {
    final account = _Account();
    var oversized = true;
    final client = LiveTradeHistoryClient(
      account: account,
      origin: _origin,
      client: MockClient(
        (_) async => oversized
            ? http.Response('x' * 131073, 200)
            : _reply(_page([_trade(1)], cursor: 'same')),
      ),
    );
    await expectLater(client.read(), throwsA(isA<LiveTradeHistoryFailure>()));
    oversized = false;
    await expectLater(client.read(cursor: 'same'), throwsFormatException);
    client.close();
    account.dispose();
  });

  testWidgets(
    'history displays status and exact quoted details with a safe explorer link',
    (tester) async {
      final account = _Account();
      Uri? opened;
      await _mount(
        tester,
        account,
        MockClient(
          (_) async => _reply(_page([_trade(1), _trade(2, status: 'failed')])),
        ),
        explorer: (uri) async {
          opened = uri;
          return true;
        },
      );
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Not completed'), findsOneWidget);
      expect(find.textContaining('paper'), findsNothing);
      await tester.tap(find.byKey(ValueKey('trade-${_id(1)}')));
      await tester.pump();
      expect(find.text('Quoted output'), findsOneWidget);
      expect(find.text('0.12345678 NVDAx raw units'), findsOneWidget);
      await tester.tap(find.text('View transaction'));
      await _pump(tester);
      expect(opened, Uri.https('solscan.io', '/tx/${'2' * 88}'));
      await _close(tester, account);
    },
  );

  testWidgets(
    'pagination failure retains rows and retries without duplicates',
    (tester) async {
      final account = _Account();
      var moreCalls = 0;
      await _mount(
        tester,
        account,
        MockClient((request) async {
          if (!request.url.queryParameters.containsKey('cursor')) {
            return _reply(_page([_trade(1)], cursor: 'older'));
          }
          moreCalls++;
          return moreCalls == 1
              ? _reply({'code': 'HISTORY_UNAVAILABLE'}, status: 503)
              : _reply(_page([_trade(1), _trade(2, buy: false)]));
        }),
      );
      await tester.tap(find.text('More trades'));
      await _pump(tester);
      expect(find.byKey(ValueKey('trade-${_id(1)}')), findsOneWidget);
      expect(
        find.text('Couldn’t load your trades. Try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('More trades'));
      await _pump(tester);
      expect(find.byKey(ValueKey('trade-${_id(1)}')), findsOneWidget);
      expect(find.byKey(ValueKey('trade-${_id(2)}')), findsOneWidget);
      expect(find.text('More trades'), findsNothing);
      await _close(tester, account);
    },
  );

  testWidgets(
    'retry recovers the unavailable state and empty history stays honest',
    (tester) async {
      final account = _Account();
      var calls = 0;
      await _mount(
        tester,
        account,
        MockClient((_) async {
          calls++;
          return calls == 1 ? _reply({}, status: 503) : _reply(_page([]));
        }),
      );
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await _pump(tester);
      expect(find.text('Your first trade starts here'), findsOneWidget);
      await _close(tester, account);
    },
  );

  testWidgets(
    'pending history reconciles through GET and becomes confirmed automatically',
    (tester) async {
      final account = _Account();
      var resolved = false, reconciles = 0;
      await _mount(
        tester,
        account,
        MockClient((request) async {
          expect(request.method, 'GET');
          if (request.url.path.startsWith('/v1/trading/order/')) {
            reconciles++;
            resolved = true;
            return _reply({
              'order': {'id': _id(1), 'status': 'confirmed'},
            });
          }
          return _reply(
            _page([_trade(1, status: resolved ? 'confirmed' : 'pending')]),
          );
        }),
      );
      expect(find.text('Confirming'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await _pump(tester);
      expect(reconciles, 1);
      expect(find.text('Confirmed'), findsOneWidget);
      await _close(tester, account);
    },
  );

  testWidgets('account changes immediately remove the previous user history', (
    tester,
  ) async {
    final account = _Account();
    await _mount(
      tester,
      account,
      MockClient((_) async => _reply(_page([_trade(1)]))),
    );
    expect(find.text('Buy NVDAx'), findsOneWidget);
    account.changeAccount();
    await tester.pump();
    expect(find.text('Buy NVDAx'), findsNothing);
    expect(find.text('Sign in again to see your trades.'), findsOneWidget);
    await _close(tester, account);
  });

  testWidgets(
    'pagination during pending reconciliation cannot strand Loading',
    (tester) async {
      final account = _Account();
      final reconciliation = Completer<http.Response>();
      final older = Completer<http.Response>();
      var reconciling = false, paging = false;
      await _mount(
        tester,
        account,
        MockClient((request) async {
          if (request.url.path.startsWith('/v1/trading/order/')) {
            reconciling = true;
            return reconciliation.future;
          }
          if (request.url.queryParameters.containsKey('cursor')) {
            paging = true;
            return older.future;
          }
          return _reply(_page([_trade(1, status: 'pending')], cursor: 'older'));
        }),
      );
      await tester.pump(const Duration(seconds: 10));
      await _pump(tester);
      expect(reconciling, isTrue);
      await tester.tap(find.text('More trades'));
      await _pump(tester);
      expect(paging, isTrue);
      reconciliation.complete(
        _reply({
          'order': {'id': _id(1), 'status': 'confirmed'},
        }),
      );
      await _pump(tester);
      older.complete(_reply(_page([_trade(2, buy: false)])));
      await _pump(tester);
      expect(find.text('Loading…'), findsNothing);
      expect(find.byKey(ValueKey('trade-${_id(2)}')), findsOneWidget);
      await _close(tester, account);
    },
  );

  testWidgets(
    'replacing the account controller clears old rows before the next response',
    (tester) async {
      final previous = _Account(),
          next = _Account()..accountId = 'next-account';
      await _mount(
        tester,
        previous,
        MockClient((_) async => _reply(_page([_trade(1)]))),
      );
      final reply = Completer<http.Response>();
      await _mount(tester, next, MockClient((_) => reply.future));
      expect(find.byKey(ValueKey('trade-${_id(1)}')), findsNothing);
      reply.complete(_reply(_page([_trade(2, buy: false)])));
      await _pump(tester);
      expect(find.byKey(ValueKey('trade-${_id(2)}')), findsOneWidget);
      await _close(tester, next);
      previous.dispose();
    },
  );

  testWidgets('returning from the stock route refreshes newly placed trades', (
    tester,
  ) async {
    final account = _Account(), returned = Completer<void>();
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return _reply(_page([_trade(1), if (returned.isCompleted) _trade(2)]));
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: LiveTradeHistoryScreen(
          account: account,
          origin: _origin,
          httpClient: client,
          onBack: () {},
          onOpenAsset: (assetId, mint) async {
            expect(assetId, 'nvidia');
            expect(mint, fixtures.nvidiaMint);
            await returned.future;
          },
        ),
      ),
    );
    await _pump(tester);
    await tester.tap(find.byKey(ValueKey('trade-${_id(1)}')));
    await tester.pump();
    await tester.tap(find.text('Open stock'));
    await _pump(tester);
    expect(calls, 1);
    returned.complete();
    await _pump(tester);
    expect(calls, 2);
    expect(find.byKey(ValueKey('trade-${_id(2)}')), findsOneWidget);
    await _close(tester, account);
  });
}
