/**
 * Tokenized-stock issuers Trimmy recognises. Each issuer has:
 *  - disclosure: what the app must show before a user trades that issuer's tokens,
 *    including the issuer's key warning and a versioned eligibility attestation
 *    the server requires on preview. Texts summarise each issuer's own terms as
 *    read on 2026-09-27 (links in termsUrl); they are not legal advice.
 *  - identity: pinned on-chain authorities the token directory checks,
 *    together with a curated listing, to prove a mint belongs to the issuer
 *    (stock-token-directory.ts). Neither alone admits a token.
 *  - offer: whether Trimmy offers trading in the issuer's tokens at all. A
 *    not-offered issuer's registry entries stay recognisable for holdings and
 *    history but cannot be quoted or traded.
 * Changing any attestation text MUST bump its version so earlier acceptances
 * no longer satisfy the preview check.
 */
export type StockIssuerId = 'xstocks' | 'ondo' | 'backpack' | 'prestocks' | 'tessera';

export interface StockIssuerDisclosure {
  readonly issuerId: StockIssuerId;
  /** Short brand shown next to a symbol, e.g. "Ondo". */
  readonly name: string;
  readonly legalName: string;
  readonly productType: string;
  /** One or two plain sentences on what a holder owns. */
  readonly summary: string;
  readonly holderRights: string;
  /** The issuer's most important warning, shown before the attestation. */
  readonly warning: string;
  readonly excludedRegions: readonly string[];
  readonly termsUrl: string;
  readonly attestation: Readonly<{version: string; text: string}>;
}

export type StockIssuerOffer =
  | Readonly<{status: 'offered'}>
  | Readonly<{status: 'not_offered'; reason: string}>;

export type StockIssuerRegistrySource =
  | Readonly<{kind: 'xstocks_api'; url: string}>
  | Readonly<{kind: 'backpack_assets_api'; url: string}>
  | Readonly<{kind: 'ondo_assets_api'; url: string}>
  | Readonly<{kind: 'issuer_metadata'}>;

export interface StockIssuerIdentity {
  readonly tokenProgram: 'token_2022';
  readonly decimals: number;
  readonly metadataUpdateAuthority: string;
  /** A fixed mint authority, or null when the issuer uses one per token (checked via the registry source). */
  readonly mintAuthority: string | null;
  readonly freezeAuthorities: readonly string[];
  readonly permanentDelegate: string | null;
  readonly metadataUriPrefixes: readonly string[];
  readonly registry: StockIssuerRegistrySource;
  /** Admission refuses higher Token-2022 transfer fees for this issuer. */
  readonly maxTransferFeeBps: number;
  /** 'rfq': liquidity comes only from JupiterZ market makers (fixed quotes, maker pays the fee). */
  readonly route: 'aggregator' | 'rfq';
}

export interface StockIssuer {
  readonly disclosure: StockIssuerDisclosure;
  readonly identity: StockIssuerIdentity;
  readonly offer: StockIssuerOffer;
}

const TERMS_VERSION = '2026-09-27';

