import {createHmac, createPublicKey, timingSafeEqual, verify} from 'node:crypto';
import {address, getAddressEncoder} from '@solana/kit';
import type {FastifyInstance, FastifyRequest} from 'fastify';
import type {AccountContextAdapters} from './account-context-route.js';

type Environment = 'staging' | 'production';
interface Configuration {environment: Environment; serverKey: string; clientKey: string}
export class OnrampError extends Error {
  constructor(readonly code: string, readonly status = 503) { super(code); }
}
const fail = (code: string, status = 503): never => { throw new OnrampError(code, status); };
const mint = {
  staging: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
  production: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
};
const object = (v: unknown): Record<string, any> =>
  v !== null && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, any> : {};

export function readCrossmintOnramp(env: Readonly<Record<string, string | undefined>>) {
  const environment = env['CROSSMINT_ENVIRONMENT'];
  if (!environment || environment === 'disabled') return undefined;
  const serverKey = env['CROSSMINT_SERVER_SIDE_API_KEY'];
  const clientKey = env['CROSSMINT_CLIENT_SIDE_API_KEY'];
  if ((environment !== 'staging' && environment !== 'production') ||
      !serverKey?.startsWith(`sk_${environment}_`) || !clientKey?.startsWith(`ck_${environment}_`)) {
    throw new Error('Crossmint requires matching environment, server and client keys.');
  }
  return new CrossmintOnramp({environment, serverKey, clientKey});
}

/** Creates unpaid orders only. Crossmint collects KYC and card details; this
 * service never receives payment credentials, charges a card or credits a ledger. */
