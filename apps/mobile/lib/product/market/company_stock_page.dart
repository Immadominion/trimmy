import '../design/product_notice.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../markets/followed_stocks_controller.dart';
import '../../markets/history_models.dart';
import '../../markets/stock_history_panel.dart';
import '../../markets/stock_research_controller.dart';
import '../../social/relationships_controller.dart';
import '../career/own_reason_history.dart';
import '../career/reason_privacy_controller.dart';
import '../career/reason_sharing_repository.dart';
import 'market_craft.dart';
import 'stock_facts.dart';
import 'public_holders.dart';
import 'asset_price_chart.dart';
import '../design/product_empty_state.dart';
import '../../ui_review/review_animated_splash.dart';
import 'market_facts.dart';
import 'market_models.dart';
import 'paper_order_flow.dart';
import 'paper_portfolio.dart';
import 'paper_position_projection.dart';
import 'paper_order_repository.dart';
import 'stock_reasons_tab.dart';

enum MarketStockSection { about, holders, reasons }

class CompanyStockPage extends StatefulWidget {
  const CompanyStockPage({
    super.key,
    required this.details,
    required this.orderRepository,
    required this.clientOrderId,
    required this.availablePaper,
    required this.availableShares,
    this.recentOrders = const [],
    this.tradingAvailable = true,
    this.tradingMessage,
    this.reasonCaptureAvailable = false,
    this.researchController,
    this.factsController,
    this.following,
    this.reasonSharing,
    this.ownReasons,
    this.reasonPrivacy,
    this.relationships,
    this.onOpenSettings,
    this.onShare,
    this.onPriceAlert,
    this.onOrderConfirmed,
    this.onReasonSaved,
    this.now,
    this.onRealTrade,
    this.realPositionLabel,
    this.onRetryTrading,
  });

  final Future<void> Function(PaperOrderSide side)? onRealTrade;
  final MarketStockDetails details;
  final PaperOrderRepository orderRepository;
  final String Function() clientOrderId;
  final String availablePaper;
  final String availableShares;
  final String? realPositionLabel;
  final VoidCallback? onRetryTrading;
  final List<PaperPortfolioOrder> recentOrders;
  final bool tradingAvailable;
  final String? tradingMessage;
  final bool reasonCaptureAvailable;
  final StockResearchController? researchController;
  final MarketFactsController? factsController;
  final FollowedStocksController? following;

  /// Live shared reasons for this page's exact stock version. The read is
  /// never held beyond this page.
  final ReasonSharingRepository? reasonSharing;
  final OwnReasonHistory? ownReasons;
  final ReasonPrivacyController? reasonPrivacy;
  final RelationshipsController? relationships;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onShare;
  final VoidCallback? onPriceAlert;
  final ValueChanged<PaperOrderReceipt>? onOrderConfirmed;
  final ValueChanged<PaperReasonReceipt>? onReasonSaved;
  final DateTime Function()? now;

  @override
  State<CompanyStockPage> createState() => _CompanyStockPageState();
}

class _CompanyStockPageState extends State<CompanyStockPage> {
  MarketStockSection _section = MarketStockSection.about;
  StockInsight? _insight;
  StockInsight? _snapshot;
  String _period = 'day';
  bool _insightLoading = false;
  bool _insightFailed = false;
  int _insightGeneration = 0;
  final _insights = <String, StockInsight>{};
  StockInsightReader? get _insightReader {
    final reader = widget.factsController?.repository;
    return reader is StockInsightReader ? reader as StockInsightReader : null;
  }

