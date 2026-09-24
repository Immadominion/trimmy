import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/document_desk.dart';

Widget _desk({
  required bool sourceOpen,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(2),
      disableAnimations: reduceMotion,
      accessibleNavigation: accessibleNavigation,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: StudyDocumentDesk(
          sourceOpen: sourceOpen,
          headline: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 180),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Headline paper'),
                SelectableText('This year, users grew 80%.'),
              ],
            ),
          ),
          source: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 340),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Source paper'),
                SelectableText('Annual report 2025'),
                Text('100,000 to 180,000 users'),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _readableContent(WidgetTester tester) => tester.semantics
    .simulatedAccessibilityTraversal()
    .map((node) {
      final data = node.getSemanticsData();
      return '${data.label} ${data.value}';
    })
    .join(' ');

double _height(WidgetTester tester) =>
    tester.getSize(find.byType(StudyDocumentDesk)).height;

void main() {
  testWidgets('only the active paper is exposed to assistive navigation', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_desk(sourceOpen: false));
    await tester.pumpAndSettle();
    expect(_readableContent(tester), contains('This year'));
    expect(_readableContent(tester), isNot(contains('2025')));
    expect(_readableContent(tester), isNot(contains('180,000')));

    await tester.pumpWidget(_desk(sourceOpen: true));
    await tester.pumpAndSettle();
    expect(_readableContent(tester), contains('Annual report 2025'));
    expect(_readableContent(tester), contains('180,000'));
    expect(_readableContent(tester), isNot(contains('This year')));

    await tester.pumpWidget(_desk(sourceOpen: false));
    await tester.pumpAndSettle();
    expect(_readableContent(tester), contains('This year'));
    expect(_readableContent(tester), isNot(contains('2025')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reversing midflight is continuous and parent disposal is safe', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_desk(sourceOpen: false));
    final closedHeight = _height(tester);
    await tester.pumpWidget(_desk(sourceOpen: true));
    await tester.pump(const Duration(milliseconds: 140));
    final interruptedHeight = _height(tester);
    expect(interruptedHeight, greaterThan(closedHeight));

    await tester.pumpWidget(_desk(sourceOpen: false));
    expect(_height(tester), interruptedHeight);
    await tester.pumpAndSettle();
    expect(_height(tester), closedHeight);

    await tester.pumpWidget(_desk(sourceOpen: true));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion and accessible navigation settle immediately', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_desk(sourceOpen: true));
    final openHeight = _height(tester);
    await tester.pumpWidget(_desk(sourceOpen: false));
    await tester.pumpAndSettle();
    final closedHeight = _height(tester);

    // Enabling the preference while the paper is travelling must finish it now.
    await tester.pumpWidget(_desk(sourceOpen: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_height(tester), lessThan(openHeight));
    await tester.pumpWidget(_desk(sourceOpen: true, reduceMotion: true));
    expect(_height(tester), openHeight);
    expect(_readableContent(tester), contains('Annual report 2025'));
    await tester.pump(const Duration(milliseconds: 30));
    expect(_height(tester), openHeight);

    await tester.pumpWidget(_desk(sourceOpen: false, reduceMotion: true));
    expect(_height(tester), closedHeight);
    await tester.pumpWidget(
      _desk(sourceOpen: true, accessibleNavigation: true),
    );
    expect(_height(tester), openHeight);
    expect(_readableContent(tester), isNot(contains('This year')));
    expect(tester.takeException(), isNull);
  });
}
