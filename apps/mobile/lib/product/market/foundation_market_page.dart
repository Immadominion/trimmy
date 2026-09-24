import '../design/product_notice.dart';
import '../../ui_review/review_feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../markets/followed_stocks_controller.dart';
import '../../markets/followed_stocks.dart';
import 'market_craft.dart';
import 'market_models.dart';
import 'market_research_gateway.dart';
import 'market_search_page.dart';

enum MarketPageStatus { loading, ready, offline, error }

class FoundationMarketPage extends StatefulWidget {
  const FoundationMarketPage({
    super.key,
    required this.companies,
    required this.searchGateway,
    required this.recents,
    required this.onOpenCompany,
    this.following,
    this.resolveCompany,
    this.onSignIn,
    this.intro,
    this.initialList = MarketList.all,
    this.total = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreMessage,
    this.onLoadMore,
    this.status = MarketPageStatus.ready,
    this.statusMessage,
    this.onRetry,
    this.onRefresh,
  });

  final int total;
  final bool hasMore, loadingMore;
  final String? loadMoreMessage;
  final Future<void> Function()? onLoadMore;
  final List<MarketCompany> companies;
  final MarketSearchGateway searchGateway;
  final MarketRecentsController recents;
  final ValueChanged<MarketCompany> onOpenCompany;
  final FollowedStocksController? following;
  final Future<MarketCompany?> Function(String)? resolveCompany;
  final VoidCallback? onSignIn;
  final Widget? intro;
  final MarketList initialList;
  final MarketPageStatus status;
  final String? statusMessage;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  @override
  State<FoundationMarketPage> createState() => _FoundationMarketPageState();
}

class _FoundationMarketPageState extends State<FoundationMarketPage> {
  late MarketList _list;
  MarketSort _sort = MarketSort.featured;
  final Map<String, MarketCompany> _resolved = {};
  bool _resolving = false;
  bool _resolveFailed = false;

  Future<void> _loadFollowed() async {
    if (_resolving ||
        widget.resolveCompany == null ||
        _activeList != MarketList.following) {
      return;
    }
    _resolving = true;
    _resolveFailed = false;
    if (mounted) setState(() {});
    try {
      final known = [
        ...widget.companies,
        ...widget.recents.companies,
        ..._resolved.values,
      ].map((c) => c.assetId).toSet();
      for (final id in widget.following?.assetIds ?? <String>[]) {
        if (!mounted || _activeList != MarketList.following) break;
        if (known.contains(id)) continue;
        try {
          final company = await widget.resolveCompany!(id);
          if (!mounted) return;
          if (company != null) {
            setState(() => _resolved[id] = company);
          } else {
            _resolveFailed = true;
          }
        } catch (_) {
          _resolveFailed = true;
        }
      }
    } finally {
      _resolving = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _list = widget.initialList;
    widget.following?.addListener(_followingChanged);
  }

  @override
  void didUpdateWidget(covariant FoundationMarketPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialList != oldWidget.initialList &&
        _list == oldWidget.initialList) {
      _list = widget.initialList;
    }
    if (!identical(oldWidget.following, widget.following)) {
      oldWidget.following?.removeListener(_followingChanged);
      widget.following?.addListener(_followingChanged);
    }
  }

  @override
  void dispose() {
    widget.following?.removeListener(_followingChanged);
    super.dispose();
  }

  void _followingChanged() {
    if (mounted) {
      setState(() {});
      if (widget.following?.busy == false) _loadFollowed();
    }
  }

  List<MarketList> get _availableLists => [
    MarketList.all,
    if (widget.following != null) MarketList.following,
  ];

  MarketList get _activeList {
    final lists = _availableLists;
    return lists.contains(_list) ? _list : lists.first;
  }

  List<MarketSort> get _availableSorts => [
    MarketSort.featured,
    MarketSort.name,
    MarketSort.price,
    if (widget.companies.any(
      (company) => company.dayChangePercent != null,
    )) ...[
      MarketSort.dayChange,
      MarketSort.dayLoss,
    ],
    if (widget.companies.any((company) => company.floorHolders != null))
      MarketSort.floorHolders,
  ];

  MarketSort get _activeSort =>
      _availableSorts.contains(_sort) ? _sort : MarketSort.featured;

