import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement, useEffect} from 'react';
import {loadCatalog, setLocale, t} from '../src/i18n/runtime.js';
import {messageArguments, messageTags, parseMessage, type MessagePart} from '../src/i18n/icu.js';
import {en} from '../src/i18n/messages/en/index.js';
import enMoney from '../src/i18n/messages/en/money.js';
import {LOCALES, type Locale} from '../src/i18n/locales.js';
import {LiveOrderPanel} from '../src/product/money/live-order-panel.js';
import {FastBuySheet} from '../src/product/money/fast-buy-sheet.js';
import {FundWalletSheet} from '../src/product/money/fund-wallet-sheet.js';
import {RealBalanceCard, RealHoldings} from '../src/product/money/real-desk.js';
import {TradeHistoryScreen} from '../src/product/money/trade-history.js';
import {ProductMarketClient} from '../src/product/market-client.js';
import {useMoney} from '../src/product/money/money-api.js';
import {liveOrderMessage} from '../src/product/money/live-order-client.js';
import {marketLabel, marketTime, parseMarketState} from '../src/product/money/live-trading.js';
import {transferMessage} from '../src/product/money/wallet-transfer-client.js';
import {findLeaks} from './support/i18n-leaks.js';
import {moneyPage} from './support/money-dom.js';
import {AAPLX, ACCOUNT_ID, holdingsJson, message, stockHolding, unsigned} from './support/money-fixtures.js';
import {apiVerifier, liveCapabilitiesJson} from './support/money-harness.js';

const {buildSendReview} = await import(new URL('../../../tool/testing/client-send-fixtures.mjs', import.meta.url).href);

const NBSP = ' ';
const REAL_KEY = `trimmy.money-mode.v1.${encodeURIComponent('/api')}.${ACCOUNT_ID}`;
const TRANSLATED = LOCALES.filter((locale): locale is Exclude<Locale, 'en'> => locale !== 'en');
/** Keys whose text is the same in some language: names, symbols and the "≤" form. */
const SAME_AS_ENGLISH = new Set(['money.mode.real', 'money.max', 'money.fund.crypto', 'money.review.atMost', 'money.send.solName', 'money.market.sentence', 'money.history.when']);

function runs(parts: readonly MessagePart[], into: string[] = []): string[] {
  for (const part of parts) {
    if (part.kind === 'text') into.push(...part.text.replace(/<\/?[a-z]+\s*\/?>/gu, '\n').split('\n'));
    else if (part.kind === 'plural' || part.kind === 'select') for (const option of part.options.values()) runs(option, into);
  }
  return into;
}
function selectors(parts: readonly MessagePart[], into: string[] = []): string[] {
  for (const part of parts) if (part.kind === 'select') {
    into.push(`${part.name}:${[...part.options.keys()].sort().join('|')}`);
    for (const option of part.options.values()) selectors(option, into);
  }
  return into.sort();
}
/**
 * The money area's English, and the shared copy it uses, that must not show
 * once the page reads another language (as support/i18n-leaks.ts reads it),
 * limited to money and common so other areas' work does not decide this test.
 */
async function moneyFragments(locale: Exclude<Locale, 'en'>): Promise<Map<string, string>> {
  const catalog = await loadCatalog(locale);
  const fragments = new Map<string, string>();
  for (const [key, source] of Object.entries(en)) {
    if (!key.startsWith('money.') && !key.startsWith('common.')) continue;
    const translated = catalog[key as keyof typeof en];
    if (translated === source) continue;
    for (const run of runs(parseMessage(source))) {
      const text = run.trim().replace(/^[^\p{L}]+|[^\p{L}]+$/gu, '');
      if (text.split(/\s+/u).length < 2 || text.length < 8 || translated.includes(text)) continue;
      fragments.set(text, key);
    }
  }
  assert.ok(fragments.size > 250, 'the area has English to look for');
  return fragments;
}
function assertNoLeaks(element: Element | null, fragments: ReadonlyMap<string, string>, allow: readonly string[] = []) {
  assert.ok(element, 'the screen is on the page');
  const scope = {body: element, title: '',
    querySelectorAll: (selector: string) => [...(element.matches(selector) ? [element] : []), ...element.querySelectorAll(selector)]};
  const report = findLeaks(scope as unknown as Document, fragments, allow);
  assert.deepEqual(report.fragments, [], 'no English sentence from the money area');
  assert.deepEqual(report.words, [], 'no untranslated English words');
}

