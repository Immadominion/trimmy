/** Public retry bounds matching the fixed windows enforced by PostgreSQL. */
export const GUEST_RATE_WINDOW_SECONDS = Object.freeze({
  paperRead: 60,
  paperPreview: 600,
  paperCommit: 600,
  paperReset: 3600,
  profileRead: 60,
  profileWrite: 600,
  careerRead: 60,
  careerWrite: 600,
  refresh: 3600,
  claim: 3600,
});
