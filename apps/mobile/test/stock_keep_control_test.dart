import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/markets/followed_stocks.dart';
import 'package:trimmy/markets/followed_stocks_controller.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'package:trimmy/markets/stock_research_panel.dart';
import 'package:trimmy/practice_sync/http_transport.dart';

import 'support/stock_research_fixtures.dart';

const _account = '9f000000-0000-4000-8000-000000000001';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

final class _Discovery implements StockResearchClient {
  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) async =>
      StockSearchPage.fromJson(stockSearchFixture(query: query, limit: limit));

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) async =>
      StockVariantsPage.fromJson(stockVariantsFixture(assetId: assetId));

  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('unused');
}

final class _UnusedHistory implements StockHistoryClient {
  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('unused');
}

final class _UnusedRaydium implements RaydiumQuoteClient {
  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) async => throw StateError('unused');
}

final class _HeldTimer implements Timer {
  var active = true;
  @override
  void cancel() => active = false;
  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
}

Future<void> _mount(
  WidgetTester tester, {
  FollowedStocksController? following,
}) async {
  final controller = StockResearchController.withClients(
    researchClient: _Discovery(),
    historyClient: _UnusedHistory(),
    raydiumClient: _UnusedRaydium(),
    clock: () => DateTime.parse('2026-09-14T18:00:02.000Z'),
    timerFactory: (delay, callback) => _HeldTimer(),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StockResearchPanel(
            controller: controller,
            following: following,
          ),
        ),
      ),
    ),
  );
  await tester.enterText(
    find.byKey(const ValueKey('stock-research-query')),
    'Apple',
  );
  await tester.tap(find.byKey(const ValueKey('stock-research-search')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a guest is offered no way to keep a stock', (tester) async {
    await _mount(tester);
    expect(find.text('Apple (AAPL)'), findsOne);
    // Keeping needs an account, so it is absent rather than offered and refused.
    expect(find.byKey(const ValueKey('stock-keep-apple')), findsNothing);
  });

  testWidgets('a verified account can keep a looked-up stock', (tester) async {
    var stored = <String>[];
    var revision = 0;
    final requests = <String>[];
    final following = FollowedStocksController(
      client: HttpFollowedStocksClient(
        client: MockClient((request) async {
          requests.add(request.method);
          if (request.method == 'GET') {
            return _json({
              'schemaVersion': 1,
              'revision': revision,
              'assetIds': stored,
              'updatedAt': revision == 0 ? null : '2026-09-19T10:00:00.000Z',
            });
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          stored = (body['assetIds'] as List).cast<String>();
          revision += 1;
          return _json({
            'schemaVersion': 1,
            'revision': revision,
            'assetIds': stored,
            'updatedAt': '2026-09-19T10:00:00.000Z',
          });
        }),
        baseUri: Uri.parse('https://api.example'),
        accountId: _account,
        accessToken: () async =>
            PracticeAccessToken(accountId: _account, token: 'a.b.c'),
      ),
    );
    addTearDown(following.dispose);

    await _mount(tester, following: following);
    await tester.pumpAndSettle();
    // Opening the panel reads the list once, so the control tells the truth.
    expect(requests, ['GET']);

    final keep = find.byKey(const ValueKey('stock-keep-apple'));
    expect(keep, findsOne);
    expect(
      tester.widget<TextButton>(keep).child.toString(),
      contains('Keep this'),
    );

    await tester.tap(keep);
    await tester.pumpAndSettle();
    expect(stored, ['apple'], reason: 'the server holds the identifier only');
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('stock-keep-apple')))
          .child
          .toString(),
      contains('Kept'),
    );

    // Removing it is the same control, and writes the emptied list.
    await tester.tap(find.byKey(const ValueKey('stock-keep-apple')));
    await tester.pumpAndSettle();
    expect(stored, isEmpty);
  });

  testWidgets('a refusal is explained in plain words', (tester) async {
    final following = FollowedStocksController(
      client: HttpFollowedStocksClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return _json({
              'schemaVersion': 1,
              'revision': 0,
              'assetIds': const [],
              'updatedAt': null,
            });
          }
          return _json({
            'error': {
              'code': 'WATCHLIST_REVISION_EXHAUSTED',
              'message': 'x',
              'requestId': 'r',
            },
          }, 503);
        }),
        baseUri: Uri.parse('https://api.example'),
        accountId: _account,
        accessToken: () async =>
            PracticeAccessToken(accountId: _account, token: 'a.b.c'),
      ),
    );
    addTearDown(following.dispose);
    await _mount(tester, following: following);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stock-keep-apple')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('stock-keep-failure')))
          .data,
      'Your list is full. Remove one to keep another.',
    );
    expect(find.textContaining('WATCHLIST_'), findsNothing);
  });
}
