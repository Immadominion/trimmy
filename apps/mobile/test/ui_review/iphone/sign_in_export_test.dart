import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_optional_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const capturePath = String.fromEnvironment('TRIMMY_SIGN_IN_CAPTURE');
  if (capturePath.isNotEmpty) {
    testWidgets('capture actual settled sign-in layout in widget harness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        for (final entry in {
          'Dejanire Sans': 'assets/fonts/dejanire/DejanireSans-Regular.otf',
          'Bricolage Grotesque':
              'assets/fonts/bricolage/BricolageGrotesque-Variable.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(rootBundle.load(entry.value));
          await loader.load();
        }
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(useMaterial3: true, fontFamily: 'Dejanire Sans'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 47, bottom: 34),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: ReviewAccountOptionsPage(signIn: true, onClose: () {}),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (final path in [
          'assets/images/ui_review/sal-chair-welcome-v3-still.png',
          'assets/images/ui_review/icons8/account-apple-rounded.png',
          'assets/images/ui_review/icons8/account-google-rounded.png',
          'assets/images/ui_review/icons8/account-x-standalone-rounded.png',
        ]) {
          await precacheImage(AssetImage(path), boundary.currentContext!);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Welcome back.'), findsOneWidget);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 3);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        image.dispose();
        await File(capturePath).writeAsBytes(png.buffer.asUint8List());
      });
    });
  }

  test(
    'actual chair export decodes and ends on its matching alpha poster',
    () async {
      final clip = await rootBundle.load(
        'assets/images/ui_review/sal-chair-welcome-v3.webp',
      );
      final poster = await rootBundle.load(
        'assets/images/ui_review/sal-chair-welcome-v3-still.png',
      );
      final codec = await ui.instantiateImageCodec(
        clip.buffer.asUint8List(clip.offsetInBytes, clip.lengthInBytes),
      );
      final stillCodec = await ui.instantiateImageCodec(
        poster.buffer.asUint8List(poster.offsetInBytes, poster.lengthInBytes),
      );
      addTearDown(codec.dispose);
      addTearDown(stillCodec.dispose);
      expect(codec.frameCount, greaterThan(20));
      expect(codec.repetitionCount, 0);

      var duration = Duration.zero;
      ByteData? first;
      ByteData? last;
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 960);
        expect(frame.image.height, 800);
        duration += frame.duration;
        if (i == 0 || i == codec.frameCount - 1) {
          final bytes = await frame.image.toByteData();
          if (i == 0) first = bytes;
          if (i == codec.frameCount - 1) last = bytes;
        }
        frame.image.dispose();
      }
      expect(duration.inMilliseconds, closeTo(3500, 2));
      final still = await stillCodec.getNextFrame();
      final target = (await still.image.toByteData())!;
      still.image.dispose();
      expect(last!.lengthInBytes, target.lengthInBytes);

      var changedPixels = 0;
      var alphaDifference = 0;
      var colorDifference = 0;
      var colorSamples = 0;
      for (var p = 0; p < target.lengthInBytes; p += 4) {
        if ((first!.getUint8(p + 3) - last.getUint8(p + 3)).abs() > 8 ||
            (first.getUint8(p) - last.getUint8(p)).abs() > 12) {
          changedPixels++;
        }
        alphaDifference += (last.getUint8(p + 3) - target.getUint8(p + 3))
            .abs();
        if (target.getUint8(p + 3) > 240) {
          for (var c = 0; c < 3; c++) {
            colorDifference += (last.getUint8(p + c) - target.getUint8(p + c))
                .abs();
            colorSamples++;
          }
        }
      }
      expect(changedPixels, greaterThan(1000));
      expect(alphaDifference / (960 * 800), lessThan(2));
      expect(colorDifference / colorSamples, lessThan(8));
      for (final pixel in [0, 959, 960 * 799, 960 * 800 - 1]) {
        expect(target.getUint8(pixel * 4 + 3), 0);
        expect(last.getUint8(pixel * 4 + 3), 0);
      }
    },
  );
}
