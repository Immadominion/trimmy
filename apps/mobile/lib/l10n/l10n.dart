import 'package:flutter/widgets.dart';

import 'app_formats.dart';
import 'app_localizations.dart';

export 'app_formats.dart';
export 'app_locale.dart';
export 'app_localizations.dart';

/// English copy, used whenever a widget is built without the app's
/// localization delegate (most widget tests pump screens that way).
final AppLocalizations englishLocalizations = lookupAppLocalizations(
  const Locale('en'),
);

extension AppL10nContext on BuildContext {
  /// The app's copy in the current language. Falls back to English when no
  /// [AppLocalizations] delegate is in the tree, so a widget never fails
  /// just because it was pumped on its own.
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? englishLocalizations;

  /// Numbers, dollar amounts, percents, dates and times for the current
  /// language. English when no locale is in the tree.
  AppFormats get formats => AppFormats.of(this);
}
