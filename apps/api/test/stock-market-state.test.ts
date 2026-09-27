import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { usMarketMoment, usTradingState, US_SESSIONS } from '../src/us-equity-calendar.js';
import type { UsSession } from '../src/us-equity-calendar.js';
import { OndoMarketStatusReader, parseOndoStatusPage } from '../src/ondo-market-status.js';
import type { OndoMarketStatus } from '../src/ondo-market-status.js';
import { StockMarketStates, StockMintPauseReader, stockMarketState } from '../src/stock-market-state.js';

const at = (iso: string) => Date.parse(iso);
const all = new Set<UsSession>(US_SESSIONS);
const fiveDay = new Set<UsSession>(['overnight', 'premarket', 'regular', 'postmarket']);
const regular = new Set<UsSession>(['regular']);
const iso = (value: number | null) => value === null ? null : new Date(value).toISOString();

describe('US session calendar', () => {
  it('follows Ondo sessions, pauses and weekends in New York time across daylight saving', () => {
    // Sunday afternoon: off-hours; 24/5 tokens open at 20:05 New York (00:05 UTC in summer).
    const sunday = at('2026-09-27T18:40:00Z');
    assert.equal(usMarketMoment(sunday).session, 'offhours');
    assert.equal(usTradingState(sunday, all).status, 'open');
    assert.equal(iso(usTradingState(sunday, fiveDay).nextOpenAt), '2026-09-28T00:05:00.000Z');
    assert.equal(iso(usTradingState(sunday, regular).nextOpenAt), '2026-09-28T13:31:00.000Z');
    // The 03:55 to 04:01 pause.
    const pause = at('2026-09-28T07:57:00Z');
    assert.deepEqual({...usMarketMoment(pause), changesAt: iso(usMarketMoment(pause).changesAt)},
      {session: null, gap: 'pause', changesAt: '2026-09-28T08:01:00.000Z'});
    assert.equal(usTradingState(pause, fiveDay).status, 'paused');
    assert.equal(usTradingState(pause, regular).status, 'closed');
    // Regular hours.
    const noon = at('2026-09-28T16:00:00Z');
    assert.deepEqual(usTradingState(noon, regular), {status: 'open', session: 'regular', nextOpenAt: null,
      closesAt: at('2026-09-28T19:59:00Z')});
    // Friday 20:06 New York: off-hours until Sunday's overnight session.
    const friday = at('2026-10-03T00:06:00Z');
    assert.equal(usTradingState(friday, all).status, 'open');
    assert.equal(iso(usTradingState(friday, fiveDay).nextOpenAt), '2026-10-05T00:05:00.000Z');
    // Winter time: 20:05 New York is 01:05 UTC.
    assert.equal(iso(usTradingState(at('2026-11-08T12:00:00Z'), fiveDay).nextOpenAt), '2026-11-09T01:05:00.000Z');
  });

  it('closes NYSE holidays and ends early-close days at 13:00 and 17:00', () => {
    // Thanksgiving: off-hours all day; the overnight session for Friday opens that evening.
    const thanksgiving = at('2026-11-26T15:00:00Z');
    assert.equal(usMarketMoment(thanksgiving).session, 'offhours');
    assert.equal(iso(usTradingState(thanksgiving, fiveDay).nextOpenAt), '2026-11-27T01:05:00.000Z');
    // The day after closes regular trading at 13:00 New York.
    const early = at('2026-11-27T18:30:00Z');
    assert.equal(usMarketMoment(early).session, 'postmarket');
    assert.equal(usTradingState(early, regular).status, 'closed');
    assert.equal(iso(usTradingState(early, regular).nextOpenAt), '2026-11-30T14:31:00.000Z');
    // Good Friday 2027 is closed.
    assert.equal(usMarketMoment(at('2027-03-26T15:00:00Z')).session, 'offhours');
  });
});

