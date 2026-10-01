import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/product/analytics/product_events.dart';

class MemoryStore implements ProductEventsStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  late DateTime now;
  late int ids;
  late List<http.Request> requests;
  late List<int> statuses;
  late MemoryStore store;
  ProductEvents make() => ProductEvents(
    origin: Uri.parse('https://api.example'),
    platform: 'ios',
    appVersion: '0.1.0+4',
    locale: () => 'es-419',
    store: store,
    authorization: () async => 'Bearer token',
    now: () => now,
    uuid: () =>
        '00000000-0000-4000-8000-${(++ids).toString().padLeft(12, '0')}',
    client: MockClient((request) async {
      requests.add(request);
      final status = statuses.isEmpty ? 202 : statuses.removeAt(0);
      return http.Response(status == 204 ? '' : '{}', status);
    }),
  );
  List<Map<String, dynamic>> sent(int index) => List<Map<String, dynamic>>.from(
    (jsonDecode(requests[index].body) as Map)['events'] as List,
  );

  setUp(() {
    now = DateTime.utc(2026, 10, 1, 12);
    ids = 0;
    requests = [];
    statuses = [];
    store = MemoryStore();
  });

  test(
    'catalogued events batch, survive a restart and carry no account data',
    () async {
      statuses = [503];
      final events = make();
      await events.load();
      await events.track(ProductEvent.appOpen(AppOpenSource.launch));
      await events.once(ProductEvent.onboardingStep(OnboardingStep.firstTrade));
      await events.once(ProductEvent.onboardingStep(OnboardingStep.firstTrade));
      await events.once(
        ProductEvent.tabView(ProductTab.desk),
        perSession: true,
      );
      await events.once(
        ProductEvent.tabView(ProductTab.desk),
        perSession: true,
      );
      await events.flush();
      expect(requests, hasLength(1), reason: 'the server was down');
      events.close();

      final restarted = make();
      await restarted.load();
      await restarted.flush();
      expect(requests, hasLength(2));
      final batch = sent(1);
      expect(batch.map((e) => [e['name'], e['props']]).toList(), [
        [
          'app_open',
          {'source': 'launch'},
        ],
        [
          'onboarding_step',
          {'step': 'first_trade'},
        ],
        [
          'tab_view',
          {'tab': 'desk'},
        ],
      ]);
      for (final event in batch) {
        expect(event.keys.toSet(), {
          'id',
          'installId',
          'sessionId',
          'platform',
          'appVersion',
          'locale',
          'name',
          'props',
          'occurredAt',
        });
        expect(event['platform'], 'ios');
        expect(event['locale'], 'es-419');
        expect(event['installId'], batch.first['installId']);
        expect(event['occurredAt'], '2026-10-01T12:00:00.000Z');
      }
      expect(store.values['trimmy.events.queue.v1'], isNull);

      now = now.add(const Duration(minutes: 31));
      await restarted.resumed();
      await restarted.flush();
      final resumed = sent(2).single;
      expect(resumed['props'], {'source': 'resume'});
      expect(resumed['sessionId'], isNot(batch.first['sessionId']));
    },
  );

  test('switching off forgets everything and is remembered', () async {
    final events = make();
    await events.load();
    await events.track(ProductEvent.modeSwitch(real: true));
    await events.setEnabled(false);
    await events.track(ProductEvent.modeSwitch(real: false));
    await events.flush();
    expect(requests, isEmpty);
    expect(store.values['trimmy.events.queue.v1'], isNull);
    final again = make();
    await again.load();
    expect(again.enabled, isFalse);
  });

  test(
    'a refused batch is dropped and linking happens once per desk with a credential',
    () async {
      statuses = [400, 204];
      final events = make();
      await events.load();
      await events.track(ProductEvent.startupFailed(StartupStage.network));
      await events.flush();
      await events.flush();
      expect(requests, hasLength(1), reason: 'a 400 is never retried');
      await events.link('desk-1');
      await events.link('desk-1');
      expect(requests, hasLength(2));
      expect(requests[1].url.path, '/v1/events/link');
      expect(requests[1].headers['authorization'], 'Bearer token');
      expect(jsonDecode(requests[1].body), {
        'schemaVersion': 1,
        'installId': store.values['trimmy.install.v1'],
      });
    },
  );

  test('constructors refuse values outside the catalog', () {
    expect(
      () => ProductEvent.workdayOpen(ordinal: 0, resumed: false),
      throwsRangeError,
    );
    expect(() => ProductEvent.languageSet('de'), throwsArgumentError);
    expect(
      ProductEvent.reminderChoice(
        ReminderFrequency.occasional,
        PermissionOutcome.notAsked,
      ).props,
      {'frequency': 'occasional', 'permission': 'not_asked'},
    );
    expect(
      ProductEvents.instantForTest(DateTime.utc(2026, 10, 1, 9, 5, 7, 42, 123)),
      '2026-10-01T09:05:07.042Z',
    );
  });
}
