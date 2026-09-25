import 'dart:async';
import 'package:flutter/material.dart';
import '../../ui_review/review_feedback.dart';
import '../design/product_theme.dart';
import '../design/product_motion_icon.dart';
import '../../ui_review/review_animated_splash.dart';
import 'market_craft.dart';
import 'market_models.dart';
import 'market_research_gateway.dart';

/// Search and order entry stay in one sheet, preserving the chosen asset.
class FastBuySheet extends StatefulWidget {
  const FastBuySheet({
    super.key,
    required this.gateway,
    required this.companies,
    required this.orderBuilder,
    this.loadAvailableCompanies,
    this.canSelect,
  });
  final Future<List<MarketCompany>> Function()? loadAvailableCompanies;
  final bool Function(MarketCompany company)? canSelect;
  final MarketSearchGateway gateway;
  final List<MarketCompany> companies;
  final Widget Function(MarketCompany company, VoidCallback back) orderBuilder;
  @override
  State<FastBuySheet> createState() => _FastBuySheetState();
}

class _FastBuySheetState extends State<FastBuySheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  MarketCompany? _selected;
  List<MarketCompany>? _available;
  bool _loadingAvailable = false;
  bool _availabilityFailed = false;

  Future<void> _loadAvailable() async {
    final load = widget.loadAvailableCompanies;
    if (load == null || _loadingAvailable) return;
    setState(() {
      _loadingAvailable = true;
      _availabilityFailed = false;
    });
    try {
      final rows = await load();
      if (mounted) setState(() => _available = rows);
    } catch (_) {
      if (mounted) setState(() => _availabilityFailed = true);
    } finally {
      if (mounted) setState(() => _loadingAvailable = false);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.gateway.addListener(_changed);
    unawaited(_loadAvailable());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    widget.gateway.removeListener(_changed);
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    setState(() {});
    if (text.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        await widget.gateway.search(text.trim());
      } catch (_) {
        _changed();
      }
    });
  }

  void _choose(MarketCompany company) {
    if (company.primaryVariant == null ||
        widget.canSelect?.call(company) == false) {
      return;
    }
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    ReviewFeedback.shared.press(selection: true);
    setState(() => _selected = company);
  }

  @override
  Widget build(BuildContext context) {
    if (_selected case final company?) {
      return widget.orderBuilder(
        company,
        () => setState(() => _selected = null),
      );
    }
    final query = _query.text.trim();
    final state = widget.gateway.snapshot;
    final matching = state.query.toLowerCase() == query.toLowerCase();
    final searching =
        query.isNotEmpty &&
        (!matching || state.phase == MarketSearchPhase.loading);
    final candidates = query.isEmpty
        ? _available ?? widget.companies
        : matching
        ? state.companies
        : <MarketCompany>[];
    final rows = candidates
        .where((c) => widget.canSelect?.call(c) ?? true)
        .toList();
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
                      'Fast buy',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close fast buy',
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
                onChanged: _search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Search a name or ticker',
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
            Expanded(
              child: searching || _loadingAvailable
                  ? const Center(child: TrimmyLiquidMark(size: 52))
                  : _availabilityFailed || rows.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _availabilityFailed
                                ? 'Trading could not connect.'
                                : query.isEmpty
                                ? 'No stocks available to buy right now.'
                                : state.message ??
                                      (widget.canSelect == null
                                          ? 'No matches yet.'
                                          : 'This stock isn’t available to buy yet.'),
                          ),
                          if (_availabilityFailed || state.message != null)
                            TextButton(
                              onPressed: _availabilityFailed
                                  ? _loadAvailable
                                  : () => widget.gateway.search(query),
                              child: const Text('Retry'),
                            ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final company = rows[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 5,
                          ),
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
                          subtitle: Text(
                            '\$${company.symbol.replaceAll(r'$', '')}',
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: ProductColor.violet,
                          ),
                          enabled: company.primaryVariant != null,
                          onTap: () => _choose(company),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
