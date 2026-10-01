/**
 * Trading capabilities, read from the execution API and never inferred from a
 * logo, ticker or the discovery provider's primary token. Version 2 lists every
 * tradeable token across issuers, each issuer's disclosure and offer status,
 * and a refusal reason for Market tokens that cannot be traded. Parsing is
 * strict about what an order needs and lenient about fields the API adds.
 * Contract: apps/api/src/live-stock-orders.ts, mobile live_trading.dart.
 */
import {USDC_MINT} from './amounts.js';
import * as fmt from '../../i18n/format.js';
import {t, type MessageKey} from '../../i18n/runtime.js';

/** Bounds for one read. The API admits tokens automatically, so these sit well above today's list (as mobile's do). */
export const CAPABILITIES_MAX_ASSETS = 10_000;
export const CAPABILITIES_MAX_UNAVAILABLE = 10_000;
export const CAPABILITIES_MAX_BYTES = 8_388_608;
/** Sells carry no per-token cap under schema 3: a limit at or above this reads as none. */
export const UNCAPPED_RAW = 10n ** 18n;
export function uncapped(raw: string): boolean {return BigInt(raw) >= UNCAPPED_RAW;}
const MAX_ISSUERS = 32;

const MINT = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
const RAW_LIMIT = /^[1-9][0-9]{0,19}$/;
const ASSET_ID = /^[a-z0-9][a-z0-9_-]{0,127}$/;
const ISSUER_ID = /^[a-z0-9][a-z0-9_-]{0,63}$/;
const VERSION = /^[^\s\x00-\x1f\x7f]{1,64}$/;
const REASON = /^[a-z0-9_]{1,64}$/;
const CONTROL = /[\x00-\x1f\x7f]/;
const PROSE_CONTROL = /[\x00-\x09\x0b-\x1f\x7f]/;

export class CapabilitiesError extends Error {
  readonly code = 'TRADING_CAPABILITIES_INVALID';
  constructor(readonly detail: string) {super(detail); this.name = 'CapabilitiesError';}
}
function fail(detail: string): never {throw new CapabilitiesError(detail);}
function record(value: unknown, detail: string): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) fail(detail);
  return value as Record<string, unknown>;
}
function text(value: unknown, max: number, detail: string): string {
  if (typeof value !== 'string' || !value.trim() || value.length > max || CONTROL.test(value)) fail(detail);
  return value;
}
/** Optional prose: null or missing reads as empty; anything else must be clean text. */
function prose(value: unknown, max: number, detail: string): string {
  if (value === null || value === undefined) return '';
  if (typeof value !== 'string' || value.length > max || PROSE_CONTROL.test(value)) fail(detail);
  return value.trim();
}
function optionalText(value: unknown, max: number): string | null {
  return typeof value === 'string' && value.trim() && value.length <= max && !CONTROL.test(value) ? value.trim() : null;
}

export interface IssuerAttestation {readonly version: string; readonly text: string}
export interface TradingIssuer {
  readonly issuerId: string; readonly name: string; readonly legalName: string; readonly productType: string;
  readonly summary: string; readonly holderRights: string;
  /** The issuer's key warning, shown before the eligibility tick and the review. May be empty. */
  readonly warning: string;
  readonly excludedRegions: readonly string[]; readonly termsUrl: string;
  readonly attestation: IssuerAttestation;
  /** A tick or a trade is never offered for an issuer that is not offered. */
  readonly offered: boolean; readonly notOfferedReason: string | null;
  readonly route: 'aggregator' | 'rfq' | null;
}

