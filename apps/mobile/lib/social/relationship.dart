/// Strict public models for Trimmy's relationship and safety API.
///
/// Every identifier here is a public UUID. Account IDs, provider subjects,
/// order IDs and credentials never cross this boundary.
library;

enum RelationshipFailure {
  invalidConfiguration,
  invalidRequest,
  unauthenticated,
  accountMismatch,
  notFound,
  forbidden,
  revisionConflict,
  idempotencyConflict,
  notActive,
  limitReached,
  pairUnavailable,
  rateLimited,
  notConfigured,
  unavailable,
  invalidResponse,
  timeout,
  busy,
  closed,
}

final class RelationshipException implements Exception {
  const RelationshipException(this.failure);

  final RelationshipFailure failure;

  bool get ambiguous => switch (failure) {
    RelationshipFailure.unavailable ||
    RelationshipFailure.invalidResponse ||
    RelationshipFailure.timeout ||
    RelationshipFailure.closed => true,
    _ => false,
  };

  @override
  String toString() => 'RelationshipException(${failure.name})';
}

enum ReasonReportCategory {
  spam,
  harassment,
  impersonation,
  unsafe,
  other;

  String get label => switch (this) {
    ReasonReportCategory.spam => 'Spam',
    ReasonReportCategory.harassment => 'Harassment',
    ReasonReportCategory.impersonation => 'Impersonation',
    ReasonReportCategory.unsafe => 'Unsafe content',
    ReasonReportCategory.other => 'Something else',
  };

  static ReasonReportCategory? parse(Object? value) {
    for (final category in values) {
      if (category.name == value) return category;
    }
    return null;
  }
}

sealed class RelationshipMutationCommand {
  const RelationshipMutationCommand();

  String get mutationId;
  Map<String, Object> toStoredJson();

  static RelationshipMutationCommand fromStoredJson(Object? value) {
    if (value is! Map<String, dynamic> || value['kind'] is! String) {
      throw const RelationshipException(RelationshipFailure.invalidResponse);
    }
    try {
      switch (value['kind']) {
        case 'remove-friend':
          if (value.length != 5 ||
              value['schemaVersion'] != 1 ||
              value['friendshipId'] is! String ||
              value['mutationId'] is! String ||
              value['expectedRevision'] is! int) {
            invalidRelationshipResponse();
          }
          return FriendRemoveCommand(
            friendshipId: value['friendshipId'] as String,
            mutationId: value['mutationId'] as String,
            expectedRevision: value['expectedRevision'] as int,
          );
        case 'put-block':
          if (value.length != 6 ||
              value['schemaVersion'] != 1 ||
              value['socialId'] is! String ||
              value['mutationId'] is! String ||
              value['baseRevision'] is! int ||
              value['blocked'] is! bool) {
            invalidRelationshipResponse();
          }
          return BlockCommand(
            socialId: value['socialId'] as String,
            mutationId: value['mutationId'] as String,
            baseRevision: value['baseRevision'] as int,
            blocked: value['blocked'] as bool,
          );
        case 'report-reason':
          if (value.length != 5 ||
              value['schemaVersion'] != 1 ||
              value['mutationId'] is! String ||
              value['reasonId'] is! String ||
              value['category'] is! String) {
            invalidRelationshipResponse();
          }
          final category = ReasonReportCategory.parse(value['category']);
          if (category == null) invalidRelationshipResponse();
          return ReasonReportCommand(
            mutationId: value['mutationId'] as String,
            reasonId: value['reasonId'] as String,
            category: category,
          );
        default:
          invalidRelationshipResponse();
      }
    } on RelationshipException catch (error) {
      if (error.failure == RelationshipFailure.invalidResponse) rethrow;
      throw const RelationshipException(RelationshipFailure.invalidResponse);
    }
  }
}

final _relationshipUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _relationshipInstant = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
final _relationshipHandle = RegExp(r'^[a-z][a-z0-9_]{2,17}$');
const _relationshipPersonas = {'wolf', 'oracle', 'shark'};
final _relationshipCursor = RegExp(r'^[A-Za-z0-9_-]{1,512}$');
const _relationshipMaxSafeInteger = 9007199254740991;
const _relationshipRankLabels = <String, String>{
  'rookie': 'Rookie',
  'analyst': 'Analyst',
  'trader': 'Trader',
  'senior-trader': 'Senior Trader',
  'partner': 'Partner',
  'legend': 'Legend',
};

