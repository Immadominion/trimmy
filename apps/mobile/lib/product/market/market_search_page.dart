import 'dart:async';

import 'package:flutter/material.dart';

import 'market_craft.dart';
import '../design/product_empty_state.dart';
import 'foundation_market_page.dart' show MarketSearchIcon;
import 'market_models.dart';
import 'market_research_gateway.dart';

class MarketSearchPage extends StatefulWidget {
  const MarketSearchPage({
    super.key,
    required this.gateway,
    required this.recents,
  });

  final MarketSearchGateway gateway;
  final MarketRecentsController recents;

  @override
  State<MarketSearchPage> createState() => _MarketSearchPageState();
}

class _MarketSearchPageState extends State<MarketSearchPage> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String? _localMessage;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.gateway.addListener(_changed);
    widget.recents.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant MarketSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.gateway, widget.gateway)) {
      oldWidget.gateway.removeListener(_changed);
      widget.gateway.addListener(_changed);
    }
    if (!identical(oldWidget.recents, widget.recents)) {
      oldWidget.recents.removeListener(_changed);
      widget.recents.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.gateway.removeListener(_changed);
    widget.recents.removeListener(_changed);
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() => _localMessage = null);
    if (query.isEmpty) {
      widget.gateway.cancel();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(query));
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    try {
      await widget.gateway.search(query);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _localMessage = 'Search did not finish. Try again.');
    }
  }

  void _choose(MarketCompany company) {
    widget.recents.record(company);
    Navigator.of(context).pop(company);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    final snapshot = widget.gateway.snapshot;
    final matching = snapshot.query.toLowerCase() == query.toLowerCase();
    final searching =
        query.isNotEmpty &&
        (!matching || snapshot.phase == MarketSearchPhase.loading);
    final results = matching ? snapshot.companies : const <MarketCompany>[];
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
        titleSpacing: 0,
        title: const Text(
          'Find a company',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                key: const ValueKey('market-search-field'),
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: 'Name or symbol',
                  counterText: '',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(13),
                    child: MarketSearchIcon(),
                  ),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _query.clear();
                            _onQueryChanged('');
                            _focus.requestFocus();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: const Color(0xFFF5F4F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(
                      color: Color(0xFFDED2F0),
                      width: 1,
                    ),
                  ),
                ),
                onChanged: _onQueryChanged,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  final next = value.trim();
                  if (next.isNotEmpty) _search(next);
                },
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: query.isEmpty
                    ? _Recents(
                        key: const ValueKey('market-recents'),
                        controller: widget.recents,
                        onChoose: _choose,
                      )
                    : _SearchResults(
                        key: ValueKey('market-results-$query'),
                        query: query,
                        searching: searching,
                        results: results,
                        message:
                            _localMessage ??
                            (matching ? snapshot.message : null),
                        phase: matching
                            ? snapshot.phase
                            : MarketSearchPhase.loading,
                        onChoose: _choose,
                        onRetry: () => _search(query),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Recents extends StatelessWidget {
  const _Recents({super.key, required this.controller, required this.onChoose});

  final MarketRecentsController controller;
  final ValueChanged<MarketCompany> onChoose;

  @override
  Widget build(BuildContext context) {
    final recents = controller.companies;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recently viewed',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
            ),
            if (recents.isNotEmpty)
              TextButton(
                key: const ValueKey('market-clear-recents'),
                onPressed: controller.clear,
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (recents.isEmpty)
          const ProductEmptyState(
            title: 'Find your next company',
            message: 'Your recent searches will appear here.',
          )
        else
          for (final company in recents)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CompanyResult(company: company, onTap: onChoose),
            ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    super.key,
    required this.query,
    required this.searching,
    required this.results,
    required this.message,
    required this.phase,
    required this.onChoose,
    required this.onRetry,
  });

  final String query;
  final bool searching;
  final List<MarketCompany> results;
  final String? message;
  final MarketSearchPhase phase;
  final ValueChanged<MarketCompany> onChoose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return ListView(
        key: const ValueKey('market-search-loading'),
        padding: const EdgeInsets.all(16),
        children: const [
          _LoadingResult(),
          SizedBox(height: 10),
          _LoadingResult(),
          SizedBox(height: 10),
          _LoadingResult(),
        ],
      );
    }
    final failed =
        phase == MarketSearchPhase.error ||
        phase == MarketSearchPhase.offline ||
        phase == MarketSearchPhase.paused;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (message != null)
          Semantics(
            liveRegion: true,
            child: MarketPanel(
              color: failed ? MarketPalette.softLoss : MarketPalette.mint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(message!),
                  if (failed) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (message != null) const SizedBox(height: 12),
        if (!failed && results.isEmpty)
          Semantics(
            liveRegion: true,
            child: MarketPanel(
              key: const ValueKey('market-search-empty'),
              child: Text(
                'Nothing called “$query”. Try the symbol.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          )
        else
          for (final company in results)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CompanyResult(company: company, onTap: onChoose),
            ),
      ],
    );
  }
}

class _CompanyResult extends StatelessWidget {
  const _CompanyResult({required this.company, required this.onTap});

  final MarketCompany company;
  final ValueChanged<MarketCompany> onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${company.name}, ${company.symbol}',
    child: Material(
      color: const Color(0xFFF7F7FA),
      shape: marketSquircle(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('market-search-result-${company.assetId}'),
        onTap: () => onTap(company),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CompanyLogo(
                name: company.name,
                logoUrl: company.logoUrl,
                color: company.brandColor,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cashtag(company.symbol),
                      style: const TextStyle(color: MarketPalette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    shortPrice(company.priceUsd),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (company.dayChangePercent != null)
                    DirectionLabel(company.dayChangePercent),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LoadingResult extends StatelessWidget {
  const _LoadingResult();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading company',
    child: ExcludeSemantics(
      child: Container(
        height: 78,
        decoration: ShapeDecoration(
          color: MarketPalette.line.withValues(alpha: .55),
          shape: marketSquircle(20),
        ),
      ),
    ),
  );
}
