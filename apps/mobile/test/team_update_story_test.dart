import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';
import 'package:trimmy/design_study/progress.dart';

final _now = DateTime.utc(2026, 9, 14, 19, 0, 0, 123, 456);

OfficeProgress _complete(OfficeProgress state, String id) {
  state = state.startActivity(id).advance().advance();
  if (id == OfficeActivityIds.checkTheSample) {
    state = state
        .selectAnswerPart('amount', 'eight-of-ten')
        .selectAnswerPart('group', 'testers');
  } else if (id == OfficeActivityIds.prepareTheUpdate) {
    for (final fact in ['dated-growth', 'lower-profit', 'trial-result']) {
      state = state.selectAnswerPart(fact, 'included');
    }
  } else {
    state = state.selectChoice(practiceCatalogById[id]!.correctChoiceId);
  }
  return state.submitChoice(_now).closeActivity();
}

OfficeProgress _firstEight() {
  var state = OfficeProgress.empty();
  for (final id in practiceCatalogActivityIds.take(8)) {
    state = _complete(state, id);
  }
  return state;
}

class _Store {
  _Store(OfficeProgress state) : raw = jsonEncode(state.toJson());
  String raw;
  Completer<bool>? hold;
  Completer<void>? started;

  OfficeProgressRepository open() => OfficeProgressRepository(
    read: (key) => key == OfficeProgressRepository.saveKey ? raw : null,
    write: (_, value) async {
      if (hold case final gate?) {
        hold = null;
        started?.complete();
        if (!await gate.future) return false;
      }
      raw = value;
      return true;
    },
    clock: () => _now,
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: label);
}

Future<void> _mount(
  WidgetTester tester,
  OfficeProgressRepository repository,
) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    OfficeStudy(
      preferences: await SharedPreferences.getInstance(),
      progressRepository: repository,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'both responsible first choices complete directly and replay cannot replace the branch',
    () {
      for (final branch in ['share-qualified-sales', 'request-missing-costs']) {
        final before = _firstEight();
        final saved = before
            .startActivity(OfficeActivityIds.reviewTeamUpdate)
            .advance()
            .advance()
            .selectChoice(branch)
            .submitChoice(_now);
        expect(saved.active!.stage, 4);
        expect(saved.active!.corrected, isFalse);
        expect(
          saved
              .completions[OfficeActivityIds.reviewTeamUpdate]!
              .selectedChoiceId,
          branch,
        );
        final opposite = branch == 'share-qualified-sales'
            ? 'request-missing-costs'
            : 'share-qualified-sales';
        final replay = saved
            .closeActivity()
            .startActivity(OfficeActivityIds.reviewTeamUpdate)
            .advance()
            .advance()
            .selectChoice(opposite)
            .submitChoice(_now.add(const Duration(days: 1)));
        expect(replay.active!.stage, 4);
        expect(
          replay
              .completions[OfficeActivityIds.reviewTeamUpdate]!
              .selectedChoiceId,
          branch,
        );
        expect(replay.isUnlocked(OfficeActivityIds.readReturnedCosts), isTrue);
      }
    },
  );

  testWidgets(
    'request branch is stored before consequence, receives later figures and gets its own follow-up',
    (tester) async {
      _phone(tester);
      final store = _Store(_firstEight());
      final repository = store.open();
      await _mount(tester, repository);

      expect(find.text('Review the team’s update'), findsOneWidget);
      await _tap(tester, 'Start activity');
      await _tap(tester, 'Open the figures');
      expect(find.text('Current quarter costs'), findsOneWidget);
      expect(find.text('Not included'), findsOneWidget);
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Request the missing costs');

      final gate = Completer<bool>();
      store.hold = gate;
      store.started = Completer<void>();
      await tester.tap(find.text('Submit answer'));
      await store.started!.future;
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.text('Request sent.'), findsNothing);
      expect(
        repository.state.completions.containsKey(
          OfficeActivityIds.reviewTeamUpdate,
        ),
        isFalse,
      );
      gate.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Request sent.'), findsOneWidget);
      expect(
        repository
            .state
            .completions[OfficeActivityIds.reviewTeamUpdate]!
            .selectedChoiceId,
        'request-missing-costs',
      );

      await _tap(tester, 'Back to your office');
      expect(find.textContaining('I have your request'), findsOneWidget);
      expect(find.text('Read the returned costs'), findsOneWidget);
      await _tap(tester, 'Start activity');
      await _tap(tester, 'Open the figures');
      expect(find.text('Current quarter costs'), findsOneWidget);
      expect(find.text(r'$1,300'), findsOneWidget);
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Compare sales and costs');
      await _tap(tester, 'Submit answer');
      await _tap(tester, 'Back to your office');

      expect(find.text('Finish the team’s update'), findsOneWidget);
      await _tap(tester, 'Start activity');
      expect(
        find.textContaining('You requested the missing costs'),
        findsOneWidget,
      );
      await _tap(tester, 'Open the figures');
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Apply the returned figures');
      await _tap(tester, 'Submit answer');
      expect(find.text('Requested comparison completed.'), findsOneWidget);
      await _tap(tester, 'Back to your office');
      expect(
        find.textContaining('You waited for the evidence'),
        findsOneWidget,
      );
      expect(repository.state.completions, hasLength(11));
      expect(
        repository
            .state
            .completions[OfficeActivityIds.reviewTeamUpdate]!
            .selectedChoiceId,
        'request-missing-costs',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'qualified update returns to its saved draft before the shared rejoin',
    (tester) async {
      _phone(tester);
      var state = _firstEight();
      state = _complete(state, OfficeActivityIds.reviewTeamUpdate);
      state = _complete(state, OfficeActivityIds.readReturnedCosts);
      final repository = _Store(state).open();
      await _mount(tester, repository);

      expect(find.text('Finish the team’s update'), findsOneWidget);
      await _tap(tester, 'Start activity');
      expect(
        find.textContaining('You shared a qualified sales-only update'),
        findsOneWidget,
      );
      await _tap(tester, 'Open the figures');
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Apply the returned figures');
      await _tap(tester, 'Submit answer');
      expect(find.text('Qualified update revised.'), findsOneWidget);
      await _tap(tester, 'Back to your office');
      expect(
        find.textContaining('You kept the original limit'),
        findsOneWidget,
      );
      expect(repository.state.completions, hasLength(11));
      expect(
        repository
            .state
            .completions[OfficeActivityIds.reviewTeamUpdate]!
            .selectedChoiceId,
        'share-qualified-sales',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opposite replay is labelled as practice and returns to the first consequence',
    (tester) async {
      _phone(tester);
      var state = _firstEight()
          .startActivity(OfficeActivityIds.reviewTeamUpdate)
          .advance()
          .advance()
          .selectChoice('request-missing-costs')
          .submitChoice(_now)
          .closeActivity()
          .startActivity(OfficeActivityIds.reviewTeamUpdate);
      final repository = _Store(state).open();
      await _mount(tester, repository);

      await _tap(tester, 'Continue activity');
      await _tap(tester, 'Open the figures');
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Share a qualified update');
      await _tap(tester, 'Submit answer');

      expect(find.text('Replay complete.'), findsOneWidget);
      expect(find.textContaining('original request for costs'), findsOneWidget);
      await _tap(tester, 'Back to your office');
      expect(find.textContaining('I have your request'), findsOneWidget);
      expect(
        repository
            .state
            .completions[OfficeActivityIds.reviewTeamUpdate]!
            .selectedChoiceId,
        'request-missing-costs',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
