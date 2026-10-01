import '../../l10n/l10n.dart';

/// Optional preferences. The first practice trade does not require answers.
enum OnboardingGoal { learn, practice, trade, friends }

enum TradingKnowledge { nothing, basics, practice, traded, daily }

enum TraderPersona { wolf, oracle, shark }

enum OnboardingDailyGoal { showUp, oneMission, threeMissions }

/// The result of the operating system notification request.
enum OnboardingNotificationStatus { granted, denied, notRequested, unavailable }

extension OnboardingGoalCopy on OnboardingGoal {
  String get id => switch (this) {
    OnboardingGoal.learn => 'learn',
    OnboardingGoal.practice => 'practice',
    OnboardingGoal.trade => 'trade',
    OnboardingGoal.friends => 'beat-friends',
  };

  String label(AppLocalizations l10n) => switch (this) {
    OnboardingGoal.learn => l10n.onboardingGoalLearn,
    OnboardingGoal.practice => l10n.onboardingGoalPractice,
    OnboardingGoal.trade => l10n.onboardingGoalTrade,
    OnboardingGoal.friends => l10n.onboardingGoalFriends,
  };

  String description(AppLocalizations l10n) => switch (this) {
    OnboardingGoal.learn => l10n.onboardingGoalLearnDetail,
    OnboardingGoal.practice => l10n.onboardingGoalPracticeDetail,
    OnboardingGoal.trade => l10n.onboardingGoalTradeDetail,
    OnboardingGoal.friends => l10n.onboardingGoalFriendsDetail,
  };
}

extension TradingKnowledgeCopy on TradingKnowledge {
  String get id => switch (this) {
    TradingKnowledge.nothing => 'nothing',
    TradingKnowledge.basics => 'basics',
    TradingKnowledge.practice => 'practice',
    TradingKnowledge.traded => 'traded-before',
    TradingKnowledge.daily => 'daily-trader',
  };

  String label(AppLocalizations l10n) => switch (this) {
    TradingKnowledge.nothing => l10n.onboardingKnowledgeNothing,
    TradingKnowledge.basics => l10n.onboardingKnowledgeBasics,
    TradingKnowledge.practice => l10n.onboardingKnowledgePractised,
    TradingKnowledge.traded => l10n.onboardingKnowledgeTraded,
    TradingKnowledge.daily => l10n.onboardingKnowledgeDaily,
  };
}

extension TraderPersonaCopy on TraderPersona {
  String get id => switch (this) {
    TraderPersona.wolf => 'wolf',
    TraderPersona.oracle => 'oracle',
    TraderPersona.shark => 'shark',
  };

  /// The character's name. Wolf, Oracle and Shark are never translated.
  String label(AppLocalizations l10n) => switch (this) {
    TraderPersona.wolf => l10n.personaWolfName,
    TraderPersona.oracle => l10n.personaOracleName,
    TraderPersona.shark => l10n.personaSharkName,
  };

  String description(AppLocalizations l10n) => switch (this) {
    TraderPersona.wolf => l10n.personaWolfDetail,
    TraderPersona.oracle => l10n.personaOracleDetail,
    TraderPersona.shark => l10n.personaSharkDetail,
  };
}

extension OnboardingDailyGoalCopy on OnboardingDailyGoal {
  String get id => switch (this) {
    OnboardingDailyGoal.showUp => 'show-up',
    OnboardingDailyGoal.oneMission => 'one-mission',
    OnboardingDailyGoal.threeMissions => 'three-missions',
  };

  String label(AppLocalizations l10n) => switch (this) {
    OnboardingDailyGoal.showUp => l10n.onboardingDailyShowUp,
    OnboardingDailyGoal.oneMission => l10n.onboardingDailyOneMove,
    OnboardingDailyGoal.threeMissions => l10n.onboardingDailyThreeMoves,
  };

  String description(AppLocalizations l10n) => switch (this) {
    OnboardingDailyGoal.showUp => l10n.onboardingDailyShowUpDetail,
    OnboardingDailyGoal.oneMission => l10n.onboardingDailyOneMoveDetail,
    OnboardingDailyGoal.threeMissions => l10n.onboardingDailyThreeMovesDetail,
  };
}

/// Chosen preferences only. Null means the user has not made that choice.
final class OnboardingProfile {
  static const schemaVersion = 2;

  const OnboardingProfile({
    this.goal,
    this.knowledge,
    this.persona,
    this.dailyGoal,
    this.handle,
  });

  final OnboardingGoal? goal;
  final TradingKnowledge? knowledge;
  final TraderPersona? persona;
  final OnboardingDailyGoal? dailyGoal;

  /// Lowercase, without the leading @.
  final String? handle;

  Map<String, Object?> toJson() => {
    'version': schemaVersion,
    'goal': goal?.id,
    'knowledge': knowledge?.id,
    'persona': persona?.id,
    'dailyGoal': dailyGoal?.id,
    'handle': handle,
  };

  @override
  bool operator ==(Object other) =>
      other is OnboardingProfile &&
      other.goal == goal &&
      other.knowledge == knowledge &&
      other.persona == persona &&
      other.dailyGoal == dailyGoal &&
      other.handle == handle;

  @override
  int get hashCode => Object.hash(goal, knowledge, persona, dailyGoal, handle);
}

/// The boundary value emitted before the first paper trade opens.
final class OnboardingResult {
  const OnboardingResult({
    required this.profile,
    required this.notificationStatus,
  });

  final OnboardingProfile profile;
  final OnboardingNotificationStatus notificationStatus;

  @override
  bool operator ==(Object other) =>
      other is OnboardingResult &&
      other.profile == profile &&
      other.notificationStatus == notificationStatus;

  @override
  int get hashCode => Object.hash(profile, notificationStatus);
}

typedef RequestOnboardingNotificationPermission =
    Future<OnboardingNotificationStatus> Function();
