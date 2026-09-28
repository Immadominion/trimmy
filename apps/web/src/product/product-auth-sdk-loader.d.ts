import type {ComponentType, ReactNode} from 'react';

export interface ProductAuthSdkCallbacks {
  onComplete(result: {user: {id: string}; loginMethod: 'email' | 'google' | 'twitter' | null}): void;
  onError(code: string): void;
}
/** Narrow, runtime-checked boundary around the installed Privy browser SDK. */
export interface ProductAuthSdkPort {
  PrivyProvider: ComponentType<{
    appId: string; clientId?: string; children: ReactNode;
    config: {
      loginMethods: ['email', 'google', 'twitter'];
      embeddedWallets: {ethereum: {createOnLogin: 'off'}; solana: {createOnLogin: 'off'}; disableAutomaticMigration: true};
    };
  }>;
  usePrivy(): {
    ready: boolean; authenticated: boolean; error: boolean;
    /** Display-only: the sign-in methods linked to this user, never stored. */
    user: {id: string; logins?: readonly {method: 'email' | 'google' | 'x'; label: string}[]} | null;
    getAccessToken(): Promise<string | null>; logout(): Promise<void>;
  };
  useLoginWithEmail(callbacks: ProductAuthSdkCallbacks): {
    sendCode(options: {email: string}): Promise<void>;
    loginWithCode(options: {code: string}): Promise<void>;
  };
  useLoginWithOAuth(callbacks: ProductAuthSdkCallbacks): {
    initOAuth(options: {provider: 'google' | 'twitter'}): Promise<void>;
    status: 'initial' | 'loading' | 'done' | 'error';
  };
}
export function loadProductAuthSdk(): Promise<ProductAuthSdkPort>;
