import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('pt'),
  ];

  /// Generic button that closes a sheet or dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic button that moves to the next step.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// Generic button that finishes a flow and closes it.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Generic button or tooltip that closes a sheet, page or dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Generic button or tooltip that goes back one step.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Generic button shown after something failed, to repeat the same action.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Short generic button to repeat a failed action, where space is tight.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Generic button that saves a choice.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Generic button that opens sign-in.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get commonSignIn;

  /// Short button on an amount field that fills in the largest amount allowed. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get commonMax;

  /// Button or label for buying shares of a stock.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get commonBuy;

  /// Button or label for selling shares of a stock.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get commonSell;

  /// Career rank 1 of 6, the starting rank of a new player. Shown as a title, like a job level on Wall Street.
  ///
  /// In en, this message translates to:
  /// **'Rookie'**
  String get rankRookie;

  /// Career rank 2 of 6. A Wall Street job title.
  ///
  /// In en, this message translates to:
  /// **'Analyst'**
  String get rankAnalyst;

  /// Career rank 3 of 6. A Wall Street job title.
  ///
  /// In en, this message translates to:
  /// **'Trader'**
  String get rankTrader;

  /// Career rank 4 of 6. A Wall Street job title.
  ///
  /// In en, this message translates to:
  /// **'Senior Trader'**
  String get rankSeniorTrader;

  /// Career rank 5 of 6. A partner of the firm.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get rankPartner;

  /// Career rank 6 of 6, the top rank.
  ///
  /// In en, this message translates to:
  /// **'Legend'**
  String get rankLegend;

  /// A shortened number in thousands, such as a market cap or a token amount. Keep the unit as short as your language's financial press writes it.
  ///
  /// In en, this message translates to:
  /// **'{value}K'**
  String formatCompactThousand(String value);

  /// A shortened number in millions (10^6), such as a market cap.
  ///
  /// In en, this message translates to:
  /// **'{value}M'**
  String formatCompactMillion(String value);

  /// A shortened number in billions, meaning thousands of millions (10^9), such as a market cap.
  ///
  /// In en, this message translates to:
  /// **'{value}B'**
  String formatCompactBillion(String value);

  /// A shortened number in trillions, meaning millions of millions (10^12), such as a market cap.
  ///
  /// In en, this message translates to:
  /// **'{value}T'**
  String formatCompactTrillion(String value);

  /// Shown in place of a stock's price when no price could be read.
  ///
  /// In en, this message translates to:
  /// **'Price unavailable'**
  String get marketPriceUnavailable;

  /// Settings row title and the title of the language picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Language choice that follows the phone's own language setting. Shown as the Language row's value in Settings and as the first option in the language picker. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Phone language'**
  String get settingsLanguagePhone;

  /// Line under the 'Phone language' option in the language picker, explaining that the app follows the phone.
  ///
  /// In en, this message translates to:
  /// **'Uses the language your phone is set to.'**
  String get settingsLanguagePhoneDetail;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'fr', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
