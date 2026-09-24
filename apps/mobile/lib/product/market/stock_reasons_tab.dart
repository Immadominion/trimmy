import '../design/product_notice.dart';
import 'package:flutter/material.dart';

import '../../account/guest_session.dart';
import '../../social/relationship.dart';
import '../../social/relationships_controller.dart';
import '../career/own_reason_history.dart';
import '../career/reason_privacy_controller.dart';
import '../career/reason_sharing_repository.dart';
import 'market_craft.dart';
import '../design/product_empty_state.dart';

enum _ReasonAudience { everyone, friends }

/// Everyone's shared reasons on one exact stock version.
///
/// The everyone read is never cached: it lives in this widget's state and is
/// gone when the page closes. The viewer's own history comes from the
/// session-scoped [OwnReasonHistory] so the page can say when a reason is
/// private without showing it to anyone.
class StockReasonsTab extends StatefulWidget {
  const StockReasonsTab({
    super.key,
    required this.repository,
    required this.assetId,
    required this.variantMint,
    this.ownReasons,
    this.viewerPrivacy,
    this.relationships,
    this.onOpenSettings,
    this.pageSize = reasonPageDefaultLimit,
  });

  final ReasonSharingRepository? repository;
  final String assetId;
  final String? variantMint;
  final OwnReasonHistory? ownReasons;
  final ReasonPrivacyController? viewerPrivacy;
  final RelationshipsController? relationships;
  final VoidCallback? onOpenSettings;
  final int pageSize;

  @override
  State<StockReasonsTab> createState() => _StockReasonsTabState();
}

class _StockReasonsTabState extends State<StockReasonsTab> {
  final List<SharedReason> _items = [];
  String? _nextCursor;
  bool _loaded = false;
  bool _loading = false;
  bool _loadingMore = false;
  ReasonSharingFailure? _failure;
  bool _guestFailure = false;
  bool _viewerHasCurrentReason = false;
  bool _ownReadFailed = false;
  bool _ownHistoryIncomplete = false;
  bool? _viewerIsPublic;
  int? _ownHistoryRevision;
  int _generation = 0;
  _ReasonAudience _audience = _ReasonAudience.everyone;

  bool get _supported =>
      widget.repository != null &&
      widget.variantMint != null &&
      isReasonSharingAssetId(widget.assetId) &&
      isReasonSharingMint(widget.variantMint!);

  @override
  void initState() {
    super.initState();
    _viewerIsPublic = _publicVisibility();
    _ownHistoryRevision = _historyRevision();
    widget.viewerPrivacy?.addListener(_privacyChanged);
    widget.ownReasons?.addListener(_historyChanged);
    widget.relationships?.addListener(_relationshipsChanged);
    _start();
  }

