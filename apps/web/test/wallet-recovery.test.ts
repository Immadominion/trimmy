import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement, type ReactNode} from 'react';
import {JSDOM} from 'jsdom';
import {canExportWallet, parseRecoveryTarget, readRecoveryConfig, recoveryIdentity} from '../src/recovery/recovery-model.js';
import {createRecoverySdk, type RecoverySdk, type RecoverySession} from '../src/recovery/recovery-sdk-loader.js';
import {WalletRecoveryPage} from '../src/recovery/wallet-recovery.js';

const first = 'GtuuDXDJwaYCzFkushTrS3Sd68cKdNSqGKHcw8MsKXqF';
const second = 'So11111111111111111111111111111111111111112';
const subject = 'did:privy:accountA';
function wallet(address: string, extra = {}) {return {type: 'wallet', chainType: 'solana', walletClientType: 'privy', address, ...extra};}

test('recovery configuration accepts public IDs only and target requires a canonical public address', () => {
  assert.equal(readRecoveryConfig({}).kind, 'disabled');
  assert.deepEqual(readRecoveryConfig({VITE_PRIVY_APP_ID: 'app', VITE_PRIVY_APP_CLIENT_ID: 'client'}), {kind: 'enabled', appId: 'app', clientId: 'client'});
  for (const value of ['app\n', 'has space', 1, null]) assert.equal(readRecoveryConfig({VITE_PRIVY_APP_ID: value, VITE_PRIVY_APP_CLIENT_ID: 'client'}).kind, 'invalid');
  assert.deepEqual(parseRecoveryTarget(''), {kind: 'none'});
  assert.deepEqual(parseRecoveryTarget(`#address=${first}`), {kind: 'expected', address: first});
  for (const fragment of [`#address=${first}&address=${second}`, '#token=secret', '#address=invalid', '#address=' + '1'.repeat(32),
    '#address=' + 'z'.repeat(44), `#address=${first}%0a`, `#address=${first}\n`, `#address=${first}&next=https://elsewhere.test`]) {
    assert.deepEqual(parseRecoveryTarget(fragment), {kind: 'invalid'});
  }
});

test('only authenticated Privy Solana linked wallets are eligible; expected target cannot fall back', () => {
  const identity = recoveryIdentity({id: subject, linkedAccounts: [wallet(first), wallet(first), wallet(second, {walletClientType: 'phantom'}), wallet(second, {chainType: 'ethereum'}), {type: 'email'}]});
  assert.deepEqual(identity, {subject, addresses: [first]});
  assert.equal(recoveryIdentity({id: 'wrong', linkedAccounts: [wallet(first)]}), null);
  assert.equal(recoveryIdentity({id: subject, linkedAccounts: new Array(101).fill(wallet(first))}), null);
  assert.equal(recoveryIdentity({id: subject, linkedAccounts: [wallet('invalid')]}), null);
  assert.equal(canExportWallet(identity, {kind: 'none'}, first), true);
  assert.equal(canExportWallet(identity, {kind: 'expected', address: second}, first), false);
  assert.equal(canExportWallet(identity, {kind: 'none'}, second), false);
  assert.equal(canExportWallet(null, {kind: 'none'}, first), false);
});

test('SDK boundary restricts signup, exports only an explicit address, and never reads or returns secrets', async () => {
  const calls: unknown[] = [];
  const sdk = createRecoverySdk({PrivyProvider() {}, usePrivy() {return {
    ready: true, authenticated: true, user: {id: subject, linkedAccounts: [wallet(first)]},
    get getAccessToken() {throw new Error('must not access tokens');},
    login(options: unknown) {calls.push(options);}, async logout() {calls.push('logout');},
  };}}, {useExportWallet() {return {async exportWallet(options: unknown) {calls.push(options); return 'must not propagate a result';}};}});
  const session = sdk.useSession(); session.login(); await session.logout();
  assert.equal(await sdk.useExportWallet().exportWallet(first), undefined);
  assert.deepEqual(calls, [{disableSignup: true}, 'logout', {address: first}]);
  assert.deepEqual(Object.keys(session).sort(), ['authenticated', 'failed', 'identity', 'login', 'logout', 'ready']);
  assert.throws(() => createRecoverySdk({}, {}), /RECOVERY_UNAVAILABLE/);
  assert.throws(() => createRecoverySdk({PrivyProvider() {}, usePrivy() {return {ready: true};}}, {useExportWallet() {return {};}}).useSession(), /RECOVERY_UNAVAILABLE/);
});

