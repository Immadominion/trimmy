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
}
