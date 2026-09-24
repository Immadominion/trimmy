// Review exports from real widgets; a pass does not approve art or motion.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('export third activity and filed evidence', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    for (final font in [
      ('Manrope', 'assets/fonts/manrope/Manrope-Variable.ttf'),
      ('Rubik', 'assets/fonts/rubik/Rubik-Variable.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    var progress = OfficeProgress.empty();
    for (final step in [
      ('check-the-date', 'add-year'),
      ('sales-and-profit', 'check-costs'),
    ]) {
      progress = progress
          .startActivity(step.$1)
          .advance()
          .advance()
          .selectChoice(step.$2)
          .submitChoice(DateTime.utc(2026, 9, 13))
          .closeActivity();
    }
    // Flutter test exporter is deliberately kept outside the product test suite.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      OfficeProgressRepository.saveKey: jsonEncode(progress.toJson()),
    });
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
    final out = Directory('../../art/studies/runtime/sample-v1')
      ..createSync(recursive: true);
    Future<void> capture(String name) async => tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${out.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await capture('01-office-two-completed');
    await tap(find.text('Start activity'));
    await capture('02-trial-brief');
    await tap(find.text('Open the replies'));
    await capture('03-trial-source');
    await tap(find.text('Write the headline'));
    await capture('04-headline-empty');
    await tap(find.byKey(const ValueKey('sample-amount-eight-of-ten')));
    await capture('05-headline-partial');
    await tap(find.byKey(const ValueKey('sample-group-customers')));
    await capture('06-headline-selected');
    await tap(find.text('Submit answer'));
    await capture('07-specific-correction');
    await tap(find.text('Use the trial results'));
    await capture('08-saved-outcome');
    await tap(find.text('Back to your office'));
    await capture('09-office-filed');
    await tap(find.text('Journal'));
    await capture('10-journal');
    await tester.ensureVisible(
      find.byKey(const ValueKey('journal-check-the-sample')),
    );
    await tester.pumpAndSettle();
    await capture('11-survey-first-headline');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
