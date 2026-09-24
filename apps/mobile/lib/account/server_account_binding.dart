import 'dart:async';
import 'dart:convert';

import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/practice_sync/protocol.dart';

/// Public identity metadata only. This cache never grants network authority.
class ServerAccountBinding {
  const ServerAccountBinding._(this.accountId);
  final String accountId;
}

class ServerAccountBindingStore {
  ServerAccountBindingStore({
    required this._store,
    required Uri apiUri,
    required this.appId,
    bool allowLoopbackForTests = false,
  }) : apiOrigin = _origin(apiUri, allowLoopbackForTests) {
    if (RegExp(r'[A-Za-z0-9_-]{1,128}').stringMatch(appId) != appId) {
      throw const PracticeSyncException(
        'PRACTICE_BINDING_CONFIGURATION_INVALID',
      );
    }
  }

  static String _origin(Uri apiUri, bool allowLoopbackForTests) {
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(apiUri.host.toLowerCase());
    if (apiUri.userInfo.isNotEmpty ||
        apiUri.hasQuery ||
        apiUri.hasFragment ||
        (apiUri.path.isNotEmpty && apiUri.path != '/') ||
        apiUri.host.isEmpty ||
        apiUri.port < 1 ||
        apiUri.port > 65535 ||
        (apiUri.scheme != 'https' &&
            !(allowLoopbackForTests && loopback && apiUri.scheme == 'http'))) {
      throw const PracticeSyncException(
        'PRACTICE_BINDING_CONFIGURATION_INVALID',
      );
    }
    return apiUri.origin;
  }

  final PracticeSyncStore _store;
  final String apiOrigin;
  final String appId;
  Future<void> _queue = Future<void>.value();

  String keyFor(String subject) {
    if (RegExp(r'did:privy:[A-Za-z0-9]{1,128}').stringMatch(subject) !=
        subject) {
      throw const PracticeSyncException('PRACTICE_BINDING_SUBJECT_INVALID');
    }
    // Lossless, collision-free encoding includes every isolation dimension.
    final scope = base64Url.encode(
      utf8.encode(jsonEncode([apiOrigin, appId, subject])),
    );
    return 'trimmy.server-account-binding.v1.$scope';
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _current(bool Function() isCurrent) {
    if (!isCurrent()) {
      throw const PracticeSyncException('PRACTICE_BINDING_SESSION_CHANGED');
    }
  }

  Future<ServerAccountBinding?> _read(String subject) async {
    final key = keyFor(subject);
    String? raw;
    try {
      raw = await _store.read(key);
    } catch (_) {
      throw const PracticeSyncException('PRACTICE_BINDING_LOCAL_READ_FAILED');
    }
    if (raw == null) return null;
    try {
      if (utf8.encode(raw).length > 4096) throw const FormatException();
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) throw const FormatException();
      if (data['schemaVersion'] is int && data['schemaVersion'] != 1) {
        throw const PracticeSyncException('PRACTICE_BINDING_LOCAL_UNSUPPORTED');
      }
      if (data.length != 5 ||
          !const {
            'schemaVersion',
            'apiOrigin',
            'appId',
            'subject',
            'accountId',
          }.every(data.containsKey) ||
          data['schemaVersion'] is! int ||
          data['schemaVersion'] != 1 ||
          data['apiOrigin'] != apiOrigin ||
          data['appId'] != appId ||
          data['subject'] != subject) {
        throw const FormatException();
      }
      final accountId = normalizePracticeUuid(data['accountId']);
      if (accountId != data['accountId']) throw const FormatException();
      return ServerAccountBinding._(accountId);
    } on PracticeSyncException catch (error) {
      if (error.code == 'PRACTICE_BINDING_LOCAL_UNSUPPORTED') rethrow;
      throw const PracticeSyncException('PRACTICE_BINDING_LOCAL_CORRUPT');
    } catch (_) {
      throw const PracticeSyncException('PRACTICE_BINDING_LOCAL_CORRUPT');
    }
  }

  Future<ServerAccountBinding?> read(
    String subject, {
    required bool Function() isCurrent,
  }) => _locked(() async {
    _current(isCurrent);
    final binding = await _read(subject);
    _current(isCurrent);
    return binding;
  });

  /// Called only after the authenticated session endpoint returns this UUID.
  /// Existing bindings cannot be rebound, including after a future/corrupt read.
  Future<void> confirmVerified(
    String subject,
    String accountId, {
    required bool Function() isCurrent,
  }) => _locked(() async {
    _current(isCurrent);
    final id = normalizePracticeUuid(accountId);
    final existing = await _read(subject);
    _current(isCurrent);
    if (existing != null) {
      if (existing.accountId != id) {
        throw const PracticeSyncException('PRACTICE_BINDING_ACCOUNT_MISMATCH');
      }
      return;
    }
    final value = jsonEncode({
      'schemaVersion': 1,
      'apiOrigin': apiOrigin,
      'appId': appId,
      'subject': subject,
      'accountId': id,
    });
    try {
      if (!await _store.write(keyFor(subject), value)) {
        throw const PracticeSyncException('PRACTICE_BINDING_LOCAL_SAVE_FAILED');
      }
    } catch (_) {
      throw const PracticeSyncException('PRACTICE_BINDING_LOCAL_SAVE_FAILED');
    }
    _current(isCurrent);
  });
}
