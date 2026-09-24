// Repeatable visual export of the finished game journey. No account or device.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/career_review_page.dart';
import 'package:trimmy/design_study/craft.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';
import 'package:trimmy/design_study/progress.dart';

void main() {
  testWidgets('export first review at phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final font in [('Manrope', 'manrope'), ('Rubik', 'rubik')]) {
      await (FontLoader(font.$1)..addFont(
            rootBundle.load('assets/fonts/${font.$2}/${font.$1}-Variable.ttf'),
          ))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    var progress = OfficeProgress.empty();
    for (final id in practiceCatalogActivityIds) {
      progress = progress.startActivity(id).advance().advance();
      if (id == 'check-the-sample') {
        progress = progress
            .selectAnswerPart('amount', 'eight-of-ten')
            .selectAnswerPart('group', 'testers');
      } else if (id == 'prepare-the-update') {
        for (final part in ['dated-growth', 'lower-profit', 'trial-result']) {
          progress = progress.selectAnswerPart(part, 'included');
        }
      } else {
        progress = progress.selectChoice(
          practiceCatalogById[id]!.correctChoiceId,
        );
      }
      progress = progress
          .submitChoice(DateTime.utc(2026, 9, 17))
          .closeActivity();
    }
    final repository = OfficeProgressRepository(
      read: (key) => key == OfficeProgressRepository.saveKey
          ? jsonEncode(progress.toJson())
          : null,
      write: (_, _) async => throw StateError('Review must never write.'),
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Manrope',
          colorScheme: ColorScheme.fromSeed(
            seedColor: StudyColor.pine,
            surface: StudyColor.paper,
            onSurface: StudyColor.ink,
            primary: StudyColor.pine,
          ),
          textTheme: const TextTheme(
            bodyMedium: TextStyle(fontSize: 16, height: 1.45),
          ),
        ),
        home: RepaintBoundary(
          key: boundary,
          child: CareerReviewPage(repository: repository),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/ada-acting-v1.webp'),
        tester.element(find.byType(CareerReviewPage)),
      );
    });
    await tester.pumpAndSettle();
    final output = Directory('../../art/studies/runtime/career-review')
      ..createSync(recursive: true);
    Future<void> capture(String name) => tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${output.path}/$name.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    });
    await capture('entry-390');
    await tester.ensureVisible(find.byKey(const ValueKey('review-floor-3')));
    await tester.tap(find.byKey(const ValueKey('review-floor-3')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('review-folder-3')));
    await tester.pumpAndSettle();
    await capture('team-folder-390');
    await tester.ensureVisible(find.text('Keep it fresh.'));
    await tester.pumpAndSettle();
    await capture('next-steps-390');
    expect(tester.takeException(), isNull);
  });
}
