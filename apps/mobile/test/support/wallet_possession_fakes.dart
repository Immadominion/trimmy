import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:trimmy/account/account_data_models.dart';
import 'package:trimmy/account/wallet_possession_client.dart';
import 'package:trimmy/account/wallet_possession_controller.dart';
import 'package:trimmy/account/wallet_possession_signer.dart';

final proofContract =
    jsonDecode(
          File('../../contracts/wallet-possession-v1.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
final proofAccount = proofContract['account'] as Map<String, dynamic>;
final String proofAccountId = proofAccount['userId'];
final String proofWallet = proofAccount['walletAddress'];
final String proofSubject = proofAccount['subject'];

WalletPossessionChallenge proofChallenge() =>
    WalletPossessionChallenge.fromEnvelope(
      proofContract['challenge'],
      expectedAccountId: proofAccountId,
      expectedWalletAddress: proofWallet,
    );

AccountContextSnapshot proofContext({String? missingStatus}) =>
    AccountContextSnapshot.fromEnvelope({
      'schemaVersion': 1,
      'userId': proofAccountId,
      'xIdentity': {'status': 'missing'},
      'embeddedSolanaWallet': missingStatus == null
          ? {
              'status': 'candidate',
              'address': proofWallet,
              'verifiedAtUnixSeconds': 1789639200,
            }
          : {'status': missingStatus},
    }, expectedUserId: proofAccountId);

class ProofClient implements WalletPossessionClient {
  @override
  String get accountId => proofAccountId;
  int issued = 0, verified = 0, cancelled = 0;
  bool closed = false;
  Completer<WalletPossessionChallenge>? issueGate;
  Completer<WalletPossessionReceipt>? verifyGate;
  final addresses = <String>[];
  final signatures = <String>[];
  @override
  Future<WalletPossessionChallenge> issueChallenge({
    required String expectedWalletAddress,
  }) async {
    issued++;
    addresses.add(expectedWalletAddress);
    return issueGate == null ? proofChallenge() : issueGate!.future;
  }

  WalletPossessionReceipt receipt(WalletPossessionChallenge challenge) =>
      WalletPossessionReceipt.fromEnvelope(
        proofContract['possession'],
        challenge: challenge,
      );

  @override
  Future<WalletPossessionReceipt> verify({
    required WalletPossessionChallenge challenge,
    required String signature,
  }) async {
    verified++;
    signatures.add(signature);
    return verifyGate == null ? receipt(challenge) : verifyGate!.future;
  }

  @override
  void cancelPending() => cancelled++;
  @override
  void close() => closed = true;
}

class ProofSigner implements WalletPossessionSigner {
  final subjects = <String>[];
  final messages = <String>[];
  Completer<String>? gate;
  Object? error;
  @override
  Future<String> sign({
    required String expectedSubject,
    required WalletPossessionChallenge challenge,
  }) async {
    subjects.add(expectedSubject);
    messages.add(challenge.message);
    if (error case final error?) throw error;
    return gate == null ? 'synthetic-signature-only' : gate!.future;
  }
}

class ProofHarness {
  ProofHarness({Duration timeout = const Duration(seconds: 90)}) {
    controller = WalletPossessionController(
      client: client,
      signer: signer,
      subject: proofSubject,
      readContext: () async {
        contextReads++;
        return contextGate == null ? context : contextGate!.future;
      },
      cancelContext: () => contextCancels++,
      closeContext: () => contextClosed = true,
      isAccountCurrent: () => accountCurrent,
      now: () => now,
      operationTimeout: timeout,
    );
  }
  final client = ProofClient();
  final signer = ProofSigner();
  DateTime now = proofChallenge().issuedAt.add(const Duration(seconds: 1));
  bool accountCurrent = true, contextClosed = false;
  int contextReads = 0, contextCancels = 0;
  AccountContextSnapshot context = proofContext();
  Completer<AccountContextSnapshot>? contextGate;
  late final WalletPossessionController controller;
  void close() => controller.dispose();
}
