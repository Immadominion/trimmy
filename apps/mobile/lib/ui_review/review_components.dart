import 'package:flutter/material.dart';

import 'ui_review_app.dart';
import 'review_feedback.dart';

const reviewDisplay = 'Bricolage Grotesque';

class ReviewPageScaffold extends StatelessWidget {
  const ReviewPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.subtitle,
    this.background = Colors.white,
    this.foreground = UiReviewColor.ink,
    this.onBack,
    this.trailing,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 28),
  });

  final String title;
  final String? eyebrow, subtitle;
  final Color background, foreground;
  final VoidCallback? onBack;
  final Widget? trailing, bottom;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: background,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: padding,
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          if (onBack != null) ...[
                            ReviewIconButton(
                              icon: Icons.arrow_back_rounded,
                              label: 'Back',
                              onPressed: onBack!,
                              foreground: foreground,
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (eyebrow != null)
                            Expanded(
                              child: Text(
                                eyebrow!.toUpperCase(),
                                style: TextStyle(
                                  color: foreground.withValues(alpha: .68),
                                  fontSize: 11,
                                  height: 1,
                                  letterSpacing: 1.15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          ?trailing,
                        ],
                      ),
                      const SizedBox(height: 19),
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: reviewDisplay,
                          color: foreground,
                          fontSize: 36,
                          height: .98,
                          letterSpacing: -1.35,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 9),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: foreground.withValues(alpha: .76),
                            fontSize: 15,
                            height: 1.42,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      child,
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (bottom != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                border: Border(
                  top: BorderSide(color: foreground.withValues(alpha: .12)),
                ),
              ),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: bottom!,
              ),
            ),
        ],
      ),
    ),
  );
}

class ReviewPrimaryButton extends StatefulWidget {
  const ReviewPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    this.background = UiReviewColor.pine,
    this.foreground = Colors.white,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color background, foreground;
  final bool fullWidth;

  @override
  State<ReviewPrimaryButton> createState() => _ReviewPrimaryButtonState();
}

class _ReviewPrimaryButtonState extends State<ReviewPrimaryButton> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final face = enabled ? widget.background : const Color(0xFFECEBF1);
    final contentColor = enabled
        ? widget.foreground
        : UiReviewColor.ink.withValues(alpha: .62);
    final child = Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedScale(
        duration: uiReviewDuration(context, pressed ? 70 : 150),
        scale: pressed && enabled ? .985 : 1,
        curve: Curves.easeOutCubic,
        child: Material(
          color: face,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    ReviewFeedback.shared.press();
                    widget.onPressed!();
                  }
                : null,
            onHighlightChanged: (value) => setState(() => pressed = value),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58, minWidth: 96),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisSize: widget.fullWidth
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.fullWidth && widget.icon != null)
                      const SizedBox(width: 24),
                    Flexible(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: contentColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(widget.icon, color: contentColor, size: 22),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return widget.fullWidth
        ? SizedBox(width: double.infinity, child: child)
        : child;
  }
}

class ReviewTextButton extends StatelessWidget {
  const ReviewTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = UiReviewColor.ink,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        textStyle: const TextStyle(
          fontFamily: 'Dejanire Sans',
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: Text(label),
    ),
  );
}

class ReviewIconButton extends StatelessWidget {
  const ReviewIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.foreground = UiReviewColor.ink,
    this.background,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      color: foreground,
      style: IconButton.styleFrom(
        backgroundColor: icon == Icons.close_rounded
            ? Colors.transparent
            : background ?? foreground.withValues(alpha: .08),
        minimumSize: const Size(48, 48),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(17),
        ),
      ),
      icon: Icon(icon, size: icon == Icons.close_rounded ? 29 : null),
    ),
  );
}

