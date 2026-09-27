/**
 * Small per-account browser records for own money. Nothing here is a
 * credential: the money mode, the issuer terms a person ticked, and the id of
 * an order whose result is not yet known. Blocked storage degrades to this tab.
 */
export type MoneyStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

export function browserMoneyStorage(): MoneyStorage | null {
  try {return window.localStorage;} catch {return null;}
}
const scope = (apiBase: string, accountId: string) => `${encodeURIComponent(apiBase)}.${accountId}`;

/** Account-scoped practice/real choice. It never grants transaction permission. */
export class MoneyModeStore {
  readonly #key: string;
  #memory: boolean | null = null;
  constructor(private readonly storage: MoneyStorage | null, apiBase: string, accountId: string) {
    this.#key = `trimmy.money-mode.v1.${scope(apiBase, accountId)}`;
  }
  get real(): boolean {
    if (this.#memory !== null) return this.#memory;
    try {return this.storage?.getItem(this.#key) === 'real';} catch {return false;}
  }
  set(real: boolean): void {
    this.#memory = real;
    try {this.storage?.setItem(this.#key, real ? 'real' : 'paper');} catch { /* This tab keeps the choice. */ }
  }
}

/** Eligibility ticks per account, issuer and terms version. A new version needs a new tick. */
export class IssuerTermsStore {
  readonly #key: string;
  readonly #accepted = new Set<string>();
  constructor(private readonly storage: MoneyStorage | null, accountId: string) {
    this.#key = `trimmy.issuer-terms.v1.${accountId}`;
    try {
      const saved: unknown = JSON.parse(storage?.getItem(this.#key) ?? '[]');
      if (Array.isArray(saved)) for (const entry of saved.slice(0, 200)) if (typeof entry === 'string' && entry.length < 200) this.#accepted.add(entry);
    } catch { /* Unreadable storage only means the terms are asked for again. */ }
  }
  static #entry(issuerId: string, version: string): string {return JSON.stringify([issuerId, version]);}
  accepted(issuerId: string, version: string): boolean {return this.#accepted.has(IssuerTermsStore.#entry(issuerId, version));}
  record(issuerId: string, version: string, accepted: boolean): void {
    const entry = IssuerTermsStore.#entry(issuerId, version);
    if (accepted) this.#accepted.add(entry); else this.#accepted.delete(entry);
    try {this.storage?.setItem(this.#key, JSON.stringify([...this.#accepted].sort()));} catch { /* Kept for this session. */ }
  }
}

/**
 * The id of an order that may have been dispatched. It is written and read
 * back before execute is sent; if the browser cannot keep it, nothing is sent.
 */
export class PendingOrderStore {
  readonly #key: string;
  constructor(private readonly storage: MoneyStorage | null, apiBase: string, accountId: string) {
    this.#key = `trimmy.live-order.pending.v1.${scope(apiBase, accountId)}`;
  }
  get key(): string {return this.#key;}
  read(): string | null {
    try {
      const raw = this.storage?.getItem(this.#key);
      if (!raw || raw.length > 200) return null;
      const value: unknown = JSON.parse(raw);
      const id = value && typeof value === 'object' && 'id' in value ? (value as {id: unknown}).id : null;
      return typeof id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id) ? id : null;
    } catch {return null;}
  }
  /** True only when the id is durably stored in this browser. */
  remember(id: string): boolean {
    try {
      if (!this.storage) return false;
      this.storage.setItem(this.#key, JSON.stringify({id, savedAt: new Date().toISOString()}));
      return this.read() === id;
    } catch {return false;}
  }
  clear(id?: string): void {
    try {if (id === undefined || this.read() === id) this.storage?.removeItem(this.#key);} catch { /* Cleared on the next read. */ }
  }
}
