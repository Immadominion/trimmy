/** A server-verified provider identity, never a body/header-selected user UUID. */
export interface PracticeIdentity {
  readonly provider: 'privy';
  readonly appId: string;
  readonly subject: string;
}

export interface PracticeIdentityVerifier {
  verify(token: string): Promise<PracticeIdentity | null>;
}

export interface PracticeAccount { readonly userId: string }

export interface PracticeAccountRepository {
  find(identity: PracticeIdentity): Promise<PracticeAccount | null>;
  provision(identity: PracticeIdentity): Promise<PracticeAccount>;
}

export type PracticeIdentityErrorCode =
  | 'PRACTICE_IDENTITY_INVALID'
  | 'PRACTICE_IDENTITY_CONFIGURATION_INVALID'
  | 'PRACTICE_ACCOUNT_UNAVAILABLE'
  | 'PRACTICE_IDENTITY_STORAGE_INVALID'
  | 'PRACTICE_IDENTITY_RUNTIME_ROLE_INVALID';

export class PracticeIdentityError extends Error {
  constructor(readonly code: PracticeIdentityErrorCode, message: string) {
    super(message);
    this.name = 'PracticeIdentityError';
  }
}

export const MAX_PRACTICE_BEARER_HEADER_LENGTH = 8192;
const compactJwt = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

export function isPracticeAppId(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.exec(value)?.[0] === value;
}

/** A bounded compact JWT only. No cookies, query fallback, arrays or trimming. */
export function parsePracticeBearerToken(header: unknown): string | null {
  if (typeof header !== 'string' || header.length > MAX_PRACTICE_BEARER_HEADER_LENGTH) return null;
  const match = /^Bearer (.+)$/i.exec(header);
  return match?.[0] === header && match[1] && isPracticeAccessToken(match[1]) ? match[1] : null;
}

export function isPracticeAccessToken(token: unknown): token is string {
  return typeof token === 'string' && token.length <= MAX_PRACTICE_BEARER_HEADER_LENGTH - 7 && compactJwt.exec(token)?.[0] === token;
}

function invalid(): never {
  throw new PracticeIdentityError('PRACTICE_IDENTITY_INVALID', 'Verified practice identity is invalid.');
}

/**
 * Privy documents opaque did:privy: identifiers with alphanumeric suffixes.
 * Preserve case and the complete subject; do not infer a CUID length or normalize
 * it into a wallet/email/X identity. This validates structure, not authenticity.
 * https://docs.privy.io/api-reference/users/get
 */
export function parsePracticeIdentity(input: unknown): PracticeIdentity {
  try {
    if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
    const prototype: unknown = Object.getPrototypeOf(input);
    if (prototype !== Object.prototype && prototype !== null) invalid();
    const keys = Reflect.ownKeys(input);
    if (keys.length !== 3 || keys.some(key => typeof key !== 'string' || !['provider', 'appId', 'subject'].includes(key))) invalid();
    const values: Record<string, unknown> = {};
    for (const key of keys) {
      const descriptor = Object.getOwnPropertyDescriptor(input, key);
      if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
      values[key as string] = descriptor.value;
    }
    const appId = values['appId'];
    const subject = values['subject'];
    if (values['provider'] !== 'privy' || !isPracticeAppId(appId) ||
        typeof subject !== 'string' || /^did:privy:[A-Za-z0-9]{1,128}$/.exec(subject)?.[0] !== subject) invalid();
    return Object.freeze({provider: 'privy', appId, subject});
  } catch {
    return invalid();
  }
}
