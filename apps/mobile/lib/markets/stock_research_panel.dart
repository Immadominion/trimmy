import 'package:flutter/material.dart';

import '../design_study/craft.dart';
import 'discovery.dart';
import 'history_models.dart';
import 'stock_history_panel.dart';
import 'followed_stocks.dart';
import 'followed_stocks_controller.dart';
import 'stock_research_controller.dart';
import 'validation.dart' show StockResearchException;

/// Reaches the public stock research runtime from the app.
///
/// This panel reads and nothing else. There is no amount field, no side, no
/// venue choice and no order control, because the runtime behind it has
/// `walletAccess`, `signing`, `broadcast` and `execution` all false. Every
/// number shown is one provider's own reading, reported as such.
///
/// Company discovery leads into issuer-specific details and the supported
/// token-history chart. No account is needed to explore public readings.
class StockResearchPanel extends StatefulWidget {
  const StockResearchPanel({
    super.key,
    required this.controller,
    this.configurationFailed = false,
    this.now,
    this.following,
  });

  final StockResearchController controller;
  final DateTime Function()? now;

  /// The signed-in account's followed list, or null for a guest. Keeping an
  /// asset needs an account; looking one up does not.
  final FollowedStocksController? following;

  /// The host could not read a usable API origin for this build.
  final bool configurationFailed;

  @override
  State<StockResearchPanel> createState() => _StockResearchPanelState();
}

class _StockResearchPanelState extends State<StockResearchPanel> {
  final _query = TextEditingController();

  /// A read refused before it was dispatched, which never reaches state.
  String? _refused;

  /// The asset whose full variant list was asked for, if any.
  String? _variantsOf;
  ({
    StockDiscoveryAsset asset,
    StockVariant variant,
    StockDiscoveryProvenance provenance,
  })?
  _detail;
  var _requestGeneration = 0;

  /// The followed list is read once when this panel is opened, because opening
  /// it is the request to see what is kept. Nothing polls.
  bool _askedFollowing = false;

  @override
  void initState() {
    super.initState();
    _query.text = widget.controller.discoveryState.search.data?.query ?? '';
    widget.controller.addListener(_changed);
    widget.following?.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant StockResearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
    _requestGeneration++;
    _query.text = widget.controller.discoveryState.search.data?.query ?? '';
    _refused = null;
    _variantsOf = null;
    _detail = null;
  }

