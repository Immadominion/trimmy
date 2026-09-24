export type PracticeWebConfig =
  | Readonly<{ kind: 'disabled'; apiOrigin: null }>
  | Readonly<{ kind: 'invalid'; apiOrigin: null }>
  | Readonly<{ kind: 'enabled'; appId: string; clientId: string; apiOrigin: string }>;

/** Public IDs only. The server verification key and app secret never belong here. */
export function parsePracticeWebConfig(
  input: { appId?: unknown; clientId?: unknown; apiOrigin?: unknown },
  options: { allowLoopbackForTests?: boolean } = {},
): PracticeWebConfig {
  const values = [input.appId, input.clientId, input.apiOrigin];
  if (values.every((value) => value === undefined || value === '')) {
    return Object.freeze({ kind: 'disabled', apiOrigin: null });
  }
  const validId = (value: unknown): value is string =>
    typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.exec(value)?.[0] === value;
  if (!validId(input.appId) || !validId(input.clientId) ||
      typeof input.apiOrigin !== 'string' || input.apiOrigin.length > 2048 ||
      /[\s?#\\]/.test(input.apiOrigin)) {
    return Object.freeze({ kind: 'invalid', apiOrigin: null });
  }
  try {
    const url = new URL(input.apiOrigin);
    const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
    if (url.username || url.password || url.search || url.hash ||
        url.pathname !== '/' || url.port === '0' ||
        (url.protocol !== 'https:' &&
          !(options.allowLoopbackForTests && loopback && url.protocol === 'http:'))) {
      return Object.freeze({ kind: 'invalid', apiOrigin: null });
    }
    return Object.freeze({
      kind: 'enabled', appId: input.appId, clientId: input.clientId, apiOrigin: url.origin,
    });
  } catch {
    return Object.freeze({ kind: 'invalid', apiOrigin: null });
  }
}

export function readPracticeWebConfig(
  env: Record<string, unknown> = import.meta.env,
): PracticeWebConfig {
  return parsePracticeWebConfig({
    appId: env['VITE_PRIVY_APP_ID'],
    clientId: env['VITE_PRIVY_APP_CLIENT_ID'],
    apiOrigin: env['VITE_TRIMMY_API_URL'],
  });
}
