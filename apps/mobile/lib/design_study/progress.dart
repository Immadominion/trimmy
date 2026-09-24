import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_assignment.dart';
import 'practice_catalog.generated.dart';

/// Local practice progress only. SharedPreferences is not a financial ledger or
/// a guarantee against OS-level data loss; successful writes are the UI boundary.
abstract final class OfficeActivityIds {
  static const checkTheDate = 'check-the-date';
  static const salesAndProfit = 'sales-and-profit';
  static const checkTheSample = 'check-the-sample';
  static const prepareTheUpdate = 'prepare-the-update';
  static const compareCompanyValue = 'compare-company-value';
  static const countTheFees = 'count-the-fees';
  static const checkConcentration = 'check-concentration';
  static const prepareTheComparison = 'prepare-the-comparison';
  static const reviewTeamUpdate = 'review-team-update';
  static const readReturnedCosts = 'read-returned-costs';
  static const finishTeamUpdate = 'finish-team-update';
  static const setALossLimit = 'set-a-loss-limit';
  static const planNotAPromise = 'plan-not-a-promise';
  static const writeThePlan = 'write-the-plan';
  static const all = practiceCatalogActivityIds;
}

final _choices = Map<String, List<String>>.unmodifiable(
  practiceCatalogById.map((id, entry) => MapEntry(id, entry.choiceIds)),
);

const _sampleParts = {
  'amount': ['eight-of-ten', 'all'],
  'group': ['testers', 'customers'],
};

String? _sampleChoice(Map<String, String> parts) =>
    parts.length == _sampleParts.length
    ? '${parts['amount']}-${parts['group']}'
    : null;

bool _acceptedChoice(String activityId, String choiceId) =>
    practiceCatalogById[activityId]?.acceptedChoiceIds.contains(choiceId) ==
    true;

bool _unlocked(String activityId, Map<String, ActivityCompletion> completions) {
  final entry = practiceCatalogById[activityId];
  return entry != null &&
      (entry.prerequisiteId == null ||
          completions.containsKey(entry.prerequisiteId));
}

bool _validPart(String activityId, String part, Object? value) =>
    activityId == OfficeActivityIds.prepareTheUpdate
    ? updateFacts.any((fact) => fact.id == part) &&
          (value == 'included' || value == 'excluded')
    : activityId == OfficeActivityIds.checkTheSample &&
          _sampleParts.containsKey(part) &&
          _sampleParts[part]!.contains(value);

void _requireActivity(String id) {
  if (!_choices.containsKey(id)) throw ArgumentError.value(id, 'activityId');
}

class ActivityProgress {
  ActivityProgress._({
    required this.activityId,
    required this.stage,
    required this.selectedChoiceId,
    required this.corrected,
    Map<String, String> answerParts = const {},
  }) : answerParts = Map.unmodifiable(answerParts);

  final String activityId;

  /// 0 brief, 1 source, 2 decision, 3 correction, 4 saved outcome.
  final int stage;
  final String? selectedChoiceId;
  final bool corrected;

  /// Independently acknowledged choices. The combined choice exists only after
  /// both sample parts or exactly three company-update facts are selected.
  final Map<String, String> answerParts;

  Map<String, Object?> toJson() => {
    'activityId': activityId,
    'stage': stage,
    'selectedChoiceId': selectedChoiceId,
    'corrected': corrected,
    'answerParts': answerParts,
  };
}

class ActivityCompletion {
  const ActivityCompletion._({
    required this.activityId,
    required this.selectedChoiceId,
    required this.corrected,
    required this.completedAt,
    required this.importedFromLegacy,
  });

  final String activityId;

  /// The original submitted choice, including a choice later corrected.
  final String selectedChoiceId;
  final bool corrected;

  /// Only legacy records without a saved time may have an unknown date.
  final DateTime? completedAt;
  final bool importedFromLegacy;

  Map<String, Object?> toJson() => {
    'activityId': activityId,
    'selectedChoiceId': selectedChoiceId,
    'corrected': corrected,
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'importedFromLegacy': importedFromLegacy,
  };
}

/// Immutable, pure state transitions. Replays never replace first completions.
class OfficeProgress {
  OfficeProgress._({
    this.active,
    this.wireVersion = practiceCatalogPayloadVersion,
    Map<String, ActivityCompletion> completions = const {},
  }) : completions = Map.unmodifiable(completions);

