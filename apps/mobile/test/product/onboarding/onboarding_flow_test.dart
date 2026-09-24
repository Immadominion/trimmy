import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/product_components.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/onboarding/onboarding.dart';
import 'package:trimmy/ui_review/review_feedback.dart';
import 'package:trimmy/ui_review/welcome_review_screen.dart';

void _phone(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app({
  required CompleteOnboarding onCompleted,
  FutureOr<void> Function()? onHaveAccount,
  RequestOnboardingNotificationPermission? requestPermission,
  OnboardingController? controller,
}) => MaterialApp(
  theme: productTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: TrimmyOnboarding(
    controller: controller,
    onCompleted: onCompleted,
    onHaveAccount: onHaveAccount ?? () {},
    requestNotificationPermission: requestPermission,
  ),
);

Future<void> _tap(WidgetTester tester, String text) async {
  final finder = find.text(text);
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isNotEmpty) {
    final scrollable = scrollables.first;
    await tester.drag(scrollable, const Offset(0, 1200));
    await tester.pump();
    for (var attempt = 0; attempt < 24; attempt++) {
      if (finder.hitTestable().evaluate().isNotEmpty) break;
      await tester.drag(scrollable, const Offset(0, -160));
      await tester.pump();
    }
  }
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _reachNotifications(WidgetTester tester) async {
  await _tap(tester, 'Start my first day');
  await _tap(tester, 'Continue');
  await _tap(tester, 'Learn');
  await _tap(tester, 'Continue');
  await _tap(tester, 'I know the basics');
  await _tap(tester, 'Continue');
  await _tap(tester, 'The Oracle');
  await _tap(tester, 'Continue');
  await _tap(tester, 'One move');
  await _tap(tester, 'Continue');
  await tester.enterText(find.byKey(const Key('onboarding-handle')), 'Mira_7');
  await tester.pump();
  await _tap(tester, 'Continue');
}

void main() {
  setUp(() async {
    await ReviewFeedback.shared.load();
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  testWidgets('five committed answers produce the typed handoff', (
    tester,
  ) async {
    _phone(tester);
    OnboardingResult? completed;
    await tester.pumpWidget(_app(onCompleted: (value) => completed = value));

    expect(find.byType(WelcomeReviewScreen), findsOneWidget);
    await _tap(tester, 'Start my first day');
    expect(
      find.text('Five quick questions, then your first paper trade.'),
      findsOneWidget,
    );
    await _tap(tester, 'Continue');
    expect(find.text('Why are you here?'), findsOneWidget);
    expect(find.text('Beat my friends'), findsNothing);

    final primary = tester.widget<ProductButton>(
      find.byKey(const Key('onboarding-primary')),
    );
    expect(primary.onPressed, isNull);

    await _tap(tester, 'Learn');
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('goal-learn')))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    await _tap(tester, 'Continue');
    expect(find.text('How much do you know about trading?'), findsOneWidget);
    await _tap(tester, 'I know the basics');
    await _tap(tester, 'Continue');
    await _tap(tester, 'The Oracle');
    await _tap(tester, 'Continue');
    await _tap(tester, 'One move');
    await _tap(tester, 'Continue');
    expect(find.text('What should the floor call you?'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('onboarding-handle')),
      'Mira_7',
    );
    await tester.pump();
    await _tap(tester, 'Continue');
    expect(find.text('Alerts are almost ready.'), findsOneWidget);
    expect(find.text('Keep setting up your desk.'), findsOneWidget);
    await _tap(tester, 'Continue');

    expect(
      completed,
      const OnboardingResult(
        profile: OnboardingProfile(
          goal: OnboardingGoal.learn,
          knowledge: TradingKnowledge.basics,
          persona: TraderPersona.oracle,
          dailyGoal: OnboardingDailyGoal.oneMission,
          handle: 'mira_7',
        ),
        notificationStatus: OnboardingNotificationStatus.unavailable,
      ),
    );
    expect(find.text('Opening the market'), findsOneWidget);
  });

  testWidgets('notification request is called only after its explainer', (
    tester,
  ) async {
    _phone(tester);
    var requests = 0;
    OnboardingResult? completed;
    await tester.pumpWidget(
      _app(
        onCompleted: (value) => completed = value,
        requestPermission: () async {
          requests++;
          return OnboardingNotificationStatus.granted;
        },
      ),
    );

    await _reachNotifications(tester);
    expect(requests, 0);
    expect(
      find.text(
        "I'll ring you when Wall Street opens and closes. Trading here stays open.",
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Preview of the phone notification permission'),
      findsOneWidget,
    );
    await _tap(tester, 'Turn on alerts');
    expect(requests, 1);
    expect(completed?.notificationStatus, OnboardingNotificationStatus.granted);
  });

  testWidgets('failed durable save returns to a retryable final step', (
    tester,
  ) async {
    _phone(tester);
    var attempts = 0;
    OnboardingResult? completed;
    await tester.pumpWidget(
      _app(
        onCompleted: (value) async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
          completed = value;
        },
      ),
    );

    await _reachNotifications(tester);
    await _tap(tester, 'Continue');

    expect(attempts, 1);
    expect(find.text('Opening the market'), findsNothing);
    expect(find.text('Your setup was not saved. Try again.'), findsOneWidget);
    expect(find.text('Review my answers'), findsOneWidget);

    await _tap(tester, 'Continue');

    expect(attempts, 2);
    expect(completed, isNotNull);
    expect(find.text('Opening the market'), findsOneWidget);
  });

  testWidgets('account action remains a separate host boundary', (
    tester,
  ) async {
    _phone(tester);
    var accountCalls = 0;
    await tester.pumpWidget(
      _app(onCompleted: (_) {}, onHaveAccount: () => accountCalls++),
    );

    await _tap(tester, 'Sign in or create account');
    expect(accountCalls, 1);
    expect(find.byType(WelcomeReviewScreen), findsOneWidget);
  });

  testWidgets('returning from account restores the real onboarding action', (
    tester,
  ) async {
    _phone(tester);
    final accountClosed = Completer<void>();
    final controller = OnboardingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        controller: controller,
        onCompleted: (_) {},
        onHaveAccount: () => accountClosed.future,
      ),
    );

    await _tap(tester, 'Sign in or create account');
    await _tap(tester, 'Start my first day');
    expect(controller.stage, OnboardingStage.welcome);

    accountClosed.complete();
    await tester.pumpAndSettle();
    await _tap(tester, 'Start my first day');
    expect(controller.stage, OnboardingStage.salHello);
    expect(controller.profile, isNull);
  });

  testWidgets('small phone at 200 percent text can finish without overflow', (
    tester,
  ) async {
    _phone(tester, size: const Size(320, 568), scale: 2);
    OnboardingResult? completed;
    await tester.pumpWidget(_app(onCompleted: (value) => completed = value));

    await _reachNotifications(tester);
    expect(tester.takeException(), isNull);
    await _tap(tester, 'Continue');
    expect(completed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
