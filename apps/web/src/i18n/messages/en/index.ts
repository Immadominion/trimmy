/**
 * The English catalog, the source of truth for every key. It ships with the
 * app; other languages load as their own chunks (see ../../runtime.ts).
 */
import common from './common';
import shell from './shell';
import firstDay from './firstDay';
import recovery from './recovery';
import market from './market';
import career from './career';
import profile from './profile';
import money from './money';

export const en = {...common, ...shell, ...firstDay, ...recovery, ...market, ...career, ...profile, ...money} as const;
export const AREAS = {common, shell, firstDay, recovery, market, career, profile, money} as const;
export type MessageKey = keyof typeof en;
/** A full catalog: every English key, each language's own text. */
export type Catalog = {readonly [Key in MessageKey]: string};
