import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../account/account_controller.dart';

/// Account-scoped display/routing mode. It never grants transaction permission.
class MoneyModeController extends ChangeNotifier with WidgetsBindingObserver {
  MoneyModeController(this.preferences, this.account) {
    WidgetsBinding.instance.addObserver(this);
    account?.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 25), (_) => _refresh());
  }
  final SharedPreferences preferences;
  final AccountController? account;
  Timer? _timer;
  bool _foreground = true;
  bool _closed = false;
  bool _refreshing = false;
  String? get _key =>
      account?.phase == AccountPhase.active && account?.accountId != null
      ? 'trimmy.money-mode.v1.${account!.accountId}'
      : null;
  bool get real => _key != null && preferences.getBool(_key!) == true;
  Future<void> select(bool value) async {
    final key = _key;
    if (key == null) return;
    await preferences.setBool(key, value);
    if (_closed) return;
    notifyListeners();
    if (value) unawaited(_refresh());
  }

  void _changed() => notifyListeners();
  Future<void> _refresh() async {
    if (!_foreground || !real || _refreshing) return;
    _refreshing = true;
    try {
      await account?.refreshPortfolio();
    } catch (_) {
      /* Retain last observation. */
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refresh());
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    account?.removeListener(_changed);
    super.dispose();
  }
}

class MoneyModeScope extends InheritedNotifier<MoneyModeController> {
  const MoneyModeScope({
    super.key,
    required MoneyModeController controller,
    required super.child,
  }) : super(notifier: controller);
  static MoneyModeController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoneyModeScope>()?.notifier;
  static bool isReal(BuildContext context) => of(context)?.real ?? false;
}
