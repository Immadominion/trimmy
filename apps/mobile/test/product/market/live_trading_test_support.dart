import 'package:trimmy/markets/discovery.dart';
import 'package:trimmy/product/market/market_models.dart';

// Public-key-shaped fixtures for other issuers' tokens, not execution
// identities. Each decodes to 32 bytes, as discovery requires.
const xNvidiaMint = 'Xsc9qvGR1efVDFGLrVsmkzv3qi45LTBjeUKSPmx9qEh';
const ondoNvidiaMint = 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB';
const backpackNvidiaMint = 'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263';
const preStocksMint = 'mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So';
const xAppleMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const termsVersion = '2026-09-27';

/// A unique base58 string shaped like a mint, for list size tests only.
String fakeMint(int index) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  final digits = StringBuffer();
  var rest = index;
  do {
    digits.write(alphabet[rest % 58]);
    rest ~/= 58;
  } while (rest > 0);
  return digits.toString().padRight(40, 'z');
}

Map<String, Object?> issuerJson(
  String issuerId, {
  String? name,
  String version = termsVersion,
  List<String> excluded = const ['United States', 'United Kingdom'],
  String? warning,
  bool offered = true,
  String? notOfferedReason,
}) {
  final label = name ?? issuerId;
  return {
    'issuerId': issuerId,
    'name': label,
    'legalName': '$label Limited',
    'productType': 'Tracker certificate',
    'summary': 'Each token tracks one share.',
    'holderRights': 'No voting rights. Dividends are reinvested.',
    'excludedRegions': excluded,
    'termsUrl': 'https://terms.example/$issuerId',
    'attestation': {'version': version, 'text': 'I accept the $label terms.'},
    'warning': warning ?? '',
    'offered': offered,
    'notOfferedReason': offered
        ? null
        : notOfferedReason ?? '$label tokens are not offered in Trimmy yet.',
  };
}

Map<String, Object?> assetJson({
  required String assetId,
  required String mint,
  required String symbol,
  String? name,
  String issuerId = 'xstocks',
  int decimals = 8,
  int transferFeeBps = 0,
  String maxBuyInputRaw = '100000000',
  String? maxSellInputRaw,
}) => {
  'assetId': assetId,
  'mint': mint,
  'symbol': symbol,
  'name': name ?? '$symbol token',
  'issuerId': issuerId,
  'decimals': decimals,
  'maxBuyInputRaw': maxBuyInputRaw,
  'maxSellInputRaw': maxSellInputRaw ?? '1${'0' * decimals}',
  'transferFeeBps': transferFeeBps,
};

/// The issuer-aware shape: xStocks, Ondo, Backpack and PreStocks.
Map<String, Object?> capabilitiesV2Json({
  bool enabled = true,
  List<Map<String, Object?>>? issuers,
  List<Map<String, Object?>>? assets,
  List<Object?> unavailable = const [],
}) => {
  'schemaVersion': 2,
  'enabled': enabled,
  'network': 'solana:mainnet-beta',
  'maxBuyUsdc': '100',
  'minimumSolBalanceLamports': '5000',
  'issuers':
      issuers ??
      [
        issuerJson(
          'xstocks',
          name: 'xStocks',
          excluded: const [
            'United States',
            'United Kingdom',
            'Canada',
            'Australia',
          ],
        ),
        issuerJson('ondo', name: 'Ondo', excluded: const ['United States']),
        issuerJson('backpack', name: 'Backpack'),
        issuerJson('prestocks', name: 'PreStocks'),
        issuerJson('tessera', name: 'Tessera', offered: false),
      ],
  'unavailable': unavailable,
  'assets':
      assets ??
      [
        assetJson(
          assetId: 'apple',
          mint: xAppleMint,
          symbol: 'AAPLx',
          name: 'Apple xStock',
        ),
        assetJson(
          assetId: 'nvidia',
          mint: xNvidiaMint,
          symbol: 'NVDAx',
          name: 'NVIDIA xStock',
        ),
        assetJson(
          assetId: 'nvidia',
          mint: ondoNvidiaMint,
          symbol: 'NVDAon',
          name: 'NVIDIA (Ondo Tokenized)',
          issuerId: 'ondo',
          decimals: 9,
        ),
        assetJson(
          assetId: 'nvidia',
          mint: backpackNvidiaMint,
          symbol: 'NVDAbp',
          name: 'NVIDIA (Backpack)',
          issuerId: 'backpack',
          decimals: 6,
        ),
        assetJson(
          assetId: 'spacex',
          mint: preStocksMint,
          symbol: 'SPACEX',
          name: 'SpaceX PreStock',
          issuerId: 'prestocks',
          decimals: 9,
          transferFeeBps: 300,
        ),
      ],
};

/// A discovery company listing the given tokens, each with an optional
/// liquidity reading.
MarketCompany discoveryCompany(
  String assetId,
  List<(String mint, num? liquidity)> variants, {
  String name = 'NVIDIA',
  String symbol = 'NVDA',
  String? primary,
}) => MarketCompany.fromDiscovery(
  StockDiscoveryAsset.fromJson({
    'assetId': assetId,
    'name': name,
    'symbol': symbol,
    'category': 'equity',
    'providerPrimaryVariantMint': primary ?? variants.first.$1,
    'variants': [
      for (final (mint, liquidity) in variants)
        {
          'variantId': '$assetId-${mint.substring(0, 6)}',
          'mint': mint,
          'chain': 'solana',
          'kind': 'tokenized-equity',
          'issuer': 'Issuer',
          'label': symbol,
          'name': '$name token',
          'symbol': '$symbol-${mint.substring(0, 3)}',
          'providerRedemptionTier': null,
          'advisory': null,
          'market': liquidity == null
              ? null
              : {
                  'displayOnly': true,
                  'priceUsd': 100,
                  'liquidityUsd': liquidity,
                  'volume24hUsd': 1000,
                  'decimals': 8,
                  'source': 'tokens.xyz',
                  'metricsSource': null,
                  'providerTimestamps': {
                    'asOf': null,
                    'lastFetchedAt': null,
                    'lastTradeAt': null,
                    'unit': 'not_declared',
                  },
                },
        },
    ],
    'advisories': [],
  }),
);
