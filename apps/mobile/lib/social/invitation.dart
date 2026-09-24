/// Client-side models for unfunded invitation schema version 2.
///
/// The server resolves X handles and proves linked identities. The mobile app
/// never receives, stores or returns a numeric X subject.
library;

enum InvitationBox {
  open,
  history;

  String get wireValue => name;
}

enum IncomingInvitationsStatus {
  available,
  xLinkRequired;

  static IncomingInvitationsStatus? parse(Object? value) => switch (value) {
    'available' => IncomingInvitationsStatus.available,
    'x_link_required' => IncomingInvitationsStatus.xLinkRequired,
    _ => null,
  };
}

enum InvitationState {
  draft,
  addressed,
  offered,
  accepted,
  declined,
  expired,
  canceled;

  static InvitationState? parse(Object? value) {
    for (final state in InvitationState.values) {
      if (state.name == value) return state;
    }
    return null;
  }

  bool get isTerminal => const {
    InvitationState.accepted,
    InvitationState.declined,
    InvitationState.expired,
    InvitationState.canceled,
  }.contains(this);
}

enum InvitationRole {
  sender,
  recipient;

  static InvitationRole? parse(Object? value) => switch (value) {
    'sender' => InvitationRole.sender,
    'recipient' => InvitationRole.recipient,
    _ => null,
  };
}

enum InvitationAction { address, offer, accept, decline, cancel }

enum InvitationFailure {
  invalidConfiguration,
  invalidRequest,
  unauthenticated,
  accountMismatch,
  notFound,
  forbidden,
  versionConflict,
  idempotencyConflict,
  invalidTransition,
  expired,
  limitReached,
  rateLimited,
  invalidXHandle,
  xHandleNotFound,
  xLinkRequired,
  identityConflict,
  relationshipUnavailable,
  notConfigured,
  unavailable,
  invalidResponse,
  timeout,
  busy,
  closed,
}

class InvitationException implements Exception {
  const InvitationException(this.failure);

  final InvitationFailure failure;

  @override
  String toString() => 'InvitationException(${failure.name})';
}

Never invalidInvitationResponse() =>
    throw const InvitationException(InvitationFailure.invalidResponse);

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _instantPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
final _productHandle = RegExp(r'^[a-z][a-z0-9_]{2,17}$');
final _xHandle = RegExp(r'^[a-z0-9_]{1,15}$');
final _persona = RegExp(r'^[a-z][a-z0-9-]{0,30}$');
const _personas = {'wolf', 'oracle', 'shark'};
final _cursor = RegExp(r'^[A-Za-z0-9_-]{1,512}$');
const _maxSafeInteger = 9007199254740991;
const _rankLabels = <String, String>{
  'rookie': 'Rookie',
  'analyst': 'Analyst',
  'trader': 'Trader',
  'senior-trader': 'Senior Trader',
  'partner': 'Partner',
  'legend': 'Legend',
};

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    invalidInvitationResponse();
  }
  return value;
}

String _text(Object? value, RegExp pattern) {
  if (value is! String || pattern.firstMatch(value)?.group(0) != value) {
    invalidInvitationResponse();
  }
  return value;
}

DateTime _instant(Object? value) {
  final text = _text(value, _instantPattern);
  final parsed = DateTime.tryParse(text);
  if (parsed == null || parsed.toUtc().toIso8601String() != text) {
    invalidInvitationResponse();
  }
  return parsed.toUtc();
}

final class InvitationRank {
  const InvitationRank({required this.id, required this.label});

  final String id;
  final String label;

  static InvitationRank _fromJson(Object? value) {
    final data = _object(value, const {'id', 'label'});
    final id = data['id'];
    final label = data['label'];
    if (id is! String || label is! String || _rankLabels[id] != label) {
      invalidInvitationResponse();
    }
    return InvitationRank(id: id, label: label);
  }
}

/// The bounded public sender projection included in every invitation.
final class InvitationSender {
  const InvitationSender({
    required this.socialId,
    required this.handle,
    required this.persona,
    required this.rank,
  });

  final String socialId;
  final String handle;
  final String persona;
  final InvitationRank rank;

  static InvitationSender _fromJson(Object? value) {
    final data = _object(value, const {
      'socialId',
      'handle',
      'persona',
      'rank',
    });
    final persona = _text(data['persona'], _persona);
    if (!_personas.contains(persona)) invalidInvitationResponse();
    return InvitationSender(
      socialId: _text(data['socialId'], _uuid),
      handle: _text(data['handle'], _productHandle),
      persona: persona,
      rank: InvitationRank._fromJson(data['rank']),
    );
  }
}

/// The public destination snapshot. It deliberately contains no X subject.
final class InvitationRecipient {
  const InvitationRecipient({required this.handleSnapshot});

  final String handleSnapshot;

  static InvitationRecipient _fromJson(Object? value) {
    final data = _object(value, const {'provider', 'handleSnapshot'});
    if (data['provider'] != 'x') invalidInvitationResponse();
    return InvitationRecipient(
      handleSnapshot: _text(data['handleSnapshot'], _xHandle),
    );
  }
}