Never invalidRelationshipResponse() =>
    throw const RelationshipException(RelationshipFailure.invalidResponse);

bool isRelationshipUuid(Object? value) =>
    value is String && _relationshipUuid.firstMatch(value)?.group(0) == value;

Map<String, dynamic> relationshipObject(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    invalidRelationshipResponse();
  }
  return value;
}

String _uuid(Object? value) {
  if (!isRelationshipUuid(value)) invalidRelationshipResponse();
  return value! as String;
}

int _revision(Object? value, {required bool allowZero}) {
  if (value is! int ||
      value < (allowZero ? 0 : 1) ||
      value > _relationshipMaxSafeInteger) {
    invalidRelationshipResponse();
  }
  return value;
}

DateTime _instant(Object? value) {
  if (value is! String || !_relationshipInstant.hasMatch(value)) {
    invalidRelationshipResponse();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    invalidRelationshipResponse();
  }
  return parsed;
}

String? _cursor(Object? value) {
  if (value == null) return null;
  if (value is! String || !_relationshipCursor.hasMatch(value)) {
    invalidRelationshipResponse();
  }
  return value;
}

final class RelationshipRank {
  const RelationshipRank({required this.id, required this.label});

  final String id;
  final String label;

  static RelationshipRank fromJson(Object? value) {
    final data = relationshipObject(value, const {'id', 'label'});
    final id = data['id'];
    final label = data['label'];
    if (id is! String ||
        label is! String ||
        _relationshipRankLabels[id] != label) {
      invalidRelationshipResponse();
    }
    return RelationshipRank(id: id, label: label);
  }
}

final class SocialPerson {
  const SocialPerson({
    required this.socialId,
    required this.handle,
    required this.persona,
    required this.rank,
  });

  final String socialId;
  final String handle;
  final String persona;
  final RelationshipRank rank;

  static SocialPerson fromJson(Object? value) {
    final data = relationshipObject(value, const {
      'socialId',
      'handle',
      'persona',
      'rank',
    });
    final handle = data['handle'];
    final persona = data['persona'];
    if (handle is! String ||
        !_relationshipHandle.hasMatch(handle) ||
        persona is! String ||
        !_relationshipPersonas.contains(persona)) {
      invalidRelationshipResponse();
    }
    return SocialPerson(
      socialId: _uuid(data['socialId']),
      handle: handle,
      persona: persona,
      rank: RelationshipRank.fromJson(data['rank']),
    );
  }
}

final class FriendRecord {
  const FriendRecord({
    required this.friendshipId,
    required this.revision,
    required this.connectedAt,
    required this.person,
  });

  final String friendshipId;
  final int revision;
  final DateTime connectedAt;
  final SocialPerson person;

  static FriendRecord fromJson(Object? value) {
    final data = relationshipObject(value, const {
      'friendshipId',
      'revision',
      'connectedAt',
      'person',
    });
    return FriendRecord(
      friendshipId: _uuid(data['friendshipId']),
      revision: _revision(data['revision'], allowZero: false),
      connectedAt: _instant(data['connectedAt']),
      person: SocialPerson.fromJson(data['person']),
    );
  }
}

final class FriendPage {
  const FriendPage({required this.friends, required this.nextCursor});

  final List<FriendRecord> friends;
  final String? nextCursor;

  static FriendPage fromJson(Object? value, {required int limit}) {
    final data = relationshipObject(value, const {
      'schemaVersion',
      'friends',
      'nextCursor',
    });
    final raw = data['friends'];
    if (data['schemaVersion'] != 1 || raw is! List || raw.length > limit) {
      invalidRelationshipResponse();
    }
    final rows = raw.map(FriendRecord.fromJson).toList(growable: false);
    final friendshipIds = <String>{};
    final socialIds = <String>{};
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (!friendshipIds.add(row.friendshipId) ||
          !socialIds.add(row.person.socialId)) {
        invalidRelationshipResponse();
      }
      if (index > 0 && !_friendBefore(rows[index - 1], row)) {
        invalidRelationshipResponse();
      }
    }
    return FriendPage(
      friends: List.unmodifiable(rows),
      nextCursor: _cursor(data['nextCursor']),
    );
  }

  static bool _friendBefore(FriendRecord left, FriendRecord right) {
    final time = left.connectedAt.compareTo(right.connectedAt);
    return time > 0 ||
        time == 0 && left.friendshipId.compareTo(right.friendshipId) > 0;
  }
}