function deferred() {let resolve!: () => void, reject!: (error: Error) => void; const promise = new Promise<void>((a, b) => {resolve = a; reject = b;}); return {promise, resolve, reject};}
async function harness(options: {fragment?: string; signedIn?: boolean; addresses?: string[]} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: `https://trimmy.example/wallet-recovery${options.fragment ?? `#address=${first}`}`});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document, navigator: dom.window.navigator,
    HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  const {createRoot} = await import('react-dom/client'), root = createRoot(dom.window.document.getElementById('root')!);
  let providerProps: Record<string, unknown> = {}, loads = 0, logins = 0, logouts = 0;
  const exports: string[] = [];
  let session: RecoverySession = {ready: true, authenticated: options.signedIn ?? true,
    identity: {subject, addresses: options.addresses ?? [first]}, failed: false, login() {logins++;}, async logout() {logouts++;}};
  let exportAction = async (_address: string) => {};
  const sdk: RecoverySdk = {PrivyProvider(props) {providerProps = props; return createElement('div', null, props.children as ReactNode);},
    useSession() {return session;}, useExportWallet() {return {async exportWallet(address) {exports.push(address); await exportAction(address);}};}};
  const loadSdk = async () => {loads++; return sdk;};
  const render = async (update: Partial<RecoverySession> = {}) => {session = {...session, ...update}; await act(async () => {
    root.render(createElement(WalletRecoveryPage, {config: {kind: 'enabled', appId: 'testApp', clientId: 'testClient'}, loadSdk}));
  });};
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')].find(value => value.textContent?.trim() === label);
  const click = async (label: string) => {const element = button(label); assert.ok(element, `Button ${label}`); await act(async () => {element.click();});};
  await render();
  return {dom, exports, button, click, render, setExport(value: typeof exportAction) {exportAction = value;},
    text: () => dom.window.document.body.textContent ?? '', info: () => ({providerProps, loads, logins, logouts}),
    async hash(value: string) {await act(async () => {dom.window.history.replaceState(null, '', `/wallet-recovery${value}`); dom.window.dispatchEvent(new dom.window.HashChangeEvent('hashchange'));});},
    async close() {await act(async () => {root.unmount();}); dom.window.close(); for (const [key, descriptor] of previous) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}}
  };
}

test('provider configuration cannot automatically create or migrate wallets; login is explicit', async () => {
  const h = await harness({signedIn: false});
  try {
    assert.equal(h.info().logins, 0); assert.deepEqual(h.exports, []);
    const config = h.info().providerProps['config'] as Record<string, unknown>;
    assert.deepEqual(config['embeddedWallets'], {ethereum: {createOnLogin: 'off'}, solana: {createOnLogin: 'off'}, disableAutomaticMigration: true});
    assert.deepEqual(config['loginMethods'], ['email', 'google', 'twitter', 'apple']);
    await h.click('Sign in to Trimmy'); assert.equal(h.info().logins, 1); assert.deepEqual(h.exports, []);
  } finally {await h.close();}
});

test('invalid targets do not load SDK and a mismatched authenticated wallet cannot export', async () => {
  const bad = await harness({fragment: '#address=invalid'});
  try {assert.equal(bad.info().loads, 0); assert.equal(bad.button('Open recovery key'), undefined); assert.deepEqual(bad.exports, []);}
  finally {await bad.close();}
  const h = await harness({addresses: [second]});
  try {assert.match(h.text(), /isn’t the matching account/); assert.equal(h.button('Open recovery key'), undefined);
    await h.click('Switch account'); assert.equal(h.info().logouts, 1); assert.deepEqual(h.exports, []);}
  finally {await h.close();}
});

test('matching wallet exports only after a click, blocks duplicate taps, and does not claim the key was saved', async () => {
  const h = await harness(), pending = deferred();
  try {
    h.setExport(() => pending.promise); assert.deepEqual(h.exports, []);
    await h.click('Open recovery key'); await h.click('Please wait…'); assert.deepEqual(h.exports, [first]);
    assert.equal(h.button('Switch account')?.disabled, true);
    await act(async () => pending.resolve()); assert.match(h.text(), /Recovery window closed/); assert.doesNotMatch(h.text(), /exported successfully/i);
    assert.equal(h.button('Open recovery key')?.disabled, false);
  } finally {await h.close();}
});

test('direct recovery links require wallet selection and account changes clear selection and stale completion', async () => {
  const h = await harness({fragment: '', addresses: [first, second]}), pending = deferred();
  try {
    assert.equal(h.button('Open recovery key')?.disabled, true);
    await act(async () => (h.dom.window.document.querySelectorAll<HTMLButtonElement>('[role="radio"]')[0]!).click());
    h.setExport(() => pending.promise); await h.click('Open recovery key'); assert.deepEqual(h.exports, [first]);
    await h.render({identity: {subject: 'did:privy:accountB', addresses: [second]}});
    assert.equal(h.button('Open recovery key')?.disabled, true); assert.doesNotMatch(h.text(), new RegExp(first));
    await act(async () => pending.reject(new Error('private provider detail must be discarded')));
    assert.doesNotMatch(h.text(), /private provider|couldn’t open|Recovery window closed/);
  } finally {await h.close();}
});

test('readiness loss and target removal reset pending work and fail closed', async () => {
  const h = await harness(), pending = deferred();
  try {
    h.setExport(() => pending.promise); await h.click('Open recovery key');
    await h.render({ready: false}); assert.equal(h.button('Open recovery key'), undefined);
    await act(async () => pending.resolve()); assert.doesNotMatch(h.text(), /Recovery window closed/);
    await h.render({ready: true}); await h.hash('');
    assert.match(h.text(), /recovery link isn’t valid/); assert.equal(h.button('Open recovery key'), undefined);
  } finally {await h.close();}
});

test('export errors are generic and retryable without exposing provider payloads', async () => {
  const h = await harness();
  try {h.setExport(async () => {throw new Error('sensitive provider response');}); await h.click('Open recovery key');
    assert.match(h.text(), /couldn’t open/); assert.doesNotMatch(h.text(), /sensitive provider response/);
    assert.equal(h.button('Open recovery key')?.disabled, false); assert.equal(h.exports.length, 1);
  } finally {await h.close();}
});