  Future<void> _openSearch() async {
    final company = await Navigator.of(context).push<MarketCompany>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MarketSearchPage(
          gateway: widget.searchGateway,
          recents: widget.recents,
        ),
      ),
    );
    if (!mounted || company == null) return;
    widget.onOpenCompany(company);
  }

  Future<void> _toggleFollow(MarketCompany company) async {
    final following = widget.following;
    if (following == null || following.busy) return;
    final wasFollowing = following.isFollowing(company.assetId);
    if (wasFollowing) {
      await following.unfollow(company.assetId);
    } else {
      await following.follow(company.assetId);
    }
    if (!mounted) return;
    final changed = following.isFollowing(company.assetId) != wasFollowing;
    showProductNotice(
      context,
      changed
          ? wasFollowing
                ? '${company.name} removed from Following.'
                : '${company.name} added to Following.'
          : following.failure == FollowedStocksFailure.unauthenticated
          ? 'Sign in to save your watchlist.'
          : following.failure == FollowedStocksFailure.limitReached
          ? 'Your watchlist is full. Remove a company first.'
          : 'Following did not change. Try again.',
      action:
          !changed &&
              following.failure == FollowedStocksFailure.unauthenticated &&
              widget.onSignIn != null
          ? SnackBarAction(label: 'Sign in', onPressed: widget.onSignIn!)
          : null,
    );
  }

  List<MarketCompany> get _visibleCompanies {
    final following = widget.following;
    final list = _activeList;
    final source = list == MarketList.following
        ? {
            for (final c in [
              ...widget.companies,
              ...widget.recents.companies,
              ..._resolved.values,
            ])
              c.assetId: c,
          }.values
        : widget.companies;
    final companies = source.where((company) {
      if (list == MarketList.following) {
        return following?.isFollowing(company.assetId) ?? false;
      }
      return list == MarketList.all || company.lists.contains(list);
    }).toList();
    switch (_activeSort) {
      case MarketSort.featured:
        break;
      case MarketSort.name:
        companies.sort((a, b) => a.name.compareTo(b.name));
      case MarketSort.dayChange:
        companies.sort(
          (a, b) => (b.dayChangePercent ?? double.negativeInfinity).compareTo(
            a.dayChangePercent ?? double.negativeInfinity,
          ),
        );
      case MarketSort.dayLoss:
        companies.sort(
          (a, b) => (a.dayChangePercent ?? double.infinity).compareTo(
            b.dayChangePercent ?? double.infinity,
          ),
        );
      case MarketSort.price:
        companies.sort(
          (a, b) => (b.priceUsd ?? -1).compareTo(a.priceUsd ?? -1),
        );
      case MarketSort.floorHolders:
        companies.sort(
          (a, b) => (b.floorHolders ?? -1).compareTo(a.floorHolders ?? -1),
        );
    }
    return companies;
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildBody(context);
    return Scaffold(
      backgroundColor: MarketPalette.paper,
      body: SafeArea(
        child: widget.onRefresh == null
            ? content
            : RefreshIndicator(onRefresh: widget.onRefresh!, child: content),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final companies = _visibleCompanies;
    return CustomScrollView(
      key: const PageStorageKey('foundation-market-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Market',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontFamily: 'Bricolage Grotesque',
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.1,
                          ),
                    ),
                  ),
                  Tooltip(
                    message: 'Sort: ${_activeSort.label}',
                    child: Semantics(
                      button: true,
                      label: 'Sort stocks',
                      child: TextButton(
                        key: const ValueKey('market-sort-button'),
                        style: TextButton.styleFrom(
                          foregroundColor: MarketPalette.muted,
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => _showSort(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/images/ui_review/icons8/market-sort.png',
                              width: 20,
                              height: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Search companies',
                    child: Semantics(
                      button: true,
                      label: 'Search companies',
                      child: Material(
                        color: const Color(0xFFF3F3F7),
                        shape: marketSquircle(17),
                        child: InkWell(
                          key: const ValueKey('market-open-search'),
                          customBorder: marketSquircle(17),
                          onTap: _openSearch,
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(child: MarketSearchIcon()),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Tokenized stocks',
                style: TextStyle(color: MarketPalette.muted, fontSize: 14),
              ),
              if (widget.intro != null) ...[
                const SizedBox(height: 12),
                widget.intro!,
              ],
              if (_availableLists.length > 1) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final list in _availableLists)
                      _MarketFilter(
                        key: ValueKey('market-list-${list.name}'),
                        label: list.label,
                        selected: list == _activeList,
                        onTap: () {
                          if (ReviewFeedback.shared.haptics) {
                            HapticFeedback.selectionClick();
                          }
                          setState(() => _list = list);
                          _loadFollowed();
                          final following = widget.following;
                          if (list == MarketList.following &&
                              following != null &&
                              !following.loaded &&
                              !following.busy) {
                            following.refresh();
                          }
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (widget.status == MarketPageStatus.loading &&
            widget.companies.isEmpty)
          SliverList.builder(
            itemCount: 4,
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.fromLTRB(
                i.isEven ? 20 : 28,
                0,
                i.isEven ? 28 : 20,
                12,
              ),
              child: const _LoadingCompanyCard(),
            ),
          )
        else if (widget.status == MarketPageStatus.error ||
            widget.status == MarketPageStatus.offline)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _statusCard()),
          )
        else if (companies.isEmpty &&
            !_resolving &&
            widget.following?.busy != true)
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverToBoxAdapter(
              child: Column(
                key: const ValueKey('market-list-empty'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _activeList == MarketList.following
                        ? 'Your watchlist starts here.'
                        : 'No stocks to show yet.',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _activeList == MarketList.following
                        ? 'Tap Follow on a company to keep it here.'
                        : 'Try searching for a company.',
                    style: const TextStyle(color: MarketPalette.muted),
                  ),
                  TextButton(
                    onPressed: _openSearch,
                    child: const Text('Find a company'),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: companies.length,
            itemBuilder: (context, index) {
              final company = companies[index];
              return _CardEntrance(
                key: ValueKey('market-entry-${company.assetId}'),
                index: index,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: MarketCompanyCard(
                    company: company,
                    followed:
                        widget.following?.isFollowing(company.assetId) ?? false,
                    onTap: () {
                      widget.recents.record(company);
                      widget.onOpenCompany(company);
                    },
                    onLongPress: widget.following == null
                        ? widget.onSignIn == null
                              ? null
                              : () async {
                                  widget.onSignIn!();
                                }
                        : () => _toggleFollow(company),
                  ),
                ),
              );
            },
          ),
        if (_activeList == MarketList.following &&
            (_resolving || widget.following?.busy == true))
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (_activeList == MarketList.following && _resolveFailed)
          SliverToBoxAdapter(
            child: TextButton(
              onPressed: _loadFollowed,
              child: const Text('Some stocks could not load. Retry'),
            ),
          ),
        if (widget.hasMore && _activeList != MarketList.following)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                children: [
                  if (widget.loadMoreMessage != null)
                    Text(
                      widget.loadMoreMessage!,
                      style: const TextStyle(color: MarketPalette.loss),
                    ),
                  TextButton(
                    key: const ValueKey('market-load-more'),
                    onPressed: widget.loadingMore ? null : widget.onLoadMore,
                    child: Text(
                      widget.loadingMore ? 'Loading…' : 'Load more stocks',
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _statusCard() => Semantics(
    liveRegion: true,
    child: MarketPanel(
      color: widget.status == MarketPageStatus.error
          ? MarketPalette.softLoss
          : MarketPalette.mint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.statusMessage ??
                (widget.status == MarketPageStatus.offline
                    ? 'You are offline. Check your connection.'
                    : 'The market list is unavailable.'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(height: 12),
            MarketPrimaryButton(label: 'Try again', onPressed: widget.onRetry),
          ],
        ],
      ),
    ),
  );

  Future<void> _showSort(BuildContext context) async {
    final sorts = _availableSorts;
    final activeSort = _activeSort;
    final picked = await showModalBottomSheet<MarketSort>(
      context: context,
      useSafeArea: true,
      backgroundColor: MarketPalette.paper,
      shape: marketSquircle(28),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sort loaded stocks',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            for (final sort in sorts)
              ListTile(
                minTileHeight: 52,
                shape: marketSquircle(16),
                tileColor: sort == activeSort ? const Color(0xFFF1EBFF) : null,
                trailing: sort == activeSort
                    ? const Icon(
                        Icons.check_rounded,
                        color: MarketPalette.violet,
                      )
                    : null,
                title: Text(sort.label),
                onTap: () => Navigator.pop(context, sort),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }
}

class MarketCompanyCard extends StatelessWidget {
  const MarketCompanyCard({
    super.key,
    required this.company,
    required this.followed,
    required this.onTap,
    this.onLongPress,
  });
  final MarketCompany company;
  final bool followed;
  final VoidCallback onTap;
  final Future<void> Function()? onLongPress;

  @override
  Widget build(BuildContext context) {
    final change = company.dayChangePercent;
    final tint = Color.lerp(company.brandColor, Colors.white, .35)!;
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    final identity = Row(
      children: [
        CompanyLogo(
          name: company.name,
          logoUrl: company.logoUrl,
          color: Colors.white,
          size: 40,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                company.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Dejanire Sans',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                cashtag(company.symbol),
                style: const TextStyle(
                  fontSize: 12,
                  color: MarketPalette.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final price = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          shortPrice(company.priceUsd),
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -.65,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          change == null
              ? 'Change unavailable'
              : '${signedPercent(change)}  24h',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: change == null
                ? MarketPalette.muted
                : change >= 0
                ? MarketPalette.pine
                : MarketPalette.loss,
          ),
        ),
      ],
    );
    return Semantics(
      label:
          '${company.name}, ${company.symbol}, ${shortPrice(company.priceUsd)}, ${change == null ? 'change unavailable' : signedPercent(change)}',
      child: Material(
        color: tint,
        shape: marketSquircle(24),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 6, 3, 0),
              child: Material(
                color: const Color(0xFFFEFEFF),
                shape: marketSquircle(21),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('market-company-${company.assetId}'),
                  onTap: onTap,
                  onLongPress: onLongPress,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: large
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              identity,
                              const SizedBox(height: 12),
                              price,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: identity),
                              const SizedBox(width: 10),
                              price,
                            ],
                          ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      company.primaryVariant?.symbol ?? cashtag(company.symbol),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MarketPalette.muted,
                      ),
                    ),
                  ),
                  if (onLongPress != null)
                    TextButton(
                      key: ValueKey('market-follow-${company.assetId}'),
                      style: TextButton.styleFrom(
                        foregroundColor: MarketPalette.ink,
                        minimumSize: const Size(44, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: onLongPress,
                      child: Text(
                        followed ? 'Following' : '+ Follow',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  TextButton(
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      foregroundColor: MarketPalette.ink,
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.standard,
                    ),
                    child: const Text(
                      'Open',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
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
}

class _MarketFilter extends StatelessWidget {
  const _MarketFilter({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: ShapeDecoration(
        shape: marketSquircle(14).copyWith(
          side: BorderSide(
            color: selected ? const Color(0xFFD8C6EC) : const Color(0xFFEEEEF2),
            width: .8,
          ),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: selected
              ? const [Color(0xFFF5ECFF), Color(0xFFF1E6FC), Color(0xFFDFCFEE)]
              : const [Color(0xFFFAFAFC), Color(0xFFF4F4F7), Color(0xFFEAEAF0)],
          stops: const [0, .86, 1],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: marketSquircle(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? const Color(0xFF583580) : MarketPalette.muted,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class MarketSearchIcon extends StatefulWidget {
  const MarketSearchIcon({super.key});
  @override
  State<MarketSearchIcon> createState() => _MarketSearchIconState();
}

class _MarketSearchIconState extends State<MarketSearchIcon> {
  Timer? _timer;
  bool _animate = true;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _animate = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/ui_review/icons8/market-search.${_animate && !MediaQuery.disableAnimationsOf(context) ? 'gif' : 'png'}',
    width: 26,
    height: 26,
    gaplessPlayback: true,
    excludeFromSemantics: true,
  );
}

class _CardEntrance extends StatelessWidget {
  const _CardEntrance({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = (index % 6) * .055;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      child: child,
      builder: (_, value, child) {
        final t = Curves.easeOutCubic.transform(
          ((value - delay) / (1 - delay)).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

class _LoadingCompanyCard extends StatelessWidget {
  const _LoadingCompanyCard();
  @override
  Widget build(BuildContext context) => Container(
    height: 132,
    decoration: ShapeDecoration(
      color: const Color(0xFFF6F5F9),
      shape: marketSquircle(24),
    ),
    child: const Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
