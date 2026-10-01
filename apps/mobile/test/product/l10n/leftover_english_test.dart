import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_feedback.dart';

import 'l10n_screens.dart';

/// An English catalog message that must not appear on a translated screen.
class _EnglishMessage {
  _EnglishMessage(this.key, this.text, this.pattern);
  final String key, text;
  final RegExp pattern;
}

final _placeholder = RegExp(r'\{[A-Za-z_][A-Za-z0-9_]*\}');

/// Every English message longer than three words whose translation in
/// [language] differs. Messages with placeholders match whatever fills
/// them; plural and select messages are left out.
List<_EnglishMessage> _englishMessages(String language) {
  Map<String, dynamic> read(String code) =>
      jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync())
          as Map<String, dynamic>;
  final english = read('en'), translated = read(language);
  final messages = <_EnglishMessage>[];
  for (final MapEntry(:key, :value) in english.entries) {
    if (key.startsWith('@') || value is! String) continue;
    if (value.contains(RegExp(r',\s*(plural|select)\s*,'))) continue;
    if (translated[key] == value) continue;
    final words = value
        .replaceAll(_placeholder, ' ')
        .split(RegExp(r'\s+'))
        .where((word) => RegExp('[A-Za-z]').hasMatch(word));
    if (words.length <= 3) continue;
    final pattern = value
        .split(_placeholder)
        .map(RegExp.escape)
        .join(r'[\s\S]+?');
    messages.add(_EnglishMessage(key, value, RegExp('^$pattern\$')));
  }
  return messages;
}

/// Every piece of text the screen shows or reads out: text, tooltips and
/// screen reader labels, hints and values.
Set<String> _visibleText(WidgetTester tester) {
  final found = <String>{};
  void add(String? text) {
    final trimmed = text?.trim();
    if (trimmed != null && trimmed.isNotEmpty) found.add(trimmed);
  }

  for (final widget in tester.allWidgets) {
    switch (widget) {
      case Text(:final data, :final textSpan):
        add(data ?? textSpan?.toPlainText());
      case RichText(:final text):
        add(text.toPlainText());
      case Tooltip(:final message):
        add(message);
      case Semantics(:final properties):
        add(properties.label);
        add(properties.hint);
        add(properties.value);
        add(properties.tooltip);
      case Icon(:final semanticLabel):
        add(semanticLabel);
      case Image(:final semanticLabel):
        add(semanticLabel);
    }
  }
  return found;
}

void main() {
  setUp(() async {
    quietAudioForL10nScreens();
    await ReviewFeedback.shared.load();
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  testWidgets('the check finds English sentences when they are there', (
    tester,
  ) async {
    final messages = _englishMessages('fr');
    for (final name in ['settings', 'real buy', 'send']) {
      final screen = l10nScreens.singleWhere((s) => s.name == name);
      final context = await pumpL10nScreen(tester, screen, const Locale('en'));
      final english = [
        for (final text in _visibleText(tester))
          if (messages.any((message) => message.pattern.hasMatch(text))) text,
      ];
      expect(english, isNotEmpty, reason: '$name in English');
      await disposeL10nScreen(tester, context);
    }
  });

  for (final (locale, language) in [
    (const Locale('fr'), 'fr'),
    (const Locale('pt', 'BR'), 'pt'),
  ]) {
    final messages = _englishMessages(language);

    test('the $language check knows the English catalog', () {
      expect(messages.length, greaterThan(500));
    });

    for (final screen in l10nScreens) {
      testWidgets('$language: ${screen.name} shows no English sentence', (
        tester,
      ) async {
        final context = await pumpL10nScreen(tester, screen, locale);
        final seen = _visibleText(tester);
        if (screen.reveal != null) {
          await screen.reveal!(tester);
          await settleL10nScreen(tester);
          seen.addAll(_visibleText(tester));
        }
        final english = [
          for (final text in seen)
            for (final message in messages)
              if (message.pattern.hasMatch(text)) '${message.key}: "$text"',
        ];
        expect(english, isEmpty, reason: 'English left on ${screen.name}');
        await disposeL10nScreen(tester, context);
      });
    }
  }
}
