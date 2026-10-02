import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {loadCatalog, setLocale, t} from '../src/i18n/runtime.js';
import {parseMessage, type MessagePart} from '../src/i18n/icu.js';
import {en} from '../src/i18n/messages/en/index.js';
import * as fmt from '../src/i18n/format.js';
import type {Locale} from '../src/i18n/locales.js';
import {ProductAuthContext, type ProductAuth} from '../src/product/product-auth.js';
import {SignInScreen} from '../src/product/sign-in-screen.js';
import {FirstOrderCelebration, GuestDeskPreserved, ReminderPreferencePage} from '../src/product/first-day-followup.js';
import {micros, toPaperMicros} from '../src/product/ui.js';
import {findLeaks} from './support/i18n-leaks.js';
import {harness} from './support/product-harness.js';

const NBSP = ' ', NNBSP = ' ';

function runs(parts: readonly MessagePart[], into: string[] = []): string[] {
  for (const part of parts) {
    if (part.kind === 'text') into.push(...part.text.replace(/<\/?[a-z]+\s*\/?>/gu, '\n').split('\n'));
    else if (part.kind === 'plural' || part.kind === 'select') for (const option of part.options.values()) runs(option, into);
  }
  return into;
}
/**
 * This area's English, and the shared copy it uses, that must not show once
 * the page reads another language: every literal run of two or more words
 * (as support/i18n-leaks.ts reads them), limited to firstDay and common so
 * other areas' work in progress does not decide this test.
 */
async function areaFragments(locale: Exclude<Locale, 'en'>): Promise<Map<string, string>> {
  const catalog = await loadCatalog(locale);
  const fragments = new Map<string, string>();
  for (const [key, source] of Object.entries(en)) {
    if (!key.startsWith('firstDay.') && !key.startsWith('common.')) continue;
    const translated = catalog[key as keyof typeof en];
    assert.ok(typeof translated === 'string' && translated.length > 0, `${locale} ${key} is translated`);
    if (translated === source) continue;
    for (const run of runs(parseMessage(source))) {
      const text = run.trim().replace(/^[^\p{L}]+|[^\p{L}]+$/gu, '');
      if (text.split(/\s+/u).length < 2 || text.length < 8 || translated.includes(text)) continue;
      fragments.set(text, key);
    }
  }
  assert.ok(fragments.size > 100, 'the area has English to look for');
  return fragments;
}
/** Leak report for one screen: its text and the accessible attributes of it and everything inside it. */
function leaksIn(element: Element | null, fragments: ReadonlyMap<string, string>, allow: readonly string[] = []) {
  assert.ok(element, 'the screen is on the page');
  const scope = {body: element, title: '',
    querySelectorAll: (selector: string) => [...(element.matches(selector) ? [element] : []), ...element.querySelectorAll(selector)]};
  return findLeaks(scope as unknown as Document, fragments, allow);
}
function assertNoLeaks(element: Element | null, fragments: ReadonlyMap<string, string>, allow: readonly string[] = []) {
  const report = leaksIn(element, fragments, allow);
  assert.deepEqual(report.fragments, [], 'no English sentence from this area');
  assert.deepEqual(report.words, [], 'no untranslated English words');
}

/** A sign-in screen with a stub auth context, as product-sign-in-screen.test.ts builds it. */
async function signInHarness(initial: Partial<ProductAuth> = {}, props: {entryGate?: boolean; expiredGuestRecovery?: boolean} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#sign-in'});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document,
    navigator: dom.window.navigator, HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: true, addEventListener() {}, removeEventListener() {}})});
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const sent: string[] = [];
  let auth: ProductAuth = {enabled: true, ready: true, busy: false, authenticated: false, phase: 'ready', subject: null,
    accountId: null, accountAccess: null, apiBase: '/api', email: null, errorCode: null, guestDisposition: null, lastSuccessfulMethod: null, logins: [],
    async sendEmailCode(value) {sent.push(value);}, async verifyEmailCode() {}, async loginWithProvider() {}, async freshAccessToken() {return null;},
    async openExistingAccount() {}, async retry() {}, async logout() {return true;}, cancel() {}, ...initial};
  const render = async (update: Partial<ProductAuth> = {}) => {auth = {...auth, ...update}; await act(async () => {
    root.render(createElement(ProductAuthContext.Provider, {value: auth}, createElement(SignInScreen, {motion: false, hasDesk: true,
      onBack() {}, onAccount() {}, onGuest: async () => {}, ...props})));
  });};
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')]
    .find(value => value.textContent?.trim() === label || value.getAttribute('aria-label') === label);
  const click = async (label: string) => {const target = button(label); assert.ok(target, `Button exists: ${label}`); await act(async () => {target.click();});};
  const input = async (id: string, value: string) => {
    const field = dom.window.document.getElementById(id) as HTMLInputElement; assert.ok(field);
    await act(async () => {Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value')!.set!.call(field, value);
      field.dispatchEvent(new dom.window.Event('input', {bubbles: true}));});
  };
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  await render();
  return {dom, sent, render, button, click, input, close, text: () => dom.window.document.body.textContent ?? '',
    screen: () => dom.window.document.querySelector('.sign-in-screen')};
}

