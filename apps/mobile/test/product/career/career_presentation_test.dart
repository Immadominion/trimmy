import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/career/career.dart';
import 'package:trimmy/product/career/career_activity_week.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/floor/floor_screen.dart';
import 'package:trimmy/product/profile/profile_screen.dart';

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var attempt = 0; attempt < 30; attempt++) {
    if (finder.hitTestable().evaluate().isNotEmpty) return;
    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pump();
  }
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('streak badge marks actual dates, never a grace gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(
          body: CareerStreakStrip(
            career: _career,
            week: const CareerActivityWeek(
              serverDate: '2026-09-24',
              weekStart: '2026-09-21',
              activeDates: {'2026-09-21', '2026-09-24'},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('streak-active-day')), findsNWidgets(2));
    expect(find.bySemanticsLabel('2026-09-22, no activity'), findsOneWidget);
    expect(find.bySemanticsLabel('2026-09-25, upcoming'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('working week owns Career and the header opens real progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FloorScreen(
          signedIn: false,
          onSignIn: () {},
          onOpenMarket: () {},
          career: _career,
          dailyDesk: const Center(child: Text('The working week')),
        ),
      ),
    );
    expect(find.text('The working week'), findsOneWidget);
    expect(find.byKey(const ValueKey('career-rank-card')), findsNothing);
    expect(find.byKey(const ValueKey('floor-mission-path')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('career-open-progress')));
    await tester.pumpAndSettle();
    expect(find.text('Your progress'), findsOneWidget);
    expect(find.byKey(const ValueKey('career-rank-card')), findsOneWidget);
    expect(find.text('40 Trims'), findsOneWidget);
    await tester.tap(find.byTooltip('Close progress'));
    await tester.pumpAndSettle();
    expect(find.text('The working week'), findsOneWidget);
    expect(find.byKey(const ValueKey('career-rank-card')), findsNothing);
  });

  testWidgets('Floor renders only server-owned Career totals', (tester) async {
    var openedMarket = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FloorScreen(
          signedIn: false,
          onSignIn: () {},
          onOpenMarket: () => openedMarket++,
          career: _career,
        ),
      ),
    );

    expect(find.text('Rookie'), findsOneWidget);
    expect(find.text('40 Trims'), findsOneWidget);
    expect(find.text('260 to Analyst'), findsOneWidget);
    expect(find.text('2 day streak'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('career-rank-card')),
        matching: find.byType(CareerStreakStrip),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('floor-rank-progress-label')))
          .style
          ?.color,
      ProductColor.ink,
    );
    expect(find.byKey(const ValueKey('floor-mission-path')), findsOneWidget);
    expect(find.text('Activities couldn’t load'), findsOneWidget);
    expect(find.textContaining('preparing your first mission'), findsNothing);

    await _reveal(tester, find.text('Browse stocks'));
    await tester.tap(find.text('Browse stocks'));
    expect(openedMarket, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Floor exposes a retry without inventing a Career record', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FloorScreen(
          signedIn: false,
          onSignIn: () {},
          onOpenMarket: () {},
          careerMessage: 'Your career is offline. Try again.',
          onRetryCareer: () => retried++,
        ),
      ),
    );

    expect(find.text('Career couldn’t load'), findsOneWidget);
    expect(find.text('Your career is offline. Try again.'), findsOneWidget);
    expect(find.textContaining('Trims to'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('Profile uses the same confirmed Career snapshot', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: ProfileScreen(
          handle: 'rookie',
          persona: 'The Wolf',
          signedIn: true,
          onSettings: () {},
          onSignIn: () {},
          career: _career,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-career-record')),
      250,
    );
    expect(find.byKey(const ValueKey('profile-career-record')), findsOneWidget);
    expect(find.text('40 Trims'), findsOneWidget);
    expect(find.text('30 Trims'), findsNothing);
    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('@rookie'), findsOneWidget);
    expect(find.text('Career points'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-career-pending')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Career record remains reachable at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: productTheme(),
          home: FloorScreen(
            signedIn: false,
            onSignIn: () {},
            onOpenMarket: () {},
            career: _career,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('Browse stocks'), 300);
    expect(find.text('Browse stocks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile uses singular day copy for a one-day streak', (
    tester,
  ) async {
    final oneDay = CareerSummary(
      revision: _career.revision,
      trims: _career.trims,
      rank: _career.rank,
      nextRank: _career.nextRank,
      streak: const CareerStreak(
        days: 1,
        status: CareerStreakStatus.active,
        lastActiveDate: '2026-09-20',
      ),
      careerStarted: _career.careerStarted,
      firstConfirmedBuy: _career.firstConfirmedBuy,
      serverDate: _career.serverDate,
      updatedAt: _career.updatedAt,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: ProfileScreen(
          handle: 'rookie',
          persona: 'The Wolf',
          signedIn: true,
          onSettings: () {},
          onSignIn: () {},
          career: oneDay,
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('1 day'), 250);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('1 days'), findsNothing);
  });

  testWidgets('Profile marks retained Career data stale and retries it', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: ProfileScreen(
          handle: 'rookie',
          persona: 'The Wolf',
          signedIn: true,
          onSettings: () {},
          onSignIn: () {},
          career: _career,
          careerMessage: 'Showing your last confirmed career record.',
          onRetryCareer: () => retries++,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-career-stale')),
      250,
    );
    expect(find.text('Progress couldn’t refresh.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    expect(find.byKey(const ValueKey('profile-career-record')), findsOneWidget);
  });

  testWidgets('Profile sends a reached threshold back to the Floor mission', (
    tester,
  ) async {
    var opened = 0;
    final threshold = CareerSummary(
      revision: _career.revision,
      trims: const CareerTrims(total: 300, today: 20, thisWeek: 60),
      rank: _career.rank,
      nextRank: const CareerNextRank(
        id: CareerRank.analyst,
        label: 'Analyst',
        threshold: 300,
        trimsRemaining: 0,
        promotionRequired: true,
      ),
      streak: _career.streak,
      careerStarted: _career.careerStarted,
      firstConfirmedBuy: _career.firstConfirmedBuy,
      serverDate: _career.serverDate,
      updatedAt: _career.updatedAt,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: ProfileScreen(
          handle: 'rookie',
          persona: 'The Wolf',
          signedIn: true,
          onSettings: () {},
          onSignIn: () {},
          career: threshold,
          onOpenCareer: () => opened++,
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('Your progress'), 250);
    await tester.tap(find.text('Your progress'));
    expect(opened, 1);
    expect(find.text('300 Trims'), findsOneWidget);
    expect(find.text('Promotion challenge ready.'), findsNothing);
  });

  testWidgets(
    'Floor renders the server-authored mission path and opens ready work',
    (tester) async {
      CareerMission? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          home: FloorScreen(
            signedIn: false,
            onSignIn: () {},
            onOpenMarket: () {},
            career: _career,
            missions: _missions,
            onOpenMission: (mission) => opened = mission,
          ),
        ),
      );

      await tester.scrollUntilVisible(find.text('Comment on your trade'), 260);
      expect(find.text('1 of 3 complete'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Waiting for a qualifying market day.'), findsNothing);
      final action = find.byKey(const ValueKey('mission-action-writeAReason'));
      await _reveal(tester, action);
      expect(action.hitTestable(), findsOneWidget);
      await tester.tap(action.hitTestable());
      expect(opened?.id, CareerMissionId.writeAReason);
    },
  );

  testWidgets('Floor keeps stale missions visible with an explicit retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FloorScreen(
          signedIn: false,
          onSignIn: () {},
          onOpenMarket: () {},
          career: _career,
          missions: _missions,
          missionsMessage: 'Showing your last confirmed missions.',
          onRetryMissions: () => retries++,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Showing your last confirmed missions.'),
      260,
    );
    expect(find.text('Comment on your trade'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mission-action-writeAReason')),
      findsNothing,
    );
    await _reveal(tester, find.text('Retry').last);
    await tester.tap(find.text('Retry').last);
    expect(retries, 1);
  });

  testWidgets('Floor does not expose destinations that are not live', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FloorScreen(
          signedIn: false,
          onSignIn: () {},
          onOpenMarket: () {},
          career: _career,
        ),
      ),
    );

    expect(find.text('Feed'), findsNothing);
    expect(find.text('League'), findsNothing);
    expect(find.byKey(const ValueKey('floor-career')), findsWidgets);
  });

  testWidgets('Floor withholds a mission board from another revision', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FloorScreen(
          signedIn: false,
          onSignIn: () {},
          onOpenMarket: () {},
          career: _career,
          missions: CareerMissionBoard(
            revision: _career.revision + 1,
            currentRank: CareerRank.rookie,
            missions: _missions.missions,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(find.text('Updating your progress…'), 260);
    expect(find.text('Comment on your trade'), findsNothing);
    expect(find.byKey(const ValueKey('mission-promote-analyst')), findsNothing);
  });

  testWidgets('matching server facts expose one promotion action', (
    tester,
  ) async {
    CareerMission? promoted;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FloorScreen(
          signedIn: false,
          onSignIn: () {},
          onOpenMarket: () {},
          career: _promotionReadyCareer,
          missions: _promotionReadyMissions,
          onPromote: (mission) => promoted = mission,
        ),
      ),
    );

    expect(find.text('Promotion ready for Analyst'), findsOneWidget);
    final action = find.byKey(const ValueKey('mission-promote-analyst'));
    await _reveal(tester, action);
    await tester.tap(action.hitTestable());
    expect(promoted?.id, CareerMissionId.holdThroughRedDay);
    expect(promoted?.promotesToRank, CareerRank.analyst);
  });

  testWidgets('promotion result repeats only receipt-backed facts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FloorScreen(
          signedIn: false,
          onSignIn: () {},
          onOpenMarket: () {},
          career: _career,
          promotion: _promotionReceipt,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('floor-promotion-result')),
      250,
    );
    expect(find.text('Analyst unlocked'), findsOneWidget);
    expect(find.text('+100 Trims'), findsOneWidget);
    expect(find.textContaining('Server confirmed'), findsNothing);
  });

  testWidgets('mission path has no overflow at 320 dp and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FloorScreen(
          signedIn: false,
          onSignIn: () {},
          onOpenMarket: () {},
          career: _career,
          missions: _missions,
          onOpenMission: (_) {},
        ),
      ),
    );
    final evidence = find.text('Hold through a red day');
    await _reveal(tester, evidence);

    expect(find.text('10,000'), findsNothing);
    expect(find.text('Paper limit'), findsNothing);
    expect(evidence, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _career = CareerSummary(
  revision: 5,
  trims: CareerTrims(total: 40, today: 10, thisWeek: 30),
  rank: CareerRankProgress(
    id: CareerRank.rookie,
    label: 'Rookie',
    paperLimit: '10000',
    threshold: 0,
  ),
  nextRank: CareerNextRank(
    id: CareerRank.analyst,
    label: 'Analyst',
    threshold: 300,
    trimsRemaining: 260,
    promotionRequired: false,
  ),
  streak: CareerStreak(
    days: 2,
    status: CareerStreakStatus.active,
    lastActiveDate: '2026-09-20',
  ),
  careerStarted: true,
  firstConfirmedBuy: null,
  serverDate: '2026-09-20',
  updatedAt: DateTime.utc(2026, 9, 20, 12),
);

final _missions = CareerMissionBoard(
  revision: 5,
  currentRank: CareerRank.rookie,
  missions: [
    CareerMission(
      id: CareerMissionId.firstPaperBuy,
      chapterRank: CareerRank.rookie,
      order: 1,
      kind: CareerMissionKind.action,
      title: 'Buy your first stock',
      instruction: 'Complete one paper buy.',
      trimsReward: 20,
      promotesToRank: null,
      status: CareerMissionStatus.complete,
      completedAt: DateTime.utc(2026, 9, 20, 9),
    ),
    const CareerMission(
      id: CareerMissionId.writeAReason,
      chapterRank: CareerRank.rookie,
      order: 2,
      kind: CareerMissionKind.action,
      title: 'Write your reason',
      instruction: 'Add a reason to a paper buy you still hold.',
      trimsReward: 20,
      promotesToRank: null,
      status: CareerMissionStatus.ready,
      completedAt: null,
    ),
    const CareerMission(
      id: CareerMissionId.holdThroughRedDay,
      chapterRank: CareerRank.rookie,
      order: 3,
      kind: CareerMissionKind.promotion,
      title: 'Hold through a red day',
      instruction: 'Hold a stock through a verified red Wall Street day.',
      trimsReward: 20,
      promotesToRank: CareerRank.analyst,
      status: CareerMissionStatus.locked,
      completedAt: null,
    ),
  ],
);

final _promotionReadyCareer = CareerSummary(
  revision: 6,
  trims: const CareerTrims(total: 320, today: 20, thisWeek: 60),
  rank: _career.rank,
  nextRank: const CareerNextRank(
    id: CareerRank.analyst,
    label: 'Analyst',
    threshold: 300,
    trimsRemaining: 0,
    promotionRequired: true,
  ),
  streak: _career.streak,
  careerStarted: true,
  firstConfirmedBuy: null,
  serverDate: '2026-09-20',
  updatedAt: DateTime.utc(2026, 9, 20, 12),
);

final _promotionReadyMissions = CareerMissionBoard(
  revision: 6,
  currentRank: CareerRank.rookie,
  missions: [
    for (final mission in _missions.missions)
      if (mission.id == CareerMissionId.holdThroughRedDay)
        CareerMission(
          id: mission.id,
          chapterRank: mission.chapterRank,
          order: mission.order,
          kind: mission.kind,
          title: mission.title,
          instruction: mission.instruction,
          trimsReward: mission.trimsReward,
          promotesToRank: mission.promotesToRank,
          status: CareerMissionStatus.complete,
          completedAt: DateTime.utc(2026, 9, 20, 11),
        )
      else if (mission.id == CareerMissionId.writeAReason)
        CareerMission(
          id: mission.id,
          chapterRank: mission.chapterRank,
          order: mission.order,
          kind: mission.kind,
          title: mission.title,
          instruction: mission.instruction,
          trimsReward: mission.trimsReward,
          promotesToRank: mission.promotesToRank,
          status: CareerMissionStatus.complete,
          completedAt: DateTime.utc(2026, 9, 20, 10),
        )
      else
        mission,
  ],
);

final _promotionReceipt = CareerPromotionReceipt(
  mutationId: '33333333-3333-4333-8333-333333333333',
  fromRank: CareerRank.rookie,
  toRank: CareerRank.analyst,
  careerRevision: 7,
  trimsAwarded: 100,
  promotedAt: DateTime.utc(2026, 9, 20, 12),
);
