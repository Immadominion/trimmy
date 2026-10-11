import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solana/base58.dart';
import 'package:trimmy/account/incoming_funding_client.dart';
import 'package:trimmy/account/incoming_funding_controller.dart';
import 'package:trimmy/account/incoming_funding_models.dart';
import 'package:trimmy/account/incoming_funding_store.dart';
import 'package:trimmy/account/mobile_wallet_service.dart';
import 'package:trimmy/practice_sync/http_transport.dart';

final now = DateTime.utc(2026, 10, 11);
final fixtures =
    jsonDecode(
          File('test/fixtures/incoming-funding-policy.json').readAsStringSync(),
        )
        as List;
Map<String, Object?> envelope([int i = 0]) {
  final v =
      jsonDecode(jsonEncode(fixtures[i]['envelope'])) as Map<String, Object?>;
  (v['review'] as Map)['expiresAt'] = now
      .add(const Duration(seconds: 90))
      .toIso8601String();
  return v;
}

FundingReview review() => FundingReview.parse(envelope());
final sig = base58encode(List.filled(64, 3));

class Store implements FundingIntentStore {
  FundingIntent? value;
  Completer<void>? saving;
  @override
  Future<FundingIntent?> read() async => value;
  @override
  Future<void> save(FundingIntent v) async {
    await saving?.future;
    value = v;
  }

  @override
  Future<void> clear(String h) async {
    if (value?.requestHash == h) value = null;
  }
}

class Wallet implements MobileWalletService {
  int sends = 0, acks = 0, resolves = 0;
  Object? failure;
  Completer<MobileWalletAccount>? connecting;
  Completer<String>? sending;
  MobileWalletPendingOperation? pending;
  @override
  bool get available => true;
  @override
  Future<MobileWalletAccount> connect() async => connecting == null
      ? MobileWalletAccount(address: review().from)
      : await connecting!.future;
  @override
  Future<String> signAndSend({
    required String address,
    required String unsignedTransaction,
  }) async {
    sends++;
    if (failure != null) throw failure!;
    return sending == null ? sig : await sending!.future;
  }

  @override
  Future<void> disconnect() async {}
  @override
  Future<MobileWalletPendingOperation?> getPendingOperation() async => pending;
  @override
  Future<void> acknowledgeUnknownOutcome({required String requestHash}) async {
    acks++;
    pending = null;
  }

  @override
  Future<void> resolvePending({
    required String requestHash,
    required String signature,
  }) async {
    resolves++;
    pending = null;
  }
}

class Client implements IncomingFundingClient {
  int previews = 0, checks = 0;
  bool closed = false;
  Completer<FundingReview>? preparing;
  Completer<FundingReceipt>? checking;
  FundingReview next = review();
  FundingReceipt receipt = const FundingReceipt(FundingStatus.pending, null);
  Object? statusError;
  @override
  Future<FundingReview> preview(String f, String a, String amount) async {
    previews++;
    return preparing == null ? next : await preparing!.future;
  }

  @override
  Future<FundingReceipt> status(FundingReview r, String s) async {
    checks++;
    if (statusError != null) throw statusError!;
    return checking == null ? receipt : await checking!.future;
  }

  @override
  void close() {
    closed = true;
  }
}

class Harness {
  final client = Client(), wallet = Wallet(), store = Store();
  bool current = true;
  int refreshes = 0;
  late final controller = IncomingFundingController(
    client: client,
    wallet: wallet,
    store: store,
    accountId: 'a',
    subject: 's',
    recipient: review().recipient,
    isCurrent: () => current,
    refreshPortfolio: () async {
      refreshes++;
    },
    now: () => now,
  );
  Future<void> prepared() async {
    await controller.initialize();
    await controller.connect();
    await controller.prepare('SOL', '0.005');
  }

