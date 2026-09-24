import 'package:flutter/material.dart';

import '../design_study/craft.dart';
import 'invitation.dart';
import 'invitations_controller.dart';

/// Functional controls for unfunded invitations. Layout and styling are
/// deliberately plain; this exists so the feature is reachable and honest, not
/// because the arrangement is settled.
class InvitationsPanel extends StatefulWidget {
  const InvitationsPanel({super.key, required this.controller});

  final InvitationsController controller;

  @override
  State<InvitationsPanel> createState() => _InvitationsPanelState();
}

class _InvitationsPanelState extends State<InvitationsPanel> {
  final _handleFields = <String, TextEditingController>{};
  bool _askedOnce = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    for (final field in _handleFields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  TextEditingController _handleField(String invitationId) =>
      _handleFields.putIfAbsent(invitationId, TextEditingController.new);

  /// Plain language for each failure. No code, no provider detail.
  String _message(InvitationFailure failure) => switch (failure) {
    InvitationFailure.notConfigured =>
      'Invitations are switched off on this server.',
    InvitationFailure.unauthenticated =>
      'Sign in again to see your invitations.',
    InvitationFailure.accountMismatch => 'This account is unavailable.',
    InvitationFailure.notFound => 'That invitation is no longer there.',
    InvitationFailure.forbidden => 'That is not yours to do.',
    InvitationFailure.versionConflict =>
      'It changed while you were looking. The list is up to date now, so try again.',
    InvitationFailure.idempotencyConflict =>
      'That request was already used for something else. Try again.',
    InvitationFailure.invalidTransition =>
      'That step is not available any more.',
    InvitationFailure.expired => 'That invitation has passed its date.',
    InvitationFailure.limitReached =>
      'You have too many invitations open. Finish or cancel one first.',
    InvitationFailure.rateLimited =>
      'Too many invitation requests. Wait a moment and try again.',
    InvitationFailure.invalidXHandle => 'Enter a valid X handle.',
    InvitationFailure.xHandleNotFound => 'No X account has that handle.',
    InvitationFailure.xLinkRequired =>
      'Link one X account before answering invitations sent to you.',
    InvitationFailure.identityConflict =>
      'That X account is linked to a different Trimmy account.',
    InvitationFailure.relationshipUnavailable =>
      'That invitation cannot be completed now.',
    InvitationFailure.timeout => 'That took too long. Try again.',
    InvitationFailure.busy => 'One thing at a time.',
    InvitationFailure.invalidRequest ||
    InvitationFailure.invalidResponse ||
    InvitationFailure.invalidConfiguration ||
    InvitationFailure.closed ||
    InvitationFailure.unavailable => 'Invitations are unavailable right now.',
  };

  String _describe(InvitationRecord record) {
    final who = record.recipient == null
        ? 'nobody yet'
        : '@${record.recipient!.handleSnapshot}';
    return switch (record.state) {
      InvitationState.draft => 'Draft, not addressed yet',
      InvitationState.addressed => 'Addressed to $who, not sent',
      InvitationState.offered =>
        record.isSender
            ? 'Offered to $who, waiting for an answer'
            : '@${record.sender.handle} invited you',
      InvitationState.accepted =>
        record.isSender
            ? '$who accepted'
            : 'You accepted @${record.sender.handle}',
      InvitationState.declined =>
        record.isSender
            ? '$who declined'
            : 'You declined @${record.sender.handle}',
      InvitationState.expired => 'Passed its date',
      InvitationState.canceled => 'Cancelled',
    };
  }

  String _label(InvitationAction action) => switch (action) {
    InvitationAction.address => 'Address it',
    InvitationAction.offer => 'Send it',
    InvitationAction.accept => 'Accept',
    InvitationAction.decline => 'Decline',
    InvitationAction.cancel => 'Cancel it',
  };

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    // This panel only ever appears in a sheet someone opened on purpose, so
    // opening it is the request to see the list.
    if (!_askedOnce) {
      _askedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !controller.loaded && !controller.busy) {
          controller.refresh();
        }
      });
    }
    final busy = controller.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Invitations', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        const Text(
          'Invite someone to Trimmy by their X handle. An invitation carries '
          'no money and only records that you asked.',
        ),
        const SizedBox(height: 10),
        CraftButton(
          key: const ValueKey('invitations-create'),
          label: 'Invite someone',
          onPressed: busy ? null : () => controller.create(),
        ),
        const SizedBox(height: 6),
        TextButton(
          key: const ValueKey('invitations-refresh'),
          onPressed: busy ? null : () => controller.refresh(),
          // Nothing is fetched until it is asked for, so opening Settings does
          // not quietly make a request.
          child: Text(controller.loaded ? 'Refresh' : 'Show my invitations'),
        ),
        if (controller.failure != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _message(controller.failure!),
              key: const ValueKey('invitations-failure'),
            ),
          ),
        if (controller.incomingInvitations ==
            IncomingInvitationsStatus.xLinkRequired)
          Semantics(
            liveRegion: true,
            child: const Text(
              'Link one X account to see and answer invitations sent to you. '
              'You can still manage invitations you sent.',
              key: ValueKey('invitations-x-link-required'),
            ),
          ),
        const SizedBox(height: 10),
        if (busy) const Text('Working.'),
        if (!controller.loaded && !busy)
          const Text('Not loaded yet. Choose Show my invitations.'),
        if (controller.loaded) ...[
          Text(
            'Open invitations',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (controller.invitations.isEmpty)
            const Text('No open invitations.'),
          for (final record in controller.invitations) ..._row(record, busy),
          if (controller.hasMoreOpen)
            TextButton(
              key: const ValueKey('invitations-open-more'),
              onPressed: busy ? null : controller.loadMoreOpen,
              child: const Text('Show more open invitations'),
            ),
          const SizedBox(height: 10),
          TextButton(
            key: const ValueKey('invitations-history'),
            onPressed: busy ? null : controller.refreshHistory,
            child: Text(
              controller.historyLoaded
                  ? 'Refresh past invitations'
                  : 'Show past invitations',
            ),
          ),
          if (controller.historyLoaded) ...[
            Text(
              'Past invitations',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (controller.historyInvitations.isEmpty)
              const Text('No past invitations.'),
            for (final record in controller.historyInvitations)
              ..._row(record, busy),
            if (controller.hasMoreHistory)
              TextButton(
                key: const ValueKey('invitations-history-more'),
                onPressed: busy ? null : controller.loadMoreHistory,
                child: const Text('Show more past invitations'),
              ),
          ],
        ],
      ],
    );
  }

  List<Widget> _row(InvitationRecord record, bool busy) {
    final controller = widget.controller;
    final actions = record.availableActions;
    final canAddressThis = actions.contains(InvitationAction.address);
    return [
      const Divider(),
      Text(_describe(record), key: ValueKey('invitation-state-${record.id}')),
      Text(record.isSender ? 'You sent this' : 'From @${record.sender.handle}'),
      if (canAddressThis) ...[
        const SizedBox(height: 6),
        TextField(
          key: ValueKey('invitation-handle-${record.id}'),
          controller: _handleField(record.id),
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Their X handle'),
        ),
        const SizedBox(height: 6),
        CraftButton(
          key: ValueKey('invitation-address-${record.id}'),
          label: _label(InvitationAction.address),
          onPressed: busy
              ? null
              : () => controller.addressByHandle(
                  record,
                  _handleField(record.id).text.trim(),
                ),
        ),
      ],
      for (final action in actions)
        if (action != InvitationAction.address) ...[
          const SizedBox(height: 6),
          CraftButton(
            key: ValueKey('invitation-${action.name}-${record.id}'),
            label: _label(action),
            onPressed: busy ? null : () => controller.act(record, action),
          ),
        ],
    ];
  }
}
