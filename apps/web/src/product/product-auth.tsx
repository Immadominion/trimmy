import {Component, createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode} from 'react';
import {IdentityBoundTokenReader, validPrivySubject} from '../account/token-binding.js';
import {normalizePracticeApiBase} from './practice-client.js';
import {productApiBase} from './config.js';
import {loadProductAuthSdk, type ProductAuthSdkCallbacks, type ProductAuthSdkPort} from './product-auth-sdk-loader.js';

export type ProductLoginMethod = 'email' | 'google' | 'x';
export type ProductAuthPhase = 'unconfigured' | 'restoring' | 'ready' | 'sending-code' | 'code-sent' |
  'authenticating' | 'connecting' | 'account-choice' | 'authenticated' | 'signing-out' | 'error';
export interface ProductAccountAccess {
  readonly subject: string; readonly accountId: string;
  readonly freshAccessToken: () => Promise<string | null>;
  /** Remains live for this verified identity epoch, including after connection. */
  readonly signal: AbortSignal;
}
export interface ProductAccountConnection {
  readonly accountId: string;
  readonly guestDisposition?: 'claimed' | 'none' | 'preserved';
}
export type ConnectProductAccount = (input: {
  readonly subject: string; readonly freshAccessToken: () => Promise<string | null>;
  readonly signal: AbortSignal; readonly openExistingAccount?: boolean;
}) => Promise<ProductAccountConnection>;
export type ProductAuthConfig = Readonly<{kind: 'disabled' | 'invalid'}> |
  Readonly<{kind: 'enabled'; appId: string; clientId?: string; apiBase: string}>;
type EnabledConfig = Extract<ProductAuthConfig, {kind: 'enabled'}>;
type AuthStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

export interface ProductAuth {
  readonly enabled: boolean; readonly ready: boolean; readonly busy: boolean;
  /** True only after the API has verified this SDK identity and returned its account UUID. */
  readonly authenticated: boolean; readonly phase: ProductAuthPhase;
  readonly subject: string | null; readonly accountId: string | null;
  readonly accountAccess: ProductAccountAccess | null; readonly apiBase: string | null;
  readonly email: string | null; readonly errorCode: string | null;
  readonly guestDisposition: 'claimed' | 'none' | 'preserved' | null;
  readonly lastSuccessfulMethod: ProductLoginMethod | null;
  sendEmailCode(email: string): Promise<void>;
  verifyEmailCode(code: string): Promise<void>;
  loginWithProvider(provider: 'google' | 'x'): Promise<void>;
  freshAccessToken(expectedSubject: string): Promise<string | null>;
  openExistingAccount(): Promise<void>;
  retry(): Promise<void>;
  logout(): Promise<boolean>;
  /** Back from an idle email step. Pending login/claim operations remain guarded. */
  cancel(): void;
}
const unavailable: ProductAuth = Object.freeze({enabled: false, ready: true, busy: false, authenticated: false,
  phase: 'unconfigured', subject: null, accountId: null, accountAccess: null, apiBase: null, email: null,
  errorCode: null, guestDisposition: null, lastSuccessfulMethod: null,
  sendEmailCode: async () => {}, verifyEmailCode: async () => {}, loginWithProvider: async () => {},
  freshAccessToken: async () => null, openExistingAccount: async () => {}, retry: async () => {}, logout: async () => true, cancel() {},
});
export const ProductAuthContext = createContext<ProductAuth>(unavailable);
export function useProductAuth(): ProductAuth {return useContext(ProductAuthContext);}

