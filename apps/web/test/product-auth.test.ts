import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement, StrictMode, type ComponentProps} from 'react';
import {createRoot} from 'react-dom/client';
import {JSDOM} from 'jsdom';
import {ProductAuthProvider, productAuthMethodStorageKey, readProductAuthConfig, useProductAuth,
  type ConnectProductAccount, type ProductAccountConnection, type ProductAuth, type ProductAuthConfig} from '../src/product/product-auth.js';
import type {ProductAuthSdkCallbacks, ProductAuthSdkPort} from '../src/product/product-auth-sdk-loader.js';

const SUBJECT = 'did:privy:accountA', OTHER = 'did:privy:accountB';
const ACCOUNT = '11111111-1111-4111-8111-111111111111';
const config = {kind: 'enabled', appId: 'testApp', apiBase: '/api'} as const;
function deferred<T>() {let resolve!: (value: T) => void; let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((done, fail) => {resolve = done; reject = fail;}); return {promise, resolve, reject};}
function token(subject = SUBJECT) {
  const at = Math.floor(Date.now() / 1000), encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({alg: 'ES256', typ: 'JWT'})}.${encode({sub: subject, aud: config.appId, iss: 'privy.io', sid: 'session', iat: at - 5, exp: at + 300})}.c3ludGhldGlj`;
}
async function harness(options: {connect?: ConnectProductAccount; authenticated?: boolean; ready?: boolean;
  oauthHint?: {method: 'google' | 'x'; at: number}; strict?: boolean; config?: ProductAuthConfig} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#sign-in'});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document, navigator: dom.window.navigator, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  if (options.oauthHint) dom.window.sessionStorage.setItem(`${productAuthMethodStorageKey(config)}.oauth-pending`, JSON.stringify(options.oauthHint));
  const root = createRoot(dom.window.document.getElementById('root')!);
  let auth!: ProductAuth, emailCallbacks!: ProductAuthSdkCallbacks, oauthCallbacks!: ProductAuthSdkCallbacks;
  const requests: Parameters<ConnectProductAccount>[0][] = [], sent: string[] = [], codes: string[] = [], providers: string[] = [];
  const native = {ready: options.ready ?? true, authenticated: options.authenticated ?? false,
    user: options.authenticated ? {id: SUBJECT} : null as {id: string} | null, error: false};
  const oauth = {status: 'initial' as 'initial' | 'loading' | 'done' | 'error'};
  const implementations = {
    send: async (_email: string) => {}, verify: async (_code: string) => {}, oauth: async (_provider: string) => {},
    logout: async () => {native.authenticated = false; native.user = null;}, token: async () => token(native.user?.id),
    connect: options.connect ?? (async () => ({accountId: ACCOUNT, guestDisposition: 'none' as const})),
  };
  let providerConfig: ComponentProps<ProductAuthSdkPort['PrivyProvider']> | null = null;
  const sdk: ProductAuthSdkPort = {
    PrivyProvider(props) {providerConfig = props; return props.children;},
    usePrivy: () => ({...native, getAccessToken: () => implementations.token(), logout: () => implementations.logout()}),
    useLoginWithEmail(callbacks) {emailCallbacks = callbacks; return {
      async sendCode({email}) {sent.push(email); await implementations.send(email);},
      async loginWithCode({code}) {codes.push(code); await implementations.verify(code);},
    };},
    useLoginWithOAuth(callbacks) {oauthCallbacks = callbacks; return {
      status: oauth.status,
      async initOAuth({provider}) {providers.push(provider); await implementations.oauth(provider);},
    };},
  };
  function Probe() {auth = useProductAuth(); return createElement('p', null, auth.phase);}
  const connect: ConnectProductAccount = input => {requests.push(input); return implementations.connect(input);};
  function element() {
    const content = createElement(ProductAuthProvider, {config: options.config ?? config, connectAccount: connect, sdk, children: createElement(Probe)});
    return options.strict ? createElement(StrictMode, null, content) : content;
  }
  const flush = async () => {await act(async () => {await Promise.resolve();});};
  const render = async () => {await act(async () => {root.render(element());}); await flush();};
  const run = async (operation: () => unknown) => {await act(async () => {await operation();}); await flush();};
  const complete = async (method: 'email' | 'google' | 'twitter', subject = SUBJECT) => {
    await run(() => {native.authenticated = true; native.user = {id: subject};
      (method === 'email' ? emailCallbacks : oauthCallbacks).onComplete({user: {id: subject}, loginMethod: method});});
    await render();
  };
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  await render();
  return {dom, requests, sent, codes, providers, native, oauth, implementations, run, render, flush, complete, close,
    get auth() {return auth;}, get providerConfig() {return providerConfig;}, get emailCallbacks() {return emailCallbacks;}, get oauthCallbacks() {return oauthCallbacks;}};
}

test('product auth accepts an omitted web client ID, rejects invalid config, and never initializes an unconfigured SDK', async () => {
  assert.deepEqual(readProductAuthConfig('/api', {VITE_PRIVY_APP_ID: 'webApp'}), {kind: 'enabled', appId: 'webApp', apiBase: '/api'});
  assert.deepEqual(readProductAuthConfig('/api', {}), {kind: 'disabled'});
  for (const bad of ['http://remote.example', '/other', 'https://user:pass@example.com']) assert.equal(readProductAuthConfig(bad, {VITE_PRIVY_APP_ID: 'webApp'}).kind, 'invalid');
  assert.equal(readProductAuthConfig('/api', {VITE_PRIVY_APP_ID: 'webApp', VITE_PRIVY_APP_CLIENT_ID: 'invalid\n'}).kind, 'invalid');
  assert.equal(readProductAuthConfig(null, {VITE_PRIVY_APP_ID: 'webApp', VITE_TRIMMY_PRODUCT_API_URL: 'https://api.example.com'}).kind, 'invalid');
  const h = await harness({config: {kind: 'disabled'}});
  try {assert.equal(h.auth.phase, 'unconfigured'); assert.equal(h.providerConfig, null); assert.equal(h.requests.length, 0);}
  finally {await h.close();}
});

test('email OTP normalizes the address, guards duplicate sends, and waits for backend binding before success or remembering', async () => {
  const send = deferred<void>(), account = deferred<ProductAccountConnection>();
  const h = await harness({connect: () => account.promise});
  try {
    h.implementations.send = () => send.promise;
    await h.run(() => {void h.auth.sendEmailCode('  Person@Example.com  '); void h.auth.sendEmailCode('other@example.com');});
    assert.deepEqual(h.sent, ['person@example.com']); assert.equal(h.auth.phase, 'sending-code');
    await h.run(() => h.auth.cancel()); assert.equal(h.auth.phase, 'sending-code');
    await h.run(() => send.resolve()); assert.equal(h.auth.phase, 'code-sent'); assert.equal(h.auth.email, 'person@example.com');
    await h.run(() => h.auth.verifyEmailCode('bad')); assert.equal(h.codes.length, 0);
    await h.run(() => h.auth.verifyEmailCode(' 123456 ')); assert.deepEqual(h.codes, ['123456']);
    assert.equal(h.requests.length, 0); assert.equal(h.auth.authenticated, false);
    await h.complete('email'); assert.equal(h.auth.phase, 'connecting'); assert.equal(h.requests.length, 1);
    assert.equal(h.auth.accountAccess, null); assert.equal(h.auth.lastSuccessfulMethod, null);
    assert.equal(domRemembered(h.dom), null);
    await h.run(() => account.resolve({accountId: ACCOUNT, guestDisposition: 'claimed'}));
    assert.equal(h.auth.authenticated, true); assert.equal(h.auth.accountId, ACCOUNT); assert.equal(h.auth.guestDisposition, 'claimed');
    assert.equal(h.auth.lastSuccessfulMethod, 'email'); assert.equal(domRemembered(h.dom), 'email');
    assert.equal(await (h.auth as ProductAuth).accountAccess?.freshAccessToken(), token());
    assert.deepEqual(h.providerConfig?.config.embeddedWallets, {ethereum: {createOnLogin: 'off'}, solana: {createOnLogin: 'off'}, disableAutomaticMigration: true});
  } finally {await h.close();}
});
function domRemembered(dom: JSDOM) {return dom.window.localStorage.getItem(productAuthMethodStorageKey(config));}

test('Google and X use real OAuth provider identifiers and remember only completed backend-verified methods', async () => {
  for (const selected of ['google', 'x'] as const) {
    const h = await harness();
    try {
      await h.run(() => h.auth.loginWithProvider(selected));
      assert.deepEqual(h.providers, [selected === 'x' ? 'twitter' : 'google']);
      assert.equal(h.auth.authenticated, false); assert.equal(domRemembered(h.dom), null);
      await h.complete(selected === 'x' ? 'twitter' : 'google');
      assert.equal(h.auth.authenticated, true); assert.equal(domRemembered(h.dom), selected);
      assert.equal(h.dom.window.sessionStorage.length, 0);
    } finally {await h.close();}
  }
});

test('provider cancellation leaves the guest signed out and does not remember the attempted method', async () => {
  const h = await harness();
  try {
    await h.run(() => h.auth.loginWithProvider('google'));
    await h.run(() => h.oauthCallbacks.onError('cancelled'));
    assert.equal(h.auth.phase, 'ready'); assert.equal(h.auth.errorCode, null); assert.equal(h.auth.authenticated, false);
    assert.equal(h.requests.length, 0); assert.equal(domRemembered(h.dom), null);
  } finally {await h.close();}
});

test('a backend connection error cannot complete provider login and retry preserves its successful method', async () => {
  const h = await harness({connect: async () => {throw Object.assign(new Error('private'), {code: 'PRACTICE_NETWORK_ERROR'});}});
  try {
    await h.run(() => h.auth.loginWithProvider('x')); await h.complete('twitter');
    assert.equal(h.auth.phase, 'error'); assert.equal(h.auth.errorCode, 'PRACTICE_NETWORK_ERROR');
    assert.equal(h.auth.accountId, null); assert.equal(h.auth.authenticated, false); assert.equal(domRemembered(h.dom), null);
    h.implementations.connect = async () => ({accountId: ACCOUNT});
    await h.run(() => h.auth.retry());
    assert.equal(h.auth.authenticated, true); assert.equal(domRemembered(h.dom), 'x');
  } finally {await h.close();}
});

test('an existing-account conflict needs an explicit choice and does not silently provision or replace the guest', async () => {
  const h = await harness({connect: async input => {
    if (!input.openExistingAccount) throw Object.assign(new Error('private'), {code: 'GUEST_CLAIM_ACCOUNT_EXISTS'});
    return {accountId: ACCOUNT, guestDisposition: 'preserved'};
  }});
  try {
    await h.run(() => h.auth.loginWithProvider('google')); await h.complete('google');
    assert.equal(h.auth.phase, 'account-choice'); assert.equal(h.auth.authenticated, false); assert.equal(h.requests.length, 1);
    await h.flush(); assert.equal(h.requests.length, 1); assert.equal(domRemembered(h.dom), null);
    await h.run(() => h.auth.openExistingAccount());
    assert.equal(h.requests.length, 2); assert.equal(h.requests[1]?.openExistingAccount, true);
    assert.equal(h.auth.authenticated, true); assert.equal(h.auth.guestDisposition, 'preserved');
  } finally {await h.close();}
});

test('restoration re-verifies the SDK identity with the backend without inventing a successful login method', async () => {
  const h = await harness({authenticated: true});
  try {
    assert.equal(h.requests.length, 1); assert.equal(h.auth.authenticated, true); assert.equal(domRemembered(h.dom), null);
    assert.equal(h.auth.accountAccess?.subject, SUBJECT);
    const access = h.auth.accountAccess!; await h.run(() => h.auth.logout()); await h.render();
    assert.equal(access.signal.aborted, true); assert.equal(await access.freshAccessToken(), null);
    assert.equal(h.auth.authenticated, false); assert.equal(h.auth.accountAccess, null);
  } finally {await h.close();}
});

test('A to B to A identity changes abort late backend results and cannot revive the previous verified session', async () => {
  const account = deferred<ProductAccountConnection>();
  const h = await harness({authenticated: true, connect: () => account.promise});
  try {
    const first = h.requests[0]!; assert.equal(h.auth.phase, 'connecting');
    h.native.user = {id: OTHER}; await h.render(); assert.equal(first.signal.aborted, true);
    h.native.user = {id: SUBJECT}; await h.render();
    await h.run(() => account.resolve({accountId: ACCOUNT}));
    assert.equal(h.auth.authenticated, false); assert.equal(h.auth.accountId, null); assert.equal(h.requests.length, 1);
    assert.equal(await first.freshAccessToken(), null);
  } finally {await h.close();}
});

test('SDK readiness loss aborts verified account access and requires a fresh backend binding on recovery', async () => {
  const h = await harness({authenticated: true});
  try {
    const previous = h.auth.accountAccess!;
    h.native.ready = false; await h.render();
    assert.equal(previous.signal.aborted, true); assert.equal(await previous.freshAccessToken(), null);
    assert.equal(h.auth.phase, 'restoring'); assert.equal(h.auth.accountAccess, null);
    h.native.ready = true; await h.render();
    assert.equal(h.requests.length, 2); assert.equal(h.auth.authenticated, true);
    assert.notEqual((h.auth as ProductAuth).accountAccess?.signal, previous.signal);
  } finally {await h.close();}
});

test('logout invalidates pending email sends and late provider completion', async () => {
  const send = deferred<void>(); const h = await harness();
  try {
    h.implementations.send = () => send.promise;
    await h.run(() => {void h.auth.sendEmailCode('person@example.com');});
    await h.run(() => h.auth.logout()); await h.run(() => send.resolve());
    assert.equal(h.auth.email, null); assert.equal(h.auth.phase, 'ready');
    await h.run(() => h.auth.loginWithProvider('google'));
    await h.run(() => h.auth.logout()); await h.complete('google');
    assert.equal(h.auth.authenticated, false); assert.equal(h.requests.length, 0); assert.equal(domRemembered(h.dom), null);
  } finally {await h.close();}
});

test('failed SDK logout returns false, revokes account access, and can retry without accepting a new login', async () => {
  const h = await harness({authenticated: true});
  try {
    const access = h.auth.accountAccess!;
    h.implementations.logout = async () => {throw new Error('private SDK failure');};
    let result = true;
    await h.run(async () => {result = await h.auth.logout();});
    assert.equal(result, false); assert.equal(h.auth.errorCode, 'PRODUCT_SIGN_OUT_FAILED');
    assert.equal(h.auth.authenticated, false); assert.equal(access.signal.aborted, true);
    await h.run(() => h.auth.loginWithProvider('google')); assert.equal(h.providers.length, 0);
    h.implementations.logout = async () => {h.native.authenticated = false; h.native.user = null;};
    await h.run(async () => {result = await h.auth.logout();});
    assert.equal(result, true); assert.equal(h.auth.phase, 'ready'); assert.equal(h.auth.errorCode, null);
  } finally {await h.close();}
});

test('OAuth redirect state errors recover even when the SDK does not fire its login error callback', async () => {
  const h = await harness({oauthHint: {method: 'google', at: Date.now()}});
  try {
    h.oauth.status = 'error'; await h.render();
    assert.equal(h.auth.phase, 'error'); assert.equal(h.auth.busy, false); assert.equal(h.auth.authenticated, false);
    assert.equal(h.auth.errorCode, 'PRODUCT_SIGN_IN_FAILED'); assert.equal(h.dom.window.sessionStorage.length, 0);
    assert.equal(h.requests.length, 0); assert.equal(domRemembered(h.dom), null);
    h.oauth.status = 'loading'; await h.render(); await h.run(() => h.auth.loginWithProvider('x'));
    assert.deepEqual(h.providers, ['twitter']); await h.complete('twitter'); assert.equal(h.auth.authenticated, true);
  } finally {await h.close();}
});

test('a bounded OAuth redirect hint survives remount and StrictMode but is not remembered until successful binding', async () => {
  const account = deferred<ProductAccountConnection>();
  const h = await harness({oauthHint: {method: 'x', at: Date.now()}, strict: true, connect: () => account.promise});
  try {
    assert.equal(domRemembered(h.dom), null); await h.complete('twitter');
    assert.equal(h.auth.authenticated, false); assert.equal(domRemembered(h.dom), null);
    await h.run(() => account.resolve({accountId: ACCOUNT}));
    assert.equal(h.auth.authenticated, true); assert.equal(domRemembered(h.dom), 'x');
  } finally {await h.close();}
  const expired = await harness({oauthHint: {method: 'x', at: Date.now() - 600001}});
  try {await expired.complete('twitter'); assert.equal(expired.auth.authenticated, false); assert.equal(expired.requests.length, 0);}
  finally {await expired.close();}
});
