import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

export class BrowserOriginsConfigurationError extends Error {
  readonly code = 'BROWSER_ORIGINS_INVALID';
  constructor() {
    super('Browser origins must be a list of canonical HTTPS origins.');
    this.name = 'BrowserOriginsConfigurationError';
  }
}

function canonicalOrigin(input: unknown): string | undefined {
  if (typeof input !== 'string' || input.length > 2048) return undefined;
  try {
    const url = new URL(input);
    if (url.protocol !== 'https:' || !url.hostname || url.hostname.includes('*') || url.hostname.endsWith('.') ||
        url.username || url.password || url.search || url.hash || url.pathname !== '/' ||
        url.origin !== input) return undefined;
    // Exact serialization rejects default ports, alternate IP notation, case,
    // Unicode and slash aliases. No implicit subdomain or trailing-dot matches.
    return input;
  } catch { return undefined; }
}

/** Configuration is explicit, detached and finite. No wildcard or dev bypass. */
export function parseBrowserOrigins(input: unknown): readonly string[] {
  if (!Array.isArray(input) || input.length > 32 || Reflect.ownKeys(input).length !== input.length + 1) {
    throw new BrowserOriginsConfigurationError();
  }
  const result: string[] = [];
  for (let index = 0; index < input.length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(input, String(index));
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) throw new BrowserOriginsConfigurationError();
    const origin = canonicalOrigin(descriptor.value);
    if (!origin || result.includes(origin)) throw new BrowserOriginsConfigurationError();
    result.push(origin);
  }
  return Object.freeze(result);
}

