import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../core/paper_decimal.dart';
import 'app_localizations.dart';

/// The one place that decides how numbers, US dollar amounts, percents, dates
/// and times read in the app's language.
///
/// Amounts in Trimmy are computed exactly elsewhere (paper micros, raw token
/// units, BigInt cents) and arrive here already rounded, written the way the
/// English app shows them: `1,234.56`, `-0.25`, `+12`. This class only
/// changes how that text reads for the current locale. It never rounds, so an
/// exact amount stays exact.
///
/// English output is byte for byte what the app showed before localization,
/// whatever the phone's region. Spanish, Portuguese and French follow the
/// phone's region when it speaks the same language (es_MX writes 1,234.56,
/// es_AR writes 1.234,56), otherwise the app language's default region.
///
/// Every amount in Trimmy is in US dollars, practice money included. Where a
/// language's own currencies also use "$" (Latin American pesos, the Brazilian
/// real's R$), the symbol is "US$" so nobody reads dollars as local money.
/// French writes "$US", the usual French form.
@immutable
final class AppFormats {
  const AppFormats._({
    required this.languageCode,
    required this.numberLocale,
    required this.dateTag,
    required this.decimalSeparator,
    required this.groupSeparator,
    required this.minusSign,
    required this.dollarSymbol,
    required this.dollarFirst,
    required this.dollarGap,
    required this.percentFirst,
    required this.percentGap,
  });

  /// Formats for [locale]. Unknown or missing locales format as English.
  factory AppFormats.forLocale(Locale? locale) {
    final language = locale?.languageCode;
    if (locale == null || !_languages.contains(language)) return english;
    final tag = locale.countryCode == null || locale.countryCode!.isEmpty
        ? language!
        : '${language}_${locale.countryCode}';
    return _cache.putIfAbsent(tag, () => AppFormats._build(language!, tag));
  }

  /// Formats for the app's current locale. Works without any localization
  /// delegate: a widget pumped on its own formats as English.
  static AppFormats of(BuildContext context) =>
      AppFormats.forLocale(Localizations.maybeLocaleOf(context));

  /// English, exactly as the app has always written it.
  static final AppFormats english = AppFormats._build('en', 'en');

  static const _languages = {'en', 'es', 'pt', 'fr'};
  static final _cache = <String, AppFormats>{};

  factory AppFormats._build(String language, String tag) {
    if (language == 'en') {
      return const AppFormats._(
        languageCode: 'en',
        numberLocale: 'en',
        dateTag: 'en_US',
        decimalSeparator: '.',
        groupSeparator: ',',
        minusSign: '-',
        dollarSymbol: r'$',
        dollarFirst: true,
        dollarGap: '',
        percentFirst: false,
        percentGap: '',
      );
    }
    // A region intl has no data for (es_AR, es_CO) reads like its language.
    final numberLocale = Intl.verifiedLocale(
      tag,
      NumberFormat.localeExists,
      onFailure: (_) => language,
    )!;
    final symbols = NumberFormat.decimalPattern(numberLocale).symbols;
    final currency = _affix(symbols.CURRENCY_PATTERN, '¤');
    final percent = _affix(symbols.PERCENT_PATTERN, '%');
    return AppFormats._(
      languageCode: language,
      numberLocale: numberLocale,
      dateTag: tag,
      decimalSeparator: symbols.DECIMAL_SEP,
      groupSeparator: symbols.GROUP_SEP,
      minusSign: symbols.MINUS_SIGN,
      dollarSymbol: language == 'fr' ? r'$US' : r'US$',
      dollarFirst: currency.first,
      dollarGap: currency.gap,
      percentFirst: percent.first,
      percentGap: percent.gap,
    );
  }

  /// Where a CLDR pattern puts [mark], and what separates it from the digits.
  static ({bool first, String gap}) _affix(String pattern, String mark) {
    final positive = pattern.split(';').first;
    if (positive.startsWith(mark)) {
      final digits = positive.indexOf(RegExp('[#0]'));
      return (first: true, gap: positive.substring(mark.length, digits));
    }
    final end = positive.lastIndexOf(RegExp('[#0]'));
    final at = positive.indexOf(mark);
    return (first: false, gap: at > end ? positive.substring(end + 1, at) : '');
  }

  /// `en`, `es`, `pt` or `fr`.
  final String languageCode;

  /// The intl locale name used for numbers, such as `es_419` or `pt_BR`.
  final String numberLocale;

  final String dateTag;

  /// The intl locale name used for dates, such as `fr` or `es_419`. Date
  /// names load with the app's Material localizations; until they have
  /// loaded (a widget pumped without delegates), dates read as English.
  String get dateLocale {
    if (isEnglish) return 'en_US';
    if (DateFormat.localeExists(dateTag)) return dateTag;
    if (DateFormat.localeExists(languageCode)) return languageCode;
    return 'en_US';
  }

