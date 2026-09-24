import {
  Component, createContext, lazy, Suspense, useCallback, useContext, useEffect, useMemo, useRef, useState,
  type ReactNode,
} from 'react';
import { readPracticeWebConfig, type PracticeWebConfig } from './config.js';
import { IdentityBoundTokenReader, validPrivySubject } from './token-binding.js';
import { loadPrivySdk } from './privy-sdk-loader.js';

export interface PracticeAccountAuth {
  readonly enabled: boolean;
  readonly ready: boolean;
  readonly authenticated: boolean;
  readonly subject: string | null;
  readonly apiOrigin: string | null;
  readonly errorCode: string | null;
  readonly busy: boolean;
  login(): void;
  logout(): Promise<void>;
  freshAccessToken(expectedSubject: string): Promise<string | null>;
}

const guest: PracticeAccountAuth = Object.freeze({
  enabled: false, ready: true, authenticated: false, subject: null, apiOrigin: null,
  errorCode: null, busy: false, login: () => {}, logout: async () => {},
  freshAccessToken: async () => null,
});
export const PracticeAccountAuthContext = createContext<PracticeAccountAuth>(guest);
export function usePracticeAccountAuth(): PracticeAccountAuth { return useContext(PracticeAccountAuthContext); }

type EnabledConfig = Extract<PracticeWebConfig, { kind: 'enabled' }>;

// Disabled builds never even import the SDK. The SDK owns its browser session
// persistence; this bridge never stores a token, provider user or server UUID.
const ConfiguredProvider = lazy(async () => {
  const sdk = await loadPrivySdk();

  function Bridge({ config, children }: { config: EnabledConfig; children: ReactNode }) {
    const native = sdk.usePrivy();
    const [, render] = useState(0);
    const [errorCode, setError] = useState<string | null>(null);
    const mounted = useRef(true);
    const intent = useRef(0);
    const pending = useRef<number | null>(null);
    const logoutPending = useRef(false);
    const awaitingNativeCommit = useRef(false);
    // undefined permits the first restored SDK session. null requires a new,
    // explicit successful login; a different unsolicited DID is never accepted.
    const allowed = useRef<string | null | undefined>(undefined);
    const reader = useMemo(() => new IdentityBoundTokenReader(config.appId), [config.appId]);
    const nativeRef = useRef(native);
    nativeRef.current = native;
    const sdkSubject = native.ready && native.authenticated && validPrivySubject(native.user?.id)
      ? native.user.id : null;
    if (native.ready && allowed.current === undefined) allowed.current = sdkSubject;
    if (allowed.current === sdkSubject && sdkSubject !== null) awaitingNativeCommit.current = false;
    if (native.ready && allowed.current && allowed.current !== sdkSubject &&
        pending.current === null && !awaitingNativeCommit.current) {
      allowed.current = null;
    }
    const subject = allowed.current === sdkSubject ? sdkSubject : null;
    const boundSubject = useRef(subject);
    boundSubject.current = subject;
    reader.observe(subject);

    useEffect(() => {
      mounted.current = true;
      reader.observe(boundSubject.current);
      return () => { mounted.current = false; intent.current++; reader.invalidate(); };
    }, [reader]);

    const { login: openLogin } = sdk.useLogin({
      onComplete: ({ user }) => {
        const attempt = pending.current;
        pending.current = null;
        if (!mounted.current) return;
        if (attempt === null || attempt !== intent.current) {
          render((value) => value + 1);
          return;
        }
        if (!validPrivySubject(user.id)) {
          setError('PRACTICE_SIGN_IN_FAILED');
          render((value) => value + 1);
          return;
        }
        allowed.current = user.id;
        awaitingNativeCommit.current = true;
        setError(null);
        render((value) => value + 1);
      },
      onError: (error) => {
        const attempt = pending.current;
        pending.current = null;
        if (!mounted.current) return;
        if (attempt === null || attempt !== intent.current) {
          render((value) => value + 1);
          return;
        }
        allowed.current = null;
        reader.invalidate();
        setError(error === 'exited_auth_flow' ? null : 'PRACTICE_SIGN_IN_FAILED');
        render((value) => value + 1);
      },
    });

    const login = useCallback(() => {
      if (!nativeRef.current.ready || pending.current !== null || logoutPending.current) return;
      const generation = ++intent.current;
      pending.current = generation;
      awaitingNativeCommit.current = false;
      allowed.current = null;
      reader.invalidate();
      setError(null);
      render((value) => value + 1);
      try { openLogin({ loginMethods: ['twitter'] }); }
      catch {
        if (generation !== intent.current) return;
        pending.current = null;
        setError('PRACTICE_SIGN_IN_FAILED');
      }
    }, [openLogin, reader]);

    const logout = useCallback(async () => {
      if (logoutPending.current) return;
      const generation = ++intent.current;
      allowed.current = null;
      awaitingNativeCommit.current = false;
      reader.invalidate();
      logoutPending.current = true;
      setError(null);
      render((value) => value + 1);
      try { await nativeRef.current.logout(); }
      catch {
        if (mounted.current && generation === intent.current) setError('PRACTICE_SIGN_OUT_FAILED');
      } finally {
        logoutPending.current = false;
        if (mounted.current) render((value) => value + 1);
      }
    }, [reader]);

    const freshAccessToken = useCallback((expectedSubject: string) =>
      reader.read(expectedSubject, () => nativeRef.current.getAccessToken()), [reader]);
    const value: PracticeAccountAuth = {
      enabled: true, ready: native.ready, authenticated: subject !== null, subject,
      apiOrigin: config.apiOrigin,
      errorCode: native.error ? 'PRACTICE_AUTH_UNAVAILABLE' : errorCode,
      busy: pending.current !== null || logoutPending.current,
      login, logout, freshAccessToken,
    };
    return <PracticeAccountAuthContext.Provider value={value}>{children}</PracticeAccountAuthContext.Provider>;
  }

  return {
    default: function SdkProvider({ config, children }: { config: EnabledConfig; children: ReactNode }) {
      return <sdk.PrivyProvider appId={config.appId} clientId={config.clientId} config={{
        loginMethods: ['twitter'],
        embeddedWallets: {
          ethereum: { createOnLogin: 'off' }, solana: { createOnLogin: 'off' },
          disableAutomaticMigration: true,
        },
      }}><Bridge config={config}>{children}</Bridge></sdk.PrivyProvider>;
    },
  };
});

