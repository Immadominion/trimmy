import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'trade_push.dart';

/// No token is requested before explicit consent. The server advertises which
/// platforms have completed provider setup and delivery validation.
class FirebaseTradePushDevice implements TradePushDevice {
  @override
  String? get platform => kIsWeb
      ? null
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          _ => null,
        };
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
    if (_disposed) return null;
    try {
      if (platform == 'ios') {
        // FlutterFire only registers with APNs while auto-init is enabled.
        // This path runs after account consent and OS permission, never at boot.
        await FirebaseMessaging.instance.setAutoInitEnabled(true);
        await _waitForAppleToken().timeout(const Duration(seconds: 10));
      }
      if (_disposed) return null;
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 10),
      );
      if (token == null || token.isEmpty) {
        throw const TradePushFailure(TradePushIssue.connectFailed);
      }
      return token;
    } catch (_) {
      // Failed enrollment must not leave automatic registration enabled.
      if (platform == 'ios') {
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
      }
      rethrow;
    }
  }

  Future<void> _waitForAppleToken() async {
    for (var attempt = 0; attempt < 20 && !_disposed; attempt++) {
      final token = await FirebaseMessaging.instance.getAPNSToken();
      if (token != null && token.isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw const TradePushFailure(TradePushIssue.connectFailed);
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