  factory OfficeProgress.empty() => OfficeProgress._();

  final ActivityProgress? active;

  /// Decoded historical records retain their original representation for
  /// pending requests and receipts. A new acknowledged transition uses the
  /// current catalog payload version.
  final int wireVersion;
  final Map<String, ActivityCompletion> completions;

  bool isUnlocked(String activityId) => _unlocked(activityId, completions);

  /// Use only when preparing a new local write, never to reconstruct a receipt
  /// or an existing pending mutation from storage.
  OfficeProgress upgradeForWrite() =>
      wireVersion == practiceCatalogPayloadVersion
      ? this
      : OfficeProgress._(active: active, completions: completions);

  OfficeProgress startActivity(String activityId) {
    _requireActivity(activityId);
    if (!isUnlocked(activityId)) throw StateError('Activity is locked.');
    if (active?.activityId == activityId) return this;
    if (active != null && active!.stage != 4) {
      throw StateError('Resume the unfinished activity first.');
    }
    return _withActive(
      ActivityProgress._(
        activityId: activityId,
        stage: 0,
        selectedChoiceId: null,
        corrected: false,
      ),
    );
  }

  /// Reinspect neighboring pre-submission stages without discarding a choice.
  OfficeProgress inspectStage(int next) {
    final task = _task;
    if (task.stage > 2 ||
        next < 0 ||
        next > 2 ||
        (next - task.stage).abs() > 1) {
      throw StateError('Only adjacent inspection stages can be opened.');
    }
    if (task.stage == next) return this;
    return _withActive(
      ActivityProgress._(
        activityId: task.activityId,
        stage: next,
        selectedChoiceId: task.selectedChoiceId,
        corrected: false,
        answerParts: task.answerParts,
      ),
    );
  }

  OfficeProgress advance() => inspectStage(_task.stage + 1);

  OfficeProgress selectChoice(String choiceId) {
    final task = _task;
    if (task.stage != 2) throw StateError('Open the decision before choosing.');
    if (task.activityId == OfficeActivityIds.checkTheSample ||
        task.activityId == OfficeActivityIds.prepareTheUpdate) {
      throw StateError('Build this answer by selecting its parts.');
    }
    if (!_choices[task.activityId]!.contains(choiceId)) {
      throw ArgumentError.value(choiceId, 'choiceId');
    }
    if (task.selectedChoiceId == choiceId) return this;
    return _withActive(
      ActivityProgress._(
        activityId: task.activityId,
        stage: 2,
        selectedChoiceId: choiceId,
        corrected: false,
      ),
    );
  }

  OfficeProgress selectAnswerPart(String part, String value) {
    final task = _task;
    if (task.stage != 2) throw StateError('Open the decision before choosing.');
    final isUpdate = task.activityId == OfficeActivityIds.prepareTheUpdate;
    if (task.activityId != OfficeActivityIds.checkTheSample && !isUpdate) {
      throw StateError('This activity does not use answer parts.');
    }
    if (isUpdate
        ? !updateFacts.any((fact) => fact.id == part)
        : !_sampleParts.containsKey(part)) {
      throw ArgumentError.value(part, 'part');
    }
    if (!_validPart(task.activityId, part, value)) {
      throw ArgumentError.value(value, 'value');
    }
    if (task.answerParts[part] == value) return this;
    final parts = {...task.answerParts, part: value};
    if (isUpdate &&
        parts.values.where((value) => value == 'included').length > 3) {
      throw StateError('Remove one fact before including another.');
    }
    return _withActive(
      ActivityProgress._(
        activityId: task.activityId,
        stage: 2,
        selectedChoiceId: isUpdate
            ? updateChoiceId(parts)
            : _sampleChoice(parts),
        corrected: false,
        answerParts: parts,
      ),
    );
  }

  OfficeProgress submitChoice(DateTime now) {
    final task = _task;
    // Repeated taps/retries after a successful submission are harmless.
    if (task.stage >= 3) return this;
    if (task.stage != 2 || task.selectedChoiceId == null) {
      throw StateError('Select a decision before submitting.');
    }
    if (_acceptedChoice(task.activityId, task.selectedChoiceId!)) {
      return _complete(task, corrected: false, now: now);
    }
    return _withActive(
      ActivityProgress._(
        activityId: task.activityId,
        stage: 3,
        selectedChoiceId: task.selectedChoiceId,
        corrected: true,
        answerParts: task.answerParts,
      ),
    );
  }

