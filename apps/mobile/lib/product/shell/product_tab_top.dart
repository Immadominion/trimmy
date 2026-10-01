import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/product_theme.dart';

/// Tapping the tab that is already open. The shell fires that tab's signal
/// and scrolls the tab's [PrimaryScrollController]; a page that keeps its own
/// scroll controller listens through [ProductTabTopListener] instead.
class ProductTabTop extends InheritedWidget {
  const ProductTabTop({super.key, required this.signal, required super.child});

  final Listenable signal;

  static Listenable? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProductTabTop>()?.signal;

  @override
  bool updateShouldNotify(ProductTabTop oldWidget) =>
      !identical(signal, oldWidget.signal);
}

/// For a page with its own scroll controller: [onTabTop] runs when the
/// person taps the tab the page is already on.
mixin ProductTabTopListener<T extends StatefulWidget> on State<T> {
  Listenable? _tabTop;

  void onTabTop();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final signal = ProductTabTop.maybeOf(context);
    if (identical(signal, _tabTop)) return;
    _tabTop?.removeListener(onTabTop);
    _tabTop = signal?..addListener(onTabTop);
  }

  @override
  void dispose() {
    _tabTop?.removeListener(onTabTop);
    super.dispose();
  }
}

/// Scrolls [controller] to [offset], at once when motion is reduced.
void productScrollTo(
  BuildContext context,
  ScrollController controller,
  double offset,
) {
  if (!controller.hasClients) return;
  final duration = productDuration(context, 420);
  if (duration == Duration.zero) {
    controller.jumpTo(offset);
  } else {
    unawaited(
      controller.animateTo(
        offset,
        duration: duration,
        curve: Curves.easeOutCubic,
      ),
    );
  }
}
