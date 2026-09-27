import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {ProductApp} from '../../src/product/ProductApp.js';
import {ProductMarketClient} from '../../src/product/market-client.js';
import {PracticeClient, PORTFOLIO_MEDIA_TYPE, PROFILE_MEDIA_TYPE} from '../../src/product/practice-client.js';
import type {LaunchCheckpoint} from '../../src/product/practice-client.js';
import type {PracticeStorage} from '../../src/product/practice-session.js';
import {JourneyStore} from '../../src/product/journey-store.js';
import {ProductApiClient} from '../../src/product/product-api.js';
import {searchFixture, variantFixture, variantsFixture} from '../../src/markets/fixtures.test-support.js';
import {RESEARCH_AAPLX_MINT as MINT, RESEARCH_USDC_MINT as TESLA_MINT} from '../../src/markets/estimate.js';

/** Shared ProductApp harness for the first-day, recovery, settings and social tests. */
export const GUEST_ID = '11111111-1111-4111-8111-111111111111';
export const ACCOUNT_ID = '22222222-2222-4222-8222-222222222222';
export const PREVIEW_ID = '44444444-4444-4444-8444-444444444444';
export const ORDER_ID = '33333333-3333-4333-8333-333333333333';
export class MemoryStorage implements PracticeStorage {
  readonly data = new Map<string, string>();
  getItem(key: string) {return this.data.get(key) ?? null;}
  setItem(key: string, value: string) {this.data.set(key, value);}
}
export interface Call {path: string; url: string; method: string; body: Record<string, unknown> | null}
export const json = (value: unknown, status = 200, media = 'application/json') => Response.json(value, {status, headers: {'content-type': media}});

