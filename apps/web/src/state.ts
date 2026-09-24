import { DEFAULT_WATCHLIST, STOCKS, holdingValueCents } from './fixtures';
import type { Sector, Stock, WorkspaceView } from './fixtures';

export const STORAGE_KEY = 'trimmy.web.workspace.v1';
export interface SavedWorkspace {readonly version: 1; readonly watchlist: readonly string[]}
export type SortOrder = 'value' | 'name' | 'gainers' | 'price';
export interface StoragePort {getItem(key: string): string | null; setItem(key: string, value: string): void}
const knownIds = new Set<string>(STOCKS.map(stock => stock.id));
const defaults = (): SavedWorkspace => ({version: 1, watchlist: [...DEFAULT_WATCHLIST]});

export function decodeWorkspace(raw: string | null): {workspace: SavedWorkspace; recovered: boolean} {
  if (raw === null) return {workspace: defaults(), recovered: false};
  try {
    if (raw.length > 10_000) throw new Error('Too large');
    const decoded: unknown = JSON.parse(raw);
    if (typeof decoded !== 'object' || decoded === null || !('version' in decoded) || decoded.version !== 1 ||
        !('watchlist' in decoded) || !Array.isArray(decoded.watchlist) || decoded.watchlist.length > 100 ||
        !decoded.watchlist.every((id: unknown) => typeof id === 'string')) throw new Error('Invalid preferences');
    const ids = decoded.watchlist as string[];
    const validIds = [...new Set(ids.filter(id => knownIds.has(id)))];
    return {workspace: {version: 1, watchlist: validIds}, recovered: validIds.length !== ids.length};
  } catch {
    return {workspace: defaults(), recovered: true};
  }
}

export function loadWorkspace(storage: StoragePort | null): {workspace: SavedWorkspace; warning: string | null} {
  try {
    if (!storage) throw new Error('Storage unavailable');
    const result = decodeWorkspace(storage.getItem(STORAGE_KEY));
    return {workspace: result.workspace, warning: result.recovered ? 'Some saved preferences could not be loaded. Your watchlist has been repaired.' : null};
  } catch {
    return {workspace: defaults(), warning: 'Browser storage is unavailable. Watchlist changes will last for this session.'};
  }
}

export function saveWorkspace(storage: StoragePort | null, watchlist: readonly string[]): boolean {
  if (watchlist.some(id => !knownIds.has(id)) || new Set(watchlist).size !== watchlist.length) return false;
  try {
    if (!storage) return false;
    storage.setItem(STORAGE_KEY, JSON.stringify({version: 1, watchlist}));
    return true;
  } catch {return false;}
}

export function toggleWatchlist(watchlist: readonly string[], id: string): string[] {
  if (!knownIds.has(id)) throw new Error('Unknown practice asset');
  return watchlist.includes(id) ? watchlist.filter(item => item !== id) : [...watchlist, id];
}

export function visibleStocks(options: {view: WorkspaceView; watchlist: readonly string[]; query: string; sector: Sector | 'All sectors'; sort: SortOrder}): Stock[] {
  const query = options.query.trim().toLocaleLowerCase('en-US');
  return STOCKS.filter(stock => {
    const inView = options.view === 'portfolio' ? stock.quantityMilli > 0 : options.view === 'watchlist' ? options.watchlist.includes(stock.id) : true;
    const matchesSector = options.sector === 'All sectors' || stock.sector === options.sector;
    const matchesSearch = `${stock.name} ${stock.symbol} ${stock.sector}`.toLocaleLowerCase('en-US').includes(query);
    return inView && matchesSector && matchesSearch;
  }).sort((left, right) => {
    switch (options.sort) {
      case 'name': return left.name.localeCompare(right.name, 'en-US');
      case 'gainers': return right.dayChangeBps - left.dayChangeBps;
      case 'price': return right.priceCents - left.priceCents;
      case 'value': return holdingValueCents(right) - holdingValueCents(left) || left.name.localeCompare(right.name, 'en-US');
    }
  });
}