/** Whether a token can trade right now, as the server reads it. An unknown status never trades. */
export type MarketStatus = 'open' | 'paused' | 'closed' | 'unknown';
export interface MarketState {
  readonly status: MarketStatus; readonly wireStatus: string;
  /** `outside_sessions`, `session_break`, `market_paused` or `issuer_paused`. */
  readonly reason: string | null;
  /** Trades only in the US `sessions` rather than around the clock. */
  readonly usSessions: boolean;
  readonly sessions: readonly string[];
  readonly session: string | null;
  readonly nextOpenAt: string | null; readonly closesAt: string | null;
}
/** The US session in force: context only, since most tokens trade around the clock. */
export interface UsMarket {readonly session: string | null; readonly between: string | null; readonly changesAt: string | null}
export interface TradingAsset {
  /** The company id. Several tokens from different issuers can share it. */
  readonly assetId: string; readonly mint: string; readonly symbol: string; readonly name: string;
  readonly decimals: number; readonly maxBuyInputRaw: string; readonly maxSellInputRaw: string;
  readonly issuerId: string; readonly transferFeeBps: number; readonly route: 'aggregator' | 'rfq';
  /** The smallest USDC buy the route fills: market makers need at least $1 after fees. */
  readonly minBuyInputRaw: string;
  /** Null when the server sends no market state; the order review then decides. */
  readonly market: MarketState | null;
}
export interface UnavailableVariant {
  readonly mint: string; readonly issuerId: string | null; readonly reason: string; readonly symbol: string | null;
  /** For a token refused only because its market is closed: when it opens. */
  readonly market: MarketState | null;
}
/** One of a company's tokens as Real mode sees it. */
export interface VariantOption {
  readonly mint: string; readonly label: string; readonly asset: TradingAsset | null;
  readonly issuer: TradingIssuer | null;
  /** Null for a token that can be traded right now. */
  readonly reason: string | null;
  readonly tradeable: boolean;
}
/** The discovery side of a company's tokens, used to prove a token belongs to it. */
export interface DiscoveryVariantRef {
  readonly mint: string; readonly liquidityUsd?: number | null;
  readonly issuer?: string | null; readonly label?: string | null; readonly symbol?: string | null;
}

function parseAttestation(value: unknown): IssuerAttestation {
  const data = record(value, 'Invalid issuer attestation');
  const version = data['version'];
  if (typeof version !== 'string' || !VERSION.test(version)) fail('Invalid issuer attestation');
  return Object.freeze({version, text: text(data['text'], 500, 'Invalid issuer attestation')});
}

/** The final disclosure shape may nest under `disclosure`; both shapes are read. */
function parseIssuer(value: unknown, legacyOffered: (issuerId: string) => boolean): TradingIssuer {
  const detail = 'Invalid trading issuer';
  const outer = record(value, detail);
  const nested = outer['disclosure'];
  const data = nested !== null && typeof nested === 'object' && !Array.isArray(nested) ? {...outer, ...nested as Record<string, unknown>} : outer;
  const issuerId = data['issuerId'];
  if (typeof issuerId !== 'string' || !ISSUER_ID.test(issuerId)) fail(detail);
  const regions = data['excludedRegions'] ?? [];
  if (!Array.isArray(regions) || regions.length > 250) fail(detail);
  const termsUrl = text(data['termsUrl'], 2048, detail);
  let terms: URL;
  try {terms = new URL(termsUrl);} catch {fail(detail);}
  if (terms.protocol !== 'https:' || !terms.hostname || terms.username || terms.password) fail(detail);
  const offered = outer['offered'];
  if (offered !== undefined && offered !== null && typeof offered !== 'boolean') fail(detail);
  const reason = prose(outer['notOfferedReason'], 500, detail);
  const route = outer['route'] ?? data['route'];
  return Object.freeze({
    issuerId, name: text(data['name'], 80, detail),
    legalName: prose(data['legalName'], 160, detail), productType: prose(data['productType'], 80, detail),
    summary: prose(data['summary'], 1000, detail), holderRights: prose(data['holderRights'], 500, detail),
    warning: prose(data['warning'], 1000, detail),
    excludedRegions: Object.freeze(regions.map(region => text(region, 80, detail))),
    termsUrl: terms.href, attestation: parseAttestation(data['attestation']),
    // An older issuer-aware server does not say: an issuer with tokens is offered.
    offered: typeof offered === 'boolean' ? offered : legacyOffered(issuerId),
    notOfferedReason: reason || null,
    route: route === 'aggregator' || route === 'rfq' ? route : null,
  });
}

const LEGACY_XSTOCKS: TradingIssuer = Object.freeze({
  issuerId: 'xstocks', name: 'xStocks', legalName: 'Backed Assets (JE) Limited', productType: '', summary: '',
  holderRights: '', warning: '', excludedRegions: Object.freeze([]), termsUrl: 'https://assets.backed.fi/legal-documentation',
  attestation: Object.freeze({version: 'legacy', get text() {return t('money.issuer.legacyAttestation');}}),
  offered: true, notOfferedReason: null, route: 'aggregator',
});