/** What the API writes in English about the issuer, plus names: allowed on a French page. */
function issuerCopy(issuerId = 'xstocks'): string[] {
  const issuers = (liveCapabilitiesJson() as {issuers: Record<string, unknown>[]}).issuers;
  const issuer = issuers.find(item => item['issuerId'] === issuerId)!;
  return [issuer['warning'], issuer['summary'], issuer['holderRights'], issuer['productType'], issuer['legalName'],
    (issuer['attestation'] as {text: string}).text, (issuer['excludedRegions'] as string[]).join(', ')].map(String);
}

test('every money message exists in every language, with the same values, choices and tags, and no em dash', async () => {
  const keys = Object.keys(enMoney);
  assert.ok(keys.length > 290);
  for (const locale of TRANSLATED) {
    const catalog = await loadCatalog(locale);
    const area = Object.fromEntries(Object.entries(catalog).filter(([key]) => key.startsWith('money.')));
    assert.deepEqual(Object.keys(area).sort(), [...keys].sort(), `${locale} has exactly the English keys`);
    for (const key of keys) {
      const source = enMoney[key as keyof typeof enMoney] as string, text = area[key]!;
      assert.ok(text.trim().length > 0 && text === text.trim(), `${locale} ${key} is written`);
      const english = parseMessage(source), translated = parseMessage(text);
      assert.deepEqual([...messageArguments(translated)].sort(), [...messageArguments(english)].sort(), `${locale} ${key} reads the same values`);
      assert.deepEqual(selectors(translated), selectors(english), `${locale} ${key} offers the same choices`);
      assert.deepEqual(messageTags(text), messageTags(source), `${locale} ${key} keeps its tags`);
      assert.doesNotMatch(text, /—/u, `${locale} ${key} has no em dash`);
      if (!SAME_AS_ENGLISH.has(key)) assert.notEqual(text, source, `${locale} ${key} is translated`);
      if (locale === 'fr') assert.doesNotMatch(text, /(?:^|[^  ])[:;?!](?:\s|$)/u, `fr ${key} keeps a no-break space before : ; ? !`);
    }
  }
});

