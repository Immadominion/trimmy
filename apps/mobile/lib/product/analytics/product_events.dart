import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// First-party usage events (API migration 0039).
///
/// Records a few catalogued moments with a random per-install id and a
/// session id. Never an account id, name, email, amount or free text: the
/// constructors below are the only shapes the API accepts. Events wait on the
/// phone (at most 200, at most 6 days) and are sent in small batches.
/// Turning "Share usage data" off stops recording and forgets anything unsent.
class ProductEvent {
  const ProductEvent._(this.name, this.props);
  final String name;
  final Map<String, Object> props;

  /// A new session: a cold start, back after 30 minutes away, or opened from
  /// a reminder or a push.
  factory ProductEvent.appOpen(AppOpenSource source) =>
      ProductEvent._('app_open', {'source': source.wire});
  factory ProductEvent.onboardingStep(OnboardingStep step) =>
      ProductEvent._('onboarding_step', {'step': step.wire});
  factory ProductEvent.onboardingSkip(OnboardingStep step) =>
      ProductEvent._('onboarding_skip', {'step': step.wire});
  factory ProductEvent.gateChoice(GateChoice choice) =>
      ProductEvent._('gate_choice', {'choice': choice.name});
  factory ProductEvent.reminderChoice(
    ReminderFrequency frequency,
    PermissionOutcome permission,
  ) => ProductEvent._('reminder_choice', {
    'frequency': frequency.name,
    'permission': permission.wire,
  });
  factory ProductEvent.pushOptIn({
    required bool enabled,
    required PermissionOutcome permission,
  }) => ProductEvent._('push_opt_in', {
    'enabled': enabled,
    'permission': permission.wire,
  });
  factory ProductEvent.tabView(ProductTab tab) =>
      ProductEvent._('tab_view', {'tab': tab.name});
  factory ProductEvent.workdayOpen({
    required int ordinal,
    required bool resumed,
  }) {
    if (ordinal < 1 || ordinal > 500) {
      throw RangeError.range(ordinal, 1, 500, 'ordinal');
    }
    return ProductEvent._('workday_open', {
      'ordinal': ordinal,
      'resumed': resumed,
    });
  }
  factory ProductEvent.workdayWaiting(WorkdayWaiting state) =>
      ProductEvent._('workday_waiting', {'state': state.name});
  factory ProductEvent.modeSwitch({required bool real}) =>
      ProductEvent._('mode_switch', {'to': real ? 'real' : 'practice'});
  factory ProductEvent.moneyAction(MoneyAction action) =>
      ProductEvent._('money_action', {'action': action.wire});
  factory ProductEvent.languageSet(String language) {
    const allowed = {'phone', 'en', 'es-419', 'pt-BR', 'fr'};
    if (!allowed.contains(language)) {
      throw ArgumentError.value(language, 'language');
    }
    return ProductEvent._('language_set', {'language': language});
  }
  factory ProductEvent.startupFailed(StartupStage stage) =>
      ProductEvent._('startup_failed', {'stage': stage.wire});
}

enum AppOpenSource {
  launch('launch'),
  resume('resume'),
  reminder('reminder'),
  push('push');

  const AppOpenSource(this.wire);
  final String wire;
}

enum OnboardingStep {
  welcome('welcome'),
  note('note'),
  firstTrade('first_trade'),
  review('review'),
  firstOrder('first_order'),
  celebration('celebration'),
  gate('gate'),
  reminders('reminders'),
  nextMove('next_move'),
  home('home');

  const OnboardingStep(this.wire);
  final String wire;
}

enum GateChoice { guest, email, google, apple, x }

enum ReminderFrequency { daily, occasional, off }

enum PermissionOutcome {
  granted('granted'),
  denied('denied'),
  notAsked('not_asked');

  const PermissionOutcome(this.wire);
  final String wire;
}

enum ProductTab { desk, market, career, profile }

enum WorkdayWaiting { tomorrow, closed, done }

enum MoneyAction {
  addMoneyOpen('add_money_open'),
  walletCreateStart('wallet_create_start'),
  sendOpen('send_open'),
  fastBuyOpen('fast_buy_open');

  const MoneyAction(this.wire);
  final String wire;
}

enum StartupStage {
  network('network'),
  guest('guest'),
  profile('profile'),
  signIn('sign_in'),
  unknown('unknown');

  const StartupStage(this.wire);
  final String wire;
}

