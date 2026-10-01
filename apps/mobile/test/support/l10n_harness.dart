import 'package:flutter/material.dart';
import 'package:trimmy/l10n/l10n.dart';
import 'package:trimmy/product/design/product_theme.dart';

/// A MaterialApp wired the way production wires TrimmyProductApp: the app's
/// localization delegates, its locale resolution and, when [controller] is
/// given, the language chosen in Settings. [textScale] enlarges text the way
/// a phone's font size setting does.
Widget localizedTestApp({
  required Widget home,
  Locale? locale,
  AppLocaleController? controller,
  double textScale = 1,
  Size? size,
}) {
  Widget app(Locale? current) => MaterialApp(
    theme: productTheme(),
    debugShowCheckedModeBanner: false,
    locale: current,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    localeListResolutionCallback: resolveAppLocale,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale), size: size),
      child: child!,
    ),
    home: home,
  );
  if (controller == null) return app(locale);
  return AppLocaleScope(
    controller: controller,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => app(controller.locale ?? locale),
    ),
  );
}

/// The locales the layout tests pump: the two languages that run longest.
const longLocales = [Locale('fr'), Locale('pt', 'BR')];
