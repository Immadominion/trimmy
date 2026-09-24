import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/account_data_models.dart';
import 'package:trimmy/account/wallet_possession_controller.dart';
import 'package:trimmy/account/wallet_possession_models.dart';

import 'support/wallet_possession_fakes.dart';

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'prepare reviews a real API contract before any signing occurs',
    () async {
      final h = ProofHarness();
      addTearDown(h.close);
      expect(h.contextReads, 0);
      expect(h.client.issued, 0);
      await h.controller.prepare();
      expect(h.contextReads, 1);
      expect(h.client.addresses, [proofWallet]);
      expect(h.controller.phase, WalletPossessionPhase.reviewing);
      expect(h.controller.challenge!.message, proofChallenge().message);
      expect(h.signer.messages, isEmpty);
      expect(h.client.verified, 0);
      await h.controller.confirm();
      expect(h.signer.subjects, [proofSubject]);
      expect(h.signer.messages, [proofChallenge().message]);
      expect(h.client.verified, 1);
      expect(h.controller.phase, WalletPossessionPhase.verified);
      expect(h.controller.receipt!.walletAddress, proofWallet);
      expect(h.controller.challenge, isNull);
    },
  );

  test('double confirmation cannot sign or submit twice', () async {
    final h = ProofHarness();
    addTearDown(h.close);
    await h.controller.prepare();
    h.signer.gate = Completer<String>();
    final first = h.controller.confirm();
    await h.controller.confirm();
    await h.controller.prepare();
    expect(h.signer.messages, hasLength(1));
    expect(h.client.issued, 1);
    h.signer.gate!.complete('signature');
    await first;
    expect(h.client.verified, 1);
  });

  test(
    'cancelling a pending identity read prevents challenge creation',
    () async {
      final h = ProofHarness();
      addTearDown(h.close);
      h.contextGate = Completer<AccountContextSnapshot>();
      final pending = h.controller.prepare();
      h.controller.cancel();
      await pending;
      h.contextGate!.complete(proofContext());
      await flush();
      expect(h.client.issued, 0);
      expect(h.signer.messages, isEmpty);
      expect(h.controller.phase, WalletPossessionPhase.cancelled);
    },
  );

  test('cancel from a listener happens before the next side effect', () async {
    final h = ProofHarness();
    addTearDown(h.close);
    h.controller.addListener(() {
      if (h.controller.phase == WalletPossessionPhase.preparing) {
        h.controller.cancel();
      }
    });
    await h.controller.prepare();
    expect(h.contextReads, 0);
    expect(h.client.issued, 0);
  });

  for (final interruption in ['background', 'offline', 'cancel', 'dispose']) {
    test('$interruption drops a late native signature', () async {
      final h = ProofHarness();
      addTearDown(h.close);
      await h.controller.prepare();
      h.signer.gate = Completer<String>();
      final pending = h.controller.confirm();
      switch (interruption) {
        case 'background':
          h.controller.setForeground(false);
        case 'offline':
          h.controller.setNetworkAvailable(false);
        case 'cancel':
          h.controller.cancel();
        case 'dispose':
          h.accountCurrent = false;
          h.controller.dispose();
      }
      await pending;
      h.signer.gate!.complete('late-signature');
      await flush();
      expect(h.client.verified, 0);
      expect(h.controller.receipt, isNull);
      h.controller.setForeground(true);
      h.controller.setNetworkAvailable(true);
      expect(h.client.issued, 1);
      expect(h.signer.messages, hasLength(1));
    });
  }

  test('expiry before confirmation never opens the signer', () async {
    final h = ProofHarness();
    addTearDown(h.close);
    await h.controller.prepare();
    h.now = proofChallenge().expiresAt;
    expect(h.controller.phase, WalletPossessionPhase.expired);
    expect(h.controller.canSign, false);
    await h.controller.confirm();
    expect(h.signer.messages, isEmpty);
  });

  test(
    'expiry while signing refuses the proof after native completion',
    () async {
      final h = ProofHarness();
      addTearDown(h.close);
      await h.controller.prepare();
      h.signer.gate = Completer<String>();
      final pending = h.controller.confirm();
      h.now = proofChallenge().expiresAt;
      h.signer.gate!.complete('late-signature');
      await pending;
      expect(h.client.verified, 0);
      expect(h.controller.failure, WalletPossessionFailure.challengeExpired);
    },
  );

  test('a cancelled submitted proof cannot report late success', () async {
    final h = ProofHarness();
    addTearDown(h.close);
    await h.controller.prepare();
    h.client.verifyGate = Completer<WalletPossessionReceipt>();
    final pending = h.controller.confirm();
    await flush();
    expect(h.client.verified, 1);
    h.controller.cancel();
    await pending;
    h.client.verifyGate!.complete(h.client.receipt(proofChallenge()));
    await flush();
    expect(h.controller.phase, WalletPossessionPhase.cancelled);
    expect(h.controller.receipt, isNull);
  });

  for (final status in ['missing', 'ambiguous']) {
    test('$status linked wallet prevents challenge and signing', () async {
      final h = ProofHarness();
      addTearDown(h.close);
      h.context = proofContext(missingStatus: status);
      await h.controller.prepare();
      expect(h.client.issued, 0);
      expect(h.signer.messages, isEmpty);
      expect(
        h.controller.failure,
        status == 'missing'
            ? WalletPossessionFailure.walletMissing
            : WalletPossessionFailure.walletAmbiguous,
      );
    });
  }

  test('a timeout drops a native result without submitting it later', () async {
    final h = ProofHarness(timeout: const Duration(milliseconds: 10));
    addTearDown(h.close);
    await h.controller.prepare();
    h.signer.gate = Completer<String>();
    await h.controller.confirm();
    expect(h.controller.failure, WalletPossessionFailure.timeout);
    h.signer.gate!.complete('late-signature');
    await flush();
    expect(h.client.verified, 0);
  });

  test(
    'unknown native errors never become UI diagnostics or success',
    () async {
      final h = ProofHarness();
      addTearDown(h.close);
      await h.controller.prepare();
      h.signer.error = StateError('PRIVATE_PROVIDER_ERROR');
      await h.controller.confirm();
      expect(h.controller.failure, WalletPossessionFailure.unavailable);
      expect(h.client.verified, 0);
    },
  );
}
