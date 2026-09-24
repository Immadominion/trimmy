import 'package:flutter/material.dart';
import '../../design/components.dart';
import '../../design/graphic.dart';
import '../../design/theme.dart';
import '../practice/practice_controller.dart';
import 'journey_catalog.dart';

final _openJourneys = Expando<bool>('open journey routes');

Future<void> openJourney(
  BuildContext context,
  PracticeController controller,
  String chapterId,
) async {
  if (_openJourneys[controller] == true) return;
  _openJourneys[controller] = true;
  try {
    await controller.startJourney(chapterId);
    if (!context.mounted) return;
    controller.cue('paper_open.wav');
    final still =
        controller.reduceMotion || MediaQuery.disableAnimationsOf(context);
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: still
            ? Duration.zero
            : const Duration(milliseconds: 230),
        reverseTransitionDuration: still
            ? Duration.zero
            : const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            JourneyScreen(controller: controller),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: const Offset(.04, 0), end: Offset.zero)
                    .animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              ),
            ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your current session is safe. Continue it from the office.',
          ),
        ),
      );
    }
  } finally {
    _openJourneys[controller] = false;
  }
}

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key, required this.controller});
  final PracticeController controller;
  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  late final note = TextEditingController(
    text: widget.controller.activeSession?.reflection ?? '',
  );
  final scroll = ScrollController();
  JourneyChapter? finished;
  bool busy = false;
  bool awarded = false;
  bool leaving = false;
  String? error;

  @override
  void dispose() {
    note.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> leave() async {
    if (leaving || busy) return;
    leaving = true;
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.controller.flushPendingWrites();
    if (!mounted) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick this up later?'),
        content: Text(
          widget.controller.storageWarning == null
              ? 'Your place, answers and note are saved on this device.'
              : 'Your progress is available in this session, but device storage is unavailable. Keep the app open to return to it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay here'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave session'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
    leaving = false;
  }

  Future<void> advance() async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final controller = widget.controller;
      final step = controller.currentJourneyStep;
      if (step?.kind == JourneyStepKind.reflection) {
        final id = controller.activeSession!.chapterId;
        awarded = !controller.completedChapterIds.contains(id);
        final chapter = journeyChapterById(id);
        await controller.completeJourney();
        if (!mounted) return;
        setState(() => finished = chapter);
        controller.cue('arrival.wav');
      } else {
        await controller.advanceJourney();
        controller.cue('soft_tap.wav');
      }
      if (scroll.hasClients) scroll.jumpTo(0);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Choose a response and add your reflection before finishing.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final session = controller.activeSession;
      final step = controller.currentJourneyStep;
      final chapter = session == null
          ? finished
          : journeyChapterById(session.chapterId);
      return PopScope(
        canPop: finished != null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) leave();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFEDEEEB),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ColoredBox(
                color: TrimmyColors.paper,
                child: SafeArea(
                  child: finished != null
                      ? _completion(context, controller)
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 24, 8),
                              child: Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Leave session',
                                    onPressed: leave,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Semantics(
                                      label: 'Session progress',
                                      value:
                                          '${(session?.stepIndex ?? 0) + 1} of ${chapter?.steps.length ?? 5}',
                                      child: Row(
                                        children: List.generate(
                                          chapter?.steps.length ?? 5,
                                          (i) => Expanded(
                                            child: Container(
                                              height: 8,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 3,
                                                  ),
                                              decoration: ShapeDecoration(
                                                shape: squircle(4),
                                                color:
                                                    i <
                                                        (session?.stepIndex ??
                                                            0)
                                                    ? TrimmyColors.pine
                                                    : i ==
                                                          (session?.stepIndex ??
                                                              0)
                                                    ? TrimmyColors.yellow
                                                    : TrimmyColors.line,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: scroll,
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  16,
                                  24,
                                  28,
                                ),
                                child: step == null
                                    ? const Text(
                                        'Your session is saved. Return to the office to continue.',
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            chapter?.title ?? 'Your session',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: TrimmyColors.muted,
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                          if (step.kind ==
                                              JourneyStepKind.intro) ...[
                                            const Center(
                                              child: SizedBox(
                                                height: 205,
                                                child: AdaPortrait(),
                                              ),
                                            ),
                                            const SizedBox(height: 22),
                                          ],
                                          Text(
                                            step.title,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.headlineMedium,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            step.body,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              height: 1.6,
                                              color: TrimmyColors.muted,
                                            ),
                                          ),
                                          if (step.kind ==
                                              JourneyStepKind.decision) ...[
                                            const SizedBox(height: 24),
                                            Text(
                                              step.question,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                            const SizedBox(height: 18),
                                            for (
                                              var i = 0;
                                              i < step.choices.length;
                                              i++
                                            )
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 12,
                                                ),
                                                child: _DecisionChoice(
                                                  label: step.choices[i].label,
                                                  selected:
                                                      session?.answers[step
                                                          .id] ==
                                                      i,
                                                  onTap: busy
                                                      ? null
                                                      : () {
                                                          controller
                                                              .answerJourney(i);
                                                          controller.cue(
                                                            'soft_tap.wav',
                                                          );
                                                        },
                                                ),
                                              ),
                                            if (controller.journeyFeedback !=
                                                null) ...[
                                              const SizedBox(height: 12),
                                              Semantics(
                                                liveRegion: true,
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    20,
                                                  ),
                                                  decoration: ShapeDecoration(
                                                    color:
                                                        TrimmyColors.paleGreen,
                                                    shape: squircle(20),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Row(
                                                        children: [
                                                          GraphicIcon(
                                                            TrimmySymbol.spark,
                                                            size: 18,
                                                            color: TrimmyColors
                                                                .pine,
                                                          ),
                                                          SizedBox(width: 8),
                                                          Text(
                                                            'Ada’s take',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color:
                                                                  TrimmyColors
                                                                      .pine,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Text(
                                                        controller
                                                            .journeyFeedback!,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          height: 1.55,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                          if (step.kind ==
                                              JourneyStepKind.reflection) ...[
                                            const SizedBox(height: 24),
                                            Text(
                                              step.question,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                            const SizedBox(height: 18),
                                            TextField(
                                              readOnly: busy,
                                              controller: note,
                                              minLines: 4,
                                              maxLines: 8,
                                              maxLength: 500,
                                              textCapitalization:
                                                  TextCapitalization.sentences,
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'A note to your future self',
                                                hintText:
                                                    'One thing I’ll look at differently…',
                                                alignLabelWithHint: true,
                                              ),
                                              onChanged: (value) => controller
                                                  .updateJourneyReflection(
                                                    value,
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Your words belong to you. Saved in your journal on this device.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: TrimmyColors.muted,
                                              ),
                                            ),
                                          ],
                                          if (controller.storageWarning !=
                                              null) ...[
                                            const SizedBox(height: 16),
                                            Text(
                                              controller.storageWarning!,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: TrimmyColors.loss,
                                              ),
                                            ),
                                          ],
                                          if (error != null) ...[
                                            const SizedBox(height: 16),
                                            Text(
                                              error!,
                                              style: const TextStyle(
                                                color: TrimmyColors.loss,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                12,
                                24,
                                20,
                              ),
                              child: TactileButton(
                                label: busy
                                    ? 'Saving…'
                                    : step?.kind == JourneyStepKind.reflection
                                    ? 'Finish session'
                                    : step?.kind == JourneyStepKind.intro
                                    ? 'Let’s get into it'
                                    : 'Continue',
                                reducedMotion: controller.reduceMotion,
                                onPressed: busy || !controller.canAdvanceJourney
                                    ? null
                                    : advance,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _completion(
    BuildContext context,
    PracticeController controller,
  ) => Column(
    children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 18),
              const GraphicIcon(
                TrimmySymbol.spark,
                size: 78,
                color: TrimmyColors.yellow,
              ),
              const SizedBox(height: 28),
              Text(
                awarded
                    ? 'A new perspective.\nThat’s progress.'
                    : 'A fresh look.\nStill yours.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 18),
              Text(
                '${finished?.title ?? 'Session'} complete',
                textAlign: TextAlign.center,
                style: const TextStyle(color: TrimmyColors.muted),
              ),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 12,
                children: [
                  StatusTag(
                    awarded ? '+30 learning points' : 'Reflection updated',
                    color: TrimmyColors.yellow,
                  ),
                  StatusTag(
                    '${controller.currentStreak} day${controller.currentStreak == 1 ? '' : 's'} of curiosity',
                    color: TrimmyColors.paleGreen,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: ShapeDecoration(
                  shape: squircle(22),
                  color: Colors.white,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'A thought worth keeping',
                      style: TextStyle(
                        fontSize: 12,
                        color: TrimmyColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectionArea(
                      child: Text(
                        note.text.trim(),
                        style: const TextStyle(fontSize: 16, height: 1.55),
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.storageWarning != null) ...[
                const SizedBox(height: 16),
                Text(
                  controller.storageWarning!,
                  style: const TextStyle(
                    color: TrimmyColors.loss,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          children: [
            TactileButton(
              label: 'Back to the office',
              reducedMotion: controller.reduceMotion,
              onPressed: () {
                controller.setTab(0);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                controller.setTab(2);
                Navigator.pop(context);
              },
              child: const Text('Read my journal'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _DecisionChoice extends StatelessWidget {
  const _DecisionChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? TrimmyColors.paleGreen : Colors.white,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? TrimmyColors.pine : TrimmyColors.line,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        customBorder: squircle(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 21,
                color: selected ? TrimmyColors.pine : TrimmyColors.muted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
