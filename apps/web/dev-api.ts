import type {IncomingMessage, ServerResponse} from 'node:http';
import type {Plugin} from 'vite';

// Deliberately a local development adapter, never a general-purpose HTTP proxy.
const routes: Readonly<Record<string, readonly string[]>> = {
  '/v1/guest/session': ['POST'], '/v1/guest/session/refresh': ['POST'],
  '/v1/practice/session': ['POST'], '/v1/guest/claim': ['POST'],
  '/v1/product/profile': ['GET', 'PUT'], '/v1/product/launch': ['POST'],
  '/v1/account/paper/portfolio': ['GET'],
  '/v1/account/paper/orders/preview': ['POST'], '/v1/account/paper/orders/commit': ['POST'],
  '/v1/career/summary': ['GET'], '/v1/career/missions': ['GET'], '/v1/career/activity-week': ['GET'],
  '/v1/career/daily-desk': ['GET'], '/v1/career/daily-desk/complete': ['POST'],
  '/v1/career/workdays': ['GET'], '/v1/career/workdays/step': ['POST'], '/v1/career/workdays/draft': ['POST'],
  '/v1/markets/stocks/catalog': ['GET'], '/v1/markets/stocks/search': ['GET'],
  '/v1/markets/stocks/cards': ['GET'], '/v1/markets/stocks/variants': ['GET'],
  '/v1/markets/stocks/facts': ['GET'], '/v1/markets/stocks/insight': ['GET'],
};

function problem(res: ServerResponse, status: number, code: string) {
  res.writeHead(status, {'content-type': 'application/json', 'cache-control': 'no-store'});
  res.end(JSON.stringify({error: {code, message: 'The local practice connection is unavailable.'}}));
}

class BodyProblem extends Error {
  constructor(readonly status: number, readonly code: string) {super(code);}
}

// The API rejects duplicate physical credentials. Node's normalized headers
// can discard or join them, so do not turn an ambiguous request into a valid one.
function credentialHeader(req: IncomingMessage, name: string): string | null | undefined {
  const values: string[] = [];
  for (let index = 0; index < req.rawHeaders.length; index += 2) {
    if (req.rawHeaders[index]?.toLowerCase() === name) values.push(req.rawHeaders[index + 1] ?? '');
  }
  return values.length > 1 ? null : values[0];
}

function readBody(req: IncomingMessage, timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    let bytes = 0;
    let settled = false;
    const chunks: Buffer[] = [];
    const finish = (error?: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      req.off('data', onData); req.off('end', onEnd); req.off('aborted', onAborted);
      if (error) {req.pause(); reject(error);} else resolve(Buffer.concat(chunks).toString('utf8'));
    };
    const onData = (chunk: Buffer | string) => {
      const value = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      bytes += value.byteLength;
      if (bytes > 8192) {finish(new BodyProblem(413, 'LOCAL_REQUEST_TOO_LARGE')); return;}
      chunks.push(value);
    };
    const onEnd = () => finish();
    const onError = (error: Error) => finish(error);
    const onAborted = () => finish(new BodyProblem(400, 'LOCAL_REQUEST_INCOMPLETE'));
    // An aborted IncomingMessage can emit error after aborted. Keep its error
    // listener until close even when the promise already returned an error.
    const onClose = () => {onAborted(); req.off('error', onError);};
    const deadline = setTimeout(() => finish(new BodyProblem(408, 'LOCAL_REQUEST_TIMEOUT')), timeoutMs);
    req.on('data', onData); req.once('end', onEnd); req.once('error', onError); req.once('aborted', onAborted); req.once('close', onClose);
  });
}

