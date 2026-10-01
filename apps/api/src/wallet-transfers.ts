import { createHash, createHmac, createPublicKey, randomBytes, randomUUID, verify } from 'node:crypto';
import {
  address, appendTransactionMessageInstructions, compileTransaction, createNoopSigner, createTransactionMessage,
  getAddressEncoder, getBase58Decoder, getBase64EncodedWireTransaction, getTransactionDecoder, getTransactionEncoder, pipe,
  setTransactionMessageFeePayerSigner, setTransactionMessageLifetimeUsingBlockhash,
} from '@solana/kit';
import type { Address, Blockhash } from '@solana/kit';
import { getSetComputeUnitLimitInstruction, getSetComputeUnitPriceInstruction } from '@solana-program/compute-budget';
import { getTransferSolInstruction } from '@solana-program/system';
import * as token from '@solana-program/token';
import * as token2022 from '@solana-program/token-2022';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { BoundedSolanaRpc } from './solana-rpc-client.js';
import type { ExistingPracticeAccountAuthentication } from './practice-session-routes.js';
import type { PracticeIdentity } from './practice-identity.js';
import type { PrivyLinkedIdentityResolution } from './privy-linked-identities.js';
import type {WalletTransferStore, StoredTransfer} from './wallet-transfer-store.js';
import { findStockTradingAssetByMint } from './stock-trading-catalog.js';

/**
 * Sending money out of a Trimmy wallet: USDC, SOL or a stock token the wallet
 * holds, to a Solana wallet address. The server builds the transfer itself,
 * checks where it goes, simulates it and returns it unsigned. The user signs on
 * their own device, and the server sends only the exact transaction it reviewed.
 *
 * A destination that is a token account, a mint or a program is refused: sending
 * there is the usual way money is lost. Nothing here signs, and nothing moves
 * without the user's signature.
 */
export const USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const SYSTEM_PROGRAM = '11111111111111111111111111111111';
const TOKEN_PROGRAMS = new Set<string>([token.TOKEN_PROGRAM_ADDRESS, token2022.TOKEN_2022_PROGRAM_ADDRESS]);
const ADDRESS = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
const U64_MAX = 18_446_744_073_709_551_615n;
/** A wallet account with no data must keep this much SOL, or none at all. */
export const RENT_EXEMPT_WALLET_LAMPORTS = 890_880n;
const BASE_FEE_LAMPORTS = 5_000n;
const PRIORITY_MICRO_LAMPORTS = 50_000n;
const REVIEW_TTL_MS = 90_000;

export type TransferAsset = 'SOL' | 'USDC' | string;

export class WalletTransferError extends Error {
  constructor(readonly code: string) { super(code); }
}
const fail = (code: string): never => { throw new WalletTransferError(code); };

export interface TransferReview {
  readonly asset: {readonly kind: 'sol' | 'token'; readonly mint: string | null; readonly symbol: string; readonly decimals: number;
    /** Displayed units per raw whole token (Token-2022 scaled UI amount); "1" without one. */
    readonly uiMultiplier: string};
  readonly from: string;
  readonly destination: string;
  readonly amountRaw: string;
  /** What the destination receives after any token transfer fee, from the simulation. */
  readonly receivedRaw: string;
  /** A new token account for the destination, paid by the sender and kept by the destination. */
  readonly createsAccount: boolean;
  readonly accountRentLamports: string;
  readonly networkFeeLamports: string;
  readonly expiresAt: string;
}

export interface TransferPreview {
  readonly id: string;
  readonly review: TransferReview;
  readonly unsignedTransaction: string;
  /** Proves this server reviewed the transaction for this account; sent back to execute. */
  readonly reviewToken: string;
}

interface Parsed { readonly owner: string; readonly lamports: bigint; readonly executable: boolean; readonly info: Record<string, unknown> | null; readonly program: string | null }

const record = (value: unknown): Record<string, unknown> | null =>
  value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;

