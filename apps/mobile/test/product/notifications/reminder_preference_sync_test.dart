import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/notifications/reminder_preferences.dart';
import 'package:trimmy/product/notifications/reminder_preference_sync.dart';
import 'package:trimmy/product/onboarding/onboarding_models.dart';

const account = 'account-one';
const guest = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const permission = OnboardingNotificationStatus.granted;
Map<String, Object?> snapshot(
  int revision,
  String? frequency, {
  String? alias,
  bool? conflict,
}) => {
  'schemaVersion': 1,
  'revision': revision,
  'frequency': frequency,
  'claimedGuestId': alias,
  'conflict': ?conflict,
};
http.Response response(Map<String, Object?> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json'},
    );
Future<PaperAuthorization> auth() async =>
    const PrivyPaperAuthorization('test-token');

// Mirrors SharedPreferences' cache update before the platform write resolves.
class FailingPreferences extends Fake implements SharedPreferences {
  FailingPreferences(this.delegate);
  final SharedPreferences delegate;
  @override
  String? getString(String key) => delegate.getString(key);
  @override
  Future<bool> setString(String key, String value) async {
    await delegate.setString(key, value);
    return false;
  }

  @override
  Future<bool> remove(String key) => delegate.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  ReminderPreferenceSync service(
    FutureOr<http.Response> Function(http.Request) handle,
  ) => ReminderPreferenceSync(
    prefs,
    MockClient((r) async => handle(r)),
    Uri.parse('https://api.example.test'),
  );
  test(
    'restores an account choice on a clean installation without requesting OS permission',
    () async {
      final sync = service((r) {
        expect(r.method, 'GET');
        expect(r.headers['authorization'], 'Bearer test-token');
        expect(r.followRedirects, false);
        return response(snapshot(3, 'occasional'));
      });
      await sync.sync(account, auth, () => true);
      expect(
        ReminderPreferences.read(prefs, account),
        ReminderPreference.occasional,
      );
      expect(ReminderPreferences.stored(prefs, account)?.mutationId, isNull);
    },
  );
  test(
    'legacy guest choice migrates only with the server-proven claimed alias',
    () async {
      await prefs.setString('trimmy.reminders.v1.$guest', 'daily');
      var puts = 0;
      final sync = service((r) {
        if (r.method == 'GET') return response(snapshot(0, null, alias: guest));
        puts++;
        final data = jsonDecode(r.body);
        expect(data['frequency'], 'daily');
        expect(data['baseRevision'], 0);
        return response(snapshot(1, 'daily', alias: guest, conflict: false));
      });
      await sync.sync(account, auth, () => true);
      expect(puts, 1);
      expect(
        ReminderPreferences.read(prefs, account),
        ReminderPreference.daily,
      );
    },
  );
  test('existing account opt-out wins over a different guest choice', () async {
    await ReminderPreferences.save(
      prefs,
      guest,
      ReminderPreference.daily,
      permission,
    );
    var reads = 0;
    final sync = service((r) {
      expect(r.method, 'GET');
      reads++;
      return response(snapshot(2, 'off', alias: guest));
    });
    await sync.sync(account, auth, () => true);
    expect(reads, 1);
    expect(ReminderPreferences.read(prefs, account), ReminderPreference.off);
  });
  test('unclaimed guest choice cannot leak into a saved account', () async {
    await prefs.setString('trimmy.reminders.v1.$guest', 'daily');
    await service((r) {
      expect(r.method, 'GET');
      return response(snapshot(0, null));
    }).sync(account, auth, () => true);
    expect(ReminderPreferences.read(prefs, account), isNull);
  });
  test(
    'a stale opt-in adopts the newer choice without automatically rebasing',
    () async {
      await ReminderPreferences.save(
        prefs,
        account,
        ReminderPreference.daily,
        permission,
      );
      var puts = 0;
      final sync = service((r) {
        if (r.method == 'GET') return response(snapshot(2, 'off'));
        puts++;
        return response(snapshot(2, 'off', conflict: true), 409);
      });
      await expectLater(
        sync.sync(account, auth, () => true),
        throwsA(isA<ReminderPreferenceChanged>()),
      );
      expect(puts, 1);
      expect(ReminderPreferences.read(prefs, account), ReminderPreference.off);
      expect(ReminderPreferences.stored(prefs, account)?.mutationId, isNull);
    },
  );
  test(
    'an explicit offline opt-out may rebase once with a new mutation id',
    () async {
      await ReminderPreferences.save(
        prefs,
        account,
        ReminderPreference.off,
        permission,
      );
      final before = ReminderPreferences.stored(prefs, account)!;
      var puts = 0;
      final sync = service((r) {
        if (r.method == 'GET') return response(snapshot(4, 'daily'));
        puts++;
        final data = jsonDecode(r.body);
        if (puts == 1) {
          expect(data['mutationId'], before.mutationId);
          return response(snapshot(4, 'daily', conflict: true), 409);
        }
        expect(data['baseRevision'], 4);
        expect(data['mutationId'], isNot(before.mutationId));
        expect(data['frequency'], 'off');
        return response(snapshot(5, 'off', conflict: false));
      });
      await sync.sync(account, auth, () => true);
      expect(puts, 2);
      expect(ReminderPreferences.stored(prefs, account)?.revision, 5);
    },
  );
  test('a second opt-out conflict stays pending instead of looping', () async {
    await ReminderPreferences.save(
      prefs,
      account,
      ReminderPreference.off,
      permission,
    );
    var puts = 0;
    final sync = service((r) {
      if (r.method == 'GET') return response(snapshot(4, 'daily'));
      puts++;
      return response(snapshot(4 + puts, 'daily', conflict: true), 409);
    });
    await expectLater(sync.sync(account, auth, () => true), throwsStateError);
    expect(puts, 2);
    expect(ReminderPreferences.stored(prefs, account)?.mutationId, isNotNull);
    expect(ReminderPreferences.read(prefs, account), ReminderPreference.off);
  });
  test(
    'lost acknowledgement retries the same mutation and accepts the latest server choice',
    () async {
      await ReminderPreferences.save(
        prefs,
        account,
        ReminderPreference.daily,
        permission,
      );
      final before = ReminderPreferences.stored(prefs, account)!;
      var fail = true;
      final sync = service((r) {
        if (r.method == 'GET') {
          return response(snapshot(fail ? 0 : 2, fail ? null : 'off'));
        }
        expect(jsonDecode(r.body)['mutationId'], before.mutationId);
        if (fail) throw Exception('offline');
        return response(snapshot(2, 'off', conflict: false));
      });
      await expectLater(sync.sync(account, auth, () => true), throwsException);
      await ReminderPreferences.save(
        prefs,
        account,
        ReminderPreference.daily,
        permission,
      );
      expect(
        ReminderPreferences.stored(prefs, account)?.mutationId,
        before.mutationId,
      );
      fail = false;
      await sync.sync(account, auth, () => true);
      expect(ReminderPreferences.read(prefs, account), ReminderPreference.off);
    },
  );
  test('an account switch discards a delayed response', () async {
    final result = Completer<http.Response>();
    var current = true;
    final sync = service((r) => result.future);
    final pending = sync.sync(account, auth, () => current);
    final assertion = expectLater(pending, throwsStateError);
    current = false;
    result.complete(response(snapshot(1, 'daily')));
    await assertion;
    expect(ReminderPreferences.stored(prefs, account), isNull);
  });
  test(
    'a local choice made during a read is not overwritten; queued sync saves it',
    () async {
      final result = Completer<http.Response>();
      final started = Completer<void>();
      var reads = 0;
      final sync = service((r) {
        if (r.method == 'GET') {
          reads++;
          if (reads == 1) {
            started.complete();
            return result.future;
          }
          return response(snapshot(0, null));
        }
        expect(jsonDecode(r.body)['frequency'], 'off');
        return response(snapshot(1, 'off', conflict: false));
      });
      final first = sync.sync(account, auth, () => true);
      final assertion = expectLater(first, throwsStateError);
      await started.future;
      await ReminderPreferences.save(
        prefs,
        account,
        ReminderPreference.off,
        permission,
      );
      final next = sync.sync(account, auth, () => true);
      result.complete(response(snapshot(0, null)));
      await assertion;
      await next;
      expect(ReminderPreferences.stored(prefs, account)?.revision, 1);
    },
  );
  test('corrupt storage cannot crash the UI or revive legacy opt-in', () async {
    await prefs.setString('trimmy.reminders.v1.$account', 'daily');
    await prefs.setString('trimmy.reminders.v1.$account.sync', 'invalid');
    expect(ReminderPreferences.read(prefs, account), isNull);
    await expectLater(
      service(
        (r) => response(snapshot(1, 'off')),
      ).sync(account, auth, () => true),
      throwsFormatException,
    );
  });
  test(
    'an authoritative empty snapshot suppresses a legacy preference',
    () async {
      await prefs.setString('trimmy.reminders.v1.$account', 'daily');
      await ReminderPreferences.write(
        prefs,
        account,
        const ReminderState(null, 0, null, 'notRequested'),
      );
      expect(ReminderPreferences.read(prefs, account), isNull);
    },
  );
  for (final data in [
    {'schemaVersion': 1, 'revision': 1, 'frequency': 'daily', 'unknown': null},
    snapshot(0, 'daily'),
    snapshot(1, 'daily', alias: '------------------------------------'),
  ]) {
    test('rejects malformed response ${jsonEncode(data)}', () async {
      await expectLater(
        service((r) => response(data)).sync(account, auth, () => true),
        throwsStateError,
      );
      expect(ReminderPreferences.stored(prefs, account), isNull);
    });
  }
  test(
    'failed platform storage cannot pretend the new choice was saved',
    () async {
      await ReminderPreferences.write(
        prefs,
        account,
        const ReminderState('off', 2, null, 'granted'),
      );
      await expectLater(
        ReminderPreferences.save(
          FailingPreferences(prefs),
          account,
          ReminderPreference.daily,
          permission,
        ),
        throwsStateError,
      );
      expect(ReminderPreferences.read(prefs, account), ReminderPreference.off);
      expect(ReminderPreferences.stored(prefs, account)?.revision, 2);
    },
  );
  test('failed legacy migration persistence sends no consent write', () async {
    await prefs.setString('trimmy.reminders.v1.$account', 'daily');
    var requests = 0;
    final sync = ReminderPreferenceSync(
      FailingPreferences(prefs),
      MockClient((r) async {
        requests++;
        expect(r.method, 'GET');
        return response(snapshot(0, null));
      }),
      Uri.parse('https://api.example.test'),
    );
    await expectLater(sync.sync(account, auth, () => true), throwsStateError);
    expect(requests, 1);
    expect(ReminderPreferences.stored(prefs, account), isNull);
  });
  test(
    'explicit choice repairs damaged local storage without inventing a server revision',
    () async {
      await prefs.setString('trimmy.reminders.v1.$account.sync', 'invalid');
      await ReminderPreferences.save(
        prefs,
        account,
        ReminderPreference.off,
        permission,
      );
      expect(ReminderPreferences.read(prefs, account), ReminderPreference.off);
      expect(ReminderPreferences.stored(prefs, account)?.revision, 0);
      expect(ReminderPreferences.stored(prefs, account)?.mutationId, isNotNull);
    },
  );
  test(
    'redirects and oversized responses do not alter local consent',
    () async {
      for (final reply in [
        http.Response('', 302, headers: {'location': 'https://elsewhere.test'}),
        http.Response(
          'x' * 4097,
          200,
          headers: {'content-type': 'application/json'},
        ),
      ]) {
        await expectLater(
          service((r) => reply).sync(account, auth, () => true),
          throwsStateError,
        );
      }
      expect(ReminderPreferences.stored(prefs, account), isNull);
    },
  );
}
