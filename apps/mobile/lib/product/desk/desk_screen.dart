import 'package:flutter/material.dart';
import '../design/paper_format.dart';
import '../design/product_theme.dart';
import '../design/product_motion_icon.dart';
import '../money/wallet_stack.dart';
import '../market/market_craft.dart';
import '../onboarding/onboarding_models.dart';
import 'desk_models.dart';

class DeskScreen extends StatelessWidget {
  const DeskScreen({
    super.key,
    required this.snapshot,
    required this.onOpenMarket,
    this.onAddMoney,
    this.onFastBuy,
    this.onInbox,
    this.onOpenPortfolio,
    this.onOpenCareer,
    this.onChoosePersona,
    this.onOpenProfile,
    this.onSignIn,
    this.statusMessage,
    this.onRetry,
    this.persona,
    this.onOpenHolding,
    this.activity,
    this.dailyDesk,
    this.onRefresh,
    this.real = false,
    this.realBalance,
    this.realBalanceNote,
    this.realHoldings,
    this.onSwitchMode,
  });
  final bool real;
  final String? realBalance, realBalanceNote;
  final Widget? realHoldings;
  final VoidCallback? onSwitchMode;
  final DeskSnapshot snapshot;
  final VoidCallback onOpenMarket;
  final VoidCallback? onFastBuy,
      onAddMoney,
      onInbox,
      onOpenPortfolio,
      onOpenCareer,
      onChoosePersona,
      onOpenProfile,
      onSignIn,
      onRetry;
  final ValueChanged<DeskHolding>? onOpenHolding;
  final Future<void> Function()? onRefresh;
  final String? statusMessage;
  final TraderPersona? persona;
  final Widget? activity, dailyDesk;

  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      key: const PageStorageKey('product-desk'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your desk',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  if (onInbox != null)
                    IconButton(
                      tooltip: 'Updates',
                      onPressed: onInbox,
                      icon: const ProductMotionIcon(
                        file: 'asset-bell.png',
                        size: 25,
                      ),
                    ),
                  Semantics(
                    label: 'Open profile',
                    button: true,
                    child: InkWell(
                      key: const ValueKey('desk-open-profile'),
                      onTap: onOpenProfile,
                      customBorder: productSquircle(18),
                      child: SizedBox.square(
                        dimension: 48,
                        child: persona == null
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: ProductMotionIcon(
                                  file: 'nav-plumpy-profile.png',
                                ),
                              )
                            : Image.asset(
                                'assets/images/ui_review/persona-${persona!.id}-avatar-v1.png',
                                semanticLabel:
                                    '${persona!.label} profile picture',
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (statusMessage != null) ...[
                Container(
                  key: const ValueKey('paper-desk-stale'),
                  padding: const EdgeInsets.all(14),
                  decoration: ShapeDecoration(
                    color: const Color(0xFFFFF4DE),
                    shape: productSquircle(20),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          statusMessage!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (onRetry != null)
                        TextButton(
                          onPressed: onRetry,
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              _portfolio(context),
              if (snapshot.streak != null || snapshot.trims != null) ...[
                const SizedBox(height: 17),
                Wrap(
                  key: const ValueKey('desk-career-counters'),
                  spacing: 22,
                  runSpacing: 8,
                  children: [
                    if (snapshot.streak != null)
                      _counter(
                        context,
                        '${snapshot.streak}',
                        'day streak',
                        const ValueKey('desk-streak-count'),
                        true,
                      ),
                    if (snapshot.trims != null)
                      _counter(
                        context,
                        '${snapshot.trims}',
                        'Trims',
                        const ValueKey('desk-trims-count'),
                        false,
                      ),
                  ],
                ),
              ],
              if (dailyDesk != null)
                dailyDesk!
              else if (onOpenCareer != null) ...[
                const SizedBox(height: 24),
                _nextStep(context),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Holdings',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (!real && snapshot.holdings.isNotEmpty)
                    TextButton(
                      onPressed: onOpenMarket,
                      child: const Text('Explore'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (real)
                realHoldings ?? const SizedBox.shrink()
              else if (snapshot.holdings.isEmpty)
                _empty(context)
              else
                for (final holding in snapshot.holdings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: const Color(0xFFF7F6FA),
                      shape: productSquircle(24),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onOpenHolding == null
                            ? null
                            : () => onOpenHolding!(holding),
                        child: _HoldingRow(holding),
                      ),
                    ),
                  ),
              if (onChoosePersona != null) ...[
                const SizedBox(height: 14),
                _actionRow(
                  context,
                  'Pick your trader',
                  'Make this desk yours.',
                  onChoosePersona!,
                  const ProductMotionIcon(file: 'nav-plumpy-profile.png'),
                ),
              ],
              if (onSignIn != null) ...[
                const SizedBox(height: 12),
                _actionRow(
                  context,
                  'Save your desk',
                  'Keep it on your other devices.',
                  onSignIn!,
                  const ProductMotionIcon(file: 'settings-lock.png'),
                  key: const ValueKey('desk-save-progress'),
                ),
              ],
              if (activity != null) ...[const SizedBox(height: 26), activity!],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: onRefresh == null
            ? scroll
            : RefreshIndicator(
                onRefresh: onRefresh!,
                color: ProductColor.violet,
                child: scroll,
              ),
      ),
    );
  }

  Widget _portfolio(BuildContext context) => WalletStack(
    real: real,
    paper: snapshot,
    balance: realBalance,
    balanceNote: realBalanceNote,
    onSwitch: onSwitchMode ?? () {},
    onBuy: onFastBuy ?? onOpenMarket,
    onAddMoney: onAddMoney,
    onHistory: onOpenPortfolio,
  );

  Widget _nextStep(BuildContext context) => Material(
    color: const Color(0xFFF4F0FB),
    shape: productSquircle(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: const ValueKey('desk-open-career'),
      onTap: onOpenCareer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 17, 14, 17),
        child: Row(
          children: [
            Image.asset(
              'assets/images/ui_review/rookie-briefcase-v1.png',
              width: 50,
              height: 50,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.rank ?? 'Your career',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: ProductColor.violet),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    snapshot.mission ?? 'See your next step',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color: ProductColor.violet,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _counter(
    BuildContext context,
    String value,
    String label,
    Key key,
    bool streak,
  ) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (streak)
        Image.asset(
          'assets/images/ui_review/icons8/career-streak.png',
          width: 22,
          height: 22,
          color: const Color(0xFFF47B35),
          colorBlendMode: BlendMode.srcIn,
        )
      else
        const SizedBox(width: 5),
      const SizedBox(width: 5),
      Text(
        value,
        key: key,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: ProductColor.ink),
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _empty(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: ShapeDecoration(
      color: ProductColor.paperRaised,
      shape: productSquircle(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('No stocks yet', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Pick a company to begin.'),
        TextButton(
          key: const ValueKey('desk-empty-open-market'),
          onPressed: onOpenMarket,
          child: const Text('Explore stocks'),
        ),
      ],
    ),
  );

  Widget _actionRow(
    BuildContext context,
    String title,
    String subtitle,
    VoidCallback onTap,
    Widget icon, {
    Key? key,
  }) => InkWell(
    key: key,
    onTap: onTap,
    customBorder: productSquircle(20),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    ),
  );
}

Widget _coin(DeskHolding holding, double size) => CompanyLogo(
  name: holding.name,
  logoUrl: holding.logoUrl,
  color: Colors.white,
  size: size,
);

class _HoldingRow extends StatelessWidget {
  const _HoldingRow(this.holding);
  final DeskHolding holding;
  @override
  Widget build(BuildContext context) {
    final change = holding.changePercent;
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          _coin(holding, 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holding.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${holding.quantity} shares',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  holding.valuePaper == null
                      ? 'Price unavailable'
                      : formatPaperForDisplay(holding.valuePaper!),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (change != null)
                  Text(
                    signedPercent(change),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: change >= 0
                          ? ProductColor.gain
                          : ProductColor.loss,
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
