/// Account-bound creation of one embedded Solana wallet. This capability never
/// requests a signature, a payment, or an additional wallet.
abstract interface class WalletSetup {
  Future<String> ensureSolanaWallet({required String expectedSubject});
}

enum WalletSetupFailure {
  unavailable,
  busy,
  accountChanged,
  multipleWallets,
  invalidWallet,
}

class WalletSetupException implements Exception {
  const WalletSetupException(this.failure);
  final WalletSetupFailure failure;
  @override
  String toString() => 'WalletSetupException(${failure.name})';
}

enum WalletSetupOutcome { ready, awaitingServer, unavailable, accountChanged }
