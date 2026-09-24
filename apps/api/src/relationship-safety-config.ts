/**
 * Social activation is deliberately opt in. An absent value has the same
 * meaning as `false`, while every other spelling fails startup rather than
 * silently widening relationship authority.
 */
export function readRelationshipSafetyEnabled(
  env: Readonly<Record<string, string | undefined>>,
): boolean {
  const value = env['TRIMMY_RELATIONSHIP_SAFETY_ENABLED'];
  if (value === undefined || value === '' || value === 'false') return false;
  if (value === 'true') return true;
  throw new Error('TRIMMY_RELATIONSHIP_SAFETY_ENABLED must be true or false.');
}

export type RelationshipSafetyReadiness = () => Promise<boolean>;
export const DEFAULT_RELATIONSHIP_MODERATION_ROLE = 'trimmy_social_moderator';

export function parseRelationshipModerationRole(value: unknown): string {
  if (typeof value !== 'string' || !/^[a-z_][a-z0-9_]{0,62}$/u.test(value)) {
    throw new Error('TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE is invalid.');
  }
  return value;
}

export function readRelationshipModerationRole(
  env: Readonly<Record<string, string | undefined>>,
): string {
  return parseRelationshipModerationRole(
    env['TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE'] || DEFAULT_RELATIONSHIP_MODERATION_ROLE,
  );
}

/**
 * Configuration never proves deployment readiness by itself. Until a caller
 * supplies a live readiness proof, social activation remains unavailable.
 */
export async function relationshipSafetyAvailable(
  enabled: boolean,
  readiness?: RelationshipSafetyReadiness,
): Promise<boolean> {
  if (!enabled || !readiness) return false;
  try { return await readiness() === true; }
  catch { return false; }
}