/** A small fake of the practice API with the server's real launch transition table. */
export type Reply = (call: Call) => Promise<Response> | Response | undefined;
export function server(options: {checkpoint?: LaunchCheckpoint | null; traded?: boolean; reply?: Reply} = {}) {
  const now = Date.now(), at = new Date(now).toISOString();
  const state = {
    profile: options.checkpoint === null || options.checkpoint === undefined ? null : {revision: 3,
      onboarding: {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null},
      launchCheckpoint: options.checkpoint, hasConfirmedPaperTrade: options.traded ?? options.checkpoint !== 'first-trade', createdAt: at, updatedAt: at},
    traded: options.traded ?? (options.checkpoint !== null && options.checkpoint !== undefined && options.checkpoint !== 'first-trade'),
    lastRequestId: GUEST_ID, launches: [] as string[], resets: 0,
    privacy: {revision: 1, visibility: 'nobody', configured: false, friendsSharing: 'unavailable', createdAt: at, updatedAt: at} as Record<string, unknown>,
    closed: false,
    career: {revision: 0, total: 0, rank: 'rookie', next: {id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 300, promotionRequired: true} as Record<string, unknown> | null},
    missions: [] as Record<string, unknown>[],
    dayContext: {revision: 1, timeZone: 'UTC', configured: false, serverDate: at.slice(0, 10), nextDayAt: new Date(now + 6 * 3600000).toISOString(), createdAt: at, updatedAt: at} as Record<string, unknown>,
    reasons: [] as Record<string, unknown>[], promotions: [] as Record<string, unknown>[],
    following: {revision: 0, assetIds: [] as string[], updatedAt: null as string | null},
    sharedReasons: [] as Record<string, unknown>[], ownReasons: [] as Record<string, unknown>[], reports: [] as Record<string, unknown>[],
    holders: [{owner: 'So11111111111111111111111111111111111111112', primaryDomain: 'bigholder.sol', amount: '1250.5', tokenAccounts: 2},
      {owner: 'Vote111111111111111111111111111111111111111', primaryDomain: null, amount: '12.25', tokenAccounts: 1}] as Record<string, unknown>[],
  };
  const refreshAfter = new Date(now + 60000).toISOString();
  const facts = {schemaVersion: 1, provider: 'tokens-xyz-v1', requestedAt: at, observedAt: at, refreshAfter, displayOnly: true, executionEnabled: false, eligibility: 'unverified'};
  const companies = [
    {assetId: 'apple', name: 'Apple', symbol: 'AAPL', mint: MINT, token: 'AAPLx', price: 51, change: -1},
    {assetId: 'tesla', name: 'Tesla', symbol: 'TSLA', mint: TESLA_MINT, token: 'TSLAx', price: 250, change: 3},
  ];
  const variantOf = (company: typeof companies[number]) => ({...variantFixture(), variantId: `${company.assetId}-xstock`, mint: company.mint,
    name: `${company.name} xStock`, label: `${company.name} xStock`, symbol: company.token});
  const cardOf = (company: typeof companies[number]) => ({assetId: company.assetId, name: company.name, symbol: company.symbol, imageUrl: null,
    stock: {priceUsd: company.price, changePercent24h: company.change, asOfUnixSeconds: Math.floor(now / 1000)},
    primaryVariant: {mint: company.mint, symbol: company.token, logoUrl: null, priceUsd: company.price, changePercent24h: company.change}});
  const source = {provider: 'tokens-xyz-v1', providerReference: '/v1/assets/apple', marketSource: null, metricsSource: null,
    providerTimestamps: {asOf: null, lastFetchedAt: null, lastTradeAt: null, unit: 'not_declared'}, observedAt: at, acceptedAt: at};
  const calculation = {action: 'buy', assetId: 'apple', variantMint: MINT, symbol: 'AAPLx', accountRevision: 0, pricePaperMicros: '50000000',
    quantityMicros: '2000000', cashDebitPaperMicros: '100000000', cashCreditPaperMicros: '0', cashAfterPaperMicros: '9900000000',
    positionQuantityAfterMicros: '2000000', positionCostBasisAfterPaperMicros: '100000000', realizedGainDeltaPaperMicros: '0', lockedGainDeltaPaperMicros: '0', source};
  const envelope = (kind: string, value: unknown) => ({schemaVersion: 1, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, [kind]: value,
    fees: {paperMicros: '0'}, reward: {trimsAwarded: 0, reason: 'Trade completion alone does not award Trims.'},
    execution: {walletUsed: false, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false}});
  const portfolio = () => {
    const base = {schemaVersion: 2, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, startingCashPaperMicros: '10000000000'};
    if (!state.traded) return {...base, revision: state.resets ? 1 + state.resets : 0, cashPaperMicros: '10000000000', openedAt: null, updatedAt: null, positions: [], recentOrders: [],
      valuation: {status: 'complete', portfolioRevision: state.resets ? 1 + state.resets : 0, openPositionCount: 0, pricedPositionCount: 0, cashPaperMicros: '10000000000',
        knownValuePaperMicros: '10000000000', totalPaperMicros: '10000000000', positions: []}};
    return {...base, revision: 1, cashPaperMicros: '9900000000', openedAt: at, updatedAt: at,
      positions: [{assetId: 'apple', variantMint: MINT, symbol: 'AAPLx', quantityMicros: '2000000', costBasisPaperMicros: '100000000',
        averageCostPricePaperMicros: '50000000', realizedGainPaperMicros: '0', lockedGainPaperMicros: '0', updatedAt: at}],
      recentOrders: [{...calculation, accountRevision: 1, id: ORDER_ID, previewId: PREVIEW_ID, committedAt: at}],
      valuation: {status: 'complete', portfolioRevision: 1, openPositionCount: 1, pricedPositionCount: 1, cashPaperMicros: '9900000000',
        knownValuePaperMicros: '10000000000', totalPaperMicros: '10000000000', positions: [{assetId: 'apple', variantMint: MINT, status: 'priced',
          pricePaperMicros: '50000000', marketValuePaperMicros: '100000000', unrealizedGainPaperMicros: '0', observedAt: at, acceptedAt: at,
          expiresAt: new Date(now + 600000).toISOString()}]}};
  };
  const guest = {guestId: GUEST_ID, token: `tg1_${'A'.repeat(43)}`, expiresAt: new Date(now + 30 * 86400000).toISOString(), hardExpiresAt: new Date(now + 60 * 86400000).toISOString()};
  const calls: Call[] = [];
  const fetcher: typeof fetch = async (url, init = {}) => {
    const parsed = new URL(String(url), 'https://trimmy.example');
    const call: Call = {path: parsed.pathname.replace(/^\/api/, ''), url: parsed.href, method: init.method ?? 'GET', body: init.body ? JSON.parse(String(init.body)) as Record<string, unknown> : null};
    calls.push(call);
    const override = options.reply?.(call); if (override !== undefined) return override;
    if (call.path === '/v1/guest/session') return json({schemaVersion: 1, requestId: call.body?.['requestId'], ...guest}, 201);
    if (call.path === '/v1/guest/session/refresh') return json({schemaVersion: 1, ...guest});
    if (call.path === '/v1/product/profile') {
      if (call.method === 'PUT') state.profile = {revision: Number(call.body?.['baseRevision']) + 1, onboarding: call.body?.['onboarding'] as never,
        launchCheckpoint: call.body?.['launchCheckpoint'] as LaunchCheckpoint, hasConfirmedPaperTrade: state.traded, createdAt: at, updatedAt: at};
      return json({schemaVersion: 2, profile: state.profile}, 200, PROFILE_MEDIA_TYPE);
    }
    if (call.path === '/v1/product/launch') {
      const action = String(call.body?.['action']), profile = state.profile;
      if (!profile || profile.launchCheckpoint === 'app' || call.body?.['baseRevision'] !== profile.revision ||
        (action === 'paper-trade-confirmed' && profile.launchCheckpoint !== 'first-trade')) {
        return json({error: {code: 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT', message: 'Conflict.', requestId: GUEST_ID}}, 409);
      }
      if ((action === 'paper-trade-confirmed' || action === 'introduction-completed') && !state.traded) {
        return json({error: {code: 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED', message: 'Trade required.', requestId: GUEST_ID}}, 409);
      }
      state.launches.push(action);
      state.profile = {...profile, revision: profile.revision + 1, launchCheckpoint: action === 'paper-trade-confirmed' ? 'first-position' : 'app', hasConfirmedPaperTrade: state.traded};
      return json({schemaVersion: 2, profile: state.profile}, 200, PROFILE_MEDIA_TYPE);
    }
    if (call.path === '/v1/account/paper/portfolio') return json(portfolio(), 200, PORTFOLIO_MEDIA_TYPE);
    if (call.path === '/v1/account/paper/reset') {
      const current = portfolio() as {revision: number};
      if (call.body?.['confirm'] !== 'reset my paper desk') return json({error: {code: 'PAPER_INPUT_INVALID', message: 'Invalid.', requestId: GUEST_ID}}, 400);
      if (call.body?.['baseRevision'] !== current.revision) return json({error: {code: 'PAPER_PORTFOLIO_CHANGED', message: 'Changed.', requestId: GUEST_ID}}, 409);
      if (!state.traded) return json({error: {code: 'PAPER_RESET_NOT_NEEDED', message: 'Fresh.', requestId: GUEST_ID}}, 409);
      state.traded = false; state.resets++;
      const revision = 1 + state.resets;
      return json({schemaVersion: 1, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6},
        reset: {mutationId: call.body?.['mutationId'], previousRevision: current.revision, revision, resetAt: at},
        portfolioAtReset: {revision, startingCashPaperMicros: '10000000000', cashPaperMicros: '10000000000', positions: [], recentOrders: []}});
    }
    if (call.path === '/v1/career/reason-privacy') {
      if (call.method === 'PUT') {
        if (call.body?.['baseRevision'] !== state.privacy['revision']) return json({error: {code: 'CAREER_REASON_PRIVACY_REVISION_CONFLICT', message: 'Conflict.', requestId: GUEST_ID}}, 409);
        state.privacy = {...state.privacy, revision: Number(state.privacy['revision']) + 1, visibility: call.body?.['visibility'], configured: true,
          updatedAt: new Date(Date.parse(String(state.privacy['updatedAt'])) + 1000).toISOString()};
      }
      return json({schemaVersion: 1, reasonPrivacy: state.privacy});
    }
    if (call.path === '/v1/account/closure') {
      if (call.body?.['confirm'] !== 'close my account') return json({error: {code: 'ACCOUNT_CLOSURE_INVALID_INPUT', message: 'Invalid.', requestId: GUEST_ID}}, 400);
      state.closed = true;
      return json({schemaVersion: 1, closed: true, canceledInvitations: 0, note: 'This account can no longer sign in. Saved practice history is kept and is no longer reachable.'});
    }
    if (call.path === '/v1/account/paper/orders/preview') {
      state.lastRequestId = String(call.body?.['requestId']);
      return json(envelope('preview', {...calculation, id: PREVIEW_ID, requestId: state.lastRequestId, state: 'open',
        amount: {kind: 'paper_amount', paperMicros: '100000000'}, expiresAt: new Date(Date.now() + 30000).toISOString(), committedAt: null}));
    }
    if (call.path === '/v1/account/paper/orders/commit') {
      state.traded = true; if (state.profile) state.profile = {...state.profile, hasConfirmedPaperTrade: true};
      return json(envelope('order', {...calculation, accountRevision: 1, id: ORDER_ID, previewId: PREVIEW_ID, committedAt: at}));
    }
    if (call.path === '/v1/career/summary') return json({schemaVersion: 1, career: {revision: state.career.revision, trims: {total: state.career.total, today: 0, thisWeek: 0},
      rank: {id: state.career.rank, label: state.career.rank === 'rookie' ? 'Rookie' : 'Analyst', paperLimit: '10000', threshold: state.career.rank === 'rookie' ? 0 : 300}, nextRank: state.career.next,
      streak: {days: 0, status: 'not-started', lastActiveDate: null}, careerStarted: state.career.total > 0,
      firstConfirmedBuy: state.traded ? {orderId: ORDER_ID, assetId: 'apple', variantMint: MINT, symbol: 'AAPLx', quantityMicros: '2000000', confirmedAt: at} : null,
      serverDate: at.slice(0, 10), updatedAt: null}});
    if (call.path === '/v1/career/missions') return json({schemaVersion: 1, career: {revision: state.career.revision, currentRank: state.career.rank}, missions: state.missions});
    if (call.path === '/v1/career/promotions') {
      const replay = state.promotions.find(item => item['mutationId'] === call.body?.['mutationId']);
      if (replay) return json({schemaVersion: 1, promotion: replay}, 201);
      if (call.body?.['targetRank'] !== 'analyst' || state.career.rank !== 'rookie') return json({error: {code: 'CAREER_PROMOTION_RANK_MISMATCH', message: 'No.', requestId: GUEST_ID}}, 409);
      state.career = {revision: state.career.revision + 1, total: state.career.total + 100, rank: 'analyst', next: {id: 'trader', label: 'Trader', threshold: 800, trimsRemaining: 400, promotionRequired: false}};
      state.missions = state.missions.map(item => ({...item, chapterRank: item['chapterRank']}));
      const promotion = {mutationId: call.body?.['mutationId'], fromRank: 'rookie', toRank: 'analyst', careerRevision: state.career.revision, trimsAwarded: 100, promotedAt: at};
      state.promotions.push(promotion);
      return json({schemaVersion: 1, promotion}, 201);
    }
    if (call.path === '/v1/career/trade-reasons' && call.method === 'POST') {
      const replay = state.reasons.find(item => item['mutationId'] === call.body?.['mutationId']);
      if (!replay && state.reasons.some(item => item['orderId'] === call.body?.['orderId'])) return json({error: {code: 'CAREER_REASON_EXISTS', message: 'Exists.', requestId: GUEST_ID}}, 409);
      const reason = replay ?? {mutationId: call.body?.['mutationId'], orderId: call.body?.['orderId'], note: call.body?.['note']};
      if (!replay) {state.reasons.push(reason); state.career = {...state.career, revision: state.career.revision + 1, total: state.career.total + 20};
        state.missions = state.missions.map(item => item['id'] === 'write-a-reason' ? {...item, status: 'complete', completedAt: at} : item);}
      return json({schemaVersion: 1, reason: {orderId: reason['orderId'], assetId: 'apple', variantMint: MINT, note: reason['note'], trimsAwarded: 20, dailyAwardNumber: 1, savedAt: at}}, 201);
    }
    if (call.path === '/v1/career/day-context') {
      if (call.method === 'PUT') {
        if (state.dayContext['configured'] || call.body?.['baseRevision'] !== state.dayContext['revision']) return json({error: {code: 'CAREER_DAY_CONTEXT_REVISION_CONFLICT', message: 'Conflict.', requestId: GUEST_ID}}, 409);
        state.dayContext = {...state.dayContext, revision: 2, timeZone: call.body?.['timeZone'], configured: true, updatedAt: new Date(now + 1000).toISOString()};
      }
      return json({schemaVersion: 1, dayContext: state.dayContext});
    }
    if (call.path.endsWith('/search')) {
      const page = {...searchFixture(parsed.searchParams.get('query')!, Number(parsed.searchParams.get('limit'))), requestedAt: at, observedAt: at,
        refreshAfter: new Date(now + 60000).toISOString()};
      page.results = [{...page.results[0]!, variants: [variantFixture()]}];
      return json(page);
    }
    if (call.path.endsWith('/facts')) {
      const company = companies.find(item => item.assetId === parsed.searchParams.get('assetId')) ?? companies[0]!;
      return json({...facts, sourceUrls: [`https://api.tokens.xyz/v1/assets/${company.assetId}`], assetId: company.assetId, name: company.name, symbol: company.symbol,
        imageUrl: null, description: `${company.name} makes things.`, stock: cardOf(company).stock, sparkline: null, sparklineStatus: 'unavailable'});
    }
    if (call.path.endsWith('/catalog')) {
      const discovery = {...searchFixture('catalog', 20), requestedAt: at, observedAt: at, refreshAfter};
      discovery.results = companies.map(company => ({...discovery.results[0]!, assetId: company.assetId, name: company.name, symbol: company.symbol,
        providerPrimaryVariantMint: company.mint, variants: [variantOf(company)]}));
      return json({discovery, cards: companies.map(cardOf), offset: 0, total: companies.length, nextOffset: null});
    }
    if (call.path.endsWith('/cards')) {
      const query = parsed.searchParams.get('query') ?? '';
      return json({...facts, sourceUrl: 'https://api.tokens.xyz/v1/assets/search', query, limit: 20, completeCatalog: false,
        results: companies.filter(company => company.name.toLowerCase().includes(query.toLowerCase())).map(cardOf)});
    }
    if (call.path.endsWith('/variants')) {
      const company = companies.find(item => item.assetId === parsed.searchParams.get('assetId')) ?? companies[0]!;
      return json({...variantsFixture(company.assetId), requestedAt: at, observedAt: at, refreshAfter, variants: [variantOf(company)]});
    }
    if (call.path.endsWith('/insight')) {
      const company = companies.find(item => item.assetId === parsed.searchParams.get('assetId')) ?? companies[0]!;
      return json({...facts, assetId: company.assetId, mint: parsed.searchParams.get('mint'), period: parsed.searchParams.get('period'), symbol: company.token,
        description: null, priceUsd: company.price, changePercent24h: company.change, asOfUnixSeconds: Math.floor(now / 1000), volume24hUsd: 1000, liquidityUsd: 2000,
        tokenMarketCapUsd: 100000, stockMarketCapUsd: 1000000000, holders: 30, points: [], chartStatus: 'empty'});
    }
    if (call.path === '/v1/markets/stocks/holders') return json({schemaVersion: 1, mint: parsed.searchParams.get('mint'), network: 'solana-mainnet',
      scope: 'largest-20-token-accounts', complete: false, observedAt: at, slot: '123456', sampledAccounts: 20, holders: state.holders});
    if (call.path === '/v1/following') {
      if (call.method === 'PUT') {
        if (call.body?.['baseRevision'] !== state.following.revision) return Response.json({error: {code: 'WATCHLIST_REVISION_CONFLICT', message: 'Changed.', requestId: GUEST_ID},
          currentSnapshot: {schemaVersion: 1, ...state.following}}, {status: 409, headers: {'content-type': 'application/json'}});
        state.following = {revision: state.following.revision + 1, assetIds: call.body?.['assetIds'] as string[], updatedAt: at};
      }
      return json({schemaVersion: 1, ...state.following});
    }
    if (call.path === '/v1/career/trade-reasons' && call.method === 'GET') {
      const scope = parsed.searchParams.get('scope'), assetId = parsed.searchParams.get('assetId'), variantMint = parsed.searchParams.get('variantMint');
      const rows = (scope === 'self' ? state.ownReasons : state.sharedReasons).filter(row => (row['stock'] as {assetId: string}).assetId === assetId);
      return json({schemaVersion: 1, scope, filter: assetId ? {assetId, variantMint} : null, reasons: rows, page: {limit: Number(parsed.searchParams.get('limit') ?? 20), nextCursor: null}});
    }
    if (call.path === '/v1/social/reason-reports') {
      state.reports.push(call.body ?? {});
      return json({schemaVersion: 1, report: {reportId: '66666666-6666-4666-8666-666666666666', reasonId: call.body?.['reasonId'], category: call.body?.['category'], receivedAt: at}}, 202);
    }
    return json({error: {code: 'NOT_IN_THIS_TEST', message: 'Not used by this test.', requestId: GUEST_ID}}, 404);
  };
  return {state, calls, fetcher};
}

export async function harness(options: {checkpoint?: LaunchCheckpoint | null; traded?: boolean; account?: boolean; savedGuest?: boolean;
  expireSavedGuest?: boolean; hash?: string; storage?: MemoryStorage; reply?: Reply; authEnabled?: boolean} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: `https://trimmy.example/${options.hash ?? ''}`, pretendToBeVisual: true});
  const saved = new Map<string, PropertyDescriptor | undefined>();
  const expose = (name: string, value: unknown) => {saved.set(name, Object.getOwnPropertyDescriptor(globalThis, name)); Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});};
  expose('window', dom.window); expose('document', dom.window.document); expose('navigator', dom.window.navigator);
  expose('HTMLElement', dom.window.HTMLElement); expose('Event', dom.window.Event); expose('localStorage', dom.window.localStorage);
  expose('crypto', webcrypto); expose('IS_REACT_ACT_ENVIRONMENT', true);
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: true, addEventListener() {}, removeEventListener() {}})});
  Object.defineProperty(dom.window.navigator, 'locks', {value: {request: async (_name: string, _options: unknown, callback: () => Promise<unknown>) => callback()}});
  const permission: string[] = [];
  Object.defineProperty(dom.window, 'Notification', {configurable: true, value: {permission: 'default', requestPermission: async () => {permission.push('asked'); return 'granted';}}});
  const api = server(options), storage = options.storage ?? new MemoryStorage();
  const practice = new PracticeClient({baseUrl: '/api', fetch: api.fetcher, timeoutMs: 1000});
  const market = new ProductMarketClient({baseUrl: '/api', fetch: api.fetcher, timeoutMs: 1000});
  const productApi = new ProductApiClient({baseUrl: '/api', fetch: api.fetcher, timeoutMs: 1000});
  const account = {subject: 'did:privy:journeyTester', accountId: ACCOUNT_ID, signal: new AbortController().signal, freshAccessToken: async () => 'test.account.proof'};
  const store = new JourneyStore(storage, '/api');
  if (options.savedGuest) {
    const {PracticeSession} = await import('../../src/product/practice-session.js');
    await new PracticeSession({client: practice, storage}).ensureGuest();
    if (options.expireSavedGuest) {
      const {practiceStorageKey} = await import('../../src/product/practice-session.js');
      const key = practiceStorageKey('/api'), record = JSON.parse(storage.getItem(key)!) as {guest: {expiresAt: string; hardExpiresAt: string}};
      record.guest.expiresAt = new Date(Date.now() - 2 * 86400000).toISOString(); record.guest.hardExpiresAt = new Date(Date.now() - 86400000).toISOString();
      storage.setItem(key, JSON.stringify(record));
    }
  }
  // Import React DOM only after the jsdom globals exist, or it falls back to legacy input handling.
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const flush = async (ms = 25) => {await act(async () => {await delay(ms);});};
  const app = async () => {
    await act(async () => {root.render(createElement(ProductApp, {apiBase: '/api', practiceClient: practice, marketClient: market, storage, productApi,
      authConfig: {kind: 'disabled'}, ...(options.account ? {accountAccess: account} : {})}));});
    await flush();
  };
  const reload = async () => {await act(async () => {root.render(createElement('div', null, 'Reloading'));}); await flush(); await app();};
  const text = () => dom.window.document.body.textContent ?? '';
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')].find(item => item.textContent?.trim() === label || item.getAttribute('aria-label') === label);
  const click = async (label: string) => {const target = button(label); assert.ok(target, `Button exists: ${label}`); await act(async () => {target.click();}); await flush();};
  const pick = async (label: string) => {
    const target = [...dom.window.document.querySelectorAll<HTMLButtonElement>('.setup-choice')].find(item => item.querySelector('strong')?.textContent === label);
    assert.ok(target, `Choice exists: ${label}`); await act(async () => {target.click();}); await flush();
  };
  const back = async () => {await act(async () => {dom.window.dispatchEvent(new dom.window.PopStateEvent('popstate'));}); await flush();};
  const escape = async () => {await act(async () => {dom.window.dispatchEvent(new dom.window.KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));}); await flush();};
  const close = async () => {await act(async () => {root.unmount();}); market.close(); dom.window.close();
    for (const [name, descriptor] of saved) {if (descriptor) Object.defineProperty(globalThis, name, descriptor); else Reflect.deleteProperty(globalThis, name);}};
  return {dom, api, storage, store, app, reload, text, button, click, pick, back, escape, flush, close, permission};
}
export type Harness = Awaited<ReturnType<typeof harness>>;
export {MINT, TESLA_MINT};
