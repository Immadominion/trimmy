import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/onboarding/onboarding.dart';

void main() {
  test('controller requires each answer and emits one complete profile', () {
    final controller = OnboardingController();

    expect(controller.stage, OnboardingStage.welcome);
    controller.advance();
    expect(controller.stage, OnboardingStage.salHello);
    controller.advance();
    expect(controller.stage, OnboardingStage.goal);
    expect(controller.canContinue, isFalse);
    expect(controller.progress, 0);

    controller.selectGoal(OnboardingGoal.practice);
    expect(controller.progress, .2);
    expect(controller.canContinue, isTrue);
    controller.advance();
    expect(controller.stage, OnboardingStage.knowledge);

    controller.selectKnowledge(TradingKnowledge.basics);
    controller.advance();
    controller.selectPersona(TraderPersona.oracle);
    controller.advance();
    controller.selectDailyGoal(OnboardingDailyGoal.oneMission);
    controller.advance();
    expect(controller.stage, OnboardingStage.handle);

    controller.setHandle('@Market_Mira');
    expect(controller.handle, 'market_mira');
    expect(controller.isHandleValid, isTrue);
    expect(controller.progress, 1);
    controller.advance();
    expect(controller.stage, OnboardingStage.notifications);

    final result = controller.complete(
      OnboardingNotificationStatus.notRequested,
    );
    expect(controller.stage, OnboardingStage.completed);
    expect(
      result,
      const OnboardingResult(
        profile: OnboardingProfile(
          goal: OnboardingGoal.practice,
          knowledge: TradingKnowledge.basics,
          persona: TraderPersona.oracle,
          dailyGoal: OnboardingDailyGoal.oneMission,
          handle: 'market_mira',
        ),
        notificationStatus: OnboardingNotificationStatus.notRequested,
      ),
    );
    expect(result?.profile.toJson(), {
      'version': 2,
      'goal': 'practice',
      'knowledge': 'basics',
      'persona': 'oracle',
      'dailyGoal': 'one-mission',
      'handle': 'market_mira',
    });
    expect(
      controller.complete(OnboardingNotificationStatus.granted),
      same(result),
      reason: 'Completion must be idempotent.',
    );
    expect(controller.retryCompletion(), isTrue);
    expect(controller.stage, OnboardingStage.notifications);
    expect(controller.result, isNull);
    expect(controller.profile, result?.profile);
    expect(controller.retryCompletion(), isFalse);
  });

  test('handle rules are deterministic and concise', () {
    final controller = OnboardingController();

    controller.setHandle('ab');
    expect(controller.handleError, 'Use at least 3 characters.');
    controller.setHandle('1trader');
    expect(controller.handleError, 'Start with a letter.');
    controller.setHandle('trader-name');
    expect(controller.handle, 'trader-name');
    expect(controller.handleError, 'Use letters, numbers or underscores.');
    controller.setHandle('abcdefghijklmnopqrs');
    expect(controller.handleError, 'Use 18 characters or fewer.');
  });

  test('back keeps answers and returns through the same five questions', () {
    final controller = OnboardingController();
    controller
      ..advance()
      ..advance()
      ..selectGoal(OnboardingGoal.learn)
      ..advance()
      ..selectKnowledge(TradingKnowledge.nothing)
      ..advance();

    expect(controller.stage, OnboardingStage.persona);
    expect(controller.goBack(), isTrue);
    expect(controller.stage, OnboardingStage.knowledge);
    expect(controller.knowledge, TradingKnowledge.nothing);
    expect(controller.goBack(), isTrue);
    expect(controller.stage, OnboardingStage.goal);
    expect(controller.goal, OnboardingGoal.learn);
  });
}