  OfficeProgress acceptCorrection(DateTime now) {
    final task = _task;
    if (task.stage == 4 && task.corrected) return this;
    if (task.stage != 3) throw StateError('There is no correction to accept.');
    return _complete(task, corrected: true, now: now);
  }

  /// Leaving an unfinished activity keeps its exact resume state.
  OfficeProgress closeActivity() =>
      active?.stage == 4 ? OfficeProgress._(completions: completions) : this;

  ActivityProgress get _task =>
      active ?? (throw StateError('No active activity.'));

  OfficeProgress _withActive(ActivityProgress task) =>
      OfficeProgress._(active: task, completions: completions);

  OfficeProgress _complete(
    ActivityProgress task, {
    required bool corrected,
    required DateTime now,
  }) {
    final firstCompletions = Map<String, ActivityCompletion>.of(completions);
    firstCompletions.putIfAbsent(
      task.activityId,
      () => ActivityCompletion._(
        activityId: task.activityId,
        selectedChoiceId: task.selectedChoiceId!,
        corrected: corrected,
        completedAt: now.toUtc(),
        importedFromLegacy: false,
      ),
    );
    return OfficeProgress._(
      active: ActivityProgress._(
        activityId: task.activityId,
        stage: 4,
        selectedChoiceId: task.selectedChoiceId,
        corrected: corrected,
        answerParts: task.answerParts,
      ),
      completions: firstCompletions,
    );
  }

  Map<String, Object?> toJson() => {
    'version': wireVersion,
    'active': active?.toJson(),
    'completions': completions.map(
      (id, completion) => MapEntry(id, completion.toJson()),
    ),
  };

  factory OfficeProgress.fromJson(Map<String, dynamic> data) {
    _fields(data, const {'version', 'active', 'completions'});
    final version = data['version'];
    if (version is! int ||
        version < 1 ||
        version > practiceCatalogPayloadVersion) {
      throw const FormatException('Unsupported progress version.');
    }
    final records = _map(data['completions']);
    if (records.length > OfficeActivityIds.all.length) _invalid();
    final completions = <String, ActivityCompletion>{};
    for (final entry in records.entries) {
      final record = _map(entry.value);
      _fields(record, const {
        'activityId',
        'selectedChoiceId',
        'corrected',
        'completedAt',
        'importedFromLegacy',
      });
      final id = record['activityId'];
      final choice = record['selectedChoiceId'];
      final corrected = record['corrected'];
      final imported = record['importedFromLegacy'];
      if (id is! String ||
          id != entry.key ||
          !_choices.containsKey(id) ||
          practiceCatalogById[id]!.introducedIn > version ||
          choice is! String ||
          !_choices[id]!.contains(choice) ||
          corrected is! bool ||
          corrected == _acceptedChoice(id, choice) ||
          imported is! bool ||
          (imported && id != OfficeActivityIds.checkTheDate)) {
        _invalid();
      }
      final time = record['completedAt'];
      if (time == null && !imported) _invalid();
      completions[id] = ActivityCompletion._(
        activityId: id,
        selectedChoiceId: choice,
        corrected: corrected,
        completedAt: time == null ? null : _time(time),
        importedFromLegacy: imported,
      );
    }
    for (final id in completions.keys) {
      if (!_unlocked(id, completions)) _invalid();
    }
    ActivityProgress? active;
    if (data['active'] != null) {
      final task = _map(data['active']);
      _fields(task, {
        'activityId',
        'stage',
        'selectedChoiceId',
        'corrected',
        if (version >= 2) 'answerParts',
      });
      final id = task['activityId'];
      final stage = task['stage'];
      final choice = task['selectedChoiceId'];
      final corrected = task['corrected'];
      if (id is! String ||
          !_choices.containsKey(id) ||
          practiceCatalogById[id]!.introducedIn > version ||
          stage is! int ||
          stage < 0 ||
          stage > 4 ||
          corrected is! bool ||
          (choice != null &&
              (choice is! String || !_choices[id]!.contains(choice)))) {
        _invalid();
      }
      final parts = <String, String>{};
      if (version >= 2) {
        for (final entry in _map(task['answerParts']).entries) {
          if (entry.value is! String ||
              !_validPart(id, entry.key, entry.value)) {
            _invalid();
          }
          parts[entry.key] = entry.value as String;
        }
      }
      if (id == OfficeActivityIds.checkTheSample) {
        if (choice != _sampleChoice(parts)) _invalid();
      } else if (id == OfficeActivityIds.prepareTheUpdate) {
        if (parts.values.where((value) => value == 'included').length > 3 ||
            choice != updateChoiceId(parts)) {
          _invalid();
        }
      } else if (parts.isNotEmpty) {
        _invalid();
      }
      if ((stage <= 2 && corrected) ||
          (stage >= 3 && choice == null) ||
          (stage == 3 &&
              (!corrected || _acceptedChoice(id, choice as String))) ||
          (stage == 4 &&
              (corrected == _acceptedChoice(id, choice as String) ||
                  !completions.containsKey(id))) ||
          !_unlocked(id, completions)) {
        _invalid();
      }
      active = ActivityProgress._(
        activityId: id,
        stage: stage,
        selectedChoiceId: choice as String?,
        corrected: corrected,
        answerParts: parts,
      );
    }
    return OfficeProgress._(
      active: active,
      completions: completions,
      wireVersion: version >= 3 ? version : 3,
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) _invalid();
  return value;
}

Never _invalid() => throw const FormatException('Invalid saved progress.');

void _fields(Map<String, dynamic> data, Set<String> expected) {
  if (data.length != expected.length || !expected.every(data.containsKey)) {
    _invalid();
  }
}

DateTime _time(Object value) {
  if (value is! String) _invalid();
  final parsed = DateTime.tryParse(value);
  // Reject normalized overflow dates and ambiguous local-time timestamps.
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    _invalid();
  }
  return parsed;
}

