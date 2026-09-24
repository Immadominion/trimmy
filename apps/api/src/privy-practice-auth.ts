import { createPublicKey } from 'node:crypto';
import { createRequire } from 'node:module';
import { PracticeIdentityError, isPracticeAccessToken, isPracticeAppId, parsePracticeIdentity } from './practice-identity.js';
import type { PracticeIdentity, PracticeIdentityVerifier } from './practice-identity.js';

export interface PrivyPracticeIdentityOptions {
  readonly appId: string;
  /** Dashboard ES256 SPKI public key, not an application secret/private key. */
  readonly verificationKey: string;
}

interface SdkVerificationInput {
  readonly access_token: string;
  readonly app_id: string;
  readonly verification_key: string;
}
type SdkVerifier = (input: SdkVerificationInput) => Promise<unknown>;

function loadSdkVerifier(): SdkVerifier {
  // 0.34.0's published declarations refer to missing NullableHeaders and
  // HPKESender definitions and leak optional wallet-only viem types. Load its
  // supported CommonJS export at this one checked runtime boundary instead of
  // disabling project-wide declaration checks or adding unused wallet packages.
  const sdk: unknown = createRequire(import.meta.url)('@privy-io/node');
  if (sdk === null || (typeof sdk !== 'object' && typeof sdk !== 'function')) throw new Error('Missing verification SDK.');
  const method: unknown = (sdk as Record<string, unknown>)['verifyAccessToken'];
  if (typeof method !== 'function') throw new Error('Missing access-token verifier.');
  return async input => Reflect.apply(method, sdk, [input]) as unknown;
}

/**
 * Verification-only use of @privy-io/node 0.34.0. The exported SDK helper pins
 * ES256, JWT typ, issuer privy.io and this app's audience, verifies the signature
 * and expiry, and requires the access-token session claim. No user/wallet API or
 * remote key fetch is invoked with this explicitly configured public key.
 * https://github.com/privy-io/node-sdk/blob/main/src/lib/auth.ts
 * https://docs.privy.io/authentication/user-authentication/tokens
 * Static verification keys must be updated when the app's key rotates.
 * Token verification alone does not perform an online session-revocation check.
 */
export class PrivyPracticeIdentityVerifier implements PracticeIdentityVerifier {
  private readonly configuration: PrivyPracticeIdentityOptions | null;
  private readonly verifyWithSdk: SdkVerifier | null;

  constructor(options?: PrivyPracticeIdentityOptions) {
    if (options === undefined) {
      this.configuration = null;
      this.verifyWithSdk = null;
      return;
    }
    try {
      const appId = options.appId;
      const verificationKey = options.verificationKey;
      if (!isPracticeAppId(appId) ||
          typeof verificationKey !== 'string' || verificationKey.length > 16_384 ||
          !/^-----BEGIN PUBLIC KEY-----\r?\n[A-Za-z0-9+/=\r\n]+-----END PUBLIC KEY-----\r?\n?$/.test(verificationKey)) {
        throw new Error('Invalid verification configuration.');
      }
      const key = createPublicKey(verificationKey);
      if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
        throw new Error('Expected a P-256 public key.');
      }
      this.configuration = Object.freeze({appId, verificationKey});
      this.verifyWithSdk = loadSdkVerifier();
    } catch {
      throw new PracticeIdentityError('PRACTICE_IDENTITY_CONFIGURATION_INVALID', 'Practice identity verification is not configured correctly.');
    }
  }

  async verify(token: string): Promise<PracticeIdentity | null> {
    if (this.configuration === null || this.verifyWithSdk === null || !isPracticeAccessToken(token)) return null;
    try {
      const verified = await this.verifyWithSdk({
        access_token: token,
        app_id: this.configuration.appId,
        verification_key: this.configuration.verificationKey,
      });
      if (verified === null || typeof verified !== 'object' || Array.isArray(verified)) return null;
      const claims = verified as Record<string, unknown>;
      const now = Math.floor(Date.now() / 1000);
      // Check mandatory claims independently of optional JWT-library behavior.
      // The identity comes only from the SDK's verified result, never decoding
      // an unverified payload or trusting wallet/linked-account metadata.
      const issuedAt = claims['issued_at'];
      const expiration = claims['expiration'];
      const sessionId = claims['session_id'];
      if (claims['app_id'] !== this.configuration.appId || claims['issuer'] !== 'privy.io' ||
          typeof issuedAt !== 'number' || !Number.isSafeInteger(issuedAt) || issuedAt <= 0 || issuedAt > now ||
          typeof expiration !== 'number' || !Number.isSafeInteger(expiration) || expiration <= now || expiration <= issuedAt ||
          typeof sessionId !== 'string' || /^[A-Za-z0-9:_-]{1,256}$/.exec(sessionId)?.[0] !== sessionId) return null;
      return parsePracticeIdentity({provider: 'privy', appId: claims['app_id'], subject: claims['user_id']});
    } catch {
      // Invalid signatures, claims and SDK exceptions all fail closed. Do not
      // return/log raw exceptions, decoded claims, token text or key material.
      return null;
    }
  }
}
