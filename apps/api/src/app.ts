import {liveStockExecutionEnabled,registerLiveStockRoutes} from './live-stock-orders.js';
import {registerOnrampRoutes, type OnrampAdapters} from './crossmint-onramp.js';
import type {LiveStockAdapters} from './live-stock-orders.js';
import {registerDailyDeskRoutes, type DailyDeskAdapters} from './daily-desk-routes.js';
import {registerWorkdayRoutes, type WorkdayAdapters} from './workday-routes.js';
import {registerCommunityRoutes, type CommunityAdapters} from './community-routes.js';
import {registerPublicHolders, type PublicTokenHolders} from './public-token-holders.js';
import { randomUUID } from 'node:crypto';
import Fastify, { LogController } from 'fastify';
import type { FastifyError, FastifyInstance, FastifyRequest, FastifyServerFactory } from 'fastify';
import { FOUNDATION_CAPABILITIES } from '@trimmy/domain';
import { PRACTICE_PROGRESS_ROUTE, practiceSyncEnabled, registerPracticeRoutes } from './practice-routes.js';
import type { PracticeSyncAdapters } from './practice-routes.js';
import { PRACTICE_SESSION_ROUTE, practiceAccountsEnabled, registerPracticeSessionRoute } from './practice-session-routes.js';
import type { PracticeSessionAdapters } from './practice-session-routes.js';
import { FOLLOWING_ROUTE, WATCHLIST_ROUTE, registerWatchlistRoutes, watchlistEnabled } from './watchlist-routes.js';
import type { WatchlistAdapters } from './watchlist-routes.js';
import {
  INVITATIONS_ROUTE, INVITATION_ACTION_ROUTE, registerInvitationRoutes, invitationsEnabled,
} from './invitation-routes.js';
import type { InvitationAdapters } from './invitation-routes.js';
import { ACCOUNT_CLOSURE_ROUTE, registerAccountClosureRoute, accountClosureEnabled } from './account-closure-route.js';
import type { AccountClosureAdapters } from './account-closure-route.js';
import { registerBrowserOrigins } from './browser-origins.js';
import { registerPracticeCatalogRoute } from './practice-catalog-route.js';
import { registerMarketEstimateRoute } from './market-estimate-route.js';
import type { MarketEstimates } from './market-estimates.js';
import { registerStockDiscoveryRoutes } from './stock-discovery-routes.js';
import { registerStockFactsRoutes } from './stock-facts-routes.js';
import type { StockFactsReader } from './stock-facts.js';
import { ReadinessReporter } from './readiness.js';
import type { ReadinessProbe } from './readiness.js';
import type { StockDiscovery } from './stock-discovery.js';
import { registerStockEstimateRoute } from './stock-estimate-route.js';
import type { StockEstimates } from './stock-estimates.js';
import { registerSocialXRoutes, socialXEnabled } from './x-profile-routes.js';
import type { SocialXAdapters } from './x-profile-routes.js';
import { accountContextEnabled, registerAccountContextRoute } from './account-context-route.js';
import type { AccountContextAdapters } from './account-context-route.js';
import { accountHoldingsEnabled, registerAccountHoldingsRoute } from './account-holdings-route.js';
import type { AccountHoldingsAdapters } from './account-holdings-route.js';
import { WALLET_CHALLENGE_ROUTE, WALLET_POSSESSION_ROUTE, registerWalletPossessionRoutes, walletPossessionEnabled } from './wallet-possession-route.js';
import type { WalletPossessionAdapters } from './wallet-possession-route.js';
import { registerStockHistoryRoute } from './stock-history-route.js';
import type { StockHistory } from './stock-history.js';
import { registerRaydiumStockQuoteRoute } from './raydium-stock-quote-route.js';
import type { RaydiumStockQuotes } from './raydium-stock-quotes.js';
import { registerPreStocksRoute } from './prestocks-route.js';
import type { PreStocks } from './prestocks-reader.js';
import {
  PAPER_COMMIT_ROUTE, PAPER_PREVIEW_ROUTE, PAPER_RESET_ROUTE, paperTradingEnabled, registerPaperTradingRoutes,
} from './paper-trading-routes.js';
import type { PaperTradingAdapters } from './paper-trading-routes.js';
import {
  GUEST_CLAIM_ROUTE, GUEST_REFRESH_ROUTE, GUEST_SESSION_ROUTE, guestSessionsEnabled, registerGuestSessionRoutes,
} from './guest-session-routes.js';
import type { GuestSessionAdapters } from './guest-session-routes.js';
import {
  PRODUCT_LAUNCH_ROUTE, PRODUCT_PROFILE_ROUTE, productProfileEnabled, registerProductProfileRoutes,
} from './product-profile-routes.js';
import type { ProductProfileAdapters } from './product-profile-routes.js';
import {
  CAREER_DAY_CONTEXT_ROUTE, CAREER_PROMOTION_ROUTE, CAREER_REASON_ROUTE,
  careerEnabled, registerCareerRoutes,
} from './career-routes.js';
import type { CareerAdapters } from './career-routes.js';
import {
  CAREER_REASON_PRIVACY_ROUTE,
  careerReasonSharingEnabled,
  registerCareerReasonSharingRoutes,
} from './career-reason-sharing-routes.js';
import type { CareerReasonSharingAdapters } from './career-reason-sharing-routes.js';
import {
  SOCIAL_BLOCK_ROUTE, SOCIAL_FRIEND_ACTION_ROUTE, SOCIAL_REASON_REPORTS_ROUTE,
  registerSocialRelationshipRoutes,
} from './social-relationship-routes.js';
import type {SocialRelationshipAdapters} from './social-relationship-routes.js';
import {relationshipSafetyAvailable} from './relationship-safety-config.js';
import type {RelationshipSafetyReadiness} from './relationship-safety-config.js';

