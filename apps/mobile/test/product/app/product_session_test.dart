import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/app/product_profile_repository.dart';
import 'package:trimmy/product/app/product_session.dart';
import 'package:trimmy/product/onboarding/onboarding.dart';

const _profile = OnboardingProfile(
  goal: OnboardingGoal.learn,
  knowledge: TradingKnowledge.nothing,
  persona: TraderPersona.oracle,
  dailyGoal: OnboardingDailyGoal.oneMission,
  handle: 'rookie',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('signed-in entry opens Home without manufacturing a trade', () async {
    ProductProfileSnapshot? stored;
    final repository = _ProfileRepository(
      onRead: () async => stored,
      onAdvance: (call) async => stored = _snapshot(
        revision: call.baseRevision + 1,
        checkpoint: ProductProfileCheckpoint.app,
        profile: const OnboardingProfile(),
        hasConfirmedPaperTrade: false,
      ),
    );
    final session = ProductSession.fromPreferences(
      await SharedPreferences.getInstance(),
    );
    await session.bindRemote(
      principalKey: 'account-new',
      repository: repository,
      mutationIdFactory: () => 'entry-test',
    );
    await session.enterSignedInApp();
    expect(session.launchStep, ProductLaunchStep.app);
    expect(session.firstTradeComplete, isFalse);
    expect(session.profile?.persona, isNull);
    final restored = ProductSession.fromPreferences(
      await SharedPreferences.getInstance(),
    );
    await restored.bindRemote(
      principalKey: 'account-new',
      repository: repository,
      mutationIdFactory: () => 'unused',
    );
    expect(restored.launchStep, ProductLaunchStep.app);
  });

  test('optional persona saves at the current checkpoint', () async {
    const unanswered = OnboardingProfile();
    final repository = _ProfileRepository(
      readResult: _snapshot(
        revision: 3,
        checkpoint: ProductProfileCheckpoint.app,
        profile: unanswered,
      ),
    );
    final session = ProductSession.fromPreferences(
      await SharedPreferences.getInstance(),
    );
    await session.bindRemote(
      principalKey: 'guest-persona',
      repository: repository,
      mutationIdFactory: () => 'persona-mutation',
    );

    await session.choosePersona(TraderPersona.shark);

    expect(session.profile?.persona, TraderPersona.shark);
    expect(session.launchStep, ProductLaunchStep.app);
    expect(repository.writes.single.checkpoint, ProductProfileCheckpoint.app);
    expect(repository.writes.single.baseRevision, 3);
    expect(repository.writes.single.onboarding.goal, isNull);
  });

  test('starting practice saves only choices the user made', () async {
    final repository = _ProfileRepository();
    final preferences = await SharedPreferences.getInstance();
    final session = ProductSession.fromPreferences(preferences);
    await session.bindRemote(
      principalKey: 'guest-short-intro',
      repository: repository,
      mutationIdFactory: () => 'intro-start',
    );
    await session.beginIntroduction();
    expect(session.profile, const OnboardingProfile());
    expect(session.launchStep, ProductLaunchStep.firstTrade);
    expect(session.firstTradeComplete, isFalse);
    expect(repository.writes.single.onboarding, const OnboardingProfile());
    expect(repository.advances, isEmpty);

    final restored = ProductSession.fromPreferences(preferences);
    await restored.bindRemote(
      principalKey: 'guest-short-intro',
      repository: _ProfileRepository(
        onRead: () async =>
            throw const ProductProfileException(ProductProfileFailure.offline),
      ),
      mutationIdFactory: () => 'unused',
    );
    expect(restored.profile, const OnboardingProfile());
    expect(restored.launchStep, ProductLaunchStep.firstTrade);
    expect(restored.firstTradeComplete, isFalse);
  });

  test(
    'skipping the introduction persists app access without a pretend trade',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final repository = _ProfileRepository(
        onAdvance: (call) async => _snapshot(
          revision: call.baseRevision + 1,
          checkpoint: ProductProfileCheckpoint.app,
          profile: const OnboardingProfile(),
          hasConfirmedPaperTrade: false,
        ),
      );
      final session = ProductSession.fromPreferences(preferences);
      await session.bindRemote(
        principalKey: 'guest-skip-intro',
        repository: repository,
        mutationIdFactory: () => 'intro-skip',
      );
      await session.skipIntroduction();
      expect(session.launchStep, ProductLaunchStep.app);
      expect(session.profile, const OnboardingProfile());
      expect(session.firstTradeComplete, isFalse);
      expect(session.firstPositionCollected, isFalse);
      expect(session.dayOneSeen, isFalse);
      expect(
        repository.advances.single.action,
        ProductLaunchAction.introductionSkipped,
      );
      final restored = ProductSession.fromPreferences(preferences);
      await restored.bindRemote(
        principalKey: 'guest-skip-intro',
        repository: _ProfileRepository(
          onRead: () async => throw const ProductProfileException(
            ProductProfileFailure.offline,
          ),
        ),
        mutationIdFactory: () => 'unused',
      );
      expect(restored.launchStep, ProductLaunchStep.app);
      expect(restored.firstTradeComplete, isFalse);
      expect(restored.profile?.handle, isNull);
    },
  );

  test(
    'skip holds the note while pending and after failure, then retries to desk',
    () async {
      final pending = Completer<ProductProfileSnapshot>();
      final entered = Completer<void>();
      var attempts = 0;
      final repository = _ProfileRepository(
        onAdvance: (call) {
          if (++attempts == 1) {
            entered.complete();
            return pending.future;
          }
          return Future.value(
            _snapshot(
              revision: call.baseRevision + 1,
              checkpoint: ProductProfileCheckpoint.app,
              profile: const OnboardingProfile(),
              hasConfirmedPaperTrade: false,
            ),
          );
        },
      );
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );
      await session.bindRemote(
        principalKey: 'guest-held-skip',
        repository: repository,
        mutationIdFactory: () => 'skip-held',
      );
      final observed = <ProductLaunchStep>[];
      session.addListener(() => observed.add(session.launchStep));
      final rejected = expectLater(
        session.skipIntroduction(),
        throwsA(isA<ProductProfileException>()),
      );
      await entered.future;
      expect(session.profile, const OnboardingProfile());
      expect(session.launchStep, ProductLaunchStep.onboarding);
      expect(observed, isNot(contains(ProductLaunchStep.firstTrade)));
      pending.completeError(
        const ProductProfileException(ProductProfileFailure.timeout),
      );
      await rejected;
      expect(session.launchStep, ProductLaunchStep.onboarding);
      await session.skipIntroduction();
      expect(session.launchStep, ProductLaunchStep.app);
      expect(observed, isNot(contains(ProductLaunchStep.firstTrade)));
      expect(repository.writes, hasLength(1));
      expect(session.firstTradeComplete, isFalse);
    },
  );

  test('Continue after a failed skip explicitly opens practice', () async {
    final session = ProductSession.fromPreferences(
      await SharedPreferences.getInstance(),
    );
    await session.bindRemote(
      principalKey: 'guest-skip-then-continue',
      repository: _ProfileRepository(
        onAdvance: (_) async =>
            throw const ProductProfileException(ProductProfileFailure.offline),
      ),
      mutationIdFactory: () => 'skip-then-continue',
    );
    await expectLater(
      session.skipIntroduction(),
      throwsA(isA<ProductProfileException>()),
    );
    expect(session.launchStep, ProductLaunchStep.onboarding);
    await session.beginIntroduction();
    expect(session.launchStep, ProductLaunchStep.firstTrade);
    expect(session.firstTradeComplete, isFalse);
  });

  test(
    'completion depends on server trade evidence and retries safely',
    () async {
      var attempt = 0;
      var mutation = 0;
      final repository = _ProfileRepository(
        readResult: _snapshot(
          revision: 1,
          checkpoint: ProductProfileCheckpoint.firstTrade,
          profile: const OnboardingProfile(),
          hasConfirmedPaperTrade: false,
        ),
        onAdvance: (call) async {
          if (++attempt == 1) {
            throw const ProductProfileException(ProductProfileFailure.timeout);
          }
          return _snapshot(
            revision: 2,
            checkpoint: ProductProfileCheckpoint.app,
            profile: const OnboardingProfile(),
            hasConfirmedPaperTrade: true,
          );
        },
      );
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );
      await session.bindRemote(
        principalKey: 'guest-finish-intro',
        repository: repository,
        mutationIdFactory: () => 'finish-${++mutation}',
      );
      await expectLater(
        session.finishIntroduction(),
        throwsA(isA<ProductProfileException>()),
      );
      expect(session.launchStep, ProductLaunchStep.firstTrade);
      expect(session.firstTradeComplete, isFalse);
      await session.finishIntroduction();
      expect(repository.advances.map((call) => call.mutationId), [
        'finish-1',
        'finish-1',
      ]);
      expect(
        repository.advances.last.action,
        ProductLaunchAction.introductionCompleted,
      );
      expect(session.launchStep, ProductLaunchStep.app);
      expect(session.firstTradeComplete, isTrue);
      expect(session.firstPositionCollected, isFalse);
    },
  );

  test(
    'a confirmed first buy on reopen never demands a duplicate first buy',
    () async {
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );
      await session.bindRemote(
        principalKey: 'guest-recovered-intro',
        repository: _ProfileRepository(
          readResult: _snapshot(
            revision: 1,
            checkpoint: ProductProfileCheckpoint.firstTrade,
            profile: const OnboardingProfile(),
            hasConfirmedPaperTrade: true,
          ),
        ),
        mutationIdFactory: () => 'unused',
      );
      expect(session.launchStep, ProductLaunchStep.firstPosition);
      expect(session.firstTradeComplete, isTrue);
    },
  );

  test('launch steps persist in product order', () async {
    final preferences = await SharedPreferences.getInstance();
    final session = ProductSession.fromPreferences(preferences);
    expect(session.launchStep, ProductLaunchStep.onboarding);

    await session.completeOnboarding(
      const OnboardingResult(
        profile: _profile,
        notificationStatus: OnboardingNotificationStatus.denied,
      ),
    );
    expect(session.launchStep, ProductLaunchStep.firstTrade);
    await session.markFirstTradeComplete();
    expect(session.launchStep, ProductLaunchStep.firstPosition);
    await session.markFirstPositionCollected();
    expect(session.launchStep, ProductLaunchStep.dayOne);
    await session.markDayOneSeen();
    expect(session.launchStep, ProductLaunchStep.saveDesk);
    await session.markAccountGateLater();
    expect(session.launchStep, ProductLaunchStep.app);

    final restored = ProductSession.fromPreferences(preferences);
    expect(restored.profile, _profile);
    expect(restored.notificationStatus, OnboardingNotificationStatus.denied);
    expect(restored.launchStep, ProductLaunchStep.app);
  });

  test('launch moments cannot advance without a confirmed trade', () async {
    final session = ProductSession.fromPreferences(
      await SharedPreferences.getInstance(),
    );
    await session.completeOnboarding(
      const OnboardingResult(
        profile: _profile,
        notificationStatus: OnboardingNotificationStatus.unavailable,
      ),
    );

    await expectLater(
      session.markFirstPositionCollected(),
      throwsA(isA<StateError>()),
    );
    await expectLater(session.markDayOneSeen(), throwsA(isA<StateError>()));
    await expectLater(
      session.markAccountGateLater(),
      throwsA(isA<StateError>()),
    );
    expect(session.launchStep, ProductLaunchStep.firstTrade);
  });

  test(
    'invalid profile cannot skip onboarding or inherit later flags',
    () async {
      SharedPreferences.setMockInitialValues({
        'trimmy.product.profile.v1': jsonEncode({
          'version': 1,
          'goal': 'learn',
          'knowledge': 'nothing',
          'persona': 'wolf',
          'dailyGoal': 'one-mission',
          'handle': '../wrong',
        }),
        'trimmy.product.first-trade.v1': true,
        'trimmy.product.account-gate.v1': true,
      });
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );
      expect(session.launchStep, ProductLaunchStep.onboarding);
      expect(session.loadIssue, isNotNull);
    },
  );

  test('server checkpoints restore the exact launch screen', () async {
    const expected = {
      ProductProfileCheckpoint.firstTrade: ProductLaunchStep.firstTrade,
      ProductProfileCheckpoint.firstPosition: ProductLaunchStep.firstPosition,
      ProductProfileCheckpoint.streak: ProductLaunchStep.dayOne,
      ProductProfileCheckpoint.saveDesk: ProductLaunchStep.saveDesk,
      ProductProfileCheckpoint.app: ProductLaunchStep.app,
    };

    for (final entry in expected.entries) {
      final repository = _ProfileRepository(
        readResult: _snapshot(
          revision: entry.key.index + 1,
          checkpoint: entry.key,
        ),
      );
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );

      await session.bindRemote(
        principalKey: 'guest-${entry.key.wire}',
        repository: repository,
        mutationIdFactory: () => 'unused',
      );

      expect(
        session.launchStep,
        entry.value,
        reason: 'checkpoint ${entry.key.wire}',
      );
      expect(session.profile, _profile);
      expect(session.remoteProfileUsable, isTrue);
      expect(repository.readCount, 1);
    }
  });

  test(
    'an existing app checkpoint stays terminal without another write',
    () async {
      final repository = _ProfileRepository(
        readResult: _snapshot(
          revision: 11,
          checkpoint: ProductProfileCheckpoint.app,
        ),
      );
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );

      await session.bindRemote(
        principalKey: 'account-existing-app',
        repository: repository,
        mutationIdFactory: () => 'must-not-be-used',
      );
      await session.markFirstTradeComplete();
      await session.markFirstPositionCollected();
      await session.markDayOneSeen();
      await session.markAccountGateSaved();

      expect(session.launchStep, ProductLaunchStep.app);
      expect(repository.writes, isEmpty);
      expect(repository.advances, isEmpty);
    },
  );

  test(
    'remote flow writes every checkpoint in order and reaches app',
    () async {
      var mutation = 0;
      final repository = _ProfileRepository(readResult: null);
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );
      await session.bindRemote(
        principalKey: 'guest-one',
        repository: repository,
        mutationIdFactory: () => 'mutation-${++mutation}',
      );

      await session.completeOnboarding(
        const OnboardingResult(
          profile: _profile,
          notificationStatus: OnboardingNotificationStatus.denied,
        ),
      );
      expect(session.launchStep, ProductLaunchStep.firstTrade);
      await session.markFirstTradeComplete();
      expect(session.launchStep, ProductLaunchStep.firstPosition);
      await session.markFirstPositionCollected();
      expect(session.launchStep, ProductLaunchStep.dayOne);
      await session.markDayOneSeen();
      expect(session.launchStep, ProductLaunchStep.saveDesk);
      await session.markAccountGateLater();
      expect(session.launchStep, ProductLaunchStep.app);

      expect(repository.writes.map((call) => call.checkpoint), [
        ProductProfileCheckpoint.firstTrade,
      ]);
      expect(repository.writes.map((call) => call.baseRevision), [0]);
      expect(repository.writes.map((call) => call.mutationId), ['mutation-1']);
      expect(
        repository.writes.every((call) => call.onboarding == _profile),
        isTrue,
      );
      expect(repository.advances.map((call) => call.action), [
        ProductLaunchAction.paperTradeConfirmed,
        ProductLaunchAction.firstPositionCollected,
        ProductLaunchAction.dayOneSeen,
        ProductLaunchAction.saveDeskLater,
      ]);
      expect(repository.advances.map((call) => call.baseRevision), [
        1,
        2,
        3,
        4,
      ]);
      expect(repository.advances.map((call) => call.mutationId), [
        'mutation-2',
        'mutation-3',
        'mutation-4',
        'mutation-5',
      ]);
      expect(session.hasRemoteSnapshot, isTrue);
      expect(session.remoteFailure, isNull);
    },
  );

  test('ambiguous timeout retry reuses the same mutation ID', () async {
    var attempt = 0;
    var mutation = 0;
    final repository = _ProfileRepository(
      readResult: null,
      onWrite: (call) async {
        attempt++;
        if (attempt == 1) {
          throw const ProductProfileException(ProductProfileFailure.timeout);
        }
        return _snapshot(
          revision: call.baseRevision + 1,
          checkpoint: call.checkpoint,
          profile: call.onboarding,
        );
      },
    );
    final session = ProductSession.fromPreferences(
      await SharedPreferences.getInstance(),
    );
    await session.bindRemote(
      principalKey: 'guest-timeout',
      repository: repository,
      mutationIdFactory: () => 'mutation-${++mutation}',
    );
    const result = OnboardingResult(
      profile: _profile,
      notificationStatus: OnboardingNotificationStatus.unavailable,
    );

    await expectLater(
      session.completeOnboarding(result),
      throwsA(
        isA<ProductProfileException>().having(
          (error) => error.failure,
          'failure',
          ProductProfileFailure.timeout,
        ),
      ),
    );
    expect(session.launchStep, ProductLaunchStep.onboarding);
    expect(session.remoteFailure, ProductProfileFailure.timeout);

    await session.completeOnboarding(result);

    expect(repository.writes, hasLength(2));
    expect(repository.writes[0].mutationId, repository.writes[1].mutationId);
    expect(repository.writes[0].baseRevision, 0);
    expect(repository.writes[1].baseRevision, 0);
    expect(mutation, 1);
    expect(session.launchStep, ProductLaunchStep.firstTrade);
    expect(session.remoteFailure, isNull);
  });

  test('repeat onboarding taps share one in-flight server write', () async {
    var calls = 0;
    var mutation = 0;
    final accepted = Completer<ProductProfileSnapshot>();
    final duplicate = Completer<ProductProfileSnapshot>();
    final repository = _ProfileRepository(
      readResult: null,
      onWrite: (_) {
        calls++;
        return calls == 1 ? accepted.future : duplicate.future;
      },
    );
    final session = ProductSession.fromPreferences(
      await SharedPreferences.getInstance(),
    );
    await session.bindRemote(
      principalKey: 'guest-repeat-onboarding',
      repository: repository,
      mutationIdFactory: () => 'mutation-${++mutation}',
    );
    const result = OnboardingResult(
      profile: _profile,
      notificationStatus: OnboardingNotificationStatus.denied,
    );

    final first = session.completeOnboarding(result);
    final repeat = session.completeOnboarding(result);
    expect(calls, 1);
    expect(mutation, 1);
    accepted.complete(
      _snapshot(revision: 1, checkpoint: ProductProfileCheckpoint.firstTrade),
    );
    await Future.wait([first, repeat]);

    expect(repository.writes, hasLength(1));
    expect(session.launchStep, ProductLaunchStep.firstTrade);
    expect(session.remoteFailure, isNull);
  });

  test('ambiguous launch timeout reuses the same action mutation ID', () async {
    var attempt = 0;
    var mutation = 0;
    final repository = _ProfileRepository(
      readResult: _snapshot(
        revision: 1,
        checkpoint: ProductProfileCheckpoint.firstTrade,
      ),
      onAdvance: (call) async {
        attempt++;
        if (attempt == 1) {
          throw const ProductProfileException(ProductProfileFailure.timeout);
        }
        return _snapshot(
          revision: call.baseRevision + 1,
          checkpoint: call.checkpoint,
        );
      },
    );
    final session = ProductSession.fromPreferences(
      await SharedPreferences.getInstance(),
    );
    await session.bindRemote(
      principalKey: 'guest-launch-timeout',
      repository: repository,
      mutationIdFactory: () => 'mutation-${++mutation}',
    );

    await expectLater(
      session.markFirstTradeComplete(),
      throwsA(
        isA<ProductProfileException>().having(
          (error) => error.failure,
          'failure',
          ProductProfileFailure.timeout,
        ),
      ),
    );
    expect(session.launchStep, ProductLaunchStep.firstTrade);

    await session.markFirstTradeComplete();

    expect(repository.advances, hasLength(2));
    expect(
      repository.advances[0].mutationId,
      repository.advances[1].mutationId,
    );
    expect(
      repository.advances[0].action,
      ProductLaunchAction.paperTradeConfirmed,
    );
    expect(mutation, 1);
    expect(session.launchStep, ProductLaunchStep.firstPosition);
  });

  test(
    'repeat launch taps share one request and cannot roll back the next action',
    () async {
      final preferences = await SharedPreferences.getInstance();
      var paperCalls = 0;
      var mutation = 0;
      final accepted = Completer<ProductProfileSnapshot>();
      final lateDuplicate = Completer<ProductProfileSnapshot>();
      final repository = _ProfileRepository(
        readResult: _snapshot(
          revision: 1,
          checkpoint: ProductProfileCheckpoint.firstTrade,
        ),
        onAdvance: (call) {
          if (call.action == ProductLaunchAction.paperTradeConfirmed) {
            paperCalls++;
            return paperCalls == 1 ? accepted.future : lateDuplicate.future;
          }
          return Future.value(
            _snapshot(
              revision: call.baseRevision + 1,
              checkpoint: call.checkpoint,
            ),
          );
        },
      );
      final session = ProductSession.fromPreferences(preferences);
      await session.bindRemote(
        principalKey: 'guest-repeat-launch',
        repository: repository,
        mutationIdFactory: () => 'mutation-${++mutation}',
      );

      final first = session.markFirstTradeComplete();
      final repeat = session.markFirstTradeComplete();
      expect(paperCalls, 1);
      expect(mutation, 1);
      accepted.complete(
        _snapshot(
          revision: 2,
          checkpoint: ProductProfileCheckpoint.firstPosition,
        ),
      );
      await Future.wait([first, repeat]);
      await session.markFirstPositionCollected();

      expect(repository.advances, hasLength(2));
      expect(session.launchStep, ProductLaunchStep.dayOne);
      expect(session.remoteFailure, isNull);
      expect(mutation, 2);

      final restored = ProductSession.fromPreferences(preferences);
      await restored.bindRemote(
        principalKey: 'guest-repeat-launch',
        repository: _ProfileRepository(
          onRead: () async => throw const ProductProfileException(
            ProductProfileFailure.offline,
          ),
        ),
        mutationIdFactory: () => 'unused',
      );
      expect(restored.launchStep, ProductLaunchStep.dayOne);
      expect(restored.remoteFailure, ProductProfileFailure.offline);
    },
  );

  test(
    'guest save completion cannot cross an account rebind at the save gate',
    () async {
      final guestCompletion = Completer<ProductProfileSnapshot>();
      final guest = _ProfileRepository(
        readResult: _snapshot(
          revision: 4,
          checkpoint: ProductProfileCheckpoint.saveDesk,
        ),
        onAdvance: (_) => guestCompletion.future,
      );
      final account = _ProfileRepository(
        readResult: _snapshot(
          revision: 4,
          checkpoint: ProductProfileCheckpoint.saveDesk,
        ),
      );
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );
      await session.bindRemote(
        principalKey: 'guest-before-claim',
        repository: guest,
        mutationIdFactory: () => 'guest-mutation',
      );

      final guestSave = session.markAccountGateLater();
      expect(guest.advances.single.action, ProductLaunchAction.saveDeskLater);
      await session.bindRemote(
        principalKey: 'account-after-claim',
        repository: account,
        mutationIdFactory: () => 'account-mutation',
      );
      guestCompletion.complete(
        _snapshot(revision: 5, checkpoint: ProductProfileCheckpoint.app),
      );
      await expectLater(
        guestSave,
        throwsA(
          isA<ProductProfileException>().having(
            (error) => error.failure,
            'failure',
            ProductProfileFailure.unavailable,
          ),
        ),
      );

      expect(session.remotePrincipalKey, 'account-after-claim');
      expect(session.launchStep, ProductLaunchStep.saveDesk);
      expect(session.remoteFailure, isNull);
      await session.markAccountGateSaved();
      expect(account.advances.single.action, ProductLaunchAction.saveDeskSaved);
      expect(session.launchStep, ProductLaunchStep.app);
    },
  );

  test(
    'a late read from the previous identity cannot replace the new one',
    () async {
      final accountARead = Completer<ProductProfileSnapshot?>();
      final accountA = _ProfileRepository(onRead: () => accountARead.future);
      const accountBProfile = OnboardingProfile(
        goal: OnboardingGoal.practice,
        knowledge: TradingKnowledge.basics,
        persona: TraderPersona.shark,
        dailyGoal: OnboardingDailyGoal.showUp,
        handle: 'account_b',
      );
      final accountB = _ProfileRepository(
        readResult: _snapshot(
          revision: 4,
          checkpoint: ProductProfileCheckpoint.saveDesk,
          profile: accountBProfile,
        ),
      );
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );

      final bindA = session.bindRemote(
        principalKey: 'account-a',
        repository: accountA,
        mutationIdFactory: () => 'a',
      );
      expect(accountA.readCount, 1);
      await session.bindRemote(
        principalKey: 'account-b',
        repository: accountB,
        mutationIdFactory: () => 'b',
      );
      expect(session.profile, accountBProfile);
      expect(session.launchStep, ProductLaunchStep.saveDesk);

      accountARead.complete(
        _snapshot(
          revision: 5,
          checkpoint: ProductProfileCheckpoint.app,
          profile: _profile,
        ),
      );
      await bindA;

      expect(session.remotePrincipalKey, 'account-b');
      expect(session.profile, accountBProfile);
      expect(session.launchStep, ProductLaunchStep.saveDesk);
      expect(session.remoteFailure, isNull);
    },
  );

  test(
    'a validated cache keeps the exact checkpoint available offline',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final online = _ProfileRepository(
        readResult: _snapshot(
          revision: 3,
          checkpoint: ProductProfileCheckpoint.streak,
        ),
      );
      final firstSession = ProductSession.fromPreferences(preferences);
      await firstSession.bindRemote(
        principalKey: 'guest-cached',
        repository: online,
        mutationIdFactory: () => 'unused',
      );
      await Future<void>.delayed(Duration.zero);

      final offline = _ProfileRepository(
        onRead: () async =>
            throw const ProductProfileException(ProductProfileFailure.offline),
      );
      final restored = ProductSession.fromPreferences(preferences);
      await restored.bindRemote(
        principalKey: 'guest-cached',
        repository: offline,
        mutationIdFactory: () => 'unused',
      );

      expect(restored.profile, _profile);
      expect(restored.launchStep, ProductLaunchStep.dayOne);
      expect(restored.remoteFailure, ProductProfileFailure.offline);
      expect(restored.remoteProfileUsable, isTrue);
      expect(restored.loadIssue, contains('offline'));
    },
  );

  test(
    'an unsafe cached revision cannot become offline profile state',
    () async {
      SharedPreferences.setMockInitialValues({
        'trimmy.product.profile-cache.v1.guest-unsafe': jsonEncode({
          'version': 1,
          'revision': 9007199254740992,
          'onboarding': _profile.toJson(),
          'launchCheckpoint': 'app',
          'createdAt': '2026-09-20T10:00:00.000Z',
          'updatedAt': '2026-09-20T10:00:00.000Z',
        }),
      });
      final session = ProductSession.fromPreferences(
        await SharedPreferences.getInstance(),
      );

      await session.bindRemote(
        principalKey: 'guest-unsafe',
        repository: _ProfileRepository(
          onRead: () async => throw const ProductProfileException(
            ProductProfileFailure.offline,
          ),
        ),
        mutationIdFactory: () => 'unused',
      );

      expect(session.profile, isNull);
      expect(session.launchStep, ProductLaunchStep.onboarding);
      expect(session.remoteProfileUsable, isFalse);
    },
  );

  test('a terminal guest read stays distinct from profile failure', () async {
    final session = ProductSession.fromPreferences(
      await SharedPreferences.getInstance(),
    );

    await session.bindRemote(
      principalKey: 'guest-terminal',
      repository: _ProfileRepository(
        onRead: () async =>
            throw const GuestSessionException(GuestSessionFailure.revoked),
      ),
      mutationIdFactory: () => 'unused',
    );

    expect(session.remoteGuestFailure, GuestSessionFailure.revoked);
    expect(session.remoteFailure, isNull);
    expect(session.remoteProfileUsable, isFalse);
  });
}

