import 'package:flutter/material.dart';
import '../../design/components.dart';
import '../../core/calendar_scope.dart';
import '../../design/graphic.dart';
import '../../design/theme.dart';
import '../practice/practice_controller.dart';

class HabitSheet extends StatelessWidget {
  const HabitSheet({super.key, required this.controller});
  final PracticeController controller;
  @override
  Widget build(BuildContext context) {
    final today = CalendarScope.todayOf(context, controller.currentLocalDate);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHeading('A little, often.'),
          const SizedBox(height: 24),
          const GraphicIcon(
            TrimmySymbol.flame,
            size: 64,
            color: TrimmyColors.pine,
          ),
          const SizedBox(height: 18),
          Text(
            '${controller.currentStreak} day${controller.currentStreak == 1 ? '' : 's'} of curiosity',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            controller.activeToday
                ? 'You made time for a new perspective today.'
                : 'Complete a new session and leave a reflection to mark today.',
            style: const TextStyle(color: TrimmyColors.muted),
          ),
          const SizedBox(height: 26),
          Row(
            children: List.generate(7, (index) {
              final date = DateTime(
                monday.year,
                monday.month,
                monday.day + index,
              );
              final key =
                  '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              final active = controller.activityDates.contains(key);
              return Expanded(
                child: Semantics(
                  label:
                      '$key, ${active ? 'practice complete' : 'no completed practice'}',
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      Text(
                        const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                        style: const TextStyle(
                          fontSize: 11,
                          color: TrimmyColors.muted,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Container(
                        width: 34,
                        height: 39,
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          shape: squircle(12),
                          color: active
                              ? TrimmyColors.pine
                              : TrimmyColors.white,
                          shadows: [],
                        ),
                        child: active
                            ? const GraphicIcon(
                                TrimmySymbol.check,
                                size: 22,
                                color: Colors.white,
                              )
                            : Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: date == today
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
          Text(
            'Longest run: ${controller.longestStreak} days',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'A day counts once, however many new sessions you finish. Replays keep your notes fresh without adding points or days. Miss a day? Your learning and notes are still yours.',
            style: TextStyle(fontSize: 13, color: TrimmyColors.muted),
          ),
          if (controller.clockWarning != null) ...[
            const SizedBox(height: 14),
            Text(
              controller.clockWarning!,
              style: const TextStyle(color: TrimmyColors.loss, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          TactileButton(
            label: 'Back to the office',
            trailing: false,
            reducedMotion: controller.reduceMotion,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
