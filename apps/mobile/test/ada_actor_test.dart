import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/ada_actor.dart';
import 'package:trimmy/design_study/mission.dart';
import 'package:trimmy/design_study/progress.dart';

// A decoded source-sized fixture makes timing deterministic. These tests check
// control continuity and interruptions, not Ada's paths or artwork quality.
class _SourceProvider extends ImageProvider<_SourceProvider> {
  const _SourceProvider(this.image);

  final ui.Image image;

  @override
  Future<_SourceProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _SourceProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture(ImageInfo(image: image.clone())),
  );
}

class _FailedSourceProvider extends ImageProvider<_FailedSourceProvider> {
  const _FailedSourceProvider();

  @override
  Future<_FailedSourceProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _FailedSourceProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(StateError('Test source could not be loaded')),
  );
}

class _DelayedSourceProvider extends ImageProvider<_DelayedSourceProvider> {
  _DelayedSourceProvider();

  final result = Completer<ImageInfo>();

  @override
  Future<_DelayedSourceProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _DelayedSourceProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(result.future);
}

const _dialogue = 'Check the report before choosing an answer.';
late ui.Image _sourceImage;
late _SourceProvider _source;

Widget _actor({
  required AdaBeat beat,
  bool animate = true,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
  bool tickerEnabled = true,
  ImageProvider? imageProvider,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reduceMotion,
      accessibleNavigation: accessibleNavigation,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: Column(
      children: [
        TickerMode(
          enabled: tickerEnabled,
          child: SizedBox(
            width: 160,
            child: AdaActor(
              beat: beat,
              animate: animate,
              imageProvider: imageProvider ?? _source,
            ),
          ),
        ),
        const Text(_dialogue),
      ],
    ),
  ),
);

Finder get _rig => find.byKey(const ValueKey('ada-rig'));

AdaRigPose _pose(WidgetTester tester) {
  expect(_rig, findsOneWidget);
  final painter = tester.widget<CustomPaint>(_rig).painter;
  expect(painter, isA<AdaRigPainter>());
  return (painter! as AdaRigPainter).pose;
}