const CODE = /^[a-z0-9_]{1,64}$/;
const instant = (value: unknown): string | null => typeof value === 'string' && value.length <= 40 && Number.isFinite(Date.parse(value)) ? value : null;
/** A present but unreadable state fails closed; a missing one leaves the decision to the order review. */
export function parseMarketState(value: unknown): MarketState | null {
  if (value === undefined || value === null) return null;
  const fields = typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
  const wire = typeof fields['status'] === 'string' ? fields['status'].slice(0, 40) : 'missing';
  const sessions = Array.isArray(fields['sessions']) ? fields['sessions'].filter((item): item is string => typeof item === 'string' && CODE.test(item)).slice(0, 8) : [];
  return Object.freeze({status: ['open', 'paused', 'closed'].includes(wire) ? wire as MarketStatus : 'unknown', wireStatus: wire,
    reason: typeof fields['reason'] === 'string' && CODE.test(fields['reason']) ? fields['reason'] : null,
    usSessions: fields['hours'] === 'us_sessions', sessions: Object.freeze(sessions),
    session: typeof fields['session'] === 'string' && CODE.test(fields['session']) ? fields['session'] : null,
    nextOpenAt: instant(fields['nextOpenAt']), closesAt: instant(fields['closesAt'])});
}

/**
 * A local time as a short phrase: `4:01 AM`, `tomorrow 9:31 AM`, `Mon 1:05 AM` or `Oct 5, 9:31 AM` (mobile liveMarketTime).
 * English keeps mobile's words; other languages write the clock, weekday and date as the reader's region does.
 */
export function marketTime(at: string, now = Date.now()): string {
  const local = new Date(at), today = new Date(now), english = fmt.isEnglish();
  const hour = local.getHours() % 12 === 0 ? 12 : local.getHours() % 12;
  const clock = english ? `${hour}:${String(local.getMinutes()).padStart(2, '0')} ${local.getHours() < 12 ? 'AM' : 'PM'}`
    : fmt.time(local, 'en-US', {hour: 'numeric', minute: '2-digit'});
  // The hour as shown also picks words, as in Spanish "a la 1:05" and "a las 9:30".
  const time = new fmt.Shown(Number(/[0-9]+/u.exec(clock)?.[0] ?? hour), clock);
  const days = Math.round((new Date(local.getFullYear(), local.getMonth(), local.getDate()).getTime() -
    new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()) / 86_400_000);
  if (days <= 0) return t('money.market.when.today', {time});
  if (days === 1) return t('money.market.when.tomorrow', {time});
  if (days < 7) return t('money.market.when.weekday', {time, day: english ? ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][local.getDay()]
    : fmt.date(local, 'en-US', {weekday: 'short'})});
  return t('money.market.when.date', {time, date: english ? `${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][local.getMonth()]} ${local.getDate()}`
    : fmt.date(local, 'en-US', {month: 'short', day: 'numeric'})});
}

/** One short line, such as `Closed · opens Mon 1:05 AM`, in mobile's words. */
export function marketLabel(state: MarketState, now = Date.now()): string {
  const next = state.nextOpenAt === null ? null : marketTime(state.nextOpenAt, now);
  if (state.status === 'open') return t(!state.usSessions ? 'money.market.open247' : state.sessions.includes('offhours') ? 'money.market.openWeekends' : 'money.market.openNow');
  if (state.status === 'paused') {
    if (state.reason === 'issuer_paused') return t('money.market.issuerPaused');
    if (state.reason === 'market_paused') return next === null ? t('money.market.marketPaused') : t('money.market.pausedResumes', {when: next});
    return next === null ? t('money.market.shortPause') : t('money.market.shortPauseResumes', {when: next});
  }
  if (state.status === 'closed') return next === null ? t('money.market.closed') : t('money.market.closedOpens', {when: next});
  return t('money.market.notTrading');
}

/** When a token that follows US sessions trades, in one sentence; null for tokens that trade around the clock. */
export function marketHours(state: MarketState): string | null {
  if (!state.usSessions) return null;
  const sessions = new Set(state.sessions);
  if (['overnight', 'premarket', 'regular', 'postmarket'].every(session => sessions.has(session))) {
    return t(sessions.has('offhours') ? 'money.market.hours.aroundClock' : 'money.market.hours.weekdays');
  }
  if (sessions.size === 1 && sessions.has('regular')) return t('money.market.hours.regular');
  return t('money.market.hours.sessions');
}

