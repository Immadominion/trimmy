import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../design/product_theme.dart';
import '../design/product_success_mark.dart';
import '../../ui_review/review_animated_splash.dart';
import 'daily_desk.dart';

/// The Career card for a day with no workday (a weekend or market holiday):
/// a short desk story instead. It hides once today's story is done.
class DailyDeskEntry extends StatelessWidget {
  const DailyDeskEntry({
    super.key,
    required this.controller,
    required this.onOpen,
    this.spacing = 24,
  });
  final DailyDeskController controller;
  final VoidCallback onOpen;

  /// Space above the card.
  final double spacing;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final shift = controller.shift;
      if (shift?.complete == true) return const SizedBox.shrink();
      final l10n = context.l10n;
      if (shift == null) {
        return Container(
          key: const ValueKey('desk-story-unavailable'),
          margin: EdgeInsets.only(top: spacing),
          padding: const EdgeInsets.all(20),
          decoration: ShapeDecoration(
            color: const Color(0xFFF7F5FB),
            shape: productSquircle(26),
          ),
          child: controller.loading
              ? const Center(child: TrimmyLiquidMark(size: 38))
              : Row(
                  children: [
                    Expanded(child: Text(l10n.deskStoryLoadFailed)),
                    TextButton(
                      onPressed: controller.refresh,
                      child: Text(l10n.commonTryAgain),
                    ),
                  ],
                ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: spacing),
          Material(
            color: const Color(0xFFF2EDF9),
            shape: productSquircle(28),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('desk-story-open'),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.deskStoryCardLabel,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF6A55A6)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            shift.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  l10n.deskStoryStepInside,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: const Color(0xFF6850B0),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: Color(0xFF6850B0),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Large text needs the width more than the portrait.
                    if (MediaQuery.textScalerOf(context).scale(1) <= 1.3) ...[
                      const SizedBox(width: 8),
                      ExcludeSemantics(
                        child: _DeskFloat(
                          child: Image.asset(
                            shift.portrait,
                            width: 80,
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (controller.failed)
            TextButton(
              onPressed: controller.refresh,
              child: Text(l10n.deskStoryRefresh),
            ),
        ],
      );
    },
  );
}

class _DeskFloat extends StatefulWidget {
  const _DeskFloat({required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<_DeskFloat> createState() => _DeskFloatState();
}

class _DeskFloatState extends State<_DeskFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _DeskFloat old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.enabled &&
        TickerMode.valuesOf(context).enabled &&
        productDuration(context, 1) != Duration.zero) {
      if (!_motion.isAnimating) _motion.repeat(reverse: true);
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      offset: Offset(0, -3 * Curves.easeInOut.transform(_motion.value)),
      child: child,
    ),
  );
}

class DailyDeskScreen extends StatefulWidget {
  const DailyDeskScreen({
    super.key,
    required this.controller,
    required this.onCompleted,
  });
  final DailyDeskController controller;
  final Future<void> Function() onCompleted;
  @override
  State<DailyDeskScreen> createState() => _DailyDeskScreenState();
}

class _DailyDeskScreenState extends State<DailyDeskScreen> {
  late DailyShift _shift = widget.controller.shift!;
  late DeskChoice? _choice = _shift.result;
  bool _saving = false;

  /// Why the last save did not go as planned. The text is built when shown.
  _StoryNotice? _error;
  Future<void> _clockOut() async {
    if (_saving || _choice == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final next = await widget.controller.complete(_shift, _choice!.id);
      await widget.onCompleted();
      if (!mounted) return;
      if (next.date != _shift.date) {
        setState(() {
          _shift = next;
          _choice = next.result;
          _error = _StoryNotice.newDay;
        });
      } else {
        setState(() => _shift = next);
      }
    } on DailyDeskException catch (e) {
      if (e.code == 'DAY_CHANGED' || e.code == 'SHIFT_ALREADY_COMPLETE') {
        await widget.controller.refresh();
        if (mounted && widget.controller.shift != null) {
          setState(() {
            _shift = widget.controller.shift!;
            _choice = _shift.result;
            _error = e.code == 'DAY_CHANGED'
                ? _StoryNotice.newDay
                : _StoryNotice.alreadySaved;
          });
        }
      } else {
        if (mounted) setState(() => _error = _StoryNotice.failed);
      }
    } catch (_) {
      if (mounted) setState(() => _error = _StoryNotice.failed);
    }
    if (mounted) setState(() => _saving = false);
  }

  String _notice(AppLocalizations l10n, _StoryNotice notice) =>
      switch (notice) {
        _StoryNotice.newDay => l10n.deskStoryNewDay,
        _StoryNotice.alreadySaved => l10n.deskStoryAlreadySaved,
        _StoryNotice.failed => l10n.deskStoryClockOutFailed,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 22, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: context.l10n.deskStoryLeave,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _shift.complete
                        ? context.l10n.deskStoryHeaderSaved
                        : context.l10n.deskStoryHeader,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          bottom: 10,
                          child: Container(
                            width: 160,
                            height: 62,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3EDF9),
                              borderRadius: BorderRadius.all(
                                Radius.elliptical(80, 31),
                              ),
                            ),
                          ),
                        ),
                        _DeskFloat(
                          enabled: !_shift.complete,
                          child: Image.asset(
                            _shift.portrait,
                            height: 148,
                            width: 165,
                            fit: BoxFit.contain,
                          ),
                        ),
                        if (_shift.complete)
                          const Positioned(
                            right: 45,
                            bottom: 4,
                            child: ProductSuccessMark(size: 45),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _shift.complete
                        ? context.l10n.deskStorySeeYou
                        : _shift.title,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 14),
                  if (_choice == null) ...[
                    Text(
                      _shift.body,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      context.l10n.deskStoryQuestion,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (final choice in _shift.choices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: const Color(0xFFF6F3FB),
                          shape: productSquircle(23),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('daily-choice-${choice.id}'),
                            onTap: () => setState(() => _choice = choice),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 20,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      choice.label,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 19,
                                    color: Color(0xFF7867B1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ] else ...[
                    if (_shift.complete) ...[
                      Text(
                        context.l10n.deskStoryReward(
                          context.formats.integer(10),
                        ),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: ProductColor.gain),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      context.l10n.deskStoryYouChose(_choice!.label),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _choice!.outcome,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: ShapeDecoration(
                        color: const Color(0xFFF3EFFA),
                        shape: productSquircle(25),
                      ),
                      child: Text(
                        _choice!.takeaway,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(height: 1.4),
                      ),
                    ),
                    if (!_shift.complete)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _choice = null),
                        child: Text(context.l10n.deskStoryThinkAgain),
                      ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _notice(context.l10n, _error!),
                          style: const TextStyle(color: ProductColor.loss),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_choice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ProductColor.violet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    shape: productSquircle(24),
                  ),
                  onPressed: _saving
                      ? null
                      : _shift.complete
                      ? () => Navigator.of(context).pop(true)
                      : _clockOut,
                  child: Text(
                    _saving
                        ? context.l10n.commonSaving
                        : _shift.complete
                        ? context.l10n.deskStoryBackToDesk
                        : context.l10n.deskStoryClockOut,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

enum _StoryNotice { newDay, alreadySaved, failed }
