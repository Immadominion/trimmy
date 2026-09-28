import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createElement, useEffect} from 'react';
import {FundWalletSheet} from '../src/product/money/fund-wallet-sheet.js';
import {LiveOrderPanel} from '../src/product/money/live-order-panel.js';
import {useMoney} from '../src/product/money/money-api.js';
import {RealBalanceCard, RealHoldings} from '../src/product/money/real-desk.js';
import {TradeHistoryScreen} from '../src/product/money/trade-history.js';
import {MarketScreen} from '../src/product/market-screen.js';
import {StockScreen} from '../src/product/stock-screen.js';
import {ProductMarketClient} from '../src/product/market-client.js';
import {searchFixture} from '../src/markets/fixtures.test-support.js';
import {moneyPage} from './support/money-dom.js';
import {liveCapabilitiesJson} from './support/money-harness.js';
import {ACCOUNT_ID, AAPLX, contextJson, holdingsJson, orderJson, stockHolding} from './support/money-fixtures.js';

const REAL_KEY = `trimmy.money-mode.v1.${encodeURIComponent('/api')}.${ACCOUNT_ID}`;
const apple = [{mint: AAPLX, liquidityUsd: 1_478_672}];

test('Add money offers crypto deposit as Recommended, card as Coming soon, and creates the one wallet first', async () => {
  const page = await moneyPage();
  let linked = false;
  page.privy.wallets = [];
  page.server.reply = call => call.path === '/v1/account/context' && !linked ? Response.json(contextJson(null)) : undefined;
  function Open() {const money = useMoney(); useEffect(() => {money.openFundWallet();}, []); return null;}
  try {
    await page.render(createElement(Open));
    await page.waitFor(() => /A wallet for your money/.test(page.text()), 'wallet setup');
    assert.match(page.text(), /Crypto\s*Recommended/); assert.match(page.text(), /Card\s*Coming soon/);
    assert.equal(page.dom.window.document.querySelector('.money-qr'), null, 'no address is shown before the server links a wallet');
    await page.click(/^Card/);
    assert.match(page.text(), /Card payments are coming soon\./);
    assert.equal(page.calls.some(call => call.path.startsWith('/v1/funding')), false, 'card funding never calls a funding route');
    await page.click('Use crypto');
    linked = true;
    await page.click('Create wallet');
    await page.waitFor(() => page.dom.window.document.querySelector('.money-qr') !== null, 'deposit QR');
    const address = page.user.address;
    assert.equal(page.dom.window.document.querySelector('.money-qr')?.getAttribute('aria-label'), `Solana deposit address ${address}`);
    assert.match(page.text(), /Send only USDC or SOL to this account on the Solana network\./);
    assert.ok(page.text().includes(`${address.slice(0, 4)}…${address.slice(-4)}`));
    await page.click('Copy address');
    assert.deepEqual(page.copied, [address]); assert.ok(page.button('Copied'));
    const fresh = page.calls.filter(call => call.path === '/v1/account/context').at(-1);
    assert.ok(fresh, 'the server link was checked after setup');
  } finally {await page.close();}
});

test('a guest asking to add money is sent to sign in, remembering the Real choice', async () => {
  const page = await moneyPage({signedIn: false});
  try {
    await page.render(createElement(FundWalletSheet, {onClose() {}}));
    assert.match(page.text(), /Sign in to create your own Solana wallet and add money\./);
    await page.click('Sign in');
    assert.equal(page.dom.window.location.hash, '#sign-in');
    assert.ok(page.dom.window.sessionStorage.getItem('trimmy.money.real-after-sign-in.v1'));
  } finally {await page.close();}
});

