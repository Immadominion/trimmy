import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/coordinator.dart';
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/practice_sync/protocol.dart';

const account = '00000000-0000-4000-8000-000000000001';
const otherAccount = '00000000-0000-4000-8000-000000000002';
const first = OfficeActivityIds.checkTheDate;
final now = DateTime.utc(2026, 9, 14, 20, 30);

Matcher code(String expected) =>
    isA<PracticeSyncException>().having((e) => e.code, 'code', expected);
OfficeProgress started() => OfficeProgress.empty().startActivity(first);
OfficeProgress completed({bool corrected = false}) {
  final submitted = started()
      .advance()
      .advance()
      .selectChoice(corrected ? 'keep-headline' : 'add-year')
      .submitChoice(now);
  return (corrected ? submitted.acceptCorrection(now) : submitted)
      .closeActivity();
}

PracticeSnapshot snapshot(int revision, OfficeProgress progress) =>
    PracticeSnapshot(revision: revision, progress: progress, updatedAt: now);
PracticeSnapshot emptyServer() =>
    PracticeSnapshot(revision: 0, progress: null, updatedAt: null);

class _Store implements PracticeSyncStore {
  final values = <String, String>{};
  final reads = <String>[];
  final writes = <(String, String)>[];
  bool failRead = false, failNextWrite = false, throwNextWrite = false;
  Completer<bool>? nextWrite;

  @override
  Future<String?> read(String key) async {
    reads.add(key);
    if (failRead) throw StateError('Unavailable disk');
    return values[key];
  }

  @override
  Future<bool> write(String key, String value) async {
    writes.add((key, value));
    final gate = nextWrite;
    nextWrite = null;
    if (gate != null && !await gate.future) return false;
    if (failNextWrite) {
      failNextWrite = false;
      return false;
    }
    if (throwNextWrite) {
      throwNextWrite = false;
      throw StateError('Unavailable disk');
    }
    values[key] = value;
    return true;
  }

  PracticeSyncState saved([String id = account]) => PracticeSyncState.decode(
    values[PracticeSyncCoordinator.storageKeyFor(id)]!,
    accountId: id,
  );
}

class _Server implements PracticeTransport {
  _Server({this.accountId = account, PracticeSnapshot? initial})
    : current = initial ?? emptyServer();
  @override
  final String accountId;
  PracticeSnapshot current;
  int gets = 0;
  final puts = <PracticeMutation>[];
  final receipts = <String, (String, PracticeSnapshot)>{};
  Future<PracticeSnapshot> Function()? getOverride;
  Future<PracticeSnapshot> Function(PracticeMutation)? putOverride;

  @override
  Future<PracticeSnapshot> getProgress() async {
    gets++;
    return getOverride == null ? current : await getOverride!();
  }

  @override
  Future<PracticeSnapshot> putProgress(PracticeMutation mutation) async {
    puts.add(mutation);
    return putOverride == null
        ? commit(mutation)
        : await putOverride!(mutation);
  }

  PracticeSnapshot commit(PracticeMutation mutation) {
    final body =
        '${mutation.baseRevision}:${canonicalProgress(mutation.progress)}';
    final receipt = receipts[mutation.mutationId];
    if (receipt != null) {
      if (receipt.$1 != body) {
        throw const PracticeSyncException('PRACTICE_IDEMPOTENCY_CONFLICT');
      }
      return receipt.$2;
    }
    if (mutation.baseRevision != current.revision) {
      throw PracticeRevisionConflict(current);
    }
    if (current.progress != null) {
      assertPracticeHistoryPreserved(current.progress!, mutation.progress);
    }
    current = snapshot(current.revision + 1, mutation.progress);
    receipts[mutation.mutationId] = (body, current);
    return current;
  }
}

int _nextUuid = 0;
String _uuid() =>
    '10000000-0000-4000-8000-${(++_nextUuid).toString().padLeft(12, '0')}';
