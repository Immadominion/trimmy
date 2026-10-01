import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';

enum SettingsSignInMethod {
  email,
  google,
  x;

  /// The method's name in the Account section. Google and X are brand names
  /// and stay as they are.
  String label(AppLocalizations l10n) => switch (this) {
    SettingsSignInMethod.email => l10n.settingsSignInMethodEmail,
    SettingsSignInMethod.google => 'Google',
    SettingsSignInMethod.x => 'X',
  };
}

enum SettingsNotificationKind {
  wallStreetOpen(SettingsNotificationGroup.market),
  wallStreetClose(SettingsNotificationGroup.market),
  stockEvents(SettingsNotificationGroup.market),
  priceAlerts(SettingsNotificationGroup.market),
  streakReminder(SettingsNotificationGroup.career),
  missions(SettingsNotificationGroup.career),
  promotions(SettingsNotificationGroup.career),
  league(SettingsNotificationGroup.career),
  friends(SettingsNotificationGroup.social),
  tradesAndReceipts(SettingsNotificationGroup.account),
  trimmyNews(SettingsNotificationGroup.account);

  const SettingsNotificationKind(this.group);

  final SettingsNotificationGroup group;

  String title(AppLocalizations l10n) => switch (this) {
    SettingsNotificationKind.wallStreetOpen => l10n.settingsNotificationOpen,
    SettingsNotificationKind.wallStreetClose => l10n.settingsNotificationClose,
    SettingsNotificationKind.stockEvents => l10n.settingsNotificationEvents,
    SettingsNotificationKind.priceAlerts => l10n.settingsNotificationPrices,
    SettingsNotificationKind.streakReminder => l10n.settingsNotificationStreak,
    SettingsNotificationKind.missions => l10n.settingsNotificationMissions,
    SettingsNotificationKind.promotions => l10n.settingsNotificationPromotions,
    SettingsNotificationKind.league => l10n.settingsNotificationLeague,
    SettingsNotificationKind.friends => l10n.settingsNotificationFriends,
    SettingsNotificationKind.tradesAndReceipts =>
      l10n.settingsNotificationTrades,
    SettingsNotificationKind.trimmyNews => l10n.settingsNotificationNews,
  };

  String description(
    AppLocalizations l10n,
    AppFormats formats,
  ) => switch (this) {
    SettingsNotificationKind.wallStreetOpen =>
      l10n.settingsNotificationOpenDetail,
    SettingsNotificationKind.wallStreetClose =>
      l10n.settingsNotificationCloseDetail,
    SettingsNotificationKind.stockEvents =>
      l10n.settingsNotificationEventsDetail,
    SettingsNotificationKind.priceAlerts =>
      l10n.settingsNotificationPricesDetail(
        formats.percent('5'),
        formats.percent('10'),
      ),
    SettingsNotificationKind.streakReminder =>
      l10n.settingsNotificationStreakDetail,
    SettingsNotificationKind.missions =>
      l10n.settingsNotificationMissionsDetail,
    SettingsNotificationKind.promotions =>
      l10n.settingsNotificationPromotionsDetail,
    SettingsNotificationKind.league => l10n.settingsNotificationLeagueDetail,
    SettingsNotificationKind.friends => l10n.settingsNotificationFriendsDetail,
    SettingsNotificationKind.tradesAndReceipts =>
      l10n.settingsNotificationTradesDetail,
    SettingsNotificationKind.trimmyNews => l10n.settingsNotificationNewsDetail,
  };
}

enum SettingsNotificationGroup {
  market,
  career,
  social,
  account;

  String label(AppLocalizations l10n) => switch (this) {
    SettingsNotificationGroup.market => l10n.settingsNotificationGroupMarket,
    SettingsNotificationGroup.career => l10n.settingsNotificationGroupCareer,
    SettingsNotificationGroup.social => l10n.settingsNotificationGroupSocial,
    SettingsNotificationGroup.account => l10n.settingsNotificationGroupAccount,
  };
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

  /// "10:00 PM to 7:00 AM". [startLabel] and [endLabel] arrive already
  /// formatted for the reader.
  String timeLabel(AppLocalizations l10n) =>
      l10n.settingsQuietHoursRange(startLabel, endLabel);
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
  });

  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool animationsEnabled;
  final bool systemReduceMotionEnabled;
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
  friends,
  everyone,
  nobody;

  String label(AppLocalizations l10n) => switch (this) {
    SettingsVisibility.friends => l10n.settingsVisibilityFriends,
    SettingsVisibility.everyone => l10n.settingsVisibilityEveryone,
    SettingsVisibility.nobody => l10n.settingsVisibilityNobody,
  };
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
