import 'package:flutter/material.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../practice/practice_controller.dart';
import 'sheets.dart';

class DeskView extends StatefulWidget {
  const DeskView({super.key, required this.controller});
  final PracticeController controller;
  @override
  State<DeskView> createState() => _DeskViewState();
}

class _DeskViewState extends State<DeskView> {
  int period = 0;
  static const samples = [
    [10.0, 9.86, 9.94, 10.13, 10.02, 10.18, 10.24],
    [10.0, 10.04, 9.87, 10.12, 10.08, 10.24],
  ];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Your own point of view.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 10),
      const Text(
        'A little room to understand what a position means.',
        style: TextStyle(color: TrimmyColors.muted),
      ),
      const SizedBox(height: 28),
      SquirclePanel(
        border: true,
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusTag(
              'Fictional portfolio',
              color: TrimmyColors.paleGreen,
            ),
            const SizedBox(height: 22),
            const Text(
              'Illustrative value',
              style: TextStyle(color: TrimmyColors.muted),
            ),
            const SizedBox(height: 6),
            Text(
              r'$10.24',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              r'+$0.24 (+2.4%) in this example',
              style: TextStyle(
                color: TrimmyColors.pine,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < 2; i++)
                  ChoiceChip(
                    label: Text(i == 0 ? 'Week example' : 'Season example'),
                    selected: period == i,
                    showCheckmark: false,
                    selectedColor: TrimmyColors.yellow,
                    side: BorderSide.none,
                    onSelected: (_) => setState(() => period = i),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Semantics(
              label:
                  'Fictional value chart. Starts at 10 dollars, ends at 10 dollars and 24 cents. Values fall as well as rise.',
              image: true,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 210,
                  child: Row(
                    children: [
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            r'$10.40',
                            style: TextStyle(
                              fontSize: 11,
                              color: TrimmyColors.muted,
                            ),
                          ),
                          Text(
                            r'$10.10',
                            style: TextStyle(
                              fontSize: 11,
                              color: TrimmyColors.muted,
                            ),
                          ),
                          Text(
                            r'$9.80',
                            style: TextStyle(
                              fontSize: 11,
                              color: TrimmyColors.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _ValueChart(samples[period]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Start of example',
                    style: TextStyle(fontSize: 11, color: TrimmyColors.muted),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'End of example',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 11, color: TrimmyColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'These are made-up prices for exploring the interface. They are not historical or live market data.',
              style: TextStyle(fontSize: 12, color: TrimmyColors.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 32),
      const SectionTitle('The positions'),
      const _Holding(
        name: 'Aster Labs',
        initials: 'a',
        description: 'Fictional technology company',
        value: r'$7.30',
        change: r'+$0.30',
        positive: true,
        color: TrimmyColors.yellow,
      ),
      const Divider(height: 24),
      const _Holding(
        name: 'Northstar Energy',
        initials: 'n',
        description: 'Fictional energy company',
        value: r'$2.94',
        change: r'−$0.06',
        positive: false,
        color: Color(0xFFE6E1F4),
      ),
      const SizedBox(height: 32),
      SquirclePanel(
        color: TrimmyColors.paleGreen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.lightbulb_outline_rounded,
              size: 24,
              color: TrimmyColors.pine,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The number is only part of the story.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Keep a note about why a position makes sense to you. Your future self will appreciate the context.',
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => openBrief(context, widget.controller),
                    child: const Text('Explore the first brief'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Holding extends StatelessWidget {
  const _Holding({
    required this.name,
    required this.initials,
    required this.description,
    required this.value,
    required this.change,
    required this.positive,
    required this.color,
  });
  final String name, initials, description, value, change;
  final bool positive;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InitialAvatar(initials, color: color, size: 46),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      const SizedBox(width: 14),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 5),
          Text(
            change,
            style: TextStyle(
              color: positive ? TrimmyColors.pine : TrimmyColors.loss,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ],
  );
}

class _ValueChart extends CustomPainter {
  _ValueChart(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = TrimmyColors.line
      ..strokeWidth = .8;
    for (final y in [0.0, size.height / 2, size.height]) {
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + 3).clamp(0, size.width), y),
          grid,
        );
      }
    }
    final path = Path();
    Offset last = Offset.zero;
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        i * (size.width - 8) / (values.length - 1),
        size.height * (1 - (values[i] - 9.8) / .6),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      last = point;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = TrimmyColors.pine
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(last, 7, Paint()..color = TrimmyColors.white);
    canvas.drawCircle(last, 4.5, Paint()..color = TrimmyColors.pine);
  }

  @override
  bool shouldRepaint(covariant _ValueChart oldDelegate) =>
      oldDelegate.values != values;
}
