import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => ProductStatePage(
    artwork: const ProductStateArtwork(file: 'trophy.png'),
    title:
        'You’re ${_rankArticle(receipt.toRank)} ${_rankLabel(receipt.toRank)}!',
    message: 'A new chapter on the floor.',
    details: ProductCard(
      key: const ValueKey('promotion-confirmed-facts'),
      color: const Color(0xFFF4F0FF),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 16,
        runSpacing: 20,
        children: [
          _MomentFact(label: 'From', value: _rankLabel(receipt.fromRank)),
          _MomentFact(label: 'New rank', value: _rankLabel(receipt.toRank)),
          _MomentFact(label: 'Earned', value: '${receipt.trimsAwarded} Trims'),
        ],
      ),
    ),
    actions: [
      ProductButton(
        key: const ValueKey('promotion-continue'),
        label: 'Back to Career',
        onPressed: onContinue,
      ),
    ],
  );
}

String _rankArticle(CareerRank rank) => rank == CareerRank.analyst ? 'an' : 'a';
String _rankLabel(CareerRank rank) => switch (rank) {
  CareerRank.rookie => 'Rookie',
  CareerRank.analyst => 'Analyst',
  CareerRank.trader => 'Trader',
  CareerRank.seniorTrader => 'Senior Trader',
  CareerRank.partner => 'Partner',
  CareerRank.legend => 'Legend',
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
  Widget build(BuildContext context) => ProductStatePage(
    artwork: const _MomentArtwork(child: ProductSuccessMark(size: 104)),
    title: 'Your first position.',
    message: 'You’ve placed your first order!',
    details: ProductCard(
      key: const ValueKey('first-position-facts'),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 16,
        runSpacing: 20,
        children: [
          _MomentFact(label: 'Stock', value: data.symbol),
          _MomentFact(label: 'Shares', value: data.quantity),
          _MomentFact(label: 'Time', value: _utcTime(data.confirmedAt)),
        ],
      ),
    ),
    actions: [
      ProductButton(
        key: const ValueKey('first-position-collect'),
        label: 'Continue',
        onPressed: onCollect,
      ),
    ],
  );
}

class DayOneMoment extends StatelessWidget {
  const DayOneMoment({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => ProductStatePage(
    artwork: const _MomentArtwork(
      child: ProductMotionIcon(file: 'career-streak.png', size: 112),
    ),
    title: 'Day 1, done.',
    message: 'See you on the floor tomorrow.',
    actions: [
      ProductButton(
        key: const ValueKey('day-one-continue'),
        label: 'Continue',
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

String _utcTime(DateTime value) {
  final utc = value.toUtc();
  return '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')} UTC';
}
