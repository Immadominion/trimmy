import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/mission.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/design_study/study_audio.dart';

class _SoundRecorder implements StudyAudioOutput {
  @override
  bool enabled = false;
  final requests = <StudySound>[];
  int closeCount = 0;

  @override
  void setEnabled(bool value) => enabled = value;

  @override
  void play(StudySound sound) => requests.add(sound);

  @override
  Future<void> close() async {
    closeCount++;
    enabled = false;
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'saved cue waits for ACK, survives retry, and stays quiet on restore',
    (tester) async {
      _phone(tester);
      final stored = <String, String>{};
      Completer<bool>? nextWrite;
      final repository = OfficeProgressRepository(
        read: (key) => stored[key],
        write: (key, value) async {
          final gate = nextWrite;
          nextWrite = null;
          if (gate != null && !await gate.future) return false;
          stored[key] = value;
          return true;
        },
        clock: () => DateTime.utc(2026, 9, 13, 12),
      );
      await repository.startActivity(OfficeActivityIds.checkTheDate);
      await repository.advance();
      await repository.advance();
      await repository.selectChoice('add-year');
      final audio = _SoundRecorder()..setEnabled(true);

      Widget activity() => MaterialApp(
        home: ActivityStudy(
          repository: repository,
          activity: checkTheDateActivity,
          audio: audio,
        ),
      );

      await tester.pumpWidget(activity());
      await tester.pumpAndSettle();
      expect(audio.requests, isEmpty);
      final failed = Completer<bool>();
      nextWrite = failed;
      await tester.tap(find.text('Submit answer'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Saving…'), findsOneWidget);
      expect(audio.requests, isEmpty);
      expect(repository.state.completions, isEmpty);
      failed.complete(false);
      await tester.pumpAndSettle();
      expect(
        find.text('Your progress could not be saved. Please try again.'),
        findsOneWidget,
      );
      expect(audio.requests, isEmpty);
      expect(repository.state.active!.stage, 2);

      final accepted = Completer<bool>();
      nextWrite = accepted;
      await tester.tap(find.text('Submit answer'));
      await tester.pump(const Duration(seconds: 2));
      expect(audio.requests, isEmpty);
      accepted.complete(true);
      await tester.pumpAndSettle();
      expect(repository.state.active!.stage, 4);
      expect(stored, contains(OfficeProgressRepository.saveKey));
      expect(audio.requests, [StudySound.saved]);
      expect(
        find.text(
          'Your first answer and what you learned are in your journal.',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(activity());
      await tester.pumpAndSettle();
      expect(find.text('Good catch.'), findsOneWidget);
      expect(audio.requests, [StudySound.saved]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sound preference persists; enabling and resuming stay silent', (
    tester,
  ) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final audio = _SoundRecorder();
    await tester.pumpWidget(
      OfficeStudy(preferences: preferences, audio: audio),
    );
    await tester.pumpAndSettle();
    expect(audio.enabled, isFalse);
    expect(audio.requests, isEmpty);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Preview sound'), findsNothing);
    await _tap(tester, 'Sound');
    expect(audio.enabled, isTrue);
    expect(preferences.getBool('trimmy.office.sound.v1'), isTrue);
    expect(audio.requests, isEmpty);
    await _tap(tester, 'Preview sound');
    expect(audio.requests, [StudySound.paper]);
    await _tap(tester, 'Sound');
    expect(audio.enabled, isFalse);
    expect(preferences.getBool('trimmy.office.sound.v1'), isFalse);
    expect(audio.requests, [StudySound.paper]);
    await _tap(tester, 'Sound');
    expect(audio.requests, [StudySound.paper]);
    await _tap(tester, 'Done');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(audio.closeCount, 1);
    await preferences.reload();

    final restoredAudio = _SoundRecorder();
    await tester.pumpWidget(
      OfficeStudy(preferences: preferences, audio: restoredAudio),
    );
    await tester.pumpAndSettle();
    expect(restoredAudio.enabled, isTrue);
    expect(restoredAudio.requests, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(restoredAudio.requests, isEmpty);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final soundTile = find.ancestor(
      of: find.text('Sound'),
      matching: find.byType(SwitchListTile),
    );
    expect(tester.widget<SwitchListTile>(soundTile).value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
