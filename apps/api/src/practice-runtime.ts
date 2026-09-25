import {PostgresLiveOrderStore} from './live-stock-orders.js';
import {PostgresLiveTradeHistory} from './live-trade-history.js';
import {postgresDailyDesk} from './daily-desk-routes.js';
import {postgresWorkdays} from './workday-routes.js';
import {postgresCommunity} from './community-routes.js';
import { X509Certificate, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { Pool } from 'pg';
import type { PoolConfig } from 'pg';
import type { ApiOptions } from './app.js';
import { PostgresPracticeRepository } from './postgres-practice-repository.js';
import { PostgresPracticeAccounts } from './postgres-practice-accounts.js';
import { PrivyPracticeIdentityVerifier } from './privy-practice-auth.js';
import { createPracticeAccountContextAuthenticator, createPracticeAuthenticator } from './practice-session-routes.js';
import { PRACTICE_ASSET_IDS } from '@trimmy/domain';
import { PostgresWatchlistRepository } from './postgres-watchlist-repository.js';
import { FOLLOWING_ROUTE } from './watchlist-routes.js';
import type { WatchlistCatalog } from './watchlist-repository.js';
import { PostgresInvitationsRepository } from './postgres-invitations-repository.js';
import { PostgresAccountClosure } from './account-closure.js';
import { parseBrowserOrigins } from './browser-origins.js';
import { PostgresWalletBindingStore } from './postgres-wallet-bindings.js';
import { PostgresReadinessProbe } from './postgres-readiness.js';
import { PostgresWalletPossessionChallengeStore } from './postgres-wallet-challenges.js';
import type { WalletBindingStore, WalletPossessionChallengeStore } from './wallet-possession.js';
import { PostgresPaperTradingRepository } from './postgres-paper-trading-repository.js';
import { PostgresGuestSessionRepository } from './postgres-guest-session-repository.js';
import { PostgresProductProfileRepository } from './postgres-product-profile-repository.js';
import { createProductProfileAuthenticator } from './product-profile-routes.js';
import { PostgresCareerRepository } from './postgres-career-repository.js';
import { createCareerAuthenticator } from './career-routes.js';
import {PostgresCareerReasonSharingRepository} from './postgres-career-reason-sharing-repository.js';
import {createCareerReasonSharingAuthenticator} from './career-reason-sharing-routes.js';
import {createGuestCreationSource, readGuestCreationSourceConfig} from './guest-creation-source.js';
import type {GuestCreationSourceConfig} from './guest-creation-source.js';
import {readRelationshipModerationRole} from './relationship-safety-config.js';
import {PostgresSocialRelationshipsRepository} from './postgres-social-relationships-repository.js';
import {PostgresRelationshipSafetyReadiness} from './postgres-relationship-safety-readiness.js';
import type {RelationshipSafetyReadiness} from './relationship-safety-config.js';

export interface PracticeRuntimeConfig {
  readonly appId: string;
  readonly verificationKey: string;
  readonly database: PoolConfig;
  readonly browserOrigins: readonly string[];
  readonly guestSource: GuestCreationSourceConfig;
  readonly relationshipModerationRole: string;
}

function invalid(): never { throw new Error('Practice configuration is incomplete or invalid.'); }

/**
 * Shape-validated identifiers, never a verified issuer catalog. The fictional
 * sample slugs are reserved so they can never be stored in the real list and
 * later read back as a real asset.
 */
const PROVIDER_ASSET_CATALOG: WatchlistCatalog = Object.freeze({
  kind: 'provider', reservedAssetIds: new Set(PRACTICE_ASSET_IDS),
});

/** Every PEM block in a pinned bundle must parse as a certificate. */
function parseCertificateBundle(text: string): string {
  if (Buffer.byteLength(text, 'utf8') > 65_536) invalid();
  const blocks = text.match(/-----BEGIN CERTIFICATE-----[^-]+-----END CERTIFICATE-----/g);
  if (!blocks || blocks.length > 16) invalid();
  try { for (const block of blocks) new X509Certificate(block); } catch { return invalid(); }
  return text;
}

/** A pinned certificate bundle for database TLS verification, read from a file. */
function readCertificateBundle(path: string): string {
  if (path.length > 4096 || path.trim() !== path || /[\x00-\x1f\x7f]/.test(path)) invalid();
  let text: string;
  try { text = readFileSync(path, {encoding: 'utf8', flag: 'r'}); } catch { return invalid(); }
  return parseCertificateBundle(text);
}

/** Explicit configuration only; an empty environment preserves offline practice. */
export function readPracticeRuntimeConfig(env: Readonly<Record<string, string | undefined>>): PracticeRuntimeConfig | null {
  const values = [env['PRIVY_APP_ID'], env['PRIVY_VERIFICATION_KEY'], env['PRACTICE_DATABASE_URL']];
  const rawOrigins = env['TRIMMY_WEB_ORIGINS'];
  const rawCaFile = env['PRACTICE_DATABASE_CA_FILE'];
  // Hosted platforms commonly offer environment variables and no writable file,
  // and a managed database often presents a private certificate authority. The
  // inline form carries the same bundle, validated identically.
  const rawCaInline = env['PRACTICE_DATABASE_CA'];
  const guestValues = [env['TRIMMY_GUEST_SOURCE_MODE'], env['TRIMMY_GUEST_SOURCE_HMAC_KEY'],
    env['TRIMMY_GUEST_TRUSTED_PROXY_CIDRS']];
  const rawModerationRole = env['TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE'];
  if (values.every(value => value === undefined || value === '') && !rawOrigins && !rawCaFile && !rawCaInline &&
      !rawModerationRole && guestValues.every(value => value === undefined || value === '')) return null;
  // Two sources would leave which one is trusted ambiguous.
  if (rawCaFile && rawCaInline) invalid();
  if (values.some(value => !value)) invalid();
  const [appId, rawKey, rawDatabase] = values as [string, string, string];
  if (appId.length > 128 || !/^[a-zA-Z0-9_-]+$/.test(appId) || rawKey.length > 8192 ||
      rawDatabase.length > 4096 || rawDatabase.trim() !== rawDatabase) invalid();
  try {
    if (rawOrigins && rawOrigins.length > 8192) invalid();
    const browserOrigins = parseBrowserOrigins(rawOrigins ? JSON.parse(rawOrigins) : []);
    const guestSource = readGuestCreationSourceConfig(env);
    const relationshipModerationRole = readRelationshipModerationRole(env);
    if (!guestSource) invalid();
    const ca = rawCaFile
      ? readCertificateBundle(rawCaFile)
      : rawCaInline ? parseCertificateBundle(rawCaInline.replace(/\\n/g, '\n')) : undefined;
    const url = new URL(rawDatabase);
    if (!['postgres:', 'postgresql:'].includes(url.protocol) || !url.hostname || url.search || url.hash) invalid();
    const database = decodeURIComponent(url.pathname.slice(1));
    const user = decodeURIComponent(url.username);
    const password = decodeURIComponent(url.password);
    const port = url.port ? Number(url.port) : 5432;
    if (!/^[a-zA-Z0-9_.-]{1,63}$/.test(database) || !/^[a-zA-Z0-9_.@-]{1,128}$/.test(user) ||
        !password || password.length > 512 || /[\x00-\x1f\x7f]/.test(password) ||
        !Number.isInteger(port) || port < 1 || port > 65535) invalid();
    return Object.freeze({
      appId,
      browserOrigins,
      guestSource,
      relationshipModerationRole,
      verificationKey: rawKey.replace(/\\n/g, '\n').trim(),
      database: Object.freeze({
        host: url.hostname.replace(/^\[|\]$/g, ''), port, database, user, password,
        // Passing parsed connection fields prevents URL sslmode options from
        // replacing certificate verification configured here. An optional pinned
        // bundle replaces the process trust store for this pool only.
        ssl: Object.freeze(ca === undefined ? {rejectUnauthorized: true} : {rejectUnauthorized: true, ca}),
        max: 5, connectionTimeoutMillis: 5000, idleTimeoutMillis: 30_000,
        statement_timeout: 8000, query_timeout: 9000,
        application_name: 'trimmy-practice-api',
      }),
    });
  } catch { return invalid(); }
}

export interface PracticeRuntime {
  readonly appId?: string;
  readonly options: Pick<ApiOptions, 'practice' | 'practiceSessions' | 'guestSessions' | 'productProfile' | 'watchlist' |
    'workdays' | 'dailyDesk' | 'community' | 'career' | 'careerReasonSharing' | 'socialRelationships' | 'invitations' | 'accountClosure' |
    'browserOrigins' | 'readiness' | 'following' | 'liveTradeHistory'>;
  readonly authenticate?: ReturnType<typeof createPracticeAuthenticator>;
  readonly authenticateContext?: ReturnType<typeof createPracticeAccountContextAuthenticator>;
  readonly invitationsRepository?: PostgresInvitationsRepository;
  readonly accountClosureRepository?: PostgresAccountClosure;
  readonly socialRelationshipsRepository?: PostgresSocialRelationshipsRepository;
  readonly relationshipSafetyReadiness?: RelationshipSafetyReadiness;
  readonly walletBindings?: WalletBindingStore;
  /** Durable challenges, so a proof can be verified by any instance. */
  readonly walletChallenges?: WalletPossessionChallengeStore;
  /** Storage only. Routes add the separately configured live read adapter. */
  readonly paperTradingRepository?: PostgresPaperTradingRepository;
  readonly guestSessionRepository?: PostgresGuestSessionRepository;
  readonly liveOrderStore?: PostgresLiveOrderStore;
  readonly close: () => Promise<void>;
}

export function createPracticeRuntime(config: PracticeRuntimeConfig | null): PracticeRuntime {
  if (!config) return {options: {}, close: async () => {}};
  // Validate the public verification key before creating a pool.
  const verifier = new PrivyPracticeIdentityVerifier({appId: config.appId, verificationKey: config.verificationKey});
  const pool = new Pool(config.database);
  pool.on('error', () => { process.stderr.write('Practice database connection failed.\n'); });
  const accounts = new PostgresPracticeAccounts(pool);
  const sessions = {verifier, accounts};
  const authenticate = createPracticeAuthenticator(sessions);
  const authenticateContext = createPracticeAccountContextAuthenticator(sessions);
  const invitationsRepository = new PostgresInvitationsRepository(pool, undefined,
    config.relationshipModerationRole);
  const accountClosureRepository = new PostgresAccountClosure(pool,
    config.relationshipModerationRole);
  const socialRelationshipsRepository = new PostgresSocialRelationshipsRepository(
    pool, config.relationshipModerationRole,
  );
  const relationshipReadiness = new PostgresRelationshipSafetyReadiness(
    pool, config.relationshipModerationRole,
  );
  const guestSessionRepository = new PostgresGuestSessionRepository(pool);
  const guestSource = createGuestCreationSource(config.guestSource);
  const allowedAssetIds = new Set(PRACTICE_ASSET_IDS);
  return {
    appId: config.appId,
    authenticate,
    authenticateContext,
    invitationsRepository,
    accountClosureRepository,
    socialRelationshipsRepository,
    relationshipSafetyReadiness: () => relationshipReadiness.ready(),
    walletBindings: new PostgresWalletBindingStore(pool),
    walletChallenges: new PostgresWalletPossessionChallengeStore(pool),
    paperTradingRepository: new PostgresPaperTradingRepository(pool),
    guestSessionRepository,
    liveOrderStore: new PostgresLiveOrderStore(pool),
    options: {
      liveTradeHistory: {authenticate, repository: new PostgresLiveTradeHistory(pool)},
      browserOrigins: config.browserOrigins,
      practiceSessions: sessions,
      guestSessions: {repository: guestSessionRepository, verifier, source: guestSource},
      productProfile: {
        repository: new PostgresProductProfileRepository(pool),
        authenticate: createProductProfileAuthenticator(authenticate, guestSessionRepository),
      },
      career: {
        repository: new PostgresCareerRepository(pool),
        authenticate: createCareerAuthenticator(authenticate, guestSessionRepository),
      },
      careerReasonSharing: {
        repository: new PostgresCareerReasonSharingRepository(pool,
          config.relationshipModerationRole),
        authenticate: createCareerReasonSharingAuthenticator(authenticate, guestSessionRepository),
      },
      socialRelationships: {repository: socialRelationshipsRepository, authenticate},
      community: {authenticate, ...postgresCommunity(pool)},
      dailyDesk: {authenticate: createCareerAuthenticator(authenticate, guestSessionRepository), ...postgresDailyDesk(pool)},
      workdays: {authenticate: createCareerAuthenticator(authenticate, guestSessionRepository), ...postgresWorkdays(pool)},
      practice: {repository: new PostgresPracticeRepository(pool), authenticate},
      watchlist: {repository: new PostgresWatchlistRepository(pool, {allowedAssetIds}), authenticate, allowedAssetIds},
      // The real list accepts any discovery-shaped identifier. That is not an
      // approval: no route reads this list as evidence an asset is tradeable.
      following: {
        repository: new PostgresWatchlistRepository(pool, {
          allowedAssetIds: PROVIDER_ASSET_CATALOG, tables: 'followed_stocks',
        }),
        authenticate, allowedAssetIds: PROVIDER_ASSET_CATALOG, route: FOLLOWING_ROUTE,
      },
      invitations: {repository: invitationsRepository, authenticate, newId: () => randomUUID()},
      accountClosure: {repository: accountClosureRepository, authenticate},
      // Readiness checks this pool only. Providers stay out of it by design.
      readiness: new PostgresReadinessProbe(pool),
    },
    close: () => pool.end(),
  };
}
