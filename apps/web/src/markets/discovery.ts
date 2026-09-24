import {assetId, integer, invalid, list, metric, mint, optionalText, record, schema, sourceUrl, text, timestamp, unique, variantId} from './validation.js';

export interface DiscoveryProvenance {
  readonly schemaVersion: 1; readonly provider: 'tokens-xyz-v1'; readonly sourceUrl: string;
  readonly requestedAt: string; readonly observedAt: string; readonly refreshAfter: string;
  readonly providerAsOf: null; readonly providerFreshness: 'not_verified';
  readonly executionEnabled: false; readonly eligibility: 'unverified'; readonly mintVerification: 'not_checked';
}
export interface StockAdvisory {
  readonly status: 'caution' | 'compromised' | 'blocked' | 'unknown';
  /** Future normalized status and the original provider status are both retained. */
  readonly wireStatus: string; readonly providerStatus: string; readonly reason: string; readonly since: string;
}
export interface StockAssetAdvisory extends StockAdvisory { readonly mint: string; readonly variantId: string }
export interface StockVariantMarket {
  readonly displayOnly: true; readonly priceUsd: number | null; readonly liquidityUsd: number | null;
  readonly volume24hUsd: number | null; readonly decimals: number | null;
  readonly source: string | null; readonly metricsSource: string | null;
  readonly providerTimestamps: Readonly<{asOf: number | null; lastFetchedAt: number | null; lastTradeAt: number | null; unit: 'not_declared'}>;
}
export interface StockVariant {
  readonly variantId: string; readonly mint: string; readonly chain: 'solana'; readonly kind: string;
  readonly issuer: string | null; readonly label: string | null; readonly name: string | null;
  readonly symbol: string | null; readonly providerRedemptionTier: string | null;
  readonly advisory: StockAdvisory | null; readonly market: StockVariantMarket | null;
}
export interface StockDiscoveryAsset {
  readonly assetId: string; readonly name: string | null; readonly symbol: string | null; readonly category: 'equity';
  readonly providerPrimaryVariantMint: string | null; readonly variants: readonly StockVariant[];
  /** Also includes flagged sibling variants omitted from the bounded search. */
  readonly advisories: readonly StockAssetAdvisory[];
}
export interface StockSearchPage extends DiscoveryProvenance {
  readonly query: string; readonly limit: number; readonly completeCatalog: false; readonly results: readonly StockDiscoveryAsset[];
}
export interface StockVariantsPage extends DiscoveryProvenance { readonly assetId: string; readonly variants: readonly StockVariant[] }
const provenanceKeys = ['schemaVersion', 'provider', 'sourceUrl', 'requestedAt', 'observedAt', 'refreshAfter',
  'providerAsOf', 'providerFreshness', 'executionEnabled', 'eligibility', 'mintVerification'];
