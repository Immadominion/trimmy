import '../practice_sync/protocol.dart';

const _maxSafeInteger = 9007199254740991;
const _maxSafeIntegerString = '9007199254740991';
const _maxU64 = '18446744073709551615';
const _mainnetGenesis = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
const _usdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _aaplxMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';

enum AccountDataFailure {
  invalidConfiguration,
  invalidRequest,
  unauthenticated,
  accountMismatch,
  walletMissing,
  walletAmbiguous,
  unavailable,

  /// The server has no adapter for this read (for example no linked-identity
  /// configuration). Distinct from a transient outage or being offline.
  notConfigured,
  invalidResponse,
  timeout,
  cancelled,
  busy,
  closed,
}

/// Deliberately carries a local category only. Provider messages, bearer
/// tokens, RPC URLs and response bodies never become exception text.
class AccountDataException implements Exception {
  const AccountDataException(this.failure);

  final AccountDataFailure failure;

  @override
  String toString() => 'AccountDataException(${failure.name})';
}

enum AccountXIdentityStatus { missing, ambiguous, verified }

final class AccountXIdentity {
  const AccountXIdentity._({
    required this.status,
    this.subject,
    this.usernameSnapshot,
    this.verifiedAtUnixSeconds,
  });

  final AccountXIdentityStatus status;
  final String? subject;
  final String? usernameSnapshot;
  final int? verifiedAtUnixSeconds;

  bool get isVerified => status == AccountXIdentityStatus.verified;

  static AccountXIdentity _fromJson(Object? value) {
    final data = _object(value);
    final status = data['status'];
    if (status == 'missing' || status == 'ambiguous') {
      _exactKeys(data, const {'status'});
      return AccountXIdentity._(
        status: status == 'missing'
            ? AccountXIdentityStatus.missing
            : AccountXIdentityStatus.ambiguous,
      );
    }
    _exactKeys(data, const {
      'status',
      'subject',
      'usernameSnapshot',
      'verifiedAtUnixSeconds',
    });
    final subject = data['subject'];
    final username = data['usernameSnapshot'];
    final verifiedAt = data['verifiedAtUnixSeconds'];
    if (status != 'verified' ||
        subject is! String ||
        !_unsignedDecimal(subject, max: _maxU64, allowZero: false) ||
        username is! String ||
        !_exactMatch(RegExp(r'[a-z0-9_]{1,15}'), username) ||
        !_positiveSafeInteger(verifiedAt)) {
      invalidAccountDataResponse();
    }
    return AccountXIdentity._(
      status: AccountXIdentityStatus.verified,
      subject: subject,
      usernameSnapshot: username,
      verifiedAtUnixSeconds: verifiedAt,
    );
  }
}

enum EmbeddedSolanaWalletStatus { missing, ambiguous, candidate }

final class EmbeddedSolanaWallet {
  const EmbeddedSolanaWallet._({
    required this.status,
    this.address,
    this.verifiedAtUnixSeconds,
  });

  final EmbeddedSolanaWalletStatus status;
  final String? address;
  final int? verifiedAtUnixSeconds;

  bool get isCandidate => status == EmbeddedSolanaWalletStatus.candidate;

  static EmbeddedSolanaWallet _fromJson(Object? value) {
    final data = _object(value);
    final status = data['status'];
    if (status == 'missing' || status == 'ambiguous') {
      _exactKeys(data, const {'status'});
      return EmbeddedSolanaWallet._(
        status: status == 'missing'
            ? EmbeddedSolanaWalletStatus.missing
            : EmbeddedSolanaWalletStatus.ambiguous,
      );
    }
    _exactKeys(data, const {'status', 'address', 'verifiedAtUnixSeconds'});
    final address = data['address'];
    final verifiedAt = data['verifiedAtUnixSeconds'];
    if (status != 'candidate' ||
        address is! String ||
        !_validNonzeroSolanaAddress(address) ||
        !_positiveSafeInteger(verifiedAt)) {
      invalidAccountDataResponse();
    }
    return EmbeddedSolanaWallet._(
      status: EmbeddedSolanaWalletStatus.candidate,
      address: address,
      verifiedAtUnixSeconds: verifiedAt,
    );
  }
}

