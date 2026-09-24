import 'package:flutter/material.dart';

import '../design_study/craft.dart';
import 'invitations_controller.dart';
import 'invitations_panel.dart';
import 'relationship.dart';
import 'relationships_controller.dart';

/// The first bounded social surface: friends, invitations and safety controls.
/// It deliberately contains no activity feed or simulated social counts.
final class RelationshipsPanel extends StatefulWidget {
  const RelationshipsPanel({
    super.key,
    required this.relationships,
    required this.invitations,
  });

  final RelationshipsController relationships;
  final InvitationsController invitations;

  @override
  State<RelationshipsPanel> createState() => _RelationshipsPanelState();
}

final class _RelationshipsPanelState extends State<RelationshipsPanel> {
  bool _askedForFriends = false;
  bool _showBlocks = false;

  @override
  void initState() {
    super.initState();
    widget.relationships.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant RelationshipsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.relationships, widget.relationships)) {
      oldWidget.relationships.removeListener(_changed);
      widget.relationships.addListener(_changed);
      _askedForFriends = false;
      _showBlocks = false;
    }
  }

  @override
  void dispose() {
    widget.relationships.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _failure(RelationshipFailure failure) => switch (failure) {
    RelationshipFailure.notConfigured =>
      'Friends are unavailable on this server right now.',
    RelationshipFailure.unauthenticated =>
      'Sign in again to manage your friends.',
    RelationshipFailure.accountMismatch => 'This account is unavailable.',
    RelationshipFailure.notFound || RelationshipFailure.notActive =>
      'That person or friendship is no longer available.',
    RelationshipFailure.forbidden => 'That is not yours to do.',
    RelationshipFailure.revisionConflict =>
      'It changed on another device. Refresh and choose again.',
    RelationshipFailure.idempotencyConflict =>
      'That saved request belongs to a different action.',
    RelationshipFailure.limitReached =>
      'Your friend list is full. Remove someone before adding another.',
    RelationshipFailure.pairUnavailable =>
      'You cannot connect with that person right now.',
    RelationshipFailure.rateLimited =>
      'Too many changes at once. Wait a moment and try again.',
    RelationshipFailure.timeout => 'That took too long. Try again.',
    RelationshipFailure.busy => 'One thing at a time.',
    RelationshipFailure.invalidConfiguration ||
    RelationshipFailure.invalidRequest ||
    RelationshipFailure.unavailable ||
    RelationshipFailure.invalidResponse ||
    RelationshipFailure.closed => 'Friends are unavailable right now.',
  };

  String _notice(RelationshipNotice notice) => switch (notice) {
    RelationshipNotice.friendRemoved => 'Friend removed.',
    RelationshipNotice.blocked =>
      'Blocked. Your friendship and open invitations are removed.',
    RelationshipNotice.unblocked =>
      'Unblocked. Old friendships and invitations stay removed.',
    RelationshipNotice.reasonReported => 'Report received.',
  };

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: studyShape(24),
          title: Text(title, style: display(21)),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep things as they are'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _remove(FriendRecord friend) async {
    final confirmed = await _confirm(
      title: 'Remove @${friend.person.handle}?',
      message:
          'You will stop being friends. Friend-only reasons disappear, and a new invitation is required to reconnect.',
      action: 'Remove friend',
    );
    if (confirmed) await widget.relationships.removeFriend(friend);
  }

  Future<void> _block(FriendRecord friend) async {
    final confirmed = await _confirm(
      title: 'Block @${friend.person.handle}?',
      message:
          'This removes the friendship, cancels open invitations and stops personalized sharing. Public reasons can still be seen from other accounts.',
      action: 'Block',
    );
    if (confirmed) {
      await widget.relationships.setBlocked(
        socialId: friend.person.socialId,
        blocked: true,
        knownHandle: friend.person.handle,
      );
    }
  }

  Future<void> _unblock(BlockedProfile profile) async {
    final name = profile.handle == null ? 'this account' : '@${profile.handle}';
    final confirmed = await _confirm(
      title: 'Unblock $name?',
      message:
          'Unblocking does not restore an old friendship or invitation. Either person can send a fresh invitation later.',
      action: 'Unblock',
    );
    if (confirmed) {
      await widget.relationships.setBlocked(
        socialId: profile.socialId,
        blocked: false,
        knownHandle: profile.handle,
      );
    }
  }

  Future<void> _toggleBlocks() async {
    setState(() => _showBlocks = !_showBlocks);
    if (_showBlocks && !widget.relationships.blocksLoaded) {
      await widget.relationships.refreshBlocks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.relationships;
    if (!_askedForFriends) {
      _askedForFriends = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !controller.friendsLoaded && !controller.busy) {
          controller.refreshFriends();
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your circle', style: display(24)),
        const SizedBox(height: 6),
        const Text(
          'Friends can share reasons with each other on the exact stock page. There is no social feed yet.',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Text('Friends', style: display(18))),
            TextButton(
              key: const ValueKey('relationships-refresh-friends'),
              onPressed: controller.busy ? null : controller.refreshFriends,
              child: Text(controller.friendsLoaded ? 'Refresh' : 'Load'),
            ),
          ],
        ),
        if (controller.busy && !controller.friendsLoaded)
          const LinearProgressIndicator(key: ValueKey('relationships-loading')),
        if (controller.failure != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              _failure(controller.failure!),
              key: const ValueKey('relationships-failure'),
              style: const TextStyle(color: StudyColor.pink),
            ),
          ),
        ],
        if (controller.notice != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              _notice(controller.notice!),
              key: const ValueKey('relationships-notice'),
              style: const TextStyle(
                color: StudyColor.pine,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        if (controller.friendsLoaded && controller.friends.isEmpty) ...[
          const SizedBox(height: 8),
          const _SocialEmpty(
            key: ValueKey('relationships-friends-empty'),
            text: 'No friends yet. Send an invitation below.',
          ),
        ],
        for (final friend in controller.friends) ...[
          const SizedBox(height: 8),
          _FriendCard(
            friend: friend,
            busy: controller.busy,
            onRemove: () => _remove(friend),
            onBlock: () => _block(friend),
          ),
        ],
        if (controller.hasMoreFriends)
          TextButton(
            key: const ValueKey('relationships-more-friends'),
            onPressed: controller.busy ? null : controller.loadMoreFriends,
            child: const Text('Show more friends'),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const ValueKey('relationships-blocks-toggle'),
          onPressed: controller.busy ? null : _toggleBlocks,
          icon: Icon(_showBlocks ? Icons.expand_less : Icons.shield_outlined),
          label: Text(
            _showBlocks ? 'Hide blocked accounts' : 'Blocked accounts',
          ),
        ),
        if (_showBlocks) ...[
          if (controller.blocksLoaded && controller.blocks.isEmpty)
            const _SocialEmpty(text: 'You have not blocked anyone.'),
          for (final profile in controller.blocks) ...[
            const SizedBox(height: 8),
            _BlockedCard(
              profile: profile,
              busy: controller.busy,
              onUnblock: () => _unblock(profile),
            ),
          ],
          if (controller.hasMoreBlocks)
            TextButton(
              key: const ValueKey('relationships-more-blocks'),
              onPressed: controller.busy ? null : controller.loadMoreBlocks,
              child: const Text('Show more blocked accounts'),
            ),
        ],
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 16),
        InvitationsPanel(controller: widget.invitations),
      ],
    );
  }
}