test('Real Home shows USDC cash first, SOL for fees, spendable versus total, and shares without an invented value', async () => {
  const page = await moneyPage();
  page.storage.data.set(REAL_KEY, 'real');
  page.server.reply = call => call.path === '/v1/account/holdings' ? Response.json(holdingsJson(page.user.address, {usdc: '30009999', usdcAvailable: '25000000',
    lamports: '21000000', tokens: [stockHolding({amountRaw: '250000000', availableToTradeRaw: '150000000', displayAmount: '2.502294', accountCount: 2,
      accountTopology: 'associated_with_ancillary'})]})) : undefined;
  try {
    await page.render(createElement('div', null, createElement(RealBalanceCard, {onSwitch() {}, onFastBuy() {}, onAddMoney() {}}),
      createElement(RealHoldings, {identities: new Map(), onOpen() {}, onExplore() {}, onAddMoney() {}, onHistory() {}})));
    await page.waitFor(() => /\$30\.00/.test(page.text()), 'cash balance');
    const card = page.dom.window.document.querySelector('.real-balance')!.textContent ?? '';
    assert.match(card, /Cash balance/); assert.match(card, /USDC available/); assert.match(card, /0\.021 SOL for fees/);
    assert.match(card, /25 USDC is ready to trade\. The rest is in another token account\./);
    assert.ok(page.button('Switch to paper mode'), 'the switch names the other mode');
    const row = page.dom.window.document.querySelector('.real-holdings .position-row')!.textContent ?? '';
    assert.match(row, /SpaceX xStock/); assert.match(row, /2\.502294 SPCXx/); assert.match(row, /ready to sell/); assert.match(row, /Value unavailable/);
  } finally {await page.close();}
});

test('the order panel shows the issuer warning before the tick, and the review shows warning, terms, fees and expiry before Confirm', async () => {
  const page = await moneyPage();
  page.storage.data.set(REAL_KEY, 'real');
  page.server.settle.push('pending', 'confirmed');
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'apple', mint: AAPLX, companyName: 'Apple', discovery: apple}));
    await page.waitFor(() => /Buy AAPLx/.test(page.text()), 'order entry');
    const doc = page.dom.window.document;
    const warning = doc.querySelector('.issuer-card .issuer-warning'), tick = doc.querySelector('.issuer-tick');
    assert.ok(warning && tick && warning.compareDocumentPosition(tick) & page.dom.window.Node.DOCUMENT_POSITION_FOLLOWING, 'warning comes before the tick');
    assert.match(page.text(), /Open 24\/7|Order limit: 100 USDC/);
    assert.equal(page.button('Review buy')?.disabled, true, 'no review before the issuer terms are ticked');
    await page.tick();
    await page.waitFor(() => page.button('Review buy')?.disabled === false, 'review enabled');
    await page.click('Review buy');
    await page.waitFor(() => /Review your buy/.test(page.text()), 'review');
    const review = doc.querySelector('.trade-panel.live')!;
    const reviewWarning = review.querySelector('.issuer-warning.review'), summary = review.querySelector('.review-summary');
    assert.ok(reviewWarning && summary && reviewWarning.compareDocumentPosition(summary) & page.dom.window.Node.DOCUMENT_POSITION_FOLLOWING, 'warning first');
    for (const line of ['You pay5 USDC', 'Minimum received', 'Network + account fees≤ 0.00204428 SOL', 'Swap fee0.2%', 'IssuerxStocks']) {
      assert.ok(review.textContent?.includes(line), `review shows ${line}`);
    }
    assert.match(review.textContent ?? '', /Quote expires in \d+s/);
    await page.click('Confirm buy');
    await page.waitFor(() => /Trade confirmed/.test(page.text()), 'confirmation');
    const link = doc.querySelector<HTMLAnchorElement>('a[href^="https://solscan.io/"]');
    assert.equal(link?.textContent, 'View transaction ↗'); assert.match(link!.href, /^https:\/\/solscan\.io\/tx\/[1-9A-HJ-NP-Za-km-z]{64,88}$/);
    assert.equal(page.calls.filter(call => call.path === '/v1/trading/execute').length, 1);
  } finally {await page.close();}
});