final class AccountContextSnapshot {
  const AccountContextSnapshot._({
    required this.userId,
    required this.xIdentity,
    required this.embeddedSolanaWallet,
  });

  final String userId;
  final AccountXIdentity xIdentity;
  final EmbeddedSolanaWallet embeddedSolanaWallet;

  factory AccountContextSnapshot.fromEnvelope(
    Object? value, {
    required String expectedUserId,
  }) {
    final data = _object(value);
    _exactKeys(data, const {
      'schemaVersion',
      'userId',
      'xIdentity',
      'embeddedSolanaWallet',
    });
    final userId = _boundUserId(data['userId'], expectedUserId);
    if (data['schemaVersion'] is! int || data['schemaVersion'] != 1) {
      invalidAccountDataResponse();
    }
    return AccountContextSnapshot._(
      userId: userId,
      xIdentity: AccountXIdentity._fromJson(data['xIdentity']),
      embeddedSolanaWallet: EmbeddedSolanaWallet._fromJson(
        data['embeddedSolanaWallet'],
      ),
    );
  }
}

enum TokenAccountTopology {
  none,
  associatedOnly,
  associatedWithAncillary,
  ancillaryOnly,
  multipleAncillary,
}

final class NativeSolBalance {
  const NativeSolBalance._({
    required this.amountRaw,
    required this.observedSlot,
  });

  final String amountRaw;
  final int observedSlot;
  String get symbol => 'SOL';
  int get decimals => 9;
  String get amountUnits => 'lamports';

  static NativeSolBalance _fromJson(Object? value) {
    final data = _object(value);
    _exactKeys(data, const {
      'symbol',
      'decimals',
      'amountRaw',
      'amountUnits',
      'observedSlot',
    });
    final amount = data['amountRaw'];
    final slot = data['observedSlot'];
    if (data['symbol'] != 'SOL' ||
        data['decimals'] is! int ||
        data['decimals'] != 9 ||
        amount is! String ||
        !_unsignedDecimal(amount, max: _maxSafeIntegerString) ||
        data['amountUnits'] != 'lamports' ||
        !_safeInteger(slot)) {
      invalidAccountDataResponse();
    }
    return NativeSolBalance._(amountRaw: amount, observedSlot: slot);
  }
}

final class StockTokenBalance {
  const StockTokenBalance._({
    required this.symbol,
    required this.mint,
    required this.decimals,
    required this.amountRaw,
    required this.observedSlot,
    required this.accountCount,
    required this.accountTopology,
    required this.hasFrozenAccounts,
    required this.availableToTradeRaw,
  });

  final String symbol;
  final String mint;
  final int decimals;
  final String amountRaw;
  final int observedSlot;
  final int accountCount;
  final TokenAccountTopology accountTopology;
  final bool hasFrozenAccounts;
  final String availableToTradeRaw;
  String get amountUnits => 'raw_token_units';
  String get aggregation => 'all_valid_owner_token_accounts';

  static StockTokenBalance _fromJson(
    Object? value, {
    required String symbol,
    required String mint,
    required int decimals,
    bool requireAvailability = false,
  }) {
    final data = _object(value);
    _exactKeys(data, {
      'symbol',
      'mint',
      'decimals',
      'amountRaw',
      'amountUnits',
      'observedSlot',
      'accountCount',
      'accountTopology',
      'aggregation',
      'hasFrozenAccounts',
      if (requireAvailability) 'availableToTradeRaw',
    });
    return _parseTokenFields(
      data,
      symbol: symbol,
      mint: mint,
      decimals: decimals,
    );
  }
}

final class AaplxTokenBalance {
  const AaplxTokenBalance._(this._raw);

  final StockTokenBalance _raw;

