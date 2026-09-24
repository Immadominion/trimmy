import assert from 'node:assert/strict';
import test from 'node:test';
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { JSDOM } from 'jsdom';
import { AccountPortfolioPanel, type AccountPortfolioPanelProps } from '../src/account/account-portfolio-panel.js';
import type { AccountContextSnapshot, AccountHoldingsSnapshot } from '../src/account/account-data-models.js';
import type { AccountPortfolioSnapshot, AccountPortfolioState } from '../src/account/account-portfolio.js';
import type { AccountPortfolioLifecycleView, VerifiedAccountBinding } from '../src/account/use-account-portfolio.js';

const subject = 'did:privy:panelSubject';
const accountId = 'aa000000-0000-4000-8000-000000000001';
const wallet = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
const observedAt = '2026-09-14T17:28:27.109Z';
const observed = new Date(observedAt);
const clock = `${String(observed.getHours()).padStart(2, '0')}:${String(observed.getMinutes()).padStart(2, '0')}`;

const context: AccountContextSnapshot = {
  schemaVersion: 1, userId: accountId,
  xIdentity: {status: 'verified', subject: '18446744073709551615', usernameSnapshot: 'trimmyhq', verifiedAtUnixSeconds: 1757845200},
  embeddedSolanaWallet: {status: 'candidate', address: wallet, verifiedAtUnixSeconds: 1757845201},
};
const holdings: AccountHoldingsSnapshot = {
  schemaVersion: 1, userId: accountId,
  wallet: {address: wallet, source: 'privy_embedded_wallet_same_subject', possessionSignatureVerified: false},
  holdings: {
    network: 'solana:mainnet-beta', genesisHash: '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d', commitment: 'confirmed',
    observedAt, readOnly: true, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false,
    balances: {
      nativeSol: {symbol: 'SOL', decimals: 9, amountRaw: '9007199254740991', amountUnits: 'lamports', observedSlot: 447040359},
      usdc: {symbol: 'USDC', mint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', decimals: 6, amountRaw: '18446744073709551615',
        amountUnits: 'raw_token_units', observedSlot: 447040360, accountCount: 2, accountTopology: 'associated_with_ancillary',
        aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: true},
      aaplx: {symbol: 'AAPLx', mint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', decimals: 8, amountRaw: '9007199254741000',
        amountUnits: 'raw_token_units', observedSlot: 447040361, accountCount: 1, accountTopology: 'associated_only',
        aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false, displayResolution: 'token_2022_scaled_ui_unresolved',
        displayAmount: null, shareAmount: null, eligibility: 'unverified', executionEnabled: false},
    },
    consistency: {kind: 'independent_confirmed_reads', atomic: false, slots: {nativeSol: 447040359, usdc: 447040360, aaplx: 447040361}},
  },
};
const portfolioSnapshot: AccountPortfolioSnapshot = {
  subject, accountId, walletAddress: wallet, context, holdings, acceptedAtMs: observed.getTime() + 1000, freshUntilMs: observed.getTime() + 45_000,
};
const binding: VerifiedAccountBinding = {subject, accountId, apiOrigin: 'https://api.trimmy.test', verificationEpoch: 1};

function state(overrides: Partial<AccountPortfolioState>): AccountPortfolioState {
  return {phase: 'ready', subject, accountId, walletAddress: wallet, context, portfolio: portfolioSnapshot, issue: null, ...overrides};
}

function view(snapshot: AccountPortfolioState | null, options: {binding?: VerifiedAccountBinding | null; errorCode?: string | null; calls: string[]}): AccountPortfolioLifecycleView {
  return {
    binding: options.binding === undefined ? binding : options.binding,
    snapshot,
    errorCode: (options.errorCode ?? snapshot?.issue ?? null) as AccountPortfolioLifecycleView['errorCode'],
    refresh: () => { options.calls.push('refresh'); return true; },
    retry: () => { options.calls.push('retry'); return true; },
  };
}

const auth = (overrides: Partial<AccountPortfolioPanelProps['auth']> = {}): AccountPortfolioPanelProps['auth'] =>
  ({enabled: true, ready: true, authenticated: true, errorCode: null, ...overrides});

