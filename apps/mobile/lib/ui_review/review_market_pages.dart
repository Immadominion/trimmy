import 'package:flutter/material.dart';

import 'review_components.dart';
import 'ui_review_app.dart';

enum ReviewMarketMode { starter, browse, search }

class ReviewMarketPage extends StatelessWidget {
  const ReviewMarketPage({
    super.key,
    required this.mode,
    required this.onBack,
    required this.onContinue,
  });

  final ReviewMarketMode mode;
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) {
    final starter = mode == ReviewMarketMode.starter;
    final search = mode == ReviewMarketMode.search;
    return Scaffold(
      backgroundColor: UiReviewColor.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                    sliver: SliverList.list(
                      children: [
                        Row(
                          children: [
                            ReviewIconButton(
                              icon: Icons.arrow_back_rounded,
                              label: 'Back',
                              onPressed: onBack,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                search ? 'Search' : 'Market',
                                style: const TextStyle(
                                  fontFamily: reviewDisplay,
                                  fontSize: 32,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (!starter)
                              ReviewIconButton(
                                icon: Icons.tune_rounded,
                                label: 'Sort market',
                                onPressed: () {},
                              ),
                          ],
                        ),
                        if (starter) ...[
                          const SizedBox(height: 17),
                          const ReviewSalMessage(
                            mood: 'teaching',
                            message:
                                "Here's 10,000 paper. Pick a company and buy your first position.",
                            background: UiReviewColor.lemon,
                          ),
                        ],
                        const SizedBox(height: 18),
                        _MarketSearchField(search: search),
                        if (search) ...[
                          const SizedBox(height: 22),
                          const ReviewSectionLabel('Results for “Apple”'),
                          const SizedBox(height: 12),
                          _SearchResult(
                            symbol: 'AAPL',
                            name: 'Apple',
                            price: '333.82',
                            change: '-0.66%',
                            color: UiReviewColor.pink,
                            onTap: onContinue,
                          ),
                          const SizedBox(height: 10),
                          _SearchResult(
                            symbol: 'APLE',
                            name: 'Apple Hospitality REIT',
                            price: '11.92',
                            change: '+0.20%',
                            color: UiReviewColor.mint,
                            onTap: () {},
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final label
                                    in starter
                                        ? const [
                                            'For you',
                                            'Familiar',
                                            'Large companies',
                                          ]
                                        : const [
                                            'Trending',
                                            'Movers',
                                            'Most held',
                                            'Following',
                                            'Tech',
                                          ]) ...[
                                  _MarketChip(
                                    label: label,
                                    selected:
                                        label ==
                                        (starter ? 'For you' : 'Trending'),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 23),
                          ReviewSectionLabel(
                            starter
                                ? 'A clear place to start'
                                : 'Moving on the floor',
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _CompanyCard(
                                symbol: 'AAPL',
                                name: 'Apple',
                                price: '333.82',
                                change: '-0.66%',
                                accent: UiReviewColor.pink,
                                heldBy: '3 friends',
                                onTap: onContinue,
                              ),
                              _CompanyCard(
                                symbol: 'NVDA',
                                name: 'Nvidia',
                                price: '201.44',
                                change: '+1.42%',
                                accent: UiReviewColor.mint,
                                heldBy: '42 hold',
                                onTap: () {},
                              ),
                              _CompanyCard(
                                symbol: 'TSLA',
                                name: 'Tesla',
                                price: '421.18',
                                change: '+0.38%',
                                accent: UiReviewColor.lemon,
                                heldBy: '18 hold',
                                onTap: () {},
                              ),
                              _CompanyCard(
                                symbol: 'META',
                                name: 'Meta',
                                price: '711.05',
                                change: '-0.19%',
                                accent: UiReviewColor.lilac,
                                heldBy: '2 friends',
                                onTap: () {},
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (mode == ReviewMarketMode.browse)
              const ReviewBottomTabs(selected: 'Market'),
          ],
        ),
      ),
    );
  }
}

class _MarketSearchField extends StatelessWidget {
  const _MarketSearchField({required this.search});

  final bool search;

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: ShapeDecoration(
      color: Colors.white,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: UiReviewColor.ink, width: 1.3),
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.search_rounded),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            search ? 'Apple' : 'Search company or ticker',
            style: TextStyle(
              color: search
                  ? UiReviewColor.ink
                  : UiReviewColor.ink.withValues(alpha: .5),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (search) const Icon(Icons.close_rounded, size: 20),
      ],
    ),
  );
}

class _MarketChip extends StatelessWidget {
  const _MarketChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: selected ? UiReviewColor.ink : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: UiReviewColor.ink.withValues(alpha: selected ? 1 : .18),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: selected ? Colors.white : UiReviewColor.ink,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.accent,
    required this.heldBy,
    required this.onTap,
  });

  final String symbol, name, price, change, heldBy;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 48) / 2;
    return SizedBox(
      width: width.clamp(142, 172),
      child: Material(
        color: Colors.white,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(25),
          side: const BorderSide(color: UiReviewColor.ink, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 106,
                padding: const EdgeInsets.all(13),
                color: accent,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: ReviewCompanyLogo(symbol: symbol, inverse: true),
                    ),
                    const Positioned.fill(
                      top: 38,
                      child: CustomPaint(painter: ReviewSparklinePainter()),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$symbol  $change',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$price paper',
                      style: TextStyle(
                        color: UiReviewColor.ink.withValues(alpha: .62),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 9),
                    Text(
                      heldBy,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResult extends StatelessWidget {
  const _SearchResult({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.color,
    required this.onTap,
  });

  final String symbol, name, price, change;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(21),
      side: BorderSide(color: UiReviewColor.ink.withValues(alpha: .18)),
    ),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      leading: ReviewCompanyLogo(symbol: symbol, color: color),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(symbol),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(price, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(
            change,
            style: const TextStyle(fontSize: 12, color: Color(0xFFB73549)),
          ),
        ],
      ),
    ),
  );
}