function provenance(data: Record<string, unknown>): DiscoveryProvenance {
  schema(data['schemaVersion']);
  if (data['provider'] !== 'tokens-xyz-v1' || data['providerAsOf'] !== null || data['providerFreshness'] !== 'not_verified' ||
      data['executionEnabled'] !== false || data['eligibility'] !== 'unverified' || data['mintVerification'] !== 'not_checked') invalid();
  const requestedAt = timestamp(data['requestedAt']), observedAt = timestamp(data['observedAt']), refreshAfter = timestamp(data['refreshAfter']);
  if (Date.parse(observedAt) < Date.parse(requestedAt) || Date.parse(refreshAfter) <= Date.parse(observedAt) ||
      Date.parse(refreshAfter) - Date.parse(requestedAt) > 60000) invalid();
  return Object.freeze({schemaVersion: 1, provider: 'tokens-xyz-v1', sourceUrl: sourceUrl(data['sourceUrl']), requestedAt,
    observedAt, refreshAfter, providerAsOf: null, providerFreshness: 'not_verified', executionEnabled: false,
    eligibility: 'unverified', mintVerification: 'not_checked'});
}
const advisoryKeys = ['status', 'providerStatus', 'reason', 'since'];
function advisoryFields(data: Record<string, unknown>): StockAdvisory {
  const wireStatus = text(data['status'], 60);
  const status = ['caution', 'compromised', 'blocked'].includes(wireStatus) ? wireStatus as StockAdvisory['status'] : 'unknown';
  return Object.freeze({status, wireStatus, providerStatus: text(data['providerStatus'], 60), reason: text(data['reason'], 1000), since: timestamp(data['since'])});
}
function advisory(value: unknown): StockAdvisory | null { return value === null ? null : advisoryFields(record(value, advisoryKeys)); }
function assetAdvisory(value: unknown): StockAssetAdvisory {
  const data = record(value, [...advisoryKeys, 'mint', 'variantId']);
  return Object.freeze({...advisoryFields(data), mint: mint(data['mint']), variantId: variantId(data['variantId'])});
}
function market(value: unknown): StockVariantMarket | null {
  if (value === null) return null;
  const data = record(value, ['displayOnly', 'priceUsd', 'liquidityUsd', 'volume24hUsd', 'decimals', 'source', 'metricsSource', 'providerTimestamps']);
  if (data['displayOnly'] !== true) invalid();
  const times = record(data['providerTimestamps'], ['asOf', 'lastFetchedAt', 'lastTradeAt', 'unit']);
  if (times['unit'] !== 'not_declared') invalid();
  const optionalInteger = (value: unknown) => value === null ? null : integer(value, 0, Number.MAX_SAFE_INTEGER);
  return Object.freeze({displayOnly: true, priceUsd: metric(data['priceUsd']), liquidityUsd: metric(data['liquidityUsd']),
    volume24hUsd: metric(data['volume24hUsd']), decimals: data['decimals'] === null ? null : integer(data['decimals'], 0, 255),
    source: optionalText(data['source'], 80), metricsSource: optionalText(data['metricsSource'], 80),
    providerTimestamps: Object.freeze({asOf: optionalInteger(times['asOf']), lastFetchedAt: optionalInteger(times['lastFetchedAt']),
      lastTradeAt: optionalInteger(times['lastTradeAt']), unit: 'not_declared'})});
}
function variant(value: unknown): StockVariant {
  const data = record(value, ['variantId', 'mint', 'chain', 'kind', 'issuer', 'label', 'name', 'symbol', 'providerRedemptionTier', 'advisory', 'market']);
  if (data['chain'] !== 'solana') invalid();
  return Object.freeze({variantId: variantId(data['variantId']), mint: mint(data['mint']), chain: 'solana', kind: text(data['kind'], 60),
    issuer: optionalText(data['issuer']), label: optionalText(data['label']), name: optionalText(data['name']), symbol: optionalText(data['symbol'], 40),
    providerRedemptionTier: optionalText(data['providerRedemptionTier'], 80), advisory: advisory(data['advisory']), market: market(data['market'])});
}
function variants(value: unknown): readonly StockVariant[] {
  const result = list(value, 64, variant); unique(result.map(row => row.mint)); unique(result.map(row => row.variantId)); return result;
}
function asset(value: unknown): StockDiscoveryAsset {
  const data = record(value, ['assetId', 'name', 'symbol', 'category', 'providerPrimaryVariantMint', 'variants', 'advisories']);
  if (data['category'] !== 'equity') invalid();
  const rows = variants(data['variants']);
  const primary = data['providerPrimaryVariantMint'] === null ? null : mint(data['providerPrimaryVariantMint']);
  if (primary !== null && !rows.some(row => row.mint === primary)) invalid();
  const flags = list(data['advisories'], 64, assetAdvisory); unique(flags.map(flag => flag.mint));
  for (const row of rows) {
    const flag = flags.find(flag => flag.mint === row.mint);
    if ((row.advisory !== null) !== (flag !== undefined) || flag && (flag.variantId !== row.variantId ||
        flag.wireStatus !== row.advisory?.wireStatus || flag.providerStatus !== row.advisory?.providerStatus ||
        flag.reason !== row.advisory?.reason || flag.since !== row.advisory?.since)) invalid();
  }
  return Object.freeze({assetId: assetId(data['assetId']), name: optionalText(data['name']), symbol: optionalText(data['symbol'], 40),
    category: 'equity', providerPrimaryVariantMint: primary, variants: rows, advisories: flags});
}
export function parseStockSearchPage(value: unknown): StockSearchPage {
  const data = record(value, [...provenanceKeys, 'query', 'limit', 'completeCatalog', 'results']);
  const common = provenance(data); if (data['completeCatalog'] !== false) invalid();
  const limit = integer(data['limit'], 1, 20); const results = list(data['results'], limit, asset);
  unique(results.map(row => row.assetId)); unique(results.flatMap(row => row.variants.map(variant => variant.mint)));
  return Object.freeze({...common, query: text(data['query'], 80), limit, completeCatalog: false, results});
}
export function parseStockVariantsPage(value: unknown): StockVariantsPage {
  const data = record(value, [...provenanceKeys, 'assetId', 'variants']);
  return Object.freeze({...provenance(data), assetId: assetId(data['assetId']), variants: variants(data['variants'])});
}
/** A display refresh deadline is not transaction validity or provider freshness. */
export function researchNeedsRefresh(value: {readonly refreshAfter: string}, now = Date.now()): boolean {
  const deadline = Date.parse(value.refreshAfter);
  return !Number.isFinite(now) || !Number.isFinite(deadline) || now >= deadline;
}
