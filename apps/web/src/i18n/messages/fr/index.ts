import type {Catalog} from '../en';
import common from './common';
import shell from './shell';
import firstDay from './firstDay';
import recovery from './recovery';
import market from './market';
import career from './career';
import profile from './profile';
import money from './money';

export const AREAS = {common, shell, firstDay, recovery, market, career, profile, money} as const;
const catalog: Catalog = {...common, ...shell, ...firstDay, ...recovery, ...market, ...career, ...profile, ...money};
export default catalog;
