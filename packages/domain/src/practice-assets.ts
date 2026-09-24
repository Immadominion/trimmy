/** IDs for explicitly fictional web examples. Never a verified issuer catalog. */
export const PRACTICE_ASSET_IDS = Object.freeze([
  'forma', 'orbital', 'grove', 'harbor', 'mesa', 'nori', 'pollen', 'helios',
] as const);
export type PracticeAssetId = typeof PRACTICE_ASSET_IDS[number];