enum ProgressLoadIssueKind {
  corruptData,
  unsupportedVersion,
  storageReadFailed,
}

class ProgressLoadIssue {
  const ProgressLoadIssue(this.kind);
  final ProgressLoadIssueKind kind;
}

class ProgressSaveException implements Exception {
  const ProgressSaveException();
  @override
  String toString() => 'Progress could not be saved. Retry the same action.';
}

class ProgressProtectedException implements Exception {
  const ProgressProtectedException();
  @override
  String toString() =>
      'Existing progress is protected until it can be restored.';
}

/// Reads never rewrite data. A corrupt/future primary record blocks all writes,
/// including legacy migration, until [retryLoad] successfully reads valid data.
class OfficeProgressRepository extends ChangeNotifier {
  factory OfficeProgressRepository({
    required String? Function(String key) read,
    required Future<bool> Function(String key, String value) write,
    DateTime Function()? clock,
    Future<void> Function()? refresh,
  }) => OfficeProgressRepository._(read, write, clock ?? DateTime.now, refresh);

  OfficeProgressRepository._(
    this._read,
    this._write,
    this._clock,
    this._refresh,
  ) {
    _load();
  }

  factory OfficeProgressRepository.fromPreferences(
    SharedPreferences preferences,
  ) => OfficeProgressRepository(
    read: preferences.getString,
    write: preferences.setString,
    refresh: preferences.reload,
  );

  static const saveKey = 'trimmy.office-progress.v1';
  static const legacyKey = 'trimmy.office-layout-study.v1';
  static const _maxRecordLength = 32768;
  final String? Function(String) _read;
  final Future<bool> Function(String, String) _write;
  final DateTime Function() _clock;
  final Future<void> Function()? _refresh;
  Future<void> _pending = Future<void>.value();
  OfficeProgress _state = OfficeProgress.empty();
  ProgressLoadIssue? _loadIssue;
  int _localRevision = 0;

  OfficeProgress get state => _state;
  ProgressLoadIssue? get loadIssue => _loadIssue;

  /// Increases only when an acknowledged local transition becomes visible.
  /// Reload notifications never request another upload by themselves.
  int get localRevision => _localRevision;

  /// Wait for transitions already accepted by this repository before retiring
  /// its account session. Closing the session rejects subsequent writes.
  Future<void> get whenIdle => _pending;

