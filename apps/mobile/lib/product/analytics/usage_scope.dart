import 'dart:async';

import 'package:flutter/widgets.dart';

import 'product_events.dart';

/// The usage recorder for the screens below, or none. Only the production
/// entry creates one; tests and previews pass none, and every call through
/// [Usage] is then a no-op. Recording never breaks the product: failures are
/// swallowed here.
class UsageScope extends InheritedWidget {
  const UsageScope({super.key, required this.recorder, required super.child});

  final ProductEvents? recorder;

  static Usage of(BuildContext context) =>
      Usage(context.getInheritedWidgetOfExactType<UsageScope>()?.recorder);

  @override
  bool updateShouldNotify(UsageScope oldWidget) =>
      !identical(recorder, oldWidget.recorder);
}

/// The language the app is showing, for the events' locale. Updated by the
/// app as its language resolves or changes.
abstract final class UsageLocale {
  static String tag = 'en';
}

class Usage {
  const Usage(this.recorder);

  final ProductEvents? recorder;

  void track(ProductEvent event) => _quietly(() => recorder?.track(event));

  /// At most once per install (first-run steps), or once per session.
  void once(ProductEvent event, {bool perSession = false}) =>
      _quietly(() => recorder?.once(event, perSession: perSession));

  static void _quietly(Future<void>? Function() action) {
    try {
      final pending = action();
      if (pending != null) unawaited(pending.catchError((Object _) {}));
    } catch (_) {
      // Usage never breaks the product.
    }
  }
}