  @override
  void dispose() {
    widget.following?.removeListener(_changed);
    widget.controller.removeListener(_changed);
    _query.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Plain language for a runtime or provider code. No code and no provider
  /// detail reaches the reader.
  String _message(String? code) => switch (code) {
    'STOCK_RESEARCH_RUNTIME_DISABLED' =>
      'Stock prices are not set up in this build.',
    'STOCK_RESEARCH_RUNTIME_OFFLINE' => 'No connection, so nothing was read.',
    'STOCK_RESEARCH_RUNTIME_BACKGROUND' =>
      'Paused while the app is in the background.',
    'STOCK_RESEARCH_RUNTIME_CLOSED' => 'Stock prices are closed.',
    'STOCK_INPUT_INVALID' => 'That is not something this can look up.',
    'STOCK_RATE_LIMITED' => 'Too many looks in a row. Wait a moment.',
    'STOCK_TIMEOUT' => 'That took too long. Try again.',
    'STOCK_NETWORK_ERROR' => 'That did not reach the server. Try again.',
    'STOCK_DATA_STALE' || 'STOCK_RESEARCH_DATA_STALE' =>
      'This reading has passed its refresh time. Search again for a newer one.',
    'STOCK_CANCELLED' => 'That search was replaced by a newer one.',
    _ => 'Prices are unavailable right now.',
  };

  String _advisory(StockAdvisory advisory) => switch (advisory.status) {
    StockAdvisoryStatus.blocked => 'The provider has blocked this one.',
    StockAdvisoryStatus.compromised =>
      'The provider reports this one as compromised.',
    StockAdvisoryStatus.caution => 'The provider flags this one for caution.',
    StockAdvisoryStatus.unknown => 'The provider flags this one.',
  };

  static String _grouped(String digits) {
    final out = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) out.write(',');
      out.write(digits[index]);
    }
    return out.toString();
  }

  /// Provider metrics are non-negative and finite, or absent. An absent number
  /// is said to be absent rather than shown as zero.
  static String _money(num? value, {bool price = false}) {
    if (value == null) return 'not given';
    final amount = value.toDouble();
    if (amount == 0) return price ? '\$0.00' : '\$0';
    if (amount < 0.0001) return '<\$0.0001';
    if (amount >= 1) {
      final parts = amount.toStringAsFixed(2).split('.');
      final fraction = !price && parts.last == '00' ? '' : '.${parts.last}';
      return '\$${_grouped(parts.first)}$fraction';
    }
    return '\$${amount.toStringAsFixed(4)}';
  }

  void _search() {
    _requestGeneration++;
    final query = _query.text.trim();
    setState(() {
      _refused = null;
      _variantsOf = null;
    });
    if (query.isEmpty) {
      setState(() => _refused = 'Type a company name or symbol first.');
      return;
    }
    if (query.length > 80) {
      setState(() => _refused = 'That is too long to look up.');
      return;
    }
    FocusScope.of(context).unfocus();
    _dispatch(() => widget.controller.search(query));
  }

  void _allVariants(String assetId) {
    _requestGeneration++;
    setState(() {
      _refused = null;
      _variantsOf = assetId;
    });
    _dispatch(() => widget.controller.loadVariants(assetId));
  }

  /// A read the runtime refuses fails its future rather than changing state, so
  /// the reason is caught and shown instead of becoming an unhandled error.
  void _dispatch(Future<void> Function() read) {
    final generation = _requestGeneration;
    Future<void>.sync(read).catchError((Object error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(
        () => _refused = _message(
          error is StockResearchException ? error.code : null,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (detail != null) {
      return _detailView(detail.asset, detail.variant, detail.provenance);
    }
    final controller = widget.controller;
    final search = controller.discoveryState.search;
    final variants = controller.discoveryState.variants;
    final unavailable =
        widget.configurationFailed ||
        controller.state.phase != StockResearchRuntimePhase.active;
    final searching = search.phase == StockResearchReadPhase.loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Stock prices', style: display(29)),
        const SizedBox(height: 6),
        const Text(
          'Explore stocks on Solana. Compare prices and the companies that issue them.',
        ),
        const SizedBox(height: 6),
        const Text(
          'Market data only. No trading here.',
          style: TextStyle(fontSize: 12, color: StudyColor.muted),
        ),
        const SizedBox(height: 10),
        if (unavailable)
          Semantics(
            liveRegion: true,
            child: Text(
              widget.configurationFailed
                  ? 'Stock prices are not set up in this build.'
                  : _message(controller.state.errorCode),
              key: const ValueKey('stock-research-unavailable'),
            ),
          )
        else ...[
          TextField(
            key: const ValueKey('stock-research-query'),
            controller: _query,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(
              labelText: 'Company name or symbol',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 8),
          CraftButton(
            key: const ValueKey('stock-research-search'),
            label: 'Search',
            onPressed: searching ? null : _search,
          ),
          if (search.data == null && !searching) ...[
            const SizedBox(height: 14),
            const Text(
              'Start with a company you know',
              style: TextStyle(fontSize: 13, color: StudyColor.muted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final name in const [
                  'Apple',
                  'Microsoft',
                  'Nvidia',
                  'Tesla',
                ])
                  ActionChip(
                    label: Text(name),
                    onPressed: () {
                      _query.text = name;
                      _search();
                    },
                  ),
              ],
            ),
          ],
        ],
        if (_refused != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _refused!,
                key: const ValueKey('stock-research-refused'),
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (searching) const Text('Looking.'),
        if (search.phase == StockResearchReadPhase.cancelled)
          const Text(
            'The search stopped. Search again when you are ready.',
            key: ValueKey('stock-research-cancelled'),
          ),
        if (search.phase == StockResearchReadPhase.error)
          Semantics(
            liveRegion: true,
            child: Text(
              _message(search.errorCode),
              key: const ValueKey('stock-research-failure'),
            ),
          ),
        // Staleness is read from the phase, not from a code: the discovery
        // channels report an aged reading with the same code as a real timeout,
        // and those two do not deserve the same sentence.
        if (search.phase == StockResearchReadPhase.stale)
          const Text(
            'This reading has passed its refresh time. Search again for a '
            'newer one.',
            key: ValueKey('stock-research-stale'),
          ),
        ..._results(search, variants),
      ],
    );
  }

  List<Widget> _results(
    StockResearchReadState<StockSearchPage> search,
    StockResearchReadState<StockVariantsPage> variants,
  ) {
    // Retained data stays readable while it is labelled as no longer fresh.
    final page = search.data;
    if (page == null) return const [];
    if (page.results.isEmpty) {
      return [
        Text(
          'Nothing listed for "${page.query}". Try another company name or symbol.',
          key: const ValueKey('stock-research-empty'),
        ),
      ];
    }
    return [
      for (final asset in page.results)
        ..._asset(asset, variants, page.provenance),
      const Divider(),
      // The provenance asserts all three of these, so they are stated.
      const Text(
        'Data from Tokens.xyz. Unverified and not a full list. These are display '
        'prices, not a price you could trade at.',
        style: TextStyle(fontSize: 12, color: StudyColor.muted),
      ),
    ];
  }

  /// Plain language for a followed-list refusal. No code reaches the reader.
  String _keepMessage(FollowedStocksFailure failure) => switch (failure) {
    FollowedStocksFailure.limitReached =>
      'Your list is full. Remove one to keep another.',
    FollowedStocksFailure.unauthenticated => 'Sign in again to keep this.',
    FollowedStocksFailure.accountMismatch => 'This account is unavailable.',
    FollowedStocksFailure.notConfigured =>
      'Keeping a stock is switched off on this server.',
    FollowedStocksFailure.timeout => 'That took too long. Try again.',
    FollowedStocksFailure.busy => 'One thing at a time.',
    FollowedStocksFailure.revisionConflict =>
      'Your list changed while you were looking. Try again.',
    _ => 'Your list is unavailable right now.',
  };

  /// Keeping needs a verified account, so a guest sees nothing here rather than
  /// a control that cannot work. Keeping records a name, not a holding.
  List<Widget> _keepControl(StockDiscoveryAsset asset) {
    final following = widget.following;
    if (following == null) return const [];
    if (!_askedFollowing) {
      _askedFollowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !following.loaded && !following.busy) {
          following.refresh();
        }
      });
    }
    final kept = following.isFollowing(asset.assetId);
    final storable = FollowedStocks.isStorableId(asset.assetId);
    return [
      if (storable)
        TextButton(
          key: ValueKey('stock-keep-${asset.assetId}'),
          onPressed: following.busy
              ? null
              : () => kept
                    ? following.unfollow(asset.assetId)
                    : following.follow(asset.assetId),
          child: Text(kept ? 'Kept. Remove' : 'Keep this'),
        ),
      if (following.failure != null)
        Semantics(
          liveRegion: true,
          child: Text(
            _keepMessage(following.failure!),
            key: const ValueKey('stock-keep-failure'),
          ),
        ),
    ];
  }

  List<Widget> _asset(
    StockDiscoveryAsset asset,
    StockResearchReadState<StockVariantsPage> variants,
    StockDiscoveryProvenance provenance,
  ) {
    final showing =
        _variantsOf == asset.assetId && variants.data?.assetId == asset.assetId
        ? variants.data
        : null;
    final rows = showing?.variants ?? asset.variants;
    final hidden = asset.advisories.any(
      (advisory) =>
          !asset.variants.any((variant) => variant.mint == advisory.mint),
    );
    final selected = _variantsOf == asset.assetId;
    final loading = variants.phase == StockResearchReadPhase.loading;
    final canRead =
        !widget.configurationFailed &&
        widget.controller.state.phase == StockResearchRuntimePhase.active;
    return [
      const Divider(),
      Text(
        asset.symbol == null
            ? asset.name ?? asset.assetId
            : '${asset.name ?? asset.assetId} (${asset.symbol})',
        key: ValueKey('stock-asset-${asset.assetId}'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      ..._keepControl(asset),
      for (final variant in rows)
        ..._variant(
          variant,
          asset: asset,
          provenance: showing?.provenance ?? provenance,
        ),
      if (showing == null && hidden)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'This search leaves out flagged versions. Show every version '
            'to see them.',
            key: ValueKey('stock-variants-hidden-${asset.assetId}'),
          ),
        ),
      if (selected && loading)
        Text(
          showing == null ? 'Looking up versions.' : 'Refreshing versions.',
          key: ValueKey('stock-variants-loading-${asset.assetId}'),
        ),
      if (selected && variants.phase == StockResearchReadPhase.stale)
        Text(
          'These versions have passed their refresh time. Refresh to see '
          'newer readings.',
          key: ValueKey('stock-variants-stale-${asset.assetId}'),
        ),
      if (selected && variants.phase == StockResearchReadPhase.cancelled)
        Text(
          'The versions lookup stopped. Try again when you are ready.',
          key: ValueKey('stock-variants-cancelled-${asset.assetId}'),
        ),
      if (showing == null || variants.phase != StockResearchReadPhase.ready)
        TextButton(
          key: ValueKey('stock-variants-${asset.assetId}'),
          onPressed: !canRead || loading
              ? null
              : () => _allVariants(asset.assetId),
          child: Text(
            showing == null ? 'Show every version' : 'Refresh versions',
          ),
        ),
      if (_variantsOf == asset.assetId &&
          variants.phase == StockResearchReadPhase.error)
        Text(
          _message(variants.errorCode),
          key: ValueKey('stock-variants-failure-${asset.assetId}'),
        ),
    ];
  }

  List<Widget> _variant(
    StockVariant variant, {
    StockDiscoveryAsset? asset,
    StockDiscoveryProvenance? provenance,
  }) {
    final market = variant.market;
    final advisory = variant.advisory;
    return [
      const SizedBox(height: 10),
      StudyPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              variant.label ??
                  variant.name ??
                  variant.symbol ??
                  variant.variantId,
              key: ValueKey('stock-variant-${variant.variantId}'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            if (variant.issuer != null)
              Text(
                'Issued by ${variant.issuer}',
                style: const TextStyle(fontSize: 12, color: StudyColor.muted),
              ),
            const SizedBox(height: 12),
            if (market == null)
              const Text('No price given')
            else ...[
              Text(
                'Price ${_money(market.priceUsd, price: true)}',
                style: display(24),
              ),
              const SizedBox(height: 8),
              Text('Liquidity ${_money(market.liquidityUsd)}'),
              Text('Traded in a day ${_money(market.volume24hUsd)}'),
            ],
            if (advisory != null)
              Text(
                _advisory(advisory),
                key: ValueKey('stock-advisory-${variant.variantId}'),
              ),
            if (asset != null && provenance != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('stock-details-${variant.variantId}'),
                  onPressed: () {
                    _requestGeneration++;
                    setState(
                      () => _detail = (
                        asset: asset,
                        variant: variant,
                        provenance: provenance,
                      ),
                    );
                  },
                  child: Text(
                    variant.mint == stockHistoryAaplxMint &&
                            asset.assetId == stockHistoryAssetId
                        ? 'View history and details'
                        : 'View details',
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _detailView(
    StockDiscoveryAsset asset,
    StockVariant variant,
    StockDiscoveryProvenance provenance,
  ) {
    final historySupported =
        asset.assetId == stockHistoryAssetId &&
        variant.mint == stockHistoryAaplxMint;
    final checked = DateTime.parse(provenance.observedAt).toUtc();
    final stale = provenance.needsRefresh((widget.now ?? DateTime.now)());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('stock-details-back'),
            onPressed: () => setState(() => _detail = null),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to results'),
          ),
        ),
        const SizedBox(height: 8),
        Text(asset.name ?? asset.symbol ?? asset.assetId, style: display(30)),
        const SizedBox(height: 4),
        const Text(
          'A tokenized version on Solana',
          style: TextStyle(color: StudyColor.muted),
        ),
        ..._variant(variant),
        const SizedBox(height: 8),
        Text(
          'Price checked ${checked.day}/${checked.month}/${checked.year} '
          '${checked.hour.toString().padLeft(2, '0')}:'
          '${checked.minute.toString().padLeft(2, '0')} UTC',
          key: const ValueKey('stock-detail-checked-at'),
          style: const TextStyle(fontSize: 12, color: StudyColor.muted),
        ),
        if (!widget.controller.networkAvailable) ...[
          const SizedBox(height: 6),
          const Text(
            'You are offline. This is the last price you opened.',
            key: ValueKey('stock-detail-offline'),
          ),
        ] else if (stale) ...[
          const SizedBox(height: 6),
          const Text(
            'This price is an older reading. Go back to results and search again for a newer one.',
            key: ValueKey('stock-detail-stale'),
          ),
        ],
        const SizedBox(height: 24),
        if (historySupported)
          StockHistoryPanel(controller: widget.controller, now: widget.now)
        else
          const StudyPanel(
            color: StudyColor.mint,
            child: Text(
              'History is not available for this version yet. You can compare its latest price with the other versions.',
            ),
          ),
        const SizedBox(height: 18),
        Text('About this version', style: display(20)),
        const SizedBox(height: 8),
        Text('Issuer: ${variant.issuer ?? 'Not provided'}'),
        Text('Symbol: ${variant.symbol ?? 'Not provided'}'),
        const SizedBox(height: 12),
        const Text(
          'Solana token address',
          style: TextStyle(fontSize: 12, color: StudyColor.muted),
        ),
        const SizedBox(height: 4),
        SelectableText(variant.mint, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 14),
        const Text(
          'Prices and issuer details come from Tokens.xyz. Availability and eligibility are not verified.',
          style: TextStyle(fontSize: 12, color: StudyColor.muted),
        ),
      ],
    );
  }
}
