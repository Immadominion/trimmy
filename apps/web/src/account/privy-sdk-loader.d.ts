import type { ComponentType, ReactNode } from 'react';

/** The runtime-checked subset consumed by the authentication bridge. */
export interface PrivySdkPort {
  PrivyProvider: ComponentType<{
    appId: string;
    clientId: string;
    config: {
      loginMethods: ['twitter'];
      embeddedWallets: {
        ethereum: { createOnLogin: 'off' };
        solana: { createOnLogin: 'off' };
        disableAutomaticMigration: true;
      };
    };
    children: ReactNode;
  }>;
  usePrivy(): {
    ready: boolean;
    authenticated: boolean;
    user: { id: string } | null;
    error: boolean;
    getAccessToken(): Promise<string | null>;
    logout(): Promise<void>;
  };
  useLogin(callbacks: {
    onComplete(result: { user: { id: string } }): void;
    onError(code: string): void;
  }): { login(options: { loginMethods: ['twitter'] }): void };
}
export function loadPrivySdk(): Promise<PrivySdkPort>;