  Future<OfficeProgress> startActivity(String activityId) =>
      _save((state) => state.startActivity(activityId));
  Future<OfficeProgress> inspectStage(int next) =>
      _save((state) => state.inspectStage(next));
  Future<OfficeProgress> advance() => _save((state) => state.advance());
  Future<OfficeProgress> selectChoice(String choiceId) =>
      _save((state) => state.selectChoice(choiceId));
  Future<OfficeProgress> selectAnswerPart(String part, String value) =>
      _save((state) => state.selectAnswerPart(part, value));
  Future<OfficeProgress> submitChoice() =>
      _save((state) => state.submitChoice(_clock()));
  Future<OfficeProgress> acceptCorrection() =>
      _save((state) => state.acceptCorrection(_clock()));
  Future<OfficeProgress> closeActivity() =>
      _save((state) => state.closeActivity());

  Future<OfficeProgress> retryLoad() {
    final operation = _pending.then((_) async {
      final before = jsonEncode(_state.toJson());
      final previousIssue = _loadIssue;
      try {
        await _refresh?.call();
      } catch (_) {
        _loadIssue = const ProgressLoadIssue(
          ProgressLoadIssueKind.storageReadFailed,
        );
        notifyListeners();
        return _state;
      }
      _load();
      if (before != jsonEncode(_state.toJson()) ||
          previousIssue != _loadIssue) {
        notifyListeners();
      }
      return _state;
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<OfficeProgress> _save(
    OfficeProgress Function(OfficeProgress) transition,
  ) {
    final operation = _pending.then((_) async {
      if (_loadIssue != null) throw const ProgressProtectedException();
      final next = transition(_state);
      if (identical(next, _state)) return _state;
      try {
        final saved = await _write(saveKey, jsonEncode(next.toJson()));
        if (!saved) throw const ProgressSaveException();
      } catch (_) {
        throw const ProgressSaveException();
      }
      // The outcome and its completion become visible together, after storage.
      _state = next;
      _localRevision++;
      notifyListeners();
      return _state;
    });
    // A failed write must not poison later queued writes or the retry.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _load() {
    String? current;
    String? legacy;
    try {
      current = _read(saveKey);
      if (current == null) legacy = _read(legacyKey);
    } catch (_) {
      _loadIssue = const ProgressLoadIssue(
        ProgressLoadIssueKind.storageReadFailed,
      );
      return;
    }
    try {
      final raw = current ?? legacy;
      if (raw == null) {
        _state = OfficeProgress.empty();
      } else {
        if (raw.length > _maxRecordLength) _invalid();
        final data = _map(jsonDecode(raw));
        final version = data['version'];
        if (version is int &&
            (current != null
                ? version < 1 || version > practiceCatalogPayloadVersion
                : version != 1)) {
          _loadIssue = const ProgressLoadIssue(
            ProgressLoadIssueKind.unsupportedVersion,
          );
          return;
        }
        _state = current != null
            ? OfficeProgress.fromJson(data)
            : _migrateLegacy(data);
      }
      _loadIssue = null;
    } catch (_) {
      _loadIssue = const ProgressLoadIssue(ProgressLoadIssueKind.corruptData);
    }
  }

  OfficeProgress _migrateLegacy(Map<String, dynamic> data) {
    if (data['version'] is! int ||
        data['version'] != 1 ||
        data['completed'] is! bool ||
        data.keys.any(
          (key) => !const {
            'version',
            'completed',
            'neededCorrection',
            'completedAt',
          }.contains(key),
        ) ||
        (data.containsKey('neededCorrection') &&
            data['neededCorrection'] is! bool)) {
      _invalid();
    }
    final time = data['completedAt'] == null
        ? null
        : _time(data['completedAt']);
    if (data['completed'] == false) return OfficeProgress.empty();
    final corrected = data['neededCorrection'] == true;
    return OfficeProgress._(
      completions: {
        OfficeActivityIds.checkTheDate: ActivityCompletion._(
          activityId: OfficeActivityIds.checkTheDate,
          selectedChoiceId: corrected ? 'keep-headline' : 'add-year',
          corrected: corrected,
          completedAt: time,
          importedFromLegacy: true,
        ),
      },
    );
  }
}