test('market times, refusals and send errors read in each language; English is unchanged', async () => {
  const now = new Date(2026, 9, 1, 12, 0).getTime();
  const at = (days: number, hour: number, minute: number) => new Date(2026, 9, 1 + days, hour, minute).toISOString();
  const closed = (nextOpenAt: string) => parseMarketState({hours: 'us_sessions', sessions: ['regular'], status: 'closed', reason: 'outside_sessions',
    session: null, nextOpenAt, closesAt: null})!;
  try {
    await setLocale('en');
    assert.equal(marketTime(at(0, 13, 5), now), '1:05 PM');
    assert.equal(marketTime(at(1, 1, 5), now), 'tomorrow 1:05 AM');
    assert.equal(marketTime(at(3, 9, 30), now), 'Sun 9:30 AM');
    assert.equal(marketTime(at(9, 9, 30), now), 'Oct 10, 9:30 AM');
    assert.equal(marketLabel(closed(at(1, 9, 30)), now), 'Closed · opens tomorrow 9:30 AM');
    assert.equal(liveOrderMessage('LIVE_BUSY', 1), 'Quotes are busy. Try again in 1 second.');
    assert.equal(liveOrderMessage('LIVE_BUSY', 2), 'Quotes are busy. Try again in 2 seconds.');
    assert.equal(transferMessage('LEAVES_TOO_LITTLE_SOL'), 'Leave at least 0.001 SOL, or send all of it.');

    await setLocale('es-419', {languages: ['es-MX']});
    assert.equal(marketLabel(closed(at(1, 1, 5)), now), 'Cerrado · abre mañana a la 1:05 a.m.', 'one o’clock reads “a la”');
    assert.equal(marketLabel(closed(at(1, 21, 30)), now), 'Cerrado · abre mañana a las 9:30 p.m.');
    assert.equal(marketLabel(closed(at(3, 9, 30)), now), 'Cerrado · abre el dom a las 9:30 a.m.');
    assert.equal(liveOrderMessage('LIVE_BUSY', 1), 'Hay mucha demanda de cotizaciones. Intenta de nuevo en 1 segundo.');
    assert.equal(transferMessage('AMOUNT_TOO_SMALL'), 'Una billetera nueva necesita al menos 0.001 SOL para abrirse.');

    await setLocale('pt-BR', {languages: ['pt-BR']});
    assert.equal(marketLabel(closed(at(0, 13, 5)), now), 'Fechado · abre às 13:05');
    assert.equal(marketLabel(closed(at(1, 1, 5)), now), 'Fechado · abre amanhã à 1:05');
    assert.equal(marketLabel(closed(at(9, 9, 30)), now), 'Fechado · abre em 10 de out. às 9:30');
    assert.equal(transferMessage('LEAVES_TOO_LITTLE_SOL'), 'Deixe pelo menos 0,001 SOL ou envie tudo.');

    await setLocale('fr', {languages: ['fr-FR']});
    assert.equal(marketLabel(closed(at(1, 9, 30)), now), 'Fermé · ouvre demain à 9:30');
    assert.equal(marketLabel(closed(at(3, 9, 30)), now), 'Fermé · ouvre dim. à 9:30');
    assert.equal(liveOrderMessage('LIVE_BUSY', 2), 'Les cotations sont surchargées. Réessaie dans 2 secondes.');
    assert.equal(t('money.review.expiresIn', {seconds: 12}), `La cotation expire dans 12${NBSP}s`);
  } finally {await setLocale('en');}
});

