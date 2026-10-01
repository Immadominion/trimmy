import '../../l10n/l10n.dart';
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

/// One of this company's tokens in Real mode, labelled by issuer and symbol,
/// such as `Ondo · NVDAon`. An unavailable token carries its reason.
@immutable
class StockVariantChoice {
  const StockVariantChoice({
    required this.mint,
    required this.label,
    this.tradeable = true,
    this.reason,
    this.marketNote,
    this.marketOpen = true,
  });
  final String mint, label;
  final bool tradeable;
  final String? reason;

  /// For a tradeable token whose market is not always open, such as
  /// `Closed · opens Mon 1:05 AM`.
  final String? marketNote;
  final bool marketOpen;
}

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
    this.variantChoices = const [],
    this.onSelectVariant,
    this.onPracticeInPaper,
  });

  final Future<void> Function(PaperOrderSide side)? onRealTrade;

  /// Every Real mode token of this company, tradeable ones first. With more
  /// than one, a picker sits above Buy and Sell; [details] carries the
  /// chosen token.
  final List<StockVariantChoice> variantChoices;
  final ValueChanged<String>? onSelectVariant;

  /// Offered when real money cannot trade this company at all.
  final VoidCallback? onPracticeInPaper;
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
    showProductNotice(context, context.l10n.marketFollowUnchanged);
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
    final l10n = context.l10n;
    final followed = widget.following?.isFollowing(_company.assetId) ?? false;
    return Scaffold(
      backgroundColor: MarketPalette.paper,
      appBar: AppBar(
        backgroundColor: MarketPalette.paper,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: l10n.commonBack,
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            key: const ValueKey('stock-follow-button'),
            tooltip: followed
                ? l10n.stockUnfollowTooltip(_company.name)
                : l10n.stockFollowTooltip(_company.name),
            onPressed: widget.following == null || widget.following!.busy
                ? null
                : _toggleFollowing,
            icon: MarketActionIcon('star', selected: followed),
          ),
          if (widget.onShare != null)
            IconButton(
              key: const ValueKey('stock-share-button'),
              tooltip: l10n.stockShareTooltip(_company.name),
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
                          l10n.stockPositionTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.realPositionLabel ??
                              '${context.formats.number(widget.availableShares)} ${_company.primaryVariant?.symbol ?? _company.symbol}',
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
        shortPrice(_snapshot?.priceUsd ?? _company.priceUsd, context.formats),
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
            Text(
              context.l10n.stockPast24h,
              style: const TextStyle(color: MarketPalette.muted, fontSize: 13),
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
    final l10n = context.l10n;
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
                                ? l10n.stockChartFailedTitle
                                : l10n.stockChartEmptyTitle,
                            message: _insightFailed
                                ? null
                                : l10n.stockChartEmptyBody,
                            action: TextButton(
                              onPressed: () => _loadInsight(null, true),
                              child: Text(l10n.commonTryAgain),
                            ),
                          ),
                  ),
                ),
        ),
        Row(
          children: [
            for (final entry in {
              'day': l10n.chartPeriodDay,
              'week': l10n.chartPeriodWeek,
              'month': l10n.chartPeriodMonth,
              'year': l10n.chartPeriodYear,
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
                tooltip: l10n.stockPriceAlertTooltip,
                onPressed: widget.onPriceAlert,
                icon: const MarketActionIcon('bell'),
              ),
          ],
        ),
        if (data != null && data.points.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
            child: Text(
              l10n.stockChartUpdatedAt(
                _time(data.points.last.at, context.formats),
              ),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, color: MarketPalette.muted),
            ),
          ),
      ],
    );
  }

  Widget _position(MarketPosition position) {
    final l10n = context.l10n;
    return Container(
      key: const ValueKey('stock-position-card'),
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
      decoration: ShapeDecoration(
        color: const Color(0xFFF3F0F8),
        shape: marketSquircle(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.stockPositionTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
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
                  l10n.stockPositionShares(
                    double.tryParse(position.shares.replaceAll(',', '')) ?? 0,
                    context.formats.number(position.shares),
                  ),
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
                      _confirmed == null
                          ? l10n.stockPositionValue
                          : l10n.stockPositionValueAtTrade,
                      position.valuePaper == null
                          ? Text(l10n.stockPositionNotPriced)
                          : PaperAmount(
                              position.exactValuePaper ??
                                  '${position.valuePaper}',
                            ),
                    ),
                    _positionMetric(
                      l10n.stockPositionAverageCost,
                      PaperAmount(
                        position.exactAverageCostPaper ??
                            '${position.averageCostPaper}',
                      ),
                    ),
                    if (position.gainPercent != null)
                      _positionMetric(
                        _confirmed == null
                            ? l10n.stockPositionReturn
                            : l10n.stockPositionReturnAtTrade,
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
  }

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
    label: context.l10n.stockSectionsLabel,
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
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 4,
                      ),
                      // Longer labels (French "Commentaires") shrink to fit
                      // instead of fading out.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          switch (section) {
                            MarketStockSection.reasons =>
                              context.l10n.stockSectionComments,
                            MarketStockSection.holders =>
                              context.l10n.stockSectionHolders,
                            MarketStockSection.about =>
                              context.l10n.stockSectionAbout,
                          },
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
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
    final l10n = context.l10n;
    final formats = context.formats;
    final data = _snapshot;
    final description = data?.description ?? _company.description;
    final metrics = <(String, String)>[
      if (data?.volume24hUsd != null)
        (l10n.stockMetricVolume24h, formats.compactUsd(data!.volume24hUsd!)),
      if (data?.liquidityUsd != null)
        (l10n.stockMetricLiquidity, formats.compactUsd(data!.liquidityUsd!)),
      if (data?.tokenMarketCapUsd != null)
        (
          l10n.stockMetricTokenMarketCap,
          formats.compactUsd(data!.tokenMarketCapUsd!),
        ),
      if (data?.holders != null)
        (l10n.stockMetricTokenHolders, formats.integer(data!.holders!)),
      if (data?.stockMarketCapUsd != null)
        (
          l10n.stockMetricCompanyMarketCap,
          formats.compactUsd(data!.stockMarketCapUsd!),
        ),
      if (_company.sector != null) (l10n.stockMetricSector, _company.sector!),
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
                child: Text(
                  _expandedDescription
                      ? l10n.stockAboutReadLess
                      : l10n.stockAboutReadMore,
                ),
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
          Text(
            l10n.stockTokensTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
                    tooltip: l10n.stockCopyAddressTooltip(
                      version.symbol ?? _company.symbol,
                    ),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: version.mint),
                      );
                      if (mounted) {
                        showProductNotice(
                          context,
                          context.l10n.stockAddressCopied,
                        );
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
          ProductEmptyState(title: l10n.stockAboutEmpty),
      ],
    );
  }

  Widget _tradeBar() {
    final l10n = context.l10n;
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
                  child: Text(l10n.commonRetry),
                ),
              if (widget.onPracticeInPaper != null)
                TextButton(
                  key: const ValueKey('stock-practice-paper'),
                  onPressed: widget.onPracticeInPaper,
                  child: Text(l10n.stockPracticeInPaper),
                ),
              const SizedBox(height: 9),
            ],
            if (widget.variantChoices.length > 1) ...[
              _variantPicker(),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: MarketPrimaryButton(
                    key: const ValueKey('stock-buy-button'),
                    label: l10n.commonBuy,
                    color: MarketPalette.violet,
                    onPressed: canBuy ? () => _trade(PaperOrderSide.buy) : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MarketPrimaryButton(
                    key: const ValueKey('stock-sell-button'),
                    label: l10n.commonSell,
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

  Widget _variantPicker() {
    final l10n = context.l10n;
    final selected = widget.variantChoices
        .where((c) => c.tradeable && c.mint == _company.primaryVariant?.mint)
        .firstOrNull;
    return Semantics(
      button: true,
      label: selected == null
          ? l10n.stockVersionsLabel
          : l10n.stockVersionSelectedLabel(selected.label),
      onTap: _chooseVariant,
      child: ExcludeSemantics(
        child: Material(
          color: const Color(0xFFF0EFF8),
          shape: marketSquircle(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('stock-variant-picker'),
            onTap: _chooseVariant,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected?.label ??
                            l10n.stockVersionsCount(
                              widget.variantChoices.length,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.expand_more_rounded,
                      color: MarketPalette.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseVariant() async {
    final selected = _company.primaryVariant?.mint;
    final mint = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: MarketPalette.paper,
      shape: marketSquircle(28),
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * .8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                sheet.l10n.stockVersionsTitle,
                style: Theme.of(
                  sheet,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            for (final choice in widget.variantChoices)
              ListTile(
                key: ValueKey('stock-variant-${choice.mint}'),
                enabled: choice.tradeable,
                shape: marketSquircle(16),
                tileColor: choice.mint == selected
                    ? const Color(0xFFF1EBFF)
                    : null,
                title: Text(
                  choice.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  choice.tradeable
                      ? choice.marketNote ?? sheet.l10n.marketTradeable
                      : choice.reason ?? sheet.l10n.stockVersionNotTradeable,
                  style: choice.tradeable && choice.marketOpen
                      ? const TextStyle(
                          color: MarketPalette.pine,
                          fontWeight: FontWeight.w700,
                        )
                      : null,
                ),
                trailing: choice.mint == selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: MarketPalette.violet,
                      )
                    : null,
                onTap: choice.tradeable
                    ? () => Navigator.pop(sheet, choice.mint)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (mint != null && mint != selected && mounted) {
      widget.onSelectVariant?.call(mint);
    }
  }

  /// "14:05" today, otherwise "30 Sep · 14:05", in [formats]' language.
  static String _time(DateTime value, AppFormats formats) {
    final local = value.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return formats.time24(local);
    }
    return '${formats.dayMonth(local)} · ${formats.time24(local)}';
  }
}

enum _ProductHistoryPeriod { day, week, month, year }

/// Why the history chart shows a message instead of a chart.
enum _HistoryIssue { noYear, unavailable }

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
  _HistoryIssue? _issue;
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
      _issue = null;
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
        _issue = _HistoryIssue.noYear;
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
      _issue = null;
    });
    try {
      await controller.loadTokensHistory(request);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _issue = _HistoryIssue.unavailable);
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
    final l10n = context.l10n;
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
                  _ProductHistoryPeriod.day => l10n.chartPeriodDay,
                  _ProductHistoryPeriod.week => l10n.chartPeriodWeek,
                  _ProductHistoryPeriod.month => l10n.chartPeriodMonth,
                  _ProductHistoryPeriod.year => l10n.chartPeriodYear,
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
        if (_issue != null || failed)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                _issue == _HistoryIssue.noYear
                    ? l10n.chartNoYear
                    : l10n.chartHistoryUnavailable,
                style: const TextStyle(color: MarketPalette.muted),
              ),
            ),
          ),
        if (stale)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                l10n.chartStaleReading,
                style: const TextStyle(color: MarketPalette.muted),
              ),
            ),
          ),
        if (data != null && data.candles.length >= 2)
          StockHistoryChart(page: data),
        if (data != null && data.candles.length < 2 && !loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              l10n.chartNotEnoughReadings,
              style: const TextStyle(color: MarketPalette.muted),
            ),
          ),
        if (data != null && data.candles.length < 2 && _hasFactsTrend)
          _factsFallback(),
        if (data == null &&
            !loading &&
            (_hasFactsTrend || (!failed && _issue == null)))
          _factsFallback(),
      ],
    );
  }

  Widget _factsFallback() {
    final l10n = context.l10n;
    final points = widget.company.weekTrend;
    if (_hasFactsTrend) {
      return Semantics(
        label: l10n.chartSevenDayLabel,
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
              Text(
                l10n.chartSevenDayCaption,
                style: const TextStyle(
                  color: MarketPalette.muted,
                  fontSize: 12,
                ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        l10n.chartNoHistoryForVersion,
        key: const ValueKey('stock-facts-chart-unavailable'),
        style: const TextStyle(color: MarketPalette.muted),
      ),
    );
  }
}
