/**
 * A contract-faithful fake of the API's own-money routes for lifecycle tests.
 * Preview returns real Solana wire bytes; execute verifies the signed bytes
 * with the API's own verifier (apps/api/src/live-stock-orders.ts, read-only).
 */
import {readFileSync} from 'node:fs';
import {bytesToBase64, parseTransaction} from '../../src/product/money/solana-wire.js';
import {AccountWalletClient} from '../../src/product/money/wallet-client.js';
import {LiveOrderClient} from '../../src/product/money/live-order-client.js';
import {MoneyWallet} from '../../src/product/money/wallet-controller.js';
import {LiveOrderSession} from '../../src/product/money/order-session.js';
import {PendingOrderStore, type MoneyStorage} from '../../src/product/money/stores.js';
import type {EmbeddedSolanaSnapshot} from '../../src/product/money/wallet-sdk-loader.js';
import {parseTradingCapabilities} from '../../src/product/money/live-trading.js';
import {ACCOUNT_ID, SUBJECT, contextJson, holdingsJson, message, orderJson, signer, signSlot, unsigned, type Signer} from './money-fixtures.js';

type Verify = (order: {wallet: string; unsignedTransaction: string}, signed: string) => string;
let verifier: Verify | null = null;
export async function apiVerifier(): Promise<Verify> {
  if (!verifier) {
    const source = new URL('../../../api/src/live-stock-orders.ts', import.meta.url).href;
    verifier = (await import(source) as {verifyReviewedSignature: Verify}).verifyReviewedSignature;
  }
  return verifier;
}
export function capabilitiesFixture() {
  return parseTradingCapabilities(JSON.parse(readFileSync(new URL('../fixtures/trading-capabilities-v2-2026-09-27-market-state.json', import.meta.url), 'utf8')));
}
export const liveCapabilitiesJson = () => JSON.parse(readFileSync(new URL('../fixtures/trading-capabilities-v2-2026-09-27-market-state.json', import.meta.url), 'utf8')) as Record<string, unknown>;

export class MemoryStorage implements MoneyStorage {
  readonly data = new Map<string, string>();
  blocked = false;
  getItem(key: string) {return this.data.get(key) ?? null;}
  setItem(key: string, value: string) {if (this.blocked) throw new Error('QuotaExceededError'); this.data.set(key, value);}
  removeItem(key: string) {this.data.delete(key);}
}

export interface ServerOrder {json: Record<string, unknown>; unsigned: string; signature: string | null}
export interface Call {method: string; path: string; body: Record<string, unknown> | null; headers: Headers}
export type Reply = (call: Call) => Response | Promise<Response | undefined> | undefined;

