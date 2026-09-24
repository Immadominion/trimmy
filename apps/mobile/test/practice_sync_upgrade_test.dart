import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/coordinator.dart';
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/practice_sync/protocol.dart';

import 'floor_two_progress_test.dart' show firstFloorV3;

const _account = '00000000-0000-4000-8000-000000000001';
const _oldId = '00000000-0000-4000-8000-000000000011';
const _newId = '00000000-0000-4000-8000-000000000012';
final _now = DateTime.utc(2026, 9, 15, 12);
PracticeSnapshot _snapshot(int revision, OfficeProgress? progress) =>
    PracticeSnapshot(
      revision: revision,
      progress: progress,
      updatedAt: revision == 0 ? null : _now,
    );
OfficeProgress _v3(OfficeProgress progress) =>
    OfficeProgress.fromJson({...progress.toJson(), 'version': 3});
Matcher _error(String code) =>
    throwsA(isA<PracticeSyncException>().having((e) => e.code, 'code', code));

class _Store implements PracticeSyncStore {
  String? raw;
  int writes = 0;
  bool failNext = false;
  @override
  Future<String?> read(String key) async => raw;
  @override
  Future<bool> write(String key, String value) async {
    writes++;
    if (failNext) {
      failNext = false;
      return false;
    }
    raw = value;
    return true;
  }
}

class _Transport implements PracticeTransport {
  _Transport(this.current);
  @override
  String get accountId => _account;
  PracticeSnapshot current;
  int gets = 0;
  final bodies = <String>[];
  Future<PracticeSnapshot> Function(PracticeMutation)? onPut;
  @override
  Future<PracticeSnapshot> getProgress() async {
    gets++;
    return current;
  }

  @override
  Future<PracticeSnapshot> putProgress(PracticeMutation mutation) async {
    bodies.add(jsonEncode(mutation.toJson()));
    if (onPut != null) return onPut!(mutation);
    current = _snapshot(mutation.baseRevision + 1, mutation.progress);
    return current;
  }
}

PracticeSyncCoordinator _sync(_Store store, _Transport transport) =>
    PracticeSyncCoordinator(
      accountId: _account,
      store: store,
      transport: transport,
      mutationId: () => _newId,
    );
_Store _queued(OfficeProgress old) => _Store()
  ..raw = PracticeSyncState(
    accountId: _account,
    local: old,
    base: _snapshot(0, null),
    pending: PracticeMutation(
      mutationId: _oldId,
      baseRevision: 0,
      progress: old,
    ),
    conflict: null,
  ).encode();

