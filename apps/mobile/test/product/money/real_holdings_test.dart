import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/product/money/real_holdings.dart';
import 'package:trimmy/product/desk/holding_tile.dart';
import 'package:trimmy/product/design/product_theme.dart';
import '../../support/account_data_fixtures.dart' as fixtures;

class Reader implements AccountPortfolioReader {
  @override
  String get accountId => fixtures.account;
  @override
  Future<AccountContextSnapshot> readContext() async =>
      AccountContextSnapshot.fromEnvelope(
        fixtures.contextEnvelope(),
        expectedUserId: fixtures.account,
      );
  @override
  Future<AccountHoldingsSnapshot> readHoldings() async =>
      AccountHoldingsSnapshot.fromEnvelope(
        fixtures.holdingsEnvelope(),
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
}