final class FriendRemoveCommand extends RelationshipMutationCommand {
  factory FriendRemoveCommand({
    required String friendshipId,
    required String mutationId,
    required int expectedRevision,
  }) {
    if (!isRelationshipUuid(friendshipId) ||
        !isRelationshipUuid(mutationId) ||
        expectedRevision < 1 ||
        expectedRevision > _relationshipMaxSafeInteger) {
      throw const RelationshipException(RelationshipFailure.invalidRequest);
    }
    return FriendRemoveCommand._(
      friendshipId: friendshipId,
      mutationId: mutationId,
      expectedRevision: expectedRevision,
    );
  }

  const FriendRemoveCommand._({
    required this.friendshipId,
    required this.mutationId,
    required this.expectedRevision,
  });

  final String friendshipId;
  @override
  final String mutationId;
  final int expectedRevision;

  @override
  Map<String, Object> toStoredJson() => {
    'schemaVersion': 1,
    'kind': 'remove-friend',
    'friendshipId': friendshipId,
    'mutationId': mutationId,
    'expectedRevision': expectedRevision,
  };

  Map<String, Object> get body => {
    'schemaVersion': 1,
    'action': 'remove',
    'mutationId': mutationId,
    'expectedRevision': expectedRevision,
  };

  @override
  bool operator ==(Object other) =>
      other is FriendRemoveCommand &&
      other.friendshipId == friendshipId &&
      other.mutationId == mutationId &&
      other.expectedRevision == expectedRevision;

  @override
  int get hashCode => Object.hash(friendshipId, mutationId, expectedRevision);
}

final class FriendRemoveReceipt {
  const FriendRemoveReceipt({
    required this.mutationId,
    required this.friendshipId,
    required this.appliedRevision,
    required this.occurredAt,
  });

  final String mutationId;
  final String friendshipId;
  final int appliedRevision;
  final DateTime occurredAt;

  static FriendRemoveReceipt fromJson(
    Object? value, {
    required FriendRemoveCommand command,
  }) {
    final data = relationshipObject(value, const {
      'schemaVersion',
      'mutationId',
      'friendshipId',
      'appliedRevision',
      'state',
      'occurredAt',
    });
    final appliedRevision = _revision(
      data['appliedRevision'],
      allowZero: false,
    );
    if (data['schemaVersion'] != 1 ||
        data['state'] != 'removed' ||
        data['mutationId'] != command.mutationId ||
        data['friendshipId'] != command.friendshipId ||
        appliedRevision != command.expectedRevision + 1) {
      invalidRelationshipResponse();
    }
    return FriendRemoveReceipt(
      mutationId: command.mutationId,
      friendshipId: command.friendshipId,
      appliedRevision: appliedRevision,
      occurredAt: _instant(data['occurredAt']),
    );
  }
}

final class BlockedProfile {
  const BlockedProfile({
    required this.socialId,
    required this.handle,
    required this.revision,
    required this.updatedAt,
  });

  final String socialId;
  final String? handle;
  final int revision;
  final DateTime updatedAt;

  static BlockedProfile fromJson(Object? value) {
    final data = relationshipObject(value, const {
      'socialId',
      'handle',
      'revision',
      'updatedAt',
    });
    final handle = data['handle'];
    if (handle != null &&
        (handle is! String || !_relationshipHandle.hasMatch(handle))) {
      invalidRelationshipResponse();
    }
    return BlockedProfile(
      socialId: _uuid(data['socialId']),
      handle: handle as String?,
      revision: _revision(data['revision'], allowZero: false),
      updatedAt: _instant(data['updatedAt']),
    );
  }
}