test('an RFQ review says the price is a market maker’s fixed quote delivered at fill, and the result links wallet activity', async () => {
  const page = await moneyPage({route: 'rfq'});
  page.storage.data.set(REAL_KEY, 'real');
  page.server.settle.push('confirmed');
  const meta = 'fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo';
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'meta', mint: meta, companyName: 'Meta', discovery: [{mint: meta}]}));
    await page.waitFor(() => /Buy METAon/.test(page.text()), 'order entry');
    assert.match(page.text(), /Open now, including weekends/); assert.match(page.text(), /Orders start at 2 USDC\./);
    await page.tick();
    await page.type('#live-amount', '1');
    await page.click('Review buy');
    assert.match(page.text(), /Orders for this token start at 2 USDC\./);
    assert.equal(page.calls.some(call => call.path === '/v1/trading/preview'), false);
    await page.type('#live-amount', '2');
    await page.click('Review buy');
    await page.waitFor(() => /Review your buy/.test(page.text()), 'review');
    assert.match(page.text(), /PriceFixed quote from a market maker/); assert.match(page.text(), /DeliveryBy the market maker at fill/);
    assert.match(page.dom.window.document.querySelector('[data-testid="live-order-settlement"]')?.textContent ?? '', /all or nothing/);
    await page.click('Confirm buy');
    await page.waitFor(() => /Trade confirmed/.test(page.text()), 'confirmation');
    const link = page.dom.window.document.querySelector<HTMLAnchorElement>('a[href^="https://solscan.io/"]');
    assert.equal(link?.textContent, 'View wallet activity ↗'); assert.equal(link?.href, `https://solscan.io/account/${page.user.address}`);
  } finally {await page.close();}
});

const META = 'fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo';
function metaMarket(market: Record<string, unknown>) {
  const json = liveCapabilitiesJson() as {assets: Record<string, unknown>[]};
  return {...json, assets: json.assets.map(asset => asset['mint'] === META ? {...asset, market: {...asset['market'] as object, ...market}} : asset)};
}

test('ordering is disabled while a token’s market is closed, and says when it opens in local time', async () => {
  const page = await moneyPage({route: 'rfq'});
  page.storage.data.set(REAL_KEY, 'real');
  const opens = new Date(Date.now() + 3 * 86_400_000);
  opens.setHours(1, 5, 0, 0);
  page.server.reply = call => call.path.startsWith('/v1/trading/capabilities') ? Response.json(metaMarket({status: 'closed', reason: 'outside_sessions',
    sessions: ['overnight', 'premarket', 'regular', 'postmarket'], nextOpenAt: opens.toISOString()})) : undefined;
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'meta', mint: META, companyName: 'Meta', discovery: [{mint: META}]}));
    await page.waitFor(() => /Closed · opens/.test(page.text()), 'closed state');
    const label = `Closed · opens ${['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][opens.getDay()]} 1:05 AM`;
    assert.ok(page.text().includes(label));
    const review = page.dom.window.document.querySelector<HTMLButtonElement>('.live-action');
    assert.equal(review?.disabled, true); assert.equal(review?.textContent, label);
    assert.match(page.text(), /Trades 24 hours a day, Sunday evening to Friday evening \(US Eastern\)\./);
    await page.tick();
    assert.equal(page.dom.window.document.querySelector<HTMLButtonElement>('.live-action')?.disabled, true, 'the tick does not open a closed market');
    assert.equal(page.calls.some(call => call.path === '/v1/trading/preview'), false);
  } finally {await page.close();}
});

test('an issuer pause disables ordering and says so', async () => {
  const page = await moneyPage({route: 'rfq'});
  page.storage.data.set(REAL_KEY, 'real');
  page.server.reply = call => call.path.startsWith('/v1/trading/capabilities') ? Response.json(metaMarket({status: 'paused', reason: 'issuer_paused', nextOpenAt: null})) : undefined;
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'meta', mint: META, companyName: 'Meta', discovery: [{mint: META}]}));
    await page.waitFor(() => /Paused by the issuer/.test(page.text()), 'paused state');
    assert.equal(page.dom.window.document.querySelector<HTMLButtonElement>('.live-action')?.disabled, true);
  } finally {await page.close();}
});