  String get symbol => _raw.symbol;
  String get mint => _raw.mint;
  int get decimals => _raw.decimals;
  String get amountRaw => _raw.amountRaw;
  int get observedSlot => _raw.observedSlot;
  int get accountCount => _raw.accountCount;
  TokenAccountTopology get accountTopology => _raw.accountTopology;
  bool get hasFrozenAccounts => _raw.hasFrozenAccounts;
  String get amountUnits => _raw.amountUnits;
  String get aggregation => _raw.aggregation;
  String get displayResolution => 'token_2022_scaled_ui_unresolved';
  String? get displayAmount => null;
  String? get shareAmount => null;
  String get eligibility => 'unverified';
  bool get executionEnabled => false;

  static AaplxTokenBalance _fromJson(Object? value) {
    final data = _object(value);
    _exactKeys(data, const {
      'symbol',
      'mint',
      'decimals',
      'amountRaw',
      'amountUnits',
      'observedSlot',
      'accountCount',
      'accountTopology',
      'aggregation',
      'hasFrozenAccounts',
      'displayResolution',
      'displayAmount',
      'shareAmount',
      'eligibility',
      'executionEnabled',
    });
    if (data['displayResolution'] != 'token_2022_scaled_ui_unresolved' ||
        data['displayAmount'] != null ||
        data['shareAmount'] != null ||
        data['eligibility'] != 'unverified' ||
        data['executionEnabled'] != false) {
      invalidAccountDataResponse();
    }
    return AaplxTokenBalance._(
      _parseTokenFields(data, symbol: 'AAPLx', mint: _aaplxMint, decimals: 8),
    );
  }
}

/// An observed stock balance. RPC display amounts may include a Token-2022
/// multiplier, so trading uses [amountRaw] and never a rounded display value.
final class WalletStockBalance {
  const WalletStockBalance._(
    this._balance, {
    required this.assetId,
    required this.name,
    required this.displayAmount,
  });

  final String assetId;
  final String name;
  final StockTokenBalance _balance;
  final String? displayAmount;
  String get symbol => _balance.symbol;
  String get mint => _balance.mint;
  int get decimals => _balance.decimals;
  String get amountRaw => _balance.amountRaw;
  String get availableToTradeRaw => _balance.availableToTradeRaw;
  int get observedSlot => _balance.observedSlot;
  int get accountCount => _balance.accountCount;
  TokenAccountTopology get accountTopology => _balance.accountTopology;
  bool get hasFrozenAccounts => _balance.hasFrozenAccounts;
  String get displayUnits => 'token_units';

  /// Exact base token units, without grouping separators. This is suitable for
  /// an amount field; [displayAmount] is only for portfolio presentation.
  String get rawTokenUnits {
    if (decimals == 0) return amountRaw;
    final padded = amountRaw.padLeft(decimals + 1, '0');
    final whole = padded.substring(0, padded.length - decimals);
    final fraction = padded
        .substring(padded.length - decimals)
        .replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? whole : '$whole.$fraction';
  }

  static WalletStockBalance _fromLegacy(AaplxTokenBalance value) =>
      WalletStockBalance._(
        value._raw,
        assetId: 'apple',
        name: 'Apple',
        displayAmount: null,
      );