export function readProductAuthConfig(apiBase?: string | null, env: Record<string, unknown> = import.meta.env ?? {}): ProductAuthConfig {
  const appId = env['VITE_PRIVY_APP_ID'], clientId = env['VITE_PRIVY_APP_CLIENT_ID'];
  if ((appId === undefined || appId === '') && (clientId === undefined || clientId === '')) return {kind: 'disabled'};
  const id = (value: unknown): value is string => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.exec(value)?.[0] === value;
  if (!id(appId) || clientId !== undefined && clientId !== '' && !id(clientId)) return {kind: 'invalid'};
  try {return {kind: 'enabled', appId, ...(id(clientId) ? {clientId} : {}),
    apiBase: normalizePracticeApiBase((apiBase === undefined ? productApiBase(env) : apiBase) ?? '')};}
  catch {return {kind: 'invalid'};}
}
export function productAuthMethodStorageKey(config: {appId: string; clientId?: string; apiBase: string}): string {
  return `trimmy.product.last-login.v1.${encodeURIComponent(config.appId)}.${encodeURIComponent(config.clientId ?? '')}.${encodeURIComponent(config.apiBase)}`;
}
function method(value: unknown): ProductLoginMethod | null {return value === 'email' || value === 'google' || value === 'x' ? value : null;}
function browserStore(kind: 'localStorage' | 'sessionStorage'): AuthStorage | null {try {return window[kind];} catch {return null;}}
function readMethod(storage: AuthStorage | null, key: string): ProductLoginMethod | null {try {return method(storage?.getItem(key));} catch {return null;}}
function safeError(error: unknown, fallback: string): string {
  const code = error && typeof error === 'object' && 'code' in error ? error.code : null;
  return typeof code === 'string' && /^(?:GUEST|PRACTICE|PRODUCT)_[A-Z0-9_]{1,80}$/.test(code) ? code : fallback;
}
const choiceErrors = new Set(['GUEST_CLAIM_ACCOUNT_EXISTS', 'GUEST_SESSION_EXPIRED']);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
type Operation = {generation: number; kind: 'send' | 'login' | 'oauth' | 'logout'; method: ProductLoginMethod};
type Connection = ProductAccountAccess & {guestDisposition: 'claimed' | 'none' | 'preserved'};

