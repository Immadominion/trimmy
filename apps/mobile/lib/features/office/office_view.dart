import 'package:flutter/material.dart';
import '../../design/components.dart';
import '../../design/graphic.dart';
import '../../design/theme.dart';
import '../journey/journey_catalog.dart';
import '../journey/journey_screen.dart';
import '../practice/practice_controller.dart';
import 'sheets.dart';

class OfficeView extends StatelessWidget {
  const OfficeView({super.key, required this.controller});
  final PracticeController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeSession;
    final next = active == null
        ? controller.nextChapter
        : journeyChapterById(active.chapterId);
    final done = controller.completedChapterIds.length;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 21;
    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your daily office',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: TrimmyColors.muted,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          done == 0 ? 'Good to\nsee you.' : 'Look at\nyou grow.',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: 37,
            height: 1.06,
            letterSpacing: -1.8,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'A little curiosity.\nA fresh perspective.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: TrimmyColors.muted,
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (largeText) ...[
          greeting,
          const Center(child: SizedBox(height: 210, child: AdaPortrait())),
        ] else
          SizedBox(
            height: 218,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 10, child: greeting),
                const Expanded(
                  flex: 11,
                  child: SizedBox(
                    height: 218,
                    child: AdaPortrait(fit: BoxFit.cover),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                next == null
                    ? 'Three sessions, a fresh start'
                    : active == null
                    ? 'Up next'
                    : 'Right where you left off',
                style: const TextStyle(
                  color: TrimmyColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Practice',
              style: TextStyle(
                color: TrimmyColors.pine,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          next?.title ?? 'That’s a good beginning.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          next?.subtitle ??
              'Your notes are waiting in the journal. Revisit a session whenever you like.',
          style: const TextStyle(color: TrimmyColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 20),
        TactileButton(
          label: next == null
              ? 'Open my journal'
              : active == null
              ? 'Start session'
              : 'Continue session',
          reducedMotion: controller.reduceMotion,
          onPressed: () => next == null
              ? controller.setTab(2)
              : openJourney(context, controller, next.id),
        ),
        const SizedBox(height: 34),
        Row(
          children: [
            Expanded(
              child: Text(
                'Your path',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            GraphicIcon(TrimmySymbol.spark, size: 17, color: TrimmyColors.pine),
            const SizedBox(width: 6),
            Text(
              '${controller.learningPoints} points',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TrimmyColors.pine,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < journeyChapters.length; i++)
          _PathStop(
            chapter: journeyChapters[i],
            index: i,
            last: i == journeyChapters.length - 1,
            controller: controller,
          ),
        const SizedBox(height: 26),
        const Divider(),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GraphicIcon(TrimmySymbol.office, size: 31),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Better with another point of view.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Save an offer for someone you’d like at your desk.',
                    style: TextStyle(color: TrimmyColors.muted, fontSize: 13),
                  ),
                  TextButton(
                    onPressed: () => showTrimmySheet(
                      context,
                      InviteSheet(controller: controller),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    child: const Text('Draft an offer'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Practice sessions and drafts stay on this device. No real stocks or money move here.',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: TrimmyColors.muted,
          ),
        ),
      ],
    );
  }
}

class _PathStop extends StatelessWidget {
  const _PathStop({
    required this.chapter,
    required this.index,
    required this.last,
    required this.controller,
  });
  final JourneyChapter chapter;
  final int index;
  final bool last;
  final PracticeController controller;
  @override
  Widget build(BuildContext context) {
    final done = controller.completedChapterIds.contains(chapter.id);
    final unlocked = controller.isChapterUnlocked(chapter.id);
    final active = controller.activeSession;
    final canOpen =
        unlocked && (active == null || active.chapterId == chapter.id);
    final color = done
        ? TrimmyColors.yellow
        : unlocked
        ? TrimmyColors.pine
        : const Color(0xFFE7E6E0);
    final label = done
        ? 'Revisit session'
        : unlocked
        ? 'About 3 minutes'
        : 'After ${journeyChapters[index - 1].title.toLowerCase()}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              children: [
                Semantics(
                  label: done
                      ? 'Completed'
                      : unlocked
                      ? 'Available'
                      : 'Locked',
                  child: Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      shape: squircle(18),
                      color: color,
                    ),
                    child: done
                        ? const GraphicIcon(TrimmySymbol.check, size: 26)
                        : unlocked
                        ? const GraphicIcon(
                            TrimmySymbol.spark,
                            size: 26,
                            color: Colors.white,
                          )
                        : const Icon(
                            Icons.lock_outline_rounded,
                            size: 22,
                            color: TrimmyColors.muted,
                          ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        constraints: const BoxConstraints(minHeight: 18),
                        color: TrimmyColors.line,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: InkWell(
                customBorder: squircle(14),
                onTap: canOpen
                    ? () => openJourney(context, controller, chapter.id)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        !canOpen && unlocked
                            ? 'Finish your current session first'
                            : label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: TrimmyColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
