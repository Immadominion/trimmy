import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_optional_setup.dart';

const _clipAsset = 'assets/images/ui_review/sal-chair-welcome-v3.webp';
const _stillAsset = 'assets/images/ui_review/sal-chair-welcome-v3-still.png';
const _frameKey = ValueKey('sign-in-chair-frame');
const _stillKey = ValueKey('sign-in-chair-still');
const _methods = ['email', 'Apple', 'Google', 'X'];

// Authored test fixture: three 1px frames, red/green/blue, 100ms each.
// The welcome should keep playing while visible, regardless of loop metadata.
final _loopingGif = base64Decode(
  'R0lGODlhAQABAIEAAP8AAAD/AAAA/////yH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACwAAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAIfkEAAoAAAAsAAAAAAEAAQAAAgJUAQA7',
);
final _whitePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final method in _methods) {
    testWidgets('$method works before the chair clip has loaded', (
      tester,
    ) async {
      final pending = Completer<ByteData>();
      final bundle = _AnimationBundle(clip: () => pending.future);
      await _pumpPage(tester, bundle);

      expect(bundle.clipLoads, 1);
      expect(find.byKey(_stillKey), findsOneWidget);
      for (final action in _methods) {
        expect(_methodAction(action).hitTestable(), findsOneWidget);
      }
      await tester.tap(_methodAction(method));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('$method sign-in preview'), findsOneWidget);
      expect(
        find.textContaining('No account has been connected'),
        findsOneWidget,
      );
      expect(pending.isCompleted, isFalse);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(ByteData.sublistView(_loopingGif));
      await _drainNativeWork(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('close works while the chair clip is still loading', (
    tester,
  ) async {
    final pending = Completer<ByteData>();
    final bundle = _AnimationBundle(clip: () => pending.future);
    var closeCount = 0;
    await _pumpPage(tester, bundle, onClose: () => closeCount++);
    await tester.tap(find.byTooltip('Close sign in'));
    expect(closeCount, 1);
    expect(pending.isCompleted, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(ByteData.sublistView(_loopingGif));
    await _drainNativeWork(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chair loops repeatedly without reloading the clip', (
    tester,
  ) async {
    final bundle = _AnimationBundle();
    await _pumpPage(tester, bundle);
    await _waitFor(tester, () => find.byKey(_frameKey).evaluate().isNotEmpty);
    expect(await _framePixel(tester), [255, 0, 0, 255]);
    for (var loop = 0; loop < 3; loop++) {
      await _waitForPixel(tester, [0, 255, 0, 255]);
      await _waitForPixel(tester, [0, 0, 255, 255]);
      await _waitForPixel(tester, [255, 0, 0, 255]);
    }
    expect(bundle.clipLoads, 1);
    expect(find.byKey(_stillKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuild and hot reload keep the loop; a new entry starts anew', (
    tester,
  ) async {
    final bundle = _AnimationBundle();
    await _pumpPage(tester, bundle);
    await _waitFor(tester, () => find.byKey(_frameKey).evaluate().isNotEmpty);
    await _waitForPixel(tester, [0, 255, 0, 255]);
    await _pumpPage(tester, bundle);
    final reassemble = tester.binding.reassembleApplication();
    await tester.pump();
    await reassemble;
    await _waitForPixel(tester, [0, 0, 255, 255]);
    await _waitForPixel(tester, [255, 0, 0, 255]);
    expect(bundle.clipLoads, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpPage(tester, bundle);
    await _waitFor(tester, () => find.byKey(_frameKey).evaluate().isNotEmpty);
    expect(bundle.clipLoads, 2);
    expect(await _framePixel(tester), [255, 0, 0, 255]);
    expect(tester.takeException(), isNull);
  });

  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      accessibleNavigation
          ? 'accessible navigation pauses motion until disabled'
          : 'reduced motion pauses animation until disabled',
      (tester) async {
        final bundle = _AnimationBundle();
        await _pumpPage(
          tester,
          bundle,
          disableAnimations: !accessibleNavigation,
          accessibleNavigation: accessibleNavigation,
        );
        await _drainNativeWork(tester);
        _expectSettled(tester);
        expect(bundle.clipLoads, 0);
        expect(tester.binding.transientCallbackCount, 0);
        for (final method in _methods) {
          expect(_methodAction(method).hitTestable(), findsOneWidget);
        }

        await _pumpPage(tester, bundle);
        await _waitFor(
          tester,
          () => find.byKey(_frameKey).evaluate().isNotEmpty,
        );
        await _waitForPixel(tester, [0, 255, 0, 255]);
        expect(bundle.clipLoads, 1);
        await _pumpPage(
          tester,
          bundle,
          disableAnimations: !accessibleNavigation,
          accessibleNavigation: accessibleNavigation,
        );
        await _drainNativeWork(tester);
        _expectSettled(tester);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('background pauses the loop and foreground restarts it', (
    tester,
  ) async {
    final bundle = _AnimationBundle();
    await _pumpPage(tester, bundle);
    await _waitFor(tester, () => find.byKey(_frameKey).evaluate().isNotEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    await _drainNativeWork(tester);
    expect(bundle.clipLoads, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await _waitFor(
      tester,
      () =>
          bundle.clipLoads == 2 && find.byKey(_frameKey).evaluate().isNotEmpty,
    );
    await _waitForPixel(tester, [0, 255, 0, 255]);
    await _waitForPixel(tester, [0, 0, 255, 255]);
    await _waitForPixel(tester, [255, 0, 0, 255]);
    expect(bundle.clipLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TickerMode pauses an obscured page and resumes its loop', (
    tester,
  ) async {
    final bundle = _AnimationBundle();
    await _pumpPage(tester, bundle);
    await _waitFor(tester, () => find.byKey(_frameKey).evaluate().isNotEmpty);
    await _pumpPage(tester, bundle, tickersEnabled: false);
    await _drainNativeWork(tester);
    _expectSettled(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(bundle.clipLoads, 1);

    await _pumpPage(tester, bundle);
    await _waitFor(tester, () => find.byKey(_frameKey).evaluate().isNotEmpty);
    await _waitForPixel(tester, [0, 255, 0, 255]);
    expect(bundle.clipLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late clip data cannot animate a page that is no longer visible',
    (tester) async {
      final pending = Completer<ByteData>();
      final bundle = _AnimationBundle(clip: () => pending.future);
      await _pumpPage(tester, bundle);
      expect(bundle.clipLoads, 1);
      await _pumpPage(tester, bundle, tickersEnabled: false);
      pending.complete(ByteData.sublistView(_loopingGif));
      await _drainNativeWork(tester);
      await tester.pump(const Duration(seconds: 30));
      await _drainNativeWork(tester);
      _expectSettled(tester);
      expect(bundle.clipLoads, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing as native codec setup starts handles late completion', (
    tester,
  ) async {
    final bundle = _AnimationBundle();
    await _pumpPage(tester, bundle);
    expect(bundle.clipLoads, 1);

    // Do not wait for an engine frame. Leave while clip setup/decode is pending.
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainNativeWork(tester);
    await tester.pump(const Duration(seconds: 30));
    await _drainNativeWork(tester);
    expect(find.byKey(_frameKey), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final corrupt in [false, true]) {
    testWidgets(
      corrupt
          ? 'corrupt clip preserves the still and usable account controls'
          : 'missing clip preserves the still and usable account controls',
      (tester) async {
        final bundle = _AnimationBundle(
          clip: () async {
            if (!corrupt) throw FlutterError('Missing test animation asset');
            return ByteData.sublistView(Uint8List.fromList([0, 1, 2, 3]));
          },
        );
        await _pumpPage(tester, bundle);
        await _finishTake(tester);
        _expectSettled(tester);
        expect(bundle.clipLoads, 1);
        expect(tester.takeException(), isNull);
        await tester.tap(_methodAction('email'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('email sign-in preview'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _methodAction(String method) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      widget.properties.label == 'Continue with $method',
);

void _expectSettled(WidgetTester tester) {
  expect(find.byKey(_frameKey), findsNothing);
  final still = tester.widget<Image>(find.byKey(_stillKey));
  expect((still.image as AssetImage).assetName, _stillAsset);
}

Future<List<int>> _framePixel(WidgetTester tester) async {
  final frame = tester.widget<RawImage>(find.byKey(_frameKey));
  final data = await tester.runAsync(
    () => frame.image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return data!.buffer.asUint8List().take(4).toList();
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 40 && !ready(); i++) {
    await _drainNativeWork(tester);
  }
  expect(ready(), isTrue, reason: 'The native codec did not deliver a frame.');
}

Future<void> _waitForPixel(WidgetTester tester, List<int> expected) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await _drainNativeWork(tester);
    if (find.byKey(_frameKey).evaluate().isEmpty) break;
    final pixel = await _framePixel(tester);
    if (pixel.join(',') == expected.join(',')) return;
  }
  fail('The next authored animation color $expected was never displayed.');
}

Future<void> _drainNativeWork(WidgetTester tester) async {
  // Codec completion comes from the engine's IO thread, outside fake test time.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 5)),
  );
  await tester.pump();
}

Future<void> _finishTake(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await _drainNativeWork(tester);
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  _AnimationBundle bundle, {
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  bool tickersEnabled = true,
  VoidCallback? onClose,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _drainNativeWork(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'Dejanire Sans'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 47, bottom: 34),
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: TickerMode(enabled: tickersEnabled, child: child!),
        ),
        home: ReviewAccountOptionsPage(signIn: true, onClose: onClose ?? () {}),
      ),
    ),
  );
}

class _AnimationBundle extends CachingAssetBundle {
  _AnimationBundle({Future<ByteData> Function()? clip})
    : _clip = clip ?? (() async => ByteData.sublistView(_loopingGif));

  final Future<ByteData> Function() _clip;
  final loadedAssets = <String>[];
  int clipLoads = 0;

  @override
  Future<ByteData> load(String key) async {
    loadedAssets.add(key);
    if (key == _clipAsset) {
      clipLoads++;
      return _clip();
    }
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    }
    if (key.endsWith('.png') || key.endsWith('.webp')) {
      return ByteData.sublistView(_whitePng);
    }
    return rootBundle.load(key);
  }
}
