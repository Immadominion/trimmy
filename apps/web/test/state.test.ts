import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { PRACTICE_ASSET_IDS } from '@trimmy/domain';
import { CHART_RANGES, DEFAULT_WATCHLIST, STOCKS, chartSeries, holdingValueCents, portfolioSeries } from '../src/fixtures';
import { STORAGE_KEY, decodeWorkspace, loadWorkspace, saveWorkspace, toggleWatchlist, visibleStocks } from '../src/state';
import type { StoragePort } from '../src/state';

const options = {view: 'explore' as const, watchlist: [], query: '', sector: 'All sectors' as const, sort: 'name' as const};
describe('web workspace state', () => {
  it('uses exactly the fictional IDs accepted by account watchlist sync', () => {
    assert.deepEqual(STOCKS.map(stock => stock.id), PRACTICE_ASSET_IDS);
  });
  it('loads a deliberate sample watchlist only when no saved state exists', () => {
    assert.deepEqual(decodeWorkspace(null), {workspace: {version: 1, watchlist: [...DEFAULT_WATCHLIST]}, recovered: false});
    assert.deepEqual(decodeWorkspace('{"version":1,"watchlist":[]}'), {workspace: {version: 1, watchlist: []}, recovered: false});
  });
  it('validates version, shape, types and payload size before accepting browser data', () => {
    for (const invalid of ['bad json', 'null', '[]', '{}', '{"version":2,"watchlist":[]}', '{"version":1,"watchlist":[null]}', ' '.repeat(10001)]) {
      const decoded = decodeWorkspace(invalid);
      assert.equal(decoded.recovered, true);
      assert.deepEqual(decoded.workspace.watchlist, DEFAULT_WATCHLIST);
    }
  });
  it('removes unknown assets and duplicates while preserving supported selections', () => {
    assert.deepEqual(decodeWorkspace('{"version":1,"watchlist":["forma","script","forma","grove"]}'), {workspace: {version: 1, watchlist: ['forma', 'grove']}, recovered: true});
  });
  it('persists and reloads additions, removals and a genuinely empty watchlist', () => {
    let saved: string | null = null;
    const storage: StoragePort = {getItem: key => {assert.equal(key, STORAGE_KEY); return saved;}, setItem: (key, value) => {assert.equal(key, STORAGE_KEY); saved = value;}};
    const afterAdd = toggleWatchlist([], 'forma');
    assert.equal(saveWorkspace(storage, afterAdd), true);
    assert.deepEqual(loadWorkspace(storage).workspace.watchlist, ['forma']);
    assert.equal(saveWorkspace(storage, toggleWatchlist(afterAdd, 'forma')), true);
    assert.deepEqual(loadWorkspace(storage).workspace.watchlist, []);
  });
  it('keeps usable session state when storage access or quota fails', () => {
    const storage: StoragePort = {getItem: () => {throw new Error('denied');}, setItem: () => {throw new Error('quota');}};
    assert.ok(loadWorkspace(storage).warning);
    assert.deepEqual(loadWorkspace(storage).workspace.watchlist, DEFAULT_WATCHLIST);
    assert.equal(saveWorkspace(storage, ['forma']), false);
    assert.equal(saveWorkspace(null, ['forma']), false);
    assert.equal(saveWorkspace(storage, ['unknown']), false);
  });
  it('does not mutate the old state when toggling, and rejects unknown assets', () => {
    const original = ['forma'];
    assert.deepEqual(toggleWatchlist(original, 'grove'), ['forma', 'grove']);
    assert.deepEqual(original, ['forma']);
    assert.throws(() => toggleWatchlist(original, '<script>'));
  });
  it('searches names, symbols and sectors case-insensitively with trimming', () => {
    assert.deepEqual(visibleStocks({...options, query: '  fRmA '}).map(stock => stock.id), ['forma']);
    assert.deepEqual(visibleStocks({...options, query: 'orbital'}).map(stock => stock.id), ['orbital']);
    assert.equal(visibleStocks({...options, query: 'energy'}).length, 2);
    assert.equal(visibleStocks({...options, query: '<script>alert(1)</script>'}).length, 0);
  });
  it('combines view membership, sector and search filters', () => {
    assert.equal(visibleStocks({...options, view: 'portfolio'}).length, 5);
    assert.equal(visibleStocks({...options, view: 'watchlist', watchlist: []}).length, 0);
    assert.deepEqual(visibleStocks({...options, view: 'watchlist', watchlist: ['forma', 'grove'], sector: 'Technology'}).map(stock => stock.id), ['forma']);
    assert.equal(visibleStocks({...options, view: 'portfolio', query: 'pollen'}).length, 0);
  });
  it('sorts by gain, price or held market value without mutating fixtures', () => {
    const idsBefore = STOCKS.map(stock => stock.id);
    assert.equal(visibleStocks({...options, sort: 'gainers'})[0]?.id, 'pollen');
    assert.equal(visibleStocks({...options, sort: 'price'})[0]?.id, 'orbital');
    assert.equal(visibleStocks({...options, sort: 'value'})[0]?.id, 'forma');
    assert.deepEqual(STOCKS.map(stock => stock.id), idsBefore);
  });
});

describe('fictional chart and position consistency', () => {
  it('provides distinct range histories ending at each stock’s displayed price', () => {
    for (const stock of STOCKS) {
      const starts = new Set<number>();
      for (const range of CHART_RANGES) {
        const points = chartSeries(stock, range);
        assert.equal(points.length, 24);
        assert.equal(points.at(-1)?.valueCents, stock.priceCents);
        assert.ok(points.every(point => Number.isSafeInteger(point.valueCents) && point.valueCents > 0 && point.label.length > 0));
        starts.add(points[0]!.valueCents);
      }
      assert.equal(starts.size, CHART_RANGES.length);
    }
  });
  it('makes daily chart direction and displayed daily change agree', () => {
    for (const stock of STOCKS) {
      const points = chartSeries(stock, '1D');
      const delta = points.at(-1)!.valueCents - points[0]!.valueCents;
      assert.equal(Math.sign(delta), Math.sign(stock.dayChangeBps));
    }
  });
  it('reconciles the portfolio endpoint with exactly the displayed positions', () => {
    const total = STOCKS.reduce((sum, stock) => sum + holdingValueCents(stock), 0);
    for (const range of CHART_RANGES) assert.equal(portfolioSeries(range).at(-1)?.valueCents, total);
    assert.equal(total, 2_282_644);
  });
});