const methodsByRoute: Readonly<Record<string, readonly string[]>> = Object.freeze({
  '/v1/watchlist': Object.freeze(['GET', 'PUT']),
  '/v1/practice/session': Object.freeze(['POST']),
  '/v1/guest/session': Object.freeze(['POST']),
  '/v1/guest/session/refresh': Object.freeze(['POST']),
  '/v1/guest/claim': Object.freeze(['POST']),
  '/v1/product/profile': Object.freeze(['GET', 'PUT']),
  '/v1/product/launch': Object.freeze(['POST']),
  '/v1/career/summary': Object.freeze(['GET']),
  '/v1/career/missions': Object.freeze(['GET']),
  '/v1/career/trade-reasons': Object.freeze(['GET', 'POST']),
  '/v1/career/reason-privacy': Object.freeze(['GET', 'PUT']),
  '/v1/career/promotions': Object.freeze(['POST']),
  '/v1/career/day-context': Object.freeze(['GET', 'PUT']),
  '/v1/career/workdays': Object.freeze(['GET']),
  '/v1/career/workdays/step': Object.freeze(['POST']),
  '/v1/career/workdays/draft': Object.freeze(['POST']),
  '/v1/career/daily-desk': Object.freeze(['GET']),
  '/v1/career/daily-desk/complete': Object.freeze(['POST']),
  // Career's "Activity this week" on the web, as on mobile.
  '/v1/career/activity-week': Object.freeze(['GET']),
  '/v1/community': Object.freeze(['GET']),
  '/v1/community/following/:socialId': Object.freeze(['PUT']),
  // Web parity with mobile: followed stocks, blocking a trader, reporting a
  // reason and closing one's own account. Authentication still decides.
  '/v1/following': Object.freeze(['GET', 'PUT']),
  '/v1/social/blocks/:socialId': Object.freeze(['GET', 'PUT']),
  '/v1/social/reason-reports': Object.freeze(['POST']),
  '/v1/account/closure': Object.freeze(['POST']),
  '/v1/practice/progress': Object.freeze(['GET', 'PUT']),
  '/v1/config': Object.freeze(['GET']),
  '/v1/practice/catalog': Object.freeze(['GET']),
  '/v1/markets/estimate': Object.freeze(['GET']),
  '/v1/markets/stocks/search': Object.freeze(['GET']),
  '/v1/markets/stocks/variants': Object.freeze(['GET']),
  '/v1/markets/stocks/estimate': Object.freeze(['GET']),
  '/v1/markets/stocks/history': Object.freeze(['GET']),
  '/v1/markets/stocks/quotes/raydium': Object.freeze(['GET']),
  '/v1/markets/stocks/catalog': Object.freeze(['GET']),
  '/v1/markets/stocks/cards': Object.freeze(['GET']),
  '/v1/markets/stocks/facts': Object.freeze(['GET']),
  '/v1/markets/stocks/prices': Object.freeze(['GET']),
  '/v1/markets/stocks/insight': Object.freeze(['GET']),
  '/v1/markets/stocks/holders': Object.freeze(['GET']),
  '/v1/markets/prestocks': Object.freeze(['GET']),
  '/v1/social/x/profile': Object.freeze(['GET']),
  '/v1/account/context': Object.freeze(['GET']),
  '/v1/account/holdings': Object.freeze(['GET']),
  '/v1/account/wallet/challenge': Object.freeze(['POST']),
  '/v1/account/wallet/possession': Object.freeze(['POST']),
  // Real-money orders from the web app: the same authenticated, reviewed and
  // user-signed flow as mobile. Response access only; no permission is implied.
  '/v1/trading/capabilities': Object.freeze(['GET']),
  '/v1/trading/preview': Object.freeze(['POST']),
  '/v1/trading/execute': Object.freeze(['POST']),
  '/v1/trading/order': Object.freeze(['GET']),
  '/v1/trading/history': Object.freeze(['GET']),
  '/v1/trading/order/:id': Object.freeze(['GET']),
  // Sending money out: the same authenticated, reviewed and user-signed flow.
  '/v1/wallet/transfers/preview': Object.freeze(['POST']),
  '/v1/wallet/transfers/execute': Object.freeze(['POST']),
  '/v1/wallet/transfers/status': Object.freeze(['GET']),
  '/v1/account/paper/portfolio': Object.freeze(['GET']),
  '/v1/account/paper/orders/preview': Object.freeze(['POST']),
  '/v1/account/paper/orders/commit': Object.freeze(['POST']),
  '/v1/account/paper/reset': Object.freeze(['POST']),
});
const allowedHeaders = new Set(['authorization', 'content-type', 'x-trimmy-guest']);

function vary(reply: FastifyReply, ...names: string[]): void {
  const previous = reply.getHeader('vary');
  const values = (Array.isArray(previous) ? previous.join(',') : String(previous ?? ''))
    .split(',').map(value => value.trim()).filter(Boolean);
  for (const name of names) {
    if (!values.some(value => value.toLowerCase() === name.toLowerCase())) values.push(name);
  }
  reply.header('vary', values.join(', '));
}

function deny(reply: FastifyReply, request: FastifyRequest, code: string, message: string, status = 403) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}

function requestedHeaders(input: unknown, route: string | undefined): readonly string[] | undefined {
  if (input === undefined) return [];
  if (typeof input !== 'string' || input.length > 128) return undefined;
  const names = input.split(',').map(name => name.trim().toLowerCase());
  if (names.length > (route === '/v1/account/holdings' ? 4 : 3) || new Set(names).size !== names.length || names.some(name =>
    !allowedHeaders.has(name) && !(route === '/v1/account/holdings' && ['x-trimmy-holdings-version','x-trimmy-holdings-min-slot'].includes(name)))) return undefined;
  return names;
}

/**
 * Register after common security headers and before authentication/body parsing.
 * This grants browser response access, never identity or financial permissions.
 * https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS
 * https://fastify.dev/docs/latest/Reference/Hooks/#onrequest
 */
