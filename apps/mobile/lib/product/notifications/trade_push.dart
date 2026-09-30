import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PushIdentity {
  const PushIdentity(this.id, this.accessToken);
  final String id;
  final Future<String> Function() accessToken;
}

abstract interface class TradePushDevice {
  String? get platform;
  Future<String?> token({required bool askPermission});
  Future<void> disable();
  void listen({
    required VoidCallback onToken,
    required void Function(Map<String, dynamic>, bool) onMessage,
  });
  void dispose();
}

/// Consent belongs to an account; the installation is shared across logins.
/// Every delayed request is checked again before it can bind a device.
class TradePushController extends ChangeNotifier {
  TradePushController({
    required this.preferences,
    required this.origin,
    required this.identity,
    required this.device,
    required this.onOpen,
    required this.onForeground,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    device.listen(onToken: () => unawaited(refresh()), onMessage: _message);
  }
  final SharedPreferences preferences;
  final Uri origin;
  final PushIdentity? Function() identity;
  final TradePushDevice device;
  final VoidCallback onOpen, onForeground;
  final http.Client _client;
  String? _account;
  bool _bound = false;
  int _generation = 0;
  bool _disposed = false, available = false, busy = false;
  Future<void> _tail = Future.value();
  String get _key => 'trimmy.tradePush.v1.${_account ?? 'guest'}';
  bool get enabled => _account != null && preferences.getBool(_key) == true;
  String? error;
  Map<String, dynamic>? _pendingOpen;

  void bind() {
    final next = identity()?.id;
    if (_bound && next == _account) return;
    _bound = true;
    _generation++;
    _account = next;
    available = false;
    _drainOpen();
    unawaited(
      _enqueue(() async {
        try {
          await device.disable();
        } catch (_) {
          /* Retry on resume. */
        }
        await _sync();
      }),
    );
  }

  Future<void> refresh() => _enqueue(_sync);
  Future<void> setEnabled(bool value) {
    final owner = _account;
    final generation = _generation;
    return _enqueue(() async {
      if (owner == null || !_current(owner, generation)) return;
      error = null;
      if (value) {
        final token = await device.token(askPermission: true);
        if (!_current(owner, generation)) return;
        if (token == null) {
          throw const FormatException(
            'Notifications are off in device settings.',
          );
        }
        try {
          await _register(owner, token);
        } catch (_) {
          await device.disable();
          rethrow;
        }
        if (_current(owner, generation)) {
          await preferences.setBool(_key, true);
        }
      } else {
        await preferences.setBool(_key, false);
        try {
          await _remove(owner);
        } finally {
          await device.disable();
        }
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _tail.then((_) async {
      if (_disposed || device.platform == null) return;
      busy = true;
      _notify();
      try {
        await action();
        error = null;
      } catch (e) {
        error = e is FormatException
            ? e.message
            : 'Couldn’t update notifications. Try again.';
      } finally {
        busy = false;
        _notify();
      }
    });
    _tail = next;
    return next;
  }

  bool _current(String owner, [int? generation]) =>
      !_disposed &&
      (generation == null || generation == _generation) &&
      _account == owner &&
      identity()?.id == owner;
  Future<void> _sync() async {
    final generation = _generation;
    final owner = _account;
    if (owner == null) {
      // A logout while offline may leave a native token awaiting revocation.
      await device.disable();
      return;
    }
    if (!_current(owner)) return;
    final response = await _client
        .get(origin.resolve('/v1/notifications/capabilities'))
        .timeout(const Duration(seconds: 10));
    if (!_current(owner, generation)) return;
    final data = response.statusCode == 200 ? jsonDecode(response.body) : null;
    available =
        data is Map &&
        data['tradePush'] == true &&
        data['platforms'] is List &&
        (data['platforms'] as List).contains(device.platform);
    if (!available) return;
    if (!enabled) {
      try {
        await _remove(owner);
      } finally {
        await device.disable();
      }
      return;
    }
    final token = await device.token(askPermission: false);
    if (!_current(owner, generation)) return;
    if (token == null) {
      await preferences.setBool(_key, false);
      try {
        await _remove(owner);
      } finally {
        await device.disable();
      }
      return;
    }
    await _register(owner, token);
  }

  Future<String> _installation() async {
    const key = 'trimmy.pushInstallation.v1';
    final previous = preferences.getString(key);
    if (previous != null) return previous;
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await preferences.setString(key, id);
    return id;
  }

  Future<void> _register(String owner, String token) => _request(owner, token);
  Future<void> _remove(String owner) => _request(owner, null);
  Future<void> _request(String owner, String? token) async {
    final generation = _generation;
    final installation = await _installation();
    if (!_current(owner, generation)) return;
    final access = await identity()!.accessToken();
    if (!_current(owner, generation)) return;
    final url = origin.resolve('/v1/notifications/devices/$installation');
    final headers = {
      'authorization': 'Bearer $access',
      'content-type': 'application/json',
    };
    final response =
        await (token == null
                ? _client.delete(url, headers: headers)
                : _client.put(
                    url,
                    headers: headers,
                    body: jsonEncode({
                      'token': token,
                      'platform': device.platform,
                    }),
                  ))
            .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const FormatException('Couldn’t update notifications. Try again.');
    }
    // A registration already in flight at logout must not survive token revocation.
    if (!_current(owner, generation) && token != null) await device.disable();
  }

  void _message(Map<String, dynamic> data, bool opened) {
    if (_disposed || data['kind'] != 'trade_update') return;
    if (opened && _account == null) {
      _pendingOpen = data;
      return;
    }
    if (data['accountId'] != _account ||
        identity()?.id != _account ||
        !enabled) {
      return;
    }
    if (opened) {
      onOpen();
    } else {
      onForeground();
    }
  }

  void _drainOpen() {
    final data = _pendingOpen;
    if (data == null || _account == null) return;
    _pendingOpen = null;
    _message(data, true);
  }

  /// Used before the account loses its bearer; consent is retained for next login.
  Future<void> beforeSignOut() => _enqueue(() async {
    final owner = _account;
    try {
      if (owner != null) await _remove(owner);
    } finally {
      await device.disable();
    }
  });
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    device.dispose();
    _client.close();
    super.dispose();
  }
}
