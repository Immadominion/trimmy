import '../design/product_success_mark.dart';
import 'package:flutter/material.dart';

import '../career/career.dart';
import '../career/career_activity_week.dart';
import '../market/market_craft.dart';
import '../design/product_empty_state.dart';
import '../design/product_motion_icon.dart';
import '../../ui_review/review_animated_splash.dart';
import '../design/product_theme.dart';

class FloorScreen extends StatefulWidget {
  const FloorScreen({
    super.key,
    required this.signedIn,
    required this.onSignIn,
    required this.onOpenMarket,
    this.career,
    this.personaId,
    this.dailyDesk,
    this.activityWeekLoader,
    this.principalKey,
    this.careerLoading = false,
    this.careerMessage,
    this.onRetryCareer,
    this.missions,
    this.missionsLoading = false,
    this.missionsMessage,
    this.onRetryMissions,
    this.onOpenMission,
    this.promotion,
    this.promotionLoading = false,
    this.onPromote,
  });

  final bool signedIn;
  final VoidCallback onSignIn, onOpenMarket;
  final CareerSummary? career;
  final Widget? dailyDesk;
  final String? personaId, principalKey;
  final Future<CareerActivityWeek?> Function()? activityWeekLoader;
  final bool careerLoading;
  final String? careerMessage;
  final VoidCallback? onRetryCareer;
  final CareerMissionBoard? missions;
  final bool missionsLoading;
  final String? missionsMessage;
  final VoidCallback? onRetryMissions;
  final ValueChanged<CareerMission>? onOpenMission;
  final CareerPromotionReceipt? promotion;
  final bool promotionLoading;
  final ValueChanged<CareerMission>? onPromote;

  @override
  State<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends State<FloorScreen> {
  CareerActivityWeek? _week;
  int _weekGeneration = 0;
  bool _weekFailed = false;
  final _rankSheetRevision = ValueNotifier<int>(0);

  @override
  void dispose() {
    _rankSheetRevision.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadWeek();
  }

  @override
  void didUpdateWidget(covariant FloorScreen old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rankSheetRevision.value++;
    });
    if (old.principalKey != widget.principalKey ||
        old.career?.revision != widget.career?.revision ||
        old.career?.serverDate != widget.career?.serverDate) {
      _week = null;
      _loadWeek();
    }
  }

  Future<void> _loadWeek() async {
    final generation = ++_weekGeneration;
    _weekFailed = false;
    try {
      final week = await widget.activityWeekLoader?.call();
      if (mounted && generation == _weekGeneration) {
        setState(() => _week = week);
        _rankSheetRevision.value++;
      }
    } catch (_) {
      if (mounted && generation == _weekGeneration) {
        setState(() => _weekFailed = true);
        _rankSheetRevision.value++;
      }
    }
  }

  Future<void> _openRank() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    shape: productSquircle(32),
    builder: (sheetContext) => ListenableBuilder(
      listenable: _rankSheetRevision,
      builder: (context, _) => FractionallySizedBox(
        heightFactor: .87,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your progress',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close progress',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                child: _career(context, inSheet: true),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      bottom: false,
      child: widget.dailyDesk == null
          ? CustomScrollView(
              key: const PageStorageKey('product-floor'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        'Career',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 22),
                      _career(context),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 16, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Career',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        TextButton.icon(
                          key: const ValueKey('career-open-progress'),
                          onPressed: _openRank,
                          style: TextButton.styleFrom(
                            foregroundColor: ProductColor.violet,
                          ),
                          icon: const ProductMotionIcon(
                            file: 'nav-plumpy-career.png',
                            size: 23,
                          ),
                          label: Text(widget.career?.rank.label ?? 'Progress'),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: widget.dailyDesk!),
              ],
            ),
    ),
  );

  Widget _career(BuildContext context, {bool inSheet = false}) =>
      widget.career == null
      ? widget.careerLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: TrimmyLiquidMark(size: 72),
                ),
              )
            : ProductEmptyState(
                title: 'Career couldn’t load',
                message: widget.careerMessage,
                action: TextButton(
                  onPressed: widget.onRetryCareer ?? widget.onOpenMarket,
                  child: Text(
                    widget.onRetryCareer == null ? 'Browse stocks' : 'Retry',
                  ),
                ),
              )
      : _CareerRecord(
          key: const ValueKey('floor-career'),
          career: widget.career!,
          personaId: widget.personaId,
          week: _week,
          onRetryWeek: _weekFailed ? _loadWeek : null,
          onOpenMarket: widget.onOpenMarket,
          statusMessage: widget.careerMessage,
          onRetry: widget.onRetryCareer,
          missions: widget.missions,
          missionsLoading: widget.missionsLoading,
          missionsMessage: widget.missionsMessage,
          onRetryMissions: widget.onRetryMissions,
          onOpenMission: widget.onOpenMission == null
              ? null
              : (mission) {
                  if (inSheet) Navigator.of(context).pop();
                  widget.onOpenMission!(mission);
                },
          promotion: widget.promotion,
          promotionLoading: widget.promotionLoading,
          onPromote: widget.onPromote,
        );
}

