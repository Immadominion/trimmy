import {
  PracticeClient, PracticeError, assertReceiptMatches, freezePracticeValue, normalizePracticeApiBase,
  parseGuest, parseGuestCreation, parseLaunchWrite, parsePaperCommit, parsePaperPreview,
  parsePaperReceipt, parsePracticeUuid, parsePracticeSubject, parseProfileWrite, parseDailyDeskCompletion, parseDailyDeskShift, parseWorkdayMutation, parseWorkdayAssignment,
} from './practice-client.js';
import type {
  WorkdayJourney, WorkdayAssignment, WorkdayAnswer, WorkdayMutation, CareerActivityWeek, DailyDeskCompletion, DailyDeskShift, CareerMissionBoard, CareerSummary, GuestCreationRequest, GuestCredential, LaunchAction, ProductOnboarding,
  PaperCommitRequest, PaperOrderIntent, PaperPortfolio, PaperPreview, PaperReceipt,
  ProductLaunchWrite, ProductProfile, ProductProfileWrite, PracticeAccountAccess, PracticeAccountProof, PracticeIdentity, GuestClaimRequest,
} from './practice-client.js';

export type PracticeStorage = Pick<Storage, 'getItem' | 'setItem'>;
export type PracticeCrypto = Pick<Crypto, 'randomUUID' | 'getRandomValues'>;
// Match mobile GuestSessionController.ensureActive: routine restores reuse a valid token.
const GUEST_REFRESH_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
export interface PendingPaperCommit {
  readonly guestId: string | null; readonly accountId?: string; readonly body: PaperCommitRequest; readonly preview: PaperPreview;
}
interface AccountBinding {readonly subject: string; readonly accountId: string}
interface SavedClaim {
  readonly subject: string; readonly guestId: string; readonly body: GuestClaimRequest;
  readonly status: 'pending' | 'claimed' | 'conflict' | 'preserved'; readonly failureCode: string | null;
}
type PendingProfileMutation = {readonly kind: 'profile'; readonly body: ProductProfileWrite} |
  {readonly kind: 'launch'; readonly body: ProductLaunchWrite};
