import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An external funding source. This never replaces the account's Privy wallet.
class MobileWalletAccount {
  const MobileWalletAccount({required this.address, this.label});
  final String address;
  final String? label;
}

class MobileWalletPendingOperation {
  const MobileWalletPendingOperation({
    required this.address,
    required this.requestHash,
    this.signature,
  });
  final String address;
  final String requestHash;
  final String? signature;
}

class MobileWalletException implements Exception {
  const MobileWalletException(this.code);
  final String code;
  @override
  String toString() => code;
}

abstract interface class MobileWalletService {
  bool get available;
  Future<MobileWalletAccount> connect();
  Future<String> signAndSend({
    required String address,
    required String unsignedTransaction,
  });
  Future<void> disconnect();
  Future<MobileWalletPendingOperation?> getPendingOperation();

  /// Only after the user explicitly checks the source wallet. The old wire
  /// remains blocked; the next attempt needs a fresh review and wallet approval.
  Future<void> acknowledgeUnknownOutcome({required String requestHash});

  /// Only after the API verifies the exact incoming transfer's terminal result.
  Future<void> resolvePending({
    required String requestHash,
    required String signature,
  });
}

class MethodChannelMobileWalletService implements MobileWalletService {
  const MethodChannelMobileWalletService({
    this.channel = const MethodChannel('com.trimmy.trimmy/mobile_wallet'),
    this.supported,
  });

  final MethodChannel channel;
  final bool? supported;
  static final _address = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
  static final _signature = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{64,88}$');
  static final _hash = RegExp(r'^[a-f0-9]{64}$');

  @override
  bool get available =>
      supported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<Object?> _call(String method, [Map<String, Object>? arguments]) async {
    if (!available) {
      throw const MobileWalletException('MOBILE_WALLET_UNSUPPORTED');
    }
    try {
      return await channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      throw const MobileWalletException('MOBILE_WALLET_UNSUPPORTED');
    } on PlatformException catch (error) {
      // Native error text/details can contain provider internals. Expose codes
      // only, and conservatively treat an unknown send result as uncertain.
      throw MobileWalletException(
        error.code.startsWith('MOBILE_WALLET_')
            ? error.code
            : method == 'signAndSend'
            ? 'MOBILE_WALLET_OUTCOME_UNKNOWN'
            : 'MOBILE_WALLET_UNAVAILABLE',
      );
    }
  }

  @override
  Future<MobileWalletAccount> connect() async {
    final value = await _call('connect');
    if (value is! Map ||
        value['address'] is! String ||
        !_address.hasMatch(value['address'] as String)) {
      throw const MobileWalletException('MOBILE_WALLET_UNAVAILABLE');
    }
    final label = value['label'];
    return MobileWalletAccount(
      address: value['address'] as String,
      label: label is String && label.length <= 80 ? label : null,
    );
  }

  @override
  Future<String> signAndSend({
    required String address,
    required String unsignedTransaction,
  }) async {
    if (!_address.hasMatch(address) || unsignedTransaction.length > 1644) {
      throw const MobileWalletException('MOBILE_WALLET_INVALID_TRANSACTION');
    }
    try {
      final bytes = base64Decode(unsignedTransaction);
      if (bytes.length < 134 || bytes.length > 1232) {
        throw const FormatException();
      }
    } on FormatException {
      throw const MobileWalletException('MOBILE_WALLET_INVALID_TRANSACTION');
    }
    final value = await _call('signAndSend', {
      'address': address,
      'unsignedTransaction': unsignedTransaction,
    });
    if (value is! Map ||
        value['signature'] is! String ||
        !_signature.hasMatch(value['signature'] as String)) {
      throw const MobileWalletException('MOBILE_WALLET_OUTCOME_UNKNOWN');
    }
    return value['signature'] as String;
  }

  @override
  Future<void> disconnect() async {
    await _call('disconnect');
  }

  @override
  Future<MobileWalletPendingOperation?> getPendingOperation() async {
    final value = await _call('getPendingOperation');
    if (value == null) return null;
    if (value is! Map ||
        value['address'] is! String ||
        !_address.hasMatch(value['address'] as String) ||
        value['requestHash'] is! String ||
        !_hash.hasMatch(value['requestHash'] as String) ||
        (value['signature'] != null &&
            (value['signature'] is! String ||
                !_signature.hasMatch(value['signature'] as String)))) {
      throw const MobileWalletException('MOBILE_WALLET_OUTCOME_UNKNOWN');
    }
    return MobileWalletPendingOperation(
      address: value['address'] as String,
      requestHash: value['requestHash'] as String,
      signature: value['signature'] as String?,
    );
  }

  @override
  Future<void> acknowledgeUnknownOutcome({required String requestHash}) async {
    if (!_hash.hasMatch(requestHash)) {
      throw const MobileWalletException('MOBILE_WALLET_INVALID_REQUEST');
    }
    await _call('acknowledgeUnknownOutcome', {'requestHash': requestHash});
  }

  @override
  Future<void> resolvePending({
    required String requestHash,
    required String signature,
  }) async {
    if (!_hash.hasMatch(requestHash) || !_signature.hasMatch(signature)) {
      throw const MobileWalletException('MOBILE_WALLET_INVALID_REQUEST');
    }
    await _call('resolvePending', {
      'requestHash': requestHash,
      'signature': signature,
    });
  }
}
