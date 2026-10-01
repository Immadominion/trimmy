import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/markets/config.dart';
import 'package:trimmy/markets/stock_research_host.dart';
import 'package:trimmy/product/analytics/product_events.dart';
import 'package:trimmy/product/app/product_app.dart';
import 'package:trimmy/ui_review/review_feedback.dart';

class _MemoryStore implements ProductEventsStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  setUp(() async {
    await ReviewFeedback.shared.load();
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  testWidgets(
    'the app records its launch and each first-run step, once, from a new install',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final sent = <Map<String, dynamic>>[];
      var ids = 0;
      final usage = ProductEvents(
        origin: Uri.parse('https://api.example'),
        platform: 'ios',
        appVersion: '0.1.0+test',
        locale: () => 'en',
        store: _MemoryStore(),
        uuid: () =>
            '00000000-0000-4000-8000-${(++ids).toString().padLeft(12, '0')}',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sent.addAll(List<Map<String, dynamic>>.from(body['events'] as List));
          return http.Response('{}', 202);
        }),
      );
      await usage.load();
      await tester.pumpWidget(
        StockResearchHost(
          config: StockResearchConfig.parse(apiUrl: ''),
          child: TrimmyProductApp(
            preferences: preferences,
            account: null,
            accountConfigurationFailed: false,
            usage: usage,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Start my first day'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pick a company.'), findsOneWidget);
      // Events were recorded on the test's fake clock: send them on it too.
      var flushed = false;
      usage.flush().whenComplete(() => flushed = true);
      for (var i = 0; i < 20 && !flushed; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(flushed, isTrue);

      String describe(Map<String, dynamic> event) {
        final props = Map<String, dynamic>.from(event['props'] as Map);
        return '${event['name']}:${props['source'] ?? props['step'] ?? ''}';
      }

      final names = sent.map(describe).toList();
      expect(names.first, 'app_open:launch');
      expect(
        names.where((name) => name.startsWith('onboarding_step')).toList(),
        [
          'onboarding_step:welcome',
          'onboarding_step:note',
          'onboarding_step:first_trade',
        ],
      );
      for (final event in sent) {
        expect(event['platform'], 'ios');
        expect(event['locale'], 'en');
      }
      usage.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
