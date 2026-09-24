import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/account_data.dart';

import 'support/account_data_fixtures.dart';

Matcher fails([
  AccountDataFailure failure = AccountDataFailure.invalidResponse,
]) => throwsA(
  isA<AccountDataException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void main() {
  test('account context preserves verified identity and wallet candidate', () {
    final value = AccountContextSnapshot.fromEnvelope(
      contextEnvelope(),
      expectedUserId: account.toUpperCase(),
    );
    expect(value.userId, account);
    expect(value.xIdentity.status, AccountXIdentityStatus.verified);
    expect(value.xIdentity.subject, '18446744073709551615');
    expect(value.xIdentity.usernameSnapshot, 'trimmyhq');
    expect(value.xIdentity.verifiedAtUnixSeconds, 1757845200);
    expect(value.embeddedSolanaWallet.isCandidate, isTrue);
    expect(value.embeddedSolanaWallet.address, wallet);
  });

  test('account context keeps missing and ambiguous states explicit', () {
    final missing = AccountContextSnapshot.fromEnvelope(
      contextEnvelope(
        xIdentity: {'status': 'missing'},
        embeddedWallet: {'status': 'ambiguous'},
      ),
      expectedUserId: account,
    );
    expect(missing.xIdentity.status, AccountXIdentityStatus.missing);
    expect(missing.xIdentity.subject, isNull);
    expect(
      missing.embeddedSolanaWallet.status,
      EmbeddedSolanaWalletStatus.ambiguous,
    );

    final inverse = AccountContextSnapshot.fromEnvelope(
      contextEnvelope(
        xIdentity: {'status': 'ambiguous'},
        embeddedWallet: {'status': 'missing'},
      ),
      expectedUserId: account,
    );
    expect(inverse.xIdentity.status, AccountXIdentityStatus.ambiguous);
    expect(
      inverse.embeddedSolanaWallet.status,
      EmbeddedSolanaWalletStatus.missing,
    );
  });

  test(
    'account context rejects overclaims, malformed IDs and account drift',
    () {
      final cases = <Map<String, Object?>>[
        {...contextEnvelope(), 'private': 'secret'},
        {...contextEnvelope(), 'schemaVersion': 1.0},
        {...contextEnvelope(), 'userId': account.toUpperCase()},
        contextEnvelope(
          xIdentity: {
            'status': 'verified',
            'subject': 123,
            'usernameSnapshot': 'trimmyhq',
            'verifiedAtUnixSeconds': 1757845200,
          },
        ),
        contextEnvelope(
          xIdentity: {
            'status': 'verified',
            'subject': '18446744073709551616',
            'usernameSnapshot': 'trimmyhq',
            'verifiedAtUnixSeconds': 1757845200,
          },
        ),
        contextEnvelope(
          xIdentity: {
            'status': 'verified',
            'subject': '123',
            'usernameSnapshot': 'TrimmyHQ',
            'verifiedAtUnixSeconds': 1757845200,
          },
        ),
        contextEnvelope(
          embeddedWallet: {
            'status': 'candidate',
            'address': '11111111111111111111111111111111',
            'verifiedAtUnixSeconds': 1757845201,
          },
        ),
        contextEnvelope(
          embeddedWallet: {
            'status': 'candidate',
            'address': wallet,
            'verifiedAtUnixSeconds': 0,
            'delegated': true,
          },
        ),
      ];
      for (var index = 0; index < cases.length; index++) {
        final value = cases[index];
        expect(
          () => AccountContextSnapshot.fromEnvelope(
            value,
            expectedUserId: account,
          ),
          fails(),
          reason: 'case $index: $value',
        );
      }
      expect(
        () => AccountContextSnapshot.fromEnvelope(
          contextEnvelope(),
          expectedUserId: otherAccount,
        ),
        fails(AccountDataFailure.accountMismatch),
      );
    },
  );

  test(
    'holdings preserve u64 strings and expose non-atomic read-only facts',
    () {
      final value = AccountHoldingsSnapshot.fromEnvelope(
        holdingsEnvelope(),
        expectedUserId: account,
      );
      expect(value.wallet.address, wallet);
      expect(value.wallet.possessionSignatureVerified, isFalse);
      expect(value.network, 'solana:mainnet-beta');
      expect(value.observedAt.toIso8601String(), '2026-09-14T17:28:27.109Z');
      expect(value.nativeSol.amountRaw, '9007199254740991');
      expect(value.usdc.amountRaw, '18446744073709551615');
      expect(
        value.usdc.accountTopology,
        TokenAccountTopology.associatedWithAncillary,
      );
      expect(value.usdc.hasFrozenAccounts, isTrue);
      expect(value.aaplx.amountRaw, '9007199254741000');
      expect(value.aaplx.displayAmount, isNull);
      expect(value.aaplx.shareAmount, isNull);
      expect(value.aaplx.executionEnabled, isFalse);
      expect(value.readOnly, isTrue);
      expect(value.atomic, isFalse);
      expect(value.transactionBuilt, isFalse);
      expect(value.transactionSigned, isFalse);
      expect(value.transactionBroadcast, isFalse);
    },
  );

  test('zero token holdings keep exact strings and no-account topology', () {
    final envelope = holdingsEnvelope();
    final holdings = envelope['holdings'] as Map<String, Object?>;
    final balances = holdings['balances'] as Map<String, Object?>;
    for (final key in ['usdc', 'aaplx']) {
      final token = balances[key] as Map<String, Object?>;
      token['amountRaw'] = '0';
      token['accountCount'] = 0;
      token['accountTopology'] = 'none';
      token['hasFrozenAccounts'] = false;
    }
    final value = AccountHoldingsSnapshot.fromEnvelope(
      envelope,
      expectedUserId: account,
    );
    expect(value.usdc.amountRaw, '0');
    expect(value.aaplx.amountRaw, '0');
    expect(value.usdc.accountTopology, TokenAccountTopology.none);
    expect(value.aaplx.accountTopology, TokenAccountTopology.none);
  });

  test(
    'holdings reject raw-number coercion, changed pins and unsafe flags',
    () {
      final cases = <Map<String, Object?>>[];

      Map<String, Object?> changed(void Function(Map<String, dynamic>) update) {
        final value = holdingsEnvelope();
        update(value.cast<String, dynamic>());
        return value;
      }

      cases.add(changed((value) => value['private'] = 'secret'));
      cases.add(changed((value) => value['schemaVersion'] = 1.0));
      cases.add(changed((value) => value['userId'] = account.toUpperCase()));
      cases.add(
        changed((value) {
          final holdings = value['holdings'] as Map<String, Object?>;
          holdings['network'] = 'solana:devnet';
        }),
      );
      cases.add(
        changed((value) {
          final holdings = value['holdings'] as Map<String, Object?>;
          holdings['transactionBuilt'] = true;
        }),
      );
      cases.add(
        changed((value) {
          final holdings = value['holdings'] as Map<String, Object?>;
          holdings['observedAt'] = '2026-09-14T17:28:27.109+00:00';
        }),
      );
      cases.add(
        changed((value) {
          final holdings = value['holdings'] as Map<String, Object?>;
          final balances = holdings['balances'] as Map<String, Object?>;
          final nativeSol = balances['nativeSol'] as Map<String, Object?>;
          nativeSol['amountRaw'] = '9007199254740992';
        }),
      );
      cases.add(
        changed((value) {
          final holdings = value['holdings'] as Map<String, Object?>;
          final balances = holdings['balances'] as Map<String, Object?>;
          final usdc = balances['usdc'] as Map<String, Object?>;
          usdc['amountRaw'] = BigInt.parse('18446744073709551615');
        }),
      );
      cases.add(
        changed((value) {
          final holdings = value['holdings'] as Map<String, Object?>;
          final balances = holdings['balances'] as Map<String, Object?>;
          final usdc = balances['usdc'] as Map<String, Object?>;
          usdc['amountRaw'] = '01';
        }),
      );
      cases.add(
        changed((value) {
          final holdings = value['holdings'] as Map<String, Object?>;
          final balances = holdings['balances'] as Map<String, Object?>;
          final usdc = balances['usdc'] as Map<String, Object?>;
          usdc['amountRaw'] = '18446744073709551616';
        }),
      );
      cases.add(
        changed((value) {
          final holdings = value['holdings'] as Map<String, Object?>;
          final balances = holdings['balances'] as Map<String, Object?>;
          final usdc = balances['usdc'] as Map<String, Object?>;
          usdc['mint'] = wallet;
        }),
      );
      cases.add(
        changed((value) {
          final holdings = value['holdings'] as Map<String, Object?>;
          final balances = holdings['balances'] as Map<String, Object?>;
          final aaplx = balances['aaplx'] as Map<String, Object?>;
          aaplx['displayAmount'] = '0.01';
        }),
      );
      cases.add(
        changed((value) {
          final walletData = value['wallet'] as Map<String, Object?>;
          walletData['possessionSignatureVerified'] = true;
        }),
      );

      for (var index = 0; index < cases.length; index++) {
        final value = cases[index];
        expect(
          () => AccountHoldingsSnapshot.fromEnvelope(
            value,
            expectedUserId: account,
          ),
          fails(),
          reason: 'case $index: $value',
        );
      }
    },
  );

  test('holdings reject contradictory topology, frozen state and slots', () {
    Map<String, Object?> changed(void Function(Map<String, dynamic>) update) {
      final value = holdingsEnvelope();
      update(value.cast<String, dynamic>());
      return value;
    }

    final cases = [
      changed((value) {
        final holdings = value['holdings'] as Map<String, Object?>;
        final balances = holdings['balances'] as Map<String, Object?>;
        final aaplx = balances['aaplx'] as Map<String, Object?>;
        aaplx['accountCount'] = 0;
        aaplx['accountTopology'] = 'none';
      }),
      changed((value) {
        final holdings = value['holdings'] as Map<String, Object?>;
        final balances = holdings['balances'] as Map<String, Object?>;
        final aaplx = balances['aaplx'] as Map<String, Object?>;
        aaplx['amountRaw'] = '0';
        aaplx['accountCount'] = 0;
        aaplx['accountTopology'] = 'none';
        aaplx['hasFrozenAccounts'] = true;
      }),
      changed((value) {
        final holdings = value['holdings'] as Map<String, Object?>;
        final consistency = holdings['consistency'] as Map<String, Object?>;
        final slots = consistency['slots'] as Map<String, Object?>;
        slots['aaplx'] = 447040362;
      }),
      changed((value) {
        final holdings = value['holdings'] as Map<String, Object?>;
        final consistency = holdings['consistency'] as Map<String, Object?>;
        consistency['atomic'] = true;
      }),
    ];
    for (final value in cases) {
      expect(
        () => AccountHoldingsSnapshot.fromEnvelope(
          value,
          expectedUserId: account,
        ),
        fails(),
      );
    }
    expect(
      () => AccountHoldingsSnapshot.fromEnvelope(
        holdingsEnvelope(),
        expectedUserId: otherAccount,
      ),
      fails(AccountDataFailure.accountMismatch),
    );
  });
}
