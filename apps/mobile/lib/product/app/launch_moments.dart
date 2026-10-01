import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../career/career.dart';
import '../design/product_components.dart';
import '../design/product_motion_icon.dart';
import '../design/product_state_page.dart';
import '../design/product_success_mark.dart';
import '../design/product_theme.dart';

@immutable
final class FirstPositionMomentData {
  const FirstPositionMomentData({
    required this.symbol,
    required this.quantity,
    required this.confirmedAt,
  });
  final String symbol, quantity;
  final DateTime confirmedAt;
}

class PromotionMoment extends StatelessWidget {
  const PromotionMoment({
    super.key,
    required this.receipt,
    required this.onContinue,
  });
  final CareerPromotionReceipt receipt;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ProductStatePage(
      artwork: const ProductStateArtwork(file: 'trophy.png'),
      title: l10n.appPromotionTitle(
        receipt.toRank.name,
        _rankLabel(l10n, receipt.toRank),
      ),
      message: l10n.appPromotionMessage,
      details: ProductCard(
        key: const ValueKey('promotion-confirmed-facts'),
        color: const Color(0xFFF4F0FF),
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 16,
          runSpacing: 20,
          children: [
            _MomentFact(
              label: l10n.appPromotionFrom,
              value: _rankLabel(l10n, receipt.fromRank),
            ),
            _MomentFact(
              label: l10n.appPromotionNewRank,
              value: _rankLabel(l10n, receipt.toRank),
            ),
            _MomentFact(
              label: l10n.appPromotionEarned,
              value: l10n.appPromotionTrims(
                context.formats.number('${receipt.trimsAwarded}'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ProductButton(
          key: const ValueKey('promotion-continue'),
          label: l10n.appPromotionBackToCareer,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

String _rankLabel(AppLocalizations l10n, CareerRank rank) => switch (rank) {
  CareerRank.rookie => l10n.rankRookie,
  CareerRank.analyst => l10n.rankAnalyst,
  CareerRank.trader => l10n.rankTrader,
  CareerRank.seniorTrader => l10n.rankSeniorTrader,
  CareerRank.partner => l10n.rankPartner,
  CareerRank.legend => l10n.rankLegend,
};

/// Retained for older checkpoints and previews, using the same state layout.
class FirstPositionMoment extends StatelessWidget {
  const FirstPositionMoment({
    super.key,
    required this.data,
    required this.onCollect,
  });
  final FirstPositionMomentData data;
  final VoidCallback onCollect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formats = context.formats;
    return ProductStatePage(
      artwork: const _MomentArtwork(child: ProductSuccessMark(size: 104)),
      title: l10n.appFirstPositionTitle,
      message: l10n.appFirstPositionMessage,
      details: ProductCard(
        key: const ValueKey('first-position-facts'),
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 16,
          runSpacing: 20,
          children: [
            _MomentFact(label: l10n.appFirstPositionStock, value: data.symbol),
            _MomentFact(
              label: l10n.appFirstPositionShares,
              value: formats.number(data.quantity),
            ),
            _MomentFact(
              label: l10n.appFirstPositionTime,
              value: l10n.appFirstPositionTimeUtc(
                formats.time24(data.confirmedAt.toUtc()),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ProductButton(
          key: const ValueKey('first-position-collect'),
          label: l10n.commonContinue,
          onPressed: onCollect,
        ),
      ],
    );
  }
}

class DayOneMoment extends StatelessWidget {
  const DayOneMoment({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => ProductStatePage(
    artwork: const _MomentArtwork(
      child: ProductMotionIcon(file: 'career-streak.png', size: 112),
    ),
    title: context.l10n.appDayOneTitle,
    message: context.l10n.appDayOneMessage,
    actions: [
      ProductButton(
        key: const ValueKey('day-one-continue'),
        label: context.l10n.commonContinue,
        onPressed: onContinue,
      ),
    ],
  );
}

class _MomentArtwork extends StatelessWidget {
  const _MomentArtwork({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: .8, end: 1),
    duration: productDuration(context, 520),
    curve: Curves.easeOutBack,
    builder: (_, value, child) => Transform.scale(scale: value, child: child),
    child: SizedBox(height: 140, child: Center(child: child)),
  );
}

class _MomentFact extends StatelessWidget {
  const _MomentFact({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    child: Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}
