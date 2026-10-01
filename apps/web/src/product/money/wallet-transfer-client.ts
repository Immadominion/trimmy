/**
 * Sending money out: USDC, SOL or a stock token to another Solana wallet.
 * Contract: apps/api/src/wallet-transfers.ts; mobile send_money_flow.dart.
 * The server reviews and simulates the transfer; the wallet signs it here;
 * nothing is sent without that signature. Nothing in this file signs.
 */
import type {MoneyStorage} from './stores.js';
import {USDC_MINT} from './amounts.js';
import {moneyApiBase, requestJson, validBearer, type BearerSource} from './http.js';
import {copyText, type MoneyCopy} from './live-order-client.js';
import * as fmt from '../../i18n/format.js';

const ADDRESS = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
const RAW = /^(?:0|[1-9][0-9]{0,19})$/;
const SIGNATURE = /^[1-9A-HJ-NP-Za-km-z]{64,88}$/;

export class TransferError extends Error {
  constructor(readonly code: string) {super(transferMessage(code)); this.name = 'TransferError';}
  /** The message as copy, for screens that show it later. */
  get copy(): MoneyCopy {return transferCopy(this.code);}
}

/** Mobile's copy for every code the API can return, plus local signing outcomes. */
export function transferMessage(code: string): string {return copyText(transferCopy(code));}
/** The smallest SOL amounts the API names, formatted when shown. */
const minimumSol = {get amount() {return fmt.number('0.001');}};
export function transferCopy(code: string): MoneyCopy {
  switch (code) {
    case 'DESTINATION_INVALID': case 'TRANSFER_INPUT_INVALID': return {key: 'money.sendError.checkInput'};
    case 'DESTINATION_SELF': return {key: 'money.sendError.destinationSelf'};
    case 'DESTINATION_NOT_WALLET': return {key: 'money.sendError.notWallet'};
    case 'DESTINATION_FROZEN': return {key: 'money.sendError.destinationFrozen'};
    case 'ASSET_UNSUPPORTED': return {key: 'money.sendError.assetUnsupported'};
    case 'ASSET_NOT_TRANSFERABLE': return {key: 'money.sendError.notTransferable'};
    case 'ASSET_PAUSED': return {key: 'money.sendError.assetPaused'};
    case 'ASSET_FROZEN': return {key: 'money.sendError.assetFrozen'};
    case 'INSUFFICIENT_BALANCE': return {key: 'money.sendError.insufficient'};
    case 'ADD_SOL': return {key: 'money.sendError.addSol'};
    case 'LEAVES_TOO_LITTLE_SOL': return {key: 'money.sendError.leaveSol', params: minimumSol};
    case 'AMOUNT_TOO_SMALL': return {key: 'money.sendError.tooSmall', params: minimumSol};
    case 'SIMULATION_FAILED': case 'SIMULATION_MISMATCH': return {key: 'money.sendError.simulation'};
    case 'REVIEW_EXPIRED': case 'INVALID_REVIEW': case 'INVALID_SIGNATURE': case 'QUOTE_EXPIRED': return {key: 'money.sendError.reviewExpired'};
    case 'TRANSFER_NOT_SENT': case 'TRANSFER_PENDING': return {key: 'money.sendError.previousSend'};
    case 'INVALID_TRANSACTION': return {key: 'money.sendError.invalidTransaction'};
    case 'SIGNATURE_MISMATCH': return {key: 'money.sendError.signatureMismatch'};
    case 'TRANSFER_STORAGE': return {key: 'money.sendError.storage'};
    case 'TRANSFER_BUSY': return {key: 'money.sendError.busy'};
    case 'ACCOUNT_REQUIRED': case 'WALLET_REQUIRED': case 'ACCOUNT_CHANGED': case 'WALLET_CHANGED': return {key: 'money.error.signInAgain'};
    case 'SIGNING_CANCELLED': return {key: 'money.sendError.cancelled'};
    case 'SIGNING_TIMEOUT': return {key: 'money.sendError.signingTimeout'};
    case 'WALLET_BUSY': return {key: 'money.sendError.walletBusy'};
    case 'TRANSFER_UNAVAILABLE': return {key: 'money.sendError.paused'};
    default: return {key: 'money.sendError.connection'};
  }
}