export interface ApiOptions {
  readonly onramp?: OnrampAdapters;
  readonly logger?: boolean;
  readonly logLevel?: 'debug' | 'info' | 'warn' | 'error' | 'fatal' | 'silent';
  readonly practice?: PracticeSyncAdapters;
  readonly practiceSessions?: PracticeSessionAdapters;
  readonly watchlist?: WatchlistAdapters;
  /** The real list of looked-up assets, stored separately from the sample one. */
  readonly following?: WatchlistAdapters;
  readonly invitations?: InvitationAdapters;
  readonly accountClosure?: AccountClosureAdapters;
  readonly browserOrigins?: readonly string[];
  readonly marketEstimates?: MarketEstimates;
  readonly stockDiscovery?: StockDiscovery;
  readonly stockFacts?: StockFactsReader;
  readonly publicHolders?: PublicTokenHolders;
  readonly stockEstimates?: StockEstimates;
  readonly socialX?: SocialXAdapters;
  readonly accountContext?: AccountContextAdapters;
  readonly accountHoldings?: AccountHoldingsAdapters;
  readonly walletPossession?: WalletPossessionAdapters;
  readonly stockHistory?: StockHistory;
  readonly raydiumStockQuotes?: RaydiumStockQuotes;
  readonly preStocks?: PreStocks;
  /** Simulated paper ledger only. It has no wallet or execution adapter. */
  readonly paperTrading?: PaperTradingAdapters;
  /** Anonymous credentials can reach the simulated paper ledger, product profile and Career only. */
  readonly guestSessions?: GuestSessionAdapters;
  /** Server-owned onboarding choices and ordered first-use checkpoint. */
  readonly productProfile?: ProductProfileAdapters;
  /** Server-owned progress and notes earned through paper learning actions. */
  readonly career?: CareerAdapters;
  /** Server-owned reason reads and explicit reason visibility. */
  readonly careerReasonSharing?: CareerReasonSharingAdapters;
  /** Function-backed friend, block and report safety controls. */
  readonly socialRelationships?: SocialRelationshipAdapters;
  readonly community?: CommunityAdapters;
  readonly dailyDesk?: DailyDeskAdapters;
  readonly workdays?: WorkdayAdapters;
  readonly liveStocks?: LiveStockAdapters;
  /** Explicit social activation gate. Absence is always disabled. */
  readonly relationshipSafetyEnabled?: boolean;
  /** Live migration, grant and moderation readiness proof. */
  readonly relationshipSafetyReadiness?: RelationshipSafetyReadiness;
  /** This instance's own storage check, used by GET /ready. Never a provider. */
  readonly readiness?: ReadinessProbe;
  /** Optional raw-server factory, used for the native TLS listener. */
  readonly serverFactory?: FastifyServerFactory;
}

const noQuery = { type: 'object', additionalProperties: false, properties: {} } as const;
const safeError = (code: string, message: string, requestId: string) => ({ error: { code, message, requestId } });

