import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/fast_buy_sheet.dart';
import 'package:trimmy/product/market/market_models.dart';
import '../../support/l10n_harness.dart';
import 'market_test_support.dart';

const _ondoMint = 'So11111111111111111111111111111111111111112';

FastBuyAsset _asset({
  String assetId = 'apple',
  String mint = testMint,
  String name = 'Apple xStock',
  String symbol = 'AAPLx',
  String issuer = 'xStocks',
  String? companyName = 'Apple',
}) => FastBuyAsset(
  assetId: assetId,
  mint: mint,
  name: name,
  symbol: symbol,
  issuer: issuer,
  companyName: companyName,
);

void main() {
  Future<void> mount(
    WidgetTester tester, {
    required Future<List<FastBuyAsset>> Function() load,
    Future<MarketCompany?> Function(FastBuyAsset)? open,
    FakeMarketSearchGateway? gateway,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FastBuySheet(
            gateway: gateway ?? FakeMarketSearchGateway(),
            companies: const [],
            loadTradeable: load,
            openTradeable: open ?? (_) async => null,
            orderBuilder: (company, back) =>
                Text('Order ${company.name} ${company.primaryVariant?.mint}'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('fast-buy-search')), text);
    await tester.pump();
  }

  testWidgets(
    'real fast buy lists only tradeable tokens and never searches discovery',
    (tester) async {
      final gateway = FakeMarketSearchGateway(
        results: {
          'hims': [testCompany(assetId: 'hims', name: 'Hims', symbol: 'HIMS')],
        },
      );
      await mount(tester, load: () async => [_asset()], gateway: gateway);
      expect(find.text('Apple'), findsOneWidget);
      expect(find.text('AAPLx · xStocks'), findsOneWidget);
      await search(tester, 'hims');
      await tester.pump(const Duration(milliseconds: 300));
      expect(gateway.queries, isEmpty);
      expect(find.text('Hims'), findsNothing);
      expect(find.text('No tradeable stock matches that.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      gateway.dispose();
    },
  );

  testWidgets('catalog connection failure offers a functioning retry', (
    tester,
  ) async {
    var calls = 0;
    Future<List<FastBuyAsset>> load() async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return [_asset()];
    }

    await mount(tester, load: load);
    expect(find.text('Trading could not connect.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Apple'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'search matches company name, symbol and issuer and shows the issuer',
    (tester) async {
      final rows = [
        _asset(),
        _asset(
          assetId: 'nvidia',
          mint: 'Xsc9qvGR1efVDFGLrVsmkzv3qi45LTBjeUKSPmx9qEh',
          name: 'NVIDIA xStock',
          symbol: 'NVDAx',
          companyName: 'NVIDIA',
        ),
        _asset(
          assetId: 'nvidia',
          mint: _ondoMint,
          name: 'NVIDIA (Ondo Tokenized)',
          symbol: 'NVDAon',
          issuer: 'Ondo',
          companyName: 'NVIDIA',
        ),
        // A token the catalog has not loaded still lists by its own name.
        for (var index = 0; index < 200; index++)
          _asset(
            assetId: 'company-$index',
            mint: 'mint-$index',
            name: 'Company $index Token',
            symbol: 'C${index}x',
            companyName: null,
          ),
      ];
      await mount(tester, load: () async => rows);
      await search(tester, 'nvidia');
      expect(find.text('NVDAx · xStocks'), findsOneWidget);
      expect(find.text('NVDAon · Ondo'), findsOneWidget);
      expect(find.text('AAPLx · xStocks'), findsNothing);

      await search(tester, r'$nvdaon');
      expect(find.text('NVDAon · Ondo'), findsOneWidget);
      expect(find.text('NVDAx · xStocks'), findsNothing);

      await search(tester, 'ondo');
      expect(find.text('NVDAon · Ondo'), findsOneWidget);
      expect(find.text('NVDAx · xStocks'), findsNothing);

      await search(tester, 'Company 199');
      expect(find.text('Company 199 Token'), findsOneWidget);
      expect(find.text('C199x · xStocks'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('long lists build lazily', (tester) async {
    final rows = [
      for (var index = 0; index < 600; index++)
        _asset(
          assetId: 'company-$index',
          mint: 'mint-$index',
          name: 'Company $index',
          symbol: 'C$index',
          companyName: null,
        ),
    ];
    await mount(tester, load: () async => rows);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(40));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'choosing a token opens its company with that exact token selected',
    (tester) async {
      final opened = <String>[];
      final lookup = Completer<MarketCompany?>();
      await mount(
        tester,
        load: () async => [_asset()],
        open: (asset) {
          opened.add(asset.mint);
          return lookup.future;
        },
      );
      await tester.tap(find.text('Apple'));
      await tester.pump();
      expect(opened, [testMint]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      lookup.complete(testCompany());
      await tester.pump();
      expect(find.text('Order Apple $testMint'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a token whose company cannot open stays in the list', (
    tester,
  ) async {
    await mount(tester, load: () async => [_asset()], open: (_) async => null);
    await tester.tap(find.text('Apple'));
    await tester.pump();
    expect(find.text('This stock couldn’t open. Try again.'), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('This stock couldn’t open. Try again.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('paper fast buy still searches the market', (tester) async {
    final apple = testCompany();
    final gateway = FakeMarketSearchGateway(
      results: {
        'apple': [apple],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FastBuySheet(
            gateway: gateway,
            companies: [apple],
            orderBuilder: (company, back) => Text('Paper ${company.name}'),
          ),
        ),
      ),
    );
    expect(find.text(r'$AAPL'), findsOneWidget);
    await search(tester, 'apple');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(gateway.queries, ['apple']);
    await tester.tap(find.text('Apple'));
    await tester.pump();
    expect(find.text('Paper Apple'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    gateway.dispose();
  });
  group('localized', () {
    Future<void> mountLocalized(
      WidgetTester tester, {
      required Locale locale,
      required Future<List<FastBuyAsset>> Function() load,
      double textScale = 1,
    }) async {
      await tester.pumpWidget(
        localizedTestApp(
          locale: locale,
          textScale: textScale,
          home: Scaffold(
            body: FastBuySheet(
              gateway: FakeMarketSearchGateway(),
              companies: const [],
              loadTradeable: load,
              openTradeable: (_) async => null,
              orderBuilder: (company, back) => Text(company.name),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('French title, hint, empty state and notice', (tester) async {
      await mountLocalized(
        tester,
        locale: const Locale('fr'),
        load: () async => [_asset()],
      );
      expect(find.text('Achat rapide'), findsOneWidget);
      expect(find.byTooltip('Fermer l’achat rapide'), findsOneWidget);
      expect(find.text('Cherche un nom ou un symbole'), findsOneWidget);
      await tester.tap(find.text('Apple'));
      await tester.pump();
      expect(
        find.text('Impossible d’ouvrir cette action. Réessaie.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await search(tester, 'zzz');
      expect(
        find.text('Aucune action disponible ne correspond à ta recherche.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final locale in longLocales) {
      testWidgets('connection failure fits at 320px and 130% text in $locale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mountLocalized(
          tester,
          locale: locale,
          textScale: 1.3,
          load: () async => throw StateError('offline'),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(TextButton), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });
}