class ReviewCompanyLogo extends StatelessWidget {
  const ReviewCompanyLogo({
    super.key,
    required this.symbol,
    this.color = UiReviewColor.ink,
    this.inverse = false,
  });

  final String symbol;
  final Color color;
  final bool inverse;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: inverse ? UiReviewColor.ink : color,
      shape: BoxShape.circle,
      border: Border.all(
        color: inverse ? Colors.white : UiReviewColor.ink,
        width: 1.2,
      ),
    ),
    child: Text(
      symbol.characters.first,
      style: TextStyle(
        fontFamily: reviewDisplay,
        color: inverse ? Colors.white : UiReviewColor.paper,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class ReviewSparklinePainter extends CustomPainter {
  const ReviewSparklinePainter({this.color = UiReviewColor.ink});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      Offset(0, size.height * .72),
      Offset(size.width * .16, size.height * .48),
      Offset(size.width * .31, size.height * .58),
      Offset(size.width * .49, size.height * .27),
      Offset(size.width * .65, size.height * .39),
      Offset(size.width * .82, size.height * .14),
      Offset(size.width, size.height * .2),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant ReviewSparklinePainter oldDelegate) =>
      oldDelegate.color != color;
}

enum ReviewStockTab { overview, reasons, holders, about }

class ReviewStockPage extends StatelessWidget {
  const ReviewStockPage({
    super.key,
    required this.owned,
    required this.tab,
    required this.onBack,
    required this.onContinue,
  });

  final bool owned;
  final ReviewStockTab tab;
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: UiReviewColor.paper,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          ReviewIconButton(
                            icon: Icons.arrow_back_rounded,
                            label: 'Back',
                            onPressed: onBack,
                          ),
                          const Spacer(),
                          ReviewIconButton(
                            icon: Icons.notifications_none_rounded,
                            label: 'Set price alert',
                            onPressed: tab == ReviewStockTab.overview
                                ? onContinue
                                : () {},
                          ),
                          const SizedBox(width: 7),
                          ReviewIconButton(
                            icon: Icons.star_rounded,
                            label: 'Following Apple',
                            onPressed: () {},
                            background: UiReviewColor.lemon,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Row(
                        children: [
                          ReviewCompanyLogo(
                            symbol: 'AAPL',
                            color: UiReviewColor.pink,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Apple',
                                  style: TextStyle(
                                    fontFamily: reviewDisplay,
                                    fontSize: 28,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'AAPL  •  AAPLx',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.ios_share_rounded),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        owned ? '334.97 paper' : '333.82 paper',
                        style: const TextStyle(
                          fontFamily: reviewDisplay,
                          fontSize: 43,
                          height: 1,
                          letterSpacing: -1.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        owned
                            ? '+1.15  (+0.34%) today'
                            : '-2.21  (-0.66%) today',
                        style: TextStyle(
                          color: owned
                              ? UiReviewColor.pine
                              : const Color(0xFFB73549),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'On-chain price • updated now',
                        style: TextStyle(
                          color: UiReviewColor.ink.withValues(alpha: .55),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 19),
                      SizedBox(
                        height: 172,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: UiReviewColor.lilac,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(18),
                            child: CustomPaint(painter: _LargeChartPainter()),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _RangeLabel('1D', selected: true),
                          _RangeLabel('1W'),
                          _RangeLabel('1M'),
                          _RangeLabel('1Y'),
                        ],
                      ),
                      const SizedBox(height: 21),
                      const Text(
                        '3 friends and 41 others on the floor hold this.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Apple designs phones, computers, services and the systems that connect them.',
                        style: TextStyle(
                          color: UiReviewColor.ink.withValues(alpha: .72),
                          height: 1.42,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (owned) ...[
                        const SizedBox(height: 22),
                        _PositionBlock(onContinue: onContinue),
                      ],
                      const SizedBox(height: 24),
                      const _StockTabs(),
                      const SizedBox(height: 16),
                      switch (tab) {
                        ReviewStockTab.reasons => const _ReasonsContent(),
                        ReviewStockTab.holders => const _HoldersContent(),
                        ReviewStockTab.about => const _AboutContent(),
                        ReviewStockTab.overview => const SizedBox.shrink(),
                      },
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Row(
              children: [
                if (owned) ...[
                  Expanded(
                    child: ReviewPrimaryButton(
                      label: 'Trim',
                      onPressed: onContinue,
                      icon: null,
                      background: UiReviewColor.lemon,
                      foreground: UiReviewColor.ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ReviewPrimaryButton(
                    label: owned ? 'Sell' : 'Buy',
                    onPressed: onContinue,
                    icon: null,
                    background: owned ? UiReviewColor.ink : UiReviewColor.pine,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LargeChartPainter extends CustomPainter {
  const _LargeChartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = UiReviewColor.ink.withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    const ReviewSparklinePainter(
      color: UiReviewColor.violet,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RangeLabel extends StatelessWidget {
  const _RangeLabel(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? UiReviewColor.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: selected ? Colors.white : UiReviewColor.ink,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _PositionBlock extends StatelessWidget {
  const _PositionBlock({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => ReviewPaper(
    color: UiReviewColor.mint,
    shadow: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR POSITION',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(
              child: ReviewStat(label: 'shares', value: '1.497813'),
            ),
            Expanded(
              child: ReviewStat(label: 'value', value: '501.72'),
            ),
            Expanded(
              child: ReviewStat(label: 'gain', value: '+1.72'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Average cost 333.82 paper',
          style: TextStyle(
            color: UiReviewColor.ink.withValues(alpha: .7),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _StockTabs extends StatelessWidget {
  const _StockTabs();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(child: _StockTabLabel('Reasons', active: true)),
      Expanded(child: _StockTabLabel('Holders')),
      Expanded(child: _StockTabLabel('About')),
    ],
  );
}

class _StockTabLabel extends StatelessWidget {
  const _StockTabLabel(this.label, {this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: active ? UiReviewColor.violet : const Color(0xFFD8D1C2),
          width: active ? 3 : 1,
        ),
      ),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: active ? UiReviewColor.violet : UiReviewColor.ink,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _ReasonsContent extends StatelessWidget {
  const _ReasonsContent();

  @override
  Widget build(BuildContext context) => Column(
    children: const [
      _ReasonRow(
        handle: '@trimmydemo',
        reason: 'I use Apple every day, so I want to learn what moves it.',
        result: '+0.34%',
      ),
      SizedBox(height: 11),
      _ReasonRow(
        handle: '@mira',
        reason: 'Services revenue is the part I am watching.',
        result: '+2.10%',
      ),
    ],
  );
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.handle,
    required this.reason,
    required this.result,
  });

  final String handle, reason, result;

  @override
  Widget build(BuildContext context) => ReviewPaper(
    shadow: false,
    border: false,
    color: UiReviewColor.lilac,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(handle, style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(
              result,
              style: const TextStyle(
                color: UiReviewColor.pine,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          reason,
          style: const TextStyle(height: 1.38, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Entered at 333.82 paper',
          style: TextStyle(
            color: UiReviewColor.ink.withValues(alpha: .58),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _HoldersContent extends StatelessWidget {
  const _HoldersContent();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      _HolderRow(rank: 'ANALYST', handle: '@mira', result: '+2.10%'),
      Divider(),
      _HolderRow(rank: 'ROOKIE', handle: '@tobe', result: '-0.42%'),
      Divider(),
      _HolderRow(rank: 'ROOKIE', handle: '@trimmydemo', result: '+0.34%'),
    ],
  );
}

class _HolderRow extends StatelessWidget {
  const _HolderRow({
    required this.rank,
    required this.handle,
    required this.result,
  });

  final String rank, handle, result;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: UiReviewColor.lemon,
      child: Text(
        handle.substring(1, 2).toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    title: Text(handle, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text('$rank • avg 331.20'),
    trailing: Text(result, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _AboutContent extends StatelessWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Row(
        children: [
          Expanded(
            child: ReviewStat(label: 'market cap', value: '3.1T'),
          ),
          Expanded(
            child: ReviewStat(label: '52-week range', value: '169 to 342'),
          ),
          Expanded(
            child: ReviewStat(label: 'sector', value: 'Tech'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      ReviewPaper(
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text(
                  'AAPLx',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Spacer(),
                Text(
                  'VERIFIED',
                  style: TextStyle(
                    color: UiReviewColor.pine,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Issuer: Backed Finance • Backed 1:1 • No voting rights',
            ),
            const SizedBox(height: 9),
            Text(
              'Mint 9bb...aP4  •  trades 24/7',
              style: TextStyle(
                color: UiReviewColor.ink.withValues(alpha: .62),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

enum ReviewTicketKind { buy, trim, sell }

class ReviewTradeTicketPage extends StatefulWidget {
  const ReviewTradeTicketPage({
    super.key,
    required this.kind,
    required this.onBack,
    required this.onContinue,
  });

  final ReviewTicketKind kind;
  final VoidCallback onBack, onContinue;

  @override
  State<ReviewTradeTicketPage> createState() => _ReviewTradeTicketPageState();
}

class _ReviewTradeTicketPageState extends State<ReviewTradeTicketPage> {
  int preset = 1;

  @override
  Widget build(BuildContext context) {
    final buying = widget.kind == ReviewTicketKind.buy;
    final label = switch (widget.kind) {
      ReviewTicketKind.buy => 'Buy Apple',
      ReviewTicketKind.trim => 'Trim Apple',
      ReviewTicketKind.sell => 'Sell Apple',
    };
    final presets = buying
        ? const ['100', '500', '1,000', 'Max']
        : const ['25%', '50%', '75%', 'Max'];
    return ReviewPageScaffold(
      eyebrow: 'Paper order',
      title: label,
      subtitle: buying
          ? 'Choose how much paper to put into this position.'
          : 'Choose how much of your position leaves the desk.',
      onBack: widget.onBack,
      bottom: ReviewPrimaryButton(
        label: 'Review ${widget.kind.name}',
        onPressed: widget.onContinue,
        background: widget.kind == ReviewTicketKind.trim
            ? UiReviewColor.lemon
            : UiReviewColor.pine,
        foreground: widget.kind == ReviewTicketKind.trim
            ? UiReviewColor.ink
            : Colors.white,
      ),
      child: Column(
        children: [
          ReviewPaper(
            color: UiReviewColor.lilac,
            shadow: false,
            child: Column(
              children: [
                Text(
                  buying ? '500' : '25%',
                  style: const TextStyle(
                    fontFamily: reviewDisplay,
                    fontSize: 58,
                    height: 1,
                    letterSpacing: -2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  buying ? 'paper' : 'of 1.497813 shares',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (var index = 0; index < presets.length; index++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: index == presets.length - 1 ? 0 : 7,
                          ),
                          child: ChoiceChip(
                            label: SizedBox(
                              width: double.infinity,
                              child: Text(
                                presets[index],
                                textAlign: TextAlign.center,
                              ),
                            ),
                            selected: preset == index,
                            onSelected: (_) => setState(() => preset = index),
                            selectedColor: UiReviewColor.lemon,
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            showCheckmark: false,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _NumberPad(),
          const SizedBox(height: 24),
          ReviewPaper(
            shadow: false,
            child: Column(
              children: [
                _DetailRow(
                  label: buying ? 'Estimated shares' : 'Shares leaving',
                  value: buying ? '1.497813' : '0.374453',
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: buying ? 'Available paper' : 'Shares remaining',
                  value: buying ? '10,000' : '1.123360',
                ),
                const SizedBox(height: 10),
                const _DetailRow(label: 'Estimated fee', value: '0'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad();

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    childAspectRatio: 1.75,
    mainAxisSpacing: 6,
    crossAxisSpacing: 6,
    children: [
      for (final key in const [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '.',
        '0',
      ])
        Center(
          child: Text(
            key,
            style: const TextStyle(
              fontFamily: reviewDisplay,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      const Center(child: Icon(Icons.backspace_outlined)),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: UiReviewColor.ink.withValues(alpha: .65),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

class ReviewOrderReviewPage extends StatelessWidget {
  const ReviewOrderReviewPage({
    super.key,
    required this.selling,
    required this.onBack,
    required this.onContinue,
  });

  final bool selling;
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Check the receipt',
    title: selling ? 'Review your trim.' : 'Review your buy.',
    subtitle: 'Nothing moves until you confirm this exact order.',
    onBack: onBack,
    bottom: ReviewPrimaryButton(
      label: selling ? 'Confirm trim' : 'Confirm buy',
      onPressed: onContinue,
      background: selling ? UiReviewColor.lemon : UiReviewColor.pine,
      foreground: selling ? UiReviewColor.ink : Colors.white,
    ),
    child: Transform.rotate(
      angle: -.012,
      child: ReviewPaper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                ReviewCompanyLogo(symbol: 'AAPL', color: UiReviewColor.pink),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Apple • AAPLx',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  'PAPER',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _DetailRow(label: 'Action', value: selling ? 'Trim 25%' : 'Buy'),
            const SizedBox(height: 13),
            _DetailRow(
              label: 'Price',
              value: selling ? '334.97 paper' : '333.82 paper',
            ),
            const SizedBox(height: 13),
            _DetailRow(
              label: 'Shares',
              value: selling ? '0.374453' : '1.497813',
            ),
            const SizedBox(height: 13),
            const _DetailRow(label: 'Fee', value: '0'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 17),
              child: Divider(),
            ),
            _DetailRow(
              label: selling ? 'Estimated proceeds' : 'Total',
              value: selling ? '125.43 paper' : '500 paper',
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(12),
              color: UiReviewColor.lilac,
              child: const Text(
                'Practice order. No real money or token will move.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ReviewTradeReportPage extends StatelessWidget {
  const ReviewTradeReportPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Trade report • confirmed',
    title: 'Your first position.',
    subtitle: 'Apple is now on your paper desk.',
    background: UiReviewColor.lilac,
    bottom: ReviewPrimaryButton(label: 'Save my reason', onPressed: onContinue),
    child: Column(
      children: [
        Transform.rotate(
          angle: .015,
          child: ReviewPaper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    ReviewCompanyLogo(
                      symbol: 'AAPL',
                      color: UiReviewColor.pink,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '1.497813 shares',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(Icons.check_circle_rounded, color: UiReviewColor.pine),
                  ],
                ),
                const SizedBox(height: 20),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ReviewStat(label: 'spent', value: '500'),
                    ReviewStat(label: 'position', value: '500.00'),
                    ReviewStat(label: 'fee', value: '0'),
                  ],
                ),
                const SizedBox(height: 19),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'FIRST BUY MISSION',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                const ReviewProgress(value: 1, color: UiReviewColor.pine),
                const SizedBox(height: 6),
                const Text(
                  '+20 Trims ready to collect',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 27),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Why did you buy?',
            style: TextStyle(
              fontFamily: reviewDisplay,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          initialValue:
              'I use Apple every day, so I want to learn what moves it.',
          maxLines: 3,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: UiReviewColor.ink),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(
                color: UiReviewColor.ink,
                width: 1.3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A saved reason can earn 10 Trims. Your first one also completes a 20 Trim mission.',
          style: TextStyle(
            color: UiReviewColor.ink.withValues(alpha: .63),
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class ReviewFirstPositionPage extends StatelessWidget {
  const ReviewFirstPositionPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: UiReviewColor.violet,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          children: [
            const Text(
              'FIRST POSITION',
              style: TextStyle(
                color: UiReviewColor.lemon,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'You are on the floor.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: reviewDisplay,
                color: Colors.white,
                fontSize: 39,
                height: .98,
                fontWeight: FontWeight.w800,
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned(
                    left: -20,
                    bottom: 8,
                    child: ReviewSal(mood: 'celebrating', width: 220),
                  ),
                  Positioned(
                    right: 0,
                    top: 42,
                    child: Transform.rotate(
                      angle: .05,
                      child: ReviewPaper(
                        color: UiReviewColor.lemon,
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '+50',
                              style: TextStyle(
                                fontFamily: reviewDisplay,
                                fontSize: 48,
                                height: 1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'TRIMS',
                              style: TextStyle(
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 13),
                            Text('20  first buy'),
                            Text('10  written reason'),
                            Text('20  first reason'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Text(
              'Trims are points. You get them for getting better, not for spending.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ReviewPrimaryButton(
              label: 'Collect 50 Trims',
              onPressed: onContinue,
              background: UiReviewColor.lemon,
              foreground: UiReviewColor.ink,
            ),
          ],
        ),
      ),
    ),
  );
}

class ReviewStreakPage extends StatelessWidget {
  const ReviewStreakPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'A habit begins',
    title: 'Day 1.',
    subtitle: 'A trade, mission or note keeps your floor streak alive.',
    background: UiReviewColor.lemon,
    bottom: ReviewPrimaryButton(label: 'Continue', onPressed: onContinue),
    child: Column(
      children: [
        const SizedBox(height: 18),
        const Icon(
          Icons.local_fire_department_rounded,
          size: 150,
          color: UiReviewColor.pink,
        ),
        const SizedBox(height: 8),
        const Text(
          '1',
          style: TextStyle(
            fontFamily: reviewDisplay,
            fontSize: 76,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Text(
          'DAY STREAK',
          style: TextStyle(letterSpacing: 1.4, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 32),
        ReviewPaper(
          shadow: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final day in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Column(
                  children: [
                    Text(
                      day,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(
                        color: day == 'S'
                            ? UiReviewColor.pink
                            : const Color(0xFFE4DECF),
                        shape: BoxShape.circle,
                      ),
                      child: day == 'S'
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ReviewDeskPage extends StatelessWidget {
  const ReviewDeskPage({
    super.key,
    required this.onContinue,
    this.state = 'holding',
  });

  final VoidCallback onContinue;
  final String state;

  @override
  Widget build(BuildContext context) {
    final empty = state == 'empty';
    final stale = state == 'stale';
    return Scaffold(
      backgroundColor: UiReviewColor.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: UiReviewColor.violet,
                        child: Text(
                          'O',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '@trimmydemo',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'Rookie • Day 1',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      _TinyCounter(
                        icon: Icons.local_fire_department_rounded,
                        value: '1',
                      ),
                      const SizedBox(width: 6),
                      _TinyCounter(
                        icon: Icons.content_cut_rounded,
                        value: '50',
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: onContinue,
                        icon: const Icon(Icons.notifications_none_rounded),
                      ),
                    ],
                  ),
                  if (stale) ...[
                    const SizedBox(height: 12),
                    const ReviewPreviewNotice(
                      text:
                          'Prices are a little old. Your confirmed shares and paper cash are safe.',
                    ),
                  ],
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: UiReviewColor.ink,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Expanded(
                              child: Text(
                                'YOUR PAPER DESK',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              'Add money',
                              style: TextStyle(
                                color: UiReviewColor.lemon,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Text(
                          empty ? '10,000.00' : '10,001.72',
                          style: const TextStyle(
                            fontFamily: reviewDisplay,
                            color: Colors.white,
                            fontSize: 42,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          empty ? 'No change yet' : '+1.72  (+0.02%)',
                          style: const TextStyle(
                            color: UiReviewColor.mint,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 19),
                        const SizedBox(
                          height: 80,
                          child: CustomPaint(
                            painter: ReviewSparklinePainter(
                              color: UiReviewColor.mint,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text(
                              '1D',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text('1W', style: TextStyle(color: Colors.white54)),
                            Text('1M', style: TextStyle(color: Colors.white54)),
                            Text('1Y', style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Wall Street opens in 2h 14m • Trimmy trades 24/7',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 24),
                  const ReviewSalMessage(
                    mood: 'deadpan',
                    message:
                        'One position. One reason. This is already more thoughtful than most desks.',
                  ),
                  const SizedBox(height: 22),
                  const ReviewSectionLabel('Today'),
                  const SizedBox(height: 11),
                  ReviewPaper(
                    shadow: false,
                    color: UiReviewColor.lemon,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MISSION',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Follow 3 companies',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 10),
                        ReviewProgress(value: 1 / 3),
                        SizedBox(height: 6),
                        Text(
                          '1 of 3 • +20 Trims',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ReviewSectionLabel(
                    'Holdings',
                    trailing: TextButton(
                      onPressed: onContinue,
                      child: const Text('See all'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (empty)
                    ReviewPaper(
                      shadow: false,
                      child: Column(
                        children: [
                          const Text(
                            'Your desk is empty.',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text('Buy your first stock with paper.'),
                          const SizedBox(height: 16),
                          ReviewPrimaryButton(
                            label: 'Open Market',
                            onPressed: onContinue,
                          ),
                        ],
                      ),
                    )
                  else
                    _HoldingRow(onTap: onContinue),
                ],
              ),
            ),
            const ReviewBottomTabs(selected: 'Desk'),
          ],
        ),
      ),
    );
  }
}

class _TinyCounter extends StatelessWidget {
  const _TinyCounter({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: UiReviewColor.lilac,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(color: UiReviewColor.ink.withValues(alpha: .16)),
    ),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      leading: const ReviewCompanyLogo(
        symbol: 'AAPL',
        color: UiReviewColor.pink,
      ),
      title: const Text('Apple', style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: const Text('1.497813 shares'),
      trailing: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('501.72', style: TextStyle(fontWeight: FontWeight.w800)),
          Text(
            '+0.34%',
            style: TextStyle(
              color: UiReviewColor.pine,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class ReviewPortfolioPage extends StatelessWidget {
  const ReviewPortfolioPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Paper desk',
    title: 'Portfolio',
    subtitle: 'Every confirmed position and paper movement.',
    onBack: onBack,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Expanded(
              child: ReviewStat(label: 'desk value', value: '10,001.72'),
            ),
            Expanded(
              child: ReviewStat(label: 'cash', value: '9,500'),
            ),
            Expanded(
              child: ReviewStat(label: 'invested', value: '501.72'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Container(
          height: 142,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: UiReviewColor.ink,
            borderRadius: BorderRadius.circular(26),
          ),
          child: const CustomPaint(
            painter: ReviewSparklinePainter(color: UiReviewColor.mint),
          ),
        ),
        const SizedBox(height: 26),
        const ReviewSectionLabel('Holdings'),
        const SizedBox(height: 11),
        _HoldingRow(onTap: onContinue),
        const SizedBox(height: 26),
        const ReviewSectionLabel('Trade log'),
        const SizedBox(height: 10),
        ReviewPaper(
          shadow: false,
          child: const Column(
            children: [
              _TradeLogRow(
                action: 'Bought',
                amount: '500 paper',
                when: 'Today • 10:42',
              ),
              Divider(height: 24),
              _TradeLogRow(
                action: 'Desk opened',
                amount: '10,000 paper',
                when: 'Today • 10:38',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TradeLogRow extends StatelessWidget {
  const _TradeLogRow({
    required this.action,
    required this.amount,
    required this.when,
  });

  final String action, amount, when;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: UiReviewColor.mint,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.receipt_long_rounded, size: 20),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(action, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(when, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
      Text(amount, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

class ReviewPriceAlertPage extends StatefulWidget {
  const ReviewPriceAlertPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack, onContinue;

  @override
  State<ReviewPriceAlertPage> createState() => _ReviewPriceAlertPageState();
}

class _ReviewPriceAlertPageState extends State<ReviewPriceAlertPage> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Apple • AAPL',
    title: 'Price alert',
    subtitle: 'Sal will ring once when Apple moves this far from 333.82 paper.',
    onBack: widget.onBack,
    bottom: ReviewPrimaryButton(
      label: 'Set 5% alert',
      onPressed: widget.onContinue,
    ),
    child: Column(
      children: [
        const Icon(
          Icons.notifications_active_rounded,
          size: 98,
          color: UiReviewColor.violet,
        ),
        const SizedBox(height: 24),
        ReviewChoice(
          title: '5% move',
          subtitle: 'At 317.13 or 350.51 paper',
          selected: selected == 0,
          onTap: () => setState(() => selected = 0),
          color: UiReviewColor.lemon,
        ),
        const SizedBox(height: 11),
        ReviewChoice(
          title: '10% move',
          subtitle: 'At 300.44 or 367.20 paper',
          selected: selected == 1,
          onTap: () => setState(() => selected = 1),
          color: UiReviewColor.lemon,
        ),
      ],
    ),
  );
}