  final String decimalSeparator;
  final String groupSeparator;
  final String minusSign;

  /// `$` in English, `US$` in Spanish and Portuguese, `$US` in French.
  final String dollarSymbol;

  final bool dollarFirst;
  final String dollarGap;
  final bool percentFirst;
  final String percentGap;

  bool get isEnglish => languageCode == 'en';

  static final _englishNumber = RegExp(
    r'^([+\-]?)([<>~]?)([0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.([0-9]+))?$',
  );

  /// Rewrites a number already written the English way ("1,234.5", "-0.25",
  /// "+12", "<0.01") with this locale's separators: "1.234,5" in pt_BR,
  /// "1 234,5" in French. Grouping follows the English text: an ungrouped
  /// figure stays ungrouped. English text and anything that is not a plain
  /// number come back unchanged.
  String number(String english) {
    if (isEnglish) return english;
    final match = _englishNumber.firstMatch(english);
    if (match == null) return english;
    final sign = match[1] == '-' ? minusSign : match[1]!;
    final whole = match[3]!.replaceAll(',', groupSeparator);
    final fraction = match[4];
    return '$sign${match[2]}$whole'
        '${fraction == null ? '' : '$decimalSeparator$fraction'}';
  }

  /// A whole number with thousands grouping: 12,500 / 12.500 / 12 500.
  String integer(int value) => number(
    value < 0
        ? '-${groupThousands(value.abs().toString())}'
        : groupThousands(value.toString()),
  );

  /// [value] rounded to [decimals] places and grouped, the way the English
  /// app writes `toStringAsFixed` figures with separators.
  String fixed(num value, int decimals) =>
      number(groupDecimal(value.toStringAsFixed(decimals)));

  /// A US dollar amount. [english] is the figure the English app writes
  /// after its "$": "1,234.56", "-12.30", "+5". A sign goes before the
  /// symbol: "-$12.30", "-US$12.30", "-12,30 $US".
  String usd(String english) {
    final signed = english.startsWith('-') || english.startsWith('+');
    final sign = !signed
        ? ''
        : english.startsWith('-')
        ? minusSign
        : '+';
    return _dollars(sign, number(signed ? english.substring(1) : english));
  }

  String _dollars(String sign, String digits) => dollarFirst
      ? '$sign$dollarSymbol$dollarGap$digits'
      : '$sign$digits$dollarGap$dollarSymbol';

  /// A dollar amount from a double, to [decimals] places, grouped.
  String usdFixed(num value, [int decimals = 2]) =>
      usd(groupDecimal(value.toStringAsFixed(decimals)));

  /// A percent. [english] is the figure the English app writes before its
  /// "%": "12.34", "+0.50", "-<0.01". French and Spain's Spanish put a
  /// no-break space before the sign: "12,34 %".
  String percent(String english) {
    final digits = number(english);
    return percentFirst ? '%$percentGap$digits' : '$digits$percentGap%';
  }

  /// Large dollar figures such as market caps: "$1.23T", "$2.50B" and
  /// "$12.35K" in English. Other languages keep the two places and use their
  /// own short units from the ARB files ("US$ 1,23 tri", "1,23 Bn $US").
  /// Below a thousand it is a plain two-place amount.
  String compactUsd(double value) {
    for (final unit in _compactUnits) {
      if (value.abs() >= unit.$1) {
        return _dollars('', _compact(value / unit.$1, unit.$2));
      }
    }
    return isEnglish ? '\$${value.toStringAsFixed(2)}' : usdFixed(value);
  }

