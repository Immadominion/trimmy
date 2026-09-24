import 'package:trimmy/markets/stock_research.dart';

Map<String, Object?> researchProvenanceFixture() => {
  'schemaVersion': 1,
  'provider': 'tokens-xyz-v1',
  'sourceUrl': 'https://api.tokens.xyz/v1/assets/search?q=Apple',
  'requestedAt': '2026-09-14T18:00:00.000Z',
  'observedAt': '2026-09-14T18:00:01.000Z',
  'refreshAfter': '2026-09-14T18:01:00.000Z',
  'providerAsOf': null,
  'providerFreshness': 'not_verified',
  'executionEnabled': false,
  'eligibility': 'unverified',
  'mintVerification': 'not_checked',
};
Map<String, Object?> stockVariantFixture() => {
  'variantId': 'apple-xstock',
  'mint': researchAaplxMint,
  'chain': 'solana',
  'kind': 'xstock',
  'issuer': 'Backed',
  'label': 'Apple xStock',
  'name': 'Apple xStock',
  'symbol': 'AAPLx',
  'providerRedemptionTier': 'provider_description_only',
  'advisory': null,
  'market': {
    'displayOnly': true,
    'priceUsd': 200.5,
    'liquidityUsd': 100000,
    'volume24hUsd': 15000,
    'decimals': 8,
    'source': 'provider',
    'metricsSource': null,
    'providerTimestamps': {
      'asOf': 1789400000,
      'lastFetchedAt': 1789400000000,
      'lastTradeAt': null,
      'unit': 'not_declared',
    },
  },
};
Map<String, Object?> stockSearchFixture({
  String query = 'Apple',
  int limit = 10,
}) => {
  ...researchProvenanceFixture(),
  'query': query,
  'limit': limit,
  'completeCatalog': false,
  'results': [
    {
      'assetId': 'apple',
      'name': 'Apple',
      'symbol': 'AAPL',
      'category': 'equity',
      'providerPrimaryVariantMint': researchAaplxMint,
      'variants': [stockVariantFixture()],
      'advisories': [],
    },
  ],
};
Map<String, Object?> stockVariantsFixture({String assetId = 'apple'}) => {
  ...researchProvenanceFixture(),
  'assetId': assetId,
  'variants': [stockVariantFixture()],
};
Map<String, Object?> stockEstimateFixture({
  StockEstimateSide side = StockEstimateSide.buy,
  String raw = '10000000',
}) {
  final buying = side == StockEstimateSide.buy;
  return {
    'schemaVersion': 1,
    'kind': 'indicative',
    'network': 'solana:mainnet-beta',
    'provider': 'jupiter-swap-v2',
    'executable': false,
    'walletChecked': false,
    'networkFees': null,
    'input': {
      'symbol': buying ? 'USDC' : 'AAPLx',
      'mint': buying ? researchUsdcMint : researchAaplxMint,
      'decimals': buying ? 6 : 8,
      'amountRaw': raw,
    },
    'output': {
      'symbol': buying ? 'AAPLx' : 'USDC',
      'mint': buying ? researchAaplxMint : researchUsdcMint,
      'decimals': buying ? 8 : 6,
      'estimatedAmountRaw': '18446744073709551615',
      'quotedMinimumAmountRaw': '18446744073709551614',
    },
    'slippageBps': 50,
    'swapFee': {'basisPoints': 0, 'mint': researchUsdcMint},
    'router': 'metis',
    'requestedAt': '2026-09-14T18:00:00.000Z',
    'receivedAt': '2026-09-14T18:00:01.000Z',
    'refreshAfter': '2026-09-14T18:00:10.000Z',
    'providerExpiresAt': null,
    'assetId': 'apple',
    'variantMint': researchAaplxMint,
    'side': side.name,
    'executionEnabled': false,
    'eligibility': 'unverified',
    'amountUnits': 'raw_token_units',
  };
}
