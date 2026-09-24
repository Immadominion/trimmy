export function validPrivySubject(subject: unknown): subject is string {
  return typeof subject === 'string' &&
    /^did:privy:[A-Za-z0-9]{1,128}$/.exec(subject)?.[0] === subject;
}

/** Local race check only. Authentication remains the API's signature check. */
export class IdentityBoundTokenReader {
  #subject: string | null = null;
  #generation = 0;
  #closed = false;

  constructor(private readonly appId: string, private readonly now: () => number = Date.now) {}

  observe(subject: string | null): void {
    const next = validPrivySubject(subject) ? subject : null;
    if (this.#subject !== next) {
      this.#generation++;
      this.#subject = next;
    }
  }

  invalidate(): void {
    this.#generation++;
    this.#subject = null;
  }

  close(): void { this.invalidate(); this.#closed = true; }

  async read(expectedSubject: string, sdkToken: () => Promise<string | null>): Promise<string | null> {
    const generation = this.#generation;
    const bound = () => !this.#closed && this.#generation === generation &&
      this.#subject === expectedSubject && validPrivySubject(expectedSubject);
    if (!bound()) return null;
    try {
      const token = await sdkToken();
      return bound() && tokenMatches(token, expectedSubject, this.appId, this.now()) ? token : null;
    } catch { return null; }
  }
}

function tokenMatches(token: string | null, subject: string, appId: string, now: number): boolean {
  if (token === null || token.length > 8185 ||
      /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.exec(token)?.[0] !== token) return false;
  try {
    const parts = token.split('.');
    const decode = (part: string): Record<string, unknown> | null => {
      const text = atob(part.replaceAll('-', '+').replaceAll('_', '/'));
      const value: unknown = JSON.parse(text);
      return typeof value === 'object' && value !== null && !Array.isArray(value)
        ? value as Record<string, unknown> : null;
    };
    const header = decode(parts[0]!);
    const claims = decode(parts[1]!);
    if (!header || !claims) return false;
    const exp = claims['exp'], iat = claims['iat'], sid = claims['sid'];
    return header['alg'] === 'ES256' && header['typ'] === 'JWT' &&
      claims['sub'] === subject && claims['aud'] === appId && claims['iss'] === 'privy.io' &&
      typeof exp === 'number' && Number.isSafeInteger(exp) && exp > Math.floor(now / 1000) &&
      typeof iat === 'number' && Number.isSafeInteger(iat) && iat > 0 &&
      iat <= Math.floor(now / 1000) && exp > iat &&
      typeof sid === 'string' && /^[A-Za-z0-9_-]{1,256}$/.exec(sid)?.[0] === sid;
  } catch { return false; }
}