final class _ProfileWrite {
  const _ProfileWrite({
    required this.mutationId,
    required this.baseRevision,
    required this.onboarding,
    required this.checkpoint,
  });

  final String mutationId;
  final int baseRevision;
  final OnboardingProfile onboarding;
  final ProductProfileCheckpoint checkpoint;
}

final class _LaunchWrite {
  const _LaunchWrite({
    required this.mutationId,
    required this.baseRevision,
    required this.action,
    required this.checkpoint,
  });

  final String mutationId;
  final int baseRevision;
  final ProductLaunchAction action;
  final ProductProfileCheckpoint checkpoint;
}

final class _ProfileRepository implements ProductProfileRepository {
  _ProfileRepository({
    this.readResult,
    this.onRead,
    this.onWrite,
    this.onAdvance,
  });

  final ProductProfileSnapshot? readResult;
  final Future<ProductProfileSnapshot?> Function()? onRead;
  final Future<ProductProfileSnapshot> Function(_ProfileWrite call)? onWrite;
  final Future<ProductProfileSnapshot> Function(_LaunchWrite call)? onAdvance;
  final List<_ProfileWrite> writes = [];
  final List<_LaunchWrite> advances = [];
  int readCount = 0;

  @override
  Future<ProductProfileSnapshot?> read() async {
    readCount++;
    return onRead == null ? readResult : onRead!();
  }