/** A bare page for one component. */
async function page() {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/'});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document,
    navigator: dom.window.navigator, HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const show = async (element: ReturnType<typeof createElement>) => {await act(async () => {root.render(element);});};
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  return {dom, show, close, text: () => dom.window.document.body.textContent ?? ''};
}

test('the first day reads in French from welcome to the money choice, and a comma amount reaches the quote', async () => {
  await setLocale('fr', {languages: ['fr-FR']});
  const fragments = await areaFragments('fr');
  const h = await harness();
  const doc = () => h.dom.window.document;
  try {
    await h.app();
    assert.match(h.text(), /Sal t’a gardé une place\./);
    assert.match(h.text(), /Ta première journée commence ici\./);
    assert.equal(doc().querySelector('.intro-copy h1 + p')?.innerHTML, 'Choisis une entreprise. Passe à l’action.<br>Trouve tes marques à Wall Street.');
    assert.match(h.text(), /Pas besoin de te connecter\.Mieux sur mobile\./);
    assert.match(h.text(), /Bientôt disponible/);
    assertNoLeaks(doc().querySelector('.first-day'), fragments);

    await h.click('Commencer ma journée');
    assert.match(h.text(), /Un mot de SalBienvenue sur le parquet\./);
    assert.equal(doc().querySelector('.intro-note > p:not(.intro-eyebrow)')?.textContent, 'Ta première journée commence par de l’entraînement.\n\nChoisis une entreprise. C’est gratuit.');
    assert.ok(h.button('Passer la première journée'), 'the × skip button has a French name');
    assertNoLeaks(doc().querySelector('.first-day'), fragments);

    await h.click('Continuer'); await h.flush(60);
    assert.match(h.text(), /Choisis une entreprise que tu connais\./);
    assert.ok(h.button('Choisir Apple'));
    assert.equal(doc().querySelector('.intro-companies')?.getAttribute('aria-label'), 'Choisis une entreprise');
    assert.equal(doc().querySelector('.intro-amount label')?.textContent, 'Montant pour t’entraîner');
    assert.equal(doc().querySelector('.intro-amount-input span')?.textContent, 'd’entraînement');
    assert.deepEqual([...doc().querySelectorAll('.intro-amount-options button')].map(item => item.textContent), ['50', '100', '500']);
    assert.equal(doc().getElementById('first-day-balance')?.textContent,
      `Solde d’entraînement${NBSP}: 10${NNBSP}000,00. Utilise entre 1 et 10${NNBSP}000,00.`);
    assertNoLeaks(doc().querySelector('.first-day'), fragments, ['Apple', 'AAPLx']);

    // A French reader types a comma as the decimal mark: 12,5 is twelve and a half, and 100,00 is the quote's exact amount.
    await h.click('Choisir Apple');
    const field = doc().getElementById('first-day-amount') as HTMLInputElement;
    const type = async (value: string) => {await act(async () => {Object.getOwnPropertyDescriptor(h.dom.window.HTMLInputElement.prototype, 'value')!.set!.call(field, value);
      field.dispatchEvent(new h.dom.window.Event('input', {bubbles: true}));});};
    await type('12,5');
    assert.equal(field.getAttribute('aria-invalid'), 'false'); assert.equal(h.button('Vérifier l’achat d’entraînement')?.disabled, false);
    await type('0,5');
    assert.equal(field.getAttribute('aria-invalid'), 'true', 'under the 1 minimum'); assert.equal(h.button('Vérifier l’achat d’entraînement')?.disabled, true);
    await type('100,00');
    await h.click('Vérifier l’achat d’entraînement');
    const preview = h.api.calls.find(call => call.path.endsWith('/orders/preview'));
    assert.deepEqual(preview?.body?.['amount'], {kind: 'paper_amount', paperMicros: '100000000'});

    assert.match(h.text(), /Vérifie ton premier coup\./);
    const rows = Object.fromEntries([...doc().querySelectorAll('.intro-summary > div')].map(row => [row.querySelector('dt')?.textContent, row.querySelector('dd')?.textContent]));
    assert.deepEqual(rows, {'Token de l’entreprise': 'AAPLx', 'Actions': '2', 'Prix par action': '50,00 d’entraînement', 'Frais': '0,00 d’entraînement',
      'Montant à utiliser': '100,00 d’entraînement', 'Argent d’entraînement restant': `9${NNBSP}900,00 d’entraînement`});
    assert.match(h.text(), new RegExp(`La cotation expire dans \\d+${NBSP}s`));
    assertNoLeaks(doc().querySelector('.first-day'), fragments, ['Apple', 'AAPLx']);

    await h.click('Confirmer l’achat d’entraînement'); await h.flush(60);
    assert.match(h.text(), new RegExp(`Tu as passé ton premier ordre${NBSP}!`));
    assert.equal(doc().querySelector('.first-order-shares')?.innerHTML, 'Actions <strong>2</strong>');
    assert.equal(doc().querySelector('.first-order-amount')?.textContent, '100,00d’entraînement');
    assert.equal(doc().querySelector('.first-order-check')?.getAttribute('aria-label'), 'Achat confirmé');
    assert.equal(doc().querySelector('.first-order-reward')?.textContent, 'Recrue · 0 Trim au total', 'the rank in French, then a French plural');
    assertNoLeaks(doc().querySelector('.first-order'), fragments, ['Apple']);

    await h.click('Continuer');
    assert.match(h.text(), /Ton bureau t’attend\./);
    assert.match(h.text(), /Connecte-toi ou crée ton compte\./);
    assert.ok(h.button('Continuer en invité'));
    assertNoLeaks(doc().querySelector('.sign-in-screen'), fragments);

    await h.click('Continuer en invité');
    assert.match(h.text(), new RegExp(`Un petit rappel${NBSP}\\?`));
    await h.pick('Une fois par jour');
    assert.match(h.text(), new RegExp(`Vers 19${NBSP}h, à ton heure\\.`));
    await h.click('Continuer');
    assert.match(h.text(), /Ta préférence est enregistrée\./);
    assert.ok(h.button('Ajouter à l’agenda'));
    assert.equal(doc().querySelector('.reminder-page .intro-close')?.getAttribute('aria-label'), 'Passer les rappels');
    assertNoLeaks(doc().querySelector('.reminder-page'), fragments);

    await h.click('Continuer');
    assert.match(h.text(), /Ton prochain coup\./);
    assert.ok(h.button('Continuer avec l’argent d’entraînement'));
    assertNoLeaks(doc().querySelector('.money-choice'), fragments);
  } finally {await h.close(); await setLocale('en');}
});