export class CrossmintOnramp {
  readonly #fetch: typeof fetch;
  readonly #now: () => number;
  readonly #inFlight = new Set<string>();
  readonly #pace = new Map<string, {until: number; count: number}>();
  readonly #recent = new Map<string, {expires: number; input: string; value: unknown}>();
  constructor(private readonly config: Configuration, options: {fetch?: typeof fetch; now?: () => number} = {}) {
    this.#fetch = options.fetch ?? fetch;
    this.#now = options.now ?? Date.now;
  }
  get environment() { return this.config.environment; }
  get baseUrl() { return this.environment === 'staging' ? 'https://staging.crossmint.com' : 'https://www.crossmint.com'; }
  get capabilities() { return {enabled: true, environment: this.environment, chain: 'solana', currency: 'usd', asset: 'USDC'}; }
  private mac(text: string) {
    return createHmac('sha256', this.config.serverKey).update(`trimmy.onramp.v1:${text}`).digest();
  }
  private grant(value: Record<string, unknown>, ttl: number) {
    const body = Buffer.from(JSON.stringify({...value, env: this.environment, exp: this.#now() + ttl})).toString('base64url');
    return `${body}.${this.mac(body).toString('base64url')}`;
  }
  private readGrant(token: unknown, user: string, kind: string) {
    if (typeof token !== 'string' || token.length > 12000) return fail('ONRAMP_EXPIRED', 400);
    const [body, signature, extra] = token.split('.');
    if (!body || !signature || extra) return fail('ONRAMP_EXPIRED', 400);
    const supplied = Buffer.from(signature, 'base64url'), expected = this.mac(body);
    if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return fail('ONRAMP_EXPIRED', 400);
    let value: Record<string, any>;
    try { value = object(JSON.parse(Buffer.from(body, 'base64url').toString())); } catch { return fail('ONRAMP_EXPIRED', 400); }
    if (value['user'] !== user || value['kind'] !== kind || value['env'] !== this.environment ||
        typeof value['exp'] !== 'number' || value['exp'] <= this.#now()) return fail('ONRAMP_EXPIRED', 400);
    return value;
  }
  private async json(path: string, method: string, body?: unknown): Promise<Record<string, any>> {
    const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 20000);
    try {
      const response = await this.#fetch(`${this.baseUrl}/api/${path}`, {
        method, redirect: 'error', signal: controller.signal,
        headers: {'x-api-key': this.config.serverKey, 'content-type': 'application/json', accept: 'application/json'},
        ...(body === undefined ? {} : {body: JSON.stringify(body)}),
      });
      if (!response.ok) return fail(response.status === 403 ? 'ONRAMP_NOT_ENABLED' : response.status === 429 ? 'ONRAMP_BUSY' : 'ONRAMP_UNAVAILABLE');
      if (!response.body) return fail('ONRAMP_UNAVAILABLE');
      const chunks: Uint8Array[] = []; let size = 0;
      const reader = response.body.getReader();
      try { for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.length;
        if (size > 262144) return fail('ONRAMP_UNAVAILABLE'); chunks.push(part.value); }
      } finally { await reader.cancel().catch(() => {}); }
      return object(JSON.parse(Buffer.concat(chunks).toString()));
    } catch (error) { if (error instanceof OnrampError) throw error; return fail('ONRAMP_UNAVAILABLE'); }
    finally { clearTimeout(timer); controller.abort(); }
  }
  async bounded<T>(user: string, action: () => Promise<T>): Promise<T> {
    for (const [key, value] of this.#pace) if (value.until <= this.#now()) this.#pace.delete(key);
    if (this.#inFlight.has(user) || (this.#pace.get(user)?.count ?? 0) >= 50 ||
        this.#inFlight.size >= 20 || this.#pace.size >= 2048) return fail('ONRAMP_BUSY', 429);
    this.#inFlight.add(user);
    const pace = this.#pace.get(user) ?? {until: this.#now() + 60000, count: 0};
    pace.count++; this.#pace.set(user, pace);
    try { return await action(); } finally { this.#inFlight.delete(user); }
  }
  private linkPath(email: string, wallet: string) {
    return `2025-06-09/users/${encodeURIComponent(`email:${email}`)}/linked-wallets/${encodeURIComponent(wallet)}`;
  }
  async prepare(user: string, wallet: string, email: string) {
    const linked = await this.json(this.linkPath(email, wallet), 'PUT', {chain: 'solana'});
    if (linked['address'] !== wallet || linked['chain'] !== 'solana') return fail('ONRAMP_UNAVAILABLE');
    const ownership = object(linked['ownership']);
    if (ownership['verified'] === true) return {verified: true, wallet,
      walletToken: this.grant({kind: 'wallet', user, wallet, email}, 3600000)};
    const message: unknown = ownership['verificationChallenge'];
    if (typeof message !== 'string' || message.length > 4096 || !message.startsWith('crossmint.com wants you to sign in with your ') ||
        !message.split('\n').includes(wallet)) return fail('ONRAMP_UNAVAILABLE');
    return {verified: false, wallet, message,
      challengeToken: this.grant({kind: 'challenge', user, wallet, email, message}, 600000)};
  }
  async prove(user: string, wallet: string, token: string, proof: string) {
    const value = this.readGrant(token, user, 'challenge');
    if (value['wallet'] !== wallet) return fail('ONRAMP_WALLET_CHANGED', 409);
    const bytes = Buffer.from(proof, 'base64');
    if (bytes.length !== 64 || bytes.toString('base64') !== proof) return fail('ONRAMP_INVALID_PROOF', 400);
    const key = createPublicKey({key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'),
      Buffer.from(getAddressEncoder().encode(address(wallet)))]), format: 'der', type: 'spki'});
    if (!verify(null, Buffer.from(value['message']), key, bytes)) return fail('ONRAMP_INVALID_PROOF', 400);
    const linked = await this.json(this.linkPath(value['email'], wallet), 'PUT', {chain: 'solana', proof});
    if (linked['address'] !== wallet || object(linked['ownership'])['verified'] !== true) return fail('ONRAMP_INVALID_PROOF', 400);
    return {verified: true, wallet, walletToken: this.grant({kind: 'wallet', user, wallet, email: value['email']}, 3600000)};
  }
  async create(user: string, wallet: string, token: string, amount: string, requestId: string) {
    const grant = this.readGrant(token, user, 'wallet');
    if (grant['wallet'] !== wallet) return fail('ONRAMP_WALLET_CHANGED', 409);
    if (!/^(?:0|[1-9][0-9]{0,4})(?:\.[0-9]{1,2})?$/.test(amount) || Number(amount) < 5 || Number(amount) > 10000) {
      return fail('ONRAMP_AMOUNT_INVALID', 400);
    }
    for (const [key, value] of this.#recent) if (value.expires <= this.#now()) this.#recent.delete(key);
    const cacheKey = `${user}:${requestId}`, input = JSON.stringify([wallet, amount, grant['email']]);
    const existing = this.#recent.get(cacheKey);
    if (existing) { if (existing.input !== input) return fail('ONRAMP_REQUEST_CHANGED', 409); return existing.value; }
    if (this.#recent.size >= 2048) return fail('ONRAMP_BUSY', 429);
    const result = await this.json('2022-06-09/orders', 'POST', {
      recipient: {walletAddress: wallet}, payment: {method: 'card', currency: 'usd', receiptEmail: grant['email']},
      lineItems: [{tokenLocator: `solana:${mint[this.environment]}`, executionParameters: {mode: 'exact-in', amount}}],
    });
    const order = object(result['order']), id = order['orderId'], secret = result['clientSecret'];
    if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(id) || typeof secret !== 'string' || secret.length > 4096 || !secret) return fail('ONRAMP_UNAVAILABLE');
    const value = {orderId: id, clientSecret: secret, clientKey: this.config.clientKey, environment: this.environment,
      wallet, amount, orderToken: this.grant({kind: 'order', user, wallet, id}, 86400000)};
    // Replays within a process return the unpaid order. No automated retries of
    // order creation: a timeout never implies a payment failed or succeeded.
    this.#recent.set(cacheKey, {input, value, expires: this.#now() + 3600000});
    return value;
  }
  async status(user: string, token: string) {
    const value = this.readGrant(token, user, 'order');
    const result = await this.json(`2022-06-09/orders/${encodeURIComponent(value['id'])}`, 'GET');
    const order = result['order'] ? object(result['order']) : result;
    if (order['orderId'] !== value['id']) return fail('ONRAMP_UNAVAILABLE');
    const items = order['lineItems'];
    const item = Array.isArray(items) && items.length === 1 ? object(items[0]) : {};
    const recipient = object(object(item['delivery'])['recipient']);
    const walletAddress = recipient['walletAddress'], locator = recipient['locator'];
    const matchesRecipient = (walletAddress === value['wallet'] || locator === `solana:${value['wallet']}`) &&
      (walletAddress === undefined || walletAddress === value['wallet']) &&
      (locator === undefined || locator === `solana:${value['wallet']}`);
    const delivered = item['chain'] === 'solana' && object(item['delivery'])['status'] === 'completed' && matchesRecipient;
    const failed = Array.isArray(items) && items.some(item => object(item['delivery'])['status'] === 'failed');
    return {orderId: value['id'], status: delivered ? 'completed' : failed ? 'failed' : 'pending', environment: this.environment};
  }
}

export interface OnrampAdapters extends AccountContextAdapters {service: CrossmintOnramp}
export function registerOnrampRoutes(app: FastifyInstance, adapters?: OnrampAdapters) {
  app.get('/v1/funding/capabilities', {exposeHeadRoute: false}, async (_request, reply) => {
    reply.header('cache-control', 'no-store'); return adapters?.service.capabilities ?? {enabled: false};
  });
  const routes = {
    wallet: {email: {type: 'string', format: 'email', maxLength: 254}},
    verify: {challengeToken: {type: 'string', maxLength: 12000}, proof: {type: 'string', maxLength: 88}},
    orders: {walletToken: {type: 'string', maxLength: 12000}, amount: {type: 'string', maxLength: 8}, requestId: {type: 'string', format: 'uuid'}},
    status: {orderToken: {type: 'string', maxLength: 12000}},
  };
  for (const [route, properties] of Object.entries(routes)) {
    app.post(`/v1/funding/${route}`, {bodyLimit: 16000, schema: {body: {
      type: 'object', additionalProperties: false, required: Object.keys(properties), properties,
    }}}, async (request: FastifyRequest, reply) => {
      reply.header('cache-control', 'no-store');
      try {
        if (!adapters) return fail('ONRAMP_NOT_ENABLED');
        const account = await adapters.authenticate(request);
        if (!account || account.identity.provider !== 'privy') return fail('ACCOUNT_REQUIRED', 401);
        return await adapters.service.bounded(account.userId, async () => {
          const body = object(request.body);
          if (route === 'status') return adapters.service.status(account.userId, body['orderToken']);
          const identity = await adapters.linkedIdentities.resolve(account.identity);
          if (identity.subject !== account.identity.subject || identity.embeddedSolanaWallet.status !== 'candidate') return fail('WALLET_REQUIRED', 409);
          const wallet = identity.embeddedSolanaWallet.address;
          if (route === 'wallet') return adapters.service.prepare(account.userId, wallet, body['email'].trim().toLowerCase());
          if (route === 'verify') return adapters.service.prove(account.userId, wallet, body['challengeToken'], body['proof']);
          return adapters.service.create(account.userId, wallet, body['walletToken'], body['amount'], body['requestId']);
        });
      } catch (error) {
        const safe = error instanceof OnrampError ? error : new OnrampError('ONRAMP_UNAVAILABLE');
        return reply.code(safe.status).send({code: safe.code});
      }
    });
  }
}