const issuers: Record<StockIssuerId, StockIssuer> = {
  xstocks: {
    disclosure: {
      issuerId: 'xstocks', name: 'xStocks', legalName: 'Backed Assets (JE) Limited',
      productType: 'Tracker certificate',
      summary: 'Each token tracks one share and is backed by shares held in custody. You own a certificate issued by Backed, not the share.',
      holderRights: 'No voting rights. Dividends are reinvested by adjusting your token amount. Redeeming directly needs identity checks and at least 5,000 US dollars.',
      warning: 'These products suit only people who can afford to lose the money they put in and who understand the risks. Their issue is not covered by all of Jersey\'s financial services law.',
      excludedRegions: ['United States', 'United Kingdom', 'Canada', 'Australia'],
      termsUrl: 'https://assets.backed.fi/legal-documentation',
      attestation: {version: TERMS_VERSION,
        text: 'I am not a US person and I do not live in the United Kingdom, Canada or Australia. I have read the xStocks warning and accept the xStocks terms.'},
    },
    identity: {
      tokenProgram: 'token_2022', decimals: 8,
      metadataUpdateAuthority: '5aMNNLQJwAEeoemTEMkv5NVjqKwvvefRYCQ5Z67HFvEq',
      mintAuthority: '7pt9tkctJPK7PPNQJ77GKg8ZffSF6QxoMiCFYHxrtaCj',
      freezeAuthorities: ['JDq14BWvqCRFNu1krb12bcRpbGtJZ1FLEakMw6FdxJNs'],
      permanentDelegate: '5aMNNLQJwAEeoemTEMkv5NVjqKwvvefRYCQ5Z67HFvEq',
      metadataUriPrefixes: ['https://xstocks-metadata.backed.fi/tokens/Solana/'],
      registry: {kind: 'xstocks_api', url: 'https://api.xstocks.fi/api/v2/public/assets/'},
      maxTransferFeeBps: 0,
      route: 'aggregator',
    },
    offer: {status: 'offered'},
  },
  backpack: {
    disclosure: {
      issuerId: 'backpack', name: 'Backpack', legalName: 'Trek Nexus Markets Ltd',
      productType: 'Share receipt token',
      summary: 'Each token is a receipt for a share held in trust by Backpack\'s issuer. You do not own the share.',
      holderRights: 'No voting rights. Dividends are reinvested by adjusting your token amount.',
      warning: 'The issuer does not recognise wallet holders. To redeem, you must move the tokens into a verified Backpack account. Otherwise you can only sell them, and Backpack says they may be worthless to you.',
      excludedRegions: ['United States', 'United Kingdom', 'United Arab Emirates', 'Japan', 'European Economic Area', 'Canada',
        'New Zealand', 'Cuba', 'Iran', 'North Korea', 'Occupied regions of Ukraine'],
      termsUrl: 'https://support.backpack.exchange/legal/general-legal/user-agreement',
      attestation: {version: TERMS_VERSION,
        text: 'I am not a US person and I do not live in a country Backpack Securities excludes. I understand the issuer does not recognise wallet holders, and I accept the Backpack Securities terms.'},
    },
    identity: {
      tokenProgram: 'token_2022', decimals: 6,
      metadataUpdateAuthority: '2cVYpagTt7ZGc3mmTXBa7fAznUtx5DUu6aCq8uVDaf4a',
      mintAuthority: null,
      freezeAuthorities: ['2cVYpagTt7ZGc3mmTXBa7fAznUtx5DUu6aCq8uVDaf4a'],
      permanentDelegate: '2cVYpagTt7ZGc3mmTXBa7fAznUtx5DUu6aCq8uVDaf4a',
      metadataUriPrefixes: ['https://metadata.backpack.exchange/stocks/', 'https://trek-labs.github.io/heart-metadata/stocks/'],
      registry: {kind: 'backpack_assets_api', url: 'https://api.backpack.exchange/api/v1/assets'},
      maxTransferFeeBps: 0,
      route: 'aggregator',
    },
    offer: {status: 'offered'},
  },
  ondo: {
    disclosure: {
      issuerId: 'ondo', name: 'Ondo', legalName: 'Ondo Global Markets (BVI) Limited',
      productType: 'Structured note',
      summary: 'Each token is a note that tracks one share, backed by shares held through a US broker. You do not own the share.',
      holderRights: 'No voting or shareholder rights. Dividends are reinvested after tax by adjusting your token amount. Prices come from market makers, and trading can pause outside US market hours or around company events.',
      warning: 'Only professional investors may buy in the United Kingdom, the European Economic Area, Switzerland, Singapore, Hong Kong, Malaysia and Brazil.',
      excludedRegions: ['United States', 'Canada', 'Afghanistan', 'Belarus', 'Cuba', 'Iran', 'Libya', 'Myanmar', 'North Korea',
        'Russia', 'Somalia', 'South Sudan', 'Sudan', 'Syria', 'Occupied regions of Ukraine'],
      termsUrl: 'https://docs.ondo.finance/ondo-stocks/eligibility',
      attestation: {version: TERMS_VERSION,
        text: 'I am not a US person and I do not live in a country Ondo prohibits. If I live where only professional investors may buy, I am one. I accept the Ondo Global Markets terms.'},
    },
    identity: {
      tokenProgram: 'token_2022', decimals: 9,
      metadataUpdateAuthority: '9foMHsSDq7nMg4WPusSz9eY7tyxyukqborA8GyU5cUxD',
      mintAuthority: '9foMHsSDq7nMg4WPusSz9eY7tyxyukqborA8GyU5cUxD',
      freezeAuthorities: ['51QVCuHfL1FeNjd8BDeffCKhCcAYoULnVB3yjNhShiuK'],
      permanentDelegate: null,
      metadataUriPrefixes: ['https://app.ondo.finance/api/v2/assets/'],
      registry: {kind: 'ondo_assets_api', url: 'https://app.ondo.finance/api/v2/assets'},
      maxTransferFeeBps: 0,
      route: 'rfq',
    },
    // Ondo liquidity is quoted by JupiterZ market makers (route: 'rfq').
    offer: {status: 'offered'},
  },
  prestocks: {
    disclosure: {
      issuerId: 'prestocks', name: 'PreStocks', legalName: 'PreStocks (no legal issuer named)',
      productType: 'Pre-IPO exposure token',
      summary: 'Each token claims economic exposure to a private company through arrangements PreStocks does not disclose. You own no shares.',
      holderRights: 'No ownership, voting, dividend or information rights. A token can expire worthless if it is not converted after the company lists.',
      warning: 'Anthropic and OpenAI have said transfers of their shares through such vehicles are void. Each transfer costs a fee the issuer can change.',
      excludedRegions: ['United States', 'China', 'Russia', 'Singapore', 'Ukraine', 'Other countries listed in the PreStocks terms'],
      termsUrl: 'https://url.prestocks.com/terms-of-service',
      attestation: {version: TERMS_VERSION,
        text: 'I am not a US person and I do not live in a country PreStocks prohibits, and I accept the PreStocks terms.'},
    },
    identity: {
      tokenProgram: 'token_2022', decimals: 9,
      metadataUpdateAuthority: 'WV9PJN7XTmTLVwbutCLFxp8TyePee6Xq5mRq6Fti5Wc',
      mintAuthority: 'WV9PJN7XTmTLVwbutCLFxp8TyePee6Xq5mRq6Fti5Wc',
      freezeAuthorities: ['WV9PJN7XTmTLVwbutCLFxp8TyePee6Xq5mRq6Fti5Wc'],
      permanentDelegate: 'WV9PJN7XTmTLVwbutCLFxp8TyePee6Xq5mRq6Fti5Wc',
      metadataUriPrefixes: ['https://prestocks.com/metadata/'],
      registry: {kind: 'issuer_metadata'},
      maxTransferFeeBps: 300,
      route: 'aggregator',
    },
    // Offered at the owner's direction (27 Sept 2026) with the warning above shown before any order.
    offer: {status: 'offered'},
  },
  tessera: {
    disclosure: {
      issuerId: 'tessera', name: 'Tessera', legalName: 'Tessera Works Foundation issuers (Panama)',
      productType: 'Loan participation token',
      summary: 'Each token is a share in a small loan to a Panama company that holds private company exposure. It is not a share.',
      holderRights: 'No ownership, voting or dividend rights. You are repaid only after the position is sold, inside a 90 day window.',
      warning: 'If you miss the 90 day redemption window, your claim is lost.',
      excludedRegions: ['United States', 'China', 'Russia', 'Iran', 'North Korea', 'Countries on the FATF grey or black list'],
      termsUrl: 'https://terms.tessera.pe/terms-and-conditions',
      attestation: {version: TERMS_VERSION,
        text: 'I am not a US person and I do not live in a country Tessera excludes, and I accept the Tessera terms.'},
    },
    identity: {
      tokenProgram: 'token_2022', decimals: 9,
      metadataUpdateAuthority: 'EXvTtxurWBUNNCtLojaN8ZBJFNJPZFSH3szoih9hh7YW',
      mintAuthority: 'EXvTtxurWBUNNCtLojaN8ZBJFNJPZFSH3szoih9hh7YW',
      freezeAuthorities: ['7n2PNcDXVDMK2m8dyV9cVPNY7p4jM4ZMHv7TzfibEt8o'],
      permanentDelegate: null,
      metadataUriPrefixes: ['https://cdn.tesseralab.co/tessera/'],
      registry: {kind: 'issuer_metadata'},
      maxTransferFeeBps: 50,
      route: 'aggregator',
    },
    // Offered at the owner's direction (27 Sept 2026) with the warning above shown before any order.
    offer: {status: 'offered'},
  },
};

