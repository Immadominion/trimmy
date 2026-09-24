import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/ui_review/review_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Sound, haptics and quiet volume survive a new session', () async {
    final first = ReviewFeedback();
    await first.load();
    expect(first.volume, .4);
    await first.setSound(false);
    await first.setHaptics(false);
    await first.setVolume(.2);
    first.dispose();

    final next = ReviewFeedback();
    await next.load();
    expect(next.sound, isFalse);
    expect(next.haptics, isFalse);
    expect(next.volume, .2);
    next.dispose();
  });

  test('Volume cannot exceed the quiet playback ceiling', () async {
    final feedback = ReviewFeedback();
    await feedback.setVolume(1);
    expect(feedback.volume, .4);
    await feedback.setVolume(-1);
    expect(feedback.volume, 0);
    feedback.dispose();
  });

  test('Disabled haptics and backgrounded presses stay silent', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final feedback = ReviewFeedback();
    await feedback.load();
    await feedback.setHaptics(false);
    feedback.press();
    expect(calls, isEmpty);
    await feedback.setHaptics(true);
    feedback.didChangeAppLifecycleState(AppLifecycleState.inactive);
    feedback.press();
    expect(calls, isEmpty);
    feedback.didChangeAppLifecycleState(AppLifecycleState.resumed);
    feedback.press(selection: true);
    expect(calls.single.method, 'HapticFeedback.vibrate');
    expect(calls.single.arguments, 'HapticFeedbackType.selectionClick');
    feedback.dispose();
  });
}