test('a refusal under the market maker’s minimum reads as BELOW_MINIMUM, not a closed market', async () => {
  const page = await moneyPage({route: 'rfq'});
  page.storage.data.set(REAL_KEY, 'real');
  const meta = 'fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo';
  page.server.reply = call => call.path === '/v1/trading/preview' ? Response.json({code: 'BELOW_MINIMUM'}, {status: 409}) : undefined;
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'meta', mint: meta, companyName: 'Meta', discovery: [{mint: meta}]}));
    await page.waitFor(() => /Buy METAon/.test(page.text()), 'order entry');
    await page.tick(); await page.type('#live-amount', '2'); await page.click('Review buy');
    await page.waitFor(() => /under the market maker’s minimum/.test(page.text()), 'refusal');
    assert.doesNotMatch(page.text(), /US markets are open/);
  } finally {await page.close();}
});

test('without a wallet the order panel asks to create one through Add money', async () => {
  const page = await moneyPage();
  page.storage.data.set(REAL_KEY, 'real');
  page.server.reply = call => call.path === '/v1/account/context' ? Response.json(contextJson(null)) : undefined;
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'apple', mint: AAPLX, companyName: 'Apple', discovery: apple}));
    await page.waitFor(() => /Create your wallet to continue\./.test(page.text()), 'wallet prompt');
    assert.equal(page.button('Review buy'), undefined);
    await page.click('Add money');
    await page.waitFor(() => /A wallet for your money/.test(page.text()), 'fund sheet');
  } finally {await page.close();}
});

test('the Real Market marks tradeable companies without a separate Tradeable list', async () => {
  const market = await moneyPage();
  market.storage.data.set(REAL_KEY, 'real');
  const discovery = searchFixture('catalog', 20);
  const now = new Date().toISOString(), later = new Date(Date.now() + 30_000).toISOString();
  market.server.reply = call => {
    if (!call.path.startsWith('/v1/markets/stocks/catalog')) return undefined;
    const cards = discovery.results.map(row => ({assetId: row.assetId, name: row.name, symbol: row.symbol, imageUrl: null, stock: null, primaryVariant: null}));
    return Response.json({discovery: {...discovery, requestedAt: now, observedAt: now, refreshAfter: later}, cards, offset: 0, total: cards.length, nextOffset: null});
  };
  try {
    const client = new ProductMarketClient({baseUrl: '/api', fetch: market.fetch, timeoutMs: 1000});
    function RealMarket() {const money = useMoney(); return createElement(MarketScreen, {client, onSelect() {}, real: money.real, capabilities: money.capabilities});}
    await market.render(createElement(RealMarket));
    await market.waitFor(() => market.all('[data-testid="market-tradeable-apple"]').length === 1, 'Apple marker');
    assert.equal(market.dom.window.document.querySelector('.market-lists'), null, 'no Tradeable tab: every listed company can be bought');
    const paper = await moneyPage();
    try {
      const paperClient = new ProductMarketClient({baseUrl: '/api', fetch: market.fetch, timeoutMs: 1000});
      await paper.render(createElement(MarketScreen, {client: paperClient, onSelect() {}}));
      await paper.waitFor(() => paper.all('.stock-row').length > 0, 'paper market');
      assert.equal(paper.all('[data-testid^="market-tradeable-"]').length, 0, 'Paper never claims anything is tradeable');
      assert.equal(paper.dom.window.document.querySelector('.market-lists'), null);
    } finally {await paper.close();}
  } finally {await market.close();}
});

