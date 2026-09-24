import {LiveStockOrders} from './live-stock-orders.js';
import {readCrossmintOnramp} from './crossmint-onramp.js';
import {PublicTokenHolders} from './public-token-holders.js';
import { buildApp } from './app.js';
import { createPracticeRuntime, readPracticeRuntimeConfig } from './practice-runtime.js';
import { readMarketEstimates } from './market-estimates.js';
import { readStockDiscovery } from './stock-discovery.js';
import { readStockFacts } from './stock-facts.js';
import { readPreStocks } from './prestocks-reader.js';
import { readJupiterQuoteReader } from './jupiter-quote-reader.js';
import { readStockEstimates } from './stock-estimates.js';
import { readXProfileLookup } from './x-profile-lookup.js';
import {XProfileRequestBudget} from './x-profile-routes.js';
import { readAccountContextResolver } from './account-context-route.js';
import { readSolanaStockHoldingsReader } from './stock-holdings.js';
import { readStockHistory } from './stock-history.js';
import { readRaydiumStockQuotes } from './raydium-stock-quotes.js';
import { createTlsServerFactory, readTlsListenerConfig } from './tls-listener.js';
import { createWalletPossessionRuntime, readWalletPossessionRuntimeConfig } from './wallet-possession-runtime.js';
import { TokensPaperPriceReader } from './paper-price-reader.js';
import { createGuestPaperAuthenticator } from './guest-session-routes.js';
import {readRelationshipSafetyEnabled} from './relationship-safety-config.js';

const rawPort = process.env['PORT'] ?? '4100';
if (!/^\d{1,5}$/.test(rawPort) || Number(rawPort) < 1 || Number(rawPort) > 65535) {
  throw new Error('PORT must be an integer between 1 and 65535.');
}
const rawLogLevel = process.env['LOG_LEVEL'] ?? 'info';
const levels = ['debug', 'info', 'warn', 'error', 'fatal', 'silent'] as const;
type LogLevel = typeof levels[number];
if (!levels.includes(rawLogLevel as LogLevel)) throw new Error('LOG_LEVEL is not supported.');
const relationshipSafetyEnabled = readRelationshipSafetyEnabled(process.env);

// One reader owns the provider pace across SOL/USDC and pinned stock estimates.
const jupiterQuoteReader = readJupiterQuoteReader(process.env);
const marketEstimates = readMarketEstimates(process.env, jupiterQuoteReader);
const stockEstimates = readStockEstimates(process.env, jupiterQuoteReader);
const stockDiscovery = readStockDiscovery(process.env);
const stockFacts = readStockFacts(process.env);
const publicHolders = process.env['HOLDERS_SOLANA_RPC_URL'] ? new PublicTokenHolders(process.env['HOLDERS_SOLANA_RPC_URL']) : undefined;
const preStocks = readPreStocks(process.env);
const walletPossessionConfig = readWalletPossessionRuntimeConfig(process.env);
const linkedIdentities = readAccountContextResolver(process.env);
const practice = createPracticeRuntime(readPracticeRuntimeConfig(process.env));
const walletPossession = createWalletPossessionRuntime(walletPossessionConfig, practice, linkedIdentities);
const xProfileLookup = readXProfileLookup(process.env);
const xProfileBudget = new XProfileRequestBudget();
const socialX = xProfileLookup && practice.authenticate
  ? {lookup: xProfileLookup, authenticate: practice.authenticate, budget: xProfileBudget} : undefined;
const invitations = xProfileLookup && linkedIdentities && practice.authenticate &&
    practice.authenticateContext && practice.invitationsRepository
  ? {
      repository: practice.invitationsRepository,
      authenticate: practice.authenticate,
      authenticateContext: practice.authenticateContext,
      linkedIdentities,
      xProfiles: xProfileLookup,
      xLookupBudget: xProfileBudget,
    }
  : undefined;
const accountClosure = practice.authenticate && practice.accountClosureRepository
  ? {
      repository: practice.accountClosureRepository,
      authenticate: practice.authenticate,
      ...(practice.authenticateContext ? {authenticateContext: practice.authenticateContext} : {}),
      ...(linkedIdentities ? {linkedIdentities} : {}),
    }
  : undefined;
