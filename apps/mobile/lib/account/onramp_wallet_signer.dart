import 'dart:convert';

/// Message-only wallet ownership proof. This interface cannot sign transactions.
abstract interface class OnrampWalletSigner {
  Future<String> signOnrampOwnership({
    required String expectedSubject,
    required OnrampWalletChallenge challenge,
  });
}

class OnrampWalletChallenge {
  OnrampWalletChallenge._(this.wallet, this.message);
  final String wallet, message;
  factory OnrampWalletChallenge.parse({
    required String wallet,
    required String message,
  }) {
    if (wallet.length < 32 ||
        wallet.length > 44 ||
        message.length > 4096 ||
        !message.startsWith('crossmint.com wants you to sign in with your ') ||
        !message.split('\n').contains(wallet)) {
      throw const FormatException('Invalid Crossmint wallet challenge');
    }
    return OnrampWalletChallenge._(wallet, message);
  }
}

String checkedOnrampSignature(String value) {
  if (value.length != 88 ||
      base64Decode(value).length != 64 ||
      base64Encode(base64Decode(value)) != value) {
    throw const FormatException('Invalid wallet signature');
  }
  return value;
}