PracticeSyncCoordinator _coordinator(_Store store, _Server server) =>
    PracticeSyncCoordinator(
      accountId: server.accountId,
      store: store,
      transport: server,
      mutationId: _uuid,
    );
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'new account persists its explicit initial copy; existing and repeated loads never re-import',
    () async {
      final store = _Store();
      final server = _Server();
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: started());
      expect(sync.loadIssue, isNull);
      expect(store.saved().local.active!.stage, 0);
      expect(store.saved().base, isNull);
      await sync.saveLocal(sync.localProgress.advance());
      final before = store.values[sync.storageKey];
      await sync.load(initialProgress: completed(corrected: true));
      expect(store.values[sync.storageKey], before);
      expect(sync.localProgress.active!.stage, 1);
      final restart = _coordinator(store, server);
      await restart.load(initialProgress: completed(corrected: true));
      expect(restart.localProgress.active!.stage, 1);
      expect(restart.localProgress.completions, isEmpty);
      expect(server.gets, 0);
    },
  );

  test(
    'failed first persistence or storage reads expose no initialized progress and can retry',
    () async {
      final store = _Store()..failRead = true;
      final sync = _coordinator(store, _Server());
      await sync.load(initialProgress: started());
      expect(sync.loadIssue, PracticeSyncLoadIssue.storageReadFailed);
      expect(sync.state, isNull);
      expect(
        () => sync.localProgress,
        throwsA(code('PRACTICE_LOCAL_UNAVAILABLE')),
      );
      store.failRead = false;
      store.failNextWrite = true;
      await sync.load(initialProgress: started());
      expect(sync.loadIssue, PracticeSyncLoadIssue.storageWriteFailed);
      expect(sync.state, isNull);
      expect(store.values, isEmpty);
      await sync.load(initialProgress: started());
      expect(sync.loadIssue, isNull);
      expect(sync.localProgress.active!.stage, 0);
    },
  );

  test(
    'malformed, future and wrong-account records stay protected without rewriting bytes',
    () async {
      final valid = PracticeSyncState(
        accountId: account,
        local: started(),
        base: null,
        pending: null,
        conflict: null,
      ).toJson();
      final malformed = <(String, PracticeSyncLoadIssue)>[
        ('{broken', PracticeSyncLoadIssue.corruptState),
        (
          jsonEncode({...valid, 'schemaVersion': 2}),
          PracticeSyncLoadIssue.unsupportedVersion,
        ),
        (
          jsonEncode({...valid, 'schemaVersion': 1.0}),
          PracticeSyncLoadIssue.corruptState,
        ),
        (
          jsonEncode({...valid, 'extra': true}),
          PracticeSyncLoadIssue.corruptState,
        ),
        (
          jsonEncode({...valid, 'accountId': otherAccount}),
          PracticeSyncLoadIssue.accountMismatch,
        ),
        (
          jsonEncode({
            ...valid,
            'local': {...started().toJson(), 'version': 7},
          }),
          PracticeSyncLoadIssue.unsupportedVersion,
        ),
        (
          'x' * (PracticeSyncState.maxBytes + 1),
          PracticeSyncLoadIssue.corruptState,
        ),
        for (final field in ['base', 'pending', 'conflict']) ...[
          (
            jsonEncode({
              ...valid,
              field: {...snapshot(1, started()).toJson(), 'schemaVersion': 2},
            }),
            PracticeSyncLoadIssue.unsupportedVersion,
          ),
          (
            jsonEncode({
              ...valid,
              field: {
                ...snapshot(1, started()).toJson(),
                'progress': {...started().toJson(), 'version': 7},
              },
            }),
            PracticeSyncLoadIssue.unsupportedVersion,
          ),
        ],
      ];
      for (final (raw, issue) in malformed) {
        final store = _Store()
          ..values[PracticeSyncCoordinator.storageKeyFor(account)] = raw;
        final server = _Server();
        final sync = _coordinator(store, server);
        await sync.load(initialProgress: completed());
        expect(sync.loadIssue, issue);
        expect(sync.state, isNull);
        await expectLater(
          sync.saveLocal(started()),
          throwsA(code('PRACTICE_LOCAL_UNAVAILABLE')),
        );
        await expectLater(
          sync.synchronize(),
          throwsA(code('PRACTICE_LOCAL_UNAVAILABLE')),
        );
        expect(store.values[sync.storageKey], raw);
        expect(store.writes, isEmpty);
        expect(server.gets, 0);
      }
    },
  );

  test(
    'local updates become visible only after storage acknowledgment and preserve first answers',
    () async {
      final store = _Store();
      final sync = _coordinator(store, _Server());
      await sync.load(initialProgress: started());
      final gate = Completer<bool>();
      store.nextWrite = gate;
      final save = sync.saveLocal(sync.localProgress.advance());
      await _flush();
      expect(sync.localProgress.active!.stage, 0);
      expect(store.saved().local.active!.stage, 0);
      gate.complete(true);
      await save;
      expect(sync.localProgress.active!.stage, 1);
      store.failNextWrite = true;
      await expectLater(
        sync.saveLocal(sync.localProgress.advance()),
        throwsA(code('PRACTICE_LOCAL_SAVE_FAILED')),
      );
      expect(sync.localProgress.active!.stage, 1);
      await sync.saveLocal(completed());
      final before = store.values[sync.storageKey];
      await expectLater(
        sync.saveLocal(completed(corrected: true)),
        throwsA(code('PRACTICE_HISTORY_CONFLICT')),
      );
      await expectLater(
        sync.saveLocal(OfficeProgress.empty()),
        throwsA(code('PRACTICE_HISTORY_CONFLICT')),
      );
      expect(store.values[sync.storageKey], before);
    },
  );

  test(
    'a stale expected local draft is rejected after an earlier held disk write acknowledges',
    () async {
      final store = _Store();
      final sync = _coordinator(store, _Server());
      await sync.load(initialProgress: started());
      final previous = sync.localProgress;
      final disk = Completer<bool>();
      store.nextWrite = disk;
      final firstSave = sync.saveLocal(
        previous.advance().advance().selectChoice('add-year'),
        expectedLocal: previous,
      );
      await _flush();
      final staleSave = expectLater(
        sync.saveLocal(previous.advance(), expectedLocal: previous),
        throwsA(code('PRACTICE_LOCAL_CHANGED')),
      );
      final writesBeforeAcknowledgment = store.writes.length;
      expect(sync.localProgress.active!.stage, 0);
      disk.complete(true);
      await firstSave;
      await staleSave;
      expect(store.writes.length, writesBeforeAcknowledgment);
      expect(store.saved().local.active!.stage, 2);
      expect(store.saved().local.active!.selectedChoiceId, 'add-year');
      final current = sync.localProgress;
      await sync.saveLocal(
        current.submitChoice(now),
        expectedLocal: OfficeProgress.fromJson(current.toJson()),
      );
      expect(
        store.saved().local.completions[first]!.selectedChoiceId,
        'add-year',
      );
    },
  );

  test(
    'a conflict decision based on a stale draft cannot replace an acknowledged local edit',
    () async {
      final store = _Store();
      final server = _Server(initial: snapshot(1, started().advance()));
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: started());
      await expectLater(sync.synchronize(), throwsA(code('PRACTICE_CONFLICT')));
      final previous = sync.localProgress;
      final disk = Completer<bool>();
      store.nextWrite = disk;
      final edit = sync.saveLocal(previous.advance().advance());
      await _flush();
      final staleResolution = expectLater(
        sync.resolveConflict(server.current.progress!, expectedLocal: previous),
        throwsA(code('PRACTICE_LOCAL_CHANGED')),
      );
      final writesBeforeAcknowledgment = store.writes.length;
      disk.complete(true);
      await edit;
      await staleResolution;
      expect(store.writes.length, writesBeforeAcknowledgment);
      expect(store.saved().local.active!.stage, 2);
      expect(store.saved().conflict!.progress!.active!.stage, 1);
      await sync.resolveConflict(
        sync.localProgress,
        expectedLocal: OfficeProgress.fromJson(sync.localProgress.toJson()),
      );
      expect(store.saved().conflict, isNull);
      expect(store.saved().local.active!.stage, 2);
      expect(store.saved().base!.revision, 1);
    },
  );

  test(
    'empty local restores remote and equal current snapshots acknowledge without a PUT',
    () async {
      final store = _Store();
      final server = _Server(initial: snapshot(7, completed()));
      final sync = _coordinator(store, server);
      await sync.load();
      await sync.synchronize();
      expect(
        canonicalProgress(sync.localProgress),
        canonicalProgress(completed()),
      );
      expect(store.saved().base!.revision, 7);
      expect(server.puts, isEmpty);
      final writes = store.writes.length;
      await sync.synchronize();
      expect(store.writes.length, writes);
      expect(server.puts, isEmpty);
    },
  );

  test(
    'unchanged local follows a newer remote while dirty local uses the last acknowledged base',
    () async {
      final store = _Store();
      final server = _Server(initial: snapshot(1, started()));
      final sync = _coordinator(store, server);
      await sync.load();
      await sync.synchronize();
      server.current = snapshot(2, started().advance());
      await sync.synchronize();
      expect(sync.localProgress.active!.stage, 1);
      expect(sync.state!.base!.revision, 2);
      await sync.saveLocal(sync.localProgress.advance());
      await sync.synchronize();
      expect(server.puts.single.baseRevision, 2);
      expect(server.puts.single.progress.active!.stage, 2);
      expect(sync.state!.base!.revision, 3);
      expect(sync.state!.pending, isNull);
    },
  );

  test(
    'local edits during GET are compared at response time instead of being overwritten',
    () async {
      final store = _Store();
      final server = _Server();
      final read = Completer<PracticeSnapshot>();
      server.getOverride = () => read.future;
      final sync = _coordinator(store, server);
      await sync.load();
      final run = sync.synchronize();
      final failed = expectLater(run, throwsA(code('PRACTICE_CONFLICT')));
      await _flush();
      await sync.saveLocal(started());
      read.complete(snapshot(1, completed()));
      await failed;
      expect(sync.localProgress.active!.stage, 0);
      expect(sync.localProgress.completions, isEmpty);
      expect(store.saved().conflict!.progress!.completions, hasLength(1));
      expect(server.puts, isEmpty);
    },
  );

  test(
    'pending intent must reach disk before PUT; a rejected write cannot start the upload',
    () async {
      final store = _Store();
      final server = _Server();
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: started());
      final disk = Completer<bool>();
      store.nextWrite = disk;
      final run = sync.synchronize();
      final failure = expectLater(
        run,
        throwsA(code('PRACTICE_LOCAL_SAVE_FAILED')),
      );
      await _flush();
      expect(server.gets, 1);
      expect(server.puts, isEmpty);
      expect(sync.state!.pending, isNull);
      expect(store.saved().pending, isNull);
      disk.complete(false);
      await failure;
      expect(server.puts, isEmpty);
      expect(store.saved().pending, isNull);
      await sync.synchronize();
      expect(server.puts, hasLength(1));
      expect(sync.state!.base!.revision, 1);
    },
  );

  test(
    'network loss before commit keeps one identical pending mutation across restart',
    () async {
      final store = _Store();
      final server = _Server();
      server.putOverride = (_) async =>
          throw const PracticeSyncException('PRACTICE_NETWORK_ERROR');
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: started());
      await expectLater(
        sync.synchronize(),
        throwsA(code('PRACTICE_NETWORK_ERROR')),
      );
      final intent = store.saved().pending!;
      expect(server.current.revision, 0);
      final restart = _coordinator(store, server);
      await restart.load();
      server.putOverride = null;
      await restart.synchronize();
      expect(
        server.gets,
        1,
        reason: 'A pending retry must not perform an intervening GET.',
      );
      expect(server.puts.map((value) => jsonEncode(value.toJson())), [
        jsonEncode(intent.toJson()),
        jsonEncode(intent.toJson()),
      ]);
      expect(store.saved().pending, isNull);
      expect(store.saved().base!.revision, 1);
    },
  );

  test(
    'lost response after commit retries the receipt without committing twice',
    () async {
      final store = _Store();
      final server = _Server();
      server.putOverride = (mutation) async {
        server.commit(mutation);
        throw const PracticeSyncException('PRACTICE_TIMEOUT');
      };
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: completed());
      await expectLater(sync.synchronize(), throwsA(code('PRACTICE_TIMEOUT')));
      expect(server.current.revision, 1);
      final originalId = store.saved().pending!.mutationId;
      final restart = _coordinator(store, server);
      await restart.load();
      server.putOverride = null;
      await restart.synchronize();
      expect(server.current.revision, 1);
      expect(server.puts.last.mutationId, originalId);
      expect(restart.state!.base!.revision, 1);
      expect(restart.state!.pending, isNull);
    },
  );

  test(
    'storage failure after server commit preserves pending intent for an exact retry',
    () async {
      final store = _Store();
      final server = _Server();
      server.putOverride = (mutation) async {
        final result = server.commit(mutation);
        store.failNextWrite = true;
        return result;
      };
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: completed());
      await expectLater(
        sync.synchronize(),
        throwsA(code('PRACTICE_LOCAL_SAVE_FAILED')),
      );
      final before = store.saved().pending!;
      expect(sync.state!.base!.revision, 0);
      expect(server.current.revision, 1);
      final restart = _coordinator(store, server);
      await restart.load();
      server.putOverride = null;
      await restart.synchronize();
      expect(server.puts.last.mutationId, before.mutationId);
      expect(server.current.revision, 1);
      expect(store.saved().base!.revision, 1);
      expect(store.saved().pending, isNull);
    },
  );

  test(
    'edits during held PUT stay local and one cycle cannot send a second mutation',
    () async {
      final store = _Store();
      final server = _Server();
      final network = Completer<PracticeSnapshot>();
      server.putOverride = (_) => network.future;
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: started());
      final run = sync.synchronize();
      expect(identical(sync.synchronize(), run), isTrue);
      await _flush();
      expect(store.saved().pending, isNotNull);
      final sent = server.puts.single;
      await sync.saveLocal(sync.localProgress.advance());
      expect(sync.localProgress.active!.stage, 1);
      expect(store.saved().pending!.progress.active!.stage, 0);
      await sync.load(initialProgress: completed());
      expect(
        sync.localProgress.active!.stage,
        1,
        reason: 'A late load cannot replace initialized state.',
      );
      network.complete(server.commit(sent));
      await run;
      expect(sync.localProgress.active!.stage, 1);
      expect(sync.state!.base!.progress!.active!.stage, 0);
      expect(server.puts, hasLength(1));
      server.putOverride = null;
      await sync.synchronize();
      expect(
        server.gets,
        2,
        reason: 'A new mutation must fetch the server after the old ACK.',
      );
      expect(server.puts, hasLength(2));
      expect(server.puts.last.mutationId, isNot(sent.mutationId));
      expect(server.puts.last.baseRevision, 1);
      expect(server.current.progress!.active!.stage, 1);
    },
  );

  test(
    'historical receipt cannot overwrite newer local data or skip the next server comparison',
    () async {
      final store = _Store();
      final server = _Server();
      server.putOverride = (mutation) async {
        server.commit(mutation);
        throw const PracticeSyncException('PRACTICE_NETWORK_ERROR');
      };
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: started());
      await expectLater(
        sync.synchronize(),
        throwsA(code('PRACTICE_NETWORK_ERROR')),
      );
      await sync.saveLocal(started().advance());
      server.current = snapshot(2, completed());
      final restart = _coordinator(store, server);
      await restart.load();
      server.putOverride = null;
      await restart.synchronize();
      expect(restart.localProgress.active!.stage, 1);
      expect(restart.state!.base!.revision, 1);
      expect(server.current.revision, 2);
      await expectLater(
        restart.synchronize(),
        throwsA(code('PRACTICE_CONFLICT')),
      );
      expect(store.saved().conflict!.revision, 2);
      expect(restart.localProgress.active!.stage, 1);
      expect(server.puts, hasLength(2));
    },
  );

  test(
    '401 and malformed acknowledgments preserve the persisted mutation unchanged',
    () async {
      final store = _Store();
      final server = _Server();
      server.putOverride = (_) async =>
          throw const PracticeSyncException('PRACTICE_UNAUTHENTICATED');
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: started());
      await expectLater(
        sync.synchronize(),
        throwsA(code('PRACTICE_UNAUTHENTICATED')),
      );
      final before = store.values[sync.storageKey];
      for (final response in [
        snapshot(2, started()),
        snapshot(1, completed()),
      ]) {
        server.putOverride = (_) async => response;
        await expectLater(
          sync.synchronize(),
          throwsA(code('PRACTICE_ACK_MISMATCH')),
        );
        expect(store.values[sync.storageKey], before);
      }
      server.putOverride = null;
      await sync.synchronize();
      expect(sync.state!.pending, isNull);
      expect(
        server.puts.map((value) => value.mutationId).toSet(),
        hasLength(1),
      );
    },
  );

  test(
    'divergent copies keep both sides on disk and block sync until explicit reconciliation',
    () async {
      final store = _Store();
      final server = _Server(initial: snapshot(3, started().advance()));
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: started());
      await expectLater(sync.synchronize(), throwsA(code('PRACTICE_CONFLICT')));
      expect(store.saved().local.active!.stage, 0);
      expect(store.saved().conflict!.progress!.active!.stage, 1);
      await sync.saveLocal(started().advance().advance());
      expect(store.saved().conflict!.revision, 3);
      final restart = _coordinator(store, server);
      await restart.load();
      await expectLater(
        restart.synchronize(),
        throwsA(code('PRACTICE_CONFLICT')),
      );
      expect(server.gets, 1);
      final reconciled = restart.localProgress.selectChoice('add-year');
      await restart.resolveConflict(reconciled);
      expect(store.saved().conflict, isNull);
      expect(store.saved().base!.revision, 3);
      await restart.synchronize();
      expect(server.puts.single.baseRevision, 3);
      expect(server.current.progress!.active!.selectedChoiceId, 'add-year');
    },
  );

  test(
    '409 clears only the rejected intent and reconciliation must preserve both first histories',
    () async {
      final store = _Store();
      final server = _Server();
      server.putOverride = (_) async {
        server.current = snapshot(1, completed(corrected: true));
        throw PracticeRevisionConflict(server.current);
      };
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: completed());
      await expectLater(
        sync.synchronize(),
        throwsA(isA<PracticeRevisionConflict>()),
      );
      final conflicted = store.values[sync.storageKey];
      expect(store.saved().pending, isNull);
      expect(store.saved().conflict!.revision, 1);
      await expectLater(
        sync.resolveConflict(completed()),
        throwsA(code('PRACTICE_HISTORY_CONFLICT')),
      );
      await expectLater(
        sync.resolveConflict(completed(corrected: true)),
        throwsA(code('PRACTICE_HISTORY_CONFLICT')),
      );
      expect(store.values[sync.storageKey], conflicted);
      expect(sync.localProgress.completions[first]!.corrected, isFalse);
      expect(
        sync.state!.conflict!.progress!.completions[first]!.corrected,
        isTrue,
      );
    },
  );

  test(
    'failed conflict persistence leaves the rejected pending request retryable',
    () async {
      final store = _Store();
      final server = _Server();
      server.putOverride = (_) async {
        store.failNextWrite = true;
        throw PracticeRevisionConflict(snapshot(1, completed()));
      };
      final sync = _coordinator(store, server);
      await sync.load(initialProgress: started());
      await expectLater(
        sync.synchronize(),
        throwsA(code('PRACTICE_LOCAL_SAVE_FAILED')),
      );
      expect(store.saved().pending, isNotNull);
      expect(store.saved().conflict, isNull);
      final pending = store.saved().pending!.mutationId;
      server.putOverride = (_) async =>
          throw PracticeRevisionConflict(snapshot(1, completed()));
      await expectLater(
        sync.synchronize(),
        throwsA(isA<PracticeRevisionConflict>()),
      );
      expect(server.puts.last.mutationId, pending);
      expect(store.saved().pending, isNull);
      expect(store.saved().conflict, isNotNull);
    },
  );

  test(
    'remote regressions or changed first answers cannot silently replace a known baseline',
    () async {
      for (final remote in [
        snapshot(1, completed()),
        snapshot(3, completed(corrected: true)),
      ]) {
        final store = _Store();
        final server = _Server(initial: snapshot(2, completed()));
        final sync = _coordinator(store, server);
        await sync.load();
        await sync.synchronize();
        server.current = remote;
        await expectLater(
          sync.synchronize(),
          throwsA(code('PRACTICE_CONFLICT')),
        );
        expect(sync.state!.base!.revision, 2);
        expect(sync.localProgress.completions[first]!.corrected, isFalse);
        expect(sync.state!.conflict!.revision, remote.revision);
        expect(server.puts, isEmpty);
      }
    },
  );

  test(
    'a known revision cannot acquire different content or a different server timestamp',
    () async {
      for (final dirty in [false, true]) {
        final store = _Store();
        final server = _Server(initial: snapshot(2, started()));
        final sync = _coordinator(store, server);
        await sync.load();
        await sync.synchronize();
        if (dirty) await sync.saveLocal(started().advance());
        server.current = snapshot(2, started().advance());
        await expectLater(
          sync.synchronize(),
          throwsA(code('PRACTICE_CONFLICT')),
        );
        expect(sync.state!.base!.progress!.active!.stage, 0);
        expect(sync.localProgress.active!.stage, dirty ? 1 : 0);
        expect(store.saved().conflict!.progress!.active!.stage, 1);
        expect(server.puts, isEmpty);
      }
      final store = _Store();
      final server = _Server(initial: snapshot(2, started()));
      final sync = _coordinator(store, server);
      await sync.load();
      await sync.synchronize();
      server.current = PracticeSnapshot(
        revision: 2,
        progress: started(),
        updatedAt: now.add(const Duration(milliseconds: 1)),
      );
      await expectLater(sync.synchronize(), throwsA(code('PRACTICE_CONFLICT')));
      expect(sync.state!.base!.updatedAt, now);
      expect(store.saved().conflict!.updatedAt, server.current.updatedAt);
      expect(server.puts, isEmpty);
    },
  );

  test(
    'account-specific disk and transport bindings never share pending uploads',
    () async {
      final store = _Store();
      final a = _Server();
      final b = _Server(accountId: otherAccount);
      final firstSync = _coordinator(store, a);
      final secondSync = _coordinator(store, b);
      await firstSync.load(initialProgress: completed());
      await secondSync.load();
      await firstSync.synchronize();
      await secondSync.synchronize();
      expect(a.puts.single.progress.completions, hasLength(1));
      expect(b.puts, isEmpty);
      expect(store.saved(otherAccount).local.completions, isEmpty);
      expect(store.values.keys.toSet(), {
        firstSync.storageKey,
        secondSync.storageKey,
      });
      expect(store.reads, [firstSync.storageKey, secondSync.storageKey]);
      expect(
        () => PracticeSyncCoordinator(
          accountId: account,
          store: store,
          transport: b,
          mutationId: _uuid,
        ),
        throwsA(code('PRACTICE_ACCOUNT_MISMATCH')),
      );
      expect(jsonDecode(store.values[firstSync.storageKey]!).keys.toSet(), {
        'schemaVersion',
        'accountId',
        'local',
        'base',
        'pending',
        'conflict',
      });
    },
  );

  test(
    'malformed account aliases cannot select a storage key or initialize a session',
    () {
      final store = _Store();
      final server = _Server();
      for (final malformed in ['$account\n', '$account\r\n', ' $account']) {
        expect(
          () => PracticeSyncCoordinator.storageKeyFor(malformed),
          throwsA(code('PRACTICE_INVALID_ACCOUNT')),
        );
        expect(
          () => PracticeSyncCoordinator(
            accountId: malformed,
            store: store,
            transport: server,
            mutationId: _uuid,
          ),
          throwsA(code('PRACTICE_INVALID_ACCOUNT')),
        );
      }
      expect(store.reads, isEmpty);
      expect(store.writes, isEmpty);
      expect(server.gets, 0);
      expect(server.puts, isEmpty);
    },
  );

  test(
    'durable crossfields reject impossible retry state without losing its bytes',
    () async {
      final pending = PracticeMutation(
        mutationId: _uuid(),
        baseRevision: 0,
        progress: started(),
      );
      final valid = PracticeSyncState(
        accountId: account,
        local: started(),
        base: emptyServer(),
        pending: pending,
        conflict: null,
      ).toJson();
      final cases = [
        {...valid, 'base': null},
        {...valid, 'base': snapshot(1, started()).toJson()},
        {...valid, 'conflict': snapshot(1, started()).toJson()},
        {
          ...valid,
          'local': OfficeProgress.empty().toJson(),
          'pending': PracticeMutation(
            mutationId: _uuid(),
            baseRevision: 0,
            progress: completed(),
          ).toJson(),
        },
      ];
      for (final value in cases) {
        final raw = jsonEncode(value);
        final store = _Store()
          ..values[PracticeSyncCoordinator.storageKeyFor(account)] = raw;
        final sync = _coordinator(store, _Server());
        await sync.load();
        expect(sync.loadIssue, PracticeSyncLoadIssue.corruptState);
        expect(store.values[sync.storageKey], raw);
        expect(store.writes, isEmpty);
      }
    },
  );
}
