import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/update_assignment.dart';
import 'package:trimmy/design_study/update_composer.dart';
import 'package:trimmy/design_study/update_evidence.dart';

Widget _paper(
  Widget child, {
  double textScale = 1,
  bool systemReduceMotion = false,
  bool accessibleNavigation = false,
}) => MaterialApp(
  theme: ThemeData(fontFamily: 'Manrope'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: systemReduceMotion,
      accessibleNavigation: accessibleNavigation,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: child,
        ),
      ),
    ),
  ),
);

void _phone(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _fact(String id) => find.byKey(ValueKey('update-fact-$id'));
Finder _tab(String id) => find.byKey(ValueKey('update-tab-$id'));

double _offset(WidgetTester tester, String key) =>
    tester.widget<Transform>(find.byKey(ValueKey(key))).transform.storage[13];

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final entry in [
      ('Manrope', 'assets/fonts/manrope/Manrope-Variable.ttf'),
      ('Rubik', 'assets/fonts/rubik/Rubik-Variable.ttf'),
    ]) {
      await (FontLoader(entry.$1)..addFont(rootBundle.load(entry.$2))).load();
    }
  });

  testWidgets(
    'folder exposes all three accurate sources without selecting facts',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(_paper(const UpdateEvidenceFolder()));
      expect(find.text('Published February 2026'), findsOneWidget);
      expect(find.text('100,000'), findsOneWidget);
      expect(find.text('180,000'), findsOneWidget);
      expect(find.text('80% growth, from 2024 to 2025.'), findsOneWidget);
      expect(
        find.text('The report does not measure growth in 2026.'),
        findsOneWidget,
      );

      await _tap(tester, _tab('profit'));
      expect(find.text('Aster user report'), findsNothing);
      expect(find.text('2024 and 2025 · Simplified USD'), findsOneWidget);
      for (final amount in [
        r'$1,000',
        r'$1,500',
        r'$600',
        r'$1,300',
        r'$400',
        r'$200',
      ]) {
        expect(find.text(amount), findsOneWidget);
      }
      expect(find.text(r'Profit fell from $400 to $200.'), findsOneWidget);
      await _tap(tester, _tab('trial'));
      expect(find.text('Aster sales and costs'), findsNothing);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('10 invited beta testers'), findsOneWidget);
      expect(find.text('Replies'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Liked Aster'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('Not for me'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
        find.text(
          'All ten invited testers replied. Other customers were not asked.',
        ),
        findsOneWidget,
      );
      expect(find.byType(UpdateComposer), findsNothing);
      expect(find.byKey(const ValueKey('update-pin-count')), findsNothing);
      await _tap(tester, _tab('growth'));
      expect(find.text('Aster user report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('source tabs reflow at 200 percent and retain 48px targets', (
    tester,
  ) async {
    _phone(tester, width: 320);
    await tester.pumpWidget(_paper(const UpdateEvidenceFolder(), textScale: 2));
    for (final id in ['growth', 'profit', 'trial']) {
      await _tap(tester, _tab(id));
      await tester.pumpAndSettle();
      final size = tester.getSize(_tab(id));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull, reason: 'Source $id at 200%');
    }
    expect(
      tester.getTopLeft(_tab('trial')).dy,
      greaterThan(tester.getTopLeft(_tab('growth')).dy),
    );
    await _tap(tester, _tab('profit'));
    expect(
      find.byType(Table),
      findsNothing,
      reason: 'Large text uses stacked year records',
    );
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text(r'$1,300'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'source arrival is finite, interrupts immediately and disposes safely',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(_paper(const UpdateEvidenceFolder()));
      await _tap(tester, _tab('profit'));
      await tester.pump(const Duration(milliseconds: 70));
      expect(_offset(tester, 'update-source-arrival'), greaterThan(0));
      expect(_offset(tester, 'update-source-arrival'), lessThan(6));
      await tester.pumpWidget(
        _paper(const UpdateEvidenceFolder(reduceMotion: true)),
      );
      expect(_offset(tester, 'update-source-arrival'), 0);
      await _tap(tester, _tab('trial'));
      expect(_offset(tester, 'update-source-arrival'), 0);
      await tester.pumpWidget(_paper(const UpdateEvidenceFolder()));
      await _tap(tester, _tab('growth'));
      await tester.pump(const Duration(milliseconds: 220));
      expect(_offset(tester, 'update-source-arrival'), 0);
      await _tap(tester, _tab('profit'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('both system motion settings hold source changes immediately', (
    tester,
  ) async {
    _phone(tester);
    for (final accessible in [false, true]) {
      await tester.pumpWidget(
        _paper(
          const UpdateEvidenceFolder(),
          systemReduceMotion: !accessible,
          accessibleNavigation: accessible,
        ),
      );
      await _tap(tester, _tab(accessible ? 'trial' : 'profit'));
      expect(_offset(tester, 'update-source-arrival'), 0);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pin waits for acknowledged parts and keeps the empty draft compact',
    (tester) async {
      _phone(tester);
      final changes = <(String, String)>[];
      void select(String id, String value) => changes.add((id, value));
      await tester.pumpWidget(
        _paper(UpdateComposer(parts: const {}, onSelect: select)),
      );
      expect(find.text('0 of 3 facts pinned'), findsOneWidget);
      final strip = find.byKey(const ValueKey('update-empty-positions'));
      expect(tester.getSize(strip).height, 48);
      expect(
        tester.getTopLeft(_fact('current-growth')).dy,
        lessThan(250),
        reason: 'Empty rows must leave room for the desk facts',
      );
      for (final fact in updateFacts) {
        expect(_fact(fact.id), findsOneWidget);
        expect(
          find.text(fact.detail!),
          findsNothing,
          reason: 'Composer must not reveal authored explanations',
        );
      }
      await _tap(tester, _fact('dated-growth'));
      expect(changes, [('dated-growth', 'included')]);
      expect(find.text('0 of 3 facts pinned'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('update-pinned-dated-growth')),
        findsNothing,
      );
      await tester.pumpWidget(
        _paper(
          UpdateComposer(
            parts: const {'dated-growth': 'included'},
            onSelect: select,
          ),
        ),
      );
      expect(find.text('1 of 3 facts pinned'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('update-pinned-dated-growth')),
        findsOneWidget,
      );
      expect(_fact('dated-growth'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'three pins require an acknowledged removal before another inclusion',
    (tester) async {
      _phone(tester);
      final changes = <(String, String)>[];
      void select(String id, String value) => changes.add((id, value));
      const three = {
        'dated-growth': 'included',
        'current-growth': 'included',
        'all-customers': 'included',
      };
      await tester.pumpWidget(
        _paper(UpdateComposer(parts: three, onSelect: select)),
      );
      expect(find.text('3 of 3 facts pinned'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('update-empty-positions')),
        findsNothing,
      );
      for (final id in ['lower-profit', 'trial-result']) {
        expect(tester.widget<OutlinedButton>(_fact(id)).onPressed, isNull);
      }
      final supported = tester.widget<Text>(
        find.byKey(const ValueKey('update-pinned-dated-growth')),
      );
      final unsupported = tester.widget<Text>(
        find.byKey(const ValueKey('update-pinned-current-growth')),
      );
      expect(
        unsupported.style,
        supported.style,
        reason: 'Inclusion must not mark correctness',
      );
      await _tap(tester, _fact('current-growth'));
      expect(changes, [('current-growth', 'excluded')]);
      expect(find.text('3 of 3 facts pinned'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(_fact('lower-profit')).onPressed,
        isNull,
      );
      await tester.pumpWidget(
        _paper(
          UpdateComposer(
            parts: const {
              'dated-growth': 'included',
              'current-growth': 'excluded',
              'all-customers': 'included',
            },
            onSelect: select,
          ),
        ),
      );
      expect(find.text('2 of 3 facts pinned'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(_fact('lower-profit')).onPressed,
        isNotNull,
      );
      await _tap(tester, _fact('lower-profit'));
      expect(changes.last, ('lower-profit', 'included'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled composer exposes no pin or unpin callback', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _paper(
        const UpdateComposer(
          parts: {'dated-growth': 'included'},
          onSelect: null,
        ),
      ),
    );
    expect(tester.widget<TextButton>(_fact('dated-growth')).onPressed, isNull);
    for (final fact in updateFacts.skip(1)) {
      expect(tester.widget<OutlinedButton>(_fact(fact.id)).onPressed, isNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'fact controls have full labels, large targets and keyboard activation',
    (tester) async {
      _phone(tester);
      final changes = <(String, String)>[];
      void select(String id, String value) => changes.add((id, value));
      await tester.pumpWidget(
        _paper(UpdateComposer(parts: const {}, onSelect: select)),
      );
      expect(
        find.bySemanticsLabel(
          'Pin fact. In 2025, users grew 80%. Source: User report.',
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(changes, [('current-growth', 'included')]);
      await tester.pumpWidget(
        _paper(
          UpdateComposer(
            parts: const {'dated-growth': 'included'},
            onSelect: select,
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Unpin fact. In 2025, users grew 80%. Source: User report.',
        ),
        findsOneWidget,
      );
      for (final fact in updateFacts) {
        final size = tester.getSize(_fact(fact.id));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'composer reflows every full claim and pinned claim at 200 percent',
    (tester) async {
      _phone(tester, width: 320);
      for (final parts in [
        <String, String>{},
        {
          'dated-growth': 'included',
          'trial-result': 'included',
          'all-customers': 'included',
        },
      ]) {
        await tester.pumpWidget(
          _paper(
            UpdateComposer(parts: parts, onSelect: (_, _) {}),
            textScale: 2,
          ),
        );
        for (final fact in updateFacts) {
          expect(find.text(fact.text), findsOneWidget);
          await tester.ensureVisible(_fact(fact.id));
          expect(
            tester.getSize(_fact(fact.id)).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.takeException(), isNull, reason: fact.id);
        }
      }
    },
  );

  testWidgets(
    'acknowledged paper motion is finite and either accessibility flag interrupts it',
    (tester) async {
      _phone(tester);
      void select(String _, String _) {}
      await tester.pumpWidget(
        _paper(UpdateComposer(parts: const {}, onSelect: select)),
      );
      await tester.pumpWidget(
        _paper(
          UpdateComposer(
            parts: const {'dated-growth': 'included'},
            onSelect: select,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(_offset(tester, 'update-position-motion-1'), greaterThan(0));
      await tester.pump(const Duration(milliseconds: 160));
      expect(_offset(tester, 'update-position-motion-1'), 0);
      for (final accessible in [false, true]) {
        await tester.pumpWidget(
          _paper(UpdateComposer(parts: const {}, onSelect: select)),
        );
        await tester.pumpWidget(
          _paper(
            UpdateComposer(
              parts: const {'current-growth': 'included'},
              onSelect: select,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(_offset(tester, 'update-position-motion-1'), greaterThan(0));
        await tester.pumpWidget(
          _paper(
            UpdateComposer(
              parts: const {'current-growth': 'included'},
              onSelect: select,
            ),
            systemReduceMotion: !accessible,
            accessibleNavigation: accessible,
          ),
        );
        expect(_offset(tester, 'update-position-motion-1'), 0);
        expect(
          tester
              .widget<OutlinedButton>(_fact('dated-growth'))
              .style!
              .animationDuration,
          Duration.zero,
          reason: 'Loose-note state changes must also respect reduced motion',
        );
      }
      await tester.pumpWidget(
        _paper(
          UpdateComposer(
            parts: const {'all-customers': 'included'},
            onSelect: select,
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