  @override
  Future<ProductProfileSnapshot> write({
    required String mutationId,
    required int baseRevision,
    required OnboardingProfile onboarding,
    required ProductProfileCheckpoint launchCheckpoint,
  }) async {
    final call = _ProfileWrite(
      mutationId: mutationId,
      baseRevision: baseRevision,
      onboarding: onboarding,
      checkpoint: launchCheckpoint,
    );
    writes.add(call);
    if (onWrite != null) return onWrite!(call);
    return _snapshot(
      revision: baseRevision + 1,
      checkpoint: launchCheckpoint,
      profile: onboarding,
    );
  }

  @override
  Future<ProductProfileSnapshot> advance({
    required String mutationId,
    required int baseRevision,
    required ProductLaunchAction action,
  }) async {
    final checkpoint = switch (action) {
      ProductLaunchAction.paperTradeConfirmed =>
        ProductProfileCheckpoint.firstPosition,
      ProductLaunchAction.firstPositionCollected =>
        ProductProfileCheckpoint.streak,
      ProductLaunchAction.dayOneSeen => ProductProfileCheckpoint.saveDesk,
      ProductLaunchAction.saveDeskLater ||
      ProductLaunchAction.saveDeskSaved ||
      ProductLaunchAction.introductionSkipped ||
      ProductLaunchAction.introductionCompleted => ProductProfileCheckpoint.app,
    };
    final call = _LaunchWrite(
      mutationId: mutationId,
      baseRevision: baseRevision,
      action: action,
      checkpoint: checkpoint,
    );
    advances.add(call);
    if (onAdvance != null) return onAdvance!(call);
    return _snapshot(revision: baseRevision + 1, checkpoint: checkpoint);
  }
}

ProductProfileSnapshot _snapshot({
  required int revision,
  required ProductProfileCheckpoint checkpoint,
  OnboardingProfile profile = _profile,
  bool? hasConfirmedPaperTrade,
}) {
  final createdAt = DateTime.utc(2026, 9, 20, 10);
  return ProductProfileSnapshot(
    revision: revision,
    onboarding: profile,
    launchCheckpoint: checkpoint,
    createdAt: createdAt,
    updatedAt: createdAt.add(Duration(minutes: revision)),
    hasConfirmedPaperTrade: hasConfirmedPaperTrade,
  );
}