/** A status page shaped like Ondo's: the status JSON inside a Next.js flight string. */
function page(status: Record<string, unknown>, assets: unknown[] = [
  {symbol: 'NVDAon', tradableSessions: ['premarket', 'regular', 'postmarket', 'overnight', 'offhours']},
  {symbol: 'MXLon', tradableSessions: ['premarket', 'regular', 'postmarket', 'overnight']},
  {symbol: 'ABCon', tradableSessions: ['regular', 'lunch']},
]): string {
  const payload = `0:["$","div",null,{"children":${JSON.stringify({assets, marketStatus: status})}}]`;
  return `<html><script>self.__next_f.push([1,"a:I[1,[]]"])</script>` +
    `<script>self.__next_f.push([1,${JSON.stringify(payload)}])</script></html>`;
}
const weekend = {timestamp: '2026-09-27T18:33:47Z', isOpen: false, marketStatus: 'closed', nextOpenSession: 'overnight',
  nextOpen: '2026-09-28T00:05:00Z', nextClose: '2026-09-28T07:55:00Z',
  reason: {code: 'MARKET_CLOSED', message: 'Weekend or Holiday'},
  offhours: {isOpen: true, nextOpen: '2026-10-03T00:05:00Z', nextClose: '2026-09-27T23:55:00Z'}};

describe('Ondo live status', () => {
  it('parses market status and per-token sessions, ignoring sessions it does not know', () => {
    const status = parseOndoStatusPage(page(weekend), at('2026-09-27T18:35:00Z'));
    assert.ok(status);
    assert.equal(status.isOpen, false);
    assert.equal(status.reasonCode, 'MARKET_CLOSED');
    assert.equal(iso(status.nextOpen), '2026-09-28T00:05:00.000Z');
    assert.equal(status.offhoursOpen, true);
    assert.deepEqual([...status.sessions.get('NVDAon')!], ['premarket', 'regular', 'postmarket', 'overnight', 'offhours']);
    assert.deepEqual([...status.sessions.get('ABCon')!], ['regular']);
  });

  it('reads nothing from a stale, malformed or unexpected page', () => {
    const now = at('2026-09-27T18:35:00Z');
    assert.equal(parseOndoStatusPage(page(weekend), at('2026-09-27T19:00:00Z')), null);
    assert.equal(parseOndoStatusPage('<html>maintenance</html>', now), null);
    assert.equal(parseOndoStatusPage(page({...weekend, isOpen: 'no'}), now), null);
    assert.equal(parseOndoStatusPage(page(weekend, [{symbol: '<script>', tradableSessions: []}]), now), null);
    assert.equal(parseOndoStatusPage(page(weekend, [{symbol: 'A', tradableSessions: []}, {symbol: 'A', tradableSessions: []}]), now), null);
  });

  it('caches reads, keeps the last good status through failures and never throws', async () => {
    let calls = 0;
    let body: string | null = page(weekend);
    let now = at('2026-09-27T18:35:00Z');
    const reader = new OndoMarketStatusReader({now: () => now, ttlMs: 60_000, fetch: (async () => {
      calls += 1;
      if (body === null) throw new Error('offline');
      return new Response(body, {status: 200});
    }) as unknown as typeof fetch});
    assert.ok(await reader.read());
    assert.ok(await reader.read());
    assert.equal(calls, 1);
    now += 61_000;
    body = null;
    assert.ok(await reader.read(), 'the last good status is kept while fresh');
    assert.equal(calls, 2);
    now += 10 * 60_000;
    assert.equal(await reader.read(), null, 'too old to use');
  });
});

