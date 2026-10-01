/**
 * Catalog shapes. English (messages/en) is the source of truth: every other
 * language implements `Translation<typeof en area>`, so a missing or extra key
 * fails `npm run typecheck`. Every key in an area starts with that area's
 * prefix (`desk.`, `market.`), which keeps areas from overwriting each other
 * when they are merged.
 */
export type AreaMessages<Prefix extends string> = {readonly [Key in `${Prefix}.${string}`]: string};
export type Translation<Source> = {readonly [Key in keyof Source]: string};
