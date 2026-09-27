/**
 * Read-only account wallet reads for one verified account: the server's view
 * of the linked Privy Solana wallet (context) and its holdings v2. Every call
 * takes a fresh bearer for the same identity; nothing here signs or funds.
 */
import {AccountDataError, type AccountDataErrorCode, canonicalAccountId} from '../../account/account-data-models.js';
import {MoneyHttpError, moneyApiBase, requestJson, responseCode, validBearer, type BearerSource} from './http.js';
import {parseAccountContext, parseHoldings, type AccountContextSnapshot, type HoldingsSnapshot} from './wallet-models.js';

const KNOWN: ReadonlySet<string> = new Set<AccountDataErrorCode>([
  'ACCOUNT_CONTEXT_UNAUTHENTICATED', 'ACCOUNT_CONTEXT_UNAVAILABLE', 'ACCOUNT_CONTEXT_INVALID_REQUEST',
  'ACCOUNT_HOLDINGS_UNAUTHENTICATED', 'ACCOUNT_HOLDINGS_UNAVAILABLE', 'ACCOUNT_HOLDINGS_INVALID_REQUEST',
  'ACCOUNT_HOLDINGS_WALLET_MISSING', 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS', 'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED',
  'PRIVY_VERIFIED_IDENTITY_INVALID', 'PRIVY_USER_RESPONSE_INVALID', 'PRIVY_USER_UNAVAILABLE', 'PRIVY_USER_TIMEOUT',
  'PRIVY_USER_RATE_LIMITED', 'STOCK_HOLDINGS_OWNER_INVALID', 'STOCK_HOLDINGS_OWNER_UNVERIFIED',
  'STOCK_HOLDINGS_CONFIGURATION_INVALID', 'STOCK_HOLDINGS_RPC_UNAVAILABLE', 'STOCK_HOLDINGS_RPC_TIMEOUT',
  'STOCK_HOLDINGS_RPC_RESPONSE_INVALID', 'STOCK_HOLDINGS_WRONG_NETWORK', 'STOCK_HOLDINGS_RATE_LIMITED',
  'BROWSER_ORIGIN_DENIED', 'BROWSER_PREFLIGHT_DENIED', 'INVALID_REQUEST', 'NOT_FOUND', 'INTERNAL_ERROR',
]);
const MAX_BYTES = 262_144;

export interface AccountWalletClientOptions {
  readonly baseUrl: string; readonly accountId: string; readonly bearer: BearerSource;
  readonly fetch?: typeof fetch; readonly timeoutMs?: number;
}

export class AccountWalletClient {
  readonly accountId: string;
  readonly #base: string; readonly #bearer: BearerSource; readonly #fetch: typeof fetch; readonly #timeout: number;
  constructor(options: AccountWalletClientOptions) {
    this.#base = moneyApiBase(options.baseUrl);
    this.accountId = canonicalAccountId(options.accountId);
    this.#bearer = options.bearer;
    this.#fetch = options.fetch ?? globalThis.fetch.bind(globalThis);
    this.#timeout = options.timeoutMs ?? 15_000;
  }

  /**
   * `fresh` asks the server to bypass its linked-identity cache, so a wallet
   * created a moment ago is not hidden by an earlier "missing" read. Browsers
   * express it themselves: fetch's `no-store` mode sends `Cache-Control:
   * no-cache` without an author header, so no extra CORS permission is needed.
   */
  readContext(options: {fresh?: boolean; signal?: AbortSignal} = {}): Promise<AccountContextSnapshot> {
    return this.#get('/v1/account/context', {}, options.fresh ? 'no-store' : 'default', options.signal,
      body => parseAccountContext(body, this.accountId));
  }

  /** Holdings v2. A confirmed trade's slot keeps later reads from going back in time. */
  readHoldings(options: {minimumObservedSlot?: number | null; signal?: AbortSignal} = {}): Promise<HoldingsSnapshot> {
    const slot = options.minimumObservedSlot;
    if (slot !== undefined && slot !== null && (!Number.isSafeInteger(slot) || slot < 1)) {
      return Promise.reject(new AccountDataError('ACCOUNT_HOLDINGS_INVALID_REQUEST'));
    }
    const headers: Record<string, string> = {'x-trimmy-holdings-version': '2'};
    if (slot) headers['x-trimmy-holdings-min-slot'] = String(slot);
    return this.#get('/v1/account/holdings', headers, 'no-store', options.signal, body => parseHoldings(body, this.accountId));
  }

  async #get<T>(path: string, headers: Record<string, string>, cache: RequestCache, signal: AbortSignal | undefined,
    parse: (body: unknown) => T): Promise<T> {
    let token: string | null;
    try {token = await this.#bearer();} catch {token = null;}
    if (!validBearer(token)) throw new AccountDataError('ACCOUNT_DATA_TOKEN_UNAVAILABLE');
    let response;
    try {
      response = await requestJson(this.#fetch, `${this.#base}${path}`, {headers: {...headers, authorization: `Bearer ${token}`},
        cache, timeoutMs: this.#timeout, maxBytes: MAX_BYTES, signal});
    } catch (error) {
      const code = error instanceof MoneyHttpError ? error.code : 'NETWORK';
      throw new AccountDataError(code === 'TIMEOUT' ? 'ACCOUNT_DATA_TIMEOUT' : code === 'CANCELLED' ? 'ACCOUNT_DATA_CANCELLED'
        : code === 'TOO_LARGE' ? 'ACCOUNT_DATA_RESPONSE_TOO_LARGE' : code === 'INVALID' ? 'ACCOUNT_DATA_RESPONSE_INVALID'
        : code === 'REDIRECT' ? 'ACCOUNT_DATA_REDIRECT_REJECTED' : 'ACCOUNT_DATA_NETWORK_ERROR');
    }
    if (response.status !== 200) {
      const code = responseCode(response.body);
      throw new AccountDataError(code && KNOWN.has(code) ? code as AccountDataErrorCode : 'ACCOUNT_DATA_RESPONSE_INVALID');
    }
    return parse(response.body);
  }
}