String _readableContent(WidgetTester tester) => tester.semantics
    .simulatedAccessibilityTraversal()
    .map((node) => node.getSemanticsData().label)
    .where((label) => label.isNotEmpty)
    .join(' ');

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _sourceImage = await createTestImage(
      width: 1536,
      height: 1024,
      cache: false,
    );
    _source = _SourceProvider(_sourceImage);
    for (final font in [
      ('Manrope', 'assets/fonts/manrope/Manrope-Variable.ttf'),
      ('Rubik', 'assets/fonts/rubik/Rubik-Variable.ttf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  tearDownAll(() async {
    await _source.evict();
    _sourceImage.dispose();
  });

  testWidgets('motion preferences immediately hold the latest reaction', (
    tester,
  ) async {
    await tester.pumpWidget(_actor(beat: AdaBeat.reading));
    final initial = _pose(tester);
    final reading = AdaRigPose.forBeat(AdaBeat.reading);
    await tester.pump(const Duration(milliseconds: 120));
    final firstSample = _pose(tester);
    expect(firstSample.headRotation, isNot(initial.headRotation));
    expect(firstSample.gaze, isNot(initial.gaze));
    expect(firstSample, isNot(reading));
    await tester.pump(const Duration(milliseconds: 90));
    final secondSample = _pose(tester);
    expect(secondSample.headRotation, isNot(firstSample.headRotation));
    expect(secondSample.gaze, isNot(firstSample.gaze));
    expect(secondSample, isNot(reading));

    await tester.pumpWidget(_actor(beat: AdaBeat.reading, reduceMotion: true));
    expect(_pose(tester), reading);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_pose(tester), reading);

    // Re-enabling motion must not restart an already settled reaction.
    await tester.pumpWidget(_actor(beat: AdaBeat.reading));
    expect(_pose(tester), reading);
    await tester.pump(const Duration(milliseconds: 80));
    expect(_pose(tester), reading);

    await tester.pumpWidget(
      _actor(beat: AdaBeat.thinking, accessibleNavigation: true),
    );
    expect(_pose(tester), AdaRigPose.forBeat(AdaBeat.thinking));
    await tester.pumpWidget(_actor(beat: AdaBeat.correction, animate: false));
    expect(_pose(tester), AdaRigPose.forBeat(AdaBeat.correction));
    await tester.pumpWidget(_actor(beat: AdaBeat.complete, reduceMotion: true));
    expect(_pose(tester), AdaRigPose.forBeat(AdaBeat.complete));
    await tester.pump(const Duration(seconds: 2));
    expect(_pose(tester), AdaRigPose.forBeat(AdaBeat.complete));
    expect(tester.binding.transientCallbackCount, 0);
    expect(_readableContent(tester), contains(_dialogue));
    expect(tester.takeException(), isNull);
  });

  testWidgets('background and offstage interruption do not replay on return', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(_actor(beat: AdaBeat.correction));
    await tester.pump(const Duration(milliseconds: 100));
    final correction = AdaRigPose.forBeat(AdaBeat.correction);
    expect(_pose(tester), isNot(correction));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(_pose(tester), correction);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_pose(tester), correction);
    await tester.pump(const Duration(milliseconds: 150));
    expect(_pose(tester), correction);

    await tester.pumpWidget(_actor(beat: AdaBeat.thinking));
    await tester.pump(const Duration(milliseconds: 60));
    final thinking = AdaRigPose.forBeat(AdaBeat.thinking);
    expect(_pose(tester), isNot(thinking));
    await tester.pumpWidget(
      _actor(beat: AdaBeat.thinking, tickerEnabled: false),
    );
    expect(_pose(tester), thinking);
    await tester.pumpWidget(_actor(beat: AdaBeat.thinking));
    expect(_pose(tester), thinking);
    await tester.pump(const Duration(milliseconds: 80));
    expect(_pose(tester), thinking);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid replacement preserves the current pose and settles the latest beat',
    (tester) async {
      await tester.pumpWidget(_actor(beat: AdaBeat.correction));
      await tester.pump(const Duration(milliseconds: 90));
      final interruptedCorrection = _pose(tester);
      await tester.pumpWidget(_actor(beat: AdaBeat.complete));
      expect(_pose(tester), interruptedCorrection);
      await tester.pump(const Duration(milliseconds: 250));
      final interruptedCompletion = _pose(tester);
      expect(interruptedCompletion, isNot(interruptedCorrection));
      await tester.pumpWidget(_actor(beat: AdaBeat.thinking));
      expect(_pose(tester), interruptedCompletion);
      await tester.pump(const Duration(milliseconds: 770));
      final interruptedBlink = _pose(tester);
      expect(interruptedBlink.eyeOpen, lessThan(.1));
      await tester.pumpWidget(_actor(beat: AdaBeat.reading));
      expect(
        _pose(tester),
        interruptedBlink,
        reason: 'Replacing a reaction must not snap even a closing eye open.',
      );
      await tester.pump(const Duration(seconds: 2));
      expect(_pose(tester), AdaRigPose.forBeat(AdaBeat.reading));
      expect(tester.binding.transientCallbackCount, 0);
      expect(_readableContent(tester), _dialogue);

      await tester.pumpWidget(_actor(beat: AdaBeat.complete));
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed art uses a static fallback without hiding the instruction',
    (tester) async {
      await tester.pumpWidget(
        _actor(
          beat: AdaBeat.reading,
          imageProvider: const _FailedSourceProvider(),
        ),
      );
      await tester.pumpAndSettle();
      final fallback = find.byKey(const ValueKey('ada-art-fallback'));
      expect(fallback, findsOneWidget);
      expect(tester.getSize(fallback).height, greaterThan(0));
      expect(_rig, findsNothing);
      expect(find.text(_dialogue), findsOneWidget);
      expect(_readableContent(tester), _dialogue);
      await tester.pump(const Duration(seconds: 2));
      expect(fallback, findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late source loading respects the latest beat and motion setting',
    (tester) async {
      final delayed = _DelayedSourceProvider();
      addTearDown(delayed.evict);
      await tester.pumpWidget(
        _actor(beat: AdaBeat.reading, imageProvider: delayed),
      );
      expect(find.byKey(const ValueKey('ada-art-loading')), findsOneWidget);
      expect(_rig, findsNothing);
      expect(_readableContent(tester), _dialogue);

      await tester.pumpWidget(
        _actor(
          beat: AdaBeat.complete,
          reduceMotion: true,
          imageProvider: delayed,
        ),
      );
      delayed.result.complete(ImageInfo(image: _sourceImage.clone()));
      await tester.pumpAndSettle();
      final complete = AdaRigPose.forBeat(AdaBeat.complete);
      expect(find.byKey(const ValueKey('ada-art-loading')), findsNothing);
      expect(_pose(tester), complete);
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(
        _actor(beat: AdaBeat.complete, imageProvider: delayed),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(_pose(tester), complete);
      expect(tester.binding.transientCallbackCount, 0);
      expect(_readableContent(tester), _dialogue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Ada cannot celebrate a pending or failed progress write', (
    tester,
  ) async {
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

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Manrope'),
        home: ActivityStudy(
          repository: repository,
          activity: checkTheDateActivity,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdaActor), findsWidgets);
    final celebrating = find.byWidgetPredicate(
      (widget) => widget is AdaActor && widget.beat == AdaBeat.complete,
    );
    expect(celebrating, findsNothing);

    final failedWrite = Completer<bool>();
    nextWrite = failedWrite;
    await tester.ensureVisible(find.text('Submit answer'));
    await tester.tap(find.text('Submit answer'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Saving…'), findsOneWidget);
    expect(celebrating, findsNothing);
    expect(repository.state.completions, isEmpty);

    failedWrite.complete(false);
    await tester.pumpAndSettle();
    expect(
      find.text('Your progress could not be saved. Please try again.'),
      findsOneWidget,
    );
    expect(celebrating, findsNothing);
    expect(repository.state.active!.stage, 2);
    expect(repository.state.completions, isEmpty);

    await tester.ensureVisible(find.text('Submit answer'));
    await tester.tap(find.text('Submit answer'));
    await tester.pumpAndSettle();
    expect(celebrating, findsOneWidget);
    expect(repository.state.active!.stage, 4);
    final saved = OfficeProgress.fromJson(
      jsonDecode(stored[OfficeProgressRepository.saveKey]!)
          as Map<String, dynamic>,
    );
    expect(
      saved.completions[OfficeActivityIds.checkTheDate]!.selectedChoiceId,
      'add-year',
    );
    expect(
      find.text('Your first answer and what you learned are in your journal.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved correction removes outgoing decision semantics before its fade ends',
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
      await repository.selectChoice('keep-headline');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Manrope'),
          home: ActivityStudy(
            repository: repository,
            activity: checkTheDateActivity,
          ),
        ),
      );
      await tester.pumpAndSettle();
      const outgoingQuestion = 'What does the report tell you?';
      expect(_readableContent(tester), contains(outgoingQuestion));

      final pendingWrite = Completer<bool>();
      nextWrite = pendingWrite;
      await tester.tap(find.text('Submit answer'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(repository.state.active!.stage, 2);
      expect(_readableContent(tester), contains(outgoingQuestion));
      expect(
        find.text('Which year does the report cover?'),
        findsNothing,
        reason: 'Correction must wait for the accepted progress write.',
      );

      pendingWrite.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.state.active!.stage, 3);
      expect(repository.state.completions, isEmpty);

      // These widgets are still mounted for the outgoing fade. Their absence
      // from accessibility cannot be explained by a completed transition.
      expect(find.text(outgoingQuestion), findsOneWidget);
      expect(find.text('Keep the headline'), findsOneWidget);
      var readable = _readableContent(tester);
      expect(readable, isNot(contains(outgoingQuestion)));
      expect(readable, isNot(contains('Keep the headline')));
      expect(readable, isNot(contains('Read the report again')));
      expect(readable, isNot(contains('Submit answer')));
      expect(
        find.bySemanticsLabel(RegExp(r'^Add the year$')),
        findsOneWidget,
        reason:
            'The current correction action remains available during the fade.',
      );

      // Once the incoming face has appeared, its native instruction is exposed
      // while the outgoing subtree is still awaiting removal at 300 ms.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(outgoingQuestion), findsOneWidget);
      readable = _readableContent(tester);
      expect(readable, contains('Which year does the report cover?'));
      expect(readable, contains('Let’s check one detail.'));
      expect(readable, contains('Add the year'));
      expect(readable, isNot(contains(outgoingQuestion)));
      expect(readable, isNot(contains('Keep the headline')));
      expect(repository.state.completions, isEmpty);
      await tester.pumpAndSettle();
      expect(find.text(outgoingQuestion), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
