import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/product/money/money_mode.dart';
import 'package:trimmy/product/money/wallet_stack.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/desk/desk_models.dart';

class TestAccount extends ChangeNotifier implements AccountController {
  @override
  AccountPhase phase = AccountPhase.active;
  @override
  String? accountId = 'account-a';
  int refreshes = 0;
  @override
  Future<void> refreshPortfolio() async {
    refreshes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'mode persists per account, guests cannot enter real mode, no cross-account inheritance',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final account = TestAccount();
      final mode = MoneyModeController(preferences, account);
      expect(mode.real, false);
      await mode.select(true);
      expect(mode.real, true);
      expect(account.refreshes, 1);
      account.accountId = 'account-b';
      account.notifyListeners();
      expect(mode.real, false);
      account.accountId = 'account-a';
      account.notifyListeners();
      expect(mode.real, true);
      account.phase = AccountPhase.guest;
      account.notifyListeners();
      await mode.select(true);
      expect(mode.real, false);
      mode.dispose();
      account.dispose();
    },
  );
  testWidgets('automatic balances pause in background and refresh on return', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final account = TestAccount();
    final mode = MoneyModeController(
      await SharedPreferences.getInstance(),
      account,
    );
    await mode.select(true);
    await tester.pump(const Duration(seconds: 25));
    expect(account.refreshes, 2);
    mode.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 50));
    expect(account.refreshes, 2);
    mode.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(account.refreshes, 3);
    await mode.select(false);
    await tester.pump(const Duration(seconds: 25));
    expect(account.refreshes, 3);
    mode.dispose();
    account.dispose();
  });
  testWidgets('new routes inherit the account mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final account = TestAccount();
    final mode = MoneyModeController(
      await SharedPreferences.getInstance(),
      account,
    );
    await mode.select(true);
    await tester.pumpWidget(
      MoneyModeScope(
        controller: mode,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    body: Text(
                      MoneyModeScope.isReal(context)
                          ? 'Real route'
                          : 'Paper route',
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Real route'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    mode.dispose();
    account.dispose();
  });
  testWidgets(
    'wallet swap finishes on real balance and leaves only active switch interactive',
    (tester) async {
      var real = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => WalletStack(
                real: real,
                paper: DeskSnapshot.newRookie(handle: ''),
                balance: r'$25.00',
                onSwitch: () => setState(() => real = !real),
                onBuy: () {},
                onAddMoney: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('money-mode-switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(real, true);
      expect(
        find.byKey(const ValueKey('money-mode-switch')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text(r'$25.00').hitTestable(), findsOneWidget);
      expect(find.text('Add money').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