test('account portfolio panel renders every read state truthfully', async () => {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example', pretendToBeVisual: true});
  const descriptors = new Map<string, PropertyDescriptor | undefined>();
  function global(name: string, value: unknown) {
    descriptors.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});
  }
  global('window', dom.window); global('document', dom.window.document); global('navigator', dom.window.navigator);
  global('HTMLElement', dom.window.HTMLElement); global('Event', dom.window.Event); global('IS_REACT_ACT_ENVIRONMENT', true);
  const root: Root = createRoot(dom.window.document.getElementById('root')!);
  const text = () => dom.window.document.body.textContent ?? '';
  const buttons = () => [...dom.window.document.querySelectorAll('button')].map(button => button.textContent);
  const render = async (props: AccountPortfolioPanelProps) => { await act(async () => { root.render(createElement(AccountPortfolioPanel, props)); }); };
  const click = async (label: string) => {
    const button = [...dom.window.document.querySelectorAll('button')].find(item => item.textContent === label);
    assert.ok(button, `button ${label}`);
    await act(async () => { button.dispatchEvent(new dom.window.MouseEvent('click', {bubbles: true})); });
  };
  try {
    const calls: string[] = [];
    await render({auth: auth({enabled: false}), portfolio: view(null, {binding: null, calls})});
    assert.equal(text(), '', 'an unconfigured workspace renders nothing');

    await render({auth: auth({authenticated: false}), portfolio: view(null, {binding: null, calls})});
    assert.match(text(), /Your accountRead-onlySign in to see the wallet linked to your account\./);
    assert.match(text(), /Balances only\. No prices, no buying or selling\./);
    assert.deepEqual(buttons(), []);

    await render({auth: auth(), portfolio: view(null, {binding: null, calls})});
    assert.match(text(), /checked once it is verified/);

    await render({auth: auth(), portfolio: view(state({phase: 'loading', portfolio: null, context: null}), {calls})});
    assert.match(text(), /Checking your account…/);
    assert.deepEqual(buttons(), []);

    await render({auth: auth(), portfolio: view(state({}), {calls})});
    assert.match(text(), new RegExp(`Checked at ${clock}\\.`));
    assert.match(text(), /WalletFVen…S96Z/);
    assert.match(text(), /X@trimmyhq/);
    assert.match(text(), /SOL9,007,199\.254740991/);
    assert.match(text(), /USDC18,446,744,073,709\.551615/);
    assert.match(text(), /Some USDC is in a frozen account\./);
    assert.match(text(), /USDC is held in 2 accounts\./);
    assert.match(text(), /AAPLxAmount not confirmed/);
    assert.match(text(), /share amount is not confirmed yet/);
    assert.equal(text().includes('$'), false, 'no prices or currency values');
    assert.equal(dom.window.document.querySelector('[aria-label]')?.getAttribute('aria-label'), `Wallet address ${wallet}`);
    await click('Check again');
    assert.deepEqual(calls, ['refresh']);

    await render({auth: auth(), portfolio: view(state({phase: 'stale', issue: 'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED'}), {calls})});
    assert.match(text(), new RegExp(`Checked at ${clock}\\. This may have changed\\.`));
    assert.match(text(), /SOL9,007,199\.254740991/);
    assert.deepEqual(buttons(), ['Check again']);

    await render({auth: auth(), portfolio: view(state({phase: 'offline', issue: 'ACCOUNT_DATA_NETWORK_ERROR'}), {calls})});
    assert.match(text(), new RegExp(`You're offline\\. This is what we saw at ${clock}\\.`));
    assert.deepEqual(buttons(), []);

    await render({auth: auth(), portfolio: view(state({phase: 'offline', portfolio: null, context: null, issue: 'ACCOUNT_CONTEXT_UNAVAILABLE'}), {calls})});
    assert.match(text(), /Account details are not available on this server yet\./);
    assert.equal(text().includes('offline'), false);

    await render({auth: auth(), portfolio: view(state({phase: 'error', portfolio: null, walletAddress: null,
      context: {...context, embeddedSolanaWallet: {status: 'missing'}}, issue: 'ACCOUNT_HOLDINGS_WALLET_MISSING'}), {calls})});
    assert.match(text(), /No wallet is linked to this account yet\./);
    assert.match(text(), /X@trimmyhq/);
    assert.equal(text().includes('SOL'), false);
    assert.deepEqual(buttons(), ['Check again']);

    await render({auth: auth(), portfolio: view(state({phase: 'error', portfolio: null, context: null, issue: 'ACCOUNT_CONTEXT_UNAUTHENTICATED'}), {calls})});
    assert.match(text(), /Sign in again to see your account\./);
    await click('Try again');
    assert.deepEqual(calls, ['refresh', 'retry']);

    await render({auth: auth(), portfolio: view(null, {errorCode: 'ACCOUNT_DATA_INVALID_CONFIGURATION', calls})});
    assert.match(text(), /Your account could not be checked\./);
    assert.deepEqual(buttons(), []);
  } finally {
    await act(async () => { root.unmount(); });
    for (const [name, descriptor] of descriptors) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else delete (globalThis as Record<string, unknown>)[name];
    }
    dom.window.close();
  }
});
