import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_amount_picker.dart';
import 'package:trimmy/ui_review/review_components.dart';
import 'package:trimmy/ui_review/review_feedback.dart';
import 'package:trimmy/ui_review/review_first_play.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  testWidgets(
    'company guide blocks amounts until a company is explicitly chosen',
    (tester) async {
      await _mount(
        tester,
        ReviewFirstPlayPage(onExit: () {}, onComplete: (_) {}),
      );
      expect(find.byKey(const ValueKey('company-guide')), findsOneWidget);
      expect(_reviewButton(tester).onPressed, isNull);

      await tester.ensureVisible(find.text('\$50'));
      await tester.tap(find.text('\$50'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_amount(tester), 100);
      await tester.ensureVisible(
        find.byTooltip('Increase amount by 100 dollars'),
      );
      await tester.tap(
        find.byTooltip('Increase amount by 100 dollars'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(_amount(tester), 100);
      expect(find.byKey(const ValueKey('company-guide')), findsOneWidget);
      expect(find.byKey(const ValueKey('amount-guide')), findsNothing);

      await _tap(tester, find.text('Nvidia'));
      expect(find.byKey(const ValueKey('company-guide')), findsNothing);
      expect(find.byKey(const ValueKey('amount-guide')), findsOneWidget);
      expect(_selected(tester, 'Nvidia, NVDA'), isTrue);
      await _tap(tester, find.text('\$50'));
      expect(_amount(tester), 50);
      await _tap(tester, find.byTooltip('Increase amount by 50 dollars'));
      expect(_amount(tester), 100);
      expect(_reviewButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Hint toggles all controls and resumes the appropriate guide stage',
    (tester) async {
      await _mount(
        tester,
        ReviewFirstPlayPage(onExit: () {}, onComplete: (_) {}),
      );
      await _tap(tester, find.text('Hint'));
      expect(find.byKey(const ValueKey('company-guide')), findsNothing);
      await _tap(tester, find.text('\$25'));
      expect(_amount(tester), 25);
      expect(_reviewButton(tester).onPressed, isNull);
      await _tap(tester, find.text('Hint'));
      expect(find.byKey(const ValueKey('company-guide')), findsOneWidget);

      await _tap(tester, find.text('Microsoft'));
      expect(find.byKey(const ValueKey('amount-guide')), findsOneWidget);
      await tester.ensureVisible(find.text('Apple'));
      await tester.tap(find.text('Apple'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_selected(tester, 'Microsoft, MSFT'), isTrue);
      expect(_selected(tester, 'Apple, AAPL'), isFalse);

      await _tap(tester, find.text('Hint'));
      expect(find.byKey(const ValueKey('amount-guide')), findsNothing);
      await _tap(tester, find.text('Apple'));
      expect(_selected(tester, 'Apple, AAPL'), isTrue);
      await _tap(tester, find.text('\$100'));
      expect(_amount(tester), 100);
      await _tap(tester, find.text('Hint'));
      expect(find.byKey(const ValueKey('amount-guide')), findsOneWidget);
      expect(find.byKey(const ValueKey('company-guide')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cleared custom input disables review and confirmed decimals carry through',
    (tester) async {
      ReviewPracticePosition? completed;
      await _mount(
        tester,
        ReviewFirstPlayPage(
          onExit: () {},
          onComplete: (value) => completed = value,
        ),
      );
      await _tap(tester, find.text('Nvidia'));
      await _tap(tester, find.byKey(const ValueKey('review-amount-edit')));
      final field = find.byKey(const ValueKey('review-amount-input'));
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount.'), findsOneWidget);
      expect(_reviewButton(tester).onPressed, isNull);
      await tester.tap(find.text('Review buy'));
      await tester.pumpAndSettle();
      expect(find.text('Review your buy.'), findsNothing);
      expect(completed, isNull);

      await tester.enterText(field, '42.75');
      await tester.pumpAndSettle();
      expect(_amount(tester), 42.75);
      expect(_reviewButton(tester).onPressed, isNotNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Review buy'));
      expect(find.text('\$42.75'), findsOneWidget);
      expect(completed, isNull);
      await _tap(tester, find.text('Confirm buy'));
      expect(completed?.symbol, 'NVDA');
      expect(completed?.amount, 42.75);
      expect(completed?.shares, .342);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full page handles 320-wide large text and keyboard while X stays reachable',
    (tester) async {
      var exits = 0;
      await _mount(
        tester,
        ReviewFirstPlayPage(
          onExit: () => exits++,
          onComplete: (_) {},
          initialPosition: ReviewPracticePosition.example,
        ),
        size: const Size(320, 720),
        textScale: 2,
        keyboardInset: 300,
      );
      await _tap(tester, find.byKey(const ValueKey('review-amount-edit')));
      final field = find.byKey(const ValueKey('review-amount-input'));
      await tester.enterText(field, '123.45');
      await tester.pumpAndSettle();
      expect(_amount(tester), 123.45);
      expect(tester.takeException(), isNull);
      final close = find.byTooltip('Skip first trade');
      expect(close.hitTestable(), findsOneWidget);
      await tester.tap(close);
      await tester.pump();
      expect(exits, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

double _amount(WidgetTester tester) =>
    tester.widget<ReviewAmountPicker>(find.byType(ReviewAmountPicker)).value;

ReviewPrimaryButton _reviewButton(WidgetTester tester) =>
    tester.widget<ReviewPrimaryButton>(
      find.widgetWithText(ReviewPrimaryButton, 'Review buy'),
    );

bool? _selected(WidgetTester tester, String label) => tester
    .widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      ),
    )
    .properties
    .selected;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(393, 852),
  double textScale = 1,
  double keyboardInset = 0,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'Dejanire Sans'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
          padding: const EdgeInsets.only(top: 24, bottom: 24),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child!,
      ),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}
