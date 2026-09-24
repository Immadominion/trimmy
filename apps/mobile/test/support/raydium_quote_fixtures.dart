import 'dart:convert';

import 'package:trimmy/markets/raydium_quotes.dart';

const raydiumQuotePool = 'ApniVWuZbZoruTAJdyJcLBA4AVw4DKGdV5fHxo6qrAZT';

const raydiumBuyRequest = RaydiumQuoteRequest.appleAaplx(
  side: RaydiumQuoteSide.buy,
  amountRaw: '10000000',
);

const raydiumSellRequest = RaydiumQuoteRequest.appleAaplx(
  side: RaydiumQuoteSide.sell,
  amountRaw: '2978849',
);

Map<String, Object?> raydiumQuotePayload({
  RaydiumQuoteRequest request = raydiumBuyRequest,
  String? estimatedAmountRaw,
  String? minimumAmountRaw,
  String? providerActualAmountRaw,
  String feeAmountRaw = '10000',
  String? feeMint,
}) {
  final buying = request.side == RaydiumQuoteSide.buy;
  final inputMint = buying ? raydiumQuoteUsdcMint : raydiumQuoteAaplxMint;
  final outputMint = buying ? raydiumQuoteAaplxMint : raydiumQuoteUsdcMint;
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'indicative',
    'comparisonOnly': true,
    'network': 'solana:mainnet-beta',
    'provider': 'raydium-trade-api',
    'providerResponseVersion': 'V1',
    'providerEndpoint': 'compute/swap-base-in',
    'quoteMode': 'BaseIn',
    'transactionVersionRequested': 'V0',
    'assetId': request.assetId,
    'variantMint': request.variantMint,
    'side': request.side.name,
    'executionEnabled': false,
    'executable': false,
    'eligibility': 'unverified',
    'walletChecked': false,
    'networkFees': null,
    'amountUnits': 'raw_token_units',
    'input': <String, Object?>{
      'symbol': buying ? 'USDC' : 'AAPLx',
      'mint': inputMint,
      'decimals': buying ? 6 : 8,
      'amountRaw': request.amountRaw,
      'providerActualAmountRaw': providerActualAmountRaw ?? request.amountRaw,
    },
    'output': <String, Object?>{
      'symbol': buying ? 'AAPLx' : 'USDC',
      'mint': outputMint,
      'decimals': buying ? 8 : 6,
      'estimatedAmountRaw':
          estimatedAmountRaw ?? (buying ? '2978849' : '9988901'),
      'quotedMinimumAmountRaw':
          minimumAmountRaw ?? (buying ? '2963954' : '9938956'),
    },
    'slippageBps': 50,
    'priceImpactPct': 0.12,
    'referralAmountRaw': '0',
    'route': <String, Object?>{
      'hopCount': 1,
      'hops': <Object?>[
        <String, Object?>{
          'poolId': raydiumQuotePool,
          'inputMint': inputMint,
          'outputMint': outputMint,
          'fee': <String, Object?>{
            'amountRaw': feeAmountRaw,
            'mint': feeMint ?? inputMint,
            'providerRateRaw': 10,
            'rateUnit': 'provider_integer_unverified',
          },
        },
      ],
    },
    'requestedAt': '2026-09-14T18:00:00.000Z',
    'receivedAt': '2026-09-14T18:00:00.050Z',
    'refreshAfter': '2026-09-14T18:00:10.000Z',
    'providerExpiresAt': null,
  };
}

String raydiumQuoteJson({
  RaydiumQuoteRequest request = raydiumBuyRequest,
  String? estimatedAmountRaw,
  String? minimumAmountRaw,
  String? providerActualAmountRaw,
  String feeAmountRaw = '10000',
  String? feeMint,
}) => jsonEncode(
  raydiumQuotePayload(
    request: request,
    estimatedAmountRaw: estimatedAmountRaw,
    minimumAmountRaw: minimumAmountRaw,
    providerActualAmountRaw: providerActualAmountRaw,
    feeAmountRaw: feeAmountRaw,
    feeMint: feeMint,
  ),
);

RaydiumStockQuote parsedRaydiumQuote({
  RaydiumQuoteRequest request = raydiumBuyRequest,
  Map<String, Object?>? payload,
}) => RaydiumStockQuote.fromJson(
  payload ?? raydiumQuotePayload(request: request),
  request: request,
);
