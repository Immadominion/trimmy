import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'trade_push.dart';

/// No token is requested before explicit consent. iOS remains unavailable until
/// its APNs credentials and signed entitlement have been validated.
class FirebaseTradePushDevice implements TradePushDevice {
  @override
  String? get platform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'android'
      : null;
  bool _ready = false;
  bool _disposed = false;
  VoidCallback? _onToken;
  void Function(Map<String, dynamic>, bool)? _onMessage;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _initialize() async {
    if (_disposed || _ready || platform == null) return;
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    if (_disposed) return;
    _ready = true;
    _subscriptions.add(
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => _onToken?.call()),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen(
        (m) => _onMessage?.call(m.data, false),
      ),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _onMessage?.call(m.data, true),
      ),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _onMessage?.call(initial.data, true);
  }

  @override
  Future<String?> token({required bool askPermission}) async {
    await _initialize();
    if (!_ready) return null;
    final settings = askPermission
        ? await FirebaseMessaging.instance.requestPermission()
        : await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return null;
    }
    // Auto-init stays off: registration and rotation are managed by this owner.
    return FirebaseMessaging.instance.getToken().timeout(
      const Duration(seconds: 10),
    );
  }

  @override
  Future<void> disable() async {
    // Initialize to revoke a token retained by the native SDK across restarts.
    await _initialize();
    if (!_ready) return;
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await FirebaseMessaging.instance.deleteToken().timeout(
      const Duration(seconds: 10),
    );
  }

  @override
  void listen({
    required VoidCallback onToken,
    required void Function(Map<String, dynamic>, bool) onMessage,
  }) {
    _onToken = onToken;
    _onMessage = onMessage;
  }

  @override
  void dispose() {
    _disposed = true;
    _onToken = null;
    _onMessage = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