/** Factory supports in-process request tests without starting a socket or contacting providers. */
export function buildApp(options: ApiOptions = {}): FastifyInstance {
  const app = Fastify({
    logger: options.logger === false ? false : {
      level: options.logLevel ?? 'info',
      redact: {
        paths: ['req.headers.authorization', 'req.headers["x-trimmy-guest"]', 'req.headers.cookie', 'req.headers["x-api-key"]',
          'req.body.replaySecret', 'res.headers["set-cookie"]', '*.token', '*.secret', '*.privateKey', '*.replaySecret'],
        censor: '[REDACTED]',
      },
      // URL/query strings can contain claim tokens. Log the matched route only.
      serializers: {
        req: (request: FastifyRequest) => ({method: request.method, url: request.routeOptions.url ?? 'unmatched'}),
      },
    },
    bodyLimit: 16_384,
    requestTimeout: 10_000,
    connectionTimeout: 10_000,
    keepAliveTimeout: 5_000,
    trustProxy: false,
    logController: new LogController({ disableRequestLogging: true }),
    requestIdHeader: false,
    genReqId: () => randomUUID(),
    ajv: { customOptions: { removeAdditional: false, coerceTypes: false, useDefaults: false } },
    ...(options.serverFactory ? {serverFactory: options.serverFactory} : {}),
  });

  app.addHook('onRequest', async (request, reply) => {
    reply.header('x-request-id', request.id);
    reply.header('x-content-type-options', 'nosniff');
    reply.header('cache-control', 'no-store');
    reply.header('referrer-policy', 'no-referrer');
  });

  registerBrowserOrigins(app, options.browserOrigins);
  registerPracticeCatalogRoute(app);

  app.addHook('onRequest', async (request, reply) => {
    // Only registered practice saves, account provisioning, watchlists and wallet possession
    // proofs can write. The two wallet routes bind an identity to a wallet and move no money.
    const practiceWrite = request.method === 'PUT' && request.routeOptions.url === PRACTICE_PROGRESS_ROUTE;
    const practiceSession = request.method === 'POST' && request.routeOptions.url === PRACTICE_SESSION_ROUTE;
    const watchlistWrite = request.method === 'PUT' && request.routeOptions.url === WATCHLIST_ROUTE;
    // Keeping the name of an asset someone looked up. It stores identifiers
    // only, buys nothing, and is not a catalog approval.
    const followingWrite = request.method === 'PUT' && request.routeOptions.url === FOLLOWING_ROUTE;
    const walletPossessionWrite = request.method === 'POST' &&
      (request.routeOptions.url === WALLET_CHALLENGE_ROUTE || request.routeOptions.url === WALLET_POSSESSION_ROUTE);
    // Invitations are unfunded throughout: creating, addressing, offering,
    // accepting or declining one records social intent and moves no money.
    const invitationWrite = request.method === 'POST' &&
      (request.routeOptions.url === INVITATIONS_ROUTE || request.routeOptions.url === INVITATION_ACTION_ROUTE);
    // Closing an account changes only account status and cancels the offers it
    // sent. It moves no money.
    const closureWrite = request.method === 'POST' && request.routeOptions.url === ACCOUNT_CLOSURE_ROUTE;
    // These writes change only the simulated paper ledger. Neither route can
    // receive a wallet, transaction or live-money execution mode.
    const paperWrite = request.method === 'POST' &&
      (request.routeOptions.url === PAPER_PREVIEW_ROUTE || request.routeOptions.url === PAPER_COMMIT_ROUTE ||
        request.routeOptions.url === PAPER_RESET_ROUTE);
    // Guest writes issue, extend or one-time claim an opaque practice-only
    // credential. They cannot create a wallet or reach money execution.
    const guestWrite = request.method === 'POST' &&
      (request.routeOptions.url === GUEST_SESSION_ROUTE || request.routeOptions.url === GUEST_REFRESH_ROUTE ||
        request.routeOptions.url === GUEST_CLAIM_ROUTE);
    // This stores onboarding choices and advances the launch checkpoint. It
    // cannot access a wallet or create a financial transaction.
    const productProfileWrite = (request.method === 'PUT' && request.routeOptions.url === PRODUCT_PROFILE_ROUTE) ||
      (request.method === 'POST' && request.routeOptions.url === PRODUCT_LAUNCH_ROUTE);
    // Career writes annotate a committed paper buy or record a server-verified
    // promotion. They cannot place an order or reach a wallet.
    const dailyDeskWrite = request.method === 'POST' && request.routeOptions.url === '/v1/career/daily-desk/complete';
    const liveWrite = request.method === 'POST' && ['/v1/trading/preview','/v1/trading/execute'].includes(request.routeOptions.url ?? '');
    // These routes link an owned wallet and prepare/read a Crossmint checkout.
    // The cardholder completes payment at Crossmint; no charge endpoint exists here.
    const onrampWrite = request.method === 'POST' && ['/v1/funding/wallet', '/v1/funding/verify', '/v1/funding/orders', '/v1/funding/status'].includes(request.routeOptions.url ?? '');
    const workdayWrite = request.method === 'POST' && ['/v1/career/workdays/step','/v1/career/workdays/draft'].includes(request.routeOptions.url ?? '');
    const communityWrite = request.method === 'PUT' && request.routeOptions.url === '/v1/community/following/:socialId';
    const careerWrite = (request.method === 'POST' &&
      (request.routeOptions.url === CAREER_REASON_ROUTE || request.routeOptions.url === CAREER_PROMOTION_ROUTE)) ||
      (request.method === 'PUT' && request.routeOptions.url === CAREER_DAY_CONTEXT_ROUTE);
    // Visibility changes affect only Career reason reads. They cannot place an
    // order, move money or create a social relationship.
    const careerReasonSharingWrite = request.method === 'PUT' &&
      request.routeOptions.url === CAREER_REASON_PRIVACY_ROUTE;
    // Relationship exits and safety actions move no money and remain available
    // when new social activation is disabled.
    const socialRelationshipWrite =
      (request.method === 'POST' && (request.routeOptions.url === SOCIAL_FRIEND_ACTION_ROUTE ||
        request.routeOptions.url === SOCIAL_REASON_REPORTS_ROUTE)) ||
      (request.method === 'PUT' && request.routeOptions.url === SOCIAL_BLOCK_ROUTE);
    if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method) && !practiceWrite && !practiceSession && !watchlistWrite &&
        !followingWrite && !walletPossessionWrite && !invitationWrite && !closureWrite && !paperWrite && !guestWrite &&
        !onrampWrite && !liveWrite && !workdayWrite && !dailyDeskWrite && !communityWrite && !productProfileWrite && !careerWrite && !careerReasonSharingWrite && !socialRelationshipWrite) {
      return reply.code(503).send(safeError('FINANCIAL_OPERATIONS_DISABLED', 'Live operations are unavailable in this foundation build.', request.id));
    }
  });

  app.addHook('onResponse', async (request, reply) => {
    request.log.info({ method: request.method, route: request.routeOptions.url, statusCode: reply.statusCode }, 'request completed');
  });

  app.setErrorHandler<FastifyError>((error, request, reply) => {
    // Provider payloads, input bodies and raw error objects never enter responses/logs.
    if (error.validation) return reply.code(400).send(safeError('INVALID_REQUEST', 'Request parameters are invalid.', request.id));
    if (error.code === 'FST_ERR_CTP_BODY_TOO_LARGE') return reply.code(413).send(safeError('PAYLOAD_TOO_LARGE', 'Request body exceeds the allowed size.', request.id));
    if (error.statusCode === 415) return reply.code(415).send(safeError('UNSUPPORTED_MEDIA_TYPE', 'Request content type is unsupported.', request.id));
    if (error.statusCode === 400) return reply.code(400).send(safeError('INVALID_REQUEST', 'Request is malformed.', request.id));
    request.log.error({ errorCode: error.code ?? 'INTERNAL_ERROR' }, 'request failed');
    return reply.code(500).send(safeError('INTERNAL_ERROR', 'The request could not be completed.', request.id));
  });

  app.setNotFoundHandler((request, reply) => reply.code(404).send(safeError('NOT_FOUND', 'Route not found.', request.id)));

  app.get('/health', {schema: {querystring: noQuery}}, async () => ({
    status: 'ok',
    service: 'trimmy-api',
    mode: 'foundation',
    // Process liveness only; there is no claim that providers or a database are ready.
    financialOperationsEnabled: liveStockExecutionEnabled(options.liveStocks),
  }));

  // Liveness and readiness are separate answers on purpose. A restart policy
  // wants the first; a load balancer wants the second, and routing traffic to an
  // instance that cannot reach its database is the failure this prevents.
  const readiness = new ReadinessReporter(options.readiness ? {probe: options.readiness} : {});
  app.get('/ready', {schema: {querystring: noQuery}}, async (_request, reply) => {
    const report = await readiness.report();
    return reply.code(report.status === 'ready' ? 200 : 503).send(report);
  });

  app.get('/v1/config', {schema: {querystring: noQuery}}, async () => ({
    schemaVersion: 1,
    productName: 'Trimmy',
    capabilities: FOUNDATION_CAPABILITIES,
    moneyMode: 'practice_only',
    practiceSyncEnabled: practiceSyncEnabled(options.practice),
    practiceAccountsEnabled: practiceAccountsEnabled(options.practiceSessions),
    watchlistSyncEnabled: watchlistEnabled(options.watchlist, WATCHLIST_ROUTE),
    followedStocksEnabled: watchlistEnabled(options.following, FOLLOWING_ROUTE),
    invitationsEnabled: invitationsEnabled(options.invitations),
    relationshipSafetyEnabled: await relationshipSafetyAvailable(
      options.relationshipSafetyEnabled === true,
      options.relationshipSafetyReadiness,
    ),
    accountClosureEnabled: accountClosureEnabled(options.accountClosure),
    marketEstimatesEnabled: options.marketEstimates !== undefined,
    stockDiscoveryEnabled: options.stockDiscovery !== undefined,
    stockFactsEnabled: options.stockFacts !== undefined,
    stockEstimatesEnabled: options.stockEstimates !== undefined,
    socialXEnabled: socialXEnabled(options.socialX),
    accountContextEnabled: accountContextEnabled(options.accountContext),
    accountHoldingsEnabled: accountHoldingsEnabled(options.accountHoldings),
    walletPossessionEnabled: walletPossessionEnabled(options.walletPossession),
    stockHistoryEnabled: options.stockHistory !== undefined,
    raydiumStockQuotesEnabled: options.raydiumStockQuotes !== undefined,
    preStocksEnabled: options.preStocks !== undefined,
    paperTradingEnabled: paperTradingEnabled(options.paperTrading),
    guestSessionsEnabled: guestSessionsEnabled(options.guestSessions),
    productProfileEnabled: productProfileEnabled(options.productProfile),
    careerEnabled: careerEnabled(options.career),
    careerReasonSharingEnabled: careerReasonSharingEnabled(options.careerReasonSharing),
    notice: 'Paper positions are simulations. Real asset transfers and swaps are unavailable.',
  }));

  app.get('/v1/catalog', {schema: {querystring: noQuery}}, async () => ({
    schemaVersion: 1,
    assets: [],
    status: 'unverified',
    financialOperationsEnabled: liveStockExecutionEnabled(options.liveStocks),
    reason: 'Issuer eligibility, market-data rights and individual mint verification are pending.',
  }));

  registerPracticeRoutes(app, options.practice);
  registerPracticeSessionRoute(app, options.practiceSessions);
  registerGuestSessionRoutes(app, options.guestSessions);
  registerProductProfileRoutes(app, options.productProfile);
  registerCareerRoutes(app, options.career);
  registerCareerReasonSharingRoutes(app, options.careerReasonSharing,
    options.relationshipSafetyEnabled === true, options.relationshipSafetyReadiness);
  registerSocialRelationshipRoutes(app, options.socialRelationships);
  registerCommunityRoutes(app, options.community);
  registerDailyDeskRoutes(app, options.dailyDesk);
  registerWorkdayRoutes(app, options.workdays);
  registerLiveStockRoutes(app, options.liveStocks);
  registerWatchlistRoutes(app, options.watchlist, WATCHLIST_ROUTE);
  // The same storage engine on a second table, so the fictional sample list and
  // the real one cannot merge.
  registerWatchlistRoutes(app, options.following, FOLLOWING_ROUTE);
  registerInvitationRoutes(app, options.invitations,
    options.relationshipSafetyEnabled === true, options.relationshipSafetyReadiness);
  registerAccountClosureRoute(app, options.accountClosure);
  registerMarketEstimateRoute(app, options.marketEstimates);
  registerStockDiscoveryRoutes(app, options.stockDiscovery);
  registerStockFactsRoutes(app, options.stockFacts);
  registerPublicHolders(app, options.publicHolders);
  registerStockEstimateRoute(app, options.stockEstimates ? {stockEstimates: options.stockEstimates} : {});
  registerSocialXRoutes(app, options.socialX);
  registerAccountContextRoute(app, options.accountContext);
  registerOnrampRoutes(app, options.onramp);
  registerAccountHoldingsRoute(app, options.accountHoldings);
  registerWalletPossessionRoutes(app, options.walletPossession);
  registerStockHistoryRoute(app, options.stockHistory);
  registerRaydiumStockQuoteRoute(app, options.raydiumStockQuotes ? {quotes: options.raydiumStockQuotes} : {});
  registerPreStocksRoute(app, options.preStocks);
  registerPaperTradingRoutes(app, options.paperTrading);

  return app;
}