  @override
  void didUpdateWidget(covariant StockReasonsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.viewerPrivacy, widget.viewerPrivacy)) {
      oldWidget.viewerPrivacy?.removeListener(_privacyChanged);
      widget.viewerPrivacy?.addListener(_privacyChanged);
      _viewerIsPublic = _publicVisibility();
    }
    if (!identical(oldWidget.ownReasons, widget.ownReasons)) {
      oldWidget.ownReasons?.removeListener(_historyChanged);
      widget.ownReasons?.addListener(_historyChanged);
      _ownHistoryRevision = _historyRevision();
    }
    if (!identical(oldWidget.relationships, widget.relationships)) {
      oldWidget.relationships?.removeListener(_relationshipsChanged);
      widget.relationships?.addListener(_relationshipsChanged);
    }
    if (!identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.viewerPrivacy, widget.viewerPrivacy) ||
        !identical(oldWidget.ownReasons, widget.ownReasons) ||
        oldWidget.assetId != widget.assetId ||
        oldWidget.variantMint != widget.variantMint) {
      _ownHistoryRevision = _historyRevision();
      _start();
    }
  }

  @override
  void dispose() {
    widget.viewerPrivacy?.removeListener(_privacyChanged);
    widget.ownReasons?.removeListener(_historyChanged);
    widget.relationships?.removeListener(_relationshipsChanged);
    _generation++;
    super.dispose();
  }

  void _privacyChanged() {
    if (!mounted) return;
    final next = _publicVisibility();
    final friendsUnavailable =
        _audience == _ReasonAudience.friends && !_friendsAvailable;
    final changedPublicMembership =
        _viewerIsPublic != null && next != null && _viewerIsPublic != next;
    _viewerIsPublic = next;
    if (friendsUnavailable) {
      _audience = _ReasonAudience.everyone;
      _start();
    } else if (changedPublicMembership) {
      _start();
    } else {
      setState(() {});
    }
  }

  void _historyChanged() {
    if (!mounted) return;
    final next = _historyRevision();
    if (next == _ownHistoryRevision) return;
    _ownHistoryRevision = next;
    _start();
  }

  void _relationshipsChanged() {
    if (mounted) setState(() {});
  }

  List<SharedReason> get _visibleItems {
    final relationships = widget.relationships;
    if (relationships == null) return _items;
    final blocked = relationships.blocks.map((row) => row.socialId).toSet();
    return _items
        .where(
          (reason) =>
              !relationships.hasReported(reason.reasonId) &&
              !blocked.contains(reason.author.socialId),
        )
        .toList(growable: false);
  }

  bool? _publicVisibility() => widget.viewerPrivacy?.privacy == null
      ? null
      : widget.viewerPrivacy!.privacy!.visibility == ReasonVisibility.everyone;

  bool get _friendsAvailable =>
      widget.viewerPrivacy?.privacy?.friendsSharingAvailable == true;

  Future<ReasonPage<SharedReason>> _read(
    ReasonSharingRepository repository,
    SharedReasonQuery query,
  ) => _audience == _ReasonAudience.friends
      ? repository.listFriendReasons(query)
      : repository.listSharedReasons(query);

  void _chooseAudience(_ReasonAudience audience) {
    if (audience == _audience ||
        audience == _ReasonAudience.friends && !_friendsAvailable) {
      return;
    }
    setState(() => _audience = audience);
    _start();
  }

  int? _historyRevision() {
    final history = widget.ownReasons;
    final mint = widget.variantMint;
    if (history == null || mint == null) return null;
    return history.revisionForStock(assetId: widget.assetId, variantMint: mint);
  }

  void _start() {
    _generation++;
    _items.clear();
    _nextCursor = null;
    _loaded = false;
    _loading = false;
    _loadingMore = false;
    _failure = null;
    _guestFailure = false;
    _viewerHasCurrentReason = false;
    _ownReadFailed = false;
    _ownHistoryIncomplete = false;
    if (!_supported) return;
    _loadFirstPage();
    _loadOwn();
  }

  Future<void> _loadFirstPage() async {
    final repository = widget.repository;
    if (repository == null || !_supported) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _failure = null;
      _guestFailure = false;
    });
    try {
      final page = await _read(
        repository,
        SharedReasonQuery(
          assetId: widget.assetId,
          variantMint: widget.variantMint!,
          limit: widget.pageSize,
        ),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextCursor = page.nextCursor;
        _loaded = true;
        _loading = false;
      });
    } on GuestSessionException {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _guestFailure = true;
      });
    } on ReasonSharingException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failure = error.failure;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failure = ReasonSharingFailure.unavailable;
      });
    }
  }

  Future<void> _loadMore() async {
    final repository = widget.repository;
    final cursor = _nextCursor;
    if (repository == null || cursor == null || _loadingMore || !_supported) {
      return;
    }
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _failure = null;
      _guestFailure = false;
    });
    try {
      final page = await _read(
        repository,
        SharedReasonQuery(
          assetId: widget.assetId,
          variantMint: widget.variantMint!,
          limit: widget.pageSize,
          cursor: cursor,
        ),
      );
      if (!mounted || generation != _generation) return;
      final known = _items.map((item) => item.reasonId).toSet();
      setState(() {
        _items.addAll(page.items.where((item) => known.add(item.reasonId)));
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } on GuestSessionException {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _guestFailure = true;
      });
    } on ReasonSharingException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _failure = error.failure;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _failure = ReasonSharingFailure.unavailable;
      });
    }
  }

  Future<void> _loadOwn() async {
    final history = widget.ownReasons;
    if (history == null || !_supported) return;
    final generation = _generation;
    try {
      final own = await history.forStock(
        assetId: widget.assetId,
        variantMint: widget.variantMint!,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _viewerHasCurrentReason = own.any(
          (reason) => reason.deskCycle == ReasonDeskCycle.current,
        );
        _ownReadFailed = false;
        _ownHistoryIncomplete = false;
      });
    } on OwnReasonHistoryIncompleteException {
      if (!mounted || generation != _generation) return;
      setState(() {
        _ownReadFailed = true;
        _ownHistoryIncomplete = true;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _ownReadFailed = true;
        _ownHistoryIncomplete = false;
      });
    }
  }

  bool get _showPrivateLine {
    if (!_viewerHasCurrentReason) return false;
    final privacy = widget.viewerPrivacy?.privacy;
    if (privacy != null) {
      final sharedToAudience = switch (_audience) {
        _ReasonAudience.everyone =>
          privacy.visibility == ReasonVisibility.everyone,
        _ReasonAudience.friends =>
          privacy.friendsSharingAvailable &&
              (privacy.visibility == ReasonVisibility.friends ||
                  privacy.visibility == ReasonVisibility.everyone),
      };
      return !sharedToAudience;
    }
    return _loaded && !_items.any((item) => item.author.isViewer);
  }

  Future<ReasonReportCategory?>
  _chooseReportCategory() => showModalBottomSheet<ReasonReportCategory>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: MarketPalette.paper,
    shape: marketSquircle(28),
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Why are you reporting this?',
            style: Theme.of(
              sheetContext,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose the closest reason. The author will not see who reported it.',
            style: TextStyle(color: MarketPalette.muted),
          ),
          const SizedBox(height: 12),
          for (final category in ReasonReportCategory.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: MarketPalette.white,
                shape: marketSquircle(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('reason-report-category-${category.name}'),
                  onTap: () => Navigator.pop(sheetContext, category),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.label,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: marketSquircle(24),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: ValueKey('reason-safety-confirm-$action'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _report(SharedReason reason) async {
    final relationships = widget.relationships;
    if (relationships == null || relationships.busy) return;
    final category = await _chooseReportCategory();
    if (!mounted || category == null) return;
    final confirmed = await _confirm(
      title: 'Report this reason?',
      message:
          'Trimmy will review it as ${category.label.toLowerCase()}. It will leave this page after the report is received.',
      action: 'Report',
    );
    if (!mounted || !confirmed) return;
    final succeeded = await relationships.reportReason(
      reasonId: reason.reasonId,
      category: category,
    );
    if (!mounted) return;
    _showSafetyResult(
      succeeded: succeeded,
      success: 'Report received.',
      controller: relationships,
    );
  }

  Future<void> _block(SharedReason reason) async {
    final relationships = widget.relationships;
    final socialId = reason.author.socialId;
    if (relationships == null || socialId == null || relationships.busy) return;
    final confirmed = await _confirm(
      title: 'Block @${reason.author.handle}?',
      message:
          'Their reasons will leave this page. Any friendship and open invitations between you will also be removed. Public reasons can still be seen from other accounts.',
      action: 'Block',
    );
    if (!mounted || !confirmed) return;
    final succeeded = await relationships.setBlocked(
      socialId: socialId,
      blocked: true,
      knownHandle: reason.author.handle,
    );
    if (!mounted) return;
    _showSafetyResult(
      succeeded: succeeded,
      success: '@${reason.author.handle} blocked.',
      controller: relationships,
    );
  }

  void _showSafetyResult({
    required bool succeeded,
    required String success,
    required RelationshipsController controller,
  }) {
    final message = succeeded ? success : _relationshipFailure(controller);
    showProductNotice(context, message);
  }

  String _relationshipFailure(RelationshipsController controller) =>
      switch (controller.failure) {
        RelationshipFailure.revisionConflict =>
          'This changed on another device. Choose again.',
        RelationshipFailure.rateLimited =>
          'Too many changes at once. Wait a moment and try again.',
        RelationshipFailure.unauthenticated ||
        RelationshipFailure.accountMismatch ||
        RelationshipFailure.forbidden =>
          'This action is unavailable for your account right now.',
        RelationshipFailure.timeout ||
        RelationshipFailure.unavailable ||
        RelationshipFailure.invalidResponse ||
        RelationshipFailure.closed =>
          'We could not confirm the result. It will retry safely.',
        _ => 'That action could not be completed. Try again.',
      };

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return const ProductEmptyState(
        key: ValueKey('stock-reasons-unavailable'),
        title: 'No comments yet',
      );
    }
    if (_loading && !_loaded) {
      return const _ReasonsSkeleton(key: ValueKey('stock-reasons-loading'));
    }
    if (!_loaded) {
      return _ReasonsNotice(
        key: const ValueKey('stock-reasons-failed'),
        message: _failureMessage(),
        onRetry: _loadFirstPage,
      );
    }
    final visibleItems = _visibleItems;
    return Column(
      key: const ValueKey('stock-reasons'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_friendsAvailable) ...[
          _AudiencePicker(audience: _audience, onChanged: _chooseAudience),
          const SizedBox(height: 10),
        ],
        if (_showPrivateLine) ...[
          _PrivateLine(onOpenSettings: widget.onOpenSettings),
          const SizedBox(height: 10),
        ],
        if (_ownReadFailed) ...[
          _ReasonsNotice(
            key: const ValueKey('stock-own-reasons-failed'),
            message: _ownHistoryIncomplete
                ? 'Your complete reason history could not be loaded here.'
                : 'Your private reason status could not be checked.',
            onRetry: _ownHistoryIncomplete ? null : _loadOwn,
          ),
          const SizedBox(height: 10),
        ],
        if (visibleItems.isEmpty)
          ProductEmptyState(
            key: const ValueKey('stock-reasons-empty'),
            title: _audience == _ReasonAudience.friends
                ? 'No comments from friends yet'
                : 'No comments yet',
          )
        else
          for (final reason in visibleItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReasonCard(
                reason,
                relationships: widget.relationships,
                onReport: () => _report(reason),
                onBlock: reason.author.socialId == null
                    ? null
                    : () => _block(reason),
              ),
            ),
        if (_failure != null || _guestFailure) ...[
          _ReasonsNotice(
            key: const ValueKey('stock-reasons-more-failed'),
            message: _failureMessage(),
            onRetry: _loadMore,
          ),
          const SizedBox(height: 10),
        ] else if (_nextCursor != null) ...[
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            OutlinedButton(
              key: const ValueKey('stock-reasons-more'),
              onPressed: _loadMore,
              child: const Text('Show more'),
            ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String _failureMessage() {
    if (_guestFailure) {
      return 'Your session needs a refresh before comments can load.';
    }
    return switch (_failure) {
      ReasonSharingFailure.offline =>
        'You are offline. Comments couldn’t load.',
      ReasonSharingFailure.timeout => 'Comments took too long to load.',
      ReasonSharingFailure.rateLimited =>
        'Comments are refreshing too quickly. Try again shortly.',
      ReasonSharingFailure.accountRequired =>
        'Your session needs a refresh before comments can load.',
      _ => 'Comments couldn’t load.',
    };
  }
}

class _AudiencePicker extends StatelessWidget {
  const _AudiencePicker({required this.audience, required this.onChanged});

  final _ReasonAudience audience;
  final ValueChanged<_ReasonAudience> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Choose whose comments to see',
    child: Row(
      children: [
        for (final option in _ReasonAudience.values) ...[
          if (option != _ReasonAudience.values.first) const SizedBox(width: 8),
          Expanded(
            child: _AudienceButton(
              audience: option,
              selected: audience == option,
              onPressed: () => onChanged(option),
            ),
          ),
        ],
      ],
    ),
  );
}

class _AudienceButton extends StatelessWidget {
  const _AudienceButton({
    required this.audience,
    required this.selected,
    required this.onPressed,
  });

  final _ReasonAudience audience;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: ExcludeSemantics(
      child: Material(
        color: selected ? MarketPalette.ink : MarketPalette.paper,
        shape: marketSquircle(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('stock-reasons-audience-${audience.name}'),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Text(
              audience == _ReasonAudience.friends ? 'Friends' : 'Everyone',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? MarketPalette.paper : MarketPalette.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReasonCard extends StatelessWidget {
  const _ReasonCard(
    this.reason, {
    required this.relationships,
    required this.onReport,
    required this.onBlock,
  });

  final SharedReason reason;
  final RelationshipsController? relationships;
  final VoidCallback onReport;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) => MarketPanel(
    key: ValueKey('stock-reason-${reason.reasonId}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '@${reason.author.handle}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    reason.author.rankLabel,
                    style: const TextStyle(
                      color: MarketPalette.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (reason.author.isViewer)
              Container(
                key: ValueKey('stock-reason-you-${reason.reasonId}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: ShapeDecoration(
                  color: MarketPalette.yellow,
                  shape: marketSquircle(9),
                ),
                child: const Text(
                  'You',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(reason.note, style: const TextStyle(height: 1.4)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Saved ${formatReasonSavedAt(reason.savedAt)}',
                style: const TextStyle(
                  color: MarketPalette.muted,
                  fontSize: 12,
                ),
              ),
            ),
            if (relationships != null && !reason.author.isViewer) ...[
              _ReasonAction(
                key: ValueKey('reason-report-${reason.reasonId}'),
                label: 'Report',
                icon: Icons.flag_outlined,
                onPressed: relationships!.busy ? null : onReport,
              ),
              if (onBlock != null) ...[
                const SizedBox(width: 6),
                _ReasonAction(
                  key: ValueKey('reason-block-${reason.reasonId}'),
                  label: 'Block',
                  icon: Icons.block_outlined,
                  onPressed: relationships!.busy ? null : onBlock,
                ),
              ],
            ],
          ],
        ),
      ],
    ),
  );
}

class _ReasonAction extends StatelessWidget {
  const _ReasonAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: MarketPalette.paper,
    shape: marketSquircle(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: MarketPalette.muted),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: MarketPalette.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PrivateLine extends StatelessWidget {
  const _PrivateLine({required this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) => MarketPanel(
    key: const ValueKey('stock-reason-private'),
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    color: MarketPalette.mint,
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Your comment is private.',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        if (onOpenSettings != null)
          TextButton(
            key: const ValueKey('stock-reason-private-settings'),
            onPressed: onOpenSettings,
            child: const Text('Settings'),
          ),
      ],
    ),
  );
}

class _ReasonsNotice extends StatelessWidget {
  const _ReasonsNotice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MarketPanel(
    child: Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(color: MarketPalette.muted)),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('stock-reasons-retry'),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ReasonsSkeleton extends StatelessWidget {
  const _ReasonsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading comments',
    child: ExcludeSemantics(
      child: Column(
        children: [
          for (var index = 0; index < 2; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MarketPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    _SkeletonBar(width: 120),
                    SizedBox(height: 12),
                    _SkeletonBar(),
                    SizedBox(height: 6),
                    _SkeletonBar(width: 180),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({this.width});

  final double? width;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      width: width,
      height: 12,
      decoration: ShapeDecoration(
        color: MarketPalette.line,
        shape: marketSquircle(6),
      ),
    ),
  );
}

const _months = [
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

/// Local day, month, year and time, for example `20 Sep 2026, 13:51`.
String formatReasonSavedAt(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year}, $hour:$minute';
}
