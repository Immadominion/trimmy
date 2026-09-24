// Exports actual production widgets for visual review; never runs on a device.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/account/guest_desk_preserved_screen.dart';
import 'package:trimmy/product/account/guest_desk_recovery_screen.dart';
import 'package:trimmy/product/app/launch_moments.dart';
import 'package:trimmy/product/career/career.dart';
import 'package:trimmy/product/design/product_theme.dart';

void main() {
  testWidgets('review production state screens at phone sizes', (tester) async {
    for (final font in [
      ('Dejanire Sans', 'dejanire/DejanireSans-Regular.otf'),
      ('Bricolage Grotesque', 'bricolage/BricolageGrotesque-Variable.ttf'),
    ]) {
      await (FontLoader(
        font.$1,
      )..addFont(rootBundle.load('assets/fonts/${font.$2}'))).load();
    }
    final output = Directory('/tmp/trimmy-design-system-review')
      ..createSync(recursive: true);
    final pages = <String, Widget>{
      'saved-desk': GuestDeskPreservedScreen(onContinue: () {}),
      'expired-saved-desk': GuestDeskPreservedScreen(
        expired: true,
        onContinue: () {},
      ),
      'guest-recovery': GuestDeskRecoveryScreen(
        onSignIn: () {},
        onStartNew: () async {},
      ),
      'promotion': PromotionMoment(
        receipt: CareerPromotionReceipt(
          mutationId: 'visual-review',
          fromRank: CareerRank.rookie,
          toRank: CareerRank.analyst,
          careerRevision: 7,
          trimsAwarded: 100,
          promotedAt: DateTime.utc(2026, 9, 24),
        ),
        onContinue: () {},
      ),
      'day-complete': DayOneMoment(onContinue: () {}),
    };
    for (final scale in [1.0, 2.0]) {
      final size = scale == 1 ? const Size(390, 844) : const Size(320, 640);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final entry in pages.entries) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: productTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: RepaintBoundary(key: boundary, child: entry.value),
            ),
          ),
        );
        await tester.runAsync(() async {
          for (final element in find.byType(Image).evaluate()) {
            await precacheImage((element.widget as Image).image, element);
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${output.path}/${entry.key}-${scale.toInt()}x.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
