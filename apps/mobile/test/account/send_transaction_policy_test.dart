import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:solana/base58.dart';
import 'package:trimmy/account/reviewed_transaction.dart';
import 'package:trimmy/account/send_transaction_policy.dart';
import 'package:trimmy/account/wallet_trade_signer.dart';

void main() {
  final fixtures =
      jsonDecode(
            File(
              '../../tool/testing/fixtures/client-send-policy.json',
            ).readAsStringSync(),
          )
          as List;
  for (final fixture in fixtures) {
    test('offline send policy: ${fixture['name']}', () async {
      final envelope = fixture['envelope'] as Map,
          review = envelope['review'] as Map,
          asset = review['asset'] as Map;
      final work = checkSendTransaction(
        transaction: envelope['unsignedTransaction'],
        from: review['from'],
        destination: review['destination'],
        assetId: asset['kind'] == 'sol'
            ? 'SOL'
            : asset['symbol'] == 'USDC'
            ? 'USDC'
            : asset['mint'],
        decimals: asset['decimals'],
        amountRaw: review['amountRaw'],
        receivedRaw: review['receivedRaw'],
        createsAccount: review['createsAccount'],
        networkFeeLamports: review['networkFeeLamports'],
        accountRentLamports: review['accountRentLamports'],
      );
      if (fixture['accepted'] == true) {
        await work;
      } else {
        await expectLater(work, throwsA(isA<WalletTradeException>()));
      }
    });
  }
  test(
    'the native signing boundary verifies the wallet signature and unchanged message',
    () async {
      final algorithm = Ed25519(),
          key = await Ed25519().newKeyPairFromSeed(List.filled(32, 7));
      final public = await key.extractPublicKey(),
          wallet = base58encode((await key.extractPublicKey()).bytes);
      final bytes = base64Decode(
        fixtures.first['envelope']['unsignedTransaction'],
      );
      // v0: one signature, header, then compact static-key count. Replace only test fee-payer key.
      bytes.setRange(70, 102, public.bytes);
      final plan = ReviewedTransaction.parse(base64Encode(bytes), wallet);
      final signature = await algorithm.sign(plan.message, keyPair: key);
      final signed = bytes.toList();
      signed.setRange(1, 65, signature.bytes);
      await plan.verifySigned(base64Encode(signed), wallet);
      final altered = [...signed];
      altered[altered.length - 2] ^= 1;
      await expectLater(
        plan.verifySigned(base64Encode(altered), wallet),
        throwsA(isA<WalletTradeException>()),
      );
      final invalidSignature = [...signed];
      invalidSignature[3] ^= 1;
      await expectLater(
        plan.verifySigned(base64Encode(invalidSignature), wallet),
        throwsA(isA<WalletTradeException>()),
      );
      await expectLater(
        plan.verifySigned(base64Encode(bytes), wallet),
        throwsA(isA<WalletTradeException>()),
      );
    },
  );
  test(
    'RFQ signing preserves the empty maker slot and signs only the user slot',
    () async {
      final algorithm = Ed25519();
      final key = await algorithm.newKeyPairFromSeed(List.filled(32, 11));
      final public = await key.extractPublicKey();
      final wallet = base58encode(public.bytes);
      final maker = base58decode(
        '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM',
      );
      final message = <int>[
        128,
        2,
        0,
        1,
        3,
        ...maker,
        ...public.bytes,
        ...List.filled(32, 0),
        ...List.filled(32, 9),
        1,
        2,
        2,
        1,
        0,
        12,
        2,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ];
      final bytes = <int>[2, ...List.filled(128, 0), ...message];
      final plan = ReviewedTransaction.parse(base64Encode(bytes), wallet);
      expect(plan.signerSlot, 1);
      final signature = await algorithm.sign(plan.message, keyPair: key);
      final signed = [...bytes]..setRange(65, 129, signature.bytes);
      await plan.verifySigned(base64Encode(signed), wallet);
      final changedMaker = [...signed]..[1] = 1;
      await expectLater(
        plan.verifySigned(base64Encode(changedMaker), wallet),
        throwsA(isA<WalletTradeException>()),
      );
      expect(
        () => ReviewedTransaction.parse(base64Encode(signed), wallet),
        throwsA(isA<WalletTradeException>()),
      );
      expect(
        () =>
            ReviewedTransaction.parse(base64Encode(bytes), base58encode(maker)),
        throwsA(isA<WalletTradeException>()),
      );
    },
  );
}
