import 'validation.dart';

const researchAaplxMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const researchUsdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

enum StockEstimateSide { buy, sell }

class StockEstimateRequest {
  const StockEstimateRequest({
    required this.assetId,
    required this.variantMint,
    required this.side,
    required this.amountRaw,
  });
  final String assetId, variantMint, amountRaw;
  final StockEstimateSide side;
  void validate() {
    try {
      if (assetId != 'apple' || variantMint != researchAaplxMint) {
        researchInvalid();
      }
      researchRawAmount(amountRaw);
      if (BigInt.parse(amountRaw) > BigInt.from(100000000)) researchInvalid();
    } catch (_) {
      throw const StockResearchException('MARKET_INPUT_INVALID');
    }
  }

  Map<String, String> get queryParameters => {
    'assetId': assetId,
    'variantMint': variantMint,
    'side': side.name,
    'amountRaw': amountRaw,
  };
  @override
  bool operator ==(Object other) =>
      other is StockEstimateRequest &&
      assetId == other.assetId &&
      variantMint == other.variantMint &&
      side == other.side &&
      amountRaw == other.amountRaw;
  @override
  int get hashCode => Object.hash(assetId, variantMint, side, amountRaw);
}

class StockEstimateInput {
  StockEstimateInput._(this.symbol, this.mint, this.decimals, this.amountRaw);
  factory StockEstimateInput.fromJson(Object? value) {
    final data = researchObject(value, const {
      'symbol',
      'mint',
      'decimals',
      'amountRaw',
    });
    return StockEstimateInput._(
      researchText(data['symbol'], 40),
      researchMint(data['mint']),
      researchInteger(data['decimals'], 0, 255),
      researchRawAmount(data['amountRaw']),
    );
  }
  final String symbol, mint, amountRaw;
  final int decimals;
}

class StockEstimateOutput {
  StockEstimateOutput._(
    this.symbol,
    this.mint,
    this.decimals,
    this.estimatedAmountRaw,
    this.quotedMinimumAmountRaw,
  );
  factory StockEstimateOutput.fromJson(Object? value) {
    final data = researchObject(value, const {
      'symbol',
      'mint',
      'decimals',
      'estimatedAmountRaw',
      'quotedMinimumAmountRaw',
    });
    return StockEstimateOutput._(
      researchText(data['symbol'], 40),
      researchMint(data['mint']),
      researchInteger(data['decimals'], 0, 255),
      researchRawAmount(data['estimatedAmountRaw']),
      researchRawAmount(data['quotedMinimumAmountRaw']),
    );
  }
  final String symbol, mint, estimatedAmountRaw, quotedMinimumAmountRaw;
  final int decimals;
}

class StockEstimate {
  StockEstimate._(
    this.request,
    this.input,
    this.output,
    this.slippageBps,
    this.swapFeeBasisPoints,
    this.swapFeeMint,
    this.router,
    this.requestedAt,
    this.receivedAt,
    this.refreshAfter,
    this.providerExpiresAt,
  );
  factory StockEstimate.fromJson(Object? value) {
    final data = researchObject(value, const {
      'schemaVersion',
      'kind',
      'network',
      'provider',
      'executable',
      'walletChecked',
      'networkFees',
      'input',
      'output',
      'slippageBps',
      'swapFee',
      'router',
      'requestedAt',
      'receivedAt',
      'refreshAfter',
      'providerExpiresAt',
      'assetId',
      'variantMint',
      'side',
      'executionEnabled',
      'eligibility',
      'amountUnits',
    });
    researchSchema(data['schemaVersion']);
    if (data['kind'] != 'indicative' ||
        data['network'] != 'solana:mainnet-beta' ||
        data['provider'] != 'jupiter-swap-v2' ||
        data['executable'] != false ||
        data['walletChecked'] != false ||
        data['networkFees'] != null ||
        data['executionEnabled'] != false ||
        data['eligibility'] != 'unverified' ||
        data['amountUnits'] != 'raw_token_units') {
      researchInvalid();
    }
    final side = StockEstimateSide.values
        .where((side) => side.name == data['side'])
        .firstOrNull;
    if (side == null) researchInvalid();
    final input = StockEstimateInput.fromJson(data['input']);
    final output = StockEstimateOutput.fromJson(data['output']);
    final request = StockEstimateRequest(
      assetId: researchAssetId(data['assetId']),
      variantMint: researchMint(data['variantMint']),
      side: side,
      amountRaw: input.amountRaw,
    );
    if (request.assetId != 'apple' ||
        request.variantMint != researchAaplxMint ||
        BigInt.parse(input.amountRaw) > BigInt.from(100000000)) {
      researchInvalid();
    }
    final buying = side == StockEstimateSide.buy;
    if (input.mint != (buying ? researchUsdcMint : researchAaplxMint) ||
        input.decimals != (buying ? 6 : 8) ||
        input.symbol != (buying ? 'USDC' : 'AAPLx') ||
        output.mint != (buying ? researchAaplxMint : researchUsdcMint) ||
        output.decimals != (buying ? 8 : 6) ||
        output.symbol != (buying ? 'AAPLx' : 'USDC')) {
      researchInvalid();
    }
    final slippage = researchInteger(data['slippageBps'], 0, 10000);
    final amount = BigInt.parse(output.estimatedAmountRaw);
    final minimum = BigInt.parse(output.quotedMinimumAmountRaw);
    if (minimum > amount ||
        minimum <
            amount * BigInt.from(10000 - slippage) ~/ BigInt.from(10000)) {
      researchInvalid();
    }
    final fee = researchObject(data['swapFee'], const {'basisPoints', 'mint'});
    final feeMint = researchMint(fee['mint']);
    if (feeMint != input.mint && feeMint != output.mint) researchInvalid();
    final router = researchText(data['router'], 40);
    if (!const {'metis', 'jupiterz', 'dflow', 'okx'}.contains(router)) {
      researchInvalid();
    }
    final requested = researchTimestamp(data['requestedAt']);
    final received = researchTimestamp(data['receivedAt']);
    final refresh = researchTimestamp(data['refreshAfter']);
    final expires = data['providerExpiresAt'] == null
        ? null
        : researchTimestamp(data['providerExpiresAt']);
    if (DateTime.parse(received).isBefore(DateTime.parse(requested)) ||
        !DateTime.parse(refresh).isAfter(DateTime.parse(received)) ||
        DateTime.parse(refresh).difference(DateTime.parse(requested)) >
            const Duration(seconds: 10) ||
        (expires != null &&
            DateTime.parse(refresh).isAfter(DateTime.parse(expires)))) {
      researchInvalid();
    }
    return StockEstimate._(
      request,
      input,
      output,
      slippage,
      researchInteger(fee['basisPoints'], 0, 10000),
      feeMint,
      router,
      requested,
      received,
      refresh,
      expires,
    );
  }
  final StockEstimateRequest request;
  final StockEstimateInput input;
  final StockEstimateOutput output;
  final int slippageBps, swapFeeBasisPoints;
  final String swapFeeMint, router, requestedAt, receivedAt, refreshAfter;
  final String? providerExpiresAt;
  String get kind => 'indicative';
  String get provider => 'jupiter-swap-v2';
  String get network => 'solana:mainnet-beta';
  String get amountUnits => 'raw_token_units';
  String get eligibility => 'unverified';
  bool get executable => false;
  bool get executionEnabled => false;
  bool get walletChecked => false;
  Object? get networkFees => null;
  bool needsRefresh(DateTime now) =>
      !now.isBefore(DateTime.parse(refreshAfter));
}