export function createDevelopmentRelay(apiOrigin: string, fetcher: typeof fetch = fetch,
  {bodyTimeoutMs = 5_000}: {bodyTimeoutMs?: number} = {}) {
  const target = new URL(apiOrigin);
  if (target.protocol !== 'https:' || target.origin !== apiOrigin || target.username || target.password) {
    throw new Error('TRIMMY_WEB_DEV_API_URL must be a canonical HTTPS origin.');
  }
  if (!Number.isInteger(bodyTimeoutMs) || bodyTimeoutMs <= 0) throw new Error('Body timeout must be a positive integer.');
  return async (req: IncomingMessage, res: ServerResponse, next: () => void): Promise<void> => {
    if (!req.url?.startsWith('/api/')) {next(); return;}
    const host = req.headers.host;
    const origin = req.headers.origin;
    if (!host || !/^(127\.0\.0\.1|localhost):4174$/.test(host) ||
        origin !== undefined && origin !== `http://${host}` ||
        req.headers['sec-fetch-site'] === 'cross-site' || req.headers['sec-fetch-site'] === 'same-site') {
      problem(res, 403, 'LOCAL_ORIGIN_DENIED'); return;
    }
    const relative = req.url.slice(4);
    const rawPath = relative.split(/[?#]/, 1)[0]!;
    const url = new URL(relative, target);
    const method = req.method ?? 'GET';
    if (url.origin !== target.origin || rawPath.includes('\\') || /%2f|%5c|%2e/i.test(rawPath) ||
        !routes[url.pathname]?.includes(method)) {
      problem(res, 404, 'LOCAL_ROUTE_UNAVAILABLE'); return;
    }
    const authorization = credentialHeader(req, 'authorization');
    const guestClaim = url.pathname === '/v1/guest/claim' ? credentialHeader(req, 'x-trimmy-guest') : undefined;
    if (authorization === null || guestClaim === null) {
      problem(res, 400, 'LOCAL_AUTH_HEADERS_INVALID'); return;
    }
    const headers = new Headers({accept: String(req.headers.accept ?? 'application/json')});
    if (authorization !== undefined) headers.set('authorization', authorization);
    if (guestClaim !== undefined) headers.set('x-trimmy-guest', guestClaim);
    let body: string | undefined;
    if (method !== 'GET') {
      if (req.headers['content-type']?.split(';')[0] !== 'application/json') {
        problem(res, 415, 'LOCAL_JSON_REQUIRED'); return;
      }
      headers.set('content-type', 'application/json');
      try {body = await readBody(req, bodyTimeoutMs);} catch (error) {
        if (!(error instanceof BodyProblem)) throw error;
        // Flush the error before closing an incomplete request's connection.
        // Destroying IncomingMessage immediately can discard the 408/413.
        res.shouldKeepAlive = false;
        res.setHeader('connection', 'close');
        problem(res, error.status, error.code); return;
      }
    }
    try {
      // Only the caller's explicit authorization and claim-only guest credential
      // cross this boundary. No cookies, Origin rewriting, generated SDK token,
      // API key, or administrative secret.
      const response = await fetcher(url, {method, headers, ...(body === undefined ? {} : {body}),
        redirect: 'error', signal: AbortSignal.timeout(25_000)});
      const reader = response.body?.getReader();
      const chunks: Uint8Array[] = []; let length = 0;
      if (reader) for (;;) {
        const {done, value} = await reader.read(); if (done) break;
        length += value.byteLength;
        if (length > 2_097_152) {await reader.cancel(); throw new Error('Response too large');}
        chunks.push(value);
      }
      const responseHeaders: Record<string, string> = {'content-type': response.headers.get('content-type') ?? 'application/json',
        'cache-control': 'no-store', 'x-content-type-options': 'nosniff'};
      const retry = response.headers.get('retry-after'); if (retry) responseHeaders['retry-after'] = retry;
      res.writeHead(response.status, responseHeaders);
      res.end(Buffer.concat(chunks));
    } catch {problem(res, 502, 'LOCAL_API_UNAVAILABLE');}
  };
}

export function developmentApiPlugin(apiOrigin: string | undefined): Plugin {
  return {name: 'trimmy-local-practice-api', apply: 'serve', configureServer(server) {
    if (!apiOrigin) return;
    const relay = createDevelopmentRelay(apiOrigin);
    server.middlewares.use((req, res, next) => {void relay(req, res, next).catch(() => {
      if (!res.headersSent) problem(res, 502, 'LOCAL_API_UNAVAILABLE'); else res.end();
    });});
  }};
}
