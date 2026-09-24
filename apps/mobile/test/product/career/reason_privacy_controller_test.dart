import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/career/career.dart';

import 'reason_sharing_test_support.dart';

void main() {
  test('bind reads the server choice and holds no pending write', () async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy());
    final store = _MutationStore();
    final controller = _controller(store: store);

    await controller.bind(principalKey: 'account:one', repository: repository);

    expect(controller.privacy?.visibility, ReasonVisibility.nobody);
    expect(controller.privacy?.configured, isFalse);
    expect(controller.pending, isNull);
    expect(controller.loading, isFalse);
    expect(controller.failure, isNull);
    expect(store.events, ['read:account:one']);
  });

  test(
    'a choice is stored, written once and confirmed by the server',
    () async {
      final store = _MutationStore();
      final repository = FakeReasonSharingRepository()
        ..privacyReads.add(testPrivacy())
        ..onPut = (write) {
          expect(store.values['account:one']?.mutationId, write.mutationId);
          return testReceipt(write);
        };
      final controller = _controller(store: store);
      await controller.bind(
        principalKey: 'account:one',
        repository: repository,
      );

      final saved = await controller.choose(ReasonVisibility.everyone);

      expect(saved, isTrue);
      expect(repository.writes.single.mutationId, testReasonMutation);
      expect(repository.writes.single.baseRevision, 1);
      expect(repository.writes.single.visibility, ReasonVisibility.everyone);
      expect(controller.privacy?.revision, 2);
      expect(controller.privacy?.visibility, ReasonVisibility.everyone);
      expect(controller.notice, ReasonPrivacyNotice.saved);
      expect(controller.pending, isNull);
      expect(store.values, isEmpty);
      expect(store.events, [
        'read:account:one',
        'write:account:one:$testReasonMutation',
        'remove:account:one',
      ]);
    },
  );

  test('nothing reads as saved until the server answers', () async {
    final gate = Completer<ReasonPrivacyReceipt>();
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (_) => gate.future;
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);
    final states = <String>[];
    controller.addListener(() {
      states.add(
        '${controller.saving ? 'saving' : 'idle'}:'
        '${controller.privacy?.visibility.name}:'
        '${controller.pending?.visibility.name}:'
        '${controller.notice?.name}',
      );
    });

    final result = controller.choose(ReasonVisibility.everyone);
    await Future<void>.delayed(Duration.zero);

    expect(controller.saving, isTrue);
    expect(controller.privacy?.visibility, ReasonVisibility.nobody);
    expect(controller.pending?.visibility, ReasonVisibility.everyone);
    expect(controller.notice, isNull);

    gate.complete(testReceipt(repository.writes.single));
    expect(await result, isTrue);
    expect(states.first, 'saving:nobody:everyone:null');
    expect(states.last, 'idle:everyone:null:saved');
  });

  test(
    'an ambiguous timeout keeps the exact write and retry replays it',
    () async {
      final store = _MutationStore();
      var puts = 0;
      final repository = FakeReasonSharingRepository()
        ..privacyReads.add(testPrivacy())
        ..onPut = (write) {
          puts++;
          if (puts == 1) {
            throw const ReasonSharingException(ReasonSharingFailure.timeout);
          }
          return testReceipt(write);
        };
      var generated = 0;
      final controller = _controller(
        store: store,
        mutationId: () {
          generated++;
          return generated == 1 ? testReasonMutation : testOtherReasonMutation;
        },
      );
      await controller.bind(
        principalKey: 'account:one',
        repository: repository,
      );

      expect(await controller.choose(ReasonVisibility.everyone), isFalse);
      expect(controller.failure, ReasonSharingFailure.timeout);
      expect(controller.pending?.mutationId, testReasonMutation);
      expect(controller.privacy?.visibility, ReasonVisibility.nobody);
      expect(store.values['account:one']?.mutationId, testReasonMutation);

      expect(await controller.retry(), isTrue);

      expect(repository.writes, hasLength(2));
      expect(repository.writes[1].mutationId, testReasonMutation);
      expect(generated, 1);
      expect(controller.failure, isNull);
      expect(controller.notice, ReasonPrivacyNotice.saved);
      expect(controller.privacy?.visibility, ReasonVisibility.everyone);
      expect(store.values, isEmpty);
    },
  );

  test('choosing the same value again reuses the pending command', () async {
    var puts = 0;
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (write) {
        puts++;
        if (puts == 1) {
          throw const ReasonSharingException(ReasonSharingFailure.offline);
        }
        return testReceipt(write);
      };
    var generated = 0;
    final controller = _controller(
      mutationId: () {
        generated++;
        return generated == 1 ? testReasonMutation : testOtherReasonMutation;
      },
    );
    await controller.bind(principalKey: 'account:one', repository: repository);

    await controller.choose(ReasonVisibility.everyone);
    await controller.choose(ReasonVisibility.everyone);

    expect(repository.writes.map((write) => write.mutationId), [
      testReasonMutation,
      testReasonMutation,
    ]);
    expect(controller.privacy?.visibility, ReasonVisibility.everyone);
  });

  test('a different value after an ambiguous failure gets a new ID', () async {
    var puts = 0;
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (write) {
        puts++;
        if (puts == 1) {
          throw const ReasonSharingException(ReasonSharingFailure.offline);
        }
        return testReceipt(write);
      };
    var generated = 0;
    final controller = _controller(
      mutationId: () {
        generated++;
        return generated == 1 ? testReasonMutation : testOtherReasonMutation;
      },
    );
    await controller.bind(principalKey: 'account:one', repository: repository);

    await controller.choose(ReasonVisibility.everyone);
    expect(await controller.choose(ReasonVisibility.friends), isTrue);

    expect(repository.writes[1].mutationId, testOtherReasonMutation);
    expect(repository.writes[1].visibility, ReasonVisibility.friends);
    expect(controller.privacy?.visibility, ReasonVisibility.friends);
  });

  test('an exact replay after a later change shows the newer choice', () async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (write) => testReceipt(
        write,
        privacy: testPrivacy(revision: 3, visibility: ReasonVisibility.friends),
      );
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);

    expect(await controller.choose(ReasonVisibility.everyone), isFalse);

    expect(controller.privacy?.revision, 3);
    expect(controller.privacy?.visibility, ReasonVisibility.friends);
    expect(controller.notice, ReasonPrivacyNotice.changedElsewhere);
    expect(controller.failure, isNull);
    expect(controller.pending, isNull);
  });

  test('a revision conflict refreshes and reports the change', () async {
    final store = _MutationStore();
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..privacyReads.add(
        testPrivacy(revision: 2, visibility: ReasonVisibility.friends),
      )
      ..onPut = (_) => Future<ReasonPrivacyReceipt>.error(
        const ReasonSharingException(ReasonSharingFailure.revisionConflict),
      );
    final controller = _controller(store: store);
    await controller.bind(principalKey: 'account:one', repository: repository);

    expect(await controller.choose(ReasonVisibility.everyone), isFalse);

    expect(repository.privacyReadCount, 2);
    expect(controller.privacy?.revision, 2);
    expect(controller.privacy?.visibility, ReasonVisibility.friends);
    expect(controller.notice, ReasonPrivacyNotice.changedElsewhere);
    expect(controller.failure, isNull);
    expect(controller.pending, isNull);
    expect(store.values, isEmpty);
  });

  test('an idempotency conflict burns the ID and never replays it', () async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (write) {
        if (write.mutationId == testReasonMutation) {
          throw const ReasonSharingException(
            ReasonSharingFailure.idempotencyConflict,
          );
        }
        return testReceipt(write);
      };
    var generated = 0;
    final controller = _controller(
      mutationId: () {
        generated++;
        return generated == 1 ? testReasonMutation : testOtherReasonMutation;
      },
    );
    await controller.bind(principalKey: 'account:one', repository: repository);

    expect(await controller.choose(ReasonVisibility.everyone), isFalse);
    expect(controller.failure, ReasonSharingFailure.idempotencyConflict);
    expect(controller.pending, isNull);
    expect(controller.privacy?.visibility, ReasonVisibility.nobody);

    expect(await controller.choose(ReasonVisibility.everyone), isTrue);
    expect(repository.writes[1].mutationId, testOtherReasonMutation);
    expect(controller.privacy?.visibility, ReasonVisibility.everyone);
  });

  test('a rate limit keeps the write and the exact delay', () async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (_) => Future<ReasonPrivacyReceipt>.error(
        const ReasonSharingException(
          ReasonSharingFailure.rateLimited,
          retryAfter: Duration(seconds: 42),
        ),
      );
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);

    expect(await controller.choose(ReasonVisibility.nobody), isFalse);

    expect(controller.failure, ReasonSharingFailure.rateLimited);
    expect(controller.retryAfter, const Duration(seconds: 42));
    expect(controller.pending?.visibility, ReasonVisibility.nobody);
  });

  test('a closed account clears the write and reports it', () async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (_) => Future<ReasonPrivacyReceipt>.error(
        const ReasonSharingException(ReasonSharingFailure.accountNotFound),
      );
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);

    expect(await controller.choose(ReasonVisibility.everyone), isFalse);

    expect(controller.failure, ReasonSharingFailure.accountNotFound);
    expect(controller.pending, isNull);
  });

  test('a restart replays a stored pending write with the same ID', () async {
    final store = _MutationStore()
      ..values['account:one'] = ReasonPrivacyWrite(
        mutationId: testReasonMutation,
        baseRevision: 1,
        visibility: ReasonVisibility.everyone,
      );
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (write) => testReceipt(write);
    final controller = _controller(
      store: store,
      mutationId: () => testOtherReasonMutation,
    );

    await controller.bind(principalKey: 'account:one', repository: repository);

    expect(repository.writes.single.mutationId, testReasonMutation);
    expect(controller.privacy?.visibility, ReasonVisibility.everyone);
    expect(controller.notice, ReasonPrivacyNotice.saved);
    expect(store.values, isEmpty);
  });

  test('a stored write ahead of the server revision is dropped', () async {
    final store = _MutationStore()
      ..values['account:one'] = ReasonPrivacyWrite(
        mutationId: testReasonMutation,
        baseRevision: 5,
        visibility: ReasonVisibility.everyone,
      );
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy());
    final controller = _controller(store: store);

    await controller.bind(principalKey: 'account:one', repository: repository);

    expect(repository.writes, isEmpty);
    expect(controller.pending, isNull);
    expect(store.values, isEmpty);
  });

  test('refresh keeps a pending write without replaying it', () async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..privacyReads.add(testPrivacy())
      ..onPut = (_) => Future<ReasonPrivacyReceipt>.error(
        const ReasonSharingException(ReasonSharingFailure.unavailable),
      );
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);
    await controller.choose(ReasonVisibility.everyone);

    await controller.refresh();

    expect(repository.writes, hasLength(1));
    expect(controller.pending?.mutationId, testReasonMutation);
    expect(controller.failure, isNull);
  });

  test('a load failure is reported and retry re-reads', () async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(
        Future<ReasonPrivacy>.error(
          const ReasonSharingException(ReasonSharingFailure.offline),
        ),
      )
      ..privacyReads.add(testPrivacy());
    final controller = _controller();

    await controller.bind(principalKey: 'account:one', repository: repository);
    expect(controller.privacy, isNull);
    expect(controller.failure, ReasonSharingFailure.offline);
    expect(await controller.choose(ReasonVisibility.everyone), isFalse);
    expect(repository.writes, isEmpty);

    expect(await controller.retry(), isTrue);
    expect(controller.privacy?.visibility, ReasonVisibility.nobody);
    expect(controller.failure, isNull);
  });

  test('a terminal guest failure is surfaced, not flattened', () async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(
        Future<ReasonPrivacy>.error(
          const GuestSessionException(GuestSessionFailure.expired),
        ),
      );
    final controller = _controller();

    await controller.bind(principalKey: 'guest:one', repository: repository);

    expect(controller.guestSessionFailure, GuestSessionFailure.expired);
    expect(controller.failure, isNull);
  });

  test('a late old-principal answer cannot write into the new one', () async {
    final oldGate = Completer<ReasonPrivacyReceipt>();
    final oldRepository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (_) => oldGate.future;
    final newRepository = FakeReasonSharingRepository()
      ..privacyReads.add(
        testPrivacy(revision: 4, visibility: ReasonVisibility.friends),
      );
    final controller = _controller();
    await controller.bind(
      principalKey: 'account:old',
      repository: oldRepository,
    );
    final oldChoice = controller.choose(ReasonVisibility.everyone);
    await Future<void>.delayed(Duration.zero);

    await controller.bind(
      principalKey: 'account:new',
      repository: newRepository,
    );
    oldGate.complete(testReceipt(oldRepository.writes.single));

    expect(await oldChoice, isFalse);
    expect(controller.principalKey, 'account:new');
    expect(controller.privacy?.revision, 4);
    expect(controller.privacy?.visibility, ReasonVisibility.friends);
    expect(controller.saving, isFalse);
    expect(controller.notice, isNull);
  });

  test('SharedPreferences store round-trips the exact command', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = PreferencesReasonPrivacyMutationStore(preferences);
    final command = ReasonPrivacyWrite(
      mutationId: testReasonMutation,
      baseRevision: 1,
      visibility: ReasonVisibility.everyone,
    );

    expect(await store.write('account:one', command), isTrue);
    final restored = await PreferencesReasonPrivacyMutationStore(
      preferences,
    ).read('account:one');

    expect(restored?.mutationId, command.mutationId);
    expect(restored?.baseRevision, command.baseRevision);
    expect(restored?.visibility, command.visibility);
    expect(await store.remove('account:one'), isTrue);
    expect(await store.read('account:one'), isNull);
  });
}

ReasonPrivacyController _controller({
  ReasonPrivacyMutationStore? store,
  ReasonPrivacyMutationIdFactory? mutationId,
}) {
  final controller = ReasonPrivacyController(
    mutationStore: store ?? _MutationStore(),
    mutationId: mutationId ?? () => testReasonMutation,
  );
  addTearDown(controller.dispose);
  return controller;
}

final class _MutationStore implements ReasonPrivacyMutationStore {
  final values = <String, ReasonPrivacyWrite>{};
  final events = <String>[];

  @override
  Future<ReasonPrivacyWrite?> read(String principalKey) async {
    events.add('read:$principalKey');
    return values[principalKey];
  }

  @override
  Future<bool> write(String principalKey, ReasonPrivacyWrite command) async {
    events.add('write:$principalKey:${command.mutationId}');
    values[principalKey] = command;
    return true;
  }

  @override
  Future<bool> remove(String principalKey) async {
    events.add('remove:$principalKey');
    values.remove(principalKey);
    return true;
  }
}
