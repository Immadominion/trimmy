/**
 * Holdings v2 for the account's embedded Solana wallet. USDC is the cash, SOL
 * pays fees, and stock tokens are raw units with the RPC's display amount.
 * `amountRaw` is everything the wallet holds; `availableToTradeRaw` is the part
 * in the canonical account an order can spend. They are never merged.
 * Contract: apps/api/src/account-holdings-route.ts, mobile account_data_models.dart.
 */
import {ACCOUNT_DATA_AAPLX_MINT, ACCOUNT_DATA_MAINNET_GENESIS, ACCOUNT_DATA_USDC_MINT, AccountDataError,
  canonicalAccountId, solanaAddress} from '../../account/account-data-models.js';

export {parseAccountContext} from '../../account/account-data-models.js';
export type {AccountContextSnapshot, EmbeddedSolanaWallet} from '../../account/account-data-models.js';

const MAX_U64 = 18_446_744_073_709_551_615n;
type Topology = 'none' | 'associated_only' | 'associated_with_ancillary' | 'ancillary_only' | 'multiple_ancillary';

export interface TokenBalance {
  readonly symbol: string; readonly mint: string; readonly decimals: number;
  /** Everything the wallet holds across its valid token accounts. */
  readonly amountRaw: string;
  /** The canonical account's balance, which is what an order can spend. */
  readonly availableToTradeRaw: string;
  readonly observedSlot: number; readonly accountCount: number; readonly accountTopology: Topology;
  readonly hasFrozenAccounts: boolean;
}
export interface WalletStockBalance extends TokenBalance {
  readonly assetId: string; readonly name: string;
  /** The RPC's scaled display amount (shares), or null when it could not be resolved. */
  readonly displayAmount: string | null;
}
export interface HoldingsSnapshot {
  readonly schemaVersion: 1 | 2; readonly userId: string; readonly walletAddress: string;
  readonly observedAt: string; readonly nativeSolLamports: string; readonly nativeSolSlot: number;
  readonly usdc: TokenBalance; readonly stockTokens: readonly WalletStockBalance[];
  /** The legacy AAPLx read's slot, part of the same consistency set. */
  readonly aaplxSlot: number;
}

function invalid(): never {throw new AccountDataError('ACCOUNT_DATA_RESPONSE_INVALID');}
function object(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  const data = value as Record<string, unknown>;
  const own = Object.keys(data);
  if (own.length !== keys.length || own.some(key => !keys.includes(key))) invalid();
  return data;
}
function raw(value: unknown, max = MAX_U64): string {
  if (typeof value !== 'string' || !/^(?:0|[1-9][0-9]{0,19})$/.test(value) || BigInt(value) > max) invalid();
  return value;
}
function slot(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) invalid();
  return value;
}
function timestamp(value: unknown): string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) ||
      new Date(Date.parse(value)).toISOString() !== value) invalid();
  return value;
}
const TOPOLOGIES: readonly Topology[] = ['none', 'associated_only', 'associated_with_ancillary', 'ancillary_only', 'multiple_ancillary'];

function tokenFields(data: Record<string, unknown>, expected: {symbol: string; mint: string; decimals: number}): TokenBalance {
  const amount = raw(data['amountRaw']), count = slot(data['accountCount']);
  const topology = data['accountTopology'];
  if (!TOPOLOGIES.includes(topology as Topology)) invalid();
  const frozen = data['hasFrozenAccounts'];
  if (typeof frozen !== 'boolean') invalid();
  // Older reads leave spendability out: only a lone unfrozen canonical account is spendable.
  const available = 'availableToTradeRaw' in data ? raw(data['availableToTradeRaw'])
    : topology === 'associated_only' && !frozen ? amount : '0';
  const unspendable = topology === 'none' || topology === 'ancillary_only' || topology === 'multiple_ancillary' ||
    topology === 'associated_only' && frozen;
  if (data['symbol'] !== expected.symbol || data['mint'] !== expected.mint || data['decimals'] !== expected.decimals ||
      BigInt(available) > BigInt(amount) || unspendable && available !== '0' ||
      data['amountUnits'] !== 'raw_token_units' || count > 128 ||
      topology === 'none' && count !== 0 || (topology === 'associated_only' || topology === 'ancillary_only') && count !== 1 ||
      (topology === 'associated_with_ancillary' || topology === 'multiple_ancillary') && count < 2 ||
      data['aggregation'] !== 'all_valid_owner_token_accounts' || count === 0 && (frozen || amount !== '0')) invalid();
  return Object.freeze({symbol: expected.symbol, mint: expected.mint, decimals: expected.decimals, amountRaw: amount,
    availableToTradeRaw: available, observedSlot: slot(data['observedSlot']), accountCount: count,
    accountTopology: topology as Topology, hasFrozenAccounts: frozen});
}

const TOKEN_KEYS = ['symbol', 'mint', 'decimals', 'amountRaw', 'amountUnits', 'observedSlot', 'accountCount',
  'accountTopology', 'aggregation', 'hasFrozenAccounts'];

