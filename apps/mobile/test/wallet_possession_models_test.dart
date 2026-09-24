import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/wallet_possession_models.dart';

Map<String, dynamic> _contract() =>
    jsonDecode(
          File('../../contracts/wallet-possession-v1.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

WalletPossessionChallenge _challenge(
  Map<String, dynamic> contract, [
  Object? envelope,
]) => WalletPossessionChallenge.fromEnvelope(
  envelope ?? contract['challenge'],
  expectedAccountId: contract['account']['userId'] as String,
  expectedWalletAddress: contract['account']['walletAddress'] as String,
);

void main() {
  test(
    'generated real-route challenge and receipt parse without changing signed bytes',
    () {
      final contract = _contract();
      final challenge = _challenge(contract);
      final receipt = WalletPossessionReceipt.fromEnvelope(
        contract['possession'],
        challenge: challenge,
      );
      expect(challenge.message, contract['challenge']['challenge']['message']);
      expect(challenge.message.split('\n'), hasLength(10));
      expect(challenge.accountId, contract['account']['userId']);
      expect(challenge.network, 'mainnet-beta');
      expect(challenge.nonce, '42' * 32);
      expect(
        challenge.isExpired(
          challenge.expiresAt.subtract(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
      expect(challenge.isExpired(challenge.expiresAt), isTrue);
      expect(receipt.challengeId, challenge.challengeId);
      expect(receipt.accountId, challenge.accountId);
      expect(receipt.walletAddress, challenge.walletAddress);
      expect(receipt.possessionSignatureVerified, isTrue);
    },
  );

  test(
    'repeat real-route proof accepts the original durable binding timestamp',
    () {
      final contract = _contract();
      final first = WalletPossessionReceipt.fromEnvelope(
        contract['possession'],
        challenge: _challenge(contract),
      );
      final repeated = _challenge(contract, contract['repeat']['challenge']);
      final receipt = WalletPossessionReceipt.fromEnvelope(
        contract['repeat']['possession'],
        challenge: repeated,
      );
      expect(receipt.bindingId, first.bindingId);
      expect(receipt.bindingVerifiedAt, first.bindingVerifiedAt);
      expect(receipt.bindingVerifiedAt.isBefore(repeated.issuedAt), isTrue);
      expect(receipt.verifiedAt.isAfter(first.verifiedAt), isTrue);
    },
  );

  test(
    'every signed line is fixed and altered headers or scoped fields are refused',
    () {
      for (var index = 0; index < 10; index++) {
        final contract = _contract();
        final data = contract['challenge']['challenge'] as Map<String, dynamic>;
        final lines = (data['message'] as String).split('\n');
        lines[index] = '${lines[index]} extra';
        data['message'] = lines.join('\n');
        expect(
          () => _challenge(contract),
          throwsA(isA<WalletPossessionException>()),
          reason: 'line $index must be exact',
        );
      }
      for (final suffix in ['\n', '\r', '\u0000', '\u200b']) {
        final contract = _contract();
        contract['challenge']['challenge']['message'] += suffix;
        expect(
          () => _challenge(contract),
          throwsA(isA<WalletPossessionException>()),
        );
      }
    },
  );

  test('challenge scope binds exactly to the expected account and wallet', () {
    final contract = _contract();
    expect(
      () => WalletPossessionChallenge.fromEnvelope(
        contract['challenge'],
        expectedAccountId: '40000000-0000-4000-a000-000000000004',
        expectedWalletAddress: contract['account']['walletAddress'] as String,
      ),
      throwsA(
        isA<WalletPossessionException>().having(
          (e) => e.failure,
          'failure',
          WalletPossessionFailure.accountMismatch,
        ),
      ),
    );
    expect(
      () => WalletPossessionChallenge.fromEnvelope(
        contract['challenge'],
        expectedAccountId: contract['account']['userId'] as String,
        expectedWalletAddress: '7pt9tkctJPK7PPNQJ77GKg8ZffSF6QxoMiCFYHxrtaCj',
      ),
      throwsA(
        isA<WalletPossessionException>().having(
          (e) => e.failure,
          'failure',
          WalletPossessionFailure.walletMismatch,
        ),
      ),
    );
  });

  test(
    'network, shape, nonce, canonical dates and lifetime bounds fail closed',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (data) => data['extra'] = true,
        (data) => data.remove('challengeId'),
        (data) => data['network'] = 'devnet',
        (data) => data['challengeId'] = '${data['challengeId']}\n',
        (data) => data['message'] = (data['message'] as String).replaceFirst(
          'nonce: 42',
          'nonce: 4G',
        ),
        (data) => data['issuedAt'] = '2026-09-17T10:00:00Z',
        (data) => data['issuedAt'] = '2026-09-17T10:00:00.000+00:00',
        (data) => data['issuedAt'] = '2026-09-32T10:00:00.000Z',
        (data) => data['expiresAt'] = '2026-09-17T10:00:29.999Z',
        (data) => data['expiresAt'] = '2026-09-17T10:15:00.001Z',
      ]) {
        final contract = _contract();
        mutate(contract['challenge']['challenge'] as Map<String, dynamic>);
        expect(
          () => _challenge(contract),
          throwsA(isA<WalletPossessionException>()),
        );
      }
    },
  );

  test(
    'receipt identity, lifetime and binding shape cannot imply an unrelated proof',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (data) => data['network'] = 'devnet',
        (data) => data['walletAddress'] =
            '7pt9tkctJPK7PPNQJ77GKg8ZffSF6QxoMiCFYHxrtaCj',
        (data) => data['possessionSignatureVerified'] = false,
        (data) => data['kind'] = 'transaction',
        (data) => data['signature'] = 'not a receipt field',
        (data) => data['verifiedAt'] = '2026-09-17T09:59:59.999Z',
        (data) => data['verifiedAt'] = '2026-09-17T10:05:00.000Z',
        (data) => data['binding']['id'] = 'invalid',
        (data) => data['binding']['verifiedAt'] = '2026-09-17T10:00:03.000Z',
      ]) {
        final contract = _contract();
        mutate(contract['possession'] as Map<String, dynamic>);
        expect(
          () => WalletPossessionReceipt.fromEnvelope(
            contract['possession'],
            challenge: _challenge(contract),
          ),
          throwsA(isA<WalletPossessionException>()),
        );
      }
    },
  );

  test(
    'base58 guards require exact nonzero key and signature byte lengths',
    () {
      expect(
        isWalletPossessionAddress(
          _contract()['account']['walletAddress'] as String,
        ),
        isTrue,
      );
      for (final value in [
        '1' * 32,
        '2' * 32,
        '0' * 44,
        '${_contract()['account']['walletAddress']}\n',
      ]) {
        expect(isWalletPossessionAddress(value), isFalse);
      }
      expect(isWalletPossessionSignature('2' * 88), isTrue);
      for (final value in [
        '1' * 64,
        '2' * 64,
        '2' * 128,
        '0' * 88,
        '${'2' * 87}\n',
      ]) {
        expect(isWalletPossessionSignature(value), isFalse);
      }
    },
  );
}