class _CareerRecord extends StatelessWidget {
  const _CareerRecord({
    super.key,
    required this.career,
    this.personaId,
    this.week,
    this.onRetryWeek,
    required this.onOpenMarket,
    required this.missions,
    required this.missionsLoading,
    this.statusMessage,
    this.onRetry,
    this.missionsMessage,
    this.onRetryMissions,
    this.onOpenMission,
    this.promotion,
    this.promotionLoading = false,
    this.onPromote,
  });

  final CareerSummary career;
  final String? personaId;
  final CareerActivityWeek? week;
  final VoidCallback? onRetryWeek;
  final VoidCallback onOpenMarket;
  final CareerMissionBoard? missions;
  final bool missionsLoading;
  final String? statusMessage;
  final VoidCallback? onRetry;
  final String? missionsMessage;
  final VoidCallback? onRetryMissions;
  final ValueChanged<CareerMission>? onOpenMission;
  final CareerPromotionReceipt? promotion;
  final bool promotionLoading;
  final ValueChanged<CareerMission>? onPromote;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('floor-career'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (statusMessage != null) ...[
        _MissionStatus(message: statusMessage!, onRetry: onRetry),
        const SizedBox(height: 12),
      ],
      _RankCard(
        career: career,
        week: week,
        onRetryWeek: onRetryWeek,
        promotionReady:
            missions != null &&
            eligibleCareerPromotion(summary: career, board: missions!) != null,
      ),
      const SizedBox(height: 28),
      if (promotion != null) ...[
        _PromotionResult(receipt: promotion!),
        const SizedBox(height: 18),
      ],
      _MissionPath(
        career: career,
        board: missions,
        loading: missionsLoading,
        message: missionsMessage,
        onRetry: onRetryMissions,
        onOpenMarket: onOpenMarket,
        onOpenMission: onOpenMission,
        promotionLoading: promotionLoading,
        onPromote: onPromote,
      ),
    ],
  );
}

class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.career,
    required this.promotionReady,
    this.week,
    this.onRetryWeek,
  });
  final CareerSummary career;
  final bool promotionReady;
  final CareerActivityWeek? week;
  final VoidCallback? onRetryWeek;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    decoration: ShapeDecoration(
      color: const Color(0xFFE2DBF1),
      shape: productSquircle(33),
    ),
    child: Material(
      key: const ValueKey('career-rank-card'),
      color: const Color(0xFFF7F5FC),
      shape: productSquircle(30),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            career.rank.label,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          Tooltip(
                            message:
                                'Trims are career points. Earn them through activities to move up in rank.',
                            triggerMode: TooltipTriggerMode.tap,
                            margin: const EdgeInsets.symmetric(horizontal: 28),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            constraints: const BoxConstraints(maxWidth: 300),
                            decoration: ShapeDecoration(
                              color: const Color(0xFFEEE8F8),
                              shape: productSquircle(18),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: 'Dejanire Sans',
                              fontSize: 14,
                              height: 1.4,
                              color: ProductColor.ink,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    '${_count(career.trims.total)} Trims',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: MarketPalette.violet),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 15,
                                  color: MarketPalette.violet,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Career points',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ExcludeSemantics(
                      child: Image.asset(
                        career.rank.id == CareerRank.rookie
                            ? 'assets/images/ui_review/rookie-briefcase-v1.png'
                            : 'assets/images/ui_review/icons8/goal-goal-animated.png',
                        width: 112,
                        height: 112,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _RankProgress(career: career, promotionReady: promotionReady),
              ],
            ),
          ),
          CareerStreakStrip(
            career: career,
            week: week,
            onRetry: onRetryWeek,
            embedded: true,
          ),
        ],
      ),
    ),
  );
}

class _MissionPath extends StatelessWidget {
  const _MissionPath({
    required this.career,
    required this.board,
    required this.loading,
    required this.onOpenMarket,
    this.message,
    this.onRetry,
    this.onOpenMission,
    this.promotionLoading = false,
    this.onPromote,
  });

