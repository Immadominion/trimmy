import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../ui_review/review_feedback.dart';
import '../design/product_notice.dart';
import '../design/product_theme.dart';
import '../design/product_motion_icon.dart';
import '../../ui_review/review_animated_splash.dart';
import 'market_craft.dart';
import 'market_models.dart';
import 'market_research_gateway.dart';

/// A token that can be bought with real money. Rows come straight from the
/// trading capabilities, so a long list opens without a lookup per company.
@immutable
class FastBuyAsset {
  const FastBuyAsset({
    required this.assetId,
    required this.mint,
    required this.name,
    required this.symbol,
    required this.issuer,
    this.companyName,
    this.logoUrl,
    this.brandColor = const Color(0xFFE7E0FA),
  });

  final String assetId, mint, name, symbol, issuer;

  /// The company name when the market catalog already knows it.
  final String? companyName;
  final String? logoUrl;
  final Color brandColor;

  String get title => companyName ?? name;

  /// Company name, token name, symbol or issuer, ignoring case and a `$`.
  bool matches(String query) {
    final text = query.trim().toLowerCase().replaceFirst(r'$', '');
    if (text.isEmpty) return true;
    return [
      ?companyName,
      name,
      symbol,
      issuer,
    ].any((field) => field.toLowerCase().contains(text));
  }
}

/// Search and order entry stay in one sheet, preserving the chosen asset.
class FastBuySheet extends StatefulWidget {
  const FastBuySheet({
    super.key,
    required this.gateway,
    required this.companies,
    required this.orderBuilder,
    this.loadTradeable,
    this.openTradeable,
  });

  /// Real mode: every tradeable token, searched on this device.
  final Future<List<FastBuyAsset>> Function()? loadTradeable;

  /// Real mode: the company behind a chosen token with that token selected,
  /// or null when it cannot open.
  final Future<MarketCompany?> Function(FastBuyAsset asset)? openTradeable;
  final MarketSearchGateway gateway;
  final List<MarketCompany> companies;
  final Widget Function(MarketCompany company, VoidCallback back) orderBuilder;
  @override
  State<FastBuySheet> createState() => _FastBuySheetState();
}

class _FastBuySheetState extends State<FastBuySheet> {
  final _query = TextEditingController();
  Timer? _debounce, _noticeTimer;
  MarketCompany? _selected;
  List<FastBuyAsset>? _tradeable;
  bool _loadingTradeable = false;
  bool _tradeableFailed = false;
  String? _opening;

  /// A tapped stock could not open. The notice is written when shown, so it
  /// follows the current language.
  bool _openFailed = false;

  bool get _real => widget.loadTradeable != null;

