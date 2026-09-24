const account = 'aaaaaaaa-1234-5678-aaaa-123456789abc';
const otherAccount = 'bbbbbbbb-1234-5678-bbbb-123456789abc';
const wallet = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';

Map<String, Object?> contextEnvelope({
  Object? xIdentity,
  Object? embeddedWallet,
}) => {
  'schemaVersion': 1,
  'userId': account,
  'xIdentity':
      xIdentity ??
      {
        'status': 'verified',
        'subject': '18446744073709551615',
        'usernameSnapshot': 'trimmyhq',
        'verifiedAtUnixSeconds': 1757845200,
      },
  'embeddedSolanaWallet':
      embeddedWallet ??
      {
        'status': 'candidate',
        'address': wallet,
        'verifiedAtUnixSeconds': 1757845201,
      },
};

Map<String, Object?> tokenBalance({
  required String symbol,
  required String mint,
  required int decimals,
  required String amountRaw,
  required int slot,
  int accountCount = 1,
  String topology = 'associated_only',
  bool frozen = false,
}) => {
  'symbol': symbol,
  'mint': mint,
  'decimals': decimals,
  'amountRaw': amountRaw,
  'amountUnits': 'raw_token_units',
  'observedSlot': slot,
  'accountCount': accountCount,
  'accountTopology': topology,
  'aggregation': 'all_valid_owner_token_accounts',
  'hasFrozenAccounts': frozen,
};

Map<String, Object?> holdingsEnvelope() => {
  'schemaVersion': 1,
  'userId': account,
  'wallet': {
    'address': wallet,
    'source': 'privy_embedded_wallet_same_subject',
    'possessionSignatureVerified': false,
  },
  'holdings': {
    'network': 'solana:mainnet-beta',
    'genesisHash': '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d',
    'commitment': 'confirmed',
    'observedAt': '2026-09-14T17:28:27.109Z',
    'readOnly': true,
    'transactionBuilt': false,
    'transactionSigned': false,
    'transactionBroadcast': false,
    'balances': {
      'nativeSol': {
        'symbol': 'SOL',
        'decimals': 9,
        'amountRaw': '9007199254740991',
        'amountUnits': 'lamports',
        'observedSlot': 447040359,
      },
      'usdc': tokenBalance(
        symbol: 'USDC',
        mint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
        decimals: 6,
        amountRaw: '18446744073709551615',
        slot: 447040360,
        accountCount: 2,
        topology: 'associated_with_ancillary',
        frozen: true,
      ),
      'aaplx': {
        ...tokenBalance(
          symbol: 'AAPLx',
          mint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
          decimals: 8,
          amountRaw: '9007199254741000',
          slot: 447040361,
          accountCount: 1,
          topology: 'associated_only',
        ),
        'displayResolution': 'token_2022_scaled_ui_unresolved',
        'displayAmount': null,
        'shareAmount': null,
        'eligibility': 'unverified',
        'executionEnabled': false,
      },
    },
    'consistency': {
      'kind': 'independent_confirmed_reads',
      'atomic': false,
      'slots': {'nativeSol': 447040359, 'usdc': 447040360, 'aaplx': 447040361},
    },
  },
};