/// Where unsent events, the install id and the choice to share live.
abstract interface class ProductEventsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesEventsStore implements ProductEventsStore {
  SharedPreferencesEventsStore(this._preferences);
  final SharedPreferences _preferences;
  @override
  Future<String?> read(String key) async => _preferences.getString(key);
  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
  @override
  Future<void> remove(String key) => _preferences.remove(key);
}

class ProductEvents {
  ProductEvents({
    required this.origin,
    required this.platform,
    required this.appVersion,
    required this.locale,
    required this.store,
    this.authorization,
    http.Client? client,
    DateTime Function()? now,
    String Function()? uuid,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _uuid = uuid ?? _randomUuid {
    if (platform != 'android' && platform != 'ios') {
      throw ArgumentError.value(platform, 'platform');
    }
    if (!RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_-]{0,39}$').hasMatch(appVersion)) {
      throw ArgumentError.value(appVersion, 'appVersion');
    }
    _sessionId = _uuid();
    _lastActivity = _now();
  }

  /// The app's version for every event. Release builds pass
  /// `--dart-define=TRIMMY_APP_VERSION=<version+build>`.
  static const buildVersion = String.fromEnvironment(
    'TRIMMY_APP_VERSION',
    defaultValue: 'dev',
  );

  final Uri origin;
  final String platform, appVersion;

  /// The language the app is showing, as a BCP 47 tag.
  final String Function() locale;

  /// The Authorization header for linking this install to the desk using it,
  /// or null when there is none.
  final Future<String?> Function()? authorization;
  final ProductEventsStore store;
  final http.Client _client;
  final DateTime Function() _now;
  final String Function() _uuid;

  static const _installKey = 'trimmy.install.v1',
      _queueKey = 'trimmy.events.queue.v1',
      _optOutKey = 'trimmy.events.optOut.v1',
      _onceKey = 'trimmy.events.once.v1';
  static const _maxQueue = 200, _batch = 50;
  static const _maxAge = Duration(days: 6),
      _sessionIdle = Duration(minutes: 30);
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  List<Map<String, Object>> _queue = [];
  late String _sessionId;
  late DateTime _lastActivity;
  String? _installId, _linkedTo;
  bool _enabled = true, _loaded = false, _closed = false;
  Future<void>? _sending;
  Timer? _timer;
  Duration _backoff = Duration.zero;
  final _seen = <String>{};
  Future<void> _work = Future<void>.value();

  bool get enabled => _enabled;

  /// Reads the saved choice, install id and unsent events. Call once.
  Future<void> load() => _serial(() async {
    if (_loaded) return;
    _loaded = true;
    _enabled = await store.read(_optOutKey) != 'true';
    final saved = await store.read(_installKey);
    _installId = saved != null && _uuidPattern.hasMatch(saved) ? saved : null;
    if (_installId == null) {
      _installId = _uuid();
      await store.write(_installKey, _installId!);
    }
    if (_enabled) _queue = _decodeQueue(await store.read(_queueKey));
  });

  /// Records an event. A new session starts after 30 minutes without one.
  Future<void> track(ProductEvent event) => _serial(() async {
    if (_loaded) await _trackNow(event);
  });

  /// Records an event at most once per install (first-run steps), or once per
  /// session with [perSession].
  Future<void> once(ProductEvent event, {bool perSession = false}) =>
      _serial(() async {
        if (!_loaded || !_enabled) return;
        final key = '${event.name}:${jsonEncode(event.props)}';
        if (perSession) {
          if (!_seen.add('$_sessionId:$key')) return;
        } else {
          final done = _decodeStrings(await store.read(_onceKey));
          if (done.contains(key)) return;
          done.add(key);
          await store.write(
            _onceKey,
            jsonEncode(done.skip(max(0, done.length - 100)).toList()),
          );
        }
        await _trackNow(event);
      });

  /// Back after 30 minutes away: a new session that starts with an app open.
  Future<void> resumed() async {
    if (_now().difference(_lastActivity) > _sessionIdle) {
      await track(ProductEvent.appOpen(AppOpenSource.resume));
    }
  }

  /// Turns recording on or off. Off forgets unsent events and first-run marks.
  Future<void> setEnabled(bool enabled) => _serial(() async {
    _enabled = enabled;
    await store.write(_optOutKey, enabled ? 'false' : 'true');
    if (!enabled) {
      _queue = [];
      _linkedTo = null;
      _seen.clear();
      _timer?.cancel();
      _timer = null;
      await store.remove(_queueKey);
      await store.remove(_onceKey);
    }
  });

  /// Ties this install to the desk using it, once per desk per launch.
  /// [using] gives that desk's Authorization header when it differs from the
  /// default.
  Future<void> link(String deskKey, {Future<String?> Function()? using}) async {
    final header = using ?? authorization;
    if (!_loaded || !_enabled || _linkedTo == deskKey || header == null) {
      return;
    }
    final String? value;
    try {
      value = await header();
    } catch (_) {
      return;
    }
    if (value == null) return;
    try {
      final response = await _client
          .post(
            origin.resolve('/v1/events/link'),
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              'authorization': value,
            },
            body: jsonEncode({'schemaVersion': 1, 'installId': _installId}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 204) _linkedTo = deskKey;
    } catch (_) {
      // Linking is retried on the next desk change or launch.
    }
  }

  /// Sends what is waiting, in batches. Never throws.
  Future<void> flush() => _sending ??= _send().whenComplete(() {
    _sending = null;
  });

  void close() {
    _closed = true;
    _timer?.cancel();
    _client.close();
  }

  Future<void> _send() async {
    await _serial(_dropStale);
    while (_enabled && !_closed && _queue.isNotEmpty) {
      final batch = _queue.take(_batch).toList();
      int status;
      try {
        final response = await _client
            .post(
              origin.resolve('/v1/events'),
              headers: {
                'content-type': 'application/json',
                'accept': 'application/json',
              },
              body: jsonEncode({'schemaVersion': 1, 'events': batch}),
            )
            .timeout(const Duration(seconds: 12));
        status = response.statusCode;
      } catch (_) {
        status = 599;
      }
      if (status == 202 || status == 400) {
        // 400 means this batch can never be accepted (an app out of step
        // with the catalog): drop it rather than retry forever.
        final sent = {for (final event in batch) event['id']};
        await _serial(() async {
          _queue.removeWhere((event) => sent.contains(event['id']));
          await _saveQueue();
        });
        _backoff = Duration.zero;
        continue;
      }
      _backoff = _backoff == Duration.zero
          ? const Duration(seconds: 30)
          : Duration(seconds: min(600, _backoff.inSeconds * 2));
      _arm(_backoff);
      return;
    }
  }

  Future<void> _trackNow(ProductEvent event) async {
    if (!_enabled || _closed) return;
    final now = _now();
    if (now.difference(_lastActivity) > _sessionIdle) _sessionId = _uuid();
    _lastActivity = now;
    _queue.add(_encode(event, now));
    if (_queue.length > _maxQueue) {
      _queue.removeRange(0, _queue.length - _maxQueue);
    }
    await _saveQueue();
    if (_queue.length >= 20) {
      unawaited(flush());
    } else {
      _arm(const Duration(seconds: 15));
    }
  }

  Map<String, Object> _encode(ProductEvent event, DateTime now) => {
    'id': _uuid(),
    'installId': _installId!,
    'sessionId': _sessionId,
    'platform': platform,
    'appVersion': appVersion,
    'locale': locale(),
    'name': event.name,
    'props': event.props,
    'occurredAt': _instant(now),
  };

  void _arm(Duration delay) {
    if (_timer?.isActive ?? false) return;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> _dropStale() async {
    final oldest = _now().subtract(_maxAge);
    final before = _queue.length;
    _queue.removeWhere((event) {
      final at = DateTime.tryParse('${event['occurredAt']}');
      return at == null || at.isBefore(oldest);
    });
    if (_queue.length != before) await _saveQueue();
  }

  Future<void> _saveQueue() => _queue.isEmpty
      ? store.remove(_queueKey)
      : store.write(_queueKey, jsonEncode(_queue));

  List<Map<String, Object>> _decodeQueue(String? raw) {
    try {
      final value = jsonDecode(raw ?? '[]');
      if (value is! List) return [];
      return [
        for (final item in value)
          if (item is Map &&
              item['id'] is String &&
              _uuidPattern.hasMatch(item['id'] as String) &&
              item['name'] is String)
            Map<String, Object>.from(item),
      ].skip(max(0, value.length - _maxQueue)).toList();
    } catch (_) {
      return [];
    }
  }

  List<String> _decodeStrings(String? raw) {
    try {
      final value = jsonDecode(raw ?? '[]');
      return value is List ? value.whereType<String>().toList() : [];
    } catch (_) {
      return [];
    }
  }

  /// Serializes storage work so a track never interleaves with a load.
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _work.then((_) => operation());
    _work = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static String _instant(DateTime at) {
    final utc = at.toUtc();
    final base = utc.toIso8601String().split('.').first.replaceAll('Z', '');
    return '$base.${utc.millisecond.toString().padLeft(3, '0')}Z';
  }

  @visibleForTesting
  static String instantForTest(DateTime at) => _instant(at);
}

String _randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
