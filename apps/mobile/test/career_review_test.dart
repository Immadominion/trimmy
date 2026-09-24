import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/career_review.dart';
import 'package:trimmy/design_study/career_review_page.dart';
import 'package:trimmy/design_study/mission.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';
import 'package:trimmy/design_study/progress.dart';

final _now = DateTime.utc(2026, 9, 17, 12);

OfficeProgress _finished({
  Set<String> revised = const {},
  String branch = 'request-missing-costs',
  int count = 14,
}) {
  var state = OfficeProgress.empty();
  for (final id in practiceCatalogActivityIds.take(count)) {
    final entry = practiceCatalogById[id]!;
    state = state.startActivity(id).advance().advance();
    if (id == OfficeActivityIds.checkTheSample) {
      state = state
          .selectAnswerPart('amount', 'eight-of-ten')
          .selectAnswerPart('group', 'testers');
    } else if (id == OfficeActivityIds.prepareTheUpdate) {
      for (final part in ['dated-growth', 'lower-profit', 'trial-result']) {
        state = state.selectAnswerPart(part, 'included');
      }
    } else {
      final choice = id == OfficeActivityIds.reviewTeamUpdate
          ? branch
          : revised.contains(id)
          ? entry.choiceIds.firstWhere(
              (choice) => !entry.acceptedChoiceIds.contains(choice),
            )
          : entry.correctChoiceId;
      state = state.selectChoice(choice);
    }
    state = state.submitChoice(_now);
    if (state.active!.stage == 3) state = state.acceptCorrection(_now);
    state = state.closeActivity();
  }
  return state;
}

class _Store {
  _Store(OfficeProgress progress) : raw = jsonEncode(progress.toJson());
  String raw;
  int writes = 0;
  OfficeProgressRepository open() => OfficeProgressRepository(
    read: (key) => key == OfficeProgressRepository.saveKey ? raw : null,
    write: (_, value) async {
      writes++;
      raw = value;
      return true;
    },
    clock: () => _now.add(const Duration(days: 1)),
  );
}