interface SavedPractice {
  readonly version: 1; readonly apiBase: string; readonly issuance: GuestCreationRequest | null;
  readonly guest: GuestCredential | null; readonly pendingCommit: PendingPaperCommit | null;
  readonly lastReceipt: PaperReceipt | null; readonly pendingProfile: PendingProfileMutation | null;
  readonly terminalGuestCode: string | null;
  readonly account?: AccountBinding | null; readonly claim?: SavedClaim | null;
  readonly pendingDailyDesk?: DailyDeskCompletion | null; readonly pendingWorkdayMutation?: WorkdayMutation | null;
}
export interface PracticeSessionOptions {
  readonly client: PracticeClient; readonly storage: PracticeStorage; readonly crypto?: PracticeCrypto;
  readonly now?: () => number;
  /** Defaults to the browser Web Locks API. No runner or server is needed. */
  readonly locks?: Pick<LockManager, 'request'>;
  readonly account?: PracticeAccountAccess;
}
/** API origins never share a guest credential or a pending trade. This key contains no secret. */
export function practiceStorageKey(apiBase: string): string {
  return `trimmy.practice.v1:${encodeURIComponent(normalizePracticeApiBase(apiBase))}`;
}
export function practiceAccountStorageKey(apiBase: string, account: AccountBinding): string {
  return `${practiceStorageKey(apiBase)}:account:${encodeURIComponent(parsePracticeSubject(account.subject))}:${parsePracticeUuid(account.accountId)}`;
}
function sessionError(code: string, message: string): never {throw new PracticeError(code, message);}
function savedRecord(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return sessionError('PRACTICE_STORAGE_INVALID', 'Your saved desk could not be read.');
  return value as Record<string, unknown>;
}
function parseSaved(raw: string, apiBase: string, expectedAccount: AccountBinding | null): SavedPractice {
  try {
    if (raw.length > 65_536) throw new Error();
    const v = savedRecord(JSON.parse(raw));
    if (v['version'] !== 1 || v['apiBase'] !== apiBase) throw new Error();
    const issuance = v['issuance'] === null ? null : parseGuestCreation(v['issuance']);
    const guest = v['guest'] === null ? null : parseGuest(v['guest']);
    let account: AccountBinding | null = null;
    if (v['account'] != null) {const a = savedRecord(v['account']); account = {subject: parsePracticeSubject(a['subject']), accountId: parsePracticeUuid(a['accountId'])};}
    if (account?.subject !== expectedAccount?.subject || account?.accountId !== expectedAccount?.accountId) throw new Error();
    if (account ? issuance !== null || guest !== null : (issuance === null) === (guest === null)) throw new Error();
    let pendingCommit: PendingPaperCommit | null = null;
    if (v['pendingCommit'] !== null) {
      const p = savedRecord(v['pendingCommit']), body = parsePaperCommit(p['body']), preview = parsePaperPreview(p['preview']);
      if (body.previewId !== preview.id || preview.state !== 'open') throw new Error();
      if (account) {
        if (p['guestId'] !== null || parsePracticeUuid(p['accountId']) !== account.accountId) throw new Error();
        pendingCommit = {guestId: null, accountId: account.accountId, body, preview};
      } else {
        const guestId = parsePracticeUuid(p['guestId']);
        if (!guest || guestId !== guest.guestId || p['accountId'] != null) throw new Error();
        pendingCommit = {guestId, body, preview};
      }
    }
    const lastReceipt = v['lastReceipt'] === null ? null : parsePaperReceipt(v['lastReceipt']);
    let pendingProfile: PendingProfileMutation | null = null;
    if (v['pendingProfile'] !== null) {
      const p = savedRecord(v['pendingProfile']);
      if (p['kind'] === 'profile') pendingProfile = {kind: 'profile', body: parseProfileWrite(p['body'])};
      else if (p['kind'] === 'launch') pendingProfile = {kind: 'launch', body: parseLaunchWrite(p['body'])};
      else throw new Error();
    }
    const pendingDailyDesk = v['pendingDailyDesk'] == null ? null : parseDailyDeskCompletion(v['pendingDailyDesk']);
    const pendingWorkdayMutation = v['pendingWorkdayMutation'] == null ? null : parseWorkdayMutation(v['pendingWorkdayMutation']);
    const terminalGuestCode = v['terminalGuestCode'];
    if (terminalGuestCode !== null && (typeof terminalGuestCode !== 'string' || !/^[A-Z][A-Z0-9_]{1,99}$/u.test(terminalGuestCode))) throw new Error();
    if ((!guest && !account && (pendingCommit || lastReceipt || pendingProfile || pendingDailyDesk || pendingWorkdayMutation)) || (!guest && terminalGuestCode)) throw new Error();
    let claim: SavedClaim | null = null;
    if (v['claim'] != null) {
      const c = savedRecord(v['claim']), body = savedRecord(c['body']);
      if (!guest || account || c['guestId'] !== guest.guestId || body['schemaVersion'] !== 1 ||
        !['pending', 'claimed', 'conflict', 'preserved'].includes(String(c['status']))) throw new Error();
      const failureCode = c['failureCode'];
      if (failureCode !== null && !['GUEST_CLAIM_ACCOUNT_EXISTS', 'GUEST_SESSION_EXPIRED'].includes(String(failureCode))) throw new Error();
      if ((c['status'] === 'conflict' || c['status'] === 'preserved') !== (failureCode !== null)) throw new Error();
      claim = {subject: parsePracticeSubject(c['subject']), guestId: guest.guestId,
        body: {schemaVersion: 1, idempotencyKey: parsePracticeUuid(body['idempotencyKey'])},
        status: c['status'] as SavedClaim['status'], failureCode: failureCode as string | null};
    }
    return freezePracticeValue({version: 1, apiBase, issuance, guest, pendingCommit, lastReceipt, pendingProfile, terminalGuestCode, account, claim, pendingDailyDesk, pendingWorkdayMutation});
  } catch {return sessionError('PRACTICE_STORAGE_INVALID', 'Your saved desk could not be read. It has not been replaced.');}
}

/**
 * Durable identity-bound practice boundary. Reading or exploring never creates a desk.
 * Commands are stored before dispatch; ambiguous outcomes can only replay that command.
 * Returned values are frozen, and storage changes invalidate an in-flight identity.
 */