describe('stock market states', () => {
  const ondo = (overrides: Partial<OndoMarketStatus> = {}): OndoMarketStatus => ({
    observedAt: at('2026-09-27T18:35:00Z'), timestamp: at('2026-09-27T18:33:47Z'), isOpen: false, reasonCode: 'MARKET_CLOSED',
    nextOpen: at('2026-09-28T00:05:00Z'), offhoursOpen: true,
    sessions: new Map([['NVDAon', all], ['MXLon', fiveDay], ['RGon', regular]]), ...overrides,
  });
  const sunday = at('2026-09-27T18:40:00Z');

  it('keeps around-the-clock tokens open unless the issuer paused the mint', () => {
    assert.deepEqual(stockMarketState({issuerId: 'xstocks', symbol: 'AAPLx', now: sunday, mintPaused: false, ondo: null}), {
      hours: 'always', sessions: null, source: null, status: 'open', reason: null, session: null, nextOpenAt: null, closesAt: null});
    const paused = stockMarketState({issuerId: 'backpack', symbol: 'IBM', now: sunday, mintPaused: true, ondo: null});
    assert.equal(paused.status, 'paused');
    assert.equal(paused.reason, 'issuer_paused');
  });

  it('opens Ondo tokens only in their own sessions, with the next opening', () => {
    const open = stockMarketState({issuerId: 'ondo', symbol: 'NVDAon', now: sunday, mintPaused: false, ondo: ondo()});
    assert.equal(open.status, 'open');
    assert.equal(open.session, 'offhours');
    assert.equal(open.source, 'ondo_status');
    const closed = stockMarketState({issuerId: 'ondo', symbol: 'MXLon', now: sunday, mintPaused: false, ondo: ondo()});
    assert.deepEqual([closed.status, closed.reason, closed.nextOpenAt], ['closed', 'outside_sessions', '2026-09-28T00:05:00.000Z']);
    const regularOnly = stockMarketState({issuerId: 'ondo', symbol: 'RGon', now: sunday, mintPaused: false, ondo: ondo()});
    assert.equal(regularOnly.nextOpenAt, '2026-09-28T13:31:00.000Z');
    // Without Ondo's status, an unlisted token is assumed 24/5 from the calendar.
    const fallback = stockMarketState({issuerId: 'ondo', symbol: 'NEWon', now: sunday, mintPaused: null, ondo: null});
    assert.deepEqual([fallback.status, fallback.source, fallback.nextOpenAt], ['closed', 'calendar', '2026-09-28T00:05:00.000Z']);
  });

  it('follows Ondo when it pauses its market or closes off-hours trading', () => {
    const paused = stockMarketState({issuerId: 'ondo', symbol: 'MXLon', now: at('2026-09-28T16:00:00Z'), mintPaused: false,
      ondo: ondo({reasonCode: 'MARKET_PAUSED', isOpen: false, nextOpen: at('2026-09-28T16:30:00Z')})});
    assert.deepEqual([paused.status, paused.reason, paused.nextOpenAt], ['paused', 'market_paused', '2026-09-28T16:30:00.000Z']);
    const holiday = stockMarketState({issuerId: 'ondo', symbol: 'MXLon', now: at('2026-09-28T16:00:00Z'), mintPaused: false,
      ondo: ondo({isOpen: false, reasonCode: 'MARKET_CLOSED', offhoursOpen: false, nextOpen: at('2026-09-29T00:05:00Z')})});
    assert.deepEqual([holiday.status, holiday.nextOpenAt], ['closed', '2026-09-29T00:05:00.000Z']);
    const offhoursOff = stockMarketState({issuerId: 'ondo', symbol: 'NVDAon', now: sunday, mintPaused: false,
      ondo: ondo({offhoursOpen: false})});
    assert.equal(offhoursOff.status, 'closed');
  });

  it('reads mint pause flags in batches, keeping the last good read on failure', async () => {
    let calls = 0;
    const mint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
    let now = 0;
    const reader = new StockMintPauseReader({rpcUrl: 'https://rpc.example', now: () => now, fetch: (async () => {
      calls += 1;
      return new Response('{}', {status: 500});
    }) as unknown as typeof fetch});
    const states = new StockMarketStates({ondo: null, pauses: reader, mints: [mint], now: () => at('2026-09-27T18:40:00Z')});
    const stateOf = await states.snapshot();
    assert.equal(stateOf('xstocks', 'AAPLx', mint).status, 'open', 'an unreadable pause flag does not close a market');
    now += 1_000;
    await states.snapshot();
    assert.equal(calls, 1, 'failures are cached for the window too');
  });
});