test('the order panel reads in French from entry through review to the receipt, and a comma amount reaches the quote exactly', async () => {
  await setLocale('fr', {languages: ['fr-FR']});
  const fragments = await moneyFragments('fr');
  const page = await moneyPage();
  page.storage.data.set(REAL_KEY, 'real');
  page.server.settle.push('pending', 'confirmed');
  const panel = () => page.dom.window.document.querySelector('.trade-panel.live');
  const allow = [...issuerCopy(), 'xStocks', 'AAPLx', 'Solana', 'USDC', 'SOL'];
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'apple', mint: AAPLX, companyName: 'Apple', discovery: [{mint: AAPLX, liquidityUsd: 1_478_672}]}));
    await page.waitFor(() => /Acheter AAPLx/.test(page.text()) && /Disponible/.test(page.text()), 'order entry');
    assert.equal(panel()?.getAttribute('aria-label'), 'Ordre en argent réel');
    assert.equal(page.dom.window.document.querySelector('.live-amount > span[aria-hidden]')?.textContent, '$US');
    assert.deepEqual(page.all('.amount-options button').map(button => button.textContent), [`5${NBSP}$US`, `10${NBSP}$US`, `25${NBSP}$US`, `50${NBSP}$US`]);
    assert.match(page.text(), new RegExp(`Disponible${NBSP}: 25 USDC`));
    assert.match(page.text(), new RegExp(`Limite par ordre${NBSP}: 100 USDC`));
    assert.match(page.text(), /Conditions de l’émetteur ↗/);
    assert.equal(page.dom.window.document.querySelector('.issuer-card')?.getAttribute('aria-label'), 'Conditions de l’émetteur xStocks');
    assert.equal(page.button('Vérifier l’achat')?.disabled, true, 'no review before the issuer terms are ticked');
    assertNoLeaks(panel(), fragments, allow);

    await page.tick();
    await page.type('#live-amount', '5,5');
    assert.equal(page.dom.window.document.querySelector<HTMLInputElement>('#live-amount')?.value, '5,5', 'the French decimal mark stays as typed');
    await page.click('Vérifier l’achat');
    await page.waitFor(() => /Vérifie ton achat/.test(page.text()), 'review');
    const preview = page.calls.find(call => call.path === '/v1/trading/preview');
    assert.equal(preview?.body?.['amountRaw'], '5500000', '5,5 USDC is exactly 5.5 USDC');
    const rows = Object.fromEntries(page.all('.review-summary > div').map(row => [row.querySelector('dt')?.textContent, row.querySelector('dd')?.textContent]));
    assert.equal(rows['Tu paies'], '5,5 USDC');
    assert.equal(rows['Frais de réseau et de compte'], '≤ 0,00204428 SOL');
    assert.equal(rows['Frais de swap'], `0,2${NBSP}%`);
    assert.equal(rows['Émetteur'], 'xStocks');
    assert.ok(rows['Tu reçois ≈'] && rows['Minimum reçu'], 'what arrives, and the least of it');
    assert.match(page.text(), new RegExp(`La cotation expire dans \\d+${NBSP}s`));
    assert.match(page.text(), /En confirmant, tu signes exactement cet ordre/);
    assertNoLeaks(panel(), fragments, allow);

    await page.click('Confirmer l’achat');
    await page.waitFor(() => /Opération confirmée/.test(page.text()), 'receipt', 4000);
    assert.match(page.text(), /Ton ordre est confirmé sur Solana\./);
    assert.match(page.text(), /Achat de AAPLx/);
    assert.equal(page.dom.window.document.querySelector('a[href^="https://solscan.io/"]')?.textContent, 'Voir la transaction ↗');
    assert.ok(page.button('Terminé'));
    assertNoLeaks(panel(), fragments, allow);
    assert.equal(page.calls.filter(call => call.path === '/v1/trading/execute').length, 1);
  } finally {await page.close(); await setLocale('en');}
});

test('a refusal shown in the order panel follows a language change, and Spanish and Portuguese read their own sentence', async () => {
  await setLocale('pt-BR', {languages: ['pt-BR']});
  const page = await moneyPage({route: 'rfq'});
  page.storage.data.set(REAL_KEY, 'real');
  const meta = 'fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo';
  page.server.reply = call => call.path === '/v1/trading/preview' ? Response.json({code: 'BELOW_MINIMUM'}, {status: 409}) : undefined;
  const panel = createElement(LiveOrderPanel, {assetId: 'meta', mint: meta, companyName: 'Meta', discovery: [{mint: meta}]});
  try {
    await page.render(panel);
    await page.waitFor(() => /Comprar METAon/.test(page.text()), 'order entry');
    assert.match(page.text(), /As ordens começam em 2 USDC\./);
    await page.tick(); await page.type('#live-amount', '2'); await page.click('Revisar compra');
    await page.waitFor(() => /abaixo do mínimo do formador de mercado/.test(page.text()), 'refusal');
    // The same panel, still mounted: the language changes under it and the refusal is rewritten.
    await act(async () => {await setLocale('es-419', {languages: ['es-AR']});});
    await page.waitFor(() => /Comprar METAon/.test(page.text()) && /Revisar compra/.test(page.text()), 'Spanish entry');
    assert.match(page.text(), /Esta orden está por debajo del mínimo del creador de mercado\. Prueba con un monto mayor\./);
    assert.doesNotMatch(page.text(), /formador de mercado/);
    const fragments = await moneyFragments('es-419');
    assertNoLeaks(page.dom.window.document.querySelector('.trade-panel.live'), fragments, [...issuerCopy('ondo'), 'Ondo', 'METAon', 'Solana', 'USDC']);
  } finally {await page.close(); await setLocale('en');}
});