  Future<void> _loadTradeable() async {
    final load = widget.loadTradeable;
    if (load == null || _loadingTradeable) return;
    setState(() {
      _loadingTradeable = true;
      _tradeableFailed = false;
    });
    try {
      final rows = await load();
      if (mounted) setState(() => _tradeable = rows);
    } catch (_) {
      if (mounted) setState(() => _tradeableFailed = true);
    } finally {
      if (mounted) setState(() => _loadingTradeable = false);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.gateway.addListener(_changed);
    unawaited(_loadTradeable());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _noticeTimer?.cancel();
    _query.dispose();
    widget.gateway.removeListener(_changed);
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    setState(() {});
    // Real mode already holds every tradeable token and filters locally.
    if (_real || text.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        await widget.gateway.search(text.trim());
      } catch (_) {
        _changed();
      }
    });
  }

  void _choose(MarketCompany company) {
    if (company.primaryVariant == null) return;
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    ReviewFeedback.shared.press(selection: true);
    setState(() => _selected = company);
  }

  void _showOpenFailed() {
    _noticeTimer?.cancel();
    setState(() => _openFailed = true);
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _openFailed = false);
    });
  }

  Future<void> _open(FastBuyAsset asset) async {
    final open = widget.openTradeable;
    if (open == null || _opening != null) return;
    FocusScope.of(context).unfocus();
    ReviewFeedback.shared.press(selection: true);
    setState(() {
      _opening = asset.mint;
      _openFailed = false;
    });
    MarketCompany? company;
    try {
      company = await open(asset);
    } catch (_) {
      company = null;
    }
    if (!mounted) return;
    setState(() => _opening = null);
    if (company?.primaryVariant?.mint == asset.mint) {
      setState(() => _selected = company);
    } else {
      _showOpenFailed();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selected case final company?) {
      return widget.orderBuilder(
        company,
        () => setState(() => _selected = null),
      );
    }
    final l10n = context.l10n;
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.fastBuyTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.fastBuyClose,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
              child: TextField(
                key: const ValueKey('fast-buy-search'),
                controller: _query,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: l10n.fastBuySearchHint,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(13),
                    child: ProductMotionIcon(
                      file: 'market-search.png',
                      animatedFile: 'market-search.gif',
                      size: 24,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF5F3F9),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            ),
            Expanded(child: _real ? _tradeableList() : _paperList()),
            if (_openFailed)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                child: ProductNotice(
                  key: const ValueKey('fast-buy-notice'),
                  message: l10n.fastBuyOpenFailed,
                  onDismiss: () => setState(() => _openFailed = false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text, {VoidCallback? retry}) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (retry != null)
            TextButton(onPressed: retry, child: Text(context.l10n.commonRetry)),
        ],
      ),
    ),
  );

  Widget _tradeableList() {
    if (_loadingTradeable) {
      return const Center(child: TrimmyLiquidMark(size: 52));
    }
    if (_tradeableFailed || _tradeable == null) {
      return _message(context.l10n.fastBuyConnectFailed, retry: _loadTradeable);
    }
    final query = _query.text.trim();
    final rows = query.isEmpty
        ? _tradeable!
        : _tradeable!.where((asset) => asset.matches(query)).toList();
    if (rows.isEmpty) {
      return _message(
        query.isEmpty
            ? context.l10n.fastBuyNoneAvailable
            : context.l10n.fastBuyNoTradeableMatch,
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final asset = rows[index];
        final opening = _opening == asset.mint;
        return ListTile(
          key: ValueKey('fast-buy-${asset.mint}'),
          contentPadding: const EdgeInsets.symmetric(vertical: 5),
          leading: CompanyLogo(
            name: asset.title,
            color: asset.brandColor,
            logoUrl: asset.logoUrl,
            size: 46,
          ),
          title: Text(
            asset.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            '${asset.symbol} · ${asset.issuer}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: opening
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  Icons.chevron_right_rounded,
                  color: ProductColor.violet,
                ),
          enabled: _opening == null || opening,
          onTap: () => _open(asset),
        );
      },
    );
  }

  Widget _paperList() {
    final query = _query.text.trim();
    final state = widget.gateway.snapshot;
    final matching = state.query.toLowerCase() == query.toLowerCase();
    final searching =
        query.isNotEmpty &&
        (!matching || state.phase == MarketSearchPhase.loading);
    final rows = query.isEmpty
        ? widget.companies
        : matching
        ? state.companies
        : <MarketCompany>[];
    if (searching) return const Center(child: TrimmyLiquidMark(size: 52));
    if (rows.isEmpty) {
      return _message(
        query.isEmpty
            ? context.l10n.fastBuyNoneAvailable
            : state.noticeText(context.l10n) ?? context.l10n.fastBuyNoMatches,
        retry: state.notice == null ? null : () => widget.gateway.search(query),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final company = rows[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 5),
          leading: CompanyLogo(
            name: company.name,
            color: company.brandColor,
            logoUrl: company.logoUrl,
            size: 46,
          ),
          title: Text(
            company.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text('\$${company.symbol.replaceAll(r'$', '')}'),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: ProductColor.violet,
          ),
          enabled: company.primaryVariant != null,
          onTap: () => _choose(company),
        );
      },
    );
  }
}
