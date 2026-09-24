import 'package:flutter/widgets.dart';

import 'config.dart';
import 'stock_research_controller.dart';
import 'validation.dart' show StockResearchException;

/// Makes the application-owned public market runtime reachable by descendants.
///
/// Depending on this scope rebuilds only when the controller publishes a state
/// change. Looking the controller up never starts a provider request.
final class StockResearchScope
    extends InheritedNotifier<StockResearchController> {
  const StockResearchScope({
    super.key,
    required StockResearchController controller,
    required this.configurationFailed,
    required super.child,
  }) : super(notifier: controller);

  final bool configurationFailed;

  StockResearchController get controller => notifier!;

  static StockResearchScope? maybeOf(
    BuildContext context, {
    bool listen = true,
  }) => listen
      ? context.dependOnInheritedWidgetOfExactType<StockResearchScope>()
      : context.getInheritedWidgetOfExactType<StockResearchScope>();

  static StockResearchScope of(BuildContext context, {bool listen = true}) {
    final scope = maybeOf(context, listen: listen);
    assert(scope != null, 'No StockResearchHost exists above this context.');
    return scope!;
  }

  @override
  bool updateShouldNotify(StockResearchScope oldWidget) =>
      configurationFailed != oldWidget.configurationFailed ||
      notifier != oldWidget.notifier;
}

/// Owns one stock research controller for the production app lifetime.
///
/// This host only forwards foreground lifecycle. It never searches, requests a
/// quote, selects a venue, or performs a transaction. A build without an API
/// origin receives a disabled controller and keeps the guest office usable.
final class StockResearchHost extends StatefulWidget {
  const StockResearchHost({
    super.key,
    required this.child,
    this.controller,
    this.config,
  });

  final Widget child;

  /// Injection boundary for tests or a higher-level native composition. An
  /// injected controller remains owned by its caller.
  final StockResearchController? controller;

  /// Optional test/native override. Production reads its compile-time config.
  final StockResearchConfig? config;

  @override
  State<StockResearchHost> createState() => _StockResearchHostState();
}

final class _StockResearchHostState extends State<StockResearchHost>
    with WidgetsBindingObserver {
  late final StockResearchController _controller;
  late final bool _ownsController;
  var _configurationFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final injected = widget.controller;
    _ownsController = injected == null;
    if (injected != null) {
      _controller = injected;
    } else {
      try {
        _controller = StockResearchController.create(
          config: widget.config ?? StockResearchConfig.fromEnvironment(),
        );
      } on StockResearchException {
        _configurationFailed = true;
        _controller = StockResearchController.create(
          config: StockResearchConfig.parse(apiUrl: ''),
        );
      } catch (_) {
        _configurationFailed = true;
        _controller = StockResearchController.create(
          config: StockResearchConfig.parse(apiUrl: ''),
        );
      }
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _controller.setForeground(
      lifecycle == null || lifecycle == AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _controller.setForeground(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StockResearchScope(
    controller: _controller,
    configurationFailed: _configurationFailed,
    child: widget.child,
  );
}
