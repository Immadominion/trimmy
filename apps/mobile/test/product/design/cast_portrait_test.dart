import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/cast_portrait.dart';
import 'package:trimmy/product/design/product_theme.dart';

void main() {
  testWidgets('all cast portraits are bundled and keep their image labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(
          body: Wrap(
            children: [
              for (final member in ProductCastMember.values)
                CastPortrait(member: member, size: 72),
            ],
          ),
        ),
      ),
    );

    for (final element in find.byType(Image).evaluate()) {
      final portrait = element.widget as Image;
      await tester.runAsync(() => precacheImage(portrait.image, element));
    }
    await tester.pump();

    for (final member in ProductCastMember.values) {
      expect(
        find.byKey(ValueKey('cast-portrait-${member.name}')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(member.semanticName), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
