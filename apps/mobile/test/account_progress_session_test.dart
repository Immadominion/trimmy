import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/account_progress_session.dart';
import 'package:trimmy/practice_sync/coordinator.dart';
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/practice_sync/protocol.dart';

const account = 'bf000000-0000-4000-8000-000000000001';
const otherAccount = 'bf000000-0000-4000-8000-000000000002';
final savedAt = DateTime.utc(2026, 9, 14, 15, 0, 0, 123, 456);

class _Store implements PracticeSyncStore {
  final values = <String, String>{};
  bool failWrite = false;
  Completer<void>? holdWrite;
  Completer<void>? writeStarted;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> write(String key, String value) async {
    final gate = holdWrite;
    if (gate != null) {
      holdWrite = null;
      writeStarted?.complete();
      await gate.future;
    }
    if (failWrite) return false;
    values[key] = value;
    return true;
  }
}

class _Remote implements PracticeTransport {
  _Remote(this.accountId);
  @override
  final String accountId;
  PracticeSnapshot current = PracticeSnapshot(
    revision: 0,
    progress: null,
    updatedAt: null,
  );
  final receipts = <String, PracticeSnapshot>{};
  final writes = <PracticeMutation>[];
  bool loseNextReply = false;
  Completer<void>? gate;
  @override
  Future<PracticeSnapshot> getProgress() async => current;
  @override
  Future<PracticeSnapshot> putProgress(PracticeMutation mutation) async {
    writes.add(mutation);
    await gate?.future;
    if (receipts[mutation.mutationId] case final previous?) return previous;
    if (mutation.baseRevision != current.revision) {
      throw PracticeRevisionConflict(current);
    }
    current = PracticeSnapshot(
      revision: current.revision + 1,
      progress: mutation.progress,
      updatedAt: DateTime.utc(2026, 9, 14, 16),
    );
    receipts[mutation.mutationId] = current;
    if (loseNextReply) {
      loseNextReply = false;
      throw const PracticeSyncException('PRACTICE_NETWORK_ERROR');
    }
    return current;
  }
}

Future<void> _complete(OfficeProgressRepository repository) async {
  await repository.startActivity(OfficeActivityIds.checkTheDate);
  await repository.advance();
  await repository.advance();
  await repository.selectChoice('keep-headline');
  await repository.submitChoice();
  await repository.acceptCorrection();
}

