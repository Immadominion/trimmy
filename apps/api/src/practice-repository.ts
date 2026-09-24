import { parsePracticeProgress } from '@trimmy/domain';
import type { PracticeProgress } from '@trimmy/domain';

export interface PracticeSnapshot {
  readonly revision: number;
  readonly progress: PracticeProgress | null;
  readonly updatedAt: string | null;
}

export interface PracticeWrite {
  readonly mutationId: string;
  readonly baseRevision: number;
  readonly progress: PracticeProgress;
}

export interface PracticeRepository {
  get(userId: string): Promise<PracticeSnapshot>;
  put(userId: string, command: PracticeWrite): Promise<PracticeSnapshot>;
}

export type PracticeRepositoryErrorCode =
  | 'PRACTICE_INVALID_INPUT'
  | 'PRACTICE_ACCOUNT_NOT_FOUND'
  | 'PRACTICE_IDEMPOTENCY_CONFLICT'
  | 'PRACTICE_REVISION_CONFLICT'
  | 'PRACTICE_HISTORY_CONFLICT'
  | 'PRACTICE_VERSION_DOWNGRADE'
  | 'PRACTICE_REVISION_EXHAUSTED'
  | 'PRACTICE_STORAGE_INVALID'
  | 'PRACTICE_RUNTIME_ROLE_INVALID';

/** Safe messages only; database errors and stored payloads are never attached. */
export class PracticeRepositoryError extends Error {
  constructor(
    readonly code: PracticeRepositoryErrorCode,
    message: string,
    readonly currentSnapshot?: PracticeSnapshot,
  ) {
    super(message);
    this.name = 'PracticeRepositoryError';
  }
}

export const EMPTY_PRACTICE_SNAPSHOT: PracticeSnapshot = Object.freeze({
  revision: 0, progress: null, updatedAt: null,
});

function invalid(): never {
  throw new PracticeRepositoryError('PRACTICE_INVALID_INPUT', 'Practice request is invalid.');
}

/** PostgreSQL UUID identity, normalized before hashing or acquiring locks. */
export function parsePracticeUserId(input: unknown): string {
  if (typeof input !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input)) invalid();
  return input.toLowerCase();
}

/** Direct repository callers receive the same validation as HTTP callers. */
export function parsePracticeWrite(input: unknown): PracticeWrite {
  try {
    if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
    const prototype: unknown = Object.getPrototypeOf(input);
    if (prototype !== Object.prototype && prototype !== null) invalid();
    const keys = Reflect.ownKeys(input);
    if (keys.length !== 3 || keys.some(key => typeof key !== 'string' || !['mutationId', 'baseRevision', 'progress'].includes(key))) invalid();
    const values: Record<string, unknown> = {};
    for (const key of keys) {
      const descriptor = Object.getOwnPropertyDescriptor(input, key);
      if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
      values[key as string] = descriptor.value;
    }
    const mutationId = parsePracticeUserId(values['mutationId']);
    const baseRevision = values['baseRevision'];
    if (typeof baseRevision !== 'number' || !Number.isSafeInteger(baseRevision) || baseRevision < 0) invalid();
    return Object.freeze({mutationId, baseRevision, progress: parsePracticeProgress(values['progress'])});
  } catch {
    return invalid();
  }
}