  static WalletStockBalance _fromJson(Object? value) {
    final data = _object(value);
    _exactKeys(data, const {
      'assetId',
      'name',
      'symbol',
      'mint',
      'decimals',
      'amountRaw',
      'availableToTradeRaw',
      'amountUnits',
      'observedSlot',
      'accountCount',
      'accountTopology',
      'aggregation',
      'hasFrozenAccounts',
      'displayAmount',
      'displayResolution',
      'displayUnits',
    });
    final assetId = data['assetId'];
    final name = data['name'];
    final symbol = data['symbol'];
    final mint = data['mint'];
    final decimals = data['decimals'];
    final display = data['displayAmount'];
    if (assetId is! String ||
        !_exactMatch(RegExp(r'[a-z0-9][a-z0-9_-]{0,127}'), assetId) ||
        name is! String ||
        name.isEmpty ||
        name.length > 160 ||
        name.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        symbol is! String ||
        symbol.isEmpty ||
        symbol.length > 32 ||
        symbol.contains(RegExp(r'[\x00-\x20\x7f]')) ||
        mint is! String ||
        !_validNonzeroSolanaAddress(mint) ||
        mint == _usdcMint ||
        decimals is! int ||
        decimals < 0 ||
        decimals > 18 ||
        data['amountRaw'] == '0' ||
        data['displayUnits'] != 'token_units' ||
        (display == null
            ? data['displayResolution'] != 'unavailable'
            : display is! String ||
                  display.length > 80 ||
                  !_exactMatch(
                    RegExp(r'(?:0|[1-9][0-9]*)(?:\.[0-9]+)?'),
                    display,
                  ) ||
                  data['displayResolution'] != 'rpc_ui_amount')) {
      invalidAccountDataResponse();
    }
    return WalletStockBalance._(
      _parseTokenFields(data, symbol: symbol, mint: mint, decimals: decimals),
      assetId: assetId,
      name: name,
      displayAmount: display as String?,
    );
  }
}

StockTokenBalance _parseTokenFields(
  Map<String, dynamic> data, {
  required String symbol,
  required String mint,
  required int decimals,
}) {
  final amount = data['amountRaw'];
  final slot = data['observedSlot'];
  final count = data['accountCount'];
  final rawTopology = data['accountTopology'];
  final topology = switch (rawTopology) {
    'none' => TokenAccountTopology.none,
    'associated_only' => TokenAccountTopology.associatedOnly,
    'associated_with_ancillary' => TokenAccountTopology.associatedWithAncillary,
    'ancillary_only' => TokenAccountTopology.ancillaryOnly,
    'multiple_ancillary' => TokenAccountTopology.multipleAncillary,
    _ => null,
  };
  final available = data.containsKey('availableToTradeRaw')
      ? data['availableToTradeRaw']
      : topology == TokenAccountTopology.associatedOnly &&
            data['hasFrozenAccounts'] == false
      ? amount
      : '0';
  if (data['symbol'] != symbol ||
      data['mint'] != mint ||
      data['decimals'] is! int ||
      data['decimals'] != decimals ||
      amount is! String ||
      !_unsignedDecimal(amount, max: _maxU64) ||
      available is! String ||
      !_unsignedDecimal(available, max: _maxU64) ||
      BigInt.parse(available) > BigInt.parse(amount) ||
      (topology == TokenAccountTopology.none ||
              topology == TokenAccountTopology.ancillaryOnly ||
              topology == TokenAccountTopology.multipleAncillary ||
              (topology == TokenAccountTopology.associatedOnly &&
                  data['hasFrozenAccounts'] == true)) &&
          available != '0' ||
      data['amountUnits'] != 'raw_token_units' ||
      !_safeInteger(slot) ||
      count is! int ||
      count < 0 ||
      count > 128 ||
      topology == null ||
      !_validTopology(topology, count) ||
      data['aggregation'] != 'all_valid_owner_token_accounts' ||
      data['hasFrozenAccounts'] is! bool ||
      count == 0 && (data['hasFrozenAccounts'] != false || amount != '0')) {
    invalidAccountDataResponse();
  }
  return StockTokenBalance._(
    symbol: symbol,
    mint: mint,
    decimals: decimals,
    amountRaw: amount,
    observedSlot: slot,
    accountCount: count,
    accountTopology: topology,
    hasFrozenAccounts: data['hasFrozenAccounts'],
    availableToTradeRaw: available,
  );
}

bool _validTopology(TokenAccountTopology topology, int count) =>
    switch (topology) {
      TokenAccountTopology.none => count == 0,
      TokenAccountTopology.associatedOnly ||
      TokenAccountTopology.ancillaryOnly => count == 1,
      TokenAccountTopology.associatedWithAncillary ||
      TokenAccountTopology.multipleAncillary => count >= 2,
    };

final class AccountHoldingsWallet {
  const AccountHoldingsWallet._(this.address);

  final String address;
  String get source => 'privy_embedded_wallet_same_subject';
  bool get possessionSignatureVerified => false;

