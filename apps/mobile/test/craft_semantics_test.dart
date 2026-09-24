import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/craft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [('Manrope', 'manrope'), ('Rubik', 'rubik')]) {
      await (FontLoader(font.$1)..addFont(
            rootBundle.load('assets/fonts/${font.$2}/${font.$1}-Variable.ttf'),
          ))
          .load();
    }
  });

  testWidgets(
    'enabled button exposes its role and invokes one semantic action',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CraftButton(
              label: 'Compare all the shares',
              detail: 'Harbor has 400 shares.',
              glyph: 'report',
              onPressed: () => calls++,
            ),
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(CraftButton));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.label, 'Compare all the shares\nHarbor has 400 shares.');
      expect(
        tester.getSemantics(find.text('Harbor has 400 shares.')).id,
        node.id,
        reason: 'The label and explanation form one actionable control.',
      );
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(calls, 1);
    },
  );

  testWidgets(
    'disabled floor button remains identifiable without a tap action',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CraftButton(
              label: 'Count the fees',
              detail: 'Complete the previous activity first',
              onPressed: null,
            ),
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(CraftButton));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(
        data.label,
        'Count the fees\nComplete the previous activity first',
      );
      expect(data.flagsCollection.isFocused, Tristate.none);
    },
  );

  testWidgets('selection stays merged and readable at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(22),
            child: StatefulBuilder(
              builder: (context, setState) => CraftButton(
                label: 'Keep all three checks',
                detail: 'Company value, fees and concentration.',
                selected: selected,
                onPressed: () => setState(() => selected = !selected),
              ),
            ),
          ),
        ),
      ),
    );
    final button = find.byType(CraftButton);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(button).getSemanticsData().flagsCollection.isSelected,
      Tristate.isFalse,
    );
    await tester.tap(find.text('Keep all three checks'));
    await tester.pumpAndSettle();
    final data = tester.getSemantics(button).getSemanticsData();
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    expect(
      data.label,
      'Keep all three checks\nCompany value, fees and concentration.',
    );
    expect(tester.takeException(), isNull);
  });
}