test('history pages real orders, reconciles pending ones by id and links each to the explorer', async () => {
  const page = await moneyPage();
  const row = (id: string, status: string, rfq = false) => ({id, wallet: page.user.address, status, signature: `${id.slice(-1)}`.repeat(88),
    createdAt: '2026-09-27T10:00:00.123456Z', updatedAt: '2026-09-27T10:00:01.123456Z',
    asset: {assetId: rfq ? 'meta' : 'apple', mint: rfq ? 'fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo' : AAPLX, symbol: rfq ? 'METAon' : 'AAPLx',
      name: rfq ? 'Meta Platforms (Ondo Tokenized)' : 'Apple xStock', decimals: rfq ? 9 : 8, route: rfq ? 'rfq' : 'aggregator'},
    terms: {side: 'buy', inputMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', outputMint: rfq ? 'fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo' : AAPLX,
      inputAmountRaw: '5000000', quotedOutputAmountRaw: '1960000', minimumOutputAmountRaw: '1950000'},
    amountUnits: 'raw_token_units', amountsStatus: 'reviewed_quote'});
  let settled = false, allowSettle = false;
  page.server.reply = call => {
    if (call.path === '/v1/trading/history?limit=20') return Response.json({schemaVersion: 1, network: 'solana:mainnet-beta',
      orders: [row('55555555-5555-4555-8555-555555555551', settled ? 'confirmed' : 'pending', true), row('55555555-5555-4555-8555-555555555552', 'failed')], nextCursor: 'older'});
    if (call.path === '/v1/trading/history?limit=20&cursor=older') return Response.json({schemaVersion: 1, network: 'solana:mainnet-beta',
      orders: [row('55555555-5555-4555-8555-555555555553', 'expired')], nextCursor: null});
    if (call.path === '/v1/trading/order/55555555-5555-4555-8555-555555555551') {
      if (!allowSettle) return Response.json({order: orderJson({id: '55555555-5555-4555-8555-555555555551', wallet: page.user.address, status: 'pending',
        signature: '1'.repeat(88), mint: 'fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo', route: 'rfq'})});
      settled = true;
      return Response.json({order: orderJson({id: '55555555-5555-4555-8555-555555555551', wallet: page.user.address, status: 'confirmed',
        signature: '1'.repeat(88), mint: 'fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo', route: 'rfq'})});
    }
    return undefined;
  };
  try {
    await page.render(createElement(TradeHistoryScreen, {onBack() {}, pollMs: 20}));
    await page.waitFor(() => /Buy METAon/.test(page.text()), 'history rows');
    assert.match(page.text(), /Confirming/); assert.match(page.text(), /Not completed/);
    allowSettle = true;
    await page.waitFor(() => /Confirmed/.test(page.text()) && !/Confirming/.test(page.text()), 'pending reconciled by id');
    assert.equal(page.calls.some(call => call.path === '/v1/trading/execute'), false, 'reconciling never dispatches');
    await page.click(/Buy METAon/);
    const link = page.dom.window.document.querySelector<HTMLAnchorElement>('.history-links a');
    assert.equal(link?.textContent, 'View wallet activity ↗'); assert.equal(link?.href, `https://solscan.io/account/${page.user.address}`);
    assert.match(page.text(), /Order estimates\. See the transaction for the final amounts\./);
    await page.click('More trades');
    await page.waitFor(() => /Expired/.test(page.text()), 'older page');
    assert.equal(page.button('More trades'), undefined);
  } finally {await page.close();}
});

test('under StrictMode the wallet and the order session survive React’s double mount through to confirmation', async () => {
  const page = await moneyPage({strict: true});
  page.storage.data.set(REAL_KEY, 'real');
  page.server.settle.push('confirmed');
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'apple', mint: AAPLX, companyName: 'Apple', discovery: apple}));
    await page.waitFor(() => /25 USDC available/.test(page.text()), 'entry with a fresh balance');
    await page.tick(); await page.click('Review buy');
    await page.waitFor(() => /Review your buy/.test(page.text()), 'review');
    await page.click('Confirm buy');
    await page.waitFor(() => /Trade confirmed/.test(page.text()), 'confirmation');
    assert.equal(page.calls.filter(call => call.path === '/v1/trading/execute').length, 1);
  } finally {await page.close();}
});