  static AccountHoldingsWallet _fromJson(Object? value) {
    final data = _object(value);
    _exactKeys(data, const {
      'address',
      'source',
      'possessionSignatureVerified',
    });
    final address = data['address'];
    if (address is! String ||
        !_validNonzeroSolanaAddress(address) ||
        data['source'] != 'privy_embedded_wallet_same_subject' ||
        data['possessionSignatureVerified'] != false) {
      invalidAccountDataResponse();
    }
    return AccountHoldingsWallet._(address);
  }
}

final class AccountHoldingsSnapshot {
  const AccountHoldingsSnapshot._({
    required this.userId,
    required this.wallet,
    required this.network,
    required this.genesisHash,
    required this.observedAt,
    required this.nativeSol,
    required this.usdc,
    required this.aaplx,
    required this.stockTokens,
  });

  final String userId;
  final AccountHoldingsWallet wallet;
  final String network;
  final String genesisHash;
  final DateTime observedAt;
  final NativeSolBalance nativeSol;
  final StockTokenBalance usdc;
  final AaplxTokenBalance aaplx;
  final List<WalletStockBalance> stockTokens;

  WalletStockBalance? holdingForMint(String mint) {
    for (final token in stockTokens) {
      if (token.mint == mint) return token;
    }
    return null;
  }

  String get commitment => 'confirmed';
  bool get readOnly => true;
  bool get transactionBuilt => false;
  bool get transactionSigned => false;
  bool get transactionBroadcast => false;
  bool get atomic => false;
  String get consistencyKind => 'independent_confirmed_reads';

  factory AccountHoldingsSnapshot.fromEnvelope(
    Object? value, {
    required String expectedUserId,
  }) {
    final envelope = _object(value);
    _exactKeys(envelope, const {
      'schemaVersion',
      'userId',
      'wallet',
      'holdings',
    });
    final version = envelope['schemaVersion'];
    if (version is! int || (version != 1 && version != 2)) {
      invalidAccountDataResponse();
    }
    final userId = _boundUserId(envelope['userId'], expectedUserId);
    final wallet = AccountHoldingsWallet._fromJson(envelope['wallet']);
    final holdings = _object(envelope['holdings']);
    _exactKeys(holdings, const {
      'network',
      'genesisHash',
      'commitment',
      'observedAt',
      'readOnly',
      'transactionBuilt',
      'transactionSigned',
      'transactionBroadcast',
      'balances',
      'consistency',
    });
    final rawTime = holdings['observedAt'];
    if (holdings['network'] != 'solana:mainnet-beta' ||
        holdings['genesisHash'] != _mainnetGenesis ||
        holdings['commitment'] != 'confirmed' ||
        rawTime is! String ||
        holdings['readOnly'] != true ||
        holdings['transactionBuilt'] != false ||
        holdings['transactionSigned'] != false ||
        holdings['transactionBroadcast'] != false) {
      invalidAccountDataResponse();
    }
    final observedAt = _exactUtcMilliseconds(rawTime);
    final balances = _object(holdings['balances']);
    _exactKeys(balances, {
      'nativeSol',
      'usdc',
      'aaplx',
      if (version == 2) 'tokens',
    });
    final nativeSol = NativeSolBalance._fromJson(balances['nativeSol']);
    final usdc = StockTokenBalance._fromJson(
      balances['usdc'],
      symbol: 'USDC',
      mint: _usdcMint,
      decimals: 6,
      requireAvailability: version == 2,
    );
    final aaplx = AaplxTokenBalance._fromJson(balances['aaplx']);
    final List<WalletStockBalance> stockTokens;
    if (version == 2) {
      final tokens = balances['tokens'];
      if (tokens is! List || tokens.length > 256) invalidAccountDataResponse();
      final mints = <String>{};
      stockTokens = List.unmodifiable(
        tokens.map((value) {
          final token = WalletStockBalance._fromJson(value);
          if (!mints.add(token.mint)) invalidAccountDataResponse();
          return token;
        }),
      );
    } else {
      stockTokens = List.unmodifiable([
        if (aaplx.amountRaw != '0') WalletStockBalance._fromLegacy(aaplx),
      ]);
    }
    _validateConsistency(
      holdings['consistency'],
      nativeSol: nativeSol.observedSlot,
      usdc: usdc.observedSlot,
      aaplx: aaplx.observedSlot,
    );
    return AccountHoldingsSnapshot._(
      userId: userId,
      wallet: wallet,
      network: 'solana:mainnet-beta',
      genesisHash: _mainnetGenesis,
      observedAt: observedAt,
      nativeSol: nativeSol,
      usdc: usdc,
      aaplx: aaplx,
      stockTokens: stockTokens,
    );
  }
}

