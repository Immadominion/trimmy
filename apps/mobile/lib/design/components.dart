import 'package:flutter/material.dart';
import 'theme.dart';

class SquirclePanel extends StatelessWidget {
  const SquirclePanel({
    super.key,
    required this.child,
    this.color = TrimmyColors.white,
    this.padding = const EdgeInsets.all(24),
    this.radius = 28,
    this.border = false,
  });
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool border;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: ShapeDecoration(
      color: color,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(radius),
        side: border
            ? const BorderSide(color: TrimmyColors.line)
            : BorderSide.none,
      ),
    ),
    child: child,
  );
}

class StatusTag extends StatelessWidget {
  const StatusTag(
    this.label, {
    super.key,
    this.color = TrimmyColors.yellow,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: ShapeDecoration(color: color, shape: squircle(12)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class AdaPortrait extends StatelessWidget {
  const AdaPortrait({
    super.key,
    this.size,
    this.fit = BoxFit.contain,
    this.decorative = true,
  });
  final double? size;
  final BoxFit fit;
  final bool decorative;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/ada-graphic-v2.webp',
    width: size,
    height: size,
    fit: fit,
    excludeFromSemantics: decorative,
    semanticLabel: decorative
        ? null
        : 'Ada, your office mentor, with angular hair, yellow glasses and a knowing expression',
    errorBuilder: (context, error, stack) => SizedBox(
      width: size,
      height: size,
      child: const Center(
        child: Icon(
          Icons.person_outline_rounded,
          size: 64,
          color: TrimmyColors.pine,
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class InitialAvatar extends StatelessWidget {
  const InitialAvatar(
    this.initials, {
    super.key,
    this.color = TrimmyColors.yellow,
    this.size = 42,
  });
  final String initials;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: ShapeDecoration(color: color, shape: squircle(size * .3)),
    child: Text(
      initials,
      style: TextStyle(fontSize: size * .29, fontWeight: FontWeight.w800),
    ),
  );
}

Future<T?> showTrimmySheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 240),
              reverseDuration: Duration(milliseconds: 180),
            ),
      backgroundColor: TrimmyColors.paper,
      shape: squircle(32),
      constraints: const BoxConstraints(maxWidth: 650),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .94,
          ),
          child: child,
        ),
      ),
    );

class SheetHeading extends StatelessWidget {
  const SheetHeading(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
      IconButton(
        tooltip: 'Close',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded),
      ),
    ],
  );
}
