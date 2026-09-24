import 'package:flutter/foundation.dart';

import 'onboarding_models.dart';

enum OnboardingStage {
  welcome,
  salHello,
  goal,
  knowledge,
  persona,
  dailyGoal,
  handle,
  notifications,
  completed,
}

/// Owns onboarding state without storage, platform, or navigation side effects.
final class OnboardingController extends ChangeNotifier {
  OnboardingController();

  static final RegExp _handlePattern = RegExp(r'^[a-z][a-z0-9_]{2,17}$');

  OnboardingStage _stage = OnboardingStage.welcome;
  OnboardingGoal? _goal;
  TradingKnowledge? _knowledge;
  TraderPersona? _persona;
  OnboardingDailyGoal? _dailyGoal;
  String _handle = '';
  OnboardingResult? _result;

  OnboardingStage get stage => _stage;
  OnboardingGoal? get goal => _goal;
  TradingKnowledge? get knowledge => _knowledge;
  TraderPersona? get persona => _persona;
  OnboardingDailyGoal? get dailyGoal => _dailyGoal;
  String get handle => _handle;
  OnboardingResult? get result => _result;

  int get questionIndex => switch (_stage) {
    OnboardingStage.goal => 0,
    OnboardingStage.knowledge => 1,
    OnboardingStage.persona => 2,
    OnboardingStage.dailyGoal => 3,
    OnboardingStage.handle => 4,
    _ => -1,
  };

  int get answeredQuestionCount => [
    _goal,
    _knowledge,
    _persona,
    _dailyGoal,
    if (isHandleValid) _handle,
  ].where((answer) => answer != null).length;

  double get progress => answeredQuestionCount / 5;

  bool get isHandleValid => _handlePattern.hasMatch(_handle);

  String? get handleError {
    if (_handle.isEmpty) return null;
    if (_handle.length < 3) return 'Use at least 3 characters.';
    if (_handle.length > 18) return 'Use 18 characters or fewer.';
    if (!RegExp(r'^[a-z]').hasMatch(_handle)) {
      return 'Start with a letter.';
    }
    return 'Use letters, numbers or underscores.';
  }

  bool get canContinue => switch (_stage) {
    OnboardingStage.welcome || OnboardingStage.salHello => true,
    OnboardingStage.goal => _goal != null,
    OnboardingStage.knowledge => _knowledge != null,
    OnboardingStage.persona => _persona != null,
    OnboardingStage.dailyGoal => _dailyGoal != null,
    OnboardingStage.handle => isHandleValid,
    OnboardingStage.notifications || OnboardingStage.completed => false,
  };

  void selectGoal(OnboardingGoal value) =>
      _setValue(current: _goal, next: value, assign: () => _goal = value);

  void selectKnowledge(TradingKnowledge value) => _setValue(
    current: _knowledge,
    next: value,
    assign: () => _knowledge = value,
  );

  void selectPersona(TraderPersona value) =>
      _setValue(current: _persona, next: value, assign: () => _persona = value);

  void selectDailyGoal(OnboardingDailyGoal value) => _setValue(
    current: _dailyGoal,
    next: value,
    assign: () => _dailyGoal = value,
  );

  void setHandle(String value) {
    final next = value.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    if (_handle == next) return;
    _handle = next;
    notifyListeners();
  }

  void _setValue<T>({
    required T? current,
    required T next,
    required VoidCallback assign,
  }) {
    if (current == next) return;
    assign();
    notifyListeners();
  }

  void advance() {
    if (!canContinue) return;
    final next = switch (_stage) {
      OnboardingStage.welcome => OnboardingStage.salHello,
      OnboardingStage.salHello => OnboardingStage.goal,
      OnboardingStage.goal => OnboardingStage.knowledge,
      OnboardingStage.knowledge => OnboardingStage.persona,
      OnboardingStage.persona => OnboardingStage.dailyGoal,
      OnboardingStage.dailyGoal => OnboardingStage.handle,
      OnboardingStage.handle => OnboardingStage.notifications,
      OnboardingStage.notifications || OnboardingStage.completed => _stage,
    };
    if (next == _stage) return;
    _stage = next;
    notifyListeners();
  }

  bool goBack() {
    final previous = switch (_stage) {
      OnboardingStage.welcome || OnboardingStage.completed => null,
      OnboardingStage.salHello => OnboardingStage.welcome,
      OnboardingStage.goal => OnboardingStage.salHello,
      OnboardingStage.knowledge => OnboardingStage.goal,
      OnboardingStage.persona => OnboardingStage.knowledge,
      OnboardingStage.dailyGoal => OnboardingStage.persona,
      OnboardingStage.handle => OnboardingStage.dailyGoal,
      OnboardingStage.notifications => OnboardingStage.handle,
    };
    if (previous == null) return false;
    _stage = previous;
    notifyListeners();
    return true;
  }

  OnboardingProfile? get profile {
    if (_goal == null ||
        _knowledge == null ||
        _persona == null ||
        _dailyGoal == null ||
        !isHandleValid) {
      return null;
    }
    return OnboardingProfile(
      goal: _goal!,
      knowledge: _knowledge!,
      persona: _persona!,
      dailyGoal: _dailyGoal!,
      handle: _handle,
    );
  }

  OnboardingResult? complete(OnboardingNotificationStatus notificationStatus) {
    if (_stage != OnboardingStage.notifications) return _result;
    final completedProfile = profile;
    if (completedProfile == null) return null;
    _result = OnboardingResult(
      profile: completedProfile,
      notificationStatus: notificationStatus,
    );
    _stage = OnboardingStage.completed;
    notifyListeners();
    return _result;
  }

  /// Returns a failed completion attempt to its final reviewable step while
  /// preserving every answer. The host calls this only when its durable save
  /// fails, so a user is never stranded on the completed screen.
  bool retryCompletion() {
    if (_stage != OnboardingStage.completed || _result == null) return false;
    _result = null;
    _stage = OnboardingStage.notifications;
    notifyListeners();
    return true;
  }
}