function stockToken(value: unknown): WalletStockBalance {
  const data = object(value, ['assetId', 'name', ...TOKEN_KEYS, 'availableToTradeRaw', 'displayAmount', 'displayResolution', 'displayUnits']);
  const {assetId, name, symbol, mint, decimals, displayAmount} = data;
  if (typeof assetId !== 'string' || !/^[a-z0-9][a-z0-9_-]{0,127}$/.test(assetId) || typeof name !== 'string' ||
      !name || name.length > 160 || /[\x00-\x1f\x7f]/.test(name) || typeof symbol !== 'string' || !symbol ||
      symbol.length > 32 || /[\x00-\x20\x7f]/.test(symbol) || typeof mint !== 'string' || mint === ACCOUNT_DATA_USDC_MINT ||
      typeof decimals !== 'number' || !Number.isInteger(decimals) || decimals < 0 || decimals > 18 ||
      data['amountRaw'] === '0' || data['displayUnits'] !== 'token_units' ||
      (displayAmount === null ? data['displayResolution'] !== 'unavailable'
        : typeof displayAmount !== 'string' || displayAmount.length > 80 ||
          !/^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(displayAmount) || data['displayResolution'] !== 'rpc_ui_amount')) invalid();
  solanaAddress(mint);
  return Object.freeze({...tokenFields(data, {symbol, mint, decimals}), assetId, name, displayAmount: displayAmount as string | null});
}

/** Accepts schema 2 (requested) and schema 1 from an older server. */
export function parseHoldings(value: unknown, expectedUserId: string): HoldingsSnapshot {
  const envelope = object(value, ['schemaVersion', 'userId', 'wallet', 'holdings']);
  const version = envelope['schemaVersion'];
  if (version !== 1 && version !== 2) invalid();
  const userId = canonicalAccountId(envelope['userId']);
  if (userId !== canonicalAccountId(expectedUserId)) throw new AccountDataError('ACCOUNT_DATA_ACCOUNT_CHANGED');
  const wallet = object(envelope['wallet'], ['address', 'source', 'possessionSignatureVerified']);
  if (wallet['source'] !== 'privy_embedded_wallet_same_subject' || wallet['possessionSignatureVerified'] !== false) invalid();
  const walletAddress = solanaAddress(wallet['address']);
  const holdings = object(envelope['holdings'], ['network', 'genesisHash', 'commitment', 'observedAt', 'readOnly',
    'transactionBuilt', 'transactionSigned', 'transactionBroadcast', 'balances', 'consistency']);
  if (holdings['network'] !== 'solana:mainnet-beta' || holdings['genesisHash'] !== ACCOUNT_DATA_MAINNET_GENESIS ||
      holdings['commitment'] !== 'confirmed' || holdings['readOnly'] !== true || holdings['transactionBuilt'] !== false ||
      holdings['transactionSigned'] !== false || holdings['transactionBroadcast'] !== false) invalid();
  const balances = object(holdings['balances'], version === 2 ? ['nativeSol', 'usdc', 'aaplx', 'tokens'] : ['nativeSol', 'usdc', 'aaplx']);
  const sol = object(balances['nativeSol'], ['symbol', 'decimals', 'amountRaw', 'amountUnits', 'observedSlot']);
  if (sol['symbol'] !== 'SOL' || sol['decimals'] !== 9 || sol['amountUnits'] !== 'lamports') invalid();
  const lamports = raw(sol['amountRaw'], BigInt(Number.MAX_SAFE_INTEGER)), solSlot = slot(sol['observedSlot']);
  const usdc = tokenFields(object(balances['usdc'], version === 2 ? [...TOKEN_KEYS, 'availableToTradeRaw'] : TOKEN_KEYS),
    {symbol: 'USDC', mint: ACCOUNT_DATA_USDC_MINT, decimals: 6});
  const aaplxData = object(balances['aaplx'], [...TOKEN_KEYS, 'displayResolution', 'displayAmount', 'shareAmount', 'eligibility', 'executionEnabled']);
  if (aaplxData['displayResolution'] !== 'token_2022_scaled_ui_unresolved' || aaplxData['displayAmount'] !== null ||
      aaplxData['shareAmount'] !== null || aaplxData['eligibility'] !== 'unverified' || aaplxData['executionEnabled'] !== false) invalid();
  const aaplx = tokenFields(aaplxData, {symbol: 'AAPLx', mint: ACCOUNT_DATA_AAPLX_MINT, decimals: 8});
  let stockTokens: WalletStockBalance[];
  if (version === 2) {
    const tokens = balances['tokens'];
    if (!Array.isArray(tokens) || tokens.length > 256) invalid();
    stockTokens = tokens.map(stockToken);
    if (new Set(stockTokens.map(token => token.mint)).size !== stockTokens.length) invalid();
  } else {
    stockTokens = aaplx.amountRaw === '0' ? [] : [Object.freeze({...aaplx, assetId: 'apple', name: 'Apple', displayAmount: null})];
  }
  const consistency = object(holdings['consistency'], ['kind', 'atomic', 'slots']);
  const slots = object(consistency['slots'], ['nativeSol', 'usdc', 'aaplx']);
  if (consistency['kind'] !== 'independent_confirmed_reads' || consistency['atomic'] !== false ||
      slots['nativeSol'] !== solSlot || slots['usdc'] !== usdc.observedSlot || slots['aaplx'] !== aaplx.observedSlot) invalid();
  return Object.freeze({schemaVersion: version, userId, walletAddress, observedAt: timestamp(holdings['observedAt']),
    nativeSolLamports: lamports, nativeSolSlot: solSlot, usdc, stockTokens: Object.freeze(stockTokens), aaplxSlot: aaplx.observedSlot});
}

/** Every slot the snapshot read, so a confirmed trade's slot floor can be checked. */
export function holdingsSlots(holdings: HoldingsSnapshot): readonly number[] {
  return [holdings.nativeSolSlot, holdings.usdc.observedSlot, holdings.aaplxSlot, ...holdings.stockTokens.map(token => token.observedSlot)];
}
