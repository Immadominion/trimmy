import 'dart:convert';

import 'package:trimmy/design_study/progress.dart';

const practiceMaxRevision = 9007199254740991;
const practiceMaxProgressBytes = 32768;
const practiceMaxEnvelopeBytes = 36864;

class PracticeSyncException implements Exception {
  const PracticeSyncException(this.code);
  final String code;

  @override
  String toString() => 'PracticeSyncException($code)';
}

class PracticeRevisionConflict extends PracticeSyncException {
  const PracticeRevisionConflict(this.currentSnapshot)
    : super('PRACTICE_REVISION_CONFLICT');

  final PracticeSnapshot currentSnapshot;
}

abstract interface class PracticeTransport {
  String get accountId;
  Future<PracticeSnapshot> getProgress();
  Future<PracticeSnapshot> putProgress(PracticeMutation mutation);
}

/// UUIDs identify server accounts and logical writes; they do not authenticate.
String normalizePracticeUuid(Object? input) {
  if (input is! String ||
      input.length != 36 ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(input)) {
    _invalid();
  }
  return input.toLowerCase();
}

class PracticeSnapshot {
  factory PracticeSnapshot({
    required int revision,
    required OfficeProgress? progress,
    required DateTime? updatedAt,
  }) {
    _revision(revision);
    if (revision == 0) {
      if (progress != null || updatedAt != null) _invalid();
      return const PracticeSnapshot._(0, null, null);
    }
    if (progress == null || updatedAt == null || !updatedAt.isUtc) _invalid();
    final time = _serverTime(updatedAt.toIso8601String());
    return PracticeSnapshot._(revision, _progress(progress.toJson()), time);
  }

  const PracticeSnapshot._(this.revision, this.progress, this.updatedAt);

  factory PracticeSnapshot.fromJson(Object? input) {
    final data = _object(input, const {
      'schemaVersion',
      'revision',
      'progress',
      'updatedAt',
    });
    _version(data['schemaVersion']);
    final revision = _revision(data['revision']);
    if (revision == 0) {
      if (data['progress'] != null || data['updatedAt'] != null) _invalid();
      return const PracticeSnapshot._(0, null, null);
    }
    return PracticeSnapshot._(
      revision,
      _progress(data['progress']),
      _serverTime(data['updatedAt']),
    );
  }

  final int revision;
  final OfficeProgress? progress;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': revision,
    'progress': progress?.toJson(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}

class PracticeMutation {
  factory PracticeMutation({
    required String mutationId,
    required int baseRevision,
    required OfficeProgress progress,
  }) => PracticeMutation._(
    normalizePracticeUuid(mutationId),
    _revision(baseRevision),
    _progress(progress.toJson()),
  );

  const PracticeMutation._(this.mutationId, this.baseRevision, this.progress);

  factory PracticeMutation.fromJson(Object? input) {
    final data = _object(input, const {
      'schemaVersion',
      'mutationId',
      'baseRevision',
      'progress',
    });
    _version(data['schemaVersion']);
    return PracticeMutation._(
      normalizePracticeUuid(data['mutationId']),
      _revision(data['baseRevision']),
      _progress(data['progress']),
    );
  }

  final String mutationId;
  final int baseRevision;
  final OfficeProgress progress;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'mutationId': mutationId,
    'baseRevision': baseRevision,
    'progress': progress.toJson(),
  };
}

/// Stable key order and exact native timestamps; no mutation of caller data.
String canonicalProgress(OfficeProgress progress) =>
    jsonEncode(_canonical(_progress(progress.toJson()).toJson()));

/// Compare working copies independently of their transport version. Receipts and
/// pending uploads must continue to use [canonicalProgress] for exact identity.
String canonicalProgressContent(OfficeProgress progress) {
  final data = _progress(progress.toJson()).toJson()..remove('version');
  return jsonEncode(_canonical(data));
}

bool samePracticeProgress(OfficeProgress left, OfficeProgress right) =>
    canonicalProgressContent(left) == canonicalProgressContent(right);

Object? _canonical(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList(growable: false);
  return value;
}

Map<String, dynamic> _object(Object? input, Set<String> fields) {
  if (input is! Map<String, dynamic> ||
      input.length != fields.length ||
      !fields.every(input.containsKey)) {
    _invalid();
  }
  return input;
}

void _version(Object? input) {
  if (input is! int || input != 1) _invalid();
}

int _revision(Object? input) {
  if (input is! int || input < 0 || input > practiceMaxRevision) _invalid();
  return input;
}

DateTime _serverTime(Object? input) {
  if (input is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
      ).hasMatch(input)) {
    _invalid();
  }
  final time = DateTime.tryParse(input);
  if (time == null || !time.isUtc || time.toIso8601String() != input) {
    _invalid();
  }
  return time;
}

OfficeProgress _progress(Object? input) {
  try {
    final data = _object(input, const {'version', 'active', 'completions'});
    if (data['version'] is! int ||
        (data['version'] != 3 &&
            data['version'] != 4 &&
            data['version'] != 5 &&
            data['version'] != 6)) {
      _invalid();
    }
    if (utf8.encode(jsonEncode(data)).length > practiceMaxProgressBytes) {
      _invalid();
    }
    return OfficeProgress.fromJson(data);
  } catch (_) {
    _invalid();
  }
}

Never _invalid() =>
    throw const PracticeSyncException('PRACTICE_INVALID_PROTOCOL');
