import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/account/wallet_setup.dart';
import 'package:trimmy/product/account/fund_wallet_sheet.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/ui_review/review_animated_splash.dart';
import '../../support/account_data_fixtures.dart' as fixtures;

class _Reader implements AccountPortfolioReader {
  bool fail = false;
  String? walletStatus;
  @override
  String get accountId => fixtures.account;
  @override
  Future<AccountContextSnapshot> readContext() async {
    if (fail) throw const AccountDataException(AccountDataFailure.unavailable);
    return AccountContextSnapshot.fromEnvelope(
      fixtures.contextEnvelope(
        embeddedWallet: walletStatus == null ? null : {'status': walletStatus},
      ),
      expectedUserId: fixtures.account,
    );
  }

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

class _Account extends ChangeNotifier implements AccountController {
  _Account(this.portfolioRepository);
  @override
  final AccountPortfolioRepository portfolioRepository;
  int refreshes = 0;
  bool setupThrows = false;
  @override
  AccountPhase get phase => AccountPhase.active;
  @override
  AccountPortfolioState get portfolioState => portfolioRepository.state;
  @override
  bool get canSetUpWallet => true;
  @override
  Future<void> refreshPortfolio() async {
    refreshes++;
    await portfolioRepository.refresh();
    notifyListeners();
  }

  @override
  Future<WalletSetupOutcome> setUpWallet() async {
    if (setupThrows) throw StateError('SDK unavailable');
    return WalletSetupOutcome.ready;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Reader reader;
  late AccountPortfolioRepository repository;
  late _Account account;
  setUp(() {
    reader = _Reader();
    repository = AccountPortfolioRepository(
      reader: reader,
      clock: () => DateTime.parse('2026-09-14T17:28:28Z'),
    );
    account = _Account(repository);
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(body: FundWalletSheet(account: account)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> clean(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    repository.dispose();
    account.dispose();
  }

  testWidgets(
    'failed wallet read offers retry and recovers to deposit address',
    (tester) async {
      reader.fail = true;
      await mount(tester);
      expect(
        find.byKey(const ValueKey('fund-wallet-unavailable')),
        findsOneWidget,
      );
      expect(find.byType(TrimmyLiquidMark), findsNothing);
      reader.fail = false;
      await tester.tap(find.byKey(const ValueKey('fund-wallet-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('wallet-deposit-qr')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fund-wallet-unavailable')),
        findsNothing,
      );
      expect(account.refreshes, 2);
      await clean(tester);
    },
  );

  testWidgets(
    'ambiguous wallet has an actionable state instead of an endless loader',
    (tester) async {
      reader.walletStatus = 'ambiguous';
      await mount(tester);
      expect(find.text('We couldn’t confirm your wallet.'), findsOneWidget);
      expect(find.byKey(const ValueKey('fund-wallet-retry')), findsOneWidget);
      expect(find.byType(TrimmyLiquidMark), findsNothing);
      expect(find.byKey(const ValueKey('wallet-deposit-qr')), findsNothing);
      await clean(tester);
    },
  );

  testWidgets('wallet creation exception releases the button for retry', (
    tester,
  ) async {
    reader.walletStatus = 'missing';
    account.setupThrows = true;
    await mount(tester);
    await tester.tap(find.text('Create wallet'));
    await tester.pump();
    expect(
      find.text('Couldn’t create your wallet. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Creating…'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create wallet'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await clean(tester);
  });

  testWidgets(
    'deposit polls pause in background and refresh immediately on resume',
    (tester) async {
      await mount(tester);
      final initial = account.refreshes;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 9));
      expect(account.refreshes, initial);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(account.refreshes, initial + 1);
      await clean(tester);
    },
  );
}