function freezeIssuer(issuer: StockIssuer): StockIssuer {
  return Object.freeze({
    disclosure: Object.freeze({...issuer.disclosure, excludedRegions: Object.freeze([...issuer.disclosure.excludedRegions]),
      attestation: Object.freeze({...issuer.disclosure.attestation})}),
    identity: Object.freeze({...issuer.identity, freezeAuthorities: Object.freeze([...issuer.identity.freezeAuthorities]),
      metadataUriPrefixes: Object.freeze([...issuer.identity.metadataUriPrefixes]),
      registry: Object.freeze({...issuer.identity.registry})}),
    offer: Object.freeze({...issuer.offer}),
  });
}

export const STOCK_ISSUERS: Readonly<Record<StockIssuerId, StockIssuer>> = Object.freeze(Object.fromEntries(
  Object.entries(issuers).map(([id, issuer]) => [id, freezeIssuer(issuer)]),
) as Record<StockIssuerId, StockIssuer>);

export const STOCK_ISSUER_IDS = Object.freeze(Object.keys(STOCK_ISSUERS) as StockIssuerId[]);

export function isStockIssuerId(value: unknown): value is StockIssuerId {
  return typeof value === 'string' && Object.hasOwn(STOCK_ISSUERS, value);
}

export function stockIssuerOffered(issuerId: StockIssuerId): boolean {
  return STOCK_ISSUERS[issuerId].offer.status === 'offered';
}

/** The only issuer an older client (no terms acceptance field) may trade, with its original disclosure. */
export const LEGACY_STOCK_ISSUER: StockIssuerId = 'xstocks';

export interface StockTermsAcceptance {
  readonly issuerId: string;
  readonly version: string;
}

/** True when the acceptance names exactly this issuer's current attestation version. */
export function acceptsIssuerTerms(issuerId: StockIssuerId, acceptance: StockTermsAcceptance | undefined): boolean {
  if (acceptance === undefined) return issuerId === LEGACY_STOCK_ISSUER;
  return acceptance.issuerId === issuerId && acceptance.version === STOCK_ISSUERS[issuerId].disclosure.attestation.version;
}
