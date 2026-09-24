import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/daily_desk/daily_desk.dart';
import 'package:trimmy/product/daily_desk/daily_desk_widgets.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/floor/floor_screen.dart';

final stories =
    (jsonDecode(File('../../content/desk-stories-v1.json').readAsStringSync())
            as Map)['stories']
        as List;
Map<String, dynamic> fixture({String? choice, String date = '2026-09-24'}) => {
  'date': date,
  'story': stories[3],
  'completedChoice': choice,
  'history': choice == null
      ? []
      : [
          {'date': date},
        ],
  'trimsEarned': choice == null ? 0 : 10,
};
DailyDeskController makeController(
  FutureOr<http.Response> Function(http.Request) callback,
) => DailyDeskController(
  DailyDeskRepository(
    Uri.parse('https://api.trimmy.test'),
    () async => const GuestPaperAuthorization('tg1_test'),
    client: MockClient((r) async => await callback(r)),
  ),
);
http.Response response(Map<String, dynamic> shift) => http.Response(
  jsonEncode({'shift': shift}),
  200,
  headers: {'content-type': 'application/json'},
);
Widget app(Widget child, {double scale = 1}) => MaterialApp(
  theme: productTheme(),
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      disableAnimations: true,
    ),
    child: child,
  ),
);
void main() {
  test('every authored story has three unique choices and outcomes', () {
    expect(stories.length, 7);
    for (final story in stories) {
      final parsed = DailyShift.fromJson({...fixture(), 'story': story});
      expect(parsed.choices.map((c) => c.id).toSet().length, 3);
      for (final c in parsed.choices) {
        expect(c.outcome, isNotEmpty);
        expect(c.takeaway, isNotEmpty);
      }
    }
  });
  test(
    'guest credential, exact choice, and confirmed completion survive a read',
    () async {
      bool complete = false;
      final controller = makeController((r) {
        expect(r.followRedirects, isFalse);
        expect(r.headers['authorization'], 'Guest tg1_test');
        if (r.method == 'POST') {
          expect(jsonDecode(r.body), {
            'date': '2026-09-24',
            'caseId': 'the-cheap-share',
            'choiceId': 'compare',
          });
          complete = true;
        }
        return response(fixture(choice: complete ? 'compare' : null));
      });
      await controller.refresh();
      await controller.complete(controller.shift!, 'compare');
      await controller.refresh();
      expect(controller.shift!.complete, isTrue);
      controller.dispose();
    },
  );
  test('an old read cannot undo a completed day', () async {
    final held = Completer<http.Response>();
    bool read = false;
    final controller = makeController((r) {
      if (r.method == 'GET' && !read) {
        read = true;
        return held.future;
      }
      return response(fixture(choice: 'compare'));
    });
    final pending = controller.refresh();
    final saving = controller.complete(
      DailyShift.fromJson(fixture()),
      'compare',
    );
    held.complete(response(fixture()));
    await pending;
    await saving;
    expect(controller.shift!.complete, isTrue);
    controller.dispose();
  });
  test(
    'read started during save cannot erase its newer confirmation',
    () async {
      final read = Completer<http.Response>(),
          write = Completer<http.Response>();
      final controller = makeController(
        (r) => r.method == 'POST' ? write.future : read.future,
      );
      controller.shift = DailyShift.fromJson(fixture());
      final saving = controller.complete(controller.shift!, 'compare');
      await Future<void>.delayed(Duration.zero);
      final refreshing = controller.refresh();
      write.complete(response(fixture(choice: 'compare')));
      await saving;
      read.complete(response(fixture()));
      await refreshing;
      expect(controller.shift!.complete, isTrue);
      controller.dispose();
    },
  );
  test('closed principal never accepts a delayed response', () async {
    final held = Completer<http.Response>();
    final controller = makeController((r) => held.future);
    final pending = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    held.complete(response(fixture(choice: 'compare')));
    await pending;
    expect(controller.shift, isNull);
  });
  testWidgets(
    'choice previews without writes; clock out confirms once and survives refresh',
    (tester) async {
      var writes = 0, completed = 0;
      final controller = makeController((r) {
        if (r.method == 'POST') writes++;
        return response(fixture(choice: 'compare'));
      });
      controller.shift = DailyShift.fromJson(fixture());
      await tester.pumpWidget(
        app(
          DailyDeskScreen(
            controller: controller,
            onCompleted: () async {
              completed++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-choice-compare')),
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-compare')));
      await tester.pump();
      expect(writes, 0);
      expect(find.text('Clock out'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Clock out'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(completed, 1);
      expect(find.text('See you tomorrow.'), findsOneWidget);
      expect(find.text('+10 Trims · Day recorded'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('failed save keeps the decision for a safe retry', (
    tester,
  ) async {
    var writes = 0;
    final controller = makeController((r) {
      writes++;
      return writes == 1
          ? http.Response('{"code":"DAILY_DESK_UNAVAILABLE"}', 503)
          : response(fixture(choice: 'compare'));
    });
    controller.shift = DailyShift.fromJson(fixture());
    await tester.pumpWidget(
      app(DailyDeskScreen(controller: controller, onCompleted: () async {})),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-compare')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-compare')));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Clock out'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t clock out. Try again.'), findsOneWidget);
    expect(controller.shift!.complete, isFalse);
    await tester.runAsync(() async {
      await tester.tap(find.text('Clock out'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(controller.shift!.complete, isTrue);
    expect(writes, 2);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'midnight conflict loads the new day without inventing a reward',
    (tester) async {
      final controller = makeController(
        (r) => r.method == 'POST'
            ? http.Response('{"code":"DAY_CHANGED"}', 409)
            : response(fixture(date: '2026-09-25')),
      );
      controller.shift = DailyShift.fromJson(fixture());
      await tester.pumpWidget(
        app(DailyDeskScreen(controller: controller, onCompleted: () async {})),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-choice-compare')),
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-compare')));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Clock out'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('A new day is ready.'), findsOneWidget);
      expect(controller.shift!.date, '2026-09-25');
      expect(controller.shift!.complete, isFalse);
      expect(find.text('+10 Trims · Day recorded'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('completed day leaves no redundant Home panel or spacer', (
    tester,
  ) async {
    final controller = makeController(
      (r) => response(fixture(choice: 'compare')),
    );
    controller.shift = DailyShift.fromJson(fixture(choice: 'compare'));
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Column(
            children: [
              DailyDeskEntry(controller: controller, onOpen: () {}),
              const Text('Holdings'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Clocked out for today'), findsNothing);
    expect(tester.getTopLeft(find.text('Holdings')).dy, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('entry, map and story fit 320px at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = makeController((r) => response(fixture()));
      controller.shift = DailyShift.fromJson(fixture());
      await tester.pumpWidget(
        app(
          Scaffold(
            body: DailyDeskEntry(controller: controller, onOpen: () {}),
          ),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        app(
          FloorScreen(
            signedIn: false,
            onSignIn: () {},
            onOpenMarket: () {},
            dailyDesk: DailyDeskJourney(controller: controller, onOpen: () {}),
          ),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('career-open-progress')).hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(
        app(
          DailyDeskScreen(controller: controller, onCompleted: () async {}),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-choice-compare')),
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-compare')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