  /// Large token or share counts: "1.25M", "12.50K" and "0.125" in English
  /// (two places once shortened, up to three below a thousand, never
  /// beyond millions). Other languages use their own short units.
  String compactNumber(double value) {
    if (value.abs() >= 1e6) return _compact(value / 1e6, _CompactUnit.million);
    if (value.abs() >= 1e3) return _compact(value / 1e3, _CompactUnit.thousand);
    return number(value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), ''));
  }

  static const _compactUnits = [
    (1e12, _CompactUnit.trillion),
    (1e9, _CompactUnit.billion),
    (1e6, _CompactUnit.million),
    (1e3, _CompactUnit.thousand),
  ];

  String _compact(double scaled, _CompactUnit unit) {
    final figure = number(scaled.toStringAsFixed(2));
    return switch (unit) {
      _CompactUnit.thousand => messages.formatCompactThousand(figure),
      _CompactUnit.million => messages.formatCompactMillion(figure),
      _CompactUnit.billion => messages.formatCompactBillion(figure),
      _CompactUnit.trillion => messages.formatCompactTrillion(figure),
    };
  }

  /// The app's copy in this language, for the few formatting helpers that
  /// also need a word (a short unit, "Price unavailable"). Widgets use
  /// `context.l10n`.
  AppLocalizations get messages =>
      _messages[languageCode] ??= lookupAppLocalizations(Locale(languageCode));

  static final _messages = <String, AppLocalizations>{};

  // Dates and times. English keeps the app's historical patterns exactly;
  // other languages use CLDR skeletons for the same information.

  DateFormat _date(String englishPattern, DateFormat Function(String) other) {
    final locale = dateLocale;
    return locale == 'en_US'
        ? DateFormat(englishPattern, locale)
        : other(locale);
  }

  /// "Sep 30" in English, "30 sept." in French, "30 de set." in pt_BR.
  String monthDay(DateTime date) =>
      _date('MMM d', DateFormat.MMMd).format(date);

  /// "30 Sep" in English (day first), "30 sept." in French.
  String dayMonth(DateTime date) =>
      _date('d MMM', DateFormat.MMMd).format(date);

  /// "30 Sep 2026" in English, "30 sept. 2026" in French.
  String dayMonthYear(DateTime date) =>
      _date('d MMM y', DateFormat.yMMMd).format(date);

  /// "Sep 30, 2026" in English, "30 sept. 2026" in French.
  String monthDayYear(DateTime date) =>
      _date('MMM d, y', DateFormat.yMMMd).format(date);

  /// "30/9" in English, "30/09" in French and Portuguese.
  String numericDayMonth(DateTime date) =>
      _date('d/M', DateFormat.Md).format(date);

  /// "30/9/2026" in English, "30/09/2026" in French and Portuguese.
  String numericDate(DateTime date) =>
      _date('d/M/y', DateFormat.yMd).format(date);

  /// "Mon" in English, "lun." in French.
  String weekdayShort(DateTime date) => _date('EEE', DateFormat.E).format(date);

  /// A 24-hour clock: "14:05".
  String time24(DateTime date) => _date('HH:mm', DateFormat.Hm).format(date);

  /// "2:05 PM" in English; each language's usual clock elsewhere ("14:05" in
  /// French and Brazilian Portuguese, "2:05 p.m." in Latin American Spanish).
  String time12(DateTime date) => _date('h:mm a', DateFormat.jm).format(date);

  // Typed amounts.

  /// What an amount field accepts while typing. English accepts digits and
  /// a point, as it always has. Languages whose decimal mark is a comma also
  /// accept the comma their keypad shows.
  RegExp get decimalInputCharacters =>
      decimalSeparator == ',' ? RegExp(r'[0-9.,]') : RegExp(r'[0-9.]');

  /// Turns a typed amount into the plain `1234.5` form the exact parsers
  /// read. English text is returned unchanged, so English parsing behaves
  /// exactly as before.
  ///
  /// Where the decimal mark is a comma, both marks are accepted: a comma is
  /// the decimal mark and points are grouping ("1.234,5" is 1234.5). Without
  /// a comma, a point is the decimal mark ("12.5" is 12.5) even when three digits follow it ("1.250" stays 1.250).
  /// Do not silently multiply a typed amount by treating its point as grouping.
  /// Spaces are ignored. Anything unclear comes back as typed, so the
  /// existing validation rejects it rather than guessing.
  String normalizeDecimalInput(String typed) {
    if (decimalSeparator != ',') return typed;
    final text = typed.trim().replaceAll(RegExp(r'[\s  ]'), '');
    if (text.contains(',')) {
      final parts = text.split(',');
      if (parts.length != 2) return typed;
      final whole = parts.first;
      if (whole.contains('.') &&
          !RegExp(r'^[0-9]{1,3}(?:\.[0-9]{3})+$').hasMatch(whole)) {
        return typed;
      }
      return '${whole.replaceAll('.', '')}.${parts.last}';
    }
    return text;
  }

  /// A plain decimal for an amount field, in the reader's decimal mark:
  /// "12.5" in English, "12,5" in French. [plain] has no grouping.
  String decimalInput(String plain) =>
      isEnglish ? plain : plain.replaceFirst('.', decimalSeparator);
}

enum _CompactUnit { thousand, million, billion, trillion }

/// Adds English thousands commas to the whole part of a plain decimal such as
/// "-1234.50", keeping its sign and fraction. Anything else is unchanged.
String groupDecimal(String plain) {
  final match = RegExp(r'^([+\-]?)([0-9]+)((?:\.[0-9]+)?)$').firstMatch(plain);
  if (match == null) return plain;
  return '${match[1]}${groupThousands(match[2]!)}${match[3]}';
}