function Bridge({sdk, config, connectAccount, children}: {sdk: ProductAuthSdkPort; config: EnabledConfig; connectAccount: ConnectProductAccount; children: ReactNode}) {
  const native = sdk.usePrivy();
  const nativeRef = useRef(native); nativeRef.current = native;
  const connectRef = useRef(connectAccount); connectRef.current = connectAccount;
  const local = useMemo(() => browserStore('localStorage'), []), transient = useMemo(() => browserStore('sessionStorage'), []);
  const memoryKey = productAuthMethodStorageKey(config), pendingKey = `${memoryKey}.oauth-pending`;
  const [lastMethod, setLastMethod] = useState(() => readMethod(local, memoryKey));
  const [phase, setPhase] = useState<ProductAuthPhase>('restoring');
  const [errorCode, setError] = useState<string | null>(null), [email, setEmail] = useState<string | null>(null);
  const emailRef = useRef<string | null>(null);
  const [connection, setConnection] = useState<Connection | null>(null);
  const [, render] = useState(0), [retryEpoch, retryRender] = useState(0);
  const live = useRef(true), generation = useRef(0), nativeEpoch = useRef(0);
  const allowed = useRef<string | null | undefined>(undefined), observed = useRef<string | null | undefined>(undefined);
  const operation = useRef<Operation | null>(null), outstanding = useRef(0);
  const completed = useRef<{subject: string; method: ProductLoginMethod} | null>(null);
  const controller = useRef<AbortController | null>(null), opening = useRef(false), existingChoice = useRef(false);
  const wasReady = useRef(false);
  const reader = useMemo(() => new IdentityBoundTokenReader(config.appId), [config.appId]);
  const resume = useRef<ProductLoginMethod | null | undefined>(undefined);
  if (resume.current === undefined) {
    resume.current = null;
    try {
      const raw = transient?.getItem(pendingKey);
      const item: unknown = raw && raw.length < 200 ? JSON.parse(raw) : null;
      if (item && typeof item === 'object' && 'method' in item && 'at' in item &&
          (item.method === 'google' || item.method === 'x') && typeof item.at === 'number' &&
          Date.now() - item.at >= 0 && Date.now() - item.at < 600000) resume.current = item.method;
    } catch { /* A hint is never an authentication credential. */ }
    if (resume.current) operation.current = {generation: generation.current, kind: 'oauth', method: resume.current};
  }
  const sdkSubject = native.ready && !native.error && native.authenticated && validPrivySubject(native.user?.id) ? native.user.id : null;
  if (!native.ready && wasReady.current) {
    nativeEpoch.current++; controller.current?.abort(); controller.current = null;
  }
  wasReady.current = native.ready;
  if (native.ready && observed.current !== sdkSubject) {
    const initial = observed.current === undefined;
    observed.current = sdkSubject; nativeEpoch.current++;
    controller.current?.abort(); controller.current = null;
    if (initial && allowed.current === undefined) allowed.current = sdkSubject;
    else if (operation.current?.kind !== 'login' && operation.current?.kind !== 'oauth' && allowed.current !== sdkSubject) {
      allowed.current = null; completed.current = null;
    }
  }
  const subject = sdkSubject !== null && allowed.current === sdkSubject ? sdkSubject : null;
  reader.observe(subject);
  const subjectRef = useRef(subject); subjectRef.current = subject;
  const removePending = useCallback(() => {resume.current = null; try {transient?.removeItem(pendingKey);} catch { /* Optional hint only. */ }}, [transient, pendingKey]);
  const remember = useCallback((identity: string) => {
    if (completed.current?.subject !== identity) return;
    const value = completed.current.method; completed.current = null;
    setLastMethod(value);
    try {local?.setItem(memoryKey, value);} catch { /* Authentication does not depend on remembering a button. */ }
    removePending();
  }, [local, memoryKey, removePending]);
  const freshAccessToken = useCallback((expectedSubject: string) => reader.read(expectedSubject, () => nativeRef.current.getAccessToken()), [reader]);
  useEffect(() => {
    live.current = true; reader.observe(subjectRef.current);
    if (operation.current?.kind === 'oauth' && resume.current) operation.current.generation = generation.current;
    return () => {live.current = false; generation.current++; controller.current?.abort(); reader.invalidate();};
  }, [reader]);

  const onComplete: ProductAuthSdkCallbacks['onComplete'] = result => {
    const current = operation.current;
    const resultMethod = result.loginMethod === 'twitter' ? 'x' : method(result.loginMethod);
    if (!live.current || !current || current.generation !== generation.current ||
        (current.kind !== 'login' && current.kind !== 'oauth') || !validPrivySubject(result.user.id) ||
        resultMethod !== null && resultMethod !== current.method) return;
    allowed.current = result.user.id;
    completed.current = {subject: result.user.id, method: current.method};
    operation.current = null; setError(null); setPhase('connecting'); render(value => value + 1);
  };
  const onError: ProductAuthSdkCallbacks['onError'] = code => {
    const current = operation.current;
    if (!live.current || !current || current.generation !== generation.current || current.kind === 'logout') return;
    operation.current = null; allowed.current = null; completed.current = null; reader.invalidate(); removePending();
    setError(code === 'cancelled' ? null : 'PRODUCT_SIGN_IN_FAILED');
    setPhase(code === 'cancelled' ? (emailRef.current ? 'code-sent' : 'ready') : 'error');
  };
  const emailSdk = sdk.useLoginWithEmail({onComplete, onError});
  const oauthSdk = sdk.useLoginWithOAuth({onComplete, onError});
  const hooks = useRef({emailSdk, oauthSdk}); hooks.current = {emailSdk, oauthSdk};
  const oauthStatusSeen = useRef<typeof oauthSdk.status | null>(null);
  useEffect(() => {
    const previous = oauthStatusSeen.current; oauthStatusSeen.current = oauthSdk.status;
    // Privy's redirect state-mismatch branch updates hook state without firing
    // login.onError. Handle that documented SDK state independently of callbacks.
    if (oauthSdk.status === 'error' && previous !== 'error' && operation.current?.kind === 'oauth') onError('login_failed');
  }, [oauthSdk.status]);

  // A server connection lives for exactly one native identity epoch. A returned
  // UUID is not cached as evidence on reload, and late A→B→A responses are denied.
  useEffect(() => {
    setConnection(null);
    if (!subject) {
      if (native.ready && !operation.current) setPhase(current =>
        current === 'restoring' || current === 'connecting' || current === 'authenticated' || current === 'account-choice' ? 'ready' : current);
      return;
    }
    const abort = new AbortController(); controller.current = abort; opening.current = true;
    const identityEpoch = nativeEpoch.current, attempt = generation.current;
    const current = () => live.current && !abort.signal.aborted && generation.current === attempt &&
      nativeEpoch.current === identityEpoch && subjectRef.current === subject;
    const access = async () => current() ? freshAccessToken(subject) : null;
    setPhase('connecting'); setError(null);
    void (async () => {
      try {
        const result = await connectRef.current({subject, freshAccessToken: access, signal: abort.signal,
          ...(existingChoice.current ? {openExistingAccount: true} : {})});
        if (!current()) return;
        if (!uuid.test(result.accountId) || result.guestDisposition !== undefined &&
            !['claimed', 'none', 'preserved'].includes(result.guestDisposition)) throw new Error('Invalid account binding');
        setConnection({subject, accountId: result.accountId, freshAccessToken: access, signal: abort.signal,
          guestDisposition: result.guestDisposition ?? 'none'});
        operation.current = null; setPhase('authenticated'); setEmail(null); emailRef.current = null;
        remember(subject);
      } catch (error) {
        if (!current()) return;
        const code = safeError(error, 'PRODUCT_ACCOUNT_CONNECTION_FAILED');
        setError(code); setPhase(choiceErrors.has(code) ? 'account-choice' : 'error');
      } finally {if (controller.current === abort) opening.current = false;}
    })();
    return () => {abort.abort(); if (controller.current === abort) {controller.current = null; opening.current = false;}};
  }, [subject, native.ready, nativeEpoch.current, retryEpoch, freshAccessToken, remember]);

  const hasConnection = connection?.subject === subject && !connection.signal.aborted;
  useEffect(() => {if (hasConnection && subject) remember(subject);});
  const begin = useCallback((kind: Operation['kind'], selected: ProductLoginMethod): Operation | null => {
    if (!live.current || !nativeRef.current.ready || operation.current || outstanding.current || opening.current || nativeRef.current.authenticated) return null;
    const attempt = {generation: ++generation.current, kind, method: selected}; operation.current = attempt;
    allowed.current = null; completed.current = null; reader.invalidate(); existingChoice.current = false;
    setError(null); return attempt;
  }, [reader]);
  const active = (attempt: Operation) => live.current && operation.current === attempt && attempt.generation === generation.current;
  const sendEmailCode = useCallback(async (input: string) => {
    const normalized = input.trim().toLowerCase();
    const attempt = begin('send', 'email'); if (!attempt) return;
    if (normalized.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) {
      operation.current = null; setError('PRODUCT_EMAIL_INVALID'); setPhase('error'); return;
    }
    setPhase('sending-code'); outstanding.current++;
    try {
      await hooks.current.emailSdk.sendCode({email: normalized});
      if (!active(attempt)) return;
      emailRef.current = normalized; setEmail(normalized); operation.current = null; setPhase('code-sent');
    } catch {
      if (active(attempt)) {operation.current = null; setError('PRODUCT_EMAIL_CODE_SEND_FAILED'); setPhase('error');}
    } finally {outstanding.current--;}
  }, [begin]);
  const verifyEmailCode = useCallback(async (input: string) => {
    if (!emailRef.current) return;
    const attempt = begin('login', 'email'); if (!attempt) return;
    const code = input.trim();
    if (!/^\d{6}$/.test(code)) {operation.current = null; setError('PRODUCT_EMAIL_CODE_INVALID'); setPhase('code-sent'); return;}
    setPhase('authenticating'); outstanding.current++;
    try {await hooks.current.emailSdk.loginWithCode({code});}
    catch {if (active(attempt)) {operation.current = null; setError('PRODUCT_EMAIL_CODE_INVALID'); setPhase('code-sent');}}
    finally {outstanding.current--;}
  }, [begin]);
  const loginWithProvider = useCallback(async (provider: 'google' | 'x') => {
    if (provider !== 'google' && provider !== 'x') return;
    const attempt = begin('oauth', provider); if (!attempt) return;
    setPhase('authenticating'); outstanding.current++;
    try {
      // Only a short-lived method hint crosses the redirect. No email, token,
      // subject, guest credential or account UUID is stored here.
      try {transient?.setItem(pendingKey, JSON.stringify({method: provider, at: Date.now()}));} catch { /* SDK still owns OAuth state. */ }
      await hooks.current.oauthSdk.initOAuth({provider: provider === 'x' ? 'twitter' : 'google'});
    } catch {
      if (active(attempt)) {operation.current = null; removePending(); setError('PRODUCT_SIGN_IN_FAILED'); setPhase('error');}
    } finally {outstanding.current--;}
  }, [begin, transient, pendingKey, removePending]);
  const retry = useCallback(async () => {
    if (!live.current || operation.current || opening.current || outstanding.current) return;
    if (subjectRef.current) {existingChoice.current = false; retryRender(value => value + 1);}
    else {setError(null); setPhase(emailRef.current ? 'code-sent' : 'ready');}
  }, []);
  const openExistingAccount = useCallback(async () => {
    if (phase !== 'account-choice' || !subjectRef.current || operation.current || opening.current || outstanding.current) return;
    existingChoice.current = true; retryRender(value => value + 1);
  }, [phase]);
  const logout = useCallback(async () => {
    if (operation.current?.kind === 'logout') return false;
    const attempt: Operation = {generation: ++generation.current, kind: 'logout', method: 'email'};
    operation.current = attempt; allowed.current = null; completed.current = null; controller.current?.abort();
    reader.invalidate(); removePending(); setConnection(null); setEmail(null); emailRef.current = null;
    setError(null); setPhase('signing-out');
    try {
      await nativeRef.current.logout();
      if (!active(attempt)) return false;
      operation.current = null; setPhase('ready'); return true;
    } catch {
      if (active(attempt)) {operation.current = null; setError('PRODUCT_SIGN_OUT_FAILED'); setPhase('error');}
      return false;
    }
  }, [reader, removePending]);
  const cancel = useCallback(() => {
    if (operation.current || outstanding.current || opening.current || subjectRef.current) return;
    generation.current++; allowed.current = null; completed.current = null; reader.invalidate(); removePending();
    emailRef.current = null; setEmail(null); setError(null); setPhase('ready');
  }, [reader, removePending]);
  const actualPhase = native.error || phase === 'error' && errorCode ? 'error' : !native.ready ? 'restoring' : hasConnection ? 'authenticated' : phase;
  const value: ProductAuth = {enabled: true, ready: native.ready, phase: actualPhase,
    busy: ['restoring', 'sending-code', 'authenticating', 'connecting', 'signing-out'].includes(actualPhase),
    authenticated: actualPhase === 'authenticated', subject, accountId: hasConnection ? connection.accountId : null,
    accountAccess: hasConnection ? connection : null, apiBase: config.apiBase, email,
    errorCode: native.error ? 'PRODUCT_AUTH_UNAVAILABLE' : errorCode,
    guestDisposition: hasConnection ? connection.guestDisposition : null, lastSuccessfulMethod: lastMethod,
    sendEmailCode, verifyEmailCode, loginWithProvider, freshAccessToken, openExistingAccount, retry, logout, cancel};
  return <ProductAuthContext.Provider value={value}>{children}</ProductAuthContext.Provider>;
}

