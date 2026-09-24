import 'package:flutter/foundation.dart';

enum SettingsSignInMethod {
  email('Email'),
  google('Google'),
  x('X');

  const SettingsSignInMethod(this.label);
  final String label;
}

enum SettingsNotificationKind {
  wallStreetOpen(
    'Wall Street open',
    'When Wall Street opens.',
    SettingsNotificationGroup.market,
  ),
  wallStreetClose(
    'Wall Street close',
    'When Wall Street closes.',
    SettingsNotificationGroup.market,
  ),
  stockEvents(
    'Events on my stocks',
    'Updates that affect stocks you hold.',
    SettingsNotificationGroup.market,
  ),
  priceAlerts(
    'Price alerts',
    'Moves of 5% or 10% on followed stocks.',
    SettingsNotificationGroup.market,
  ),
  streakReminder(
    'Streak reminder',
    'When your streak is at risk.',
    SettingsNotificationGroup.career,
  ),
  missions(
    'Missions',
    'New missions and progress.',
    SettingsNotificationGroup.career,
  ),
  promotions(
    'Promotions',
    'When you earn a new rank.',
    SettingsNotificationGroup.career,
  ),
  league(
    'League',
    'League results and position changes.',
    SettingsNotificationGroup.career,
  ),
  friends(
    'Friends',
    'Friends\' trades and reasons.',
    SettingsNotificationGroup.social,
  ),
  tradesAndReceipts(
    'Trades and receipts',
    'Confirmed trades, deposits and withdrawals.',
    SettingsNotificationGroup.account,
  ),
  trimmyNews(
    'News from Trimmy',
    'Product news and updates.',
    SettingsNotificationGroup.account,
  );

  const SettingsNotificationKind(this.title, this.description, this.group);

  final String title;
  final String description;
  final SettingsNotificationGroup group;
}

enum SettingsNotificationGroup {
  market('Market'),
  career('Career'),
  social('Social'),
  account('Account');

  const SettingsNotificationGroup(this.label);
  final String label;
}

@immutable
class SettingsNotificationValue {
  const SettingsNotificationValue({
    required this.enabled,
    this.available = true,
    this.updating = false,
  });

  final bool enabled;
  final bool available;
  final bool updating;
}

@immutable
class SettingsQuietHours {
  const SettingsQuietHours({
    required this.enabled,
    required this.startLabel,
    required this.endLabel,
    this.available = true,
    this.updating = false,
  });

  final bool enabled;
  final String startLabel;
  final String endLabel;
  final bool available;
  final bool updating;

  String get timeLabel => '$startLabel to $endLabel';
}

@immutable
class SettingsAccountState {
  SettingsAccountState({
    required this.signedIn,
    required this.handle,
    required this.persona,
    this.email,
    Set<SettingsSignInMethod> signInMethods = const <SettingsSignInMethod>{},
  }) : signInMethods = Set.unmodifiable(signInMethods);

  final bool signedIn;
  final String handle;
  final String persona;
  final String? email;
  final Set<SettingsSignInMethod> signInMethods;
}

@immutable
class SettingsAppearanceState {
  const SettingsAppearanceState({
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.animationsEnabled,
    required this.systemReduceMotionEnabled,
    required this.languageLabel,
  });

  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool animationsEnabled;
  final bool systemReduceMotionEnabled;
  final String languageLabel;
}

@immutable
class SettingsPaperState {
  const SettingsPaperState({
    required this.limit,
    this.resetAvailable = false,
    this.resetPending = false,
  });

  /// Integer paper units. Paper never carries a currency symbol.
  final int limit;
  final bool resetAvailable;
  final bool resetPending;
}

enum SettingsPaperResetFailure {
  staleRevision,
  notNeeded,
  offline,
  timeout,
  accountRequired,
  rateLimited,
  unavailable,
  rejected,
}

final class SettingsPaperResetException implements Exception {
  const SettingsPaperResetException(this.failure);

  final SettingsPaperResetFailure failure;
}

@immutable
final class SettingsPaperResetReceipt {
  const SettingsPaperResetReceipt({
    required this.revision,
    required this.currentRevision,
    required this.paperBalance,
    required this.resetAt,
  });

  final int revision;
  final int currentRevision;
  final String paperBalance;
  final DateTime resetAt;

  bool get hasNewerActivity => currentRevision > revision;
}

typedef SettingsPaperReset = Future<SettingsPaperResetReceipt> Function();

enum SettingsFeatureAvailability { available, comingSoon, unavailable }

@immutable
class SettingsMoneyState {
  const SettingsMoneyState({
    required this.availability,
    this.currency,
    this.partnerName,
    this.feeSummary,
    this.countryStatus,
    this.savedBankAccountCount,
    this.savedCardCount,
  });

  final SettingsFeatureAvailability availability;
  final String? currency;
  final String? partnerName;
  final String? feeSummary;
  final String? countryStatus;
  final int? savedBankAccountCount;
  final int? savedCardCount;
}

@immutable
class SettingsWalletState {
  const SettingsWalletState({required this.availability, this.address});

  final SettingsFeatureAvailability availability;
  final String? address;
}

enum SettingsVisibility {
  friends('Friends'),
  everyone('Everyone'),
  nobody('Nobody');

  const SettingsVisibility(this.label);
  final String label;
}

/// Holdings visibility has no server contract yet. Reason visibility is
/// server-owned and rendered from its own controller, not from this state.
@immutable
class SettingsPrivacyState {
  const SettingsPrivacyState({required this.holdingsVisibility});

  final SettingsVisibility holdingsVisibility;
}

@immutable
class ProductSettingsState {
  ProductSettingsState({
    required this.account,
    required Map<SettingsNotificationKind, SettingsNotificationValue>
    notifications,
    required this.quietHours,
    required this.appearance,
    required this.paper,
    required this.money,
    required this.wallet,
    this.privacy,
  }) : notifications = Map.unmodifiable(notifications);

  final SettingsAccountState account;
  final Map<SettingsNotificationKind, SettingsNotificationValue> notifications;
  final SettingsQuietHours quietHours;
  final SettingsAppearanceState appearance;
  final SettingsPaperState paper;
  final SettingsMoneyState money;
  final SettingsWalletState wallet;
  final SettingsPrivacyState? privacy;

  SettingsNotificationValue notification(SettingsNotificationKind kind) =>
      notifications[kind] ??
      const SettingsNotificationValue(enabled: false, available: false);
}

typedef SettingsNotificationChanged =
    void Function(SettingsNotificationKind kind, bool enabled);