  final CareerSummary career;
  final CareerMissionBoard? board;
  final bool loading;
  final String? message;
  final VoidCallback? onRetry, onOpenMarket;
  final ValueChanged<CareerMission>? onOpenMission;
  final bool promotionLoading;
  final ValueChanged<CareerMission>? onPromote;

  @override
  Widget build(BuildContext context) {
    final coherentBoard =
        board != null &&
            board!.revision == career.revision &&
            board!.currentRank == career.rank.id
        ? board
        : null;
    final missions = coherentBoard?.missions;
    final complete =
        missions
            ?.where((mission) => mission.status == CareerMissionStatus.complete)
            .length ??
        0;
    final promotion = coherentBoard == null
        ? null
        : eligibleCareerPromotion(summary: career, board: coherentBoard);
    return _CareerSurface(
      key: const ValueKey('floor-mission-path'),
      color: Colors.white,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Career milestones',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      missions == null
                          ? 'Your activities'
                          : '$complete of ${missions.length} complete',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ProductColor.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            _MissionStatus(message: message!, onRetry: onRetry),
          ],
          const SizedBox(height: 18),
          if (board != null && coherentBoard == null) ...[
            const _MissionStatus(message: 'Updating your progress…'),
            const SizedBox(height: 18),
          ],
          if (missions == null)
            _MissionUnavailable(
              loading: loading,
              onRetry: onRetry,
              onOpenMarket: onOpenMarket,
            )
          else
            for (var index = 0; index < missions.length; index++)
              _MissionNode(
                mission: missions[index],
                last: index == missions.length - 1,
                onOpen: onOpenMission,
                promotionAvailable: identical(missions[index], promotion),
                promotionLoading: promotionLoading,
                onPromote: onPromote,
              ),
        ],
      ),
    );
  }
}