export interface TransferReview {
  readonly id?: string;
  /** `USDC`, `SOL` or the token's mint, as the server takes it. */
  readonly assetId: string; readonly symbol: string; readonly decimals: number; readonly uiMultiplier: string;
  readonly from: string; readonly destination: string;
  readonly amountRaw: string;
  /** What arrives after any issuer transfer fee, from the simulation. */
  readonly receivedRaw: string;
  readonly createsAccount: boolean; readonly accountRentLamports: string; readonly networkFeeLamports: string;
  readonly expiresAt: string;
  readonly unsignedTransaction: string; readonly reviewToken: string;
}

const invalid = (): never => {throw new TransferError('TRANSFER_UNAVAILABLE');};
const record = (value: unknown): Record<string, unknown> | null =>
  value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;

export function parseTransferReview(value: unknown): TransferReview {
  const body = record(value), review = record(body?.['review']), asset = record(review?.['asset']);
  if (!body || !review || !asset) return invalid();
  const kind = asset['kind'], mint = asset['mint'], decimals = asset['decimals'];
  const raw = (v: unknown) => typeof v === 'string' && RAW.test(v);
  const address = (v: unknown) => typeof v === 'string' && ADDRESS.test(v);
  const wire = body['unsignedTransaction'], token = body['reviewToken'], expires = review['expiresAt'];
  if (!(kind === 'sol' && mint === null || kind === 'token' && address(mint)) ||
      typeof asset['symbol'] !== 'string' || asset['symbol'].length > 24 ||
      typeof decimals !== 'number' || !Number.isInteger(decimals) || decimals < 0 || decimals > 18 ||
      typeof asset['uiMultiplier'] !== 'string' || !/^[0-9]+(?:\.[0-9]+)?$/.test(asset['uiMultiplier']) ||
      !address(review['from']) || !address(review['destination']) || !raw(review['amountRaw']) || !raw(review['receivedRaw']) ||
      typeof review['createsAccount'] !== 'boolean' || !raw(review['accountRentLamports']) || !raw(review['networkFeeLamports']) ||
      typeof expires !== 'string' || !Number.isFinite(Date.parse(expires)) ||
      typeof wire !== 'string' || wire.length > 1644 || !/^[A-Za-z0-9+/]+={0,2}$/.test(wire) ||
      typeof token !== 'string' || token.length > 1200 || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) return invalid();
  return Object.freeze({...(typeof body?.['id']==='string' && /^[0-9a-f-]{36}$/.test(body['id']) ? {id:body['id']} : {}),assetId: kind === 'sol' ? 'SOL' : mint === USDC_MINT ? 'USDC' : mint as string,
    symbol: asset['symbol'] as string, decimals: decimals as number, uiMultiplier: asset['uiMultiplier'] as string,
    from: review['from'] as string, destination: review['destination'] as string,
    amountRaw: review['amountRaw'] as string, receivedRaw: review['receivedRaw'] as string,
    createsAccount: review['createsAccount'] as boolean, accountRentLamports: review['accountRentLamports'] as string,
    networkFeeLamports: review['networkFeeLamports'] as string, expiresAt: expires, unsignedTransaction: wire, reviewToken: token});
}

export interface WalletTransferClientOptions {
  readonly baseUrl: string; readonly bearer: BearerSource;
  readonly storage?: MoneyStorage | null; readonly accountId?: string;
  readonly fetch?: typeof fetch; readonly signal?: AbortSignal; readonly timeoutMs?: number;
}

export class WalletTransferClient {
  readonly #base: string; readonly #bearer: BearerSource; readonly #fetch: typeof fetch;
  readonly #storage: MoneyStorage | null; readonly #storageKey: string;
  readonly #signal: AbortSignal | undefined; readonly #timeout: number;
  constructor(options: WalletTransferClientOptions) {
    this.#base = moneyApiBase(options.baseUrl);
    this.#storage=options.storage??null;
    this.#storageKey=`trimmy.pending-send.v1.${encodeURIComponent(this.#base)}.${options.accountId??''}`;
    this.#bearer = options.bearer;
    this.#fetch = options.fetch ?? globalThis.fetch.bind(globalThis);
    this.#signal = options.signal;
    this.#timeout = options.timeoutMs ?? 45_000;
  }

