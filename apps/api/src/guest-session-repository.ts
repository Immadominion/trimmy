import type { PracticeIdentity } from './practice-identity.js';

/** Capabilities granted to an active guest credential. None can reach wallets or money execution. */
export type GuestPaperScope =
  | 'paper_read'
  | 'paper_preview'
  | 'paper_commit'
  | 'paper_reset'
  | 'profile_read'
  | 'profile_write'
  | 'career_read'
  | 'career_write';

export interface GuestSessionRecord {
  readonly guestId: string;
  readonly expiresAt: string;
  readonly hardExpiresAt: string;
}

export interface GuestCreationAdmission {
  readonly sourceHash: string;
  readonly attemptId: string;
}

export interface GuestAuthorization {
  readonly userId: string;
  readonly guestId: string;
  readonly expiresAt: string;
}

export interface GuestClaimResult {
  readonly guestId: string;
  readonly claimedAt: string;
}

export interface GuestSessionRepository {
  takeCreationAttempt(sourceHash: string): Promise<GuestCreationAdmission>;
  create(command: {
    readonly sourceHash: string;
    readonly attemptId: string;
    readonly requestHash: string;
    readonly replayHash: string;
    readonly guestId: string;
    readonly credentialHash: string;
  }): Promise<GuestSessionRecord>;
  authorize(credentialHash: string, scope: GuestPaperScope): Promise<GuestAuthorization>;
  refresh(credentialHash: string): Promise<GuestSessionRecord>;
  claim(command: {
    readonly credentialHash: string;
    readonly identity: PracticeIdentity;
    readonly idempotencyKey: string;
  }): Promise<GuestClaimResult>;
}

export type GuestSessionErrorCode =
  | 'GUEST_SESSION_UNAUTHENTICATED'
  | 'GUEST_SESSION_EXPIRED'
  | 'GUEST_SESSION_REVOKED'
  | 'GUEST_SESSION_RATE_LIMITED'
  | 'GUEST_SESSION_UNAVAILABLE'
  | 'GUEST_CLAIM_ACCOUNT_EXISTS'
  | 'GUEST_CLAIM_ALREADY_USED'
  | 'GUEST_CLAIM_IDEMPOTENCY_CONFLICT'
  | 'GUEST_SESSION_STORAGE_INVALID'
  | 'GUEST_SESSION_RUNTIME_ROLE_INVALID';

/** Safe public classification only. No token, provider payload or SQL detail. */
export class GuestSessionError extends Error {
  constructor(readonly code: GuestSessionErrorCode, message: string, readonly retryAfterSeconds?: number) {
    super(message);
    this.name = 'GuestSessionError';
  }
}