  Future<void> _loadInsight([String? period, bool retry = false]) async {
    final mint = _company.primaryVariant?.mint;
    final reader = _insightReader;
    if (reader == null || mint == null) return;
    final next = period ?? _period;
    final generation = ++_insightGeneration;
    setState(() {
      _period = next;
      _insight = _insights[next];
      _insightLoading =
          _insight == null ||
          retry ||
          DateTime.now().isAfter(_insight!.refreshAfter);
      _insightFailed = false;
    });
    if (!_insightLoading) return;
    try {
      final data = await reader.insight(_company.assetId, mint, next);
      if (!mounted || generation != _insightGeneration) return;
      setState(() {
        _insight = data;
        _snapshot = data;
        _insights[next] = data;
        _insightLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _insightGeneration) return;
      setState(() {
        _insightLoading = false;
        _insightFailed = true;
      });
    }
  }

  PaperOrderReceipt? _confirmed;
  final List<AssetChartTrade> _sessionTrades = [];
  String get _availablePaper =>
      _confirmed?.cashAfterPaper ?? widget.availablePaper;
  String get _availableShares =>
      _confirmed?.positionShares ?? widget.availableShares;
  MarketPosition? get _currentPosition {
    final receipt = _confirmed;
    if (receipt == null) return widget.details.position;
    if (receipt.positionShares == '0') return null;
    final pending = pendingMarketPosition(receipt);
    // The receipt already contains the remaining position valued at the
    // accepted fill price. Do not leave a confirmed position in a loading state.
    final value = double.parse(receipt.positionValuePaper);
    final basis = double.parse(receipt.positionCostBasisPaper);
    return MarketPosition(
      shares: pending.shares,
      valuePaper: value.round(),
      averageCostPaper: pending.averageCostPaper,
      exactValuePaper: receipt.positionValuePaper,
      exactAverageCostPaper: pending.exactAverageCostPaper,
      gainPercent: basis > 0 ? (value - basis) / basis * 100 : null,
    );
  }

  List<AssetChartTrade> get _trades => [
    for (final order in widget.recentOrders)
      if (order.assetId == _company.assetId &&
          order.variantMint == _company.primaryVariant?.mint)
        AssetChartTrade(
          id: order.orderId,
          at: order.committedAt,
          price: double.parse(order.pricePaper),
          shares: order.quantity,
          buy: order.action == 'buy',
        ),
    ..._sessionTrades,
  ];

  bool _askedFollowing = false;
  bool _expandedDescription = false;

  MarketCompany get _company =>
      widget.factsController?.enrich(widget.details.company) ??
      widget.details.company;

  MarketFactsPhase get _factsPhase =>
      widget.factsController?.phase(widget.details.company.assetId) ??
      MarketFactsPhase.idle;

  @override
  void initState() {
    super.initState();
    _insightLoading = _insightReader != null;
    widget.following?.addListener(_followingChanged);
    widget.factsController?.addListener(_factsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFollowing());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFacts();
      if (mounted) _loadInsight();
    });
  }

  @override
  void didUpdateWidget(covariant CompanyStockPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.following, widget.following)) {
      oldWidget.following?.removeListener(_followingChanged);
      widget.following?.addListener(_followingChanged);
      _askedFollowing = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFollowing());
    }
    final factsChanged = !identical(
      oldWidget.factsController,
      widget.factsController,
    );
    final assetChanged =
        oldWidget.details.company.assetId != widget.details.company.assetId;
    final variantChanged =
        oldWidget.details.company.primaryVariant?.mint !=
        widget.details.company.primaryVariant?.mint;
    final modeChanged =
        (oldWidget.onRealTrade != null) != (widget.onRealTrade != null);
    if (factsChanged) {
      oldWidget.factsController?.removeListener(_factsChanged);
      widget.factsController?.addListener(_factsChanged);
    }
    if (factsChanged || assetChanged || variantChanged || modeChanged) {
      if (assetChanged || variantChanged || modeChanged) {
        _confirmed = null;
        _sessionTrades.clear();
      }
      _insightGeneration++;
      _insights.clear();
      _insight = null;
      _snapshot = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadFacts();
        if (mounted) _loadInsight();
      });
    }
  }

  @override
  void dispose() {
    widget.following?.removeListener(_followingChanged);
    widget.factsController?.removeListener(_factsChanged);
    super.dispose();
  }

  void _followingChanged() {
    if (mounted) setState(() {});
  }

  void _factsChanged() {
    if (mounted) setState(() {});
  }

  void _loadFacts() {
    final facts = widget.factsController;
    if (!mounted || facts == null || _insightReader != null) return;
    unawaited(facts.load(widget.details.company.assetId));
  }

  void _loadFollowing() {
    final following = widget.following;
    if (!mounted || following == null || _askedFollowing) return;
    _askedFollowing = true;
    if (!following.loaded && !following.busy) following.refresh();
  }

  Future<void> _toggleFollowing() async {
    final following = widget.following;
    if (following == null || following.busy) return;
    final wasFollowing = following.isFollowing(_company.assetId);
    if (wasFollowing) {
      await following.unfollow(_company.assetId);
    } else {
      await following.follow(_company.assetId);
    }
    if (!mounted || following.isFollowing(_company.assetId) != wasFollowing) {
      return;
    }
    showProductNotice(context, 'Following did not change. Try again.');
  }

  Future<void> _trade(PaperOrderSide side) async {
    if (widget.onRealTrade != null) {
      await widget.onRealTrade!(side);
      return;
    }
    if (!widget.tradingAvailable || _company.primaryVariant == null) return;
    await Navigator.of(context).push<PaperOrderReceipt>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaperOrderFlow(
          company: _company,
          side: side,
          repository: widget.orderRepository,
          clientOrderId: widget.clientOrderId,
          availablePaper: _availablePaper,
          availableShares: _availableShares,
          referencePrice: _snapshot?.priceUsd ?? _company.priceUsd,
          onConfirmed: (receipt) {
            if (mounted) {
              setState(() {
                _confirmed = receipt;
                if (receipt.unitPricePaper != null) {
                  _sessionTrades.add(
                    AssetChartTrade(
                      id: receipt.orderId,
                      at: receipt.confirmedAt,
                      price: double.parse(receipt.unitPricePaper!),
                      shares: receipt.filledShares,
                      buy: receipt.side == PaperOrderSide.buy,
                    ),
                  );
                }
              });
            }
            widget.onOrderConfirmed?.call(receipt);
          },
          onReasonSaved: widget.onReasonSaved,
          reasonCaptureAvailable: widget.reasonCaptureAvailable,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final followed = widget.following?.isFollowing(_company.assetId) ?? false;
    return Scaffold(
      backgroundColor: MarketPalette.paper,
      appBar: AppBar(
        backgroundColor: MarketPalette.paper,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            key: const ValueKey('stock-follow-button'),
            tooltip: followed
                ? 'Unfollow ${_company.name}'
                : 'Follow ${_company.name}',
            onPressed: widget.following == null || widget.following!.busy
                ? null
                : _toggleFollowing,
            icon: MarketActionIcon('star', selected: followed),
          ),
          if (widget.onShare != null)
            IconButton(
              key: const ValueKey('stock-share-button'),
              tooltip: 'Share ${_company.name}',
              onPressed: widget.onShare,
              icon: const MarketActionIcon('share'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            if (_insightReader != null) {
              await _loadInsight(null, true);
            } else {
              await widget.factsController?.load(_company.assetId, force: true);
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 28),
            children: [
              _inset(_header()),
              const SizedBox(height: 18),
              _inset(_price()),
              const SizedBox(height: 4),
              _chart(),
              if (widget.onRealTrade != null &&
                  (double.tryParse(widget.availableShares) ?? 0) > 0) ...[
                const SizedBox(height: 18),
                _inset(
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7F3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your position',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.realPositionLabel ??
                              '${widget.availableShares} ${_company.symbol} units',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_currentPosition != null) ...[
                const SizedBox(height: 20),
                _inset(_position(_currentPosition!)),
              ],
              const SizedBox(height: 24),
              _inset(_sectionSwitch()),
              const SizedBox(height: 14),
              _inset(
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: switch (_section) {
                    MarketStockSection.reasons => _reasons(),
                    MarketStockSection.holders => _holders(),
                    MarketStockSection.about => _about(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _tradeBar(),
    );
  }

  Widget _inset(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 22),
    child: child,
  );

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompanyLogo(
          name: _company.name,
          logoUrl: _company.logoUrl,
          color: _company.brandColor,
          size: 58,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _company.name,
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                cashtag(_company.primaryVariant?.symbol ?? _company.symbol),
                style: const TextStyle(
                  color: MarketPalette.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _price() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        shortPrice(_snapshot?.priceUsd ?? _company.priceUsd),
        style: const TextStyle(
          fontSize: 46,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if ((_snapshot?.changePercent24h ?? _company.dayChangePercent) !=
              null) ...[
            DirectionLabel(
              _snapshot?.changePercent24h ?? _company.dayChangePercent,
              textStyle: const TextStyle(fontSize: 15),
            ),
            const Text(
              'past 24h',
              style: TextStyle(color: MarketPalette.muted, fontSize: 13),
            ),
          ],
        ],
      ),
    ],
  );

  Widget _chart() {
    if (_insightReader == null) {
      return ProductStockHistory(
        company: _company,
        controller: widget.researchController,
        factsPhase: _factsPhase,
        now: widget.now,
      );
    }
    final data = _insight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: data != null && data.points.length >= 2
              ? AssetPriceChart(
                  key: ValueKey('asset-chart-$_period'),
                  points: data.points,
                  trades: _trades,
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 244),
                  child: Center(
                    child: _insightLoading
                        ? const TrimmyLiquidMark(size: 70)
                        : ProductEmptyState(
                            title: _insightFailed
                                ? 'Chart did not load'
                                : 'No chart yet',
                            message: _insightFailed
                                ? null
                                : 'This token needs more price history.',
                            action: TextButton(
                              onPressed: () => _loadInsight(null, true),
                              child: const Text('Try again'),
                            ),
                          ),
                  ),
                ),
        ),
        Row(
          children: [
            for (final entry in const {
              'day': '1D',
              'week': '1W',
              'month': '1M',
              'year': '1Y',
            }.entries)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Semantics(
                    selected: _period == entry.key,
                    child: TextButton(
                      key: ValueKey('asset-period-${entry.key}'),
                      style: TextButton.styleFrom(
                        foregroundColor: _period == entry.key
                            ? MarketPalette.ink
                            : MarketPalette.muted,
                        backgroundColor: _period == entry.key
                            ? const Color(0xFFF0EFF8)
                            : Colors.transparent,
                        shape: marketSquircle(20),
                      ),
                      onPressed: () => _loadInsight(entry.key),
                      child: Text(entry.value),
                    ),
                  ),
                ),
              ),
            if (widget.onPriceAlert != null)
              IconButton(
                key: const ValueKey('stock-price-alert'),
                tooltip: 'Set a price alert',
                onPressed: widget.onPriceAlert,
                icon: const MarketActionIcon('bell'),
              ),
          ],
        ),
        if (data != null && data.points.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
            child: Text(
              'Chart to ${_time(data.points.last.at)}',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, color: MarketPalette.muted),
            ),
          ),
      ],
    );
  }

  Widget _position(MarketPosition position) => Container(
    key: const ValueKey('stock-position-card'),
    padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
    decoration: ShapeDecoration(
      color: const Color(0xFFF3F0F8),
      shape: marketSquircle(32),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Your position',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF786D87),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: marketSquircle(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${position.shares} shares',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 24,
                runSpacing: 18,
                children: [
                  _positionMetric(
                    _confirmed == null ? 'Value' : 'Value at trade',
                    position.valuePaper == null
                        ? const Text('Not priced')
                        : PaperAmount(
                            position.exactValuePaper ??
                                '${position.valuePaper}',
                          ),
                  ),
                  _positionMetric(
                    'Average cost',
                    PaperAmount(
                      position.exactAverageCostPaper ??
                          '${position.averageCostPaper}',
                    ),
                  ),
                  if (position.gainPercent != null)
                    _positionMetric(
                      _confirmed == null ? 'Return' : 'Return at trade',
                      DirectionLabel(position.gainPercent!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _positionMetric(String label, Widget value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(color: MarketPalette.muted, fontSize: 12),
      ),
      const SizedBox(height: 5),
      DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        child: value,
      ),
    ],
  );

  Widget _sectionSwitch() => Semantics(
    container: true,
    label: 'Company details',
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: const Color(0xFFF5F5F8),
        shape: marketSquircle(18),
      ),
      child: Row(
        children: [
          for (final section in MarketStockSection.values)
            Expanded(
              child: Semantics(
                selected: section == _section,
                button: true,
                child: Material(
                  color: section == _section
                      ? MarketPalette.white
                      : Colors.transparent,
                  shape: marketSquircle(14),
                  child: InkWell(
                    key: ValueKey('stock-section-${section.name}'),
                    customBorder: marketSquircle(14),
                    onTap: () => setState(() => _section = section),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        switch (section) {
                          MarketStockSection.reasons => 'Comments',
                          MarketStockSection.holders => 'Holders',
                          MarketStockSection.about => 'About',
                        },
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _reasons() => StockReasonsTab(
    key: const ValueKey('stock-reasons-tab'),
    repository: widget.reasonSharing,
    assetId: _company.assetId,
    variantMint: _company.primaryVariant?.mint,
    ownReasons: widget.ownReasons,
    viewerPrivacy: widget.reasonPrivacy,
    relationships: widget.relationships,
    onOpenSettings: widget.onOpenSettings,
  );

  Widget _holders() {
    final repository = widget.factsController?.repository;
    return PublicHoldersView(
      key: ValueKey('public-holders-${_company.primaryVariant?.mint}'),
      mint: _company.primaryVariant?.mint,
      reader: repository is PublicHoldersReader
          ? repository as PublicHoldersReader
          : null,
    );
  }

  Widget _about() {
    final data = _snapshot;
    final description = data?.description ?? _company.description;
    final metrics = <(String, String)>[
      if (data?.volume24hUsd != null)
        ('24h volume', compactDollars(data!.volume24hUsd!)),
      if (data?.liquidityUsd != null)
        ('Liquidity', compactDollars(data!.liquidityUsd!)),
      if (data?.tokenMarketCapUsd != null)
        ('Token market cap', compactDollars(data!.tokenMarketCapUsd!)),
      if (data?.holders != null) ('Token holders', _count(data!.holders!)),
      if (data?.stockMarketCapUsd != null)
        ('Company market cap', compactDollars(data!.stockMarketCapUsd!)),
      if (_company.sector != null) ('Sector', _company.sector!),
    ];
    return Column(
      key: const ValueKey('stock-about'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (description != null) ...[
          Text(
            description,
            key: const ValueKey('stock-company-description'),
            maxLines: _expandedDescription ? null : 3,
            overflow: _expandedDescription
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          if (description.length > 150)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(
                  () => _expandedDescription = !_expandedDescription,
                ),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(_expandedDescription ? 'Read less' : 'Read more'),
              ),
            ),
          const SizedBox(height: 20),
        ],
        if (metrics.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 16,
              runSpacing: 18,
              children: [
                for (final item in metrics)
                  SizedBox(
                    width: (constraints.maxWidth - 16) / 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: const TextStyle(
                            color: MarketPalette.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (metrics.isNotEmpty) const SizedBox(height: 26),
        if (_company.asset.variants.isNotEmpty) ...[
          const Text(
            'Available tokens',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final version in _company.asset.variants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cashtag(version.symbol ?? _company.symbol),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (version.issuer != null || version.label != null)
                          Text(
                            version.issuer ?? version.label!,
                            style: const TextStyle(
                              color: MarketPalette.muted,
                              fontSize: 12,
                            ),
                          ),
                        if (version.advisory != null)
                          Text(
                            version.advisory!.reason,
                            style: const TextStyle(
                              color: MarketPalette.loss,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${version.mint.substring(0, 4)}…${version.mint.substring(version.mint.length - 4)}',
                    style: const TextStyle(
                      color: MarketPalette.muted,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    tooltip:
                        'Copy ${version.symbol ?? _company.symbol} address',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: version.mint),
                      );
                      if (mounted) {
                        showProductNotice(context, 'Address copied');
                      }
                    },
                    icon: const MarketActionIcon('copy'),
                  ),
                ],
              ),
            ),
        ],
        if (description == null &&
            metrics.isEmpty &&
            _company.asset.variants.isEmpty &&
            !_insightLoading)
          const ProductEmptyState(title: 'Details are on their way'),
      ],
    );
  }

  String _count(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );

  Widget _tradeBar() {
    final canBuy = widget.tradingAvailable && _company.primaryVariant != null;
    final canSell = canBuy && (double.tryParse(_availableShares) ?? 0) > 0;
    return DecoratedBox(
      decoration: const BoxDecoration(color: MarketPalette.paper),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.tradingAvailable && widget.tradingMessage != null) ...[
              Text(
                widget.tradingMessage!,
                key: const ValueKey('paper-trading-unavailable'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MarketPalette.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.onRetryTrading != null)
                TextButton(
                  onPressed: widget.onRetryTrading,
                  child: const Text('Retry'),
                ),
              const SizedBox(height: 9),
            ],
            Row(
              children: [
                Expanded(
                  child: MarketPrimaryButton(
                    key: const ValueKey('stock-buy-button'),
                    label: 'Buy',
                    color: MarketPalette.violet,
                    onPressed: canBuy ? () => _trade(PaperOrderSide.buy) : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MarketPrimaryButton(
                    key: const ValueKey('stock-sell-button'),
                    label: 'Sell',
                    onPressed: canSell
                        ? () => _trade(PaperOrderSide.sell)
                        : null,
                    color: const Color(0xFFEDE7FB),
                    foreground: const Color(0xFF6450A6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '$hour:$minute';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} · $hour:$minute';
  }
}

enum _ProductHistoryPeriod { day, week, month, year }

class ProductStockHistory extends StatefulWidget {
  const ProductStockHistory({
    super.key,
    required this.company,
    required this.controller,
    this.factsPhase = MarketFactsPhase.idle,
    this.now,
  });

  final MarketCompany company;
  final StockResearchController? controller;
  final MarketFactsPhase factsPhase;
  final DateTime Function()? now;

  @override
  State<ProductStockHistory> createState() => _ProductStockHistoryState();
}

class _ProductStockHistoryState extends State<ProductStockHistory> {
  _ProductHistoryPeriod _period = _ProductHistoryPeriod.week;
  StockHistoryRequest? _request;
  String? _message;
  var _generation = 0;

  bool get _supported =>
      widget.company.assetId == stockHistoryAssetId &&
      widget.company.primaryVariant?.mint == stockHistoryAaplxMint;

  bool get _hasFactsTrend =>
      widget.company.weekTrend.length >= 2 &&
      widget.company.weekTrend.every((point) => point.isFinite);

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _supported) _load(_ProductHistoryPeriod.week);
    });
  }

  @override
  void didUpdateWidget(covariant ProductStockHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_changed);
      widget.controller?.addListener(_changed);
      _request = null;
      _message = null;
      _generation++;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load(_ProductHistoryPeriod period) async {
    final controller = widget.controller;
    if (controller == null || !_supported) return;
    if (period == _ProductHistoryPeriod.year) {
      setState(() {
        _generation++;
        _period = period;
        _request = null;
        _message = 'A year of history is not available yet.';
      });
      return;
    }
    final mapped = switch (period) {
      _ProductHistoryPeriod.day => StockHistoryPeriod.day,
      _ProductHistoryPeriod.week => StockHistoryPeriod.week,
      _ProductHistoryPeriod.month => StockHistoryPeriod.month,
      _ProductHistoryPeriod.year => throw StateError('Handled above'),
    };
    final request = mapped.requestAt((widget.now ?? DateTime.now)());
    final generation = ++_generation;
    setState(() {
      _period = period;
      _request = request;
      _message = null;
    });
    try {
      await controller.loadTokensHistory(request);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _message = 'Price history is unavailable. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller == null || !_supported) {
      return _factsFallback();
    }
    final state = widget.controller!.tokensHistoryState;
    final matching = state.requestKey == _request;
    final data = matching ? state.data : null;
    final loading = matching && state.phase == StockResearchReadPhase.loading;
    final failed =
        matching &&
        (state.phase == StockResearchReadPhase.error ||
            state.phase == StockResearchReadPhase.offline);
    final stale = matching && state.phase == StockResearchReadPhase.stale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final period in _ProductHistoryPeriod.values)
              ChoiceChip(
                key: ValueKey('product-history-${period.name}'),
                label: Text(switch (period) {
                  _ProductHistoryPeriod.day => '1D',
                  _ProductHistoryPeriod.week => '1W',
                  _ProductHistoryPeriod.month => '1M',
                  _ProductHistoryPeriod.year => '1Y',
                }),
                selected: period == _period,
                onSelected: (_) => _load(period),
                showCheckmark: false,
                selectedColor: MarketPalette.yellow,
                shape: marketSquircle(13),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (loading)
          const LinearProgressIndicator(
            key: ValueKey('product-history-loading'),
            color: MarketPalette.pine,
          ),
        if (_message != null || failed)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                _message ?? 'Price history is unavailable. Try again.',
                style: const TextStyle(color: MarketPalette.muted),
              ),
            ),
          ),
        if (stale)
          Semantics(
            liveRegion: true,
            child: const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'This is an older reading. Refresh for a newer chart.',
                style: TextStyle(color: MarketPalette.muted),
              ),
            ),
          ),
        if (data != null && data.candles.length >= 2)
          StockHistoryChart(page: data),
        if (data != null && data.candles.length < 2 && !loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'There are not enough readings for this period.',
              style: TextStyle(color: MarketPalette.muted),
            ),
          ),
        if (data != null && data.candles.length < 2 && _hasFactsTrend)
          _factsFallback(),
        if (data == null &&
            !loading &&
            (_hasFactsTrend || (!failed && _message == null)))
          _factsFallback(),
      ],
    );
  }

  Widget _factsFallback() {
    final points = widget.company.weekTrend;
    if (_hasFactsTrend) {
      return Semantics(
        label: 'Seven day company price movement',
        image: true,
        child: ExcludeSemantics(
          child: Column(
            key: const ValueKey('stock-facts-sparkline'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => MiniTrend(
                  points: points,
                  color: MarketPalette.pine,
                  size: Size(constraints.maxWidth, 56),
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                '7-day listed stock movement',
                style: TextStyle(color: MarketPalette.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.factsPhase == MarketFactsPhase.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: LinearProgressIndicator(
          key: ValueKey('stock-facts-chart-loading'),
          color: MarketPalette.pine,
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'Price history is not available for this version yet.',
        key: ValueKey('stock-facts-chart-unavailable'),
        style: TextStyle(color: MarketPalette.muted),
      ),
    );
  }
}