class AccountLoadBoundary extends Component<{ config: EnabledConfig; children: ReactNode; fallback: ReactNode }, { failed: boolean }> {
  override state = { failed: false };
  static getDerivedStateFromError(): { failed: boolean } { return { failed: true }; }
  override render() {
    if (!this.state.failed) return this.props.children;
    return <PracticeAccountAuthContext.Provider value={{ ...guest,
      apiOrigin: this.props.config.apiOrigin, errorCode: 'PRACTICE_AUTH_UNAVAILABLE' }}>
      {this.props.fallback}
    </PracticeAccountAuthContext.Provider>;
  }
}

export function PracticeAccountProvider({ children, config = readPracticeWebConfig() }: {
  children: ReactNode; config?: PracticeWebConfig;
}) {
  if (config.kind !== 'enabled') {
    const value = config.kind === 'invalid'
      ? { ...guest, errorCode: 'PRACTICE_CONFIGURATION_INVALID' } : guest;
    return <PracticeAccountAuthContext.Provider value={value}>{children}</PracticeAccountAuthContext.Provider>;
  }
  const loading = { ...guest, enabled: true, ready: false, apiOrigin: config.apiOrigin };
  return <AccountLoadBoundary key={`${config.appId}:${config.clientId}:${config.apiOrigin}`} config={config} fallback={children}><Suspense fallback={<PracticeAccountAuthContext.Provider value={loading}>{children}</PracticeAccountAuthContext.Provider>}>
    <ConfiguredProvider config={config}>{children}</ConfiguredProvider>
  </Suspense></AccountLoadBoundary>;
}