export class PracticeSession {
  readonly apiBase: string;
  readonly storageKey: string;
  readonly #client: PracticeClient;
  readonly #storage: PracticeStorage;
  readonly #crypto: PracticeCrypto;
  readonly #now: () => number;
  readonly #locks: Pick<LockManager, 'request'> | undefined;
  readonly #account: PracticeAccountAccess | null;
  #closed = false;
  #raw: string | null;
  #saved: SavedPractice | null;
  #busy = false;
  #offeredPreview: PaperPreview | null = null;
  #dailyEpoch = 0;
  #dailyConfirmed: DailyDeskShift | null = null;
  #dailyCompletion: Promise<DailyDeskShift> | null = null;
  #workdayEpoch = 0;
  #workdayConfirmed: WorkdayJourney | null = null;
  #workdayMutation: Promise<WorkdayJourney> | null = null;
  constructor(options: PracticeSessionOptions) {
    this.#client = options.client; this.apiBase = options.client.apiBase;
    this.#account = options.account ? {...options.account, subject: parsePracticeSubject(options.account.subject), accountId: parsePracticeUuid(options.account.accountId)} : null;
    this.storageKey = this.#account ? practiceAccountStorageKey(this.apiBase, this.#account) : practiceStorageKey(this.apiBase); this.#storage = options.storage;
    this.#crypto = options.crypto ?? globalThis.crypto; this.#now = options.now ?? Date.now;
    this.#locks = options.locks ?? (typeof navigator === 'undefined' ? undefined : navigator.locks);
    this.#raw = this.#readRaw(); this.#saved = this.#raw === null ? (this.#account ? {version: 1, apiBase: this.apiBase,
      issuance: null, guest: null, pendingCommit: null, lastReceipt: null, pendingProfile: null, terminalGuestCode: null,
      account: {subject: this.#account.subject, accountId: this.#account.accountId}} : null) : parseSaved(this.#raw, this.apiBase, this.#account);
  }
  get isAccount(): boolean {return this.#account !== null;}
  get hasSavedGuest(): boolean {return !this.isAccount && this.#saved !== null && this.#saved.claim?.status !== 'claimed';}
  get hasSavedIdentity(): boolean {return this.isAccount || this.hasSavedGuest;}
  get hasIdentity(): boolean {return !this.#closed && !this.#account?.signal.aborted && (this.isAccount || this.guest !== null);}
  get guest(): GuestCredential | null {return this.#saved?.claim?.status === 'claimed' ? null : this.#saved?.guest ?? null;}
  get pendingCommit(): PendingPaperCommit | null {return this.#saved?.pendingCommit ?? null;}
  get lastReceipt(): PaperReceipt | null {return this.#saved?.lastReceipt ?? null;}
  get pendingDailyDesk(): DailyDeskCompletion | null {return this.#saved?.pendingDailyDesk ?? null;}
  get pendingWorkdayMutation(): WorkdayMutation | null {return this.#saved?.pendingWorkdayMutation ?? null;}
  close(): void {this.#closed = true; this.#offeredPreview = null;}
  #readRaw(): string | null {
    try {return this.#storage.getItem(this.storageKey);}
    catch {return sessionError('PRACTICE_STORAGE_UNAVAILABLE', 'Allow browser storage before continuing with this desk.');}
  }
  #assertBound(): void {
    if (this.#closed || this.#account?.signal.aborted) sessionError('PRACTICE_SESSION_CHANGED', 'Your signed-in desk changed. Sign in again to continue.');
    if (this.#readRaw() !== this.#raw) sessionError('PRACTICE_SESSION_CHANGED', 'Your saved desk changed in another tab. Reload to restore it.');
  }
  #save(value: SavedPractice): void {
    this.#assertBound(); const raw = JSON.stringify(value);
    const parsed = parseSaved(raw, this.apiBase, this.#account);
    try {
      this.#storage.setItem(this.storageKey, raw);
      if (this.#storage.getItem(this.storageKey) !== raw) throw new Error();
    } catch {return sessionError('PRACTICE_STORAGE_UNAVAILABLE', 'Your desk could not be saved safely. Retry before continuing.');}
    this.#saved = parsed; this.#raw = raw;
  }
  #uuid(): string {
    try {return parsePracticeUuid(this.#crypto.randomUUID());}
    catch {return sessionError('PRACTICE_CRYPTO_UNAVAILABLE', 'Secure browser storage identifiers are unavailable.');}
  }
  #creation(): GuestCreationRequest {
    try {
      const bytes = this.#crypto.getRandomValues(new Uint8Array(32));
      const secret = btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');
      return parseGuestCreation({schemaVersion: 1, requestId: this.#uuid(), replaySecret: `gr1_${secret}`});
    } catch {return sessionError('PRACTICE_CRYPTO_UNAVAILABLE', 'Secure browser storage identifiers are unavailable.');}
  }
  #activeGuest(): GuestCredential {
    this.#assertBound();
    if (this.#saved?.claim?.status === 'pending') sessionError('PRACTICE_CLAIM_PENDING', 'Finish linking this desk before continuing.');
    if (this.#saved?.terminalGuestCode) throw new PracticeError(this.#saved.terminalGuestCode, 'This saved guest desk is no longer active. Sign in to recover a saved desk.', 401);
    const guest = this.guest;
    if (!guest) return sessionError('PRACTICE_GUEST_REQUIRED', 'Start practicing to create your guest desk.');
    if (this.#now() >= Date.parse(guest.expiresAt) || this.#now() >= Date.parse(guest.hardExpiresAt)) {
      throw new PracticeError('GUEST_SESSION_EXPIRED', 'This saved guest desk has expired. It has not been replaced.', 401);
    }
    return guest;
  }
  #activeIdentity(): PracticeIdentity {this.#assertBound(); return this.#account ?? this.#activeGuest();}
  async #bound<T>(operation: (identity: PracticeIdentity) => Promise<T>): Promise<T> {
    const guest = this.#activeIdentity(), expected = this.#raw;
    try {
      const result = await operation(guest);
      this.#assertBound();
      if (expected !== this.#raw) sessionError('PRACTICE_SESSION_CHANGED', 'Your desk changed while the request was running. Try again.');
      return result;
    } catch (error) {
      this.#assertBound();
      if (expected !== this.#raw) sessionError('PRACTICE_SESSION_CHANGED', 'Your desk changed while the request was running. Try again.');
      if (!this.#account && error instanceof PracticeError && error.terminalGuest && this.#saved) this.#save({...this.#saved, terminalGuestCode: error.code});
      throw error;
    }
  }
  async #exclusive<T>(operation: () => Promise<T>, signal?: AbortSignal): Promise<T> {
    if (this.#busy) return sessionError('PRACTICE_BUSY', 'Wait for the current desk request to finish.');
    if (signal?.aborted) throw new PracticeError('PRACTICE_ABORTED', 'Practice request cancelled.');
    if (typeof window !== 'undefined' && !this.#locks) {
      return sessionError('PRACTICE_COORDINATION_UNAVAILABLE', 'This browser cannot safely coordinate your saved desk. Use a browser with Web Locks support.');
    }
    this.#busy = true;
    try {
      const run = async () => {this.#assertBound(); return operation();};
      // Serializes all conforming tabs. Storage binding still rejects stale instances after the lock is acquired.
      return this.#locks ? await this.#locks.request(this.storageKey, {...(signal ? {signal} : {}), mode: 'exclusive'}, run) : await run();
    } catch (error) {
      if (signal?.aborted && !(error instanceof PracticeError)) throw new PracticeError('PRACTICE_ABORTED', 'Practice request cancelled.');
      throw error;
    } finally {this.#busy = false;}
  }
  /** Explicit user entry, or restoration only when hasSavedGuest was already true. */
  ensureGuest(signal?: AbortSignal): Promise<GuestCredential> {
    return this.#exclusive(async () => {
      if (this.isAccount) return sessionError('PRACTICE_ACCOUNT_ACTIVE', 'This desk belongs to your signed-in account.');
      if (this.#saved?.claim?.status === 'claimed') {
        // Explicit new practice after logout retains the complete claimed desk journal.
        const archiveKey = `${this.storageKey}:claimed:${this.#saved.claim.guestId}`;
        try {this.#storage.setItem(archiveKey, this.#raw!); if (this.#storage.getItem(archiveKey) !== this.#raw) throw new Error();}
        catch {return sessionError('PRACTICE_STORAGE_UNAVAILABLE', 'Your saved desk could not be preserved safely.');}
        this.#save({version: 1, apiBase: this.apiBase, issuance: this.#creation(), guest: null,
          pendingCommit: null, lastReceipt: null, pendingProfile: null, terminalGuestCode: null});
      }
      if (this.guest) {
        const current = this.#activeGuest();
        if (Date.parse(current.expiresAt) - this.#now() > GUEST_REFRESH_WINDOW_MS) return current;
        const refreshed = await this.#bound(() => this.#client.refreshGuest(current, signal));
        this.#save({...this.#saved!, guest: refreshed}); return refreshed;
      }
      if (!this.#saved) this.#save({version: 1, apiBase: this.apiBase, issuance: this.#creation(), guest: null,
        pendingCommit: null, lastReceipt: null, pendingProfile: null, terminalGuestCode: null});
      const issuance = this.#saved!.issuance;
      if (!issuance) return sessionError('PRACTICE_STORAGE_INVALID', 'Your saved guest request is unavailable.');
      const guest = await this.#client.createGuest(issuance, signal);
      this.#assertBound(); this.#save({...this.#saved!, issuance: null, guest}); return guest;
    }, signal);
  }
  async ensureActive(signal?: AbortSignal): Promise<void> {
    if (!this.isAccount) {await this.ensureGuest(signal); return;}
    this.#assertBound(); if (signal?.aborted) sessionError('PRACTICE_ABORTED', 'Practice request cancelled.');
  }
  /** Link only a settled guest ledger. Unknown claim outcomes replay their original key. */
  claimForAccount(account: PracticeAccountProof, openExistingAccount = false): Promise<'claimed' | 'none' | 'preserved'> {
    const subject = parsePracticeSubject(account.subject);
    return this.#exclusive(async () => {
      const assertLive = () => {this.#assertBound(); if (account.signal.aborted) sessionError('PRACTICE_ABORTED', 'Sign-in was cancelled.');};
      assertLive();
      if (this.isAccount) return sessionError('PRACTICE_ACCOUNT_ACTIVE', 'This desk is already signed in.');
      if (this.#saved?.pendingCommit) return sessionError('PRACTICE_COMMIT_PENDING', 'Check your pending order from the desk before signing in.');
      if (this.#saved?.pendingProfile) return sessionError('PRACTICE_PROFILE_PENDING', 'Finish the pending desk setup before signing in.');
      if (this.pendingDailyDesk) return sessionError('PRACTICE_DAILY_DESK_PENDING', 'Check your pending desk story before signing in.');
      if (this.pendingWorkdayMutation) return sessionError('PRACTICE_WORKDAY_PENDING', 'Check your pending assignment save before signing in.');
      if (!this.#saved) return 'none';
      if (this.#saved.issuance) {
        const guest = await this.#client.createGuest(this.#saved.issuance, account.signal);
        assertLive(); this.#save({...this.#saved, issuance: null, guest});
      }
      const guest = this.#saved.guest;
      if (!guest) return sessionError('PRACTICE_STORAGE_INVALID', 'Your saved guest desk is unavailable.');
      let claim = this.#saved.claim;
      if (claim?.status === 'claimed') return claim.subject === subject ? 'claimed' : 'none';
      if (claim?.status === 'pending' && claim.subject !== subject) return sessionError('PRACTICE_CLAIM_PENDING', 'Sign in to the same account to finish linking this desk.');
      if (claim?.subject === subject && (claim.status === 'conflict' || claim.status === 'preserved')) {
        if (openExistingAccount || claim.status === 'preserved') {
          assertLive(); this.#save({...this.#saved, claim: {...claim, status: 'preserved'}}); return 'preserved';
        }
        throw new PracticeError(claim.failureCode!, 'This account has a different saved desk. You can open it and keep this guest desk here.');
      }
      // An explicit choice cannot bypass an unknown claim or a newly discovered guest.
      if (!claim || claim.subject !== subject) {
        claim = {subject, guestId: guest.guestId, body: {schemaVersion: 1, idempotencyKey: this.#uuid()}, status: 'pending', failureCode: null};
        this.#save({...this.#saved, claim});
      }
      try {
        await this.#client.claimGuest(guest, account, claim.body, account.signal);
        assertLive(); this.#save({...this.#saved, claim: {...claim, status: 'claimed', failureCode: null}}); return 'claimed';
      } catch (error) {
        assertLive();
        if (error instanceof PracticeError && ((error.code === 'GUEST_CLAIM_ACCOUNT_EXISTS' && error.status === 409) ||
          (error.code === 'GUEST_SESSION_EXPIRED' && error.status === 401))) {
          this.#save({...this.#saved, claim: {...claim, status: 'conflict', failureCode: error.code}});
        }
        throw error;
      }
    }, account.signal);
  }
  readProfile(signal?: AbortSignal): Promise<ProductProfile | null> {return this.#bound(guest => this.#client.readProfile(guest, signal));}
  async #sendProfile(signal?: AbortSignal): Promise<ProductProfile> {
    const mutation = this.#saved?.pendingProfile;
    if (!mutation) return sessionError('PRACTICE_STORAGE_INVALID', 'Your profile request is unavailable.');
    try {
      const profile = await this.#bound(guest => mutation.kind === 'profile'
        ? this.#client.writeProfile(guest, mutation.body, signal) : this.#client.advanceLaunch(guest, mutation.body, signal));
      this.#save({...this.#saved!, pendingProfile: null}); return profile;
    } catch (error) {
      if (error instanceof PracticeError && error.status === 409 && [
        'PRODUCT_PROFILE_REVISION_CONFLICT', 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT',
        'PRODUCT_PROFILE_PAPER_TRADE_REQUIRED', 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED', 'PRODUCT_PROFILE_HANDLE_TAKEN',
      ].includes(error.code)) this.#save({...this.#saved!, pendingProfile: null});
      throw error;
    }
  }
  /** Nullable preferences are truthful. This never claims that a trade or introduction happened. */
  ensureProfile(signal?: AbortSignal): Promise<ProductProfile> {
    return this.#exclusive(async () => {
      this.#activeIdentity();
      if (this.#saved?.pendingProfile) return this.#sendProfile(signal);
      const profile = await this.readProfile(signal); if (profile) return profile;
      this.#save({...this.#saved!, pendingProfile: {kind: 'profile', body: {schemaVersion: 2, mutationId: this.#uuid(), baseRevision: 0,
        onboarding: {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null}, launchCheckpoint: 'first-trade'}}});
      return this.#sendProfile(signal);
    }, signal);
  }
  /** Patch only persona against the current server revision; preserve every other preference and launch field. */
  updatePersona(persona: ProductOnboarding['persona'], signal?: AbortSignal): Promise<ProductProfile> {
    return this.#exclusive(async () => {
      this.#activeIdentity();
      if (persona !== null && !['wolf', 'oracle', 'shark'].includes(persona)) return sessionError('PRACTICE_PERSONA_INVALID', 'Choose an available persona.');
      if (this.#saved?.pendingProfile) await this.#sendProfile(signal);
      const profile = await this.readProfile(signal);
      if (!profile) return sessionError('PRODUCT_PROFILE_MISSING', 'Set up your profile before choosing a persona.');
      if (profile.onboarding.persona === persona) return profile;
      this.#save({...this.#saved!, pendingProfile: {kind: 'profile', body: parseProfileWrite({schemaVersion: 2,
        mutationId: this.#uuid(), baseRevision: profile.revision, onboarding: {...profile.onboarding, persona},
        launchCheckpoint: profile.launchCheckpoint})}});
      return this.#sendProfile(signal);
    }, signal);
  }
  advanceLaunch(action: LaunchAction, signal?: AbortSignal): Promise<ProductProfile> {
    return this.#exclusive(async () => {
      this.#activeIdentity(); const pending = this.#saved?.pendingProfile;
      if (pending) {
        if (pending.kind !== 'launch' || pending.body.action !== action) return sessionError('PRACTICE_PROFILE_PENDING', 'Resolve the previous profile request before continuing.');
        return this.#sendProfile(signal);
      }
      const profile = await this.readProfile(signal);
      if (!profile) return sessionError('PRODUCT_PROFILE_MISSING', 'Set up the guest profile before continuing.');
      this.#save({...this.#saved!, pendingProfile: {kind: 'launch', body: parseLaunchWrite({schemaVersion: 2,
        mutationId: this.#uuid(), baseRevision: profile.revision, action})}});
      return this.#sendProfile(signal);
    }, signal);
  }
  readPortfolio(signal?: AbortSignal): Promise<PaperPortfolio> {return this.#bound(guest => this.#client.readPortfolio(guest, signal));}
  readCareerSummary(signal?: AbortSignal): Promise<CareerSummary> {return this.#bound(guest => this.#client.readCareerSummary(guest, signal));}
  readMissions(signal?: AbortSignal): Promise<CareerMissionBoard> {return this.#bound(guest => this.#client.readMissions(guest, signal));}
  readActivityWeek(signal?: AbortSignal): Promise<CareerActivityWeek> {return this.#bound(identity => this.#client.readActivityWeek(identity, signal));}
  async #waitForProgress<T>(task: Promise<T>, signal?: AbortSignal): Promise<T> {
    let stop!: () => void;
    const cancelled = new Promise<never>((_resolve, reject) => {stop = () => reject(new PracticeError('PRACTICE_ABORTED', 'Practice request cancelled.'));});
    signal?.addEventListener('abort', stop, {once: true});
    if (signal?.aborted) stop();
    try {const shift = await Promise.race([task, cancelled]); this.#assertBound(); return shift;}
    finally {signal?.removeEventListener('abort', stop);}
  }
  async readWorkdays(signal?: AbortSignal): Promise<WorkdayJourney> {
    this.#assertBound();
    if (signal?.aborted) return sessionError('PRACTICE_ABORTED', 'Practice request cancelled.');
    if (this.#workdayMutation) return this.#waitForProgress(this.#workdayMutation, signal);
    const epoch = this.#workdayEpoch;
    try {
      const journey = await this.#bound(identity => this.#client.readWorkdays(identity, signal));
      if (epoch !== this.#workdayEpoch) {
        if (signal?.aborted) return sessionError('PRACTICE_ABORTED', 'Practice request cancelled.');
        if (this.#workdayMutation) return this.#waitForProgress(this.#workdayMutation, signal);
        if (this.#workdayConfirmed) return this.#workdayConfirmed;
        return sessionError('PRACTICE_ABORTED', 'The assignment changed while loading. Try again.');
      }
      this.#workdayConfirmed = journey; return journey;
    } catch (error) {
      this.#assertBound();
      if (!signal?.aborted && epoch !== this.#workdayEpoch) {
        if (this.#workdayMutation) return this.#waitForProgress(this.#workdayMutation, signal);
        if (this.#workdayConfirmed) return this.#workdayConfirmed;
      }
      throw error;
    }
  }
  /** Use the revision the player actually edited; conflicts never silently resubmit another stage. */
  saveWorkdayStep(original: WorkdayAssignment, answer: WorkdayAnswer,
    {draft, signal}: {readonly draft?: string; readonly signal?: AbortSignal} = {}): Promise<WorkdayJourney> {
    const assignment = parseWorkdayAssignment(original);
    if (assignment.step === 3) return Promise.reject(new PracticeError('WORK_CHANGED', 'This assignment has already been filed.'));
    const mutation = parseWorkdayMutation({kind: 'step', body: {assignmentId: assignment.id, revision: assignment.revision,
      step: assignment.step, answer, ...(draft === undefined ? {} : {draft})}});
    return this.#saveWorkdayMutation(mutation, signal);
  }
  saveWorkdayDraft(original: WorkdayAssignment, draft: string, signal?: AbortSignal): Promise<WorkdayJourney> {
    const assignment = parseWorkdayAssignment(original);
    if (assignment.step !== 2) return Promise.reject(new PracticeError('WORK_CHANGED', 'Open the hand-off stage before saving a note.'));
    return this.#saveWorkdayMutation(parseWorkdayMutation({kind: 'draft', body: {assignmentId: assignment.id,
      revision: assignment.revision, draft}}), signal);
  }
  #saveWorkdayMutation(mutation: WorkdayMutation, signal?: AbortSignal): Promise<WorkdayJourney> {
    if (this.#workdayMutation) return Promise.reject(new PracticeError('PRACTICE_BUSY', 'Wait for your assignment to finish saving.'));
    return this.#trackWorkdayMutation(this.#exclusive(async () => {
      this.#activeIdentity();
      if (this.pendingDailyDesk) return sessionError('PRACTICE_DAILY_DESK_PENDING', 'Check your earlier desk story before saving an assignment.');
      const pending = this.pendingWorkdayMutation;
      if (pending && JSON.stringify(pending) !== JSON.stringify(mutation)) return sessionError('PRACTICE_WORKDAY_PENDING', 'Check the previous assignment save before changing it.');
      if (!pending) this.#save({...this.#saved!, pendingWorkdayMutation: mutation});
      return this.#sendWorkdayMutation(signal);
    }, signal));
  }
  retryPendingWorkday(signal?: AbortSignal): Promise<WorkdayJourney> {
    if (this.#workdayMutation) return Promise.reject(new PracticeError('PRACTICE_BUSY', 'Wait for your assignment to finish saving.'));
    return this.#trackWorkdayMutation(this.#exclusive(() => this.#sendWorkdayMutation(signal), signal));
  }
  #trackWorkdayMutation(task: Promise<WorkdayJourney>): Promise<WorkdayJourney> {
    this.#workdayEpoch++; this.#workdayConfirmed = null;
    const tracked = task.then(journey => {this.#assertBound(); this.#workdayConfirmed = journey; return journey;})
      .finally(() => {this.#workdayEpoch++; if (this.#workdayMutation === tracked) this.#workdayMutation = null;});
    this.#workdayMutation = tracked; return tracked;
  }
  async #sendWorkdayMutation(signal?: AbortSignal): Promise<WorkdayJourney> {
    const pending = this.pendingWorkdayMutation;
    if (!pending) return sessionError('PRACTICE_NO_PENDING_WORKDAY', 'There is no assignment save waiting to be checked.');
    try {
      const journey = await this.#bound(identity => pending.kind === 'step'
        ? this.#client.saveWorkdayStep(identity, pending.body, signal) : this.#client.saveWorkdayDraft(identity, pending.body, signal));
      this.#save({...this.#saved!, pendingWorkdayMutation: null}); return journey;
    } catch (error) {
      // These responses prove this command was rejected. Refresh the server snapshot before an explicit retry.
      if (error instanceof PracticeError && ((error.status === 409 && ['WORK_CHANGED', 'WORK_LOCKED'].includes(error.code)) ||
        (error.status === 400 && ['INVALID_WORK', 'CHECK_EVIDENCE', 'CHECK_DECISION'].includes(error.code)))) {
        this.#save({...this.#saved!, pendingWorkdayMutation: null});
      }
      throw error;
    }
  }
  async readDailyDesk(signal?: AbortSignal): Promise<DailyDeskShift> {
    this.#assertBound();
    if (signal?.aborted) return sessionError('PRACTICE_ABORTED', 'Practice request cancelled.');
    // A refresh during a completion observes its confirmed response instead of racing it.
    if (this.#dailyCompletion) return this.#waitForProgress(this.#dailyCompletion, signal);
    const epoch = this.#dailyEpoch;
    try {
      const shift = await this.#bound(identity => this.#client.readDailyDesk(identity, signal));
      if (epoch !== this.#dailyEpoch) {
        if (signal?.aborted) return sessionError('PRACTICE_ABORTED', 'Practice request cancelled.');
        if (this.#dailyCompletion) return this.#waitForProgress(this.#dailyCompletion, signal);
        if (this.#dailyConfirmed) return this.#dailyConfirmed;
        return sessionError('PRACTICE_ABORTED', 'The desk story changed while loading. Try again.');
      }
      this.#dailyConfirmed = shift; return shift;
    } catch (error) {
      this.#assertBound();
      if (!signal?.aborted && epoch !== this.#dailyEpoch) {
        if (this.#dailyCompletion) return this.#waitForProgress(this.#dailyCompletion, signal);
        if (this.#dailyConfirmed) return this.#dailyConfirmed;
      }
      throw error;
    }
  }
  completeDailyDesk(original: DailyDeskShift, choiceId: string, signal?: AbortSignal): Promise<DailyDeskShift> {
    const shift = parseDailyDeskShift(original);
    if (!shift.story.choices.some(choice => choice.id === choiceId)) return Promise.reject(new PracticeError('INVALID_CHOICE', 'Choose one of the available responses.'));
    const body = parseDailyDeskCompletion({date: shift.date, caseId: shift.story.id, choiceId});
    if (this.#dailyCompletion) return Promise.reject(new PracticeError('PRACTICE_BUSY', 'Wait for your desk story to finish saving.'));
    return this.#trackDailyCompletion(this.#exclusive(async () => {
      this.#activeIdentity();
      const pending = this.pendingDailyDesk;
      if (pending && JSON.stringify(pending) !== JSON.stringify(body)) return sessionError('PRACTICE_DAILY_DESK_PENDING', 'Check the previous desk story result before choosing another response.');
      if (!pending) this.#save({...this.#saved!, pendingDailyDesk: body});
      return this.#sendDailyDesk(signal);
    }, signal));
  }
  retryPendingDailyDesk(signal?: AbortSignal): Promise<DailyDeskShift> {
    if (this.#dailyCompletion) return Promise.reject(new PracticeError('PRACTICE_BUSY', 'Wait for your desk story to finish saving.'));
    return this.#trackDailyCompletion(this.#exclusive(() => this.#sendDailyDesk(signal), signal));
  }
  #trackDailyCompletion(task: Promise<DailyDeskShift>): Promise<DailyDeskShift> {
    this.#dailyEpoch++; this.#dailyConfirmed = null;
    const tracked = task.then(shift => {this.#assertBound(); this.#dailyConfirmed = shift; return shift;})
      .finally(() => {this.#dailyEpoch++; if (this.#dailyCompletion === tracked) this.#dailyCompletion = null;});
    this.#dailyCompletion = tracked; return tracked;
  }
  async #sendDailyDesk(signal?: AbortSignal): Promise<DailyDeskShift> {
    const pending = this.pendingDailyDesk;
    if (!pending) return sessionError('PRACTICE_NO_PENDING_DAILY_DESK', 'There is no desk story waiting to be checked.');
    try {
      const shift = await this.#bound(identity => this.#client.completeDailyDesk(identity, pending, signal));
      this.#save({...this.#saved!, pendingDailyDesk: null}); return shift;
    } catch (error) {
      // The server checks an existing decision before date/choice rejection. Unknown results remain durable.
      if (error instanceof PracticeError && ((error.status === 409 && ['DAY_CHANGED', 'SHIFT_ALREADY_COMPLETE'].includes(error.code)) ||
        (error.status === 400 && error.code === 'INVALID_CHOICE'))) this.#save({...this.#saved!, pendingDailyDesk: null});
      throw error;
    }
  }

  #noPendingCommit(): void {
    if (this.pendingCommit) sessionError('PRACTICE_COMMIT_PENDING', 'Check the previous order result before requesting another quote.');
  }
  previewOrder(intent: PaperOrderIntent, signal?: AbortSignal): Promise<PaperPreview> {
    return this.#exclusive(async () => {
      this.#activeIdentity(); this.#noPendingCommit(); this.#offeredPreview = null;
      const preview = await this.#bound(guest => this.#client.previewOrder(guest, {schemaVersion: 1, requestId: this.#uuid(), ...intent}, signal));
      if (Date.parse(preview.expiresAt) <= this.#now()) return sessionError('PAPER_PREVIEW_EXPIRED', 'This quote expired. Get a new quote.');
      this.#offeredPreview = preview; return preview;
    }, signal);
  }
  commitOrder(preview: PaperPreview, signal?: AbortSignal): Promise<PaperReceipt> {
    return this.#exclusive(async () => {
      const identity = this.#activeIdentity(); this.#noPendingCommit();
      // Only the exact last quote issued for this instance and identity can become a new command.
      if (preview !== this.#offeredPreview) return sessionError('PRACTICE_PREVIEW_CHANGED', 'Get a current quote before confirming this order.');
      if (Date.parse(preview.expiresAt) <= this.#now()) return sessionError('PAPER_PREVIEW_EXPIRED', 'This quote expired. Get a new quote.');
      this.#save({...this.#saved!, pendingCommit: {guestId: 'guestId' in identity ? identity.guestId : null,
        ...(this.#account ? {accountId: this.#account.accountId} : {}), preview,
        body: {schemaVersion: 1, previewId: preview.id, idempotencyKey: this.#uuid()}}});
      this.#offeredPreview = null; return this.#sendCommit(signal);
    }, signal);
  }
  async #sendCommit(signal?: AbortSignal): Promise<PaperReceipt> {
    const pending = this.pendingCommit;
    if (!pending) return sessionError('PRACTICE_NO_PENDING_COMMIT', 'There is no order waiting to be checked.');
    try {
      const receipt = await this.#bound(guest => this.#client.commitOrder(guest, pending.body, pending.preview, signal));
      assertReceiptMatches(pending.preview, receipt);
      // Clear the unknown order only after a validated receipt is durably retained.
      this.#save({...this.#saved!, pendingCommit: null, lastReceipt: receipt}); return receipt;
    } catch (error) {
      // The server checks the idempotency ledger before these rejection paths.
      // Therefore an exact retry returning one of these confirms this command did not commit.
      if (error instanceof PracticeError && (error.status === 404 || error.status === 409) && [
        'PAPER_PREVIEW_NOT_FOUND', 'PAPER_PREVIEW_EXPIRED', 'PAPER_PORTFOLIO_CHANGED', 'PAPER_CASH_INSUFFICIENT',
        'PAPER_POSITION_INSUFFICIENT', 'PAPER_TRIM_NOT_WINNING', 'PAPER_TRIM_MUST_BE_PARTIAL', 'PAPER_ORDER_TOO_SMALL', 'PAPER_LIMIT_REACHED',
      ].includes(error.code)) this.#save({...this.#saved!, pendingCommit: null});
      throw error;
    }
  }
  retryPendingCommit(signal?: AbortSignal): Promise<PaperReceipt> {
    return this.#exclusive(() => this.#sendCommit(signal), signal);
  }
}
