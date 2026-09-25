import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/workdays/workdays.dart';
import 'package:trimmy/product/workdays/workday_screen.dart';
import 'package:trimmy/product/workdays/career_world.dart';

Map<String, dynamic> fixture({
  int step = 0,
  int revision = 0,
  String draft = '',
}) {
  final source =
      jsonDecode(
            File('../../content/workdays/intern-v1.json').readAsStringSync(),
          )
          as Map;
  final assignments = List<Map<String, dynamic>>.from(
    source['assignments'] as List,
  );
  for (final item in assignments) {
    item['step'] = item['ordinal'] == 1 ? step : 0;
    item['revision'] = item['ordinal'] == 1 ? revision : 0;
    item['draft'] = item['ordinal'] == 1 ? draft : '';
    item['evidence']['count'] =
        (item['evidence']['requiredIds'] as List).length;
    item['file']['count'] = (item['file']['requiredIds'] as List).length;
  }
  return {'assignments': assignments};
}

http.Response response(Map<String, dynamic> journey) => http.Response(
  jsonEncode({'journey': journey}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
WorkdayController controller(
  FutureOr<http.Response> Function(http.Request) fn,
) => WorkdayController(
  WorkdayRepository(
    Uri.parse('https://trimmy.test'),
    () async => const GuestPaperAuthorization('test'),
    client: MockClient((request) async => await fn(request)),
  ),
);
Widget app(Widget child, {double scale = 1, double keyboard = 0}) =>
    MaterialApp(
      theme: productTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child,
      ),
    );
void main() {
  test('a conflicting draft refreshes before an explicit retry', () async {
    final revisions = <int>[];
    var reads = 0;
    final c = controller((request) {
      if (request.method == 'GET') {
        reads++;
        return response(fixture(step: 2, revision: 3, draft: 'Remote note'));
      }
      final body = jsonDecode(request.body) as Map;
      revisions.add(body['revision'] as int);
      if (revisions.length == 1) {
        return http.Response('{"code":"WORK_CHANGED"}', 409);
      }
      return response(fixture(step: 2, revision: 4, draft: body['draft']));
    })..journey = WorkJourney.fromJson(fixture(step: 2, revision: 2));
    addTearDown(c.dispose);

    await expectLater(
      c.draft('morning-brief', 'Local note'),
      throwsA(
        isA<WorkdayException>().having((e) => e.code, 'code', 'WORK_CHANGED'),
      ),
    );
    expect(reads, 1);
    expect(revisions, [2]);
    expect(c.journey!.current!.draft, 'Remote note');
    expect(c.journey!.current!.revision, 3);

    await c.draft('morning-brief', 'Local note');
    expect(revisions, [2, 3]);
    expect(c.journey!.current!.draft, 'Local note');
  });

  test(
    'a lost draft response recovers an already saved matching note',
    () async {
      var writes = 0;
      final c = controller((request) {
        if (request.method == 'GET') {
          return response(fixture(step: 2, revision: 3, draft: 'Saved note'));
        }
        writes++;
        return writes == 1
            ? http.Response('{"code":"WORK_UNAVAILABLE"}', 503)
            : http.Response('{"code":"WORK_CHANGED"}', 409);
      })..journey = WorkJourney.fromJson(fixture(step: 2, revision: 2));
      addTearDown(c.dispose);

      await expectLater(
        c.draft('morning-brief', 'Saved note'),
        throwsA(isA<WorkdayException>()),
      );
      await c.draft('morning-brief', 'Saved note');
      expect(c.journey!.current!.revision, 3);
      expect(c.journey!.current!.draft, 'Saved note');
      await c.draft('morning-brief', 'Saved note');
      expect(writes, 2);
    },
  );

  test(
    'a remote stage change cannot report an unsaved draft as saved',
    () async {
      var writes = 0;
      final c = controller((request) {
        if (request.method == 'GET') {
          return response(fixture(step: 3, revision: 3, draft: 'Filed note'));
        }
        writes++;
        return http.Response('{"code":"WORK_CHANGED"}', 409);
      })..journey = WorkJourney.fromJson(fixture(step: 2, revision: 2));
      addTearDown(c.dispose);
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          c.draft('morning-brief', 'Local note'),
          throwsA(
            isA<WorkdayException>().having(
              (e) => e.code,
              'code',
              'WORK_CHANGED',
            ),
          ),
        );
      }
      expect(writes, 1);
      expect(c.journey!.current!.draft, 'Filed note');
    },
  );

  test(
    'draft and submission serialize revisions; sign-out discards a late read',
    () async {
      int revision = 2;
      final seen = <int>[];
      final c = controller((request) async {
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map;
          seen.add(body['revision'] as int);
          revision++;
          return response(
            fixture(
              step: request.url.path.endsWith('draft') ? 2 : 3,
              revision: revision,
              draft: body['draft'] as String? ?? '',
            ),
          );
        }
        return response(fixture(step: 2, revision: revision));
      });
      await c.refresh();
      final original = c.journey!.current!;
      final draft = c.draft(original.id, 'note');
      final file = c.save(original, {
        'ids': ['fact-1', 'fact-2'],
      }, draft: 'note');
      await Future.wait([draft, file]);
      expect(seen, [2, 3]);
      c.dispose();
      final pending = Completer<http.Response>();
      final late = controller((_) => pending.future);
      final loading = late.refresh();
      await Future<void>.delayed(Duration.zero);
      late.dispose();
      pending.complete(response(fixture()));
      await loading;
      expect(late.journey, isNull);
    },
  );
  testWidgets(
    'assignment resumes at filing with the saved note and keyboard; small screen supports large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c =
          controller(
              (_) => response(
                fixture(step: 2, revision: 2, draft: 'Keep this note.'),
              ),
            )
            ..journey = WorkJourney.fromJson(
              fixture(step: 2, revision: 2, draft: 'Keep this note.'),
            );
      await tester.pumpWidget(
        app(
          WorkdayScreen(
            controller: c,
            assignmentId: 'morning-brief',
            onCompleted: () async {},
          ),
          scale: 2,
          keyboard: 260,
        ),
      );
      await tester.pump();
      expect(find.text('File update'), findsOneWidget);
      expect(find.text('Check the evidence'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  testWidgets(
    'an unsaved note offers a choice instead of trapping the player',
    (tester) async {
      final c = controller(
        (_) => http.Response('{"code":"WORK_UNAVAILABLE"}', 503),
      )..journey = WorkJourney.fromJson(fixture(step: 2, revision: 2));
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WorkdayScreen(
                    controller: c,
                    assignmentId: 'morning-brief',
                    onCompleted: () async {},
                  ),
                ),
              ),
              child: const Text('Open assignment'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open assignment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'An unsaved note.');
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Leave this note?'), findsOneWidget);
      await tester.tap(find.text('Keep writing'));
      await tester.pumpAndSettle();
      expect(find.text('An unsaved note.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  testWidgets('career scrolls past released days and has no review footer', (
    tester,
  ) async {
    final c = controller((_) => response(fixture()))
      ..journey = WorkJourney.fromJson(fixture());
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CareerWorld(controller: c, onOpen: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('START HERE'), findsOneWidget);
    expect(find.text('Review today'), findsNothing);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(6200);
    await tester.pump();
    expect(find.text('Coming later'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
