import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/product/market/http_stock_facts_repository.dart';
import 'package:trimmy/product/market/public_holders.dart';
import 'package:trimmy/product/market/stock_facts.dart';

const mint = 'XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB';
const owner = 'FMmaHPDL47V1gXsfh9WjgAT7Er3dfDvarQubTU1Jxc1r';
Map<String, Object?> payload() => {
  'schemaVersion': 1,
  'mint': mint,
  'network': 'solana-mainnet',
  'scope': 'largest-20-token-accounts',
  'complete': false,
  'observedAt': '2026-09-24T10:00:00Z',
  'sampledAccounts': 2,
  'holders': [
    {
      'owner': owner,
      'primaryDomain': 'hello.sol',
      'amount': '123.456',
      'tokenAccounts': 2,
    },
  ],
};
void main() {
  testWidgets(
    'twenty holders stay in one bounded panel and scroll to the last',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PublicHoldersView(mint: mint, reader: _ManyReader()),
          ),
        ),
      );
      await tester.pump();
      final panel = find.byKey(const ValueKey('public-holders-panel'));
      expect(tester.getSize(panel).height, lessThan(400));
      expect(find.text('holder19.sol').hitTestable(), findsNothing);
      final list = find.byKey(const ValueKey('public-holders-scroll'));
      for (var i = 0; i < 6; i++) {
        await tester.drag(list, const Offset(0, -220));
        await tester.pump();
      }
      expect(find.text('holder19.sol').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'parses public owners and refuses misleading complete or duplicate data',
    () {
      final page = PublicHoldersPage.fromJson(payload());
      expect(page.holders.single.shortAddress, 'FMma…xc1r');
      expect(page.holders.single.primaryDomain, 'hello.sol');
      expect(
        () => PublicHoldersPage.fromJson({...payload(), 'complete': true}),
        throwsA(isA<StockFactsException>()),
      );
      final duplicate = payload();
      duplicate['holders'] = [
        for (var i = 0; i < 2; i++) (payload()['holders'] as List).single,
      ];
      expect(
        () => PublicHoldersPage.fromJson(duplicate),
        throwsA(isA<StockFactsException>()),
      );
    },
  );
  test(
    'requests public holder mint without user credentials and rejects wrong mint',
    () async {
      final repository = HttpStockFactsRepository(
        baseUri: Uri.parse('https://example.com'),
        transport: MockClient((request) async {
          expect(request.url.path, '/v1/markets/stocks/holders');
          expect(request.url.queryParameters['mint'], mint);
          expect(request.headers.containsKey('authorization'), false);
          return http.Response(
            jsonEncode(payload()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect((await repository.holders(mint)).holders.length, 1);
      await expectLater(
        repository.holders(owner),
        throwsA(isA<StockFactsException>()),
      );
    },
  );
  testWidgets(
    'shows domain plus abbreviated address and explicit sampled coverage',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PublicHoldersView(mint: mint, reader: _Reader()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('hello.sol'), findsOneWidget);
      expect(find.text('FMma…xc1r'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('public-holders-panel')),
        findsOneWidget,
      );
      expect(find.text('Largest accounts'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Reader implements PublicHoldersReader {
  @override
  Future<PublicHoldersPage> holders(String mint) async =>
      PublicHoldersPage.fromJson(payload());
}

class _ManyReader implements PublicHoldersReader {
  @override
  Future<PublicHoldersPage> holders(String mint) async => PublicHoldersPage(
    mint,
    DateTime.utc(2026, 9, 24),
    20,
    List.generate(20, (i) => PublicHolder(owner, 'holder$i.sol', '123')),
  );
}
