import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every message the English template defines exists in every language,
/// with the same placeholders and the same plural/select structure, so no
/// screen silently falls back to English or drops a value.
void main() {
  const languages = ['en', 'es', 'pt', 'fr'];
  final arb = {
    for (final language in languages)
      language:
          jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
              as Map<String, dynamic>,
  };
  Iterable<String> messages(String language) =>
      arb[language]!.keys.where((key) => !key.startsWith('@'));

  test('every language has exactly the English keys', () {
    final english = messages('en').toSet();
    expect(english, isNotEmpty);
    for (final language in languages.skip(1)) {
      final keys = messages(language).toSet();
      expect(
        english.difference(keys),
        isEmpty,
        reason: '$language is missing translations',
      );
      expect(
        keys.difference(english),
        isEmpty,
        reason: '$language has messages English does not define',
      );
    }
  });

  test('every English message explains itself to translators', () {
    for (final key in messages('en')) {
      final meta = arb['en']!['@$key'];
      expect(meta, isA<Map<String, dynamic>>(), reason: '@$key is missing');
      final description = (meta as Map<String, dynamic>)['description'];
      expect(
        description is String && description.trim().isNotEmpty,
        isTrue,
        reason: '@$key has no description',
      );
      final declared =
          ((meta['placeholders'] as Map<String, dynamic>?) ?? const {}).keys
              .toSet();
      expect(
        _arguments(arb['en']![key] as String).names,
        declared,
        reason: '$key declares different placeholders than it uses',
      );
    }
  });

  test('translations keep every placeholder, plural and select', () {
    for (final key in messages('en')) {
      final english = _arguments(arb['en']![key] as String);
      for (final language in languages.skip(1)) {
        final text = arb[language]![key];
        if (text is! String) continue;
        final translated = _arguments(text);
        expect(
          translated.names,
          english.names,
          reason: '$language $key placeholders differ from English',
        );
        expect(
          translated.kinds,
          english.kinds,
          reason: '$language $key plural/select structure differs',
        );
      }
    }
  });

  test('no message uses an em dash', () {
    for (final language in languages) {
      for (final key in messages(language)) {
        expect(
          (arb[language]![key] as String).contains('—'),
          isFalse,
          reason: '$language $key contains an em dash',
        );
      }
    }
  });
}

/// The argument names an ICU message uses, and the kind of each complex one
/// (plural, select), including arguments nested inside branches.
({Set<String> names, Map<String, String> kinds}) _arguments(String message) {
  final names = <String>{};
  final kinds = <String, String>{};
  final name = RegExp(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*');
  final type = RegExp(r',\s*([A-Za-z]+)\s*');
  final branch = RegExp(r'\s*(=?[A-Za-z0-9_]+)\s*\{');
  final close = RegExp(r'\s*\}');

  late int Function(int) argument;
  int text(int i, {required bool nested}) {
    while (i < message.length) {
      final c = message[i];
      if (c == '{') {
        i = argument(i + 1);
      } else if (c == '}') {
        if (nested) return i;
        throw FormatException('Unbalanced "}"', message, i);
      } else {
        i++;
      }
    }
    if (nested) throw FormatException('Unclosed "{"', message);
    return i;
  }

  argument = (i) {
    final n = name.matchAsPrefix(message, i);
    if (n == null) throw FormatException('Bad placeholder', message, i);
    names.add(n[1]!);
    i = n.end;
    if (message[i] == '}') return i + 1;
    final t = type.matchAsPrefix(message, i);
    if (t == null) throw FormatException('Bad argument', message, i);
    i = t.end;
    if (!const {'plural', 'select', 'selectordinal'}.contains(t[1])) {
      return message.indexOf('}', i) + 1;
    }
    kinds[n[1]!] = t[1]!;
    i++; // the comma before the branches
    while (true) {
      final b = branch.matchAsPrefix(message, i);
      if (b != null) {
        i = text(b.end, nested: true) + 1;
        continue;
      }
      final end = close.matchAsPrefix(message, i);
      if (end == null) throw FormatException('Bad branch', message, i);
      return end.end;
    }
  };
  text(0, nested: false);
  return (names: names, kinds: kinds);
}
