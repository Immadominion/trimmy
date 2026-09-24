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
  testWidgets('export company update and remembered office', (tester) async {
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
    progress = progress
        .startActivity('check-the-sample')
        .advance()
        .advance()
        .selectAnswerPart('amount', 'eight-of-ten')
        .selectAnswerPart('group', 'testers')
        .submitChoice(DateTime.utc(2026, 9, 14))
        .closeActivity();
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
    final out = Directory('../../art/studies/runtime/update-v1')
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

    await capture('01-office-three-completed');
    await tap(find.text('Start activity'));
    await capture('02-update-brief');
    await tap(find.text('Open your notes'));
    await capture('03-folder-growth');
    await tap(find.byKey(const ValueKey('update-tab-profit')));
    await capture('04-folder-profit');
    await tap(find.byKey(const ValueKey('update-tab-trial')));
    await capture('05-folder-trial');
    await tap(find.text('Build the update'));
    await capture('06-update-empty');
    await tap(find.byKey(const ValueKey('update-fact-dated-growth')));
    await capture('07-update-partial');
    await tap(find.byKey(const ValueKey('update-fact-lower-profit')));
    await tap(find.byKey(const ValueKey('update-fact-all-customers')));
    await capture('08-update-ready');
    await tap(find.text('Review with Ada'));
    await capture('09-update-correction');
    await tap(find.text('File the corrected update'));
    await capture('10-update-filed');
    await tap(find.text('Back to your office'));
    await capture('11-office-update');
    await tap(find.text('Update filed'));
    await capture('12-journal-draft');
    await tester.ensureVisible(find.text('Ada’s reply'));
    await tester.pumpAndSettle();
    await capture('13-journal-ada');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