/// One invitation exactly as schema version 2 describes it.
final class InvitationRecord {
  const InvitationRecord({
    required this.id,
    required this.state,
    required this.role,
    required this.sender,
    required this.recipient,
    required this.expiresAt,
    required this.createdAt,
    required this.acceptedAt,
    required this.version,
  });

  final String id;
  final InvitationState state;
  final InvitationRole role;
  final InvitationSender sender;
  final InvitationRecipient? recipient;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final int version;

  bool get isUnfunded => true;
  bool get isSender => role == InvitationRole.sender;

  Set<InvitationAction> get availableActions {
    if (state.isTerminal) return const {};
    if (isSender) {
      return switch (state) {
        InvitationState.draft => const {
          InvitationAction.address,
          InvitationAction.cancel,
        },
        InvitationState.addressed => const {
          InvitationAction.offer,
          InvitationAction.cancel,
        },
        InvitationState.offered => const {InvitationAction.cancel},
        _ => const {},
      };
    }
    return state == InvitationState.offered
        ? const {InvitationAction.accept, InvitationAction.decline}
        : const {};
  }

  static InvitationRecord fromJson(Object? value) {
    final data = _object(value, const {
      'schemaVersion',
      'id',
      'state',
      'funding',
      'sender',
      'recipient',
      'expiresAt',
      'createdAt',
      'acceptedAt',
      'version',
      'role',
    });
    final state = InvitationState.parse(data['state']);
    final role = InvitationRole.parse(data['role']);
    final version = data['version'];
    final accepted = data['acceptedAt'];
    final recipient = data['recipient'];
    if (data['schemaVersion'] != 2 ||
        data['funding'] != 'unfunded' ||
        state == null ||
        role == null ||
        version is! int ||
        version < 0 ||
        version >= _maxSafeInteger) {
      invalidInvitationResponse();
    }
    if ((state == InvitationState.accepted) != (accepted != null) ||
        (state == InvitationState.draft && recipient != null) ||
        (const {
              InvitationState.addressed,
              InvitationState.offered,
              InvitationState.accepted,
              InvitationState.declined,
            }.contains(state) &&
            recipient == null)) {
      invalidInvitationResponse();
    }
    return InvitationRecord(
      id: _text(data['id'], _uuid),
      state: state,
      role: role,
      sender: InvitationSender._fromJson(data['sender']),
      recipient: recipient == null
          ? null
          : InvitationRecipient._fromJson(recipient),
      expiresAt: _instant(data['expiresAt']),
      createdAt: _instant(data['createdAt']),
      acceptedAt: accepted == null ? null : _instant(accepted),
      version: version,
    );
  }
}

/// One bounded page. The cursor remains opaque and is only returned to the
/// same list endpoint with the same box.
final class InvitationPage {
  const InvitationPage({
    required this.box,
    required this.incomingInvitations,
    required this.invitations,
    required this.nextCursor,
  });

  final InvitationBox box;
  final IncomingInvitationsStatus incomingInvitations;
  final List<InvitationRecord> invitations;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  static InvitationPage fromJson(
    Object? value, {
    required InvitationBox box,
    required int limit,
  }) {
    final data = _object(value, const {
      'schemaVersion',
      'incomingInvitations',
      'invitations',
      'nextCursor',
    });
    final incoming = IncomingInvitationsStatus.parse(
      data['incomingInvitations'],
    );
    final rows = data['invitations'];
    final cursor = data['nextCursor'];
    if (data['schemaVersion'] != 2 ||
        incoming == null ||
        rows is! List ||
        rows.length > limit ||
        (rows.isEmpty && cursor != null) ||
        (cursor != null &&
            (cursor is! String ||
                _cursor.firstMatch(cursor)?.group(0) != cursor))) {
      invalidInvitationResponse();
    }
    final records = <InvitationRecord>[];
    final seen = <String>{};
    for (final row in rows) {
      final record = InvitationRecord.fromJson(row);
      if (!seen.add(record.id) ||
          (box == InvitationBox.open && record.state.isTerminal) ||
          (box == InvitationBox.history && !record.state.isTerminal) ||
          (box == InvitationBox.open &&
              incoming == IncomingInvitationsStatus.xLinkRequired &&
              !record.isSender)) {
        invalidInvitationResponse();
      }
      if (records.isNotEmpty) {
        final previous = records.last;
        final wrongTime = previous.createdAt.isBefore(record.createdAt);
        final wrongTie =
            previous.createdAt == record.createdAt &&
            previous.id.compareTo(record.id) < 0;
        if (wrongTime || wrongTie) invalidInvitationResponse();
      }
      records.add(record);
    }
    return InvitationPage(
      box: box,
      incomingInvitations: incoming,
      invitations: List.unmodifiable(records),
      nextCursor: cursor as String?,
    );
  }
}
