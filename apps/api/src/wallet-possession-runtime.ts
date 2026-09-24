import type {FastifyRequest} from 'fastify';
import type {PracticeRuntime} from './practice-runtime.js';
import {InMemoryWalletPossessionChallengeStore, WalletPossessionError, WalletPossessionService} from './wallet-possession.js';
import type {WalletPossessionAdapters, WalletPossessionIdentityResolver} from './wallet-possession-route.js';

/**
 * `single_process` keeps challenges in this process's memory, which is correct
 * for one instance and wrong for more than one: a proof that reaches a second
 * instance cannot find a challenge it never issued. `shared_storage` keeps them
 * in PostgreSQL, where consuming one is atomic, so any instance can verify a
 * proof another instance issued.
 */
export type WalletPossessionMode = 'single_process' | 'shared_storage';

export interface WalletPossessionRuntimeConfig {
  readonly mode: WalletPossessionMode;
  readonly appId: string;
  readonly network: 'mainnet-beta';
}

const MODES: readonly WalletPossessionMode[] = ['single_process', 'shared_storage'];

const invalid = (): never => { throw new WalletPossessionError('WALLET_POSSESSION_CONFIGURATION_INVALID'); };

/** Explicit opt-in either way, because the two modes have different operational
 * limits. Network and Privy application may not be supplied by a caller. */
export function readWalletPossessionRuntimeConfig(
  env: Readonly<Record<string, string | undefined>>,
): WalletPossessionRuntimeConfig | null {
  const mode = env['TRIMMY_WALLET_POSSESSION'];
  const network = env['TRIMMY_WALLET_NETWORK'];
  if (mode === undefined || mode === '' || mode === 'disabled') {
    if (network !== undefined && network !== '') return invalid();
    return null;
  }
  const appId = env['PRIVY_APP_ID'];
  if (!MODES.includes(mode as WalletPossessionMode) || network !== 'mainnet-beta' ||
      !appId || !/^[a-zA-Z0-9_-]{1,128}$/.test(appId) ||
      !env['PRIVY_APP_SECRET'] || !env['PRIVY_VERIFICATION_KEY'] || !env['PRACTICE_DATABASE_URL']) {
    return invalid();
  }
  return Object.freeze({mode: mode as WalletPossessionMode, appId, network});
}

export function createWalletPossessionRuntime(
  config: WalletPossessionRuntimeConfig | null,
  practice: Pick<PracticeRuntime, 'appId' | 'authenticateContext' | 'walletBindings' | 'walletChallenges'>,
  linkedIdentities: WalletPossessionIdentityResolver | undefined,
): WalletPossessionAdapters | undefined {
  if (!config) return undefined;
  if (!MODES.includes(config.mode) || config.network !== 'mainnet-beta' ||
      practice.appId !== config.appId || !config.appId ||
      typeof practice.authenticateContext !== 'function' ||
      typeof practice.walletBindings?.record !== 'function' ||
      typeof linkedIdentities?.resolve !== 'function' ||
      typeof linkedIdentities.resolveFresh !== 'function') return invalid();
  // Shared storage is only shared if a durable store was actually supplied.
  // Falling back to memory here would silently restore the single-instance
  // limitation under a configuration that promises otherwise.
  if (config.mode === 'shared_storage' && typeof practice.walletChallenges?.take !== 'function') return invalid();
  const authenticate = practice.authenticateContext;
  const resolver = linkedIdentities;
  return Object.freeze({
    network: config.network,
    authenticate: async (request: FastifyRequest) => {
      const account = await authenticate(request);
      // The production verifier and resolver use this same application ID.
      // Recheck the boundary here so a miscomposed adapter cannot cross apps.
      return account?.identity.provider === 'privy' && account.identity.appId === config.appId ? account : null;
    },
    linkedIdentities: resolver,
    service: new WalletPossessionService({
      challenges: config.mode === 'shared_storage' && practice.walletChallenges
        ? practice.walletChallenges
        : new InMemoryWalletPossessionChallengeStore(),
      bindings: practice.walletBindings,
    }),
  });
}
