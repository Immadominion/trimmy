import 'package:flutter/material.dart';

import 'craft.dart';

/// Filed evidence derived only from saved, first-time activity completions.
///
/// Place outside the room's source-image FittedBox: this is a logical-pixel
/// control, so its type and minimum 48-pixel target must not shrink with art.
/// The front slip follows activity order, not the iteration order of the Set.
class OfficeKeepsakes extends StatefulWidget {
  const OfficeKeepsakes({
    super.key,
    required this.completedActivityIds,
    this.onOpenNotes,
  });

  final Set<String> completedActivityIds;
  final VoidCallback? onOpenNotes;

  @override
  State<OfficeKeepsakes> createState() => _OfficeKeepsakesState();
}

class _OfficeKeepsakesState extends State<OfficeKeepsakes> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final filed = _evidence
        .where((item) => widget.completedActivityIds.contains(item.id))
        .toList(growable: false);
    if (filed.isEmpty) return const SizedBox.shrink();

    final latest = filed.last;
    final enabled = widget.onOpenNotes != null;
    final media = MediaQuery.of(context);
    // Keep the evidence itself fully scaled; the redundant caption can yield
    // space on a large-text phone without changing the semantic description.
    final showCaption = media.textScaler.scale(14) <= 20;
    final pressOffset =
        _pressed &&
            enabled &&
            !media.disableAnimations &&
            !media.accessibleNavigation
        ? 1.5
        : 0.0;
    final description =
        'Filed evidence: ${filed.map((item) => item.description).join('; ')}.';

    return SizedBox(
      // At large text, a little more desk width keeps words such as "checked"
      // intact while honoring the user's scale and the original type size.
      width: showCaption ? 132 : 156,
      child: Semantics(
        container: true,
        excludeSemantics: true,
        button: enabled,
        enabled: enabled,
        focusable: enabled,
        focused: enabled && _focused,
        label: description,
        hint: enabled ? 'Open Journal notes' : null,
        onTap: widget.onOpenNotes,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onOpenNotes,
            excludeFromSemantics: true,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            onFocusChange: (value) => setState(() => _focused = value),
            customBorder: studyShape(4),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            hoverColor: StudyColor.paper.withValues(alpha: .08),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: CustomPaint(
                painter: _FiledPaperPainter(
                  tabs: filed
                      .skip(filed.length > 4 ? filed.length - 4 : 0)
                      .map((item) => item.color)
                      .toList(growable: false),
                  focused: enabled && _focused,
                  pressOffset: pressOffset,
                ),
                child: Transform.translate(
                  offset: Offset(0, pressOffset),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(17, 12, 10, 9),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showCaption) ...[
                          Text(
                            latest.caption,
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 10,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              color: StudyColor.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          latest.label,
                          style: display(
                            14,
                          ).copyWith(height: 1.12, letterSpacing: -.25),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FiledEvidence {
  const _FiledEvidence({
    required this.id,
    required this.label,
    required this.caption,
    required this.description,
    required this.color,
  });

  final String id, label, caption, description;
  final Color color;
}

const _evidence = [
  _FiledEvidence(
    id: 'check-the-date',
    label: '2025',
    caption: 'Report year',
    description: 'report year 2025',
    color: StudyColor.pine,
  ),
  _FiledEvidence(
    id: 'sales-and-profit',
    label: 'Costs checked',
    caption: 'Report note',
    description: 'costs checked',
    color: StudyColor.yellow,
  ),
  _FiledEvidence(
    id: 'check-the-sample',
    label: '8 of 10 testers',
    caption: 'Survey note',
    description: 'survey result, 8 of 10 testers',
    color: StudyColor.pink,
  ),
  _FiledEvidence(
    id: 'prepare-the-update',
    label: 'Update filed',
    caption: 'Company update',
    description: 'company update with date, profit and trial result',
    color: StudyColor.violet,
  ),
  _FiledEvidence(
    id: 'compare-company-value',
    label: 'All shares counted',
    caption: 'Company value',
    description: 'total company stock-market values compared',
    color: StudyColor.pine,
  ),
  _FiledEvidence(
    id: 'count-the-fees',
    label: r'$9 in shares',
    caption: 'Fee checked',
    description: 'one dollar fee and nine dollars in shares',
    color: StudyColor.yellow,
  ),
  _FiledEvidence(
    id: 'check-concentration',
    label: '80% in Aster',
    caption: 'Holdings checked',
    description: 'eighty percent of the example holdings in Aster',
    color: StudyColor.pink,
  ),
  _FiledEvidence(
    id: 'prepare-the-comparison',
    label: 'Comparison filed',
    caption: 'Three checks',
    description: 'company value, fee and concentration comparison',
    color: StudyColor.violet,
  ),
  _FiledEvidence(
    id: 'review-team-update',
    label: 'Team action saved',
    caption: 'Nia’s update',
    description: 'qualified update or missing-cost request saved for Nia',
    color: StudyColor.pine,
  ),
  _FiledEvidence(
    id: 'read-returned-costs',
    label: 'Costs returned',
    caption: 'Team figures',
    description: 'Nia returned the missing fictional cost figures',
    color: StudyColor.yellow,
  ),
  _FiledEvidence(
    id: 'finish-team-update',
    label: 'Follow-up filed',
    caption: 'Team update',
    description: 'the saved team action was completed with returned figures',
    color: StudyColor.pink,
  ),
];

class _FiledPaperPainter extends CustomPainter {
  const _FiledPaperPainter({
    required this.tabs,
    required this.focused,
    required this.pressOffset,
  });

  final List<Color> tabs;
  final bool focused;
  final double pressOffset;

  Path _sheet(Size size, {double inset = 0}) => Path()
    ..moveTo(3 + inset, 9)
    ..lineTo(size.width - 5 - inset, 5)
    ..lineTo(size.width - 2 - inset, size.height - 5)
    ..lineTo(5 + inset, size.height - 2)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final sheet = _sheet(size);
    canvas.drawPath(
      sheet.shift(const Offset(0, 2)),
      paint..color = StudyColor.ink.withValues(alpha: .25),
    );

    // Earlier evidence remains as exposed paper edges and colored filing tabs.
    // There is one native-text front slip, so no tiny unreadable fake writing.
    for (var i = 0; i < tabs.length - 1; i++) {
      canvas.drawPath(
        _sheet(size, inset: 2.0 + i).shift(Offset(0, -2.0 - i * 1.5)),
        paint
          ..color = switch (i) {
            0 => StudyColor.mint,
            1 => const Color(0xFFF5E4AA),
            _ => const Color(0xFFF2DCE3),
          },
      );
    }
    // Tabs sit above every backing sheet; a fourth paper must not cover the
    // oldest filing color. The front sheet still occludes their lower edges.
    for (var i = 0; i < tabs.length - 1; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(14.0 + i * 25, 0, 22, 10),
          const Radius.circular(2),
        ),
        paint..color = tabs[i],
      );
    }

    canvas.save();
    canvas.translate(0, pressOffset);
    canvas.drawPath(sheet, paint..color = StudyColor.paper);
    canvas.drawPath(
      sheet,
      paint
        ..color = StudyColor.ink.withValues(alpha: .24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(3, 9)
        ..lineTo(9, 8.8)
        ..lineTo(11, size.height - 2.2)
        ..lineTo(5, size.height - 2)
        ..close(),
      paint..color = tabs.last,
    );
    canvas.restore();

    if (focused) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          const Radius.circular(4),
        ),
        paint
          ..color = StudyColor.pine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_FiledPaperPainter oldDelegate) =>
      oldDelegate.focused != focused ||
      oldDelegate.pressOffset != pressOffset ||
      oldDelegate.tabs.length != tabs.length ||
      List.generate(
        tabs.length,
        (i) => i,
      ).any((i) => oldDelegate.tabs[i] != tabs[i]);
}