// Capability activation requires the complete provider-backed invitation path,
// every relationship safety route and the live database/grant proof. Safety
// exits stay mounted through practiceOptions even while this is unavailable.
const relationshipSafetyReadiness = invitations && accountClosure &&
    practice.options.socialRelationships && practice.options.careerReasonSharing &&
    practice.relationshipSafetyReadiness
  ? practice.relationshipSafetyReadiness : undefined;
const accountContext = linkedIdentities && practice.authenticateContext
  ? {linkedIdentities, authenticate: practice.authenticateContext} : undefined;
const onrampService = readCrossmintOnramp(process.env);
const onramp = accountContext && onrampService ? {...accountContext, service: onrampService} : undefined;
const holdingsReader = readSolanaStockHoldingsReader(process.env);
const stockHistory = readStockHistory(process.env);
const raydiumStockQuotes = readRaydiumStockQuotes(process.env);
const accountHoldings = linkedIdentities && practice.authenticateContext && holdingsReader
  ? {linkedIdentities, authenticate: practice.authenticateContext, holdings: holdingsReader} : undefined;
const liveRpc = process.env['SOLANA_MAINNET_RPC_URL'];
const liveStocks = process.env['TRIMMY_LIVE_STOCKS'] === 'solana_mainnet' && liveRpc &&
    practice.liveOrderStore && practice.authenticateContext && linkedIdentities
  ? {authenticate: practice.authenticateContext, identities: linkedIdentities,
      service: new LiveStockOrders({rpcUrl: liveRpc, store: practice.liveOrderStore,
        ...(process.env['JUPITER_API_KEY'] ? {apiKey: process.env['JUPITER_API_KEY']} : {})})}
  : undefined;
const paperAuthenticate = practice.authenticate && practice.guestSessionRepository
  ? createGuestPaperAuthenticator(practice.authenticate, practice.guestSessionRepository) : practice.authenticate;
const paperTrading = stockDiscovery && paperAuthenticate && practice.paperTradingRepository
  ? {repository: practice.paperTradingRepository, authenticate: paperAuthenticate,
      prices: new TokensPaperPriceReader(stockDiscovery)} : undefined;
// Production social authority is composed below only when its provider proof
// dependencies exist. The legacy adapters remain available to isolated staged
// tests but cannot silently become the server runtime.
const {
  invitations: legacyInvitations,
  accountClosure: legacyAccountClosure,
  ...practiceOptions
} = practice.options;
void legacyInvitations;
void legacyAccountClosure;
// Optional native HTTPS; both certificate and key files are required together.
const tls = readTlsListenerConfig(process.env);
const app = buildApp({logLevel: rawLogLevel as LogLevel, ...practiceOptions,
  ...(onramp ? {onramp} : {}),
  relationshipSafetyEnabled,
  ...(publicHolders ? {publicHolders} : {}),
  ...(liveStocks ? {liveStocks} : {}),
  ...(relationshipSafetyReadiness ? {relationshipSafetyReadiness} : {}),
  ...(invitations ? {invitations} : {}),
  ...(accountClosure ? {accountClosure} : {}),
  ...(tls ? {serverFactory: createTlsServerFactory(tls)} : {}),
  ...(marketEstimates ? {marketEstimates} : {}), ...(stockEstimates ? {stockEstimates} : {}),
  ...(stockDiscovery ? {stockDiscovery} : {}), ...(stockFacts ? {stockFacts} : {}), ...(socialX ? {socialX} : {}),
  ...(accountContext ? {accountContext} : {}), ...(accountHoldings ? {accountHoldings} : {}),
  ...(walletPossession ? {walletPossession} : {}),
  ...(stockHistory ? {stockHistory} : {}), ...(raydiumStockQuotes ? {raydiumStockQuotes} : {}),
  ...(preStocks ? {preStocks} : {}), ...(paperTrading ? {paperTrading} : {})});
app.addHook('onClose', practice.close);
try {
  await app.listen({port: Number(rawPort), host: process.env['HOST'] ?? '127.0.0.1'});
} catch {
  await app.close();
  throw new Error('The API could not start.');
}

let shuttingDown = false;
async function shutdown(): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  try { await app.close(); }
  catch { process.exitCode = 1; }
}
process.once('SIGINT', () => { void shutdown(); });
process.once('SIGTERM', () => { void shutdown(); });
