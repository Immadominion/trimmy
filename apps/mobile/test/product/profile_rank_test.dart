import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/product_motion_icon.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/profile/profile_screen.dart';

void main() {
  testWidgets('guest can sign in without a fabricated personal profile', (
    tester,
  ) async {
    var signIns = 0;
    var settings = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(
          body: ProfileScreen(
            handle: 'guest-internal-id',
            persona: '',
            signedIn: false,
            onSignIn: () => signIns++,
            onSettings: () => settings++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('@guest-internal-id'), findsNothing);
    expect(find.text('0 Trims'), findsNothing);
    expect(find.byType(ClipOval), findsNothing);
    expect(find.text('Sound, privacy and account'), findsNothing);
    final art = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => (image.image as AssetImage).assetName);
    expect(
      art,
      isNot(contains('assets/images/ui_review/rookie-briefcase-v1.png')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-save-desk')));
    expect(signIns, 1);
    await tester.tap(find.byKey(const ValueKey('profile-settings')));
    expect(settings, 1);
  });

  testWidgets('signed-in profile opens trader editing from its portrait', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(
          body: ProfileScreen(
            handle: 'joel',
            persona: 'The Oracle',
            signedIn: true,
            onSignIn: () {},
            onSettings: () {},
            onChangePersona: () => edits++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('@joel'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    final images = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => (image.image as AssetImage).assetName);
    expect(
      images,
      contains('assets/images/ui_review/persona-oracle-avatar-v1.png'),
    );
    await tester.tap(find.byTooltip('Change your trader'));
    expect(edits, 1);
  });

  testWidgets(
    'icon animation stops, respects reduced motion, replays on tab entry',
    (tester) async {
      var visible = false;
      var reduced = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                  enabled: visible,
                  child: const ProductMotionIcon(
                    file: 'goal-chart-animated.png',
                    animatedFile: 'goal-chart-animated.gif',
                  ),
                ),
              );
            },
          ),
        ),
      );
      String imageName() =>
          (tester.widget<Image>(find.byType(Image)).image as AssetImage)
              .assetName;
      expect(imageName(), endsWith('.png'));
      rebuild(() => visible = true);
      await tester.pump();
      expect(imageName(), endsWith('.gif'));
      await tester.pump(const Duration(seconds: 2));
      expect(imageName(), endsWith('.png'));
      rebuild(() {
        visible = false;
        reduced = true;
      });
      await tester.pump();
      rebuild(() => visible = true);
      await tester.pump();
      expect(imageName(), endsWith('.png'));
      rebuild(() => reduced = false);
      await tester.pump();
      expect(imageName(), endsWith('.gif'));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