class ReviewChoice extends StatelessWidget {
  const ReviewChoice({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.color = UiReviewColor.lilac,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? color : Colors.white,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: selected ? UiReviewColor.ink : const Color(0xFFD8D1C2),
          width: selected ? 2 : 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? UiReviewColor.ink
                        : UiReviewColor.ink.withValues(alpha: .07),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: selected ? Colors.white : UiReviewColor.ink,
                  ),
                ),
                const SizedBox(width: 13),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: UiReviewColor.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: UiReviewColor.ink.withValues(alpha: .68),
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: UiReviewColor.pine,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ReviewSal extends StatelessWidget {
  const ReviewSal({
    super.key,
    this.mood = 'deadpan',
    this.width = 140,
    this.semanticLabel = 'Sal, your floor boss',
  });

  final String mood;
  final double width;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: semanticLabel,
    child: ExcludeSemantics(
      child: Image.asset(
        'assets/images/ui_review/sal/sal-$mood-v2.png',
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}

class ReviewSalMessage extends StatelessWidget {
  const ReviewSalMessage({
    super.key,
    required this.message,
    this.mood = 'deadpan',
    this.background = UiReviewColor.lemon,
  });

  final String message, mood;
  final Color background;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      ReviewSal(mood: mood, width: 92),
      const SizedBox(width: 9),
      Expanded(
        child: Container(
          margin: const EdgeInsets.only(bottom: 13),
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: UiReviewColor.ink, width: 1.4),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
              bottomRight: Radius.circular(22),
              bottomLeft: Radius.circular(5),
            ),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: UiReviewColor.ink,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  );
}

class ReviewPaper extends StatelessWidget {
  const ReviewPaper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = UiReviewColor.paper,
    this.shadow = true,
    this.border = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final bool shadow, border;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      border: border ? Border.all(color: UiReviewColor.ink, width: 1.4) : null,
      boxShadow: shadow
          ? const [BoxShadow(color: UiReviewColor.ink, offset: Offset(6, 7))]
          : null,
    ),
    child: Padding(padding: padding, child: child),
  );
}

class ReviewSectionLabel extends StatelessWidget {
  const ReviewSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Dejanire Sans',
            color: UiReviewColor.ink,
            fontSize: 21,
            height: 1.15,
            letterSpacing: -.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      ?trailing,
    ],
  );
}

class ReviewStat extends StatelessWidget {
  const ReviewStat({super.key, required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          maxLines: 1,
          style: const TextStyle(
            fontFamily: 'Dejanire Sans',
            color: UiReviewColor.ink,
            fontSize: 23,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          color: UiReviewColor.ink.withValues(alpha: .62),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class ReviewProgress extends StatelessWidget {
  const ReviewProgress({
    super.key,
    required this.value,
    this.color = UiReviewColor.violet,
    this.track = const Color(0xFFE4DECF),
    this.height = 10,
  });

  final double value, height;
  final Color color, track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: LinearProgressIndicator(
      minHeight: height,
      value: value.clamp(0, 1),
      color: color,
      backgroundColor: track,
    ),
  );
}

class ReviewPreviewNotice extends StatelessWidget {
  const ReviewPreviewNotice({
    super.key,
    this.text = 'UI preview. No money will move.',
  });

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: UiReviewColor.lemon,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: UiReviewColor.ink, width: 1.1),
    ),
    child: Row(
      children: [
        const Icon(Icons.visibility_outlined, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class ReviewBottomTabs extends StatelessWidget {
  const ReviewBottomTabs({super.key, required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Desk', Icons.space_dashboard_rounded),
      ('Market', Icons.candlestick_chart_rounded),
      ('Floor', Icons.stairs_rounded),
      ('Profile', Icons.person_rounded),
    ];
    return Container(
      height: 68,
      color: UiReviewColor.paper,
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.$2,
                    color: item.$1 == selected
                        ? UiReviewColor.violet
                        : UiReviewColor.ink.withValues(alpha: .42),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.$1,
                    style: TextStyle(
                      color: item.$1 == selected
                          ? UiReviewColor.violet
                          : UiReviewColor.ink.withValues(alpha: .52),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String reviewCount(num value, {int decimals = 0}) {
  final fixed = value.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  if (parts.length > 1) buffer.write('.${parts[1]}');
  return buffer.toString();
}
