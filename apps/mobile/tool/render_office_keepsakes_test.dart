// Visual review export, not a product test or device verification record.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/craft.dart';
import 'package:trimmy/design_study/office_keepsakes.dart';
import 'package:trimmy/design_study/office_scene.dart';

void main() {
  testWidgets('export filed evidence at actual phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 470);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final font in [
      ('Manrope', 'manrope/Manrope-Variable.ttf'),
      ('Rubik', 'rubik/Rubik-Variable.ttf'),
    ]) {
      await (FontLoader(
        font.$1,
      )..addFont(rootBundle.load('assets/fonts/${font.$2}'))).load();
    }
    final semantics = tester.ensureSemantics();
    try {
      final boundary = GlobalKey();
      var opens = 0;
      final output = Directory('../../art/studies/runtime/office-keepsakes-v2')
        ..createSync(recursive: true);

      Future<void> compose(Set<String> ids, {double textScale = 1}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Manrope'),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 470),
                textScaler: TextScaler.linear(textScale),
                disableAnimations: textScale == 2,
              ),
              child: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  backgroundColor: StudyColor.paper,
                  body: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: OfficeScene(
                                activityId: 'check-the-date',
                                onOpen: null,
                              ),
                            ),
                            Positioned(
                              left: 12,
                              bottom: 10,
                              child: OfficeKeepsakes(
                                completedActivityIds: ids,
                                onOpenNotes: () => opens++,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Office evidence • component study'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          for (final name in ['office-scene-v4.webp', 'office-desk-v5.webp']) {
            await precacheImage(
              AssetImage('assets/images/$name'),
              tester.element(find.byType(OfficeScene)),
            );
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) => tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${output.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });

      await compose({'unknown-future-activity'});
      expect(find.bySemanticsLabel(RegExp('Filed evidence:')), findsNothing);
      const orderedIds = [
        'check-the-date',
        'sales-and-profit',
        'check-the-sample',
        'prepare-the-update',
      ];
      const labels = [
        '2025',
        'Costs checked',
        '8 of 10 testers',
        'Update filed',
      ];
      for (var count = 1; count <= orderedIds.length; count++) {
        // Deliberately reverse insertion order: filing follows authored order.
        final ids = orderedIds.take(count).toList().reversed.toSet();
        for (final scale in [1.0, 2.0]) {
          await compose(ids, textScale: scale);
          expect(find.text(labels[count - 1]), findsOneWidget);
          final target = find.bySemanticsLabel(RegExp('Filed evidence:'));
          expect(target, findsOneWidget);
          expect(tester.getSize(target).width, scale == 1 ? 132 : 156);
          expect(tester.getSize(target).height, greaterThanOrEqualTo(52));
          await capture('$count-notes-text-${(scale * 100).round()}');
        }
      }
      final target = find.bySemanticsLabel(
        'Filed evidence: report year 2025; costs checked; '
        'survey result, 8 of 10 testers; '
        'company update with date, profit and trial result.',
      );
      expect(target, findsOneWidget);
      await tester.tap(target);
      expect(opens, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });
}