final class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.friend,
    required this.busy,
    required this.onRemove,
    required this.onBlock,
  });

  final FriendRecord friend;
  final bool busy;
  final VoidCallback onRemove;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('relationship-friend-${friend.friendshipId}'),
    padding: const EdgeInsets.all(14),
    decoration: ShapeDecoration(
      color: Colors.white,
      shape: studyShape(
        20,
      ).copyWith(side: const BorderSide(color: StudyColor.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(friend.person.handle),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('@${friend.person.handle}', style: display(16)),
              const SizedBox(height: 3),
              Text(
                '${friend.person.rank.label} · ${friend.person.persona}',
                style: const TextStyle(color: StudyColor.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: ValueKey('relationship-remove-${friend.friendshipId}'),
                    onPressed: busy ? null : onRemove,
                    child: const Text('Remove'),
                  ),
                  TextButton(
                    key: ValueKey('relationship-block-${friend.friendshipId}'),
                    onPressed: busy ? null : onBlock,
                    child: const Text('Block'),
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

final class _BlockedCard extends StatelessWidget {
  const _BlockedCard({
    required this.profile,
    required this.busy,
    required this.onUnblock,
  });

  final BlockedProfile profile;
  final bool busy;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final name = profile.handle == null
        ? 'Blocked account'
        : '@${profile.handle}';
    return Container(
      key: ValueKey('relationship-blocked-${profile.socialId}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: ShapeDecoration(
        color: StudyColor.mint,
        shape: studyShape(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.block, color: StudyColor.pine),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            key: ValueKey('relationship-unblock-${profile.socialId}'),
            onPressed: busy ? null : onUnblock,
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
  }
}

final class _Avatar extends StatelessWidget {
  const _Avatar(this.handle);

  final String handle;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    alignment: Alignment.center,
    decoration: ShapeDecoration(
      color: StudyColor.yellow,
      shape: studyShape(15),
    ),
    child: Text(
      handle.characters.first.toUpperCase(),
      style: display(19, color: StudyColor.deep),
    ),
  );
}

final class _SocialEmpty extends StatelessWidget {
  const _SocialEmpty({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: ShapeDecoration(color: StudyColor.mint, shape: studyShape(18)),
    child: Text(text, style: const TextStyle(color: StudyColor.muted)),
  );
}