void _validateConsistency(
  Object? value, {
  required int nativeSol,
  required int usdc,
  required int aaplx,
}) {
  final consistency = _object(value);
  _exactKeys(consistency, const {'kind', 'atomic', 'slots'});
  final slots = _object(consistency['slots']);
  _exactKeys(slots, const {'nativeSol', 'usdc', 'aaplx'});
  if (consistency['kind'] != 'independent_confirmed_reads' ||
      consistency['atomic'] != false ||
      slots['nativeSol'] is! int ||
      slots['nativeSol'] != nativeSol ||
      slots['usdc'] is! int ||
      slots['usdc'] != usdc ||
      slots['aaplx'] is! int ||
      slots['aaplx'] != aaplx) {
    invalidAccountDataResponse();
  }
}

String _boundUserId(Object? value, String expected) {
  try {
    final expectedId = normalizePracticeUuid(expected);
    final actual = normalizePracticeUuid(value);
    if (value != actual) invalidAccountDataResponse();
    if (actual != expectedId) {
      throw const AccountDataException(AccountDataFailure.accountMismatch);
    }
    return actual;
  } on AccountDataException {
    rethrow;
  } catch (_) {
    invalidAccountDataResponse();
  }
}

bool _safeInteger(Object? value) =>
    value is int && value >= 0 && value <= _maxSafeInteger;

bool _positiveSafeInteger(Object? value) =>
    value is int && value > 0 && value <= _maxSafeInteger;

bool _unsignedDecimal(
  String value, {
  required String max,
  bool allowZero = true,
}) {
  if (!_exactMatch(RegExp(r'(?:0|[1-9][0-9]{0,19})'), value) ||
      !allowZero && value == '0') {
    return false;
  }
  return value.length < max.length ||
      value.length == max.length && value.compareTo(max) <= 0;
}

bool _exactMatch(RegExp expression, String value) {
  final match = expression.firstMatch(value);
  return match?.start == 0 && match?.end == value.length;
}

DateTime _exactUtcMilliseconds(String value) {
  if (!_exactMatch(
    RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z'),
    value,
  )) {
    invalidAccountDataResponse();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    invalidAccountDataResponse();
  }
  return parsed;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) invalidAccountDataResponse();
  return value;
}

void _exactKeys(Map<String, dynamic> value, Set<String> keys) {
  if (value.length != keys.length || !keys.every(value.containsKey)) {
    invalidAccountDataResponse();
  }
}

bool _validNonzeroSolanaAddress(String value) {
  if (value.length < 32 || value.length > 44) return false;
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  var number = BigInt.zero;
  for (final rune in value.runes) {
    final digit = alphabet.indexOf(String.fromCharCode(rune));
    if (digit < 0) return false;
    number = number * BigInt.from(58) + BigInt.from(digit);
  }
  final payload = <int>[];
  while (number > BigInt.zero) {
    payload.add((number % BigInt.from(256)).toInt());
    number ~/= BigInt.from(256);
  }
  final leadingZeros = value.codeUnits.takeWhile((unit) => unit == 49).length;
  if (leadingZeros + payload.length != 32) return false;
  return payload.any((byte) => byte != 0);
}

Never invalidAccountDataResponse() =>
    throw const AccountDataException(AccountDataFailure.invalidResponse);
