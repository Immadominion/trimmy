import 'dart:convert';

import '../design_study/progress.dart';
import 'protocol.dart';

/// A store is scoped by its explicit key. Implementations never store tokens.
abstract interface class PracticeSyncStore {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
}

enum PracticeSyncLoadIssue {
  storageReadFailed,
  storageWriteFailed,
  corruptState,
  unsupportedVersion,
  accountMismatch,
}

String normalizePracticeAccountId(String accountId) {
  if (accountId.length != 36 ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(accountId)) {
    throw const PracticeSyncException('PRACTICE_INVALID_ACCOUNT');
  }
  return accountId.toLowerCase();
}

String _canonical(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonical(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonical).join(',')}]';
  return jsonEncode(value);
}

OfficeProgress _progress(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const PracticeSyncException('PRACTICE_SYNC_STATE_CORRUPT');
  }
  if (value['version'] is int && (value['version'] as int) > 6) {
    throw const PracticeSyncException('PRACTICE_SYNC_STATE_UNSUPPORTED');
  }
  if (value['version'] != 3 &&
      value['version'] != 4 &&
      value['version'] != 5 &&
      value['version'] != 6) {
    throw const PracticeSyncException('PRACTICE_SYNC_STATE_CORRUPT');
  }
  return OfficeProgress.fromJson(value);
}

void _checkNestedVersion(Object? value) {
  if (value is! Map<String, dynamic>) return;
  final schemaVersion = value['schemaVersion'];
  final progress = value['progress'];
  if ((schemaVersion is int && schemaVersion > 1) ||
      (progress is Map<String, dynamic> &&
          progress['version'] is int &&
          (progress['version'] as int) > 6)) {
    throw const PracticeSyncException('PRACTICE_SYNC_STATE_UNSUPPORTED');
  }
}

/// A replay can change the active attempt, but never its first saved answers.
void assertPracticeHistoryPreserved(
  OfficeProgress previous,
  OfficeProgress next,
) {
  for (final entry in previous.completions.entries) {
    final replacement = next.completions[entry.key];
    if (replacement == null ||
        _canonical(entry.value.toJson()) != _canonical(replacement.toJson())) {
      throw const PracticeSyncException('PRACTICE_HISTORY_CONFLICT');
    }
  }
}

/// One atomic record keeps the working copy, last server baseline and retry
/// intent together. A conflict stores both sides until explicit reconciliation.
class PracticeSyncState {
  factory PracticeSyncState({
    required String accountId,
    required OfficeProgress local,
    required PracticeSnapshot? base,
    required PracticeMutation? pending,
    required PracticeSnapshot? conflict,
  }) {
    final account = normalizePracticeAccountId(accountId);
    final localCopy = _progress(jsonDecode(jsonEncode(local.toJson())));
    final baseCopy = base == null
        ? null
        : PracticeSnapshot.fromJson(base.toJson());
    final pendingCopy = pending == null
        ? null
        : PracticeMutation.fromJson(pending.toJson());
    final conflictCopy = conflict == null
        ? null
        : PracticeSnapshot.fromJson(conflict.toJson());
    if (pendingCopy != null &&
        (baseCopy == null ||
            conflictCopy != null ||
            pendingCopy.baseRevision != baseCopy.revision)) {
      throw const PracticeSyncException('PRACTICE_SYNC_STATE_CORRUPT');
    }
    if (baseCopy?.progress case final baseline?) {
      assertPracticeHistoryPreserved(baseline, localCopy);
      if (pendingCopy != null) {
        assertPracticeHistoryPreserved(baseline, pendingCopy.progress);
      }
    }
    if (pendingCopy != null) {
      assertPracticeHistoryPreserved(pendingCopy.progress, localCopy);
    }
    return PracticeSyncState._(
      account,
      localCopy,
      baseCopy,
      pendingCopy,
      conflictCopy,
    );
  }

  const PracticeSyncState._(
    this.accountId,
    this.local,
    this.base,
    this.pending,
    this.conflict,
  );

  final String accountId;
  final OfficeProgress local;
  final PracticeSnapshot? base;
  final PracticeMutation? pending;
  final PracticeSnapshot? conflict;

  static const maxBytes = 160 * 1024;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'accountId': accountId,
    'local': local.toJson(),
    'base': base?.toJson(),
    'pending': pending?.toJson(),
    'conflict': conflict?.toJson(),
  };

  String encode() {
    final raw = _canonical(toJson());
    if (utf8.encode(raw).length > maxBytes) {
      throw const PracticeSyncException('PRACTICE_SYNC_STATE_TOO_LARGE');
    }
    return raw;
  }

  factory PracticeSyncState.decode(String raw, {required String accountId}) {
    try {
      if (utf8.encode(raw).length > maxBytes) {
        throw const PracticeSyncException('PRACTICE_SYNC_STATE_CORRUPT');
      }
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        throw const PracticeSyncException('PRACTICE_SYNC_STATE_CORRUPT');
      }
      if (data['schemaVersion'] is int && (data['schemaVersion'] as int) > 1) {
        throw const PracticeSyncException('PRACTICE_SYNC_STATE_UNSUPPORTED');
      }
      const fields = {
        'schemaVersion',
        'accountId',
        'local',
        'base',
        'pending',
        'conflict',
      };
      if (data.length != fields.length ||
          !fields.every(data.containsKey) ||
          data['schemaVersion'] is! int ||
          data['schemaVersion'] != 1) {
        throw const PracticeSyncException('PRACTICE_SYNC_STATE_CORRUPT');
      }
      if (data['accountId'] != normalizePracticeAccountId(accountId)) {
        throw const PracticeSyncException('PRACTICE_SYNC_ACCOUNT_MISMATCH');
      }
      for (final field in const ['base', 'pending', 'conflict']) {
        _checkNestedVersion(data[field]);
      }
      return PracticeSyncState(
        accountId: accountId,
        local: _progress(data['local']),
        base: data['base'] == null
            ? null
            : PracticeSnapshot.fromJson(data['base']),
        pending: data['pending'] == null
            ? null
            : PracticeMutation.fromJson(data['pending']),
        conflict: data['conflict'] == null
            ? null
            : PracticeSnapshot.fromJson(data['conflict']),
      );
    } on PracticeSyncException catch (error) {
      if (const {
        'PRACTICE_SYNC_STATE_UNSUPPORTED',
        'PRACTICE_SYNC_ACCOUNT_MISMATCH',
      }.contains(error.code)) {
        rethrow;
      }
      throw const PracticeSyncException('PRACTICE_SYNC_STATE_CORRUPT');
    } catch (_) {
      throw const PracticeSyncException('PRACTICE_SYNC_STATE_CORRUPT');
    }
  }
}
