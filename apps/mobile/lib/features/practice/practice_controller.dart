import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/practice_audio.dart';
import '../journey/journey_catalog.dart';
import '../journey/journey_progress.dart';

/// Stores only local practice notes and preferences, never financial state.
abstract interface class PracticeStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesPracticeStore implements PracticeStore {
  SharedPreferencesPracticeStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const key = 'trimmy.practice';
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() => _preferences.getString(key);

  @override
  Future<void> write(String value) => _preferences.setString(key, value);
}

@immutable
class PracticeDraft {
  const PracticeDraft({
    required this.handle,
    required this.message,
    required this.createdAt,
  });

  final String handle;
  final String message;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'handle': handle,
    'message': message,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class PracticeController extends ChangeNotifier {
  PracticeController({
    required this.store,
    PracticeAudio? audio,
    DateTime Function()? clock,
  }) : _audio = audio ?? SilentPracticeAudio(),
       _clock = clock ?? DateTime.now;

  static const schemaVersion = 2;
  static const maxDrafts = 20;
  static final _handlePattern = RegExp(r'^@?[A-Za-z0-9_]{1,15}$');

  final PracticeStore store;
  final PracticeAudio _audio;
  final DateTime Function() _clock;
  Future<void> _writes = Future<void>.value();
  Future<void>? _audioClosing;
  bool _disposed = false;
  bool _storageProtected = false;
  int _tab = 0;
  bool _soundEnabled = false;
  bool _reduceMotion = false;
  bool _hasMetOffice = false;
  int? _selectedChoice;
  String _journalNote = '';
  final List<PracticeDraft> _drafts = [];
  String? _storageWarning;
  JourneySession? _activeSession;
  final Map<String, JourneyCompletion> _chapterCompletions = {};
  final Map<String, String> _activityByChapter = {};

  int get tab => _tab;
  bool get soundEnabled => _soundEnabled;
  bool get reduceMotion => _reduceMotion;
  bool get hasMetOffice => _hasMetOffice;
  int? get selectedChoice => _selectedChoice;
  String get journalNote => _journalNote;
  List<PracticeDraft> get drafts => List.unmodifiable(_drafts);
  String? get storageWarning => _storageWarning;
  bool get briefCompleted => _selectedChoice != null && _journalNote.isNotEmpty;
  JourneySession? get activeSession => _activeSession;
  JourneyStep? get currentJourneyStep {
    final session = _activeSession;
    if (session == null) return null;
    return journeyChapterById(session.chapterId)!.steps[session.stepIndex];
  }

  String? get journeyFeedback {
    final step = currentJourneyStep;
    if (step == null || step.kind != JourneyStepKind.decision) return null;
    final answer = _activeSession!.answers[step.id];
    return answer == null ? null : step.choices[answer].feedback;
  }

  bool get canAdvanceJourney {
    final step = currentJourneyStep;
    return step != null &&
        switch (step.kind) {
          JourneyStepKind.intro => true,
          JourneyStepKind.decision => _activeSession!.answers.containsKey(
            step.id,
          ),
          JourneyStepKind.reflection =>
            _activeSession!.reflection.trim().isNotEmpty,
        };
  }

  Set<String> get completedChapterIds =>
      Set.unmodifiable(_chapterCompletions.keys);
  Map<String, JourneyCompletion> get chapterCompletions =>
      Map.unmodifiable(_chapterCompletions);
  int get learningPoints => _chapterCompletions.length * 30;
  DateTime get currentLocalDate {
    final now = _clock().toLocal();
    return DateTime(now.year, now.month, now.day);
  }

  List<String> get activityDates =>
      List.unmodifiable(_activityByChapter.values.toSet().toList()..sort());
  bool get activeToday => activityDates.contains(localDateKey(_clock()));
  String? get clockWarning {
    final dates = activityDates;
    if (dates.isNotEmpty && localDateKey(_clock()).compareTo(dates.last) < 0) {
      return 'Your local date is earlier than a saved activity date. '
          'Progress is kept; an earlier activity day will not be added.';
    }
    return null;
  }

  int get currentStreak {
    final dates = activityDates;
    if (dates.isEmpty || clockWarning != null) return 0;
    final today = parseDateKey(localDateKey(_clock()))!;
    var cursor = parseDateKey(dates.last)!;
    if (today.difference(cursor).inDays > 1) return 0;
    var count = 0;
    final daySet = dates.toSet();
    while (daySet.contains(cursor.toIso8601String().substring(0, 10))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  int get longestStreak {
    var longest = 0;
    var run = 0;
    DateTime? previous;
    for (final date in activityDates) {
      final day = parseDateKey(date)!;
      run = previous != null && day.difference(previous).inDays == 1
          ? run + 1
          : 1;
      if (run > longest) longest = run;
      previous = day;
    }
    return longest;
  }

  JourneyChapter? get nextChapter {
    for (final chapter in journeyChapters) {
      if (!_chapterCompletions.containsKey(chapter.id)) return chapter;
    }
    return null;
  }

  bool isChapterUnlocked(String id) {
    final index = journeyChapters.indexWhere((chapter) => chapter.id == id);
    return index == 0 ||
        (index > 0 &&
            _chapterCompletions.containsKey(journeyChapters[index - 1].id));
  }

  /// Optional arguments keep persistence and audio independently testable.
  static Future<PracticeController> load({
    PracticeStore? store,
    PracticeAudio? audio,
    DateTime Function()? clock,
  }) async {
    final controller = PracticeController(
      store: store ?? SharedPreferencesPracticeStore(),
      audio: audio ?? LocalPracticeAudio(),
      clock: clock,
    );
    try {
      final raw = await controller.store.read();
      if (raw != null) controller._restore(raw);
    } catch (_) {
      // A failed read must not overwrite data whose version we could not read.
      controller._storageProtected = true;
      controller._storageWarning =
          'Local storage could not be read. Changes will stay in this session. '
          'Reopen the app to retry.';
    }
    controller._audio.setEnabled(controller.soundEnabled);
    return controller;
  }

  void _restore(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      _corruptWarning();
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      _corruptWarning();
      return;
    }
    final version = decoded['version'];
    if (version is int && version > schemaVersion) {
      _storageProtected = true;
      _storageWarning =
          'This device has practice data from a newer app. It has been kept '
          'untouched; changes here will stay in this session.';
      return;
    }
    if (version is! int || version < 1 || version > schemaVersion) {
      _corruptWarning();
      return;
    }

    var repaired = false;
    bool readBool(String key) {
      final value = decoded is Map<String, dynamic> ? decoded[key] : null;
      if (value is bool) return value;
      repaired = true;
      return false;
    }

    _soundEnabled = readBool('soundEnabled');
    _reduceMotion = readBool('reduceMotion');
    _hasMetOffice = readBool('hasMetOffice');
    final savedTab = decoded['tab'];
    if (savedTab is int && savedTab >= 0 && savedTab <= 2) {
      _tab = savedTab;
    } else {
      repaired = true;
    }
    final choice = decoded['selectedChoice'];
    final note = decoded['journalNote'];
    final validChoice = choice is int && choice >= 0 && choice <= 2;
    final validNote = note is String && note.characters.length <= 500;
    // The choice and note are one record; do not attach a note to a default pick.
    if (validChoice && validNote && note.trim().isNotEmpty) {
      _selectedChoice = choice;
      _journalNote = note.trim();
    } else if (choice != null || note != '') {
      repaired = true;
    }

    final savedDrafts = decoded['drafts'];
    if (savedDrafts is List) {
      for (final item in savedDrafts) {
        if (item is! Map<String, dynamic>) {
          repaired = true;
          continue;
        }
        final handle = item['handle'];
        final message = item['message'];
        final createdAt = item['createdAt'];
        final date = createdAt is String ? DateTime.tryParse(createdAt) : null;
        if (handle is! String ||
            !_handlePattern.hasMatch(handle) ||
            message is! String ||
            message.trim().isEmpty ||
            message.characters.length > 500 ||
            date == null) {
          repaired = true;
          continue;
        }
        _drafts.add(
          PracticeDraft(
            handle: handle.startsWith('@') ? handle : '@$handle',
            message: message.trim(),
            createdAt: date.toUtc(),
          ),
        );
      }
      if (_drafts.length > maxDrafts) {
        _drafts.removeRange(0, _drafts.length - maxDrafts);
        repaired = true;
      }
    } else {
      repaired = true;
    }
    if (version == 2) {
      final restored = restoreJourneyProgress(decoded['journey']);
      _activeSession = restored.session;
      _chapterCompletions.addAll(restored.completions);
      _activityByChapter.addAll(restored.activityByChapter);
      repaired = repaired || restored.repaired;
    }
    // Schema 1 has no journey credits; reading it never invents completions.
    if (repaired) _corruptWarning();
  }

  void _corruptWarning() {
    _storageWarning =
        'Some local practice data could not be restored. Valid notes and '
        'settings were kept; your next save will store the current session.';
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('The practice controller is closed.');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setTab(int value) {
    _ensureOpen();
    if (value < 0 || value > 2) throw RangeError.range(value, 0, 2, 'tab');
    if (_tab == value) return;
    _tab = value;
    _notify();
    unawaited(_save());
  }

  Future<void> setSound(bool enabled) {
    _ensureOpen();
    _soundEnabled = enabled;
    // Set synchronously while still inside the user's gesture on web.
    _audio.setEnabled(enabled);
    _notify();
    return _save();
  }

  Future<void> setReduceMotion(bool enabled) {
    _ensureOpen();
    _reduceMotion = enabled;
    _notify();
    return _save();
  }

  Future<void> meetOffice() {
    _ensureOpen();
    _hasMetOffice = true;
    _notify();
    return _save();
  }

  Future<void> saveBrief({required int choice, required String note}) {
    _ensureOpen();
    if (choice < 0 || choice > 2) {
      throw RangeError.range(choice, 0, 2, 'choice');
    }
    final clean = note.trim();
    if (clean.isEmpty || note.characters.length > 500) {
      throw ArgumentError.value(note, 'note', 'Use 1 to 500 characters.');
    }
    _selectedChoice = choice;
    _journalNote = clean;
    _notify();
    return _save();
  }

  Future<void> saveDraft({required String handle, required String message}) {
    _ensureOpen();
    final cleanHandle = handle.trim();
    final cleanMessage = message.trim();
    if (!_handlePattern.hasMatch(cleanHandle)) {
      throw ArgumentError.value(handle, 'handle', 'Use a valid X handle.');
    }
    if (cleanMessage.isEmpty || message.characters.length > 500) {
      throw ArgumentError.value(message, 'message', 'Use 1 to 500 characters.');
    }
    if (_drafts.length >= maxDrafts) {
      throw StateError('The 20-draft limit has been reached.');
    }
    _drafts.add(
      PracticeDraft(
        handle: cleanHandle.startsWith('@') ? cleanHandle : '@$cleanHandle',
        message: cleanMessage,
        createdAt: _clock().toUtc(),
      ),
    );
    _notify();
    return _save();
  }

  Future<void> clearPractice() {
    _ensureOpen();
    _tab = 0;
    _hasMetOffice = false;
    _selectedChoice = null;
    _journalNote = '';
    _drafts.clear();
    _activeSession = null;
    _chapterCompletions.clear();
    _activityByChapter.clear();
    _notify();
    return _save();
  }

  void cue(String filename) {
    if (!_disposed && _soundEnabled) _audio.cue(filename);
  }

  Future<void> startJourney([String chapterId = 'first-floor']) {
    _ensureOpen();
    if (journeyChapterById(chapterId) == null) {
      throw ArgumentError.value(chapterId, 'chapterId', 'Unknown chapter.');
    }
    if (!isChapterUnlocked(chapterId)) {
      throw StateError('Complete the preceding chapter first.');
    }
    if (_activeSession != null) {
      if (_activeSession!.chapterId == chapterId) return Future<void>.value();
      throw StateError('Finish or explicitly reset the current session first.');
    }
    _activeSession = JourneySession(chapterId: chapterId);
    _notify();
    return _save();
  }

  Future<void> answerJourney(int choice) {
    _ensureOpen();
    final step = currentJourneyStep;
    if (step == null || step.kind != JourneyStepKind.decision) {
      throw StateError('There is no current decision to answer.');
    }
    if (choice < 0 || choice >= step.choices.length) {
      throw RangeError.range(choice, 0, step.choices.length - 1, 'choice');
    }
    _activeSession = _activeSession!.copyWith(
      answers: {..._activeSession!.answers, step.id: choice},
    );
    _notify();
    return _save();
  }

  Future<void> advanceJourney() {
    _ensureOpen();
    final step = currentJourneyStep;
    if (step == null || !canAdvanceJourney) {
      throw StateError('Read the current step and answer its question first.');
    }
    if (step.kind == JourneyStepKind.reflection) {
      throw StateError('Complete the reflection to finish this chapter.');
    }
    _activeSession = _activeSession!.copyWith(
      stepIndex: _activeSession!.stepIndex + 1,
    );
    _notify();
    return _save();
  }

  Future<void> updateJourneyReflection(String value) {
    _ensureOpen();
    if (currentJourneyStep?.kind != JourneyStepKind.reflection) {
      throw StateError('Reach the reflection step first.');
    }
    if (value.characters.length > 500) {
      throw ArgumentError('Use at most 500 characters for a reflection.');
    }
    // Keep even an unfinished/empty draft so leaving the screen is reversible.
    _activeSession = _activeSession!.copyWith(reflection: value);
    _notify();
    return _save();
  }

  Future<void> completeJourney() {
    _ensureOpen();
    final session = _activeSession;
    if (session == null) {
      return Future<void>.value(); // Repeated button callback.
    }
    final chapter = journeyChapterById(session.chapterId)!;
    final hasAnswers = chapter.steps
        .where((step) => step.kind == JourneyStepKind.decision)
        .every((step) => session.answers.containsKey(step.id));
    if (session.stepIndex != chapter.steps.length - 1 ||
        !hasAnswers ||
        session.reflection.trim().isEmpty) {
      throw StateError('Complete each step and leave a reflection first.');
    }
    final previous = _chapterCompletions[chapter.id];
    final now = _clock();
    final day = localDateKey(now);
    final dates = activityDates;
    if (previous == null && (dates.isEmpty || day.compareTo(dates.last) >= 0)) {
      _activityByChapter[chapter.id] = day;
    }
    _chapterCompletions[chapter.id] = JourneyCompletion(
      chapterId: chapter.id,
      reflection: session.reflection.trim(),
      completedAt: previous?.completedAt ?? now.toUtc(),
    );
    _activeSession = null;
    _notify();
    return _save();
  }

  Future<void> resetJourneySession() {
    _ensureOpen();
    _activeSession = null;
    _notify();
    return _save();
  }

  /// Wait for writes already queued, without closing the controller or mutating it.
  Future<void> flushPendingWrites() => _writes;

  Future<void> _save() {
    if (_storageProtected) return Future<void>.value();
    // Capture this mutation before queueing; later edits cannot alter its bytes.
    final snapshot = jsonEncode({
      'version': schemaVersion,
      'tab': _tab,
      'soundEnabled': _soundEnabled,
      'reduceMotion': _reduceMotion,
      'hasMetOffice': _hasMetOffice,
      'selectedChoice': _selectedChoice,
      'journalNote': _journalNote,
      'drafts': _drafts.map((draft) => draft.toJson()).toList(),
      'journey': {
        'session': _activeSession?.toJson(),
        'completions': _chapterCompletions.values
            .map((entry) => entry.toJson())
            .toList(),
        'activityByChapter': _activityByChapter,
      },
    });
    _writes = _writes.then((_) async {
      try {
        await store.write(snapshot);
        _storageWarning = null;
      } catch (_) {
        _storageWarning =
            'Your changes are available in this session, but could not be '
            'saved on this device. The next change will retry.';
      }
      _notify();
    });
    return _writes;
  }

  /// Flushes queued writes and releases audio; useful for explicit app teardown.
  Future<void> close() async {
    if (!_disposed) dispose();
    await _writes;
    await _audioClosing;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _audioClosing = _audio.close();
    unawaited(_audioClosing);
    super.dispose();
  }
}