void main() {
  test(
    'old v3 pending body survives restart, v4 local work and a historical receipt',
    () async {
      final old = firstFloorV3();
      final store = _queued(old);
      final untouched = store.raw;
      final receipt = _snapshot(1, old);
      final server = _Transport(receipt);
      final gate = Completer<PracticeSnapshot>();
      final entered = Completer<void>();
      server.onPut = (_) {
        entered.complete();
        return gate.future;
      };
      final sync = _sync(store, server);
      await sync.load();
      final exactBody = jsonEncode(sync.state!.pending!.toJson());
      expect(store.writes, 0);
      expect(store.raw, untouched);
      final sending = sync.synchronize();
      await entered.future;
      final newLocal = sync.localProgress
          .startActivity(OfficeActivityIds.compareCompanyValue)
          .advance();
      await sync.saveLocal(newLocal);
      expect(sync.localProgress.wireVersion, 6);
      expect(jsonEncode(sync.state!.pending!.toJson()), exactBody);
      gate.completeError(const PracticeSyncException('PRACTICE_NETWORK_ERROR'));
      await expectLater(sending, _error('PRACTICE_NETWORK_ERROR'));

      // Another device advanced the server after the committed old request.
      server.current = _snapshot(2, old.upgradeForWrite());
      server.onPut = (_) async => receipt;
      final restarted = _sync(store, server);
      await restarted.load();
      await restarted.synchronize();
      expect(server.gets, 0);
      expect(server.bodies, [exactBody, exactBody]);
      expect(restarted.state!.pending, isNull);
      expect(restarted.state!.base!.progress!.wireVersion, 3);
      expect(restarted.state!.base!.revision, 1);
      expect(restarted.localProgress.toJson(), newLocal.toJson());
      expect(
        restarted.localProgress.toJson()['completions'],
        old.toJson()['completions'],
      );
      // Next cycle observes revision2 before creating a new v4 command.
      server.onPut = null;
      await restarted.synchronize();
      expect(server.gets, 1);
      expect(restarted.state!.base!.revision, 3);
      expect(restarted.localProgress.toJson(), newLocal.toJson());
      final newBody = jsonDecode(server.bodies.last);
      expect(newBody['baseRevision'], 2);
      expect(newBody['mutationId'], _newId);
      expect(newBody['progress']['version'], 6);
    },
  );

  test(
    'failed acknowledgment persistence retains the exact old request for restart',
    () async {
      final old = firstFloorV3();
      final store = _queued(old);
      final original = store.raw;
      final receipt = _snapshot(1, old);
      final server = _Transport(receipt)..onPut = (_) async => receipt;
      final sync = _sync(store, server);
      await sync.load();
      store.failNext = true;
      await expectLater(
        sync.synchronize(),
        _error('PRACTICE_LOCAL_SAVE_FAILED'),
      );
      expect(store.raw, original);
      expect(sync.state!.pending!.progress.wireVersion, 3);
      final restart = _sync(store, server);
      await restart.load();
      await restart.synchronize();
      expect(server.bodies.first, server.bodies.last);
      expect(restart.state!.base!.progress!.wireVersion, 3);
      expect(restart.state!.pending, isNull);
    },
  );

  test(
    'a receipt with only a changed payload version cannot acknowledge v3',
    () async {
      final old = firstFloorV3();
      final store = _queued(old);
      final raw = store.raw;
      final server = _Transport(_snapshot(1, old.upgradeForWrite()));
      server.onPut = (_) async => server.current;
      final sync = _sync(store, server);
      await sync.load();
      await expectLater(sync.synchronize(), _error('PRACTICE_ACK_MISMATCH'));
      expect(store.raw, raw);
      expect(sync.state!.pending!.progress.wireVersion, 3);
    },
  );

  test(
    'version-only local migration is semantically clean but server revisions stay immutable',
    () async {
      final old = firstFloorV3();
      final current = old.upgradeForWrite();
      expect(samePracticeProgress(old, current), isTrue);
      expect(canonicalProgress(old), isNot(canonicalProgress(current)));
      final store = _Store()
        ..raw = PracticeSyncState(
          accountId: _account,
          local: current,
          base: _snapshot(1, old),
          pending: null,
          conflict: null,
        ).encode();
      final server = _Transport(_snapshot(1, old));
      final sync = _sync(store, server);
      await sync.load();
      await sync.synchronize();
      expect(server.bodies, isEmpty);
      expect(sync.state!.conflict, isNull);
      server.current = _snapshot(1, current);
      await expectLater(sync.synchronize(), _error('PRACTICE_CONFLICT'));
      expect(sync.localProgress.wireVersion, 6);
      expect(sync.state!.conflict!.revision, 1);
      expect(server.bodies, isEmpty);
    },
  );

  test(
    'empty v3 safely restores v4 remote; new intents persist as v4 before PUT',
    () async {
      final oldEmpty = _v3(OfficeProgress.empty());
      final remote = firstFloorV3().startActivity(
        OfficeActivityIds.compareCompanyValue,
      );
      final store = _Store()
        ..raw = PracticeSyncState(
          accountId: _account,
          local: oldEmpty,
          base: null,
          pending: null,
          conflict: null,
        ).encode();
      final server = _Transport(_snapshot(1, remote));
      final sync = _sync(store, server);
      await sync.load();
      expect(sync.localProgress.wireVersion, 3);
      await sync.synchronize();
      expect(sync.localProgress.toJson(), remote.toJson());
      expect(server.bodies, isEmpty);
      await sync.saveLocal(sync.localProgress.advance());
      store.failNext = true;
      await expectLater(
        sync.synchronize(),
        _error('PRACTICE_LOCAL_SAVE_FAILED'),
      );
      expect(server.bodies, isEmpty);
      expect(sync.state!.pending, isNull);
      server.onPut = (mutation) async {
        final disk = PracticeSyncState.decode(store.raw!, accountId: _account);
        expect(disk.pending!.toJson(), mutation.toJson());
        expect(mutation.progress.wireVersion, 6);
        return _snapshot(2, mutation.progress);
      };
      await sync.synchronize();
      expect(sync.state!.pending, isNull);
    },
  );
}
