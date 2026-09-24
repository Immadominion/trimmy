import 'package:flutter/material.dart';
import '../../design/components.dart';
import '../../core/calendar_scope.dart';
import '../../design/graphic.dart';
import '../../design/theme.dart';
import '../journey/habit_sheet.dart';
import '../practice/practice_controller.dart';
import 'office_view.dart';
import 'desk_view.dart';
import 'journal_view.dart';
import 'sheets.dart';

/// Mobile composition, including its internal browser preview.
/// The separate stocks web client lives in apps/web.
class OfficeShell extends StatelessWidget {
  const OfficeShell({super.key, required this.controller});
  final PracticeController controller;
  static const titles = ['Office', 'Portfolio', 'Journal'];
  static const symbols = [
    TrimmySymbol.office,
    TrimmySymbol.portfolio,
    TrimmySymbol.journal,
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      CalendarScope.todayOf(context, controller.currentLocalDate);
      final noMotion =
          controller.reduceMotion || MediaQuery.disableAnimationsOf(context);
      final page = switch (controller.tab) {
        1 => DeskView(controller: controller),
        2 => JournalView(controller: controller),
        _ => OfficeView(controller: controller),
      };
      return Scaffold(
        backgroundColor: const Color(0xFFEDEEEB),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ColoredBox(
              color: TrimmyColors.paper,
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 12, 10),
                      child: Row(
                        children: [
                          const Expanded(child: TrimmyWordmark()),
                          Tooltip(
                            message: 'Your practice streak',
                            child: TextButton.icon(
                              onPressed: () => showTrimmySheet(
                                context,
                                HabitSheet(controller: controller),
                              ),
                              icon: GraphicIcon(
                                TrimmySymbol.flame,
                                size: 22,
                                color: controller.activeToday
                                    ? TrimmyColors.pine
                                    : TrimmyColors.ink,
                              ),
                              label: Text(
                                '${controller.currentStreak}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: TrimmyColors.ink,
                                minimumSize: const Size(56, 48),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Office settings',
                            onPressed: () => showTrimmySheet(
                              context,
                              SettingsSheet(controller: controller),
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 23),
                          ),
                        ],
                      ),
                    ),
                    if (controller.storageWarning != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            controller.storageWarning!,
                            style: const TextStyle(
                              color: TrimmyColors.loss,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: PageStorageKey('mobile-page-${controller.tab}'),
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                        child: AnimatedSwitcher(
                          duration: noMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          child: KeyedSubtree(
                            key: ValueKey(controller.tab),
                            child: page,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        color: TrimmyColors.paper,
                        border: Border(
                          top: BorderSide(color: TrimmyColors.line, width: .7),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Row(
                        children: [
                          for (var i = 0; i < 3; i++)
                            Expanded(
                              child: Semantics(
                                selected: controller.tab == i,
                                button: true,
                                label: titles[i],
                                excludeSemantics: true,
                                child: InkWell(
                                  customBorder: squircle(18),
                                  onTap: () {
                                    controller.setTab(i);
                                    controller.cue('soft_tap.wav');
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedContainer(
                                          duration: noMotion
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 140,
                                                ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 5,
                                          ),
                                          decoration: ShapeDecoration(
                                            shape: squircle(12),
                                            color: controller.tab == i
                                                ? TrimmyColors.yellow
                                                : Colors.transparent,
                                          ),
                                          child: GraphicIcon(
                                            symbols[i],
                                            size: 25,
                                            color: controller.tab == i
                                                ? TrimmyColors.ink
                                                : TrimmyColors.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          titles[i],
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: controller.tab == i
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: controller.tab == i
                                                ? TrimmyColors.ink
                                                : TrimmyColors.muted,
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
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class TrimmyWordmark extends StatelessWidget {
  const TrimmyWordmark({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Trimmy',
    excludeSemantics: true,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 29,
            height: 31,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: TrimmyColors.yellow,
              shape: squircle(11),
            ),
            child: const Text(
              't',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 27,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            'trimmy',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.6,
            ),
          ),
        ],
      ),
    ),
  );
}