function parsedAccount(value: unknown): Parsed | null {
  const row = record(value);
  if (!row) return null;
  const data = record(row['data']);
  const parsed = record(data?.['parsed']);
  const lamports = row['lamports'];
  if (typeof row['owner'] !== 'string' || typeof lamports !== 'number' || !Number.isSafeInteger(lamports) || lamports < 0) fail('TRANSFER_UNAVAILABLE');
  return {owner: row['owner'] as string, lamports: BigInt(lamports as number), executable: row['executable'] === true,
    info: record(parsed?.['info']), program: typeof data?.['program'] === 'string' ? data['program'] as string : null};
}

function extension(info: Record<string, unknown> | null, name: string): Record<string, unknown> | null | undefined {
  const list = info?.['extensions'];
  if (!Array.isArray(list)) return undefined;
  const found = list.map(record).find(item => item?.['extension'] === name);
  return found === undefined ? undefined : record(found?.['state']);
}

function tokenAmount(info: Record<string, unknown> | null): bigint {
  const amount = record(info?.['tokenAmount'])?.['amount'];
  if (typeof amount !== 'string' || !/^(0|[1-9][0-9]{0,19})$/.test(amount)) return fail('TRANSFER_UNAVAILABLE');
  return BigInt(amount);
}

class TransferRpcError extends Error {}
const RPC_ERRORS = Object.freeze({
  configuration: () => new TransferRpcError('configuration'), timeout: () => new TransferRpcError('timeout'),
  unavailable: () => new TransferRpcError('unavailable'), responseInvalid: () => new TransferRpcError('response'),
  methodNotAllowed: () => new TransferRpcError('method'),
});
type Method = 'getMultipleAccounts' | 'getLatestBlockhash' | 'simulateTransaction' | 'sendTransaction' | 'getBlockHeight' | 'getSignatureStatuses' | 'isBlockhashValid';

export class WalletTransfers {
  readonly #rpc: BoundedSolanaRpc<Method, TransferRpcError>;
  readonly #now: () => number;
  readonly #key: Buffer;
  readonly #inFlight = new Set<string>();
  readonly #store: WalletTransferStore;