test('sign-in reads in French in every step, with one whole sentence per sign-in method', async () => {
  await setLocale('fr', {languages: ['fr-FR']});
  const fragments = await areaFragments('fr');
  const h = await signInHarness();
  try {
    assert.match(h.text(), /Fais de ce bureau le tien\./);
    assert.equal(h.dom.window.document.querySelector('.sign-in-preferred')?.textContent, 'Continuer par e-mail');
    assert.ok(h.button('Continuer avec Google')); assert.ok(h.button('Continuer avec X'));
    assert.deepEqual([...h.dom.window.document.querySelectorAll('.sign-in-social span')].map(item => item.textContent), ['Google', 'X']);
    assert.equal(h.dom.window.document.querySelector('.sign-in-close')?.getAttribute('aria-label'), 'Fermer l’écran de connexion');
    assertNoLeaks(h.screen(), fragments);

    await h.click('Continuer par e-mail');
    assert.match(h.text(), /Ton e-mail\. Ton bureau\./);
    assert.equal(h.dom.window.document.getElementById('sign-in-email')?.getAttribute('placeholder'), 'toi@example.com');
    assertNoLeaks(h.screen(), fragments);
    await h.input('sign-in-email', 'person@example.com'); await h.click('Continuer par e-mail');
    assert.deepEqual(h.sent, ['person@example.com']);

    await h.render({phase: 'code-sent', email: 'person@example.com'});
    assert.equal(h.dom.window.document.querySelector('.sign-in-content > p')?.innerHTML, 'Saisis le code envoyé à <strong>person@example.com</strong>.');
    assert.match(h.text(), new RegExp(`Renvoyer dans \\d+${NBSP}s`));
    await h.render({phase: 'code-sent', errorCode: 'PRODUCT_EMAIL_CODE_INVALID'});
    assert.match(h.text(), /Ce code n’a pas marché\. Vérifie-le et réessaie\./);
    assertNoLeaks(h.screen(), fragments, ['person@example.com']);

    await h.render({phase: 'error', errorCode: 'PRACTICE_DAILY_DESK_PENDING', email: null});
    assert.match(h.text(), /Vérifie ta fin de journée précédente avant de te connecter\./);
    await h.render({phase: 'error', errorCode: 'SOMETHING_ELSE'});
    assert.match(h.text(), /La connexion n’a pas abouti\. Ta progression est en sécurité\. Réessaie\./);
    await h.render({phase: 'account-choice', subject: 'did:privy:a', errorCode: 'GUEST_SESSION_EXPIRED'});
    assert.match(h.text(), /Cette session invité a expiré\./);
    assertNoLeaks(h.screen(), fragments);
    await h.render({phase: 'connecting', busy: true, subject: null, errorCode: null});
    assert.match(h.text(), /Ouverture de ton bureau\.Restauration de ta progression…/);
    assertNoLeaks(h.screen(), fragments);
  } finally {await h.close(); await setLocale('en');}
});

