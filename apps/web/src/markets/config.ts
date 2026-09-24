export type StockResearchConfig =
  | Readonly<{kind: 'disabled' | 'invalid'; apiOrigin: null}>
  | Readonly<{kind: 'enabled'; apiOrigin: string}>;

/** Canonical public origin only. No account IDs, tokens or provider credentials. */
export function parseStockResearchConfig(
  apiOrigin: unknown, options: {readonly allowLoopbackForTests?: boolean} = {},
): StockResearchConfig {
  if (apiOrigin === undefined || apiOrigin === '') return Object.freeze({kind: 'disabled', apiOrigin: null});
  const invalid = (): StockResearchConfig => Object.freeze({kind: 'invalid', apiOrigin: null});
  if (typeof apiOrigin !== 'string' || apiOrigin.length > 2048 || /[\s?#\\]/u.test(apiOrigin)) return invalid();
  try {
    const url = new URL(apiOrigin);
    const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
    if ((apiOrigin !== url.origin && apiOrigin !== url.origin + '/') || url.username || url.password ||
        url.pathname !== '/' || url.port === '0' ||
        (url.protocol !== 'https:' && !(options.allowLoopbackForTests && loopback && url.protocol === 'http:'))) return invalid();
    return Object.freeze({kind: 'enabled', apiOrigin: url.origin});
  } catch { return invalid(); }
}
export function readStockResearchConfig(env: Record<string, unknown> = import.meta.env ?? {}): StockResearchConfig {
  return parseStockResearchConfig(env['VITE_TRIMMY_STOCK_API_URL']);
}
