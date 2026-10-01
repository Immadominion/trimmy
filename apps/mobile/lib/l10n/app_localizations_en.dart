// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonDone => 'Done';

  @override
  String get commonClose => 'Close';

  @override
  String get commonBack => 'Back';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSignIn => 'Sign in';

  @override
  String get commonMax => 'Max';

  @override
  String get commonBuy => 'Buy';

  @override
  String get commonSell => 'Sell';

  @override
  String get rankRookie => 'Rookie';

  @override
  String get rankAnalyst => 'Analyst';

  @override
  String get rankTrader => 'Trader';

  @override
  String get rankSeniorTrader => 'Senior Trader';

  @override
  String get rankPartner => 'Partner';

  @override
  String get rankLegend => 'Legend';

  @override
  String formatCompactThousand(String value) {
    return '${value}K';
  }

  @override
  String formatCompactMillion(String value) {
    return '${value}M';
  }

  @override
  String formatCompactBillion(String value) {
    return '${value}B';
  }

  @override
  String formatCompactTrillion(String value) {
    return '${value}T';
  }

  @override
  String get marketPriceUnavailable => 'Price unavailable';

  @override
  String get commonAddMoney => 'Add money';

  @override
  String get commonSaving => 'Saving…';

  @override
  String get commonChecking => 'Checking…';

  @override
  String get commonConnecting => 'Connecting…';

  @override
  String get commonSending => 'Sending…';

  @override
  String get commonConfirming => 'Confirming…';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonNotNow => 'Not now';

  @override
  String get commonSkip => 'Skip';

  @override
  String get commonHistory => 'History';

  @override
  String get commonSettings => 'Settings';

  @override
  String commonInProgress(String label) {
    return '$label in progress';
  }

  @override
  String get modePaper => 'Paper';

  @override
  String get modeReal => 'Real';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguagePhone => 'Phone language';

  @override
  String get settingsLanguagePhoneDetail =>
      'Uses the language your phone is set to.';
}