final class BlockPage {
  const BlockPage({required this.blocks, required this.nextCursor});

  final List<BlockedProfile> blocks;
  final String? nextCursor;

  static BlockPage fromJson(Object? value, {required int limit}) {
    final data = relationshipObject(value, const {
      'schemaVersion',
      'blocks',
      'nextCursor',
    });
    final raw = data['blocks'];
    if (data['schemaVersion'] != 1 || raw is! List || raw.length > limit) {
      invalidRelationshipResponse();
    }
    final rows = raw.map(BlockedProfile.fromJson).toList(growable: false);
    final socialIds = <String>{};
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (!socialIds.add(row.socialId)) invalidRelationshipResponse();
      if (index > 0 && !_blockBefore(rows[index - 1], row)) {
        invalidRelationshipResponse();
      }
    }
    return BlockPage(
      blocks: List.unmodifiable(rows),
      nextCursor: _cursor(data['nextCursor']),
    );
  }

  static bool _blockBefore(BlockedProfile left, BlockedProfile right) {
    final time = left.updatedAt.compareTo(right.updatedAt);
    return time > 0 || time == 0 && left.socialId.compareTo(right.socialId) > 0;
  }
}

/// The caller's exact outgoing block snapshot for one public target.
/// Revision zero means no row has ever existed and therefore has no timestamp.
final class BlockState {
  const BlockState({
    required this.socialId,
    required this.revision,
    required this.blocked,
    required this.updatedAt,
  });

  final String socialId;
  final int revision;
  final bool blocked;
  final DateTime? updatedAt;

  static BlockState fromJson(Object? value, {required String socialId}) {
    final envelope = relationshipObject(value, const {
      'schemaVersion',
      'block',
    });
    final data = relationshipObject(envelope['block'], const {
      'socialId',
      'revision',
      'blocked',
      'updatedAt',
    });
    final revision = _revision(data['revision'], allowZero: true);
    final updatedAt = data['updatedAt'];
    if (envelope['schemaVersion'] != 1 ||
        data['socialId'] != socialId ||
        data['blocked'] is! bool ||
        (revision == 0 && (data['blocked'] != false || updatedAt != null)) ||
        (revision > 0 && updatedAt == null)) {
      invalidRelationshipResponse();
    }
    return BlockState(
      socialId: socialId,
      revision: revision,
      blocked: data['blocked'] as bool,
      updatedAt: updatedAt == null ? null : _instant(updatedAt),
    );
  }
}

final class BlockCommand extends RelationshipMutationCommand {
  factory BlockCommand({
    required String socialId,
    required String mutationId,
    required int baseRevision,
    required bool blocked,
  }) {
    if (!isRelationshipUuid(socialId) ||
        !isRelationshipUuid(mutationId) ||
        baseRevision < 0 ||
        baseRevision > _relationshipMaxSafeInteger) {
      throw const RelationshipException(RelationshipFailure.invalidRequest);
    }
    return BlockCommand._(
      socialId: socialId,
      mutationId: mutationId,
      baseRevision: baseRevision,
      blocked: blocked,
    );
  }

  const BlockCommand._({
    required this.socialId,
    required this.mutationId,
    required this.baseRevision,
    required this.blocked,
  });

  final String socialId;
  @override
  final String mutationId;
  final int baseRevision;
  final bool blocked;

  @override
  Map<String, Object> toStoredJson() => {
    'schemaVersion': 1,
    'kind': 'put-block',
    'socialId': socialId,
    'mutationId': mutationId,
    'baseRevision': baseRevision,
    'blocked': blocked,
  };

  Map<String, Object> get body => {
    'schemaVersion': 1,
    'mutationId': mutationId,
    'baseRevision': baseRevision,
    'blocked': blocked,
  };

  @override
  bool operator ==(Object other) =>
      other is BlockCommand &&
      other.socialId == socialId &&
      other.mutationId == mutationId &&
      other.baseRevision == baseRevision &&
      other.blocked == blocked;

  @override
  int get hashCode => Object.hash(socialId, mutationId, baseRevision, blocked);
}

final class BlockSnapshot {
  const BlockSnapshot({
    required this.socialId,
    required this.revision,
    required this.blocked,
    required this.updatedAt,
  });