test('the send sheet reads in French from the form through the review to the result, and a comma amount is sent exactly', async () => {
  await setLocale('fr', {languages: ['fr-FR']});
  const fragments = await moneyFragments('fr');
  const page = await moneyPage();
  const verify = await apiVerifier();
  const FRIEND = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
  const unsignedWire = (await buildSendReview({wallet: page.user.address})).unsignedTransaction as string;
  const review = {id: '77777777-7777-4777-8777-777777777777', review: {asset: {kind: 'token', mint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', symbol: 'USDC',
    decimals: 6, uiMultiplier: '1'}, from: page.user.address, destination: FRIEND, amountRaw: '5000000', receivedRaw: '5000000', createsAccount: true,
    accountRentLamports: '2039280', networkFeeLamports: '8000', expiresAt: new Date(Date.now() + 60_000).toISOString()},
    unsignedTransaction: Buffer.from(unsigned(message([page.user.address], {version: 0}), 1)).toString('base64'), reviewToken: 'payload.mac'};
  let refuse = true;
  page.server.reply = call => {
    if (call.path === '/v1/wallet/transfers/preview') return refuse ? Response.json({code: 'DESTINATION_NOT_WALLET'}, {status: 400})
      : Response.json({...review, unsignedTransaction: unsignedWire});
    if (call.path === '/v1/wallet/transfers/execute') {
      return Response.json({signature: verify({wallet: page.user.address, unsignedTransaction: unsignedWire}, call.body!['signedTransaction'] as string)});
    }
    if (call.path.startsWith('/v1/wallet/transfers/status')) return Response.json({status: 'confirmed', slot: 9});
    return undefined;
  };
  function Open() {const money = useMoney(); useEffect(() => {money.openSend();}, []); return null;}
  const sheet = () => page.dom.window.document.querySelector('.money-sheet.send-money');
  const message_ = () => page.dom.window.document.querySelector('[data-testid="send-message"]')?.textContent;
  const allow = ['Solana', 'USDC', 'SOL', FRIEND];
  try {
    await page.render(createElement(Open));
    await page.waitFor(() => page.button('Vérifier l’envoi')?.disabled === false, 'send form');
    assert.match(page.text(), /Envoie uniquement vers une adresse Solana\. Un envoi est irréversible\./);
    assert.deepEqual(page.all('[data-testid="send-asset"] option').map(option => option.textContent), ['Dollars américains (USDC) · 25 USDC', 'Solana (SOL) · 0,021 SOL']);
    assert.match(page.text(), new RegExp(`Disponible à l’envoi${NBSP}: 25 USDC`));
    assert.equal(page.dom.window.document.querySelector('.money-close')?.getAttribute('aria-label'), 'Fermer');
    assertNoLeaks(sheet(), fragments, allow);

    await page.type('[data-testid="send-destination"]', FRIEND);
    await page.type('[data-testid="send-amount"]', '40');
    await page.click('Vérifier l’envoi');
    assert.equal(message_(), 'Tu peux envoyer jusqu’à 25 USDC.');
    await page.type('[data-testid="send-amount"]', '2,5');
    await page.click('Vérifier l’envoi');
    await page.waitFor(() => message_()?.startsWith('Cette adresse') === true, 'refusal');
    assert.deepEqual(page.calls.find(call => call.path === '/v1/wallet/transfers/preview')?.body, {asset: 'USDC', destination: FRIEND, amountRaw: '2500000'},
      '2,5 USDC is exactly 2.5 USDC');
    assert.equal(message_(), 'Cette adresse n’est pas un portefeuille. C’est peut-être un compte de token ou un programme. Demande plutôt l’adresse du portefeuille.');
    await page.click('Max');
    assert.equal(page.dom.window.document.querySelector<HTMLInputElement>('[data-testid="send-amount"]')?.value, '25', 'Max fills the whole balance');
    assertNoLeaks(sheet(), fragments, allow);

    refuse = false;
    await page.type('[data-testid="send-amount"]', '5,0');
    await page.click('Vérifier l’envoi');
    await page.waitFor(() => !!page.button('Envoyer maintenant'), 'review');
    assert.deepEqual(page.calls.filter(call => call.path === '/v1/wallet/transfers/preview').at(-1)?.body, {asset: 'USDC', destination: FRIEND, amountRaw: '5000000'});
    const rows = Object.fromEntries(page.all('.send-summary > div').map(row => [row.querySelector('dt')?.textContent, row.querySelector('dd')?.textContent]));
    assert.deepEqual(rows, {'Tu envoies': '5 USDC', 'Frais de réseau': '0,000008 SOL', 'Ouvre le compte USDC du destinataire (une seule fois)': '0,00203928 SOL'});
    assert.match(page.text(), /Vers ce portefeuille Solana/);
    assert.match(page.text(), /Vérifie chaque caractère\. Un envoi est irréversible/);
    assert.ok(page.button('Modifier'));
    assertNoLeaks(sheet(), fragments, allow);

    await page.click('Envoyer maintenant');
    await page.waitFor(() => page.dom.window.document.querySelector('[data-testid="send-result"]')?.textContent === 'Envoyé', 'sent', 6000);
    assert.match(page.text(), /C’est confirmé sur Solana\./);
    assert.ok(page.all('a').some(link => link.textContent === 'Voir sur Solscan'));
    assert.ok(page.button('Terminé'));
    assertNoLeaks(sheet(), fragments, allow);
    assert.equal(page.privy.signs, 1);
  } finally {await page.close(); await setLocale('en');}
});