test('the email method is a translated word while Google and X keep their names', async () => {
  const expected: [Exclude<Locale, 'en'>, string, string, string, string][] = [
    ['es-419', 'Continuar con correo', 'Continuar con Google', 'Continuar con X', 'correo'],
    ['pt-BR', 'Continuar com e-mail', 'Continuar com Google', 'Continuar com X', 'e-mail'],
    ['fr', 'Continuer par e-mail', 'Continuer avec Google', 'Continuer avec X', 'e-mail'],
  ];
  for (const [locale, email, google, x, word] of expected) {
    await setLocale(locale);
    const h = await signInHarness({lastSuccessfulMethod: 'google'});
    try {
      assert.equal(h.dom.window.document.querySelector('.sign-in-preferred')?.textContent, google, locale);
      assert.ok(h.button(email), `${locale} ${email}`); assert.ok(h.button(x), `${locale} ${x}`);
      assert.deepEqual([...h.dom.window.document.querySelectorAll('.sign-in-social span')].map(item => item.textContent), [word, 'X'], locale);
      assertNoLeaks(h.screen(), await areaFragments(locale));
    } finally {await h.close();}
  }
  await setLocale('en');
  const h = await signInHarness({lastSuccessfulMethod: 'google'});
  try {
    assert.equal(h.dom.window.document.querySelector('.sign-in-preferred')?.textContent, 'Continue with Google');
    assert.deepEqual([...h.dom.window.document.querySelectorAll('.sign-in-social span')].map(item => item.textContent), ['email', 'X']);
    const english = leaksIn(h.screen(), await areaFragments('fr'));
    assert.ok(english.fragments.some(item => item.endsWith(': Last used on this browser')) && english.words.length > 0, 'the leak check sees English when it is there');
  } finally {await h.close();}
});

test('the reminders page from Settings, the celebration fallback and Welcome back read in Portuguese and Spanish', async () => {
  for (const locale of ['pt-BR', 'es-419'] as const) {
    await setLocale(locale);
    const fragments = await areaFragments(locale);
    const p = await page();
    try {
      await p.show(createElement(ReminderPreferencePage, {saved: {version: 1, choice: 'occasional', savedAt: new Date().toISOString()},
        onSave: async () => {}, onDone: async () => {}, onClose() {}}));
      const close = p.dom.window.document.querySelector('.intro-close')?.getAttribute('aria-label');
      const captions = [...p.dom.window.document.querySelectorAll('.setup-choice small')].map(item => item.textContent);
      if (locale === 'pt-BR') {
        assert.equal(close, 'Fechar lembretes');
        assert.deepEqual(captions, ['Por volta das 19h, no seu horário.', 'Seg., qua. e sex., por volta das 19h.', 'Eu volto por conta própria.']);
      } else {
        assert.equal(close, 'Cerrar recordatorios');
        assert.deepEqual(captions, [`Cerca de las 7${NBSP}p.${NBSP}m., en tu hora.`, `Lun., mié. y vie., cerca de las 7${NBSP}p.${NBSP}m.`, 'Vuelvo por mi cuenta.']);
      }
      assertNoLeaks(p.dom.window.document.querySelector('.reminder-page'), fragments);

      await p.show(createElement(FirstOrderCelebration, {evidence: null, name: null, logoUrl: null, career: null, loading: false,
        onContinue: async () => {}, onRetry() {}}));
      assert.match(p.text(), locale === 'pt-BR' ? /Não foi possível carregar sua operação/ : /No pudimos cargar tu operación/);
      assertNoLeaks(p.dom.window.document.querySelector('.journey-state'), fragments);

      await p.show(createElement(GuestDeskPreserved, {expired: true, onContinue() {}}));
      assert.match(p.text(), locale === 'pt-BR' ? /Sua mesa de convidado expirada fica guardada à parte\./ : /Tu escritorio de invitado vencido se guarda por separado\./);
      assertNoLeaks(p.dom.window.document.querySelector('.journey-state'), fragments);
    } finally {await p.close();}
  }
  await setLocale('en');
});