class AuthBoundary extends Component<{children: ReactNode; fallback: ReactNode}, {failed: boolean}> {
  override state = {failed: false};
  static getDerivedStateFromError() {return {failed: true};}
  override render() {return this.state.failed ? this.props.fallback : this.props.children;}
}
function Configured({children, config, connectAccount, sdk: providedSdk}: {
  children: ReactNode; config: EnabledConfig; connectAccount: ConnectProductAccount; sdk?: ProductAuthSdkPort;
}) {
  const [sdk, setSdk] = useState<ProductAuthSdkPort | null>(providedSdk ?? null), [failed, setFailed] = useState(false);
  useEffect(() => {
    if (providedSdk) return;
    let active = true;
    void loadProductAuthSdk().then(value => {if (active) setSdk(value);}, () => {if (active) setFailed(true);});
    return () => {active = false;};
  }, [providedSdk]);
  if (!sdk || failed) return <ProductAuthContext.Provider value={{...unavailable, enabled: true, ready: failed,
    busy: !failed, phase: failed ? 'error' : 'restoring', apiBase: config.apiBase,
    errorCode: failed ? 'PRODUCT_AUTH_UNAVAILABLE' : null}}>{children}</ProductAuthContext.Provider>;
  return <sdk.PrivyProvider appId={config.appId} {...(config.clientId ? {clientId: config.clientId} : {})} config={{loginMethods: ['email', 'google', 'twitter'],
    embeddedWallets: {ethereum: {createOnLogin: 'off'}, solana: {createOnLogin: 'off'}, disableAutomaticMigration: true}}}>
    <Bridge sdk={sdk} config={config} connectAccount={connectAccount}>{children}</Bridge>
  </sdk.PrivyProvider>;
}
export function ProductAuthProvider({children, apiBase, config: supplied, connectAccount, sdk}: {
  children: ReactNode; apiBase?: string | null; config?: ProductAuthConfig;
  connectAccount: ConnectProductAccount; sdk?: ProductAuthSdkPort;
}) {
  const config = supplied ?? readProductAuthConfig(apiBase);
  if (config.kind !== 'enabled') return <ProductAuthContext.Provider value={{...unavailable,
    errorCode: config.kind === 'invalid' ? 'PRODUCT_AUTH_CONFIGURATION_INVALID' : null}}>{children}</ProductAuthContext.Provider>;
  const fallback = <ProductAuthContext.Provider value={{...unavailable, enabled: true, phase: 'error', apiBase: config.apiBase,
    errorCode: 'PRODUCT_AUTH_UNAVAILABLE'}}>{children}</ProductAuthContext.Provider>;
  return <AuthBoundary key={`${config.appId}:${config.clientId}:${config.apiBase}`} fallback={fallback}>
    <Configured config={config} connectAccount={connectAccount} {...(sdk ? {sdk} : {})}>{children}</Configured>
  </AuthBoundary>;
}