function parseAsset(value: unknown, legacy: boolean): TradingAsset {
  const detail = 'Invalid trading asset';
  const data = record(value, detail);
  const {assetId, mint, decimals} = data;
  if (typeof assetId !== 'string' || !ASSET_ID.test(assetId) || typeof mint !== 'string' || !MINT.test(mint) || mint === USDC_MINT) fail(detail);
  if (typeof decimals !== 'number' || !Number.isInteger(decimals) || decimals < 0 || decimals > 18) fail('Invalid trading precision');
  const limit = (key: string): string => {
    const raw = data[key] ?? (legacy ? '100000000' : undefined);
    if (typeof raw !== 'string' || !RAW_LIMIT.test(raw)) fail('Invalid trading limit');
    return raw;
  };
  const symbol = text(data['symbol'], 32, detail);
  let issuerId = 'xstocks', fee = 0;
  if (!legacy) {
    const issuer = data['issuerId'], bps = data['transferFeeBps'] ?? 0;
    if (typeof issuer !== 'string' || !ISSUER_ID.test(issuer)) fail(detail);
    if (typeof bps !== 'number' || !Number.isInteger(bps) || bps < 0 || bps > 1000) fail('Invalid issuer fee');
    issuerId = issuer; fee = bps;
  }
  const route = data['route'];
  if (route !== undefined && route !== null && route !== 'aggregator' && route !== 'rfq') fail(detail);
  const minimum = data['minBuyInputRaw'];
  return Object.freeze({assetId, mint, symbol, name: legacy && typeof data['name'] !== 'string' ? symbol : text(data['name'], 160, detail),
    decimals, maxBuyInputRaw: limit('maxBuyInputRaw'), maxSellInputRaw: limit('maxSellInputRaw'), issuerId,
    transferFeeBps: fee, route: route === 'rfq' ? 'rfq' : 'aggregator',
    minBuyInputRaw: !legacy && typeof minimum === 'string' && RAW_LIMIT.test(minimum) ? minimum : '1',
    market: legacy ? null : parseMarketState(data['market'])});
}

/** The list only words a reason, so a malformed row is skipped rather than taking trading down. */
function parseUnavailable(value: unknown): Map<string, UnavailableVariant> {
  const rows = new Map<string, UnavailableVariant>();
  if (value === undefined || value === null) return rows;
  if (!Array.isArray(value) || value.length > CAPABILITIES_MAX_UNAVAILABLE) fail('Invalid unavailable tokens');
  for (const row of value) {
    if (row === null || typeof row !== 'object') continue;
    const {mint, issuerId, reason, symbol, market} = row as Record<string, unknown>;
    if (typeof mint !== 'string' || !MINT.test(mint) || issuerId !== null && issuerId !== undefined &&
        (typeof issuerId !== 'string' || !ISSUER_ID.test(issuerId)) || typeof reason !== 'string' || !REASON.test(reason)) continue;
    if (!rows.has(mint)) rows.set(mint, Object.freeze({mint, issuerId: typeof issuerId === 'string' ? issuerId : null, reason,
      symbol: optionalText(symbol, 32), market: parseMarketState(market)}));
  }
  return rows;
}

const NOT_OFFERED: MessageKey = 'money.reason.notOffered';
const REASONS: Readonly<Record<string, MessageKey>> = Object.freeze({
  identity_unverified: 'money.reason.identityUnverified',
  token_restricted: 'money.reason.tokenRestricted',
  low_liquidity: 'money.reason.lowLiquidity',
  no_reviewed_route: 'money.reason.noReviewedRoute',
  price_off_market: 'money.reason.priceOffMarket',
  held_back: 'money.reason.heldBack',
  not_reviewed: 'money.reason.notReviewed',
  market_closed: 'money.reason.marketClosed',
  awaiting_review: 'money.reason.awaitingReview',
  no_market_maker_quote: 'money.reason.noMarketMakerQuote',
});


