/// A separate capability from the fixed wallet-possession challenge. Callers
/// must obtain explicit approval for the exact reviewed transaction first.
abstract interface class WalletTradeSigner {
  Future<String> signReviewedTransaction({
    required String expectedSubject,
    required String wallet,
    required String transaction,
  });
}

class WalletTradeException implements Exception {
  const WalletTradeException(this.code);
  final String code;
}