test('first-day amounts, counts and countdowns follow the reader’s region; English is unchanged', async () => {
  const range = () => t('firstDay.practice.balanceRange', {cash: micros('10000000000'), minimum: 1, maximum: micros('10000000000')});
  const reward = (total: number) => t('firstDay.order.reward', {rank: 'Rookie', trims: fmt.count(total)});

  await setLocale('en');
  assert.equal(micros('10000000000'), '10,000.00');
  assert.equal(range(), '10,000.00 paper available. Practice with 1 to 10,000.00 paper.');
  assert.equal(t('firstDay.practice.balanceTooLow', {cash: micros('500000'), minimum: 1}), '0.50 paper available. You need at least 1 paper to practice.');
  assert.equal(reward(1), 'Rookie · 1 Trims total', 'English keeps its historical copy');
  assert.equal(reward(1234), `Rookie · ${(1234).toLocaleString()} Trims total`);
  assert.equal(t('firstDay.review.expiresIn', {seconds: 12}), 'Quote expires in 12s');
  assert.equal(t('firstDay.signIn.code.resendIn', {seconds: 9}), 'Send again in 9s');
  assert.equal(toPaperMicros('12,5'), '12500000', 'a comma keypad on an English page: twelve and a half, never 125');
  assert.equal(toPaperMicros('1,000'), null, 'an English thousands comma is refused, not guessed');
  assert.equal(toPaperMicros('12.5'), '12500000');

  await setLocale('fr', {languages: ['fr-FR']});
  assert.equal(range(), `Solde d’entraînement${NBSP}: 10${NNBSP}000,00. Utilise entre 1 et 10${NNBSP}000,00.`);
  assert.equal(reward(1), 'Rookie · 1 Trim au total');
  assert.equal(reward(1234), `Rookie · 1${NNBSP}234 Trims au total`);
  assert.equal(t('firstDay.review.expiresIn', {seconds: 12}), `La cotation expire dans 12${NBSP}s`);
  assert.equal(toPaperMicros('12,5'), '12500000');
  assert.equal(toPaperMicros('12.5'), '12500000');
  assert.equal(t('common.paperAmount', {amount: fmt.number('0.00')}), '0,00 d’entraînement');

  await setLocale('es-419', {languages: ['es-AR']});
  assert.equal(range(), 'Saldo de práctica: 10.000,00. Usa entre 1 y 10.000,00.');
  assert.equal(reward(2), 'Rookie · 2 Trims en total');
  assert.equal(t('firstDay.review.expiresIn', {seconds: 12}), `La cotización vence en 12${NBSP}s`);
  assert.equal(t('firstDay.signIn.code.resendIn', {seconds: 9}), `Reenviar en 9${NBSP}s`);

  await setLocale('es-419', {languages: ['es-MX']});
  assert.equal(range(), 'Saldo de práctica: 10,000.00. Usa entre 1 y 10,000.00.', 'Mexico groups the way English does');

  await setLocale('pt-BR', {languages: ['pt-BR']});
  assert.equal(range(), 'Saldo de treino: 10.000,00. Use entre 1 e 10.000,00.');
  assert.equal(t('firstDay.practice.balanceTooLow', {cash: micros('500000'), minimum: 1}), 'Saldo de treino: 0,50. Você precisa de pelo menos 1 para treinar.');
  assert.equal(reward(1), 'Rookie · 1 Trim no total');
  assert.equal(toPaperMicros('1.234,5'), '1234500000');
  await setLocale('en');
});
