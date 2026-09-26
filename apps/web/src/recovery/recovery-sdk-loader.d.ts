import type {ComponentType, ReactNode} from 'react';
import type {RecoveryIdentity} from './recovery-model.js';
export interface RecoverySession {
  ready: boolean; authenticated: boolean; identity: RecoveryIdentity | null; failed: boolean;
  login(): void; logout(): Promise<void>;
}
export interface RecoverySdk {
  PrivyProvider: ComponentType<{
    appId: string; clientId?: string; children: ReactNode;
    config: {
      loginMethods: ['email', 'google', 'twitter', 'apple'];
      appearance: {theme: 'light'; accentColor: '#7745D8'; logo: string; landingHeader: string; loginMessage: string};
      embeddedWallets: {ethereum: {createOnLogin: 'off'}; solana: {createOnLogin: 'off'}; disableAutomaticMigration: true};
    };
  }>;
  useSession(): RecoverySession;
  useExportWallet(): {exportWallet(address: string): Promise<void>};
}
export function createRecoverySdk(sdk: unknown, solana: unknown): RecoverySdk;
export function loadRecoverySdk(): Promise<RecoverySdk>;
