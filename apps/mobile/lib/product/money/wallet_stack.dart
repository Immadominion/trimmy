import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design/product_theme.dart';
import '../design/paper_format.dart';
import '../desk/desk_models.dart';
import '../market/market_craft.dart';

class WalletStack extends StatefulWidget {
  const WalletStack({
    super.key,
    required this.real,
    required this.paper,
    required this.onSwitch,
    required this.onBuy,
    this.balance,
    this.balanceNote,
    this.onAddMoney,
    this.onHistory,
  });
  final bool real;
  final DeskSnapshot paper;
  final String? balance, balanceNote;
  final VoidCallback onSwitch, onBuy;
  final VoidCallback? onAddMoney, onHistory;
  @override
  State<WalletStack> createState() => _WalletStackState();
}

class _WalletStackState extends State<WalletStack>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 580),
    value: widget.real ? 1 : 0,
  );
  @override
  void didUpdateWidget(covariant WalletStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.real != widget.real) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = widget.real ? 1 : 0;
      } else {
        _motion.animateTo(widget.real ? 1 : 0, curve: Curves.easeInOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tall = MediaQuery.textScalerOf(context).scale(14) > 20;
    return Column(
      children: [
        SizedBox(
          height: tall ? 500 : 270,
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final t = _motion.value;
              Widget layer(bool real) {
                final front = real ? t : 1 - t;
                final split = math.sin(t * math.pi);
                return Positioned.fill(
                  top: 20,
                  child: Transform.translate(
                    offset: Offset(
                      (real ? 1 : -1) * split * 35,
                      -18 * (1 - front) - split * 20,
                    ),
                    child: Transform.rotate(
                      angle: (real ? 1 : -1) * split * .055,
                      child: Transform.scale(
                        scale: .94 + front * .06,
                        child: IgnorePointer(
                          ignoring: real != widget.real,
                          child: ExcludeSemantics(
                            excluding: real != widget.real,
                            child: _card(real),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Stack(
                clipBehavior: Clip.none,
                children: t < .5
                    ? [layer(true), layer(false)]
                    : [layer(false), layer(true)],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: widget.onBuy,
                icon: const Icon(Icons.add_rounded, size: 21),
                label: const Text('Fast buy'),
              ),
            ),
            if (widget.real)
              Expanded(
                child: TextButton.icon(
                  onPressed: widget.onAddMoney,
                  icon: const Icon(Icons.south_west_rounded, size: 20),
                  label: const Text('Add money'),
                ),
              )
            else
              Expanded(
                child: TextButton.icon(
                  onPressed: widget.onHistory,
                  icon: const Icon(Icons.history_rounded, size: 20),
                  label: const Text('History'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _card(bool real) {
    final type = Theme.of(context).textTheme;
    final latest = widget.paper.holdings.take(3).toList();
    return Container(
      key: ValueKey(real ? 'real-wallet-card' : 'paper-wallet-card'),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 7),
      decoration: ShapeDecoration(
        color: real ? const Color(0xFFB6DACB) : const Color(0xFFDFD5FB),
        shape: productSquircle(30),
      ),
      child: Container(
        padding: const EdgeInsets.all(21),
        decoration: ShapeDecoration(
          shape: productSquircle(27),
          color: real ? const Color(0xFF26634F) : const Color(0xFF6C50AD),
          image: DecorationImage(
            image: const AssetImage('assets/images/ui_review/profile-sky.webp'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              real ? const Color(0xE622624B) : const Color(0xCB644799),
              BlendMode.srcATop,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flex(
              direction: MediaQuery.textScalerOf(context).scale(14) > 20
                  ? Axis.vertical
                  : Axis.horizontal,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  fit: MediaQuery.textScalerOf(context).scale(14) > 20
                      ? FlexFit.loose
                      : FlexFit.tight,
                  child: Text(
                    real
                        ? 'Cash balance'
                        : switch (widget.paper.paperValueState) {
                            DeskPaperValueState.complete => 'Account balance',
                            DeskPaperValueState.partial => 'Known value',
                            DeskPaperValueState.unavailable => 'Cash balance',
                          },
                    style: type.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ),
                Semantics(
                  button: true,
                  label: real
                      ? 'Switch to paper mode'
                      : 'Switch to real money mode',
                  child: TextButton.icon(
                    key: real == widget.real
                        ? const ValueKey('money-mode-switch')
                        : null,
                    onPressed: widget.onSwitch,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                    label: Text(real ? 'Real' : 'Paper'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: .13),
                      minimumSize: const Size(74, 44),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                real
                    ? widget.balance ?? '—'
                    : '\$${formatPaperForDisplay(widget.paper.paperValue)}',
                key: real ? const ValueKey('real-cash-balance') : null,
                style: type.displayLarge?.copyWith(
                  color: Colors.white,
                  fontSize: 44,
                  letterSpacing: -1.6,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    real
                        ? widget.balanceNote ?? 'USDC · Solana'
                        : (widget.paper.paperValueIsComplete
                              ? '${widget.paper.holdings.length} positions'
                              : widget.paper.paperValueState ==
                                    DeskPaperValueState.partial
                              ? 'Some prices unavailable'
                              : 'Position prices unavailable'),
                    style: type.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: .85),
                    ),
                  ),
                ),
                if (!real && latest.isNotEmpty)
                  SizedBox(
                    width: 40 + (latest.length - 1) * 26,
                    height: 42,
                    child: Stack(
                      children: [
                        for (var i = latest.length - 1; i >= 0; i--)
                          Positioned(
                            left: i * 26,
                            child: Container(
                              key: ValueKey(
                                'desk-stack-${latest[i].assetId}-${latest[i].variantMint}',
                              ),
                              padding: const EdgeInsets.all(2),
                              decoration: ShapeDecoration(
                                color: Colors.white,
                                shape: productSquircle(14),
                              ),
                              child: CompanyLogo(
                                name: latest[i].name,
                                color: const Color(0xFFDDD4F3),
                                logoUrl: latest[i].logoUrl,
                                size: 36,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
