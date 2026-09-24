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

  String get label => switch (this) {
    OnboardingGoal.learn => 'Learn',
    OnboardingGoal.practice => 'Practice',
    OnboardingGoal.trade => 'Trade with paper',
    OnboardingGoal.friends => 'Friends',
  };

  String get description => switch (this) {
    OnboardingGoal.learn => 'Start with the basics.',
    OnboardingGoal.practice => 'Make calls with paper.',
    OnboardingGoal.trade => 'Build confidence at live prices.',
    OnboardingGoal.friends => 'Leagues are not available yet.',
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

  String get label => switch (this) {
    TradingKnowledge.nothing => 'Nothing yet',
    TradingKnowledge.basics => 'I know the basics',
    TradingKnowledge.practice => 'I have practised',
    TradingKnowledge.traded => 'I have traded before',
    TradingKnowledge.daily => 'I trade every day',
  };
}

extension TraderPersonaCopy on TraderPersona {
  String get id => switch (this) {
    TraderPersona.wolf => 'wolf',
    TraderPersona.oracle => 'oracle',
    TraderPersona.shark => 'shark',
  };

  String get label => switch (this) {
    TraderPersona.wolf => 'The Wolf',
    TraderPersona.oracle => 'The Oracle',
    TraderPersona.shark => 'The Shark',
  };

  String get description => switch (this) {
    TraderPersona.wolf => 'Bold. Fast. Loves a big move.',
    TraderPersona.oracle => 'Patient. Reads before moving.',
    TraderPersona.shark => 'Calm when the crowd gets loud.',
  };
}

extension OnboardingDailyGoalCopy on OnboardingDailyGoal {
  String get id => switch (this) {
    OnboardingDailyGoal.showUp => 'show-up',
    OnboardingDailyGoal.oneMission => 'one-mission',
    OnboardingDailyGoal.threeMissions => 'three-missions',
  };

  String get label => switch (this) {
    OnboardingDailyGoal.showUp => 'Show up',
    OnboardingDailyGoal.oneMission => 'One move',
    OnboardingDailyGoal.threeMissions => 'Three moves',
  };

  String get description => switch (this) {
    OnboardingDailyGoal.showUp => 'Open Trimmy and check your desk.',
    OnboardingDailyGoal.oneMission => 'Make one focused paper trade.',
    OnboardingDailyGoal.threeMissions => 'Make three focused paper trades.',
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
