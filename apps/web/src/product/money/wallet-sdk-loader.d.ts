/** A Privy embedded Solana wallet linked to the signed-in user. */
export interface EmbeddedSolanaWalletRef {readonly address: string}

/**
 * The latest render's view of the Privy embedded Solana wallet. Asynchronous
 * flows read a fresh snapshot after every await; nothing here exposes a key,
 * an access token or an arbitrary signing method.
 */
export interface EmbeddedSolanaSnapshot {
  readonly ready: boolean;
  /** The authenticated Privy user id, or null. */
  readonly subject: string | null;
  /** Embedded (walletClientType `privy`) Solana wallets on the user, or null when the user object is malformed. */
  readonly wallets: readonly EmbeddedSolanaWalletRef[] | null;
  /** Embedded wallets the SDK can sign with right now. */
  readonly signable: readonly string[];
  /** Re-reads the user from Privy; a previous create may have succeeded without its reply. */
  refreshUser(): Promise<{readonly subject: string | null; readonly wallets: readonly EmbeddedSolanaWalletRef[] | null}>;
  /** Creates the one embedded Solana wallet. Fails if the user already has one. */
  createWallet(): Promise<string>;
  /** Signs exactly these transaction bytes with the named embedded wallet, without Privy's own modal. */
  signTransaction(address: string, transaction: Uint8Array): Promise<Uint8Array>;
}
export interface ProductWalletSdkPort {useEmbeddedSolana(): EmbeddedSolanaSnapshot}

export function embeddedSolanaWallets(user: unknown): EmbeddedSolanaWalletRef[] | null;
export function createProductWalletSdk(sdk: unknown, solana: unknown): ProductWalletSdkPort;
export function loadProductWalletSdk(): Promise<ProductWalletSdkPort>;