test('sells carry no per-token cap: no limit line, and Max offers the whole spendable balance', async () => {
  const page = await moneyPage();
  page.storage.data.set(REAL_KEY, 'real');
  page.server.reply = call => call.path === '/v1/account/holdings' ? Response.json(holdingsJson(page.user.address, {
    tokens: [stockHolding({assetId: 'apple', name: 'Apple xStock', symbol: 'AAPLx', mint: AAPLX, amountRaw: '250000000000', availableToTradeRaw: '250000000000',
      displayAmount: '2500', displayResolution: 'rpc_ui_amount'})]})) : undefined;
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'apple', mint: AAPLX, companyName: 'Apple', discovery: apple, initialSide: 'sell'}));
    await page.waitFor(() => /Sell AAPLx/.test(page.text()) && /2,500 AAPLx available/.test(page.text()), 'sell entry');
    assert.doesNotMatch(page.text(), /Order limit/, 'no sell limit line under schema 3');
    await page.click('Max');
    assert.equal(page.dom.window.document.querySelector<HTMLInputElement>('#live-amount')?.value, '2500', 'Max is the whole spendable balance');
    assert.doesNotMatch(page.text(), /capped at the order limit/);
    await page.click('Buy instead');
    await page.waitFor(() => /Order limit: 100 USDC/.test(page.text()), 'buy limit');
  } finally {await page.close();}
});

test('opening a company rereads the token list, so a token missing from a stale list becomes tradeable', async () => {
  const page = await moneyPage();
  page.storage.data.set(REAL_KEY, 'real');
  let reads = 0;
  const full = liveCapabilitiesJson() as {assets: {assetId: string}[]};
  const variants = JSON.parse(readFileSync(new URL('./fixtures/market-variants-apple-2026-09-27.json', import.meta.url), 'utf8')) as unknown;
  page.server.reply = call => {
    if (call.path.startsWith('/v1/trading/capabilities')) {
      reads++;
      // Right after an API restart the list is short: the first read lacks Apple.
      return Response.json(reads === 1 ? {...full, assets: full.assets.filter(asset => asset.assetId !== 'apple')} : full);
    }
    if (call.path.startsWith('/v1/markets/stocks/variants')) return Response.json(variants);
    if (call.path.startsWith('/v1/markets/stocks/')) return Response.json({error: {code: 'STOCK_FACTS_UNAVAILABLE', message: 'Not in this test.', requestId: 'r'}}, {status: 503});
    return undefined;
  };
  const market = new ProductMarketClient({baseUrl: '/api', fetch: page.fetch, timeoutMs: 1000});
  try {
    await page.render(createElement('div'));
    await page.waitFor(() => reads === 1, 'the first (stale) read');
    await page.flush(30);
    await page.render(createElement(StockScreen, {assetId: 'apple', selectedMint: AAPLX, market, session: {} as never, portfolio: null,
      onBack() {}, onDesk() {}, ensureDesk: async () => {}, onCommitted: async () => {}, onPending() {}}));
    await page.waitFor(() => /Buy AAPLx/.test(page.text()), 'the corrected list');
    assert.equal(reads, 2, 'the company page read the list again');
    assert.match(page.text(), /xStocks · AAPLx\s*Tradeable/);
  } finally {await page.close();}
});

test('a token the API does not qualify on the spot is explained, and the list is read again', async () => {
  const page = await moneyPage();
  page.storage.data.set(REAL_KEY, 'real');
  let reads = 0;
  page.server.reply = call => {
    if (call.path.startsWith('/v1/trading/capabilities')) {reads++; return undefined;}
    return call.path === '/v1/trading/preview' ? Response.json({code: 'MARKET_INPUT_INVALID'}, {status: 400}) : undefined;
  };
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'apple', mint: AAPLX, companyName: 'Apple', discovery: apple}));
    await page.waitFor(() => /Buy AAPLx/.test(page.text()), 'entry');
    const before = reads;
    await page.tick(); await page.click('Review buy');
    await page.waitFor(() => /Trimmy can’t trade this token right now\. Choose another version or company\./.test(page.text()), 'refusal copy');
    await page.waitFor(() => reads > before, 'the list read again');
  } finally {await page.close();}
});