test('the leak check sees the money area’s English when it is there', async () => {
  const fragments = await moneyFragments('fr');
  await setLocale('en');
  const page = await moneyPage();
  page.storage.data.set(REAL_KEY, 'real');
  try {
    await page.render(createElement(LiveOrderPanel, {assetId: 'apple', mint: AAPLX, companyName: 'Apple', discovery: [{mint: AAPLX}]}));
    await page.waitFor(() => /Buy AAPLx/.test(page.text()) && /available/.test(page.text()), 'English entry');
    const element = page.dom.window.document.querySelector('.trade-panel.live')!;
    const scope = {body: element, title: '', querySelectorAll: (selector: string) => [...element.querySelectorAll(selector)]};
    const report = findLeaks(scope as unknown as Document, fragments, issuerCopy());
    assert.ok(report.fragments.includes('money.order.review: Review buy') && report.fragments.includes('money.issuer.terms: Issuer terms'), 'English copy is found');
  } finally {await page.close();}
});

test('the Real desk, Add money, Fast buy and trade history read in Spanish and Portuguese', async () => {
  const expected = {
    'es-419': {cash: /Saldo disponible/, split: /Disponible para operar: 25 USDC\. El resto está en otra cuenta de token\./, sol: '0.021 SOL para comisiones',
      sell: /Disponible para vender: 1\.5/, deposit: /Envía solo USDC o SOL a esta cuenta en la red Solana\./, copy: 'Copiar dirección',
      fast: 'Compra rápida', history: /Compra de METAon/, status: /No completada/, more: 'Más operaciones'},
    'pt-BR': {cash: /Saldo disponível/, split: /Disponível para negociar: 25 USDC\. O restante está em outra conta de token\./, sol: '0,021 SOL para taxas',
      sell: /Disponível para venda: 1,5/, deposit: /Envie apenas USDC ou SOL para esta conta na rede Solana\./, copy: 'Copiar endereço',
      fast: 'Compra rápida', history: /Compra de METAon/, status: /Não concluída/, more: 'Mais operações'},
  } as const;
  for (const locale of ['es-419', 'pt-BR'] as const) {
    await setLocale(locale, {languages: [locale === 'es-419' ? 'es-MX' : 'pt-BR']});
    const want = expected[locale], fragments = await moneyFragments(locale);
    const page = await moneyPage();
    page.storage.data.set(REAL_KEY, 'real');
    const META = 'fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo';
    const order = (id: string, status: string, rfq: boolean) => ({id, wallet: page.user.address, status, signature: id.slice(-1).repeat(88),
      createdAt: '2026-09-27T10:00:00.123456Z', updatedAt: '2026-09-27T10:00:01.123456Z',
      asset: {assetId: rfq ? 'meta' : 'apple', mint: rfq ? META : AAPLX, symbol: rfq ? 'METAon' : 'AAPLx', name: 'Token', decimals: rfq ? 9 : 8, route: rfq ? 'rfq' : 'aggregator'},
      terms: {side: 'buy', inputMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', outputMint: rfq ? META : AAPLX,
        inputAmountRaw: '5000000', quotedOutputAmountRaw: '1960000', minimumOutputAmountRaw: '1950000'}, amountUnits: 'raw_token_units', amountsStatus: 'reviewed_quote'});
    page.server.reply = call => call.path === '/v1/account/holdings' ? Response.json(holdingsJson(page.user.address, {usdc: '30009999', usdcAvailable: '25000000',
      lamports: '21000000', tokens: [stockHolding({amountRaw: '250000000', availableToTradeRaw: '150000000', displayAmount: '2.502294', accountCount: 2,
        accountTopology: 'associated_with_ancillary'})]}))
      : call.path === '/v1/trading/history?limit=20' ? Response.json({schemaVersion: 1, network: 'solana:mainnet-beta',
        orders: [order('55555555-5555-4555-8555-555555555551', 'confirmed', true), order('55555555-5555-4555-8555-555555555552', 'failed', false)], nextCursor: 'older'})
      : undefined;
    const market = new ProductMarketClient({baseUrl: '/api', fetch: page.fetch, timeoutMs: 1000});
    const allow = ['USDC', 'SOL', 'Solana', 'SpaceX xStock', 'SPCXx', 'xStocks', 'METAon', 'AAPLx'];
    try {
      await page.render(createElement('div', null, createElement(RealBalanceCard, {onSwitch() {}, onFastBuy() {}, onAddMoney() {}, onSend() {}}),
        createElement(RealHoldings, {identities: new Map(), onOpen() {}, onExplore() {}, onAddMoney() {}, onHistory() {}})));
      await page.waitFor(() => /SPCXx/.test(page.text()) && /SOL/.test(page.text()), 'desk');
      const card = page.dom.window.document.querySelector('.real-balance')!;
      assert.match(card.textContent ?? '', want.cash); assert.match(card.textContent ?? '', want.split);
      assert.equal(page.dom.window.document.querySelector('[data-testid="real-sol-balance"]')?.textContent, want.sol);
      assert.match(page.dom.window.document.querySelector('.real-holdings')?.textContent ?? '', want.sell);
      assertNoLeaks(page.dom.window.document.querySelector('#root'), fragments, allow);

      await page.render(createElement(FundWalletSheet, {onClose() {}}));
      await page.waitFor(() => page.dom.window.document.querySelector('.money-qr') !== null, 'deposit');
      assert.match(page.text(), want.deposit); assert.ok(page.button(want.copy));
      assertNoLeaks(page.dom.window.document.querySelector('.fund-wallet'), fragments, [...allow, page.user.address]);

      await page.render(createElement(FastBuySheet, {market, knownCards: new Map(), onOpen() {}, onClose() {}}));
      await page.waitFor(() => page.all('.fast-buy-list li').length > 0, 'fast buy list');
      assert.equal(page.dom.window.document.querySelector('.fast-buy h2')?.textContent, want.fast);
      const names = page.all('.fast-buy-list strong, .fast-buy-list small').map(item => item.textContent ?? '');
      assertNoLeaks(page.dom.window.document.querySelector('.fast-buy'), fragments, [...allow, ...names]);

      await page.render(createElement(TradeHistoryScreen, {onBack() {}, pollMs: 100_000}));
      await page.waitFor(() => /METAon/.test(page.text()), 'history');
      assert.match(page.text(), want.history); assert.match(page.text(), want.status); assert.ok(page.button(want.more));
      await page.click(want.history);
      assertNoLeaks(page.dom.window.document.querySelector('.trade-history'), fragments, allow);
    } finally {await page.close();}
  }
  await setLocale('en');
});
