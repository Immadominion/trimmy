import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/l10n/l10n.dart';
import 'package:trimmy/product/money/real_holdings.dart';
import 'package:trimmy/product/desk/holding_tile.dart';
import 'package:trimmy/product/design/product_theme.dart';
import '../../support/account_data_fixtures.dart' as fixtures;
import '../../support/l10n_harness.dart';

class Reader implements AccountPortfolioReader {
  Reader({this.envelope});
  final Map<String, Object?>? envelope;
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
    envelope ?? fixtures.holdingsEnvelope(),
    expectedUserId: fixtures.account,
  );
  @override
  void cancelPending() {}
  @override
  void close() {}
}

class Account extends ChangeNotifier implements AccountController {
  Account(this.portfolio);
  final AccountPortfolioRepository portfolio;
  @override
  AccountPortfolioState get portfolioState => portfolio.state;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('renders and opens every V2 holding with its own identity', (
    tester,
  ) async {
    final repository = AccountPortfolioRepository(
      reader: Reader(envelope: fixtures.holdingsEnvelopeV2()),
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    final account = Account(repository);
    addTearDown(account.dispose);
    await repository.refresh();
    WalletStockBalance? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(
          body: RealHoldings(
            account: account,
            onAddMoney: () {},
            onAsset: (holding) => selected = holding,
          ),
        ),
      ),
    );
    expect(find.byType(HoldingTile), findsNWidgets(2));
    expect(find.text('NVIDIA'), findsOneWidget);
    expect(find.text('2.46913578 NVDAx'), findsOneWidget);
    expect(find.textContaining('shares'), findsNothing);
    await tester.tap(find.text('NVIDIA'));
    expect(selected?.assetId, 'nvidia');
    expect(selected?.mint, fixtures.nvidiaMint);
    expect(tester.takeException(), isNull);
    repository.dispose();
  });

  testWidgets('empty V2 holdings explore the market without picking Apple', (
    tester,
  ) async {
    final envelope = fixtures.holdingsEnvelopeV2();
    ((envelope['holdings'] as Map)['balances'] as Map)['tokens'] = [];
    final repository = AccountPortfolioRepository(
      reader: Reader(envelope: envelope),
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    final account = Account(repository);
    addTearDown(account.dispose);
    await repository.refresh();
    var explored = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(
          body: RealHoldings(
            account: account,
            onAddMoney: () {},
            onExplore: () => explored = true,
          ),
        ),
      ),
    );
    expect(find.byType(HoldingTile), findsNothing);
    expect(find.text('No stocks yet'), findsOneWidget);
    await tester.tap(find.text('Explore stocks'));
    expect(explored, isTrue);
    repository.dispose();
  });

  testWidgets(
    'real holdings use the shared stock row and keep cash out of the list',
    (tester) async {
      final repository = AccountPortfolioRepository(
        reader: Reader(),
        clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
      );
      final account = Account(repository);
      addTearDown(account.dispose);
      await repository.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          home: Scaffold(
            body: RealHoldings(
              account: account,
              onAddMoney: () {},
              onApple: () {},
            ),
          ),
        ),
      );
      expect(find.byType(HoldingTile), findsOneWidget);
      expect(find.text('Apple'), findsOneWidget);
      expect(find.text('USDC'), findsNothing);
      expect(find.text('SOL'), findsNothing);
      expect(find.textContaining('shares'), findsNothing);
      expect(realCashBalance(account), isNotNull);
      expect(realSolBalance(account), isNotNull);
      expect(tester.takeException(), isNull);
      repository.dispose();
    },
  );

  testWidgets('rows use the trading name and grouped share amounts', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = AccountPortfolioRepository(
      reader: Reader(envelope: fixtures.holdingsEnvelopeV2()),
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    final account = Account(repository);
    addTearDown(account.dispose);
    await repository.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(
          body: RealHoldings(
            account: account,
            onAddMoney: () {},
            nameForAsset: (holding) =>
                holding.mint == fixtures.nvidiaMint ? 'NVIDIA xStock' : null,
          ),
        ),
      ),
    );
    expect(find.text('NVIDIA xStock'), findsOneWidget);
    expect(find.text('NVIDIA'), findsNothing);
    // Without a trading name the wallet's own name stays.
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('90,071,992.54741 AAPLx'), findsOneWidget);
    expect(find.text('2.46913578 NVDAx'), findsOneWidget);
    // No dollar value is invented for either token.
    expect(
      find.bySemanticsLabel(RegExp('Value unavailable')),
      findsNWidgets(2),
    );
    semantics.dispose();
    repository.dispose();
  });

  testWidgets('a priced holding shows shares times its own per-share price', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = AccountPortfolioRepository(
      reader: Reader(envelope: fixtures.holdingsEnvelopeV2()),
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    final account = Account(repository);
    addTearDown(account.dispose);
    await repository.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(
          body: RealHoldings(
            account: account,
            onAddMoney: () {},
            priceForHolding: (holding) =>
                holding.mint == fixtures.nvidiaMint ? 200 : null,
          ),
        ),
      ),
    );
    // 2.46913578 shares at $200 each; the display amount already carries the
    // token's 2x share multiplier, so raw units are never multiplied.
    expect(find.text(r'$493.83'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Value unavailable')), findsOneWidget);
    semantics.dispose();
    repository.dispose();
  });

  test('the total waits until every stock has a price', () async {
    final repository = AccountPortfolioRepository(
      reader: Reader(envelope: fixtures.holdingsEnvelopeV2()),
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    final account = Account(repository);
    addTearDown(account.dispose);
    addTearDown(repository.dispose);
    await repository.refresh();
    expect(
      realTotalBalance(
        account,
        (holding) => holding.mint == fixtures.nvidiaMint ? 200 : null,
      ),
      isNull,
    );
    final total = realTotalBalance(account, (holding) => 1)!;
    final cash = realCashBalance(account)!;
    expect(total.cash, cash);
    // 90,071,992.54741 + 2.46913578 shares at $1.
    expect(total.stocks, r'$90,071,995.02');
    expect(total.total, isNot(cash));
  });

  test('balances keep their exact cents in every language', () async {
    final repository = AccountPortfolioRepository(
      reader: Reader(envelope: fixtures.holdingsEnvelopeV2()),
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    final account = Account(repository);
    addTearDown(account.dispose);
    addTearDown(repository.dispose);
    await repository.refresh();
    final french = AppFormats.forLocale(const Locale('fr'));
    final brazil = AppFormats.forLocale(const Locale('pt', 'BR'));
    final english = realTotalBalance(account, (holding) => 1)!;
    final total = realTotalBalance(account, (holding) => 1, french)!;
    expect(english.stocks, r'$90,071,995.02');
    expect(total.stocks, '90\u202f071\u202f995,02\u00a0\$US');
    expect(
      realTotalBalance(account, (holding) => 1, brazil)!.stocks,
      'US\$\u00a090.071.995,02',
    );
    expect(realCashBalance(account, french), total.cash);
    expect(realUsd(1234.5, french), '1\u202f234,50\u00a0\$US');
    expect(realUsd(1234.5), r'$1,234.50');
  });

  testWidgets('the empty wallet reads in Portuguese', (tester) async {
    final envelope = fixtures.holdingsEnvelopeV2();
    ((envelope['holdings'] as Map)['balances'] as Map)['tokens'] = [];
    final repository = AccountPortfolioRepository(
      reader: Reader(envelope: envelope),
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    final account = Account(repository);
    addTearDown(account.dispose);
    await repository.refresh();
    await tester.pumpWidget(
      localizedTestApp(
        locale: const Locale('pt', 'BR'),
        home: Scaffold(
          body: RealHoldings(account: account, onAddMoney: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma ação ainda'), findsOneWidget);
    expect(find.text('Explorar ações'), findsOneWidget);
    repository.dispose();
  });
}