export class TradingCapabilities {
  readonly #byMint: Map<string, TradingAsset>;
  readonly #byAssetId: Map<string, TradingAsset[]>;
  /** Tokens Real mode can list for sale: the issuer must be offered. Computed once. */
  readonly tradeableAssets: readonly TradingAsset[];
  constructor(
    /** 1 for servers that predate issuer terms, 2 for issuer-aware servers. */
    readonly schemaVersion: 1 | 2, readonly enabled: boolean, readonly assets: readonly TradingAsset[],
    readonly issuers: ReadonlyMap<string, TradingIssuer>, readonly unavailable: ReadonlyMap<string, UnavailableVariant>,
    readonly minimumSolBalanceLamports: string, readonly maxBuyUsdc: string | null,
    readonly usMarket: UsMarket | null = null,
  ) {
    this.#byMint = new Map(assets.map(asset => [asset.mint, asset]));
    this.#byAssetId = new Map();
    for (const asset of assets) {
      const group = this.#byAssetId.get(asset.assetId);
      if (group) group.push(asset); else this.#byAssetId.set(asset.assetId, [asset]);
    }
    this.tradeableAssets = Object.freeze(assets.filter(asset => issuers.get(asset.issuerId)?.offered === true));
  }
  get legacy(): boolean {return this.schemaVersion < 2;}
  forMint(mint: string | null | undefined): TradingAsset | null {return mint ? this.#byMint.get(mint) ?? null : null;}
  issuerFor(asset: TradingAsset): TradingIssuer {
    const issuer = this.issuers.get(asset.issuerId);
    if (!issuer) throw new CapabilitiesError('Unknown trading issuer');
    return issuer;
  }
  /** Offered and inside its market hours (or without market hours). */
  tradeableNow(asset: TradingAsset): boolean {
    return this.enabled && this.issuers.get(asset.issuerId)?.offered === true && (asset.market === null || asset.market.status === 'open');
  }
  variantLabel(asset: TradingAsset): string {return `${this.issuers.get(asset.issuerId)?.name ?? t('money.issuer.fallbackName')} · ${asset.symbol}`;}

  /**
   * Every offered token of a company, most liquid first. With discovery's own
   * token list, tokens are matched by mint: the API lists each token under one
   * Market asset, which need not share the registry's company id. Without a
   * discovery list only the company id is matched.
   */
  variantsFor(assetId: string, discovery?: readonly DiscoveryVariantRef[]): readonly TradingAsset[] {
    const liquidity = discovery ? new Map(discovery.map(v => [v.mint, v.liquidityUsd ?? null])) : null;
    // Indexed by mint: a handful of lookups per company, never a scan of every token.
    const candidates = liquidity ? [...liquidity.keys()].map(mint => this.#byMint.get(mint)).filter((asset): asset is TradingAsset => asset !== undefined)
      : this.#byAssetId.get(assetId) ?? [];
    const matched = candidates.map((asset, index) => ({asset, index})).filter(({asset}) => this.issuers.get(asset.issuerId)?.offered === true);
    matched.sort((a, b) => {
      const left = liquidity?.get(a.asset.mint) ?? null, right = liquidity?.get(b.asset.mint) ?? null;
      if (left !== null && right !== null && left !== right) return right - left;
      if ((left === null) !== (right === null)) return left === null ? 1 : -1;
      return a.index - b.index;
    });
    return matched.map(row => row.asset);
  }

  /** Every token discovery lists for the company: tradeable ones first, the rest with a reason. */
  optionsFor(assetId: string, discovery: readonly DiscoveryVariantRef[], fallbackSymbol: string, now = Date.now()): readonly VariantOption[] {
    const offered = this.variantsFor(assetId, discovery);
    const mints = new Set(offered.map(asset => asset.mint));
    const open = offered.filter(asset => this.tradeableNow(asset)), waiting = offered.filter(asset => !this.tradeableNow(asset));
    return [
      ...[...open, ...waiting].map(asset => Object.freeze({mint: asset.mint, label: this.variantLabel(asset), asset,
        issuer: this.issuers.get(asset.issuerId) ?? null, reason: this.tradeableNow(asset) ? null : this.reasonFor(asset.mint, now),
        tradeable: this.tradeableNow(asset)})),
      ...discovery.filter(variant => !mints.has(variant.mint)).map(variant => {
        const issuerId = this.#byMint.get(variant.mint)?.issuerId ?? this.unavailable.get(variant.mint)?.issuerId ?? null;
        const issuer = issuerId ? this.issuers.get(issuerId) ?? null : null;
        return Object.freeze({mint: variant.mint,
          label: `${issuer?.name ?? variant.issuer ?? variant.label ?? t('money.issuer.otherName')} · ${this.#byMint.get(variant.mint)?.symbol ?? variant.symbol ?? this.unavailable.get(variant.mint)?.symbol ?? variant.label ?? fallbackSymbol}`,
          asset: null, issuer, reason: this.reasonFor(variant.mint, now), tradeable: false});
      }),
    ];
  }

  /** Why a token cannot be traded right now, in one short plain sentence. */
  reasonFor(mint: string, now = Date.now()): string {
    if (!this.enabled) return t('money.reason.tradingPaused');
    const asset = this.#byMint.get(mint);
    if (asset) {
      const issuer = this.issuers.get(asset.issuerId);
      if (issuer && !issuer.offered) return issuer.notOfferedReason ?? t(NOT_OFFERED);
      if (asset.market && asset.market.status !== 'open') return t('money.market.sentence', {status: marketLabel(asset.market, now)});
      // Offered, but discovery does not list this token for the company shown.
      return t('money.reason.notYet');
    }
    const row = this.unavailable.get(mint);
    if (!row) return t('money.reason.notYet');
    if (row.reason === 'issuer_not_offered') return (row.issuerId && this.issuers.get(row.issuerId)?.notOfferedReason) || t(NOT_OFFERED);
    if (row.reason === 'market_closed' && row.market?.nextOpenAt) return t('money.reason.opensThenChecks', {when: marketTime(row.market.nextOpenAt, now)});
    return t(Object.hasOwn(REASONS, row.reason) ? REASONS[row.reason]! : 'money.reason.unavailable');
  }

  /** Whether Real mode can trade some token of this company right now. */
  companyTradeable(assetId: string, discovery?: readonly DiscoveryVariantRef[]): boolean {
    return this.enabled && this.variantsFor(assetId, discovery).some(asset => this.tradeableNow(asset));
  }
}

export function parseTradingCapabilities(value: unknown): TradingCapabilities {
  const data = record(value, 'Invalid trading capabilities');
  if (typeof data['enabled'] !== 'boolean' || data['network'] !== 'solana:mainnet-beta' || !Array.isArray(data['assets'])) {
    fail('Invalid trading capabilities');
  }
  const version = data['schemaVersion'];
  const legacy = (version === undefined || version === null || version === 1) && !('issuers' in data);
  // Schema 3 reads keep the version 2 shape; a version 3 payload is read the same way.
  if (!legacy && version !== 2 && version !== 3) fail('Unsupported trading capabilities');
  const rows = data['assets'] as unknown[];
  if (rows.length > CAPABILITIES_MAX_ASSETS) fail('Too many assets');
  const assets = rows.map(row => parseAsset(row, legacy));
  if (new Set(assets.map(asset => asset.mint)).size !== assets.length) fail('Duplicate trading mint');
  const issuers = new Map<string, TradingIssuer>();
  if (legacy) issuers.set('xstocks', LEGACY_XSTOCKS);
  else {
    const list = data['issuers'];
    if (!Array.isArray(list) || list.length > MAX_ISSUERS) fail('Invalid trading issuers');
    for (const row of list) {
      const issuer = parseIssuer(row, id => assets.some(asset => asset.issuerId === id));
      if (issuers.has(issuer.issuerId)) fail('Duplicate trading issuer');
      issuers.set(issuer.issuerId, issuer);
    }
  }
  if (assets.some(asset => !issuers.has(asset.issuerId))) fail('Unknown trading issuer');
  const minimum = data['minimumSolBalanceLamports'];
  if (typeof minimum !== 'string' || !/^[0-9]{1,16}$/.test(minimum)) fail('Invalid fee reserve');
  const maxBuy = typeof data['maxBuyUsdc'] === 'string' && /^[0-9]{1,12}$/.test(data['maxBuyUsdc']) ? data['maxBuyUsdc'] : null;
  const us = data['usMarket'];
  const usMarket = us && typeof us === 'object' && !Array.isArray(us) ? Object.freeze({
    session: typeof (us as Record<string, unknown>)['session'] === 'string' ? (us as Record<string, string>)['session']! : null,
    between: typeof (us as Record<string, unknown>)['between'] === 'string' ? (us as Record<string, string>)['between']! : null,
    changesAt: instant((us as Record<string, unknown>)['changesAt'])}) : null;
  return new TradingCapabilities(legacy ? 1 : 2, data['enabled'], Object.freeze(assets), issuers,
    legacy ? new Map() : parseUnavailable(data['unavailable']), minimum, maxBuy, usMarket);
}
