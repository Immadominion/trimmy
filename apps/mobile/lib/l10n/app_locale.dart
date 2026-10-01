import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The languages Trimmy speaks, plus following the phone.
enum AppLanguage {
  /// Follow the phone. English when the phone's languages include none of
  /// the others.
  phone(null),
  english('en'),

  /// Latin American Spanish (es-419).
  spanish('es-419'),

  /// Brazilian Portuguese (pt-BR).
  portuguese('pt-BR'),
  french('fr');

  const AppLanguage(this.tag);

  /// The BCP 47 tag stored on the device. Null follows the phone.
  final String? tag;

  /// The locale to hand MaterialApp. Null follows the phone.
  Locale? get locale => switch (this) {
    AppLanguage.phone => null,
    AppLanguage.english => const Locale('en'),
    AppLanguage.spanish => const Locale('es', '419'),
    AppLanguage.portuguese => const Locale('pt', 'BR'),
    AppLanguage.french => const Locale('fr'),
  };

  /// The language's name in that language. Never translated, so anyone can
  /// find their own language whatever the app is showing.
  String? get nativeName => switch (this) {
    AppLanguage.phone => null,
    AppLanguage.english => 'English',
    AppLanguage.spanish => 'Español (Latinoamérica)',
    AppLanguage.portuguese => 'Português (Brasil)',
    AppLanguage.french => 'Français',
  };

  /// The app language that shows [locale]'s copy.
  static AppLanguage forLocale(Locale locale) => switch (locale.languageCode) {
    'es' => AppLanguage.spanish,
    'pt' => AppLanguage.portuguese,
    'fr' => AppLanguage.french,
    _ => AppLanguage.english,
  };

  static AppLanguage fromTag(String? tag) {
    for (final language in values) {
      if (language.tag != null && language.tag == tag) return language;
    }
    return AppLanguage.phone;
  }
}

/// The languages the app's copy exists in, by language code.
const appLanguageCodes = {'en', 'es', 'pt', 'fr'};

/// Picks the locale the app runs in. Pass it to MaterialApp as
/// `localeListResolutionCallback`.
///
/// [preferred] is the phone's language list, or just the chosen language
/// when someone picked one in Settings. The first language Trimmy speaks
/// wins; English otherwise. The phone's region is kept whenever the phone
/// lists that language, because numbers and dates follow the region: a
/// phone set to es-AR reads 1.234,56 while es-MX reads 1,234.56. Spanish and
/// Portuguese with no region become es-419 and pt-BR, the variants the copy
/// is written in. European Spanish and Portuguese phones keep their region
/// for numbers and read the Latin American and Brazilian copy.
///
/// [device] defaults to the phone's own language list.
Locale resolveAppLocale(
  List<Locale>? preferred,
  Iterable<Locale> supported, {
  List<Locale>? device,
}) {
  final languages = {
    for (final locale in supported)
      if (appLanguageCodes.contains(locale.languageCode)) locale.languageCode,
  };
  Locale? chosen;
  for (final locale in preferred ?? const <Locale>[]) {
    if (languages.contains(locale.languageCode)) {
      chosen = locale;
      break;
    }
  }
  if (chosen == null) return const Locale('en');
  final phone = device ?? WidgetsBinding.instance.platformDispatcher.locales;
  for (final locale in [...phone, chosen]) {
    final region = locale.countryCode;
    if (locale.languageCode == chosen.languageCode &&
        region != null &&
        region.isNotEmpty) {
      return Locale(chosen.languageCode, region);
    }
  }
  return switch (chosen.languageCode) {
    'es' => const Locale('es', '419'),
    'pt' => const Locale('pt', 'BR'),
    final language => Locale(language),
  };
}

/// The language someone chose in Settings, kept on this device.
///
/// Stored as a BCP 47 tag under [storageKey]. No value follows the phone.
class AppLocaleController extends ChangeNotifier {
  AppLocaleController(this._preferences)
    : _language = AppLanguage.fromTag(_preferences.getString(storageKey));

  static const storageKey = 'trimmy.product.language.v1';

  final SharedPreferences _preferences;
  AppLanguage _language;

  /// The saved choice. [AppLanguage.phone] until someone picks one.
  AppLanguage get language => _language;

  /// What MaterialApp's `locale` should be. Null follows the phone.
  Locale? get locale => _language.locale;

  Future<void> setLanguage(AppLanguage language) async {
    if (language == _language) return;
    _language = language;
    notifyListeners();
    final tag = language.tag;
    if (tag == null) {
      await _preferences.remove(storageKey);
    } else {
      await _preferences.setString(storageKey, tag);
    }
  }
}

/// Makes the [AppLocaleController] available below the app root, and
/// rebuilds dependents when the choice changes.
class AppLocaleScope extends InheritedNotifier<AppLocaleController> {
  const AppLocaleScope({
    super.key,
    required AppLocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLocaleController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLocaleScope>()?.notifier;
}