  constructor(options: {store: WalletTransferStore; rpcUrl: string; fetch?: typeof globalThis.fetch; now?: () => number; key?: Buffer}) {
    this.#rpc = new BoundedSolanaRpc({rpcUrl: options.rpcUrl, errors: RPC_ERRORS, maxBodyBytes: 2_097_152,
      methods: ['getMultipleAccounts', 'getLatestBlockhash', 'simulateTransaction', 'sendTransaction', 'getBlockHeight', 'getSignatureStatuses', 'isBlockhashValid'],
      ...(options.fetch ? {fetch: options.fetch} : {})});
    this.#now = options.now ?? Date.now;
    this.#store = options.store;
    // The complete review token is persisted; restarts do not invalidate it.
    this.#key = options.key ?? randomBytes(32);
  }

  async #call(method: Method, params: readonly unknown[]): Promise<unknown> {
    try {
      return (await this.#rpc.call(method, params)).result;
    } catch (error) {
      if (error instanceof WalletTransferError) throw error;
      return fail('TRANSFER_UNAVAILABLE');
    }
  }

  async #accounts(addresses: readonly string[]): Promise<(Parsed | null)[]> {
    const result = record(await this.#call('getMultipleAccounts', [addresses, {encoding: 'jsonParsed', commitment: 'confirmed'}]));
    const value = result?.['value'];
    if (!Array.isArray(value) || value.length !== addresses.length) return fail('TRANSFER_UNAVAILABLE');
    return value.map(parsedAccount);
  }

  async preview(input: {userId: string; wallet: string; asset: TransferAsset; destination: string; amountRaw: string}): Promise<TransferPreview> {
    const {userId, wallet} = input;
    const pending=await this.recovery(userId,wallet);
    if(pending?.status==='pending')fail('TRANSFER_PENDING');
    if (!ADDRESS.test(input.destination) || !/^[1-9][0-9]{0,19}$/.test(input.amountRaw) || BigInt(input.amountRaw) > U64_MAX) fail('TRANSFER_INPUT_INVALID');
    let destination: Address;
    try { destination = address(input.destination); } catch { return fail('DESTINATION_INVALID'); }
    if (destination === wallet) fail('DESTINATION_SELF');
    const amount = BigInt(input.amountRaw);
    const mint = input.asset === 'SOL' ? null : input.asset === 'USDC' ? USDC_MINT : input.asset;
    // Only USDC and Trimmy's stock tokens, including ones no longer traded: a
    // holder can always take a token out.
    const stock = mint === null || mint === USDC_MINT ? undefined : findStockTradingAssetByMint(mint);
    if (mint !== null && mint !== USDC_MINT && !stock) fail('ASSET_UNSUPPORTED');
    if (this.#inFlight.has(userId)) fail('TRANSFER_BUSY');
    this.#inFlight.add(userId);
    try {
      return mint === null
        ? await this.#previewSol(userId, address(wallet), destination, amount)
        : await this.#previewToken(userId, address(wallet), destination, amount, address(mint), mint === USDC_MINT ? 'USDC' : stock!.symbol);
    } finally {
      this.#inFlight.delete(userId);
    }
  }

  /** The destination must be a wallet: a new address, or one the System Program owns. */
  static #checkDestination(account: Parsed | null): void {
    if (account === null) return;
    if (account.executable || account.owner !== SYSTEM_PROGRAM) fail('DESTINATION_NOT_WALLET');
  }

  async #previewSol(userId: string, wallet: Address, destination: Address, amount: bigint): Promise<TransferPreview> {
    const [source, target] = await this.#accounts([wallet, destination]);
    WalletTransfers.#checkDestination(target!);
    const units = 2_000n;
    const fee = BASE_FEE_LAMPORTS + (units * PRIORITY_MICRO_LAMPORTS + 999_999n) / 1_000_000n;
    const balance = source?.lamports ?? 0n;
    if (amount + fee > balance) fail('INSUFFICIENT_BALANCE');
    const left = balance - amount - fee;
    // A wallet keeps enough SOL to exist, or sends all of it.
    if (left > 0n && left < RENT_EXEMPT_WALLET_LAMPORTS) fail('LEAVES_TOO_LITTLE_SOL');
    if (target === null && amount < RENT_EXEMPT_WALLET_LAMPORTS) fail('AMOUNT_TOO_SMALL');
    const signer = createNoopSigner(wallet);
    const instructions = [getSetComputeUnitLimitInstruction({units: Number(units)}),
      getSetComputeUnitPriceInstruction({microLamports: PRIORITY_MICRO_LAMPORTS}),
      getTransferSolInstruction({source: signer, destination, amount})];
    const built = await this.#build(signer, instructions);
    const after = await this.#simulate(built.wire, [wallet, destination]);
    const received = (after[1]?.lamports ?? 0n) - (target?.lamports ?? 0n);
    if (received !== amount) fail('SIMULATION_MISMATCH');
    return this.#finish(userId, wallet, built, {kind: 'sol', mint: null, symbol: 'SOL', decimals: 9, uiMultiplier: '1'},
      destination, amount, received, false, 0n, fee);
  }

  async #previewToken(userId: string, wallet: Address, destination: Address, amount: bigint, mint: Address, symbol: string): Promise<TransferPreview> {
    const [mintAccount] = await this.#accounts([mint]);
    if (!mintAccount || !TOKEN_PROGRAMS.has(mintAccount.owner) || mintAccount.info?.['isInitialized'] !== true) fail('ASSET_UNSUPPORTED');
    const tokenProgram = address(mintAccount!.owner);
    const decimals = mintAccount!.info?.['decimals'];
    if (typeof decimals !== 'number' || !Number.isInteger(decimals) || decimals < 0 || decimals > 18) return fail('ASSET_UNSUPPORTED');
    // A transfer hook needs accounts this simple transfer does not carry, and a
    // non-transferable token cannot move at all.
    const hook = extension(mintAccount!.info, 'transferHook');
    if (hook !== undefined && hook?.['programId'] !== null && hook?.['programId'] !== undefined) fail('ASSET_NOT_TRANSFERABLE');
    if (extension(mintAccount!.info, 'nonTransferable') !== undefined) fail('ASSET_NOT_TRANSFERABLE');
    if (extension(mintAccount!.info, 'pausableConfig')?.['paused'] === true) fail('ASSET_PAUSED');
    const scaled = extension(mintAccount!.info, 'scaledUiAmountConfig');
    const figure = (value: unknown) => (typeof value === 'string' || typeof value === 'number') && Number(value) > 0 ? String(value) : null;
    const effective = Number(scaled?.['newMultiplierEffectiveTimestamp'] ?? Infinity) * 1000 <= this.#now();
    const multiplier = (effective ? figure(scaled?.['newMultiplier']) : null) ?? figure(scaled?.['multiplier']) ?? '1';
    const program = tokenProgram === token2022.TOKEN_2022_PROGRAM_ADDRESS ? token2022 : token;
    const [sourceAta] = await program.findAssociatedTokenPda({owner: wallet, mint, tokenProgram});
    const [targetAta] = await program.findAssociatedTokenPda({owner: destination, mint, tokenProgram});
    const [owner, source, target, targetToken] = await this.#accounts([wallet, sourceAta, destination, targetAta]);
    WalletTransfers.#checkDestination(target!);
    if (!source || source.owner !== tokenProgram || source.info?.['mint'] !== mint || source.info?.['owner'] !== wallet) fail('INSUFFICIENT_BALANCE');
    if (source!.info?.['state'] === 'frozen') fail('ASSET_FROZEN');
    if (tokenAmount(source!.info) < amount) fail('INSUFFICIENT_BALANCE');
    const createsAccount = targetToken === null;
    if (targetToken && (targetToken.owner !== tokenProgram || targetToken.info?.['mint'] !== mint || targetToken.info?.['owner'] !== destination)) {
      fail('DESTINATION_NOT_WALLET');
    }
    if (targetToken?.info?.['state'] === 'frozen') fail('DESTINATION_FROZEN');
    const units = createsAccount ? 60_000n : 20_000n;
    const fee = BASE_FEE_LAMPORTS + (units * PRIORITY_MICRO_LAMPORTS + 999_999n) / 1_000_000n;
    const signer = createNoopSigner(wallet);
    const instructions = [getSetComputeUnitLimitInstruction({units: Number(units)}),
      getSetComputeUnitPriceInstruction({microLamports: PRIORITY_MICRO_LAMPORTS}),
      ...(createsAccount ? [program.getCreateAssociatedTokenIdempotentInstruction({payer: signer, ata: targetAta, owner: destination, mint, tokenProgram})] : []),
      program.getTransferCheckedInstruction({source: sourceAta, mint, destination: targetAta, authority: signer, amount, decimals: decimals as number},
        {programAddress: tokenProgram})];
    const built = await this.#build(signer, instructions);
    const after = await this.#simulate(built.wire, [wallet, sourceAta, targetAta]);
    const [, sourceAfter, targetAfter] = after;
    if (!sourceAfter || tokenAmount(sourceAfter.info) !== tokenAmount(source!.info) - amount) fail('SIMULATION_MISMATCH');
    const received = (targetAfter ? tokenAmount(targetAfter.info) : 0n) - (targetToken ? tokenAmount(targetToken.info) : 0n);
    // A token's own transfer fee can be withheld; nothing else may be.
    if (received <= 0n || received > amount) fail('SIMULATION_MISMATCH');
    const rent = createsAccount ? targetAfter?.lamports ?? 0n : 0n;
    // The sender pays the fee and the new account's rent, and keeps enough SOL to exist.
    const balance = owner?.lamports ?? 0n;
    if (balance < fee + rent) fail('ADD_SOL');
    const left = balance - fee - rent;
    if (left > 0n && left < RENT_EXEMPT_WALLET_LAMPORTS) fail('ADD_SOL');
    return this.#finish(userId, wallet, built, {kind: 'token', mint, symbol, decimals: decimals as number, uiMultiplier: String(multiplier)},
      destination, amount, received, createsAccount, rent, fee);
  }

  async #build(signer: ReturnType<typeof createNoopSigner>, instructions: Parameters<typeof appendTransactionMessageInstructions>[0]) {
    const response=record(await this.#call('getLatestBlockhash', [{commitment: 'confirmed'}]));
    const latest=record(response?.['value']);
    const slot=record(response?.['context'])?.['slot'];
    const blockhash = latest?.['blockhash'], lastValidBlockHeight = latest?.['lastValidBlockHeight'];
    if (typeof blockhash !== 'string' || !ADDRESS.test(blockhash) || typeof lastValidBlockHeight !== 'number' || !Number.isSafeInteger(lastValidBlockHeight) || lastValidBlockHeight<1 || typeof slot!=='number' || !Number.isSafeInteger(slot) || slot<1) {
      return fail('TRANSFER_UNAVAILABLE');
    }
    const message = pipe(createTransactionMessage({version: 0}),
      m => setTransactionMessageFeePayerSigner(signer, m),
      m => setTransactionMessageLifetimeUsingBlockhash({blockhash: blockhash as Blockhash, lastValidBlockHeight: BigInt(lastValidBlockHeight)}, m),
      m => appendTransactionMessageInstructions(instructions, m));
    const transaction = compileTransaction(message);
    return {wire: getBase64EncodedWireTransaction(transaction), messageBytes: Buffer.from(transaction.messageBytes), lastValidBlockHeight, blockhash, observationSlot: slot as number};
  }

  async #simulate(wire: string, addresses: readonly string[]): Promise<(Parsed | null)[]> {
    const result = record(record(await this.#call('simulateTransaction', [wire, {encoding: 'base64', sigVerify: false,
      replaceRecentBlockhash: false, commitment: 'confirmed', accounts: {encoding: 'jsonParsed', addresses}}]))?.['value']);
    if (!result) return fail('TRANSFER_UNAVAILABLE');
    if (result['err'] !== null) {
      const text = JSON.stringify(result['err']);
      return fail(/InsufficientFunds/.test(text) ? 'ADD_SOL' : 'SIMULATION_FAILED');
    }
    const accounts = result['accounts'];
    if (!Array.isArray(accounts) || accounts.length !== addresses.length) return fail('TRANSFER_UNAVAILABLE');
    return accounts.map(parsedAccount);
  }

  async #finish(userId: string, wallet: Address, built: {wire: string; messageBytes: Buffer; lastValidBlockHeight: number; blockhash:string; observationSlot:number},
    asset: TransferReview['asset'], destination: Address, amount: bigint, received: bigint, createsAccount: boolean,
    rent: bigint, fee: bigint): Promise<TransferPreview> {
    const expiresAt = new Date(this.#now() + REVIEW_TTL_MS).toISOString();
    const review: TransferReview = Object.freeze({asset: Object.freeze(asset), from: wallet, destination, amountRaw: String(amount),
      receivedRaw: String(received), createsAccount, accountRentLamports: String(rent), networkFeeLamports: String(fee), expiresAt});
    const id=randomUUID();
    const payload = Buffer.from(JSON.stringify({v: 2, i:id, u: userId, w: wallet, h: messageHash(built.messageBytes),
      b: built.lastValidBlockHeight, e: expiresAt})).toString('base64url');
    const reviewToken=`${payload}.${this.#mac(payload)}`;
    await this.#store.create(userId,{id,user_id:userId,wallet,review,reviewToken,unsignedTransaction:built.wire,
      blockhash:built.blockhash,observationSlot:built.observationSlot,lastValidBlockHeight:built.lastValidBlockHeight,status:'reviewed',signature:null});
    return Object.freeze({id, review, unsignedTransaction: built.wire, reviewToken});
  }

  #mac(payload: string): string {
    return createHmac('sha256', this.#key).update(payload).digest('base64url');
  }

  /** Sends the signed transaction when it is exactly the one reviewed for this account, still in time. */
  async execute(input: {userId: string; wallet: string; reviewToken: string; signedTransaction: string}): Promise<{signature: string}> {
    let id:string;
    try {
      const payload=input.reviewToken.split('.')[0]!;
      if(payload.length>1024)fail('INVALID_REVIEW');
      id=JSON.parse(Buffer.from(payload,'base64url').toString('utf8')).i;
      if(typeof id!=='string' || !/^[0-9a-f-]{36}$/.test(id))fail('INVALID_REVIEW');
    }catch{return fail('INVALID_REVIEW');}
    const stored=await this.#store.read(input.userId,id!);
    if(!stored || stored.wallet!==input.wallet || stored.reviewToken!==input.reviewToken) return fail('INVALID_REVIEW');
    const tx=getTransactionDecoder().decode(Buffer.from(stored.unsignedTransaction,'base64'));
    const signature=verifySignedTransfer(input.signedTransaction,input.wallet,messageHash(Buffer.from(tx.messageBytes)));
    // A repeat after a lost reply or restart only recovers the same send.
    if(stored.signature===signature)return {signature};
    if(stored.status!=='reviewed' || Date.parse(stored.review.expiresAt)<=this.#now())fail('REVIEW_EXPIRED');
    const height=await this.#call('getBlockHeight',[{commitment:'confirmed'}]);
    if(typeof height!=='number' || !Number.isSafeInteger(height) || height<1)fail('TRANSFER_UNAVAILABLE');
    if((height as number)>stored.lastValidBlockHeight)fail('REVIEW_EXPIRED');
    // This commit must succeed before any broadcast can happen.
    const begun=await this.#store.begin(input.userId,id!,signature);
    if(begun.dispatch) {
      try {
        await this.#call('sendTransaction',[input.signedTransaction,{encoding:'base64',skipPreflight:false,preflightCommitment:'confirmed',maxRetries:5}]);
      }catch {
        // A timeout is not evidence of non-delivery. Recovery checks this signature.
      }
    }
    return {signature};
  }

  async recovery(user:string,wallet:string,id?:string):Promise<StoredTransfer|null> {
    const stored=await this.#store.read(user,id);
    if(!stored || stored.wallet!==wallet)return null;
    if(stored.status==='reviewed' && Date.parse(stored.review.expiresAt)<=this.#now())return {...stored,status:'expired'};
    if(stored.status!=='pending' || !stored.signature)return id?stored:null;
    const result=await this.status(stored.signature);
    if(result.status!=='pending')return this.#store.resolve(user,stored.id,result.status);
    const height=await this.#call('getBlockHeight',[{commitment:'finalized'}]);
    if(typeof height==='number' && Number.isSafeInteger(height) && height>stored.lastValidBlockHeight) {
      const valid=record(await this.#call('isBlockhashValid',[stored.blockhash,{commitment:'finalized',minContextSlot:stored.observationSlot}]));
      const slot=record(valid?.['context'])?.['slot'];
      if(typeof valid?.['value']!=='boolean' || typeof slot!=='number' || !Number.isSafeInteger(slot) || slot<stored.observationSlot)fail('TRANSFER_UNAVAILABLE');
      if(valid!['value']===false) {
        const again=await this.status(stored.signature);
        if(again.status!=='pending')return this.#store.resolve(user,stored.id,again.status);
        // status distinguishes an absent entry from a still-processed transaction.
        if(again.absent && again.contextSlot !== undefined && again.contextSlot >= slot)return this.#store.resolve(user,stored.id,'expired');
      }
    }
    return stored;
  }

  async statusFor(user:string,wallet:string,signature:string) {
    const latest=await this.#store.read(user);
    if(latest?.wallet===wallet && latest.signature===signature) {
      const row=await this.recovery(user,wallet,latest.id);
      if(row && ['confirmed','failed','expired'].includes(row.status))return {status:row.status,slot:null};
    }
    return this.status(signature);
  }

  /** A sent transfer's state on chain. */
  async status(signature: string): Promise<{status: 'pending' | 'confirmed' | 'failed'; slot: number | null; absent?: boolean; contextSlot?: number}> {
    if (!/^[1-9A-HJ-NP-Za-km-z]{64,88}$/.test(signature)) fail('TRANSFER_INPUT_INVALID');
    const result = record(await this.#call('getSignatureStatuses', [[signature], {searchTransactionHistory: true}]));
    const value = result?.['value'];
    if (!Array.isArray(value) || value.length !== 1) return fail('TRANSFER_UNAVAILABLE');
    const entry = record(value[0]);
    const contextSlot = record(result?.['context'])?.['slot'];
    const observation = typeof contextSlot === 'number' && Number.isSafeInteger(contextSlot) && contextSlot > 0 ? {contextSlot} : {};
    if (value[0]===null) return {status: 'pending', slot: null, absent:true, ...observation};
    if(!entry)return fail('TRANSFER_UNAVAILABLE');
    const slot = typeof entry['slot'] === 'number' && Number.isSafeInteger(entry['slot']) && entry['slot']>0 ? entry['slot'] : null;
    if(slot===null || !Object.hasOwn(entry,'err') || !['processed','confirmed','finalized'].includes(String(entry['confirmationStatus'])))return fail('TRANSFER_UNAVAILABLE');
    // A processed result can still disappear on a fork; keep the send locked.
    if (entry['confirmationStatus'] === 'processed') return {status: 'pending', slot};
    if (entry['err'] !== null && entry['err'] !== undefined) return {status: 'failed', slot};
    return ['confirmed', 'finalized'].includes(String(entry['confirmationStatus'])) ? {status: 'confirmed', slot} : {status: 'pending', slot};
  }
}

const messageHash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');

/** The user's signature over exactly the reviewed message; returns it in base58. */
export function verifySignedTransfer(encoded: string, wallet: string, expectedHash: string): string {
  try {
    if (encoded.length > 1644 || Buffer.from(encoded, 'base64').toString('base64') !== encoded) return fail('INVALID_SIGNATURE');
    const wire = Buffer.from(encoded, 'base64');
    const decoded = getTransactionDecoder().decode(wire);
    if (!Buffer.from(getTransactionEncoder().encode(decoded)).equals(wire)) return fail('INVALID_SIGNATURE');
    if (messageHash(Buffer.from(decoded.messageBytes)) !== expectedHash) return fail('INVALID_REVIEW');
    const signers = Object.keys(decoded.signatures);
    if (signers.length !== 1 || signers[0] !== wallet) return fail('INVALID_SIGNATURE');
    const signature = decoded.signatures[address(wallet)];
    if (!signature || signature.length !== 64) return fail('INVALID_SIGNATURE');
    const key = createPublicKey({key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'),
      Buffer.from(getAddressEncoder().encode(address(wallet)))]), format: 'der', type: 'spki'});
    if (!verify(null, Buffer.from(decoded.messageBytes), key, Buffer.from(signature))) return fail('INVALID_SIGNATURE');
    return getBase58Decoder().decode(signature);
  } catch (error) {
    if (error instanceof WalletTransferError) throw error;
    return fail('INVALID_SIGNATURE');
  }
}

export interface WalletTransferAdapters {
  /** Off: no new transfer is reviewed or sent; a sent one can still be looked up. */
  readonly executionEnabled?: boolean;
  authenticate(request: FastifyRequest): Promise<ExistingPracticeAccountAuthentication | null>;
  identities: {resolveFresh(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution>};
  service: WalletTransfers;
}

export const WALLET_TRANSFER_ROUTES = Object.freeze({
  preview: '/v1/wallet/transfers/preview', execute: '/v1/wallet/transfers/execute', status: '/v1/wallet/transfers/status',
});
const KNOWN = new Set(['ACCOUNT_REQUIRED', 'WALLET_REQUIRED', 'TRANSFER_INPUT_INVALID', 'DESTINATION_INVALID', 'DESTINATION_SELF',
  'DESTINATION_NOT_WALLET', 'DESTINATION_FROZEN', 'ASSET_UNSUPPORTED', 'ASSET_NOT_TRANSFERABLE', 'ASSET_PAUSED', 'ASSET_FROZEN',
  'INSUFFICIENT_BALANCE', 'ADD_SOL', 'LEAVES_TOO_LITTLE_SOL', 'AMOUNT_TOO_SMALL', 'SIMULATION_FAILED', 'SIMULATION_MISMATCH',
  'INVALID_REVIEW', 'INVALID_SIGNATURE', 'REVIEW_EXPIRED', 'TRANSFER_NOT_SENT', 'TRANSFER_BUSY', 'TRANSFER_PENDING']);

export function registerWalletTransferRoutes(app: FastifyInstance, adapters?: WalletTransferAdapters): void {
  async function run<T>(request: FastifyRequest, reply: FastifyReply, operation: (user: string, wallet: string) => Promise<T>, financial: boolean) {
    reply.header('cache-control', 'no-store');
    if (!adapters || financial && adapters.executionEnabled === false) return reply.code(503).send({code: 'TRANSFER_UNAVAILABLE'});
    try {
      const account = await adapters.authenticate(request);
      if (!account) return reply.code(401).send({code: 'ACCOUNT_REQUIRED'});
      const identity = await adapters.identities.resolveFresh(account.identity);
      if (identity.subject !== account.identity.subject || identity.embeddedSolanaWallet.status !== 'candidate') return fail('WALLET_REQUIRED');
      return await operation(account.userId, identity.embeddedSolanaWallet.address);
    } catch (error) {
      const raw = error instanceof WalletTransferError ? error.code : error instanceof Error && ['TRANSFER_PENDING','REVIEW_EXPIRED','INVALID_REVIEW','ACCOUNT_REQUIRED'].includes(error.message) ? error.message : 'TRANSFER_UNAVAILABLE';
      const code = KNOWN.has(raw) ? raw : 'TRANSFER_UNAVAILABLE';
      // Codes only: never an address, an amount or a transaction.
      request.log.warn({transferFailure: code}, 'Wallet transfer request failed');
      if (code === 'TRANSFER_BUSY') reply.header('retry-after', '3');
      return reply.code(code === 'TRANSFER_INPUT_INVALID' || code === 'DESTINATION_INVALID' ? 400 : code === 'TRANSFER_BUSY' ? 429
        : code === 'TRANSFER_UNAVAILABLE' ? 503 : 409).send({code});
    }
  }
  app.get<{Querystring:{id?:string}}>('/v1/wallet/transfers/recovery', {
    schema:{querystring:{type:'object',additionalProperties:false,properties:{id:{type:'string',format:'uuid'}}}},
  },(request,reply)=>run(request,reply,async(user,wallet)=>({transfer:await adapters!.service.recovery(user,wallet,request.query.id)}),false));
  const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;
  app.post<{Body: {asset: string; destination: string; amountRaw: string}}>(WALLET_TRANSFER_ROUTES.preview, {bodyLimit: 1024,
    schema: {querystring: noQuery, body: {type: 'object', additionalProperties: false, required: ['asset', 'destination', 'amountRaw'], properties: {
      asset: {type: 'string', pattern: '^(SOL|USDC|[1-9A-HJ-NP-Za-km-z]{32,44})$'},
      destination: {type: 'string', pattern: '^[1-9A-HJ-NP-Za-km-z]{32,44}$'},
      amountRaw: {type: 'string', pattern: '^[1-9][0-9]{0,19}$'}}}}},
  (request, reply) => run(request, reply, (userId, wallet) => adapters!.service.preview({userId, wallet, ...request.body}), true));
  app.post<{Body: {reviewToken: string; signedTransaction: string}}>(WALLET_TRANSFER_ROUTES.execute, {bodyLimit: 4096,
    schema: {querystring: noQuery, body: {type: 'object', additionalProperties: false, required: ['reviewToken', 'signedTransaction'], properties: {
      reviewToken: {type: 'string', minLength: 10, maxLength: 1200, pattern: '^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$'},
      signedTransaction: {type: 'string', minLength: 100, maxLength: 1644, pattern: '^[A-Za-z0-9+/]+={0,2}$'}}}}},
  (request, reply) => run(request, reply, (userId, wallet) => adapters!.service.execute({userId, wallet, ...request.body}), true));
  app.get<{Querystring: {signature: string}}>(WALLET_TRANSFER_ROUTES.status, {
    schema: {querystring: {type: 'object', additionalProperties: false, required: ['signature'],
      properties: {signature: {type: 'string', pattern: '^[1-9A-HJ-NP-Za-km-z]{64,88}$'}}}}},
  (request, reply) => run(request, reply, async(user,wallet) => adapters!.service.statusFor(user,wallet,request.query.signature), false));
}