export function registerBrowserOrigins(app: FastifyInstance, input: readonly string[] = []): void {
  const origins = new Set(parseBrowserOrigins(input));
  app.addHook('onRequest', async (request, reply) => {
    vary(reply, 'Origin');
    const origin = request.headers.origin;
    if (origin === undefined) return;
    const canonical = canonicalOrigin(origin);
    if (!canonical || !origins.has(canonical)) {
      return deny(reply, request, 'BROWSER_ORIGIN_DENIED', 'This browser origin is not allowed.');
    }
    reply.header('access-control-allow-origin', canonical);
    // Guest creation rate limits carry the database-calculated delay. Browsers
    // may read only safelisted headers unless this response header is exposed.
    reply.header('access-control-expose-headers', 'Retry-After');
    if (request.method !== 'OPTIONS') return;

    vary(reply, 'Access-Control-Request-Method', 'Access-Control-Request-Headers');
    const route = request.routeOptions.url;
    const methods = route ? methodsByRoute[route] : undefined;
    const method = request.headers['access-control-request-method'];
    const headers = requestedHeaders(request.headers['access-control-request-headers'], route);
    const queryRoute = route !== undefined && [
      '/v1/markets/estimate', '/v1/markets/stocks/search', '/v1/markets/stocks/variants', '/v1/markets/stocks/estimate',
      '/v1/markets/stocks/history',
      '/v1/markets/stocks/quotes/raydium',
      '/v1/markets/stocks/catalog', '/v1/markets/stocks/cards', '/v1/markets/stocks/facts', '/v1/markets/stocks/insight',
      '/v1/markets/stocks/prices',
      '/v1/markets/stocks/holders',
      '/v1/trading/capabilities',
      '/v1/social/x/profile',
      '/v1/career/trade-reasons',
      '/v1/community',
      '/v1/trading/history',
      '/v1/wallet/transfers/status',
    ].includes(route) &&
      request.raw.url?.split('?')[0] === route;
    const communityFollowRoute = route === '/v1/community/following/:socialId' &&
      /^\/v1\/community\/following\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(request.raw.url ?? '');
    // Workdays and desk stories take exactly one query: `?lang=` with a language the API serves.
    const workdayLanguageRoute = route !== undefined &&
      ['/v1/career/workdays', '/v1/career/workdays/step', '/v1/career/workdays/draft',
        '/v1/career/daily-desk', '/v1/career/daily-desk/complete'].includes(route) &&
      request.raw.url === `${route}?${(request.raw.url ?? '').split('?')[1] ?? ''}` &&
      /^lang=(en|es|pt|fr)$/.test((request.raw.url ?? '').split('?')[1] ?? '');
    const blockRoute = route === '/v1/social/blocks/:socialId' &&
      /^\/v1\/social\/blocks\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(request.raw.url ?? '');
    const tradeStatusRoute = route === '/v1/trading/order/:id' &&
      /^\/v1\/trading\/order\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(request.raw.url ?? '');
    if (!methods || (request.raw.url !== route && !queryRoute && !communityFollowRoute && !tradeStatusRoute && !blockRoute && !workdayLanguageRoute) ||
        (route === '/v1/trading/order/:id' && !tradeStatusRoute) || (route === '/v1/social/blocks/:socialId' && !blockRoute) ||
        typeof method !== 'string' || !methods.includes(method) ||
        headers === undefined || (headers.includes('x-trimmy-guest') && route !== '/v1/guest/claim') ||
        request.headers['access-control-request-private-network'] !== undefined) {
      return deny(reply, request, 'BROWSER_PREFLIGHT_DENIED', 'This browser request is not allowed.');
    }
    reply.header('access-control-allow-methods', methods.join(', '));
    if (headers.length) reply.header('access-control-allow-headers', headers.join(', '));
    return reply.code(204).send();
  });

  for (const route of Object.keys(methodsByRoute)) {
    app.options(route, async (request, reply) =>
      deny(reply, request, 'BROWSER_PREFLIGHT_INVALID', 'A browser preflight requires an allowed origin.', 400));
  }
}
