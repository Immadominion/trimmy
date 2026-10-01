// The installed Privy React SDK (3.42.0) ships broken transitive declarations,
// so this interop edge stays in JS behind wallet-sdk-loader.d.ts, as for the
// auth and recovery adapters. It reads no key or token and signs only the
// bytes a caller passes. Direct sends also show Privy's wallet confirmation.
const ADDRESS = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;

/** Only Privy embedded Solana wallets; external or Ethereum wallets never count. */
export function embeddedSolanaWallets(user) {
  if (!user || typeof user !== 'object' || !Array.isArray(user.linkedAccounts) || user.linkedAccounts.length > 100) return null;
  const wallets = [];
  for (const account of user.linkedAccounts) {
    if (!account || typeof account !== 'object' || account.type !== 'wallet' ||
        account.walletClientType !== 'privy' || account.chainType !== 'solana') continue;
    if (typeof account.address !== 'string' || !ADDRESS.test(account.address)) return null;
    if (!wallets.some(wallet => wallet.address === account.address)) wallets.push({address: account.address});
  }
  return wallets;
}

function unavailable() {throw new Error('PRODUCT_WALLET_SDK_UNAVAILABLE');}

export function createProductWalletSdk(sdk, solana) {
  if (typeof sdk?.usePrivy !== 'function' || typeof sdk?.useUser !== 'function' || typeof solana?.useWallets !== 'function' ||
      typeof solana?.useCreateWallet !== 'function' || typeof solana?.useSignTransaction !== 'function') unavailable();
  return {
    useEmbeddedSolana() {
      const privy = sdk.usePrivy(), account = sdk.useUser(), connected = solana.useWallets();
      const creator = solana.useCreateWallet(), signer = solana.useSignTransaction();
      if (!privy || typeof privy.ready !== 'boolean' || typeof account?.refreshUser !== 'function' ||
          !Array.isArray(connected?.wallets) || typeof creator?.createWallet !== 'function' ||
          typeof signer?.signTransaction !== 'function') unavailable();
      const subject = privy.ready && privy.authenticated && typeof privy.user?.id === 'string' ? privy.user.id : null;
      const embedded = connected.wallets.filter(wallet => wallet?.standardWallet?.isPrivyWallet === true &&
        typeof wallet.address === 'string' && ADDRESS.test(wallet.address));
      return {
        // Setup needs only Privy's session; signing also needs the wallet connected (see signable).
        ready: privy.ready,
        subject,
        wallets: subject ? embeddedSolanaWallets(privy.user) : [],
        signable: connected.ready === true ? embedded.map(wallet => wallet.address) : [],
        async refreshUser() {
          const user = await account.refreshUser();
          return {subject: typeof user?.id === 'string' ? user.id : null, wallets: embeddedSolanaWallets(user)};
        },
        async createWallet() {
          const result = await creator.createWallet();
          const address = result?.wallet?.address;
          if (typeof address !== 'string' || !ADDRESS.test(address)) throw new Error('PRODUCT_WALLET_CREATE_INVALID');
          return address;
        },
        async signTransaction(address, transaction, options) {
          const wallet = embedded.find(candidate => candidate.address === address);
          if (!wallet || !(transaction instanceof Uint8Array)) throw new Error('PRODUCT_WALLET_UNAVAILABLE');
          const result = await signer.signTransaction({transaction, wallet, chain: 'solana:mainnet',
            options: {uiOptions: {showWalletUIs: options?.confirm === true}}});
          if (!(result?.signedTransaction instanceof Uint8Array)) throw new Error('PRODUCT_WALLET_SIGNATURE_INVALID');
          return result.signedTransaction;
        },
      };
    },
  };
}

export async function loadProductWalletSdk() {
  const [sdk, solana] = await Promise.all([import('@privy-io/react-auth'), import('@privy-io/react-auth/solana')]);
  return createProductWalletSdk(sdk, solana);
}