  async #call(path: string, body?: unknown): Promise<Record<string, unknown>> {
    if (this.#signal?.aborted) throw new TransferError('ACCOUNT_REQUIRED');
    const token = await this.#bearer();
    if (!validBearer(token) || this.#signal?.aborted) throw new TransferError('ACCOUNT_REQUIRED');
    let response;
    try {
      response = await requestJson(this.#fetch, `${this.#base}/v1/wallet/transfers/${path}`, {method: body === undefined ? 'GET' : 'POST',
        headers: {authorization: `Bearer ${token}`}, ...(body === undefined ? {} : {body}), timeoutMs: this.#timeout, maxBytes: 16_384,
        signal: this.#signal});
    } catch {throw new TransferError('TRANSFER_CONNECTION');}
    const value = record(response.body);
    if (response.status !== 200) {
      const code = typeof value?.['code'] === 'string' && /^[A-Z_]{1,64}$/.test(value['code']) ? value['code'] : 'TRANSFER_UNAVAILABLE';
      throw new TransferError(code);
    }
    return value ?? invalid();
  }

  async preview(input: {readonly asset: string; readonly destination: string; readonly amountRaw: string}): Promise<TransferReview> {
    if (!(input.asset === 'SOL' || input.asset === 'USDC' || ADDRESS.test(input.asset)) || !ADDRESS.test(input.destination) ||
        !RAW.test(input.amountRaw) || input.amountRaw === '0') throw new TransferError('TRANSFER_INPUT_INVALID');
    return parseTransferReview(await this.#call('preview', {asset: input.asset, destination: input.destination, amountRaw: input.amountRaw}));
  }

  async execute(review: TransferReview, signedTransaction: string): Promise<string> {
    if(!review.id || !this.#storage)throw new TransferError('TRANSFER_STORAGE');
    try {this.#storage.setItem(this.#storageKey,review.id);if(this.#storage.getItem(this.#storageKey)!==review.id)throw Error();}
    catch {throw new TransferError('TRANSFER_STORAGE');}
    const value = await this.#call('execute', {reviewToken: review.reviewToken, signedTransaction});
    const signature = value['signature'];
    return typeof signature === 'string' && SIGNATURE.test(signature) ? signature : invalid();
  }

  async recovery():Promise<{review:TransferReview;status:'reviewed'|'pending'|'confirmed'|'failed'|'expired';signature:string|null}|null> {
    let id:string|null;
    try {id=this.#storage?.getItem(this.#storageKey)??null;}catch {throw new TransferError('TRANSFER_STORAGE');}
    if(id!==null && !/^[0-9a-f-]{36}$/.test(id))throw new TransferError('TRANSFER_STORAGE');
    const row=record((await this.#call(`recovery${id?`?id=${id}`:''}`))['transfer']);
    if(!row) {if(id)throw new TransferError('TRANSFER_UNAVAILABLE');return null;}
    const status=row['status'], signature=row['signature'];
    if(!['reviewed','pending','confirmed','failed','expired'].includes(String(status)) ||
      signature!==null && (typeof signature!=='string' || !SIGNATURE.test(signature)) ||
      ['pending','confirmed','failed'].includes(String(status)) && signature===null) return invalid();
    const review=parseTransferReview(row);
    if(!review.id || id && review.id!==id)return invalid();
    return {review,status:status as 'reviewed'|'pending'|'confirmed'|'failed'|'expired',signature:signature as string|null};
  }
  acknowledge():void {
    try {this.#storage?.removeItem(this.#storageKey);}catch {throw new TransferError('TRANSFER_STORAGE');}
  }

  async status(signature: string): Promise<'pending' | 'confirmed' | 'failed' | 'expired'> {
    if (!SIGNATURE.test(signature)) throw new TransferError('TRANSFER_INPUT_INVALID');
    const status = (await this.#call(`status?signature=${signature}`))['status'];
    return status === 'pending' || status === 'confirmed' || status === 'failed' || status === 'expired' ? status : invalid();
  }
}