void main() {
  test(
    'retirement waits for accepted guest import before same-account reopen',
    () async {
      final store = _Store();
      final remote = _Remote(account);
      final session = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
      );
      final imported = OfficeProgress.empty()
          .startActivity(OfficeActivityIds.checkTheDate)
          .advance()
          .advance()
          .selectChoice('add-year');
      final gate = Completer<void>();
      store.holdWrite = gate;
      store.writeStarted = Completer<void>();
      final importing = session.importProgress(imported);
      await store.writeStarted!.future;
      session.close();
      AccountProgressSession? reopened;
      final retirement = session.whenIdle.then((_) async {
        reopened = await AccountProgressSession.open(
          accountId: account,
          store: store,
          transport: remote,
        );
      });
      await Future<void>.delayed(Duration.zero);
      expect(reopened, isNull);
      await expectLater(
        session.importProgress(imported),
        throwsA(isA<PracticeSyncException>()),
      );
      gate.complete();
      await importing;
      await retirement;
      expect(reopened!.progressRepository.state.toJson(), imported.toJson());
      await reopened!.progressRepository.inspectStage(1);
      final saved = PracticeSyncState.decode(
        store.values[PracticeSyncCoordinator.storageKeyFor(account)]!,
        accountId: account,
      );
      expect(saved.local.active!.selectedChoiceId, 'add-year');
      expect(saved.local.active!.stage, 1);
      reopened!.close();
    },
  );

  test(
    'retirement waits for conflict resolution to persist before reopening',
    () async {
      final store = _Store();
      final remote = _Remote(account);
      final session = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
      );
      await session.progressRepository.startActivity(
        OfficeActivityIds.checkTheDate,
      );
      await session.synchronize();
      await session.progressRepository.advance();
      final resolved = session.progressRepository.state.advance().selectChoice(
        'add-year',
      );
      remote.current = PracticeSnapshot(
        revision: 2,
        progress: resolved,
        updatedAt: DateTime.utc(2026, 9, 14, 16, 1),
      );
      await expectLater(
        session.synchronize(),
        throwsA(isA<PracticeSyncException>()),
      );
      expect(session.coordinator.state!.conflict, isNotNull);
      final gate = Completer<void>();
      store.holdWrite = gate;
      store.writeStarted = Completer<void>();
      final resolving = session.resolveConflict(resolved);
      await store.writeStarted!.future;
      session.close();
      AccountProgressSession? reopened;
      final retirement = session.whenIdle.then((_) async {
        reopened = await AccountProgressSession.open(
          accountId: account,
          store: store,
          transport: remote,
        );
      });
      await Future<void>.delayed(Duration.zero);
      expect(reopened, isNull);
      gate.complete();
      await resolving;
      await retirement;
      expect(reopened!.coordinator.state!.conflict, isNull);
      expect(reopened!.coordinator.state!.base!.revision, 2);
      expect(reopened!.progressRepository.state.toJson(), resolved.toJson());
      reopened!.close();
    },
  );

  test(
    'retirement drains a failed direct write without poisoning future sessions',
    () async {
      final store = _Store();
      final remote = _Remote(account);
      final session = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
      );
      final original =
          store.values[PracticeSyncCoordinator.storageKeyFor(account)];
      final gate = Completer<void>();
      store.holdWrite = gate;
      store.writeStarted = Completer<void>();
      store.failWrite = true;
      final importing = expectLater(
        session.importProgress(
          OfficeProgress.empty().startActivity(OfficeActivityIds.checkTheDate),
        ),
        throwsA(isA<PracticeSyncException>()),
      );
      await store.writeStarted!.future;
      session.close();
      var retired = false;
      final retirement = session.whenIdle.then((_) => retired = true);
      await Future<void>.delayed(Duration.zero);
      expect(retired, isFalse);
      gate.complete();
      await importing;
      await retirement;
      expect(
        store.values[PracticeSyncCoordinator.storageKeyFor(account)],
        original,
      );
      store.failWrite = false;
      final reopened = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
      );
      expect(reopened.progressRepository.state.active, isNull);
      await reopened.progressRepository.startActivity(
        OfficeActivityIds.checkTheDate,
      );
      reopened.close();
    },
  );

  test(
    'an action from an old screen cannot overwrite a remote draft during restoration',
    () async {
      final store = _Store();
      final remote = _Remote(account);
      final session = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
      );
      await session.progressRepository.startActivity(
        OfficeActivityIds.checkTheDate,
      );
      await session.synchronize();
      // Another device moves from the synchronized brief to a selected answer.
      final restored = session.progressRepository.state
          .advance()
          .advance()
          .selectChoice('keep-headline');
      remote.current = PracticeSnapshot(
        revision: 2,
        progress: restored,
        updatedAt: DateTime.utc(2026, 9, 14, 16, 1),
      );
      final gate = Completer<void>();
      store.holdWrite = gate;
      store.writeStarted = Completer<void>();
      final sync = session.synchronize();
      await store.writeStarted!.future;
      // The UI still holds the brief while the recovered draft is being stored.
      final staleAction = expectLater(
        session.progressRepository.advance(),
        throwsA(isA<ProgressSaveException>()),
      );
      gate.complete();
      await staleAction;
      await sync;
      expect(session.progressRepository.state.toJson(), restored.toJson());
      expect(session.coordinator.localProgress.toJson(), restored.toJson());
      final restarted = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
      );
      expect(restarted.progressRepository.state.toJson(), restored.toJson());
      session.close();
      restarted.close();
    },
  );
  test(
    'existing activity writes acknowledge one account record before upload',
    () async {
      final store = _Store();
      final remote = _Remote(account);
      final session = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
        clock: () => savedAt,
      );
      await _complete(session.progressRepository);
      expect(remote.writes, isEmpty);
      expect(session.progressRepository.state.active!.stage, 4);
      expect(store.values.keys, [
        PracticeSyncCoordinator.storageKeyFor(account),
      ]);
      expect(
        store.values.containsKey(OfficeProgressRepository.saveKey),
        isFalse,
      );
      await session.synchronize();
      expect(remote.current.revision, 1);
      expect(
        remote.current.progress!.toJson(),
        session.progressRepository.state.toJson(),
      );
      expect(
        remote.writes.single.mutationId,
        matches(
          RegExp(r'^[0-9a-f-]{14}4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
        ),
      );
      expect(
        remote.current.progress!.completions.values.single.completedAt,
        savedAt,
      );
      session.close();
    },
  );

  test(
    'uncertain uploaded completion resumes with the same mutation through a new session',
    () async {
      final store = _Store();
      final remote = _Remote(account)..loseNextReply = true;
      var session = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
        clock: () => savedAt,
      );
      await _complete(session.progressRepository);
      await expectLater(
        session.synchronize(),
        throwsA(isA<PracticeSyncException>()),
      );
      final pending = session.coordinator.state!.pending!;
      session.close();
      session = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
      );
      expect(session.coordinator.state!.pending!.toJson(), pending.toJson());
      await session.synchronize();
      expect(remote.current.revision, 1);
      expect(remote.writes.length, 2);
      expect(remote.writes[0].toJson(), remote.writes[1].toJson());
      expect(session.coordinator.state!.pending, isNull);
      expect(
        session.progressRepository.state.completions.values.single.completedAt,
        savedAt,
      );
    },
  );

  test(
    'a fresh account restores remote work into the existing repository without copying another account',
    () async {
      final store = _Store();
      final remote = _Remote(account);
      var source = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
        clock: () => savedAt,
      );
      await _complete(source.progressRepository);
      await source.synchronize();
      source.close();
      final freshDevice = _Store();
      source = await AccountProgressSession.open(
        accountId: account,
        store: freshDevice,
        transport: remote,
      );
      expect(source.progressRepository.state.completions, isEmpty);
      await source.synchronize();
      expect(source.progressRepository.state.completions.length, 1);
      final other = await AccountProgressSession.open(
        accountId: otherAccount,
        store: freshDevice,
        transport: _Remote(otherAccount),
      );
      expect(other.progressRepository.state.completions, isEmpty);
      expect(freshDevice.values.length, 2);
    },
  );

  test(
    'a held upload does not block local activity writes or overwrite their newer stage',
    () async {
      final store = _Store();
      final remote = _Remote(account)..gate = Completer<void>();
      final session = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
      );
      await session.progressRepository.startActivity(
        OfficeActivityIds.checkTheDate,
      );
      final syncing = session.synchronize();
      while (remote.writes.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await session.progressRepository.advance();
      expect(session.progressRepository.state.active!.stage, 1);
      remote.gate!.complete();
      await syncing;
      expect(session.progressRepository.state.active!.stage, 1);
      expect(session.coordinator.state!.base!.progress!.active!.stage, 0);
      await session.synchronize();
      expect(remote.current.progress!.active!.stage, 1);
    },
  );

  test(
    'local write failure leaves activity state unchanged; closing blocks future writes and sync',
    () async {
      final store = _Store();
      final remote = _Remote(account);
      final session = await AccountProgressSession.open(
        accountId: account,
        store: store,
        transport: remote,
      );
      store.failWrite = true;
      await expectLater(
        session.progressRepository.startActivity(
          OfficeActivityIds.checkTheDate,
        ),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(session.progressRepository.state.active, isNull);
      expect(remote.writes, isEmpty);
      store.failWrite = false;
      session.close();
      await expectLater(
        session.progressRepository.startActivity(
          OfficeActivityIds.checkTheDate,
        ),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(session.synchronize, throwsA(isA<PracticeSyncException>()));
    },
  );

  test(
    'corrupt account records are preserved and cannot silently import guest progress over them',
    () async {
      final store = _Store();
      final key = PracticeSyncCoordinator.storageKeyFor(account);
      store.values[key] = jsonEncode({
        'schemaVersion': 999,
        'private': 'retained',
      });
      final original = store.values[key];
      await expectLater(
        AccountProgressSession.open(
          accountId: account,
          store: store,
          transport: _Remote(account),
          initialProgress: OfficeProgress.empty().startActivity(
            OfficeActivityIds.checkTheDate,
          ),
        ),
        throwsA(isA<PracticeSyncException>()),
      );
      expect(store.values[key], original);
    },
  );
}
