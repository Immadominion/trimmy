import '../design_study/progress.dart';
import '../design_study/practice_catalog.generated.dart';
import '../practice_sync/durable_state.dart';

/// Explicitly combine compatible first Journal records, then select a draft.
/// Contradictory first answers are retained in the conflict and cannot be erased
/// by selecting a preferred draft. The coordinator rechecks the current state.
OfficeProgress? reconcilePracticeDrafts({
  required OfficeProgress local,
  required OfficeProgress remote,
  required bool useRemoteDraft,
}) {
  final localData = local.toJson();
  final remoteData = remote.toJson();
  final localNotes = localData['completions']! as Map<String, Object?>;
  final remoteNotes = remoteData['completions']! as Map<String, Object?>;
  try {
    final merged = OfficeProgress.fromJson({
      'version': practiceCatalogPayloadVersion,
      'active': useRemoteDraft ? remoteData['active'] : localData['active'],
      'completions': {...localNotes, ...remoteNotes},
    });
    assertPracticeHistoryPreserved(local, merged);
    assertPracticeHistoryPreserved(remote, merged);
    return merged;
  } catch (_) {
    return null;
  }
}
