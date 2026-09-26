// Keep the installed SDK's broken transitive declarations outside TypeScript,
// as for the existing account adapters. This boundary never reads an access
// token or a private key, and discards the export method's return value.
import {recoveryIdentity} from './recovery-model.js';

export function createRecoverySdk(sdk, solana) {
  if (typeof sdk?.PrivyProvider !== 'function' || typeof sdk?.usePrivy !== 'function' ||
      typeof solana?.useExportWallet !== 'function') throw new Error('RECOVERY_UNAVAILABLE');
  return {
    PrivyProvider: sdk.PrivyProvider,
    useSession() {
      const value = sdk.usePrivy();
      if (!value || typeof value.ready !== 'boolean' || typeof value.authenticated !== 'boolean' ||
          typeof value.login !== 'function' || typeof value.logout !== 'function') throw new Error('RECOVERY_UNAVAILABLE');
      return {
        ready: value.ready,
        authenticated: value.authenticated,
        identity: value.ready && value.authenticated ? recoveryIdentity(value.user) : null,
        failed: Boolean(value.error),
        login() {value.login({disableSignup: true});},
        async logout() {await value.logout();},
      };
    },
    useExportWallet() {
      const value = solana.useExportWallet();
      if (typeof value?.exportWallet !== 'function') throw new Error('RECOVERY_UNAVAILABLE');
      return {async exportWallet(address) {await value.exportWallet({address});}};
    },
  };
}

export async function loadRecoverySdk() {
  const [sdk, solana] = await Promise.all([import('@privy-io/react-auth'), import('@privy-io/react-auth/solana')]);
  return createRecoverySdk(sdk, solana);
}