  void dispose() => controller.dispose();
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 10));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final key in ['sol', 'usdcMissingAta']) {
    test('validates actual backend previewFunding $key wire', () async {
      final fixture =
          jsonDecode(
                File('test/fixtures/funding-backend.json').readAsStringSync(),
              )
              as Map;
      final r = FundingReview.parse(fixture[key]);
      await r.validate(
        expectedFrom: fixture['from'],
        expectedRecipient: fixture['destination'],
        expectedAsset: key == 'sol' ? 'SOL' : 'USDC',
        expectedAmount: fixture['amountRaw'],
        now: DateTime.parse(fixture['now']),
      );
    });
  }
  test('amount conversion never rounds, permits exponent or overflows', () {
    expect(fundingAmountRaw('0.000000001', 'SOL'), '1');
    expect(fundingAmountRaw('1.000001', 'USDC'), '1000001');
    for (final a in [
      '0',
      '-1',
      '1e6',
      '01',
      '1.0000001',
      '18446744073709551616',
      '1.',
    ]) {
      expect(fundingAmountRaw(a, 'USDC'), isNull, reason: a);
    }
  });
  for (var i = 0; i < fixtures.length; i++) {
    final index = i;
    test('offline incoming policy: ${fixtures[i]['name']}', () async {
      Future<void> work() async {
        final r = FundingReview.parse(envelope(index));
        await r.validate(
          expectedFrom: r.from,
          expectedRecipient: r.recipient,
          expectedAsset: r.asset,
          expectedAmount: r.amountRaw,
          now: now,
        );
      }

      if (fixtures[index]['accepted'] == true) {
        await work();
      } else {
        await expectLater(work(), throwsA(isA<Exception>()));
      }
    });
  }
  test('local recipient and amount remain authoritative', () async {
    final r = review();
    await expectLater(
      r.validate(
        expectedFrom: r.from,
        expectedRecipient: r.from,
        expectedAsset: 'SOL',
        expectedAmount: r.amountRaw,
        now: now,
      ),
      throwsA(isA<FundingFailure>()),
    );
    await expectLater(
      r.validate(
        expectedFrom: r.from,
        expectedRecipient: r.recipient,
        expectedAsset: 'SOL',
        expectedAmount: '1',
        now: now,
      ),
      throwsA(isA<FundingFailure>()),
    );
  });
  test('confirmed and failed receipts require exact valid slot', () {
    for (final v in [
      {'status': 'confirmed'},
      {'status': 'success', 'slot': 1},
      {'status': 'failed', 'slot': null},
    ]) {
      expect(() => FundingReceipt.parse(v), throwsA(isA<FundingFailure>()));
    }
  });
  test(
    'single flight dispatch; only verified receipt refreshes balance',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.prepared();
      h.wallet.sending = Completer<String>();
      final work = h.controller.confirm();
      await tick();
      await h.controller.confirm();
      expect(h.wallet.sends, 1);
      expect(h.refreshes, 0);
      h.wallet.sending!.complete(sig);
      await work;
      await tick();
      expect(h.controller.phase, IncomingFundingPhase.pending);
      expect(h.refreshes, 0);
      h.client.receipt = const FundingReceipt(FundingStatus.confirmed, 12);
      await h.controller.checkStatus();
      expect(h.refreshes, 1);
      expect(h.store.value, isNull);
      expect(h.wallet.resolves, 1);
    },
  );
  test('tampered wire cannot reach signing wallet', () async {
    final h = Harness();
    addTearDown(h.dispose);
    h.client.next = FundingReview.parse(envelope(1));
    await h.prepared();
    await h.controller.confirm();
    expect(h.wallet.sends, 0);
  });
  test('account change during connect or preview cannot approve', () async {
    final h = Harness();
    addTearDown(h.dispose);
    await h.controller.initialize();
    h.wallet.connecting = Completer<MobileWalletAccount>();
    final work = h.controller.connect();
    h.current = false;
    h.wallet.connecting!.complete(MobileWalletAccount(address: review().from));
    await work;
    expect(h.controller.source, isNull);
    final g = Harness();
    addTearDown(g.dispose);
    await g.controller.initialize();
    await g.controller.connect();
    g.client.preparing = Completer<FundingReview>();
    final pending = g.controller.prepare('SOL', '0.005');
    g.current = false;
    g.client.preparing!.complete(review());
    await pending;
    await g.controller.confirm();
    expect(g.wallet.sends, 0);
  });
  test('logout during journal write prevents dispatch', () async {
    final h = Harness();
    addTearDown(h.dispose);
    await h.prepared();
    h.store.saving = Completer<void>();
    final work = h.controller.confirm();
    await tick();
    h.current = false;
    h.store.saving!.complete();
    await work;
    expect(h.wallet.sends, 0);
  });
  test(
    'wallet return after logout persists signature but cannot refresh wrong account',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.prepared();
      h.wallet.sending = Completer<String>();
      final work = h.controller.confirm();
      await tick();
      h.current = false;
      h.wallet.sending!.complete(sig);
      await work;
      expect(h.store.value?.signature, sig);
      expect(h.client.checks, 0);
      expect(h.refreshes, 0);
    },
  );
  test(
    'cancel permits new review; uncertain result never automatically resends',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.prepared();
      h.wallet.failure = const MobileWalletException('MOBILE_WALLET_CANCELLED');
      await h.controller.confirm();
      expect(h.store.value, isNull);
      expect(h.controller.phase, IncomingFundingPhase.disconnected);
      await h.controller.connect();
      await h.controller.prepare('SOL', '0.005');
      h.wallet.failure = const MobileWalletException(
        'MOBILE_WALLET_OUTCOME_UNKNOWN',
      );
      await h.controller.confirm();
      expect(h.controller.phase, IncomingFundingPhase.uncertain);
      expect(h.store.value, isNotNull);
      await h.controller.confirm();
      await h.controller.prepare('SOL', '0.005');
      expect(h.wallet.sends, 2);
      await h.controller.acknowledgeUnknown();
      expect(h.controller.phase, IncomingFundingPhase.disconnected);
      expect(h.controller.review, isNull);
      expect(h.store.value, isNull);
    },
  );
  test('account B cannot see or clear account A journal', () async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.value = FundingIntent(
      accountId: 'b',
      subject: 'b',
      recipient: review().recipient,
      requestHash: 'a' * 64,
      review: review(),
      signature: sig,
    );
    await h.controller.initialize();
    expect(h.controller.signature, isNull);
    expect(h.controller.canAcknowledge, false);
    await h.controller.acknowledgeUnknown();
    expect(h.store.value, isNotNull);
    expect(h.wallet.acks, 0);
    expect(h.client.checks, 0);
  });
  test('changed native pending hash cannot be acknowledged', () async {
    final h = Harness();
    addTearDown(h.dispose);
    await h.prepared();
    h.wallet.failure = const MobileWalletException(
      'MOBILE_WALLET_OUTCOME_UNKNOWN',
    );
    await h.controller.confirm();
    h.wallet.pending = MobileWalletPendingOperation(
      address: review().from,
      requestHash: 'b' * 64,
    );
    await h.controller.acknowledgeUnknown();
    expect(h.wallet.acks, 0);
    expect(h.store.value, isNotNull);
  });
  test(
    'unverified pasted signature is ephemeral and editable after rejection',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.prepared();
      h.wallet.failure = const MobileWalletException(
        'MOBILE_WALLET_OUTCOME_UNKNOWN',
      );
      await h.controller.confirm();
      h.client.statusError = const FundingFailure('INVALID_SIGNATURE');
      await h.controller.reconcileSignature(sig);
      expect(h.store.value?.signature, isNull);
      expect(h.controller.canAcknowledge, true);
      expect(h.refreshes, 0);
    },
  );
  test(
    'candidate status blocks acknowledgement while awaiting and respects logout',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.prepared();
      h.wallet.failure = const MobileWalletException(
        'MOBILE_WALLET_OUTCOME_UNKNOWN',
      );
      await h.controller.confirm();
      h.client.checking = Completer<FundingReceipt>();
      final work = h.controller.reconcileSignature(sig);
      expect(h.controller.busy, true);
      await h.controller.acknowledgeUnknown();
      h.current = false;
      h.client.checking!.complete(
        const FundingReceipt(FundingStatus.confirmed, 2),
      );
      await work;
      expect(h.store.value?.signature, isNull);
      expect(h.refreshes, 0);
    },
  );
  test(
    'network errors and lifecycle resume stay pending, never resend',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.prepared();
      h.client.statusError = const FundingFailure('TRANSFER_UNAVAILABLE');
      await h.controller.confirm();
      await tick();
      expect(h.controller.phase, IncomingFundingPhase.pending);
      h.controller.setForeground(false);
      h.controller.setForeground(true);
      await tick();
      expect(h.wallet.sends, 1);
      expect(h.refreshes, 0);
    },
  );
  test(
    'global journal neither overwrites a different transfer nor clears another hash',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = SharedFundingIntentStore();
      await s.save(
        FundingIntent(
          accountId: 'a',
          subject: 'a',
          recipient: review().recipient,
          requestHash: 'a' * 64,
          review: review(),
        ),
      );
      await s.clear('b' * 64);
      expect((await s.read())?.requestHash, 'a' * 64);
      await expectLater(
        s.save(
          FundingIntent(
            accountId: 'b',
            subject: 'b',
            recipient: review().recipient,
            requestHash: 'b' * 64,
            review: review(),
          ),
        ),
        throwsA(isA<FundingFailure>()),
      );
      await s.clear('a' * 64);
      expect(await s.read(), isNull);
    },
  );
  for (final status in [404, 503]) {
    test('capabilities $status hides entry', () async {
      expect(
        await HttpIncomingFundingClient.available(
          MockClient((_) async => http.Response('{}', status)),
          Uri.parse('https://trimmy.test'),
        ),
        false,
      );
    });
  }
  test('capability gate handles enabled, disabled and offline', () async {
    for (final enabled in [false, true]) {
      expect(
        await HttpIncomingFundingClient.available(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'enabled': enabled,
                'chain': 'solana:mainnet',
                'assets': ['SOL', 'USDC'],
              }),
              200,
            ),
          ),
          Uri.parse('https://trimmy.test'),
        ),
        enabled,
      );
    }
    expect(
      await HttpIncomingFundingClient.available(
        MockClient((_) async => throw const SocketException('offline')),
        Uri.parse('https://trimmy.test'),
      ),
      false,
    );
  });
  test(
    'recovery-only controller permits receipt checks but cannot create new funding',
    () async {
      final client = Client(), wallet = Wallet(), store = Store();
      final c = IncomingFundingController(
        client: client,
        wallet: wallet,
        store: store,
        accountId: 'a',
        subject: 's',
        recipient: review().recipient,
        isCurrent: () => true,
        refreshPortfolio: () async {},
        allowNew: false,
        now: () => now,
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.connect();
      await c.prepare('SOL', '0.005');
      expect(c.canEdit, false);
      expect(client.previews, 0);
      expect(wallet.sends, 0);
    },
  );
  test(
    'pending auto-checks pause in background and stop on disposal',
    () async {
      final client = Client(), wallet = Wallet(), store = Store();
      final c = IncomingFundingController(
        client: client,
        wallet: wallet,
        store: store,
        accountId: 'a',
        subject: 's',
        recipient: review().recipient,
        isCurrent: () => true,
        refreshPortfolio: () async {},
        pollInterval: const Duration(milliseconds: 5),
        now: () => now,
      );
      await c.initialize();
      await c.connect();
      await c.prepare('SOL', '0.005');
      await c.confirm();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.checks, greaterThan(1));
      c.setForeground(false);
      final paused = client.checks;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.checks, paused);
      c.setForeground(true);
      await tick();
      expect(client.checks, greaterThan(paused));
      c.dispose();
      final stopped = client.checks;
      await tick();
      expect(client.checks, stopped);
      expect(wallet.sends, 1);
    },
  );
  for (final response in [
    http.Response(
      '{}',
      302,
      headers: {
        'content-type': 'application/json',
        'location': 'https://elsewhere.test',
      },
    ),
    http.Response(
      'x' * 9000,
      200,
      headers: {'content-type': 'application/json'},
    ),
    http.Response('<html>', 200, headers: {'content-type': 'text/html'}),
  ]) {
    test(
      'funding client rejects redirect, oversized or non-JSON response ${response.statusCode}/${response.body.length}',
      () async {
        final c = HttpIncomingFundingClient(
          client: MockClient((_) async => response),
          origin: Uri.parse('https://trimmy.test'),
          accountId: 'a',
          accessToken: () async =>
              const PracticeAccessToken(accountId: 'a', token: 'test-token'),
          isCurrent: () => true,
        );
        addTearDown(c.close);
        await expectLater(
          c.preview(review().from, 'SOL', '1'),
          throwsA(isA<FundingFailure>()),
        );
      },
    );
  }
  test('account change during bearer fetch cannot send request', () async {
    var current = true, calls = 0;
    final token = Completer<PracticeAccessToken>();
    final c = HttpIncomingFundingClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
      origin: Uri.parse('https://trimmy.test'),
      accountId: 'a',
      accessToken: () => token.future,
      isCurrent: () => current,
    );
    final work = c.preview(review().from, 'SOL', '1');
    current = false;
    token.complete(
      const PracticeAccessToken(accountId: 'a', token: 'test-token'),
    );
    await expectLater(work, throwsA(isA<FundingFailure>()));
    expect(calls, 0);
    c.close();
  });
}