class _MissionStatus extends StatelessWidget {
  const _MissionStatus({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: _CareerSurface(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _MissionUnavailable extends StatelessWidget {
  const _MissionUnavailable({
    required this.loading,
    required this.onOpenMarket,
    this.onRetry,
  });
  final bool loading;
  final VoidCallback? onRetry, onOpenMarket;
  @override
  Widget build(BuildContext context) => loading
      ? const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: TrimmyLiquidMark(size: 52),
          ),
        )
      : ProductEmptyState(
          title: 'Activities couldn’t load',
          action: TextButton(
            onPressed: onRetry ?? onOpenMarket,
            child: Text(onRetry == null ? 'Browse stocks' : 'Retry'),
          ),
        );
}

class _MissionNode extends StatelessWidget {
  const _MissionNode({
    required this.mission,
    required this.last,
    required this.promotionAvailable,
    required this.promotionLoading,
    this.onOpen,
    this.onPromote,
  });
  final CareerMission mission;
  final bool last, promotionAvailable, promotionLoading;
  final ValueChanged<CareerMission>? onOpen, onPromote;
  @override
  Widget build(BuildContext context) {
    final complete = mission.status == CareerMissionStatus.complete;
    final ready = mission.status == CareerMissionStatus.ready;
    final active = ready || promotionAvailable;
    final title = mission.id == CareerMissionId.writeAReason
        ? 'Comment on your trade'
        : mission.title;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                if (complete)
                  ProductSuccessMark(
                    key: ValueKey('mission-complete-${mission.id.name}'),
                    size: 30,
                  )
                else
                  ProductMotionIcon(
                    key: ValueKey('mission-node-${mission.id.name}'),
                    size: 30,
                    file: switch (mission.id) {
                      CareerMissionId.firstPaperBuy =>
                        'goal-chart-animated.png',
                      CareerMissionId.writeAReason => 'career-comments.png',
                      CareerMissionId.holdThroughRedDay =>
                        'goal-goal-animated.png',
                    },
                    animatedFile: switch (mission.id) {
                      CareerMissionId.firstPaperBuy =>
                        'goal-chart-animated.gif',
                      CareerMissionId.holdThroughRedDay =>
                        'goal-goal-animated.gif',
                      _ => null,
                    },
                  ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      color: complete
                          ? const Color(0xFF70C591)
                          : const Color(0xFFE9E7EF),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 6 : 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    complete
                        ? 'Complete'
                        : ready
                        ? 'Ready'
                        : 'Locked',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: complete
                          ? const Color(0xFF258353)
                          : active
                          ? MarketPalette.violet
                          : ProductColor.muted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (mission.id == CareerMissionId.holdThroughRedDay &&
                      !complete) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Keep a stock through a down day.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ProductColor.muted,
                      ),
                    ),
                  ],
                  if (ready && onOpen != null)
                    TextButton(
                      key: ValueKey('mission-action-${mission.id.name}'),
                      style: TextButton.styleFrom(
                        foregroundColor: MarketPalette.violet,
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () => onOpen!(mission),
                      child: Text(
                        mission.id == CareerMissionId.writeAReason
                            ? 'Write a comment'
                            : 'Find a stock',
                      ),
                    ),
                  if (promotionAvailable && onPromote != null)
                    TextButton(
                      key: ValueKey(
                        'mission-promote-${mission.promotesToRank!.name}',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: MarketPalette.violet,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: promotionLoading
                          ? null
                          : () => onPromote!(mission),
                      child: Text(
                        promotionLoading
                            ? 'Confirming…'
                            : 'Become ${_rankLabel(mission.promotesToRank!)}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromotionResult extends StatelessWidget {
  const _PromotionResult({required this.receipt});
  final CareerPromotionReceipt receipt;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: _CareerSurface(
      key: const ValueKey('floor-promotion-result'),
      color: const Color(0xFFF1EDF9),
      child: Row(
        children: [
          const _CareerIcon(file: 'goal-goal-animated.png', size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_rankLabel(receipt.toRank)} unlocked',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('+${receipt.trimsAwarded} Trims'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CareerSurface extends StatelessWidget {
  const _CareerSurface({
    super.key,
    required this.child,
    this.color = const Color(0xFFF7F7FA),
    this.radius = 30,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color color;
  final double radius;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: ShapeDecoration(color: color, shape: productSquircle(radius)),
    child: child,
  );
}

class _CareerIcon extends StatelessWidget {
  const _CareerIcon({required this.file, required this.size});
  final String file;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: .9, end: 1),
      duration: productDuration(context, 420),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Image.asset(
        'assets/images/ui_review/icons8/$file',
        width: size,
        height: size,
      ),
    ),
  );
}

class _RankProgress extends StatelessWidget {
  const _RankProgress({required this.career, required this.promotionReady});
  final CareerSummary career;
  final bool promotionReady;

  @override
  Widget build(BuildContext context) {
    final next = career.nextRank;
    final span = next == null ? 1 : next.threshold - career.rank.threshold;
    final earned = career.trims.total - career.rank.threshold;
    final progress = next == null ? 1.0 : (earned / span).clamp(0.0, 1.0);
    final label = next == null
        ? 'Highest rank reached'
        : next.promotionRequired
        ? promotionReady
              ? 'Promotion ready for ${next.label}'
              : 'Threshold reached. Finish the promotion mission'
        : '${_count(next.trimsRemaining)} to ${next.label}';
    return Semantics(
      label: 'Rank progress ${(progress * 100).round()} percent. $label',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              key: const ValueKey('floor-rank-progress-label'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: ProductColor.ink),
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => SizedBox(
                key: const ValueKey('career-goal-bar'),
                height: 26,
                width: double.infinity,
                child: CustomPaint(painter: _GoalBarPainter(value)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _count(int value) {
  final source = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < source.length; index++) {
    if (index > 0 && (source.length - index) % 3 == 0) buffer.write(',');
    buffer.write(source[index]);
  }
  return buffer.toString();
}

String _rankLabel(CareerRank rank) => switch (rank) {
  CareerRank.rookie => 'Rookie',
  CareerRank.analyst => 'Analyst',
  CareerRank.trader => 'Trader',
  CareerRank.seniorTrader => 'Senior Trader',
  CareerRank.partner => 'Partner',
  CareerRank.legend => 'Legend',
};

/// Rounded alternating segments, clipped to the exact earned fraction.
class _GoalBarPainter extends CustomPainter {
  const _GoalBarPainter(this.value);
  final double value;
  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(30),
    );
    canvas.drawRRect(outer, Paint()..color = const Color(0xFFE8E0F5));
    final track = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(30)),
      Paint()..color = Colors.white,
    );
    if (value <= 0) return;
    final filled = Rect.fromLTWH(
      track.left,
      track.top,
      track.width * value.clamp(0, 1),
      track.height,
    );
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(filled, const Radius.circular(30)),
    );
    const stripe = 13.0;
    for (var index = 0; index * stripe < filled.width; index++) {
      canvas.drawRect(
        Rect.fromLTWH(
          track.left + index * stripe,
          track.top,
          stripe,
          track.height,
        ),
        Paint()
          ..color = index.isEven
              ? const Color(0xFF9581ED)
              : const Color(0xFFD7CAF7),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoalBarPainter oldDelegate) => oldDelegate.value != value;
}
