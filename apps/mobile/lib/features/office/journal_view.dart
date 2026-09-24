import 'package:flutter/material.dart';
import '../../design/components.dart';
import '../../design/graphic.dart';
import '../../design/theme.dart';
import '../journey/journey_catalog.dart';
import '../journey/journey_screen.dart';
import '../practice/practice_controller.dart';
import 'sheets.dart';

class JournalView extends StatelessWidget {
  const JournalView({super.key, required this.controller});
  final PracticeController controller;
  @override
  Widget build(BuildContext context) {
    final notes = controller.chapterCompletions.values.toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your journal.', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 10),
        const Text(
          'A record of how you see things.',
          style: TextStyle(color: TrimmyColors.muted),
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            const GraphicIcon(
              TrimmySymbol.spark,
              size: 22,
              color: TrimmyColors.pine,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${notes.length} session${notes.length == 1 ? '' : 's'} · ${controller.learningPoints} learning points',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        if (notes.isEmpty && controller.journalNote.isEmpty) ...[
          const Divider(),
          const SizedBox(height: 28),
          const GraphicIcon(
            TrimmySymbol.journal,
            size: 50,
            color: TrimmyColors.pine,
          ),
          const SizedBox(height: 22),
          Text(
            'It starts with one thought.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'At the end of each session, leave a note for your future self. This is where it will live.',
            style: TextStyle(color: TrimmyColors.muted),
          ),
          const SizedBox(height: 22),
          TactileButton(
            label: controller.activeSession == null
                ? 'Start my first session'
                : 'Continue my session',
            reducedMotion: controller.reduceMotion,
            onPressed: () => openJourney(
              context,
              controller,
              controller.activeSession?.chapterId ?? firstFloorChapter.id,
            ),
          ),
          const SizedBox(height: 20),
        ],
        for (final note in notes)
          _JournalEntry(
            title: journeyChapterById(note.chapterId)!.title,
            date: _date(note.completedAt),
            text: note.reflection,
            onRevisit:
                controller.activeSession == null ||
                    controller.activeSession?.chapterId == note.chapterId
                ? () => openJourney(context, controller, note.chapterId)
                : null,
          ),
        if (controller.journalNote.isNotEmpty)
          _JournalEntry(
            title: 'Your first question',
            date: 'Earlier field note',
            text: controller.journalNote,
            onRevisit: () => openBrief(context, controller),
          ),
        const SizedBox(height: 18),
        SectionTitle(
          'Draft offers',
          action: TextButton(
            onPressed: () =>
                showTrimmySheet(context, InviteSheet(controller: controller)),
            child: const Text('New draft'),
          ),
        ),
        if (controller.drafts.isEmpty)
          const Text(
            'An open seat. A friend with a different perspective. Your draft offers will collect here.',
            style: TextStyle(color: TrimmyColors.muted, fontSize: 14),
          ),
        for (final draft in controller.drafts.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SquirclePanel(
              border: true,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.mail_outline_rounded,
                        size: 22,
                        color: TrimmyColors.pine,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          draft.handle,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const StatusTag('Unsent'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SelectionArea(child: Text(draft.message)),
                  const SizedBox(height: 14),
                  Text(
                    'Saved ${_date(draft.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 28),
        const Text(
          'On this device only. Drafts are not sent and handles are not verified.',
          style: TextStyle(color: TrimmyColors.muted, fontSize: 11),
        ),
      ],
    );
  }

  String _date(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}

class _JournalEntry extends StatelessWidget {
  const _JournalEntry({
    required this.title,
    required this.date,
    required this.text,
    this.onRevisit,
  });
  final String title, date, text;
  final VoidCallback? onRevisit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 18),
        Text(
          date,
          style: const TextStyle(fontSize: 12, color: TrimmyColors.muted),
        ),
        const SizedBox(height: 10),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.only(left: 16),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: TrimmyColors.pine, width: 3),
            ),
          ),
          child: SelectionArea(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, height: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (onRevisit != null)
          TextButton(
            onPressed: onRevisit,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            child: const Text('Revisit this thought'),
          ),
      ],
    ),
  );
}
