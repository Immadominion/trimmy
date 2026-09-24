import type {FastifyInstance} from 'fastify';
import {isAddress} from '@solana/kit';
import {BoundedSolanaRpc} from './solana-rpc-client.js';
import {BoundedProviderRead} from './bounded-provider-read.js';

const tokenPrograms = new Set(['TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA', 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb']);
export class HoldersError extends Error {
  constructor(readonly code: 'unavailable' | 'invalid' | 'rate_limited' = 'unavailable') {super('Holder data could not be loaded.');}
}
export interface PublicHolder {owner: string; primaryDomain: string | null; amount: string; tokenAccounts: number}
export interface PublicHoldersPage {
  schemaVersion: 1; mint: string; network: 'solana-mainnet'; scope: 'largest-20-token-accounts';
  complete: false; observedAt: string; slot: string; sampledAccounts: number; holders: PublicHolder[];
}
const object = (v: unknown): Record<string, unknown> => {
  if (!v || typeof v !== 'object' || Array.isArray(v)) throw new HoldersError('invalid');
  return v as Record<string, unknown>;
};
const address = (v: unknown): string => {
  if (typeof v !== 'string' || !isAddress(v)) throw new HoldersError('invalid');
  return v;
};
function amount(raw: bigint, decimals: number): string {
  const text = raw.toString().padStart(decimals + 1, '0');
  return decimals === 0 ? text : `${text.slice(0, -decimals)}.${text.slice(-decimals)}`.replace(/\.?0+$/, '');
}

/** Display-only snapshots. Owners may be pools or custodians, not people. */
export class PublicTokenHolders {
  readonly rpc: BoundedSolanaRpc<'getTokenLargestAccounts' | 'getMultipleAccounts', HoldersError>;
  readonly reads = new BoundedProviderRead<PublicHoldersPage>({now: Date.now, cacheTtlMs: 60_000,
    rateLimitWindowMs: 60_000, perKeyLimit: 3, globalLimit: 60, maxTrackedKeys: 256,
    maxCacheEntries: 128, maxConcurrentReads: 4}, {
    configurationInvalid: () => new HoldersError(), rateLimited: () => new HoldersError('rate_limited'),
  });
  constructor(rpcUrl: string, readonly fetcher: typeof fetch = fetch) {
    this.rpc = new BoundedSolanaRpc({rpcUrl, fetch: fetcher, timeoutMs: 5000,
      methods: ['getTokenLargestAccounts', 'getMultipleAccounts'], errors: {
        configuration: () => new HoldersError(), timeout: () => new HoldersError(),
        unavailable: () => new HoldersError(), responseInvalid: () => new HoldersError('invalid'),
        methodNotAllowed: () => new HoldersError('invalid'),
      }});
  }
  async holders(mint: string): Promise<PublicHoldersPage> {
    address(mint);
    return this.reads.read(mint, mint, async () => {
      const largest = await this.rpc.call('getTokenLargestAccounts', [mint, {commitment: 'confirmed'}]);
      const values = object(largest.result)['value'];
      if (!Array.isArray(values) || values.length > 20 || largest.contextSlot === null) throw new HoldersError('invalid');
      const keys = values.map(v => address(object(v)['address']));
      if (new Set(keys).size !== keys.length) throw new HoldersError('invalid');
      const owners = new Map<string, {raw: bigint; accounts: number}>();
      let decimals: number | undefined;
      let slot = largest.contextSlot;
      if (keys.length) {
        const accounts = await this.rpc.call('getMultipleAccounts', [keys, {encoding: 'jsonParsed', commitment: 'confirmed', minContextSlot: Number(slot)}]);
        const rows = object(accounts.result)['value'];
        if (!Array.isArray(rows) || rows.length !== keys.length || accounts.contextSlot === null || BigInt(accounts.contextSlot) < BigInt(slot)) throw new HoldersError('invalid');
        slot = accounts.contextSlot;
        for (const row of rows) {
          if (row === null) continue; // Account may have closed between reads.
          const account = object(row);
          if (!tokenPrograms.has(String(account['owner']))) throw new HoldersError('invalid');
          const parsed = object(object(account['data'])['parsed']);
          const info = object(parsed['info']);
          if (parsed['type'] !== 'account' || info['mint'] !== mint) throw new HoldersError('invalid');
          const owner = address(info['owner']);
          const balance = object(info['tokenAmount']);
          const scale = balance['decimals']; const raw = balance['amount'];
          if (typeof scale !== 'number' || !Number.isInteger(scale) || scale < 0 || scale > 18 ||
            (decimals !== undefined && decimals !== scale) || typeof raw !== 'string' || !/^(0|[1-9][0-9]{0,19})$/.test(raw) || BigInt(raw) > 18446744073709551615n) throw new HoldersError('invalid');
          decimals = scale;
          if (BigInt(raw) === 0n) continue;
          const previous = owners.get(owner);
          owners.set(owner, {raw: BigInt(raw) + (previous?.raw ?? 0n), accounts: (previous?.accounts ?? 0) + 1});
        }
      }
      const names = await this.primaryDomains([...owners.keys()]);
      const holders = [...owners].sort((a,b) => a[1].raw > b[1].raw ? -1 : a[1].raw < b[1].raw ? 1 : a[0].localeCompare(b[0]))
        .map(([owner, value]) => ({owner, primaryDomain: names[owner] ?? null, amount: amount(value.raw, decimals ?? 0), tokenAccounts: value.accounts}));
      return {schemaVersion: 1, mint, network: 'solana-mainnet', scope: 'largest-20-token-accounts', complete: false,
        observedAt: new Date().toISOString(), slot, sampledAccounts: keys.length, holders};
    });
  }
  private async primaryDomains(owners: string[]): Promise<Record<string, string>> {
    if (!owners.length) return {};
    // Optional, display-only identity enrichment. SNS failure never hides balances.
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 2500);
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
      const response = await this.fetcher(`https://sns-api.bonfida.com/v2/user/fav-domains/${owners.join(',')}`, {signal: controller.signal, redirect: 'error'});
      if (!response.ok || !response.body) return {};
      reader = response.body.getReader(); let size = 0; const chunks: Uint8Array[] = [];
      while (true) {const part = await reader.read(); if (part.done) break; size += part.value.length;
        if (size > 16_384) return {}; chunks.push(part.value);}
      const payload = object(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      const result: Record<string, string> = {};
      for (const owner of owners) {
        const name = payload[owner];
        // Keep suspicious control/bidi/URL characters out of UI identity labels.
        if (typeof name === 'string' && /^[\p{L}\p{N}_-]{1,64}(?:\.sol)?$/u.test(name)) result[owner] = name.endsWith('.sol') ? name : `${name}.sol`;
      }
      return result;
    } catch {return {};}
    finally {clearTimeout(timer); controller.abort(); if (reader) void reader.cancel().catch(() => undefined);}
  }
}
export function registerPublicHolders(app: FastifyInstance, reader?: PublicTokenHolders): void {
  app.get<{Querystring: {mint: string}}>('/v1/markets/stocks/holders', {
    exposeHeadRoute: false, schema: {querystring: {type: 'object', additionalProperties: false, required: ['mint'],
      properties: {mint: {type: 'string', pattern: '^[1-9A-HJ-NP-Za-km-z]{32,44}$'}}}},
  }, async (request, reply) => {
    if (!isAddress(request.query.mint)) return reply.code(400).send({error: {code: 'HOLDERS_INPUT_INVALID'}});
    try {if (!reader) throw new HoldersError(); return await reader.holders(request.query.mint);}
    catch (error) {return reply.code(error instanceof HoldersError && error.code === 'rate_limited' ? 429 : 503)
      .send({error: {code: 'HOLDERS_UNAVAILABLE', message: 'Holder data could not be loaded.'}});}
  });
}