void _phone(WidgetTester tester, {double width = 390, double scale = 1}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _office(
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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [('Manrope', 'manrope'), ('Rubik', 'rubik')]) {
      await (FontLoader(font.$1)..addFont(
            rootBundle.load('assets/fonts/${font.$2}/${font.$1}-Variable.ttf'),
          ))
          .load();
    }
  });

  test('review opens only after all fourteen acknowledged activities', () {
    for (var count = 0; count < 14; count++) {
      final review = OfficeCareerReview(_finished(count: count));
      expect(review.available, false);
      expect(review.folders, isEmpty);
      expect(review.practiceActivityIds, isEmpty);
    }
    final review = OfficeCareerReview(_finished());
    expect(review.available, true);
    expect(review.folders.map((folder) => folder.floor), [1, 2, 3, 4]);
  });

  test(
    'saved revisions take priority without turning first answers into a new grade',
    () {
      final progress = _finished(
        revised: {
          OfficeActivityIds.checkTheDate,
          OfficeActivityIds.prepareTheComparison,
        },
      );
      final before = jsonEncode(progress.toJson());
      final review = OfficeCareerReview(progress);
      expect(review.practiceActivityIds.take(2), [
        OfficeActivityIds.checkTheDate,
        OfficeActivityIds.prepareTheComparison,
      ]);
      final folder = review.folders[1];
      expect(folder.revised, true);
      final savedChoice =
          progress.completions[folder.activityId]!.selectedChoiceId;
      expect(
        folder.firstDecision,
        prepareTheComparisonActivity.choices
            .firstWhere((choice) => choice.id == savedChoice)
            .detail,
      );
      expect(
        folder.filedStatement,
        prepareTheComparisonActivity.correctedHeadline,
      );
      expect(jsonEncode(progress.toJson()), before);
    },
  );

  test('each Nia decision keeps its authored response in the ending', () {
    for (final branch in ['request-missing-costs', 'share-qualified-sales']) {
      final review = OfficeCareerReview(_finished(branch: branch));
      final folder = review.folders[2];
      expect(
        folder.firstDecision,
        reviewTeamUpdateActivity.choices
            .firstWhere((choice) => choice.id == branch)
            .detail,
      );
      expect(
        folder.colleagueReply,
        finishTeamUpdateActivity.branchVariants[branch]!.officeConsequence,
      );
      expect(
        folder.evidence,
        finishTeamUpdateActivity.branchVariants[branch]!.journalEvidence,
      );
    }
  });

  testWidgets(
    'four folders reveal saved decisions and evidence without writing progress',
    (tester) async {
      _phone(tester);
      final store = _Store(_finished());
      await tester.pumpWidget(
        MaterialApp(home: CareerReviewPage(repository: store.open())),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('review-floor-3')));
      expect(find.byKey(const ValueKey('review-nia-reply')), findsOneWidget);
      await _tap(tester, find.text('Your answer and the evidence'));
      expect(
        find.byKey(const ValueKey('review-first-answer-3')),
        findsOneWidget,
      );
      expect(
        find.text(
          finishTeamUpdateActivity
              .branchVariants['request-missing-costs']!
              .journalEvidence,
        ),
        findsOneWidget,
      );
      // Each folder keeps its own disclosure state, separate from page scroll.
      await _tap(tester, find.byKey(const ValueKey('review-floor-4')));
      expect(find.byKey(const ValueKey('review-first-answer-4')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('review-floor-3')));
      expect(
        find.byKey(const ValueKey('review-first-answer-3')),
        findsOneWidget,
      );
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'ending offers an actual replay and returns to the review without changing first history',
    (tester) async {
      _phone(tester);
      final store = _Store(_finished());
      final repository = store.open();
      final firstHistory = repository.state.toJson()['completions'];
      await _office(tester, repository);
      expect(find.text('Your first review'), findsOneWidget);
      await _tap(tester, find.text('Open your review'));
      await _tap(
        tester,
        find.byKey(const ValueKey('review-practice-prepare-the-comparison')),
      );
      expect(find.byType(ActivityStudy), findsOneWidget);
      expect(
        repository.state.active!.activityId,
        OfficeActivityIds.prepareTheComparison,
      );
      await _tap(tester, find.text('Open the figures'));
      await _tap(tester, find.text('Choose an answer'));
      await _tap(tester, find.text('Keep all three checks'));
      await _tap(tester, find.text('Submit answer'));
      await _tap(tester, find.text('Back to your office'));
      expect(find.text('Open your review'), findsOneWidget);
      expect(repository.state.completions, hasLength(14));
      expect(repository.state.toJson()['completions'], firstHistory);
      expect(store.open().state.toJson()['completions'], firstHistory);
    },
  );

  testWidgets(
    'Journal review resumes an interrupted replay instead of replacing it',
    (tester) async {
      _phone(tester);
      final saved = _finished()
          .startActivity(OfficeActivityIds.countTheFees)
          .advance();
      final store = _Store(saved);
      final repository = store.open();
      await _office(tester, repository);
      await _tap(tester, find.text('Journal'));
      await _tap(tester, find.byKey(const ValueKey('journal-career-review')));
      await _tap(tester, find.byKey(const ValueKey('review-replay-1')));
      expect(
        repository.state.active!.activityId,
        OfficeActivityIds.countTheFees,
      );
      expect(repository.state.active!.stage, 1);
      expect(find.byType(ActivityStudy), findsOneWidget);
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'review opens the real Portfolio tab without starting an activity',
    (tester) async {
      _phone(tester);
      final store = _Store(_finished());
      await _office(tester, store.open());
      await _tap(tester, find.text('Open your review'));
      await _tap(tester, find.byKey(const ValueKey('review-portfolio')));
      expect(find.byType(CareerReviewPage), findsNothing);
      expect(find.byType(ActivityStudy), findsNothing);
      expect(store.writes, 0);
      expect(find.text('Your portfolio'), findsOneWidget);
    },
  );

  testWidgets(
    'review folders and actions stay usable at 320px and 200 percent text',
    (tester) async {
      _phone(tester, width: 320, scale: 2);
      final store = _Store(_finished());
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: CareerReviewPage(repository: store.open()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('review-floor-4')));
      await _tap(tester, find.text('Your answer and the evidence'));
      await tester.ensureVisible(
        find.byKey(const ValueKey('review-first-answer-4')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('review-portfolio')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(store.writes, 0);
    },
  );
}
