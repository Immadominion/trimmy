// A visual review exporter; passing this does not approve the art or motion.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('export actual office handoff frames', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    for (final font in [
      ('Manrope', 'manrope/Manrope-Variable.ttf'),
      ('Rubik', 'rubik/Rubik-Variable.ttf'),
    ]) {
      await (FontLoader(
        font.$1,
      )..addFont(rootBundle.load('assets/fonts/${font.$2}'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    // This Flutter test lives under tool/ because it exports review images.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: OfficeStudy(preferences: preferences),
      ),
    );
    await tester.runAsync(() async {
      for (final name in [
        'office-scene-v4.webp',
        'office-desk-v5.webp',
        'ada-acting-v1.webp',
        'ada-graphic-v2.webp',
      ]) {
        await precacheImage(
          AssetImage('assets/images/$name'),
          tester.element(find.byType(OfficeStudy)),
        );
      }
    });
    await tester.pumpAndSettle();
    final out = Directory('../../art/studies/runtime/office-v5')
      ..createSync(recursive: true);
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${out.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('01-office');
    await tester.tap(find.text('Start activity'));
    await tester.pump();
    await tester.pump();
    for (final sample in [
      (80, '02-flight-80ms'),
      (80, '03-flight-160ms'),
      (80, '04-flight-240ms'),
      (100, '05-flight-340ms'),
      (220, '06-activity'),
    ]) {
      await tester.pump(Duration(milliseconds: sample.$1));
      await capture(sample.$2);
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
