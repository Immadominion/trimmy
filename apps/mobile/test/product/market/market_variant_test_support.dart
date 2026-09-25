import 'package:trimmy/markets/discovery.dart';
import 'package:trimmy/product/market/market_models.dart';

import 'market_test_support.dart';

// Public-key-shaped fixture for a different issuer, not an execution identity.
const otherIssuerMint = 'So11111111111111111111111111111111111111112';

MarketCompany twoVariantCompany() => MarketCompany.fromDiscovery(
  StockDiscoveryAsset.fromJson({
    'assetId': 'apple',
    'name': 'Apple',
    'symbol': 'AAPL',
    'category': 'equity',
    'providerPrimaryVariantMint': otherIssuerMint,
    'variants': [
      for (final mint in [otherIssuerMint, testMint])
        {
          'variantId': 'apple-$mint',
          'mint': mint,
          'chain': 'solana',
          'kind': 'tokenized-equity',
          'issuer': mint == testMint ? 'Backed' : 'Other issuer',
          'label': mint == testMint ? 'AAPLx' : 'AAPL-other',
          'name': 'Apple token',
          'symbol': mint == testMint ? 'AAPLx' : 'AAPL-other',
          'providerRedemptionTier': null,
          'advisory': null,
          'market': null,
        },
    ],
    'advisories': [],
  }),
);