export async function moneyHarness(options: {route?: 'aggregator' | 'rfq'; usdc?: string; storage?: MemoryStorage; reply?: Reply} = {}) {
  const user = await signer(), maker = await signer();
  const verify = await apiVerifier();
  const calls: Call[] = [];
  const orders = new Map<string, ServerOrder>();
  const server = {usdc: options.usdc ?? '25000000', slot: 400, nextId: 1, route: options.route ?? 'aggregator' as 'aggregator' | 'rfq',
    settle: [] as ('pending' | 'confirmed' | 'failed' | 'expired')[], expiresInMs: 30_000, reply: options.reply ?? null as Reply | null};
  const id = (n: number) => `44444444-4444-4444-8444-${String(n).padStart(12, '0')}`;
  const latest = () => [...orders.values()].at(-1) ?? null;
  const publicOrder = (order: ServerOrder) => ({...order.json, ...(order.json['status'] === 'reviewed' ? {transaction: order.unsigned} : {})});
  const fetch = (async (url: string | URL | Request, init: RequestInit = {}) => {
    const parsed = new URL(String(url), 'https://trimmy.example');
    const call: Call = {method: init.method ?? 'GET', path: parsed.pathname.replace(/^\/api/, '') + parsed.search,
      body: init.body ? JSON.parse(String(init.body)) as Record<string, unknown> : null, headers: new Headers(init.headers as Record<string, string>)};
    calls.push(call);
    const override = await server.reply?.(call);
    if (override !== undefined) return override;
    const path = parsed.pathname.replace(/^\/api/, '');
    if (path === '/v1/account/context') return Response.json(contextJson(user.address));
    if (path === '/v1/account/holdings') return Response.json(holdingsJson(user.address, {usdc: server.usdc, slot: server.slot}));
    if (path === '/v1/trading/capabilities') return Response.json(liveCapabilitiesJson());
    if (path === '/v1/trading/preview') {
      const body = call.body!;
      const n = server.nextId++;
      const rfq = server.route === 'rfq';
      const bytes = rfq ? unsigned(message([maker.address, user.address], {version: 0}), 2) : unsigned(message([user.address], {version: 0}), 1);
      const json = orderJson({id: id(n), wallet: user.address, route: server.route, side: body['side'] as 'buy' | 'sell',
        mint: body['variantMint'] as string, amountRaw: body['amountRaw'] as string, expiresAt: new Date(Date.now() + server.expiresInMs).toISOString(),
        ...(rfq ? {reviewFlags: ['rfq_market_maker_fill', 'rfq_maker_delivers_at_fill'], terms: {settlement: 'maker_delivers_at_fill'}} : {})});
      const order = {json: json as unknown as Record<string, unknown>, unsigned: bytesToBase64(bytes), signature: null};
      orders.set(id(n), order);
      return Response.json({order: publicOrder(order)});
    }
    if (path === '/v1/trading/execute') {
      const body = call.body!, order = orders.get(body['id'] as string);
      if (!order || order.json['reviewDigest'] !== body['reviewDigest']) return Response.json({code: 'INVALID_REVIEW'}, {status: 409});
      let signature: string;
      try {signature = verify({wallet: user.address, unsignedTransaction: order.unsigned}, body['signedTransaction'] as string);}
      catch {return Response.json({code: 'INVALID_SIGNATURE'}, {status: 409});}
      order.signature = signature;
      order.json = {...order.json, status: server.settle.shift() ?? 'pending', signature};
      return Response.json({order: publicOrder(order)});
    }
    const match = /^\/v1\/trading\/order(?:\/([0-9a-f-]{36}))?$/.exec(path);
    if (match) {
      const order = match[1] ? orders.get(match[1]) : latest();
      if (!order) return Response.json({order: null});
      if (order.json['status'] === 'pending' && server.settle.length) {
        const next = server.settle.shift()!;
        order.json = {...order.json, status: next, ...(next === 'confirmed' ? {confirmedSlot: 900} : {})};
      } else if (order.json['status'] === 'reviewed' && Date.parse(order.json['expiresAt'] as string) <= Date.now()) {
        return Response.json({order: {...publicOrder(order), status: 'expired', transaction: undefined}});
      }
      return Response.json({order: publicOrder(order)});
    }
    if (path === '/v1/trading/history') return Response.json({schemaVersion: 1, network: 'solana:mainnet-beta', orders: [], nextCursor: null});
    throw new Error(`Unexpected money request ${call.method} ${call.path}`);
  }) as typeof globalThis.fetch;

  const identity = new AbortController();
  const privy = {subject: SUBJECT as string | null, wallets: [user.address], signs: 0,
    sign: null as null | ((bytes: Uint8Array) => Promise<Uint8Array>)};
  const embedded = (): EmbeddedSolanaSnapshot => ({ready: true, subject: privy.subject, wallets: privy.wallets.map(address => ({address})),
    signable: [...privy.wallets], refreshUser: async () => ({subject: privy.subject, wallets: privy.wallets.map(address => ({address}))}),
    createWallet: async () => user.address,
    signTransaction: async (address, bytes) => {
      privy.signs++;
      if (privy.sign) return privy.sign(bytes);
      return signSlot(bytes, parseTransaction(bytes).signers.indexOf(address), user);
    }});
  const bearer = async () => identity.signal.aborted ? null : 'aaa.bbb.ccc';
  const access = {subject: SUBJECT, accountId: ACCOUNT_ID, signal: identity.signal, freshAccessToken: bearer};
  const wallet = new MoneyWallet({access, embedded, client: new AccountWalletClient({baseUrl: '/api', accountId: ACCOUNT_ID, bearer, fetch})});
  const client = new LiveOrderClient({baseUrl: '/api', bearer, fetch, signal: identity.signal});
  const storage = options.storage ?? new MemoryStorage();
  const pending = new PendingOrderStore(storage, '/api', ACCOUNT_ID);
  const session = () => new LiveOrderSession({client, wallet, pending, pollMs: 5});
  return {user, maker: maker as Signer, server, orders, calls, fetch, identity, privy, embedded, wallet, client, storage, pending, session,
    capabilities: capabilitiesFixture()};
}

/** Waits until a condition holds, polling briefly; fails loudly instead of hanging. */
export async function until(check: () => boolean, label = 'condition', ms = 2000): Promise<void> {
  const deadline = Date.now() + ms;
  while (!check()) {
    if (Date.now() > deadline) throw new Error(`Timed out waiting for ${label}`);
    await new Promise(resolve => setTimeout(resolve, 2));
  }
}
