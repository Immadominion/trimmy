import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/craft.dart';
import 'package:trimmy/design_study/document_desk.dart';
import 'package:trimmy/design_study/mission.dart';
import 'package:trimmy/design_study/progress.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'only the active paper accepts keyboard focus, reduced=$reduced',
      (tester) async {
        final before = FocusNode(debugLabel: 'before');
        final headline = FocusNode(debugLabel: 'headline');
        final source = FocusNode(debugLabel: 'source');
        final after = FocusNode(debugLabel: 'after');
        addTearDown(() {
          before.dispose();
          headline.dispose();
          source.dispose();
          after.dispose();
        });
        var opened = false;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return Column(
                      children: [
                        TextButton(
                          focusNode: before,
                          onPressed: () {},
                          child: const Text('Before desk'),
                        ),
                        StudyDocumentDesk(
                          sourceOpen: opened,
                          headline: SelectableText(
                            'Visible headline',
                            focusNode: headline,
                          ),
                          source: SelectableText(
                            'Source figure',
                            focusNode: source,
                          ),
                        ),
                        TextButton(
                          focusNode: after,
                          onPressed: () {},
                          child: const Text('After desk'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        before.requestFocus();
        await tester.pump();
        var reachedHeadline = false;
        for (var i = 0; i < 6; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          reachedHeadline |= headline.hasFocus;
          expect(source.hasFocus, isFalse);
        }
        expect(reachedHeadline, isTrue);
        headline.requestFocus();
        await tester.pump();
        expect(headline.hasFocus, isTrue);
        update(() => opened = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(headline.hasFocus, isFalse);
        expect(headline.canRequestFocus, isFalse);
        expect(source.canRequestFocus, isTrue);
        await tester.pumpAndSettle();
        source.requestFocus();
        await tester.pump();
        expect(source.hasFocus, isTrue);
        update(() => opened = false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(source.hasFocus, isFalse);
        expect(source.canRequestFocus, isFalse);
        expect(headline.canRequestFocus, isTrue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('outgoing answer loses focus before its correction fade finishes', (
    tester,
  ) async {
    final repository = OfficeProgressRepository(
      read: (_) => null,
      write: (_, _) async => true,
    );
    await repository.startActivity('check-the-date');
    await repository.advance();
    await repository.advance();
    await repository.selectChoice('keep-headline');
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityStudy(
          repository: repository,
          activity: checkTheDateActivity,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final oldChoice = find.text('Keep the headline');
    final oldFocus = Focus.of(tester.element(oldChoice));
    oldFocus.requestFocus();
    await tester.pump();
    expect(oldFocus.hasFocus, isTrue);
    final submit = tester.widget<CraftButton>(
      find.ancestor(
        of: find.text('Submit answer'),
        matching: find.byType(CraftButton),
      ),
    );
    // Invoke the existing action without moving focus to the persistent footer.
    // This exercises a stage change while the previous choice has focus.
    submit.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(repository.state.active!.stage, 3);
    expect(
      oldChoice,
      findsOneWidget,
      reason: 'The old choice is still mounted for its fade.',
    );
    final outgoingFocus = Focus.of(tester.element(oldChoice));
    expect(outgoingFocus.canRequestFocus, isFalse);
    expect(outgoingFocus.hasFocus, isFalse);
    outgoingFocus.requestFocus();
    await tester.pump();
    expect(outgoingFocus.hasFocus, isFalse);
    expect(
      find.text('Your progress could not be saved. Please try again.'),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