  final String socialId;
  final int revision;
  final bool blocked;
  final DateTime updatedAt;

  static BlockSnapshot fromJson(Object? value) {
    final data = relationshipObject(value, const {
      'socialId',
      'revision',
      'blocked',
      'updatedAt',
    });
    if (data['blocked'] is! bool) invalidRelationshipResponse();
    return BlockSnapshot(
      socialId: _uuid(data['socialId']),
      revision: _revision(data['revision'], allowZero: false),
      blocked: data['blocked'] as bool,
      updatedAt: _instant(data['updatedAt']),
    );
  }
}

final class BlockReceipt {
  const BlockReceipt({
    required this.mutationId,
    required this.appliedRevision,
    required this.block,
  });

  final String mutationId;
  final int appliedRevision;
  final BlockSnapshot block;

  static BlockReceipt fromJson(Object? value, {required BlockCommand command}) {
    final data = relationshipObject(value, const {
      'schemaVersion',
      'mutationId',
      'appliedRevision',
      'block',
    });
    final appliedRevision = _revision(
      data['appliedRevision'],
      allowZero: false,
    );
    final snapshot = BlockSnapshot.fromJson(data['block']);
    if (data['schemaVersion'] != 1 ||
        data['mutationId'] != command.mutationId ||
        snapshot.socialId != command.socialId ||
        appliedRevision != command.baseRevision + 1 ||
        snapshot.revision < appliedRevision ||
        snapshot.revision == appliedRevision &&
            snapshot.blocked != command.blocked) {
      invalidRelationshipResponse();
    }
    return BlockReceipt(
      mutationId: command.mutationId,
      appliedRevision: appliedRevision,
      block: snapshot,
    );
  }
}

final class ReasonReportCommand extends RelationshipMutationCommand {
  factory ReasonReportCommand({
    required String mutationId,
    required String reasonId,
    required ReasonReportCategory category,
  }) {
    if (!isRelationshipUuid(mutationId) || !isRelationshipUuid(reasonId)) {
      throw const RelationshipException(RelationshipFailure.invalidRequest);
    }
    return ReasonReportCommand._(
      mutationId: mutationId,
      reasonId: reasonId,
      category: category,
    );
  }

  const ReasonReportCommand._({
    required this.mutationId,
    required this.reasonId,
    required this.category,
  });

  @override
  final String mutationId;
  final String reasonId;
  final ReasonReportCategory category;

  @override
  Map<String, Object> toStoredJson() => {
    'schemaVersion': 1,
    'kind': 'report-reason',
    'mutationId': mutationId,
    'reasonId': reasonId,
    'category': category.name,
  };

  Map<String, Object> get body => {
    'schemaVersion': 1,
    'mutationId': mutationId,
    'reasonId': reasonId,
    'category': category.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ReasonReportCommand &&
      other.mutationId == mutationId &&
      other.reasonId == reasonId &&
      other.category == category;

  @override
  int get hashCode => Object.hash(mutationId, reasonId, category);
}

final class ReasonReportReceipt {
  const ReasonReportReceipt({
    required this.reportId,
    required this.reasonId,
    required this.category,
    required this.receivedAt,
  });

  final String reportId;
  final String reasonId;
  final ReasonReportCategory category;
  final DateTime receivedAt;

  static ReasonReportReceipt fromJson(
    Object? value, {
    required ReasonReportCommand command,
    required bool created,
  }) {
    final envelope = relationshipObject(value, const {
      'schemaVersion',
      'report',
    });
    final data = relationshipObject(envelope['report'], const {
      'reportId',
      'reasonId',
      'category',
      'receivedAt',
    });
    final category = ReasonReportCategory.parse(data['category']);
    if (envelope['schemaVersion'] != 1 ||
        data['reasonId'] != command.reasonId ||
        category == null ||
        (created && category != command.category)) {
      invalidRelationshipResponse();
    }
    return ReasonReportReceipt(
      reportId: _uuid(data['reportId']),
      reasonId: command.reasonId,
      category: category,
      receivedAt: _instant(data['receivedAt']),
    );
  }
}
