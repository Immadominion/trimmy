/**
 * Own money for the signed-in account: the account-scoped Paper/Real mode, the
 * embedded Solana wallet and its holdings, trading capabilities, live order
 * sessions, and the Add money sheet. Guests only ever see Paper.
 *
 * Entry points for other screens: `useMoney()` and `useMoney().openFundWallet()`
 * (the deposit sheet), documented in apps/web/README.md.
 */
import {Component, useCallback, useContext, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode} from 'react';
import {ProductPrivyMountedContext, type ProductAccountAccess} from '../product-auth.js';
import {LiveOrderClient} from './live-order-client.js';
import type {TradingCapabilities} from './live-trading.js';
import {closedWallet, consumeRealIntent, MoneyContext, type MoneyApi} from './money-api.js';
import {LiveOrderSession} from './order-session.js';
import {browserMoneyStorage, IssuerTermsStore, MoneyModeStore, PendingOrderStore, type MoneyStorage} from './stores.js';
import {AccountWalletClient} from './wallet-client.js';
import {MoneyWallet} from './wallet-controller.js';
import {loadProductWalletSdk, type EmbeddedSolanaSnapshot, type ProductWalletSdkPort} from './wallet-sdk-loader.js';
import {FundWalletSheet} from './fund-wallet-sheet.js';

class BridgeBoundary extends Component<{onFailure(): void; children: ReactNode}, {failed: boolean}> {
  override state = {failed: false};
  static getDerivedStateFromError() {return {failed: true};}
  override componentDidCatch() {this.props.onFailure();}
  override render() {return this.state.failed ? null : this.props.children;}
}
/** Runs Privy's wallet hooks below its provider and keeps the latest snapshot for async flows. */
function WalletBridge({sdk, holder, onChange}: {sdk: ProductWalletSdkPort; holder: {current: EmbeddedSolanaSnapshot | null}; onChange(key: string): void}) {
  const snapshot = sdk.useEmbeddedSolana();
  holder.current = snapshot;
  const key = `${snapshot.ready}|${snapshot.subject}|${snapshot.wallets?.map(wallet => wallet.address).join(',') ?? 'invalid'}|${snapshot.signable.join(',')}`;
  useEffect(() => onChange(key), [key, onChange]);
  useEffect(() => () => {holder.current = null;}, [holder]);
  return null;
}

export interface MoneyProviderProps {
  readonly apiBase: string | null;
  readonly accountAccess: ProductAccountAccess | null;
  /** Tests inject the Privy wallet boundary; production loads it below Privy's provider. */
  readonly walletSdk?: ProductWalletSdkPort;
  readonly fetch?: typeof globalThis.fetch;
  readonly storage?: MoneyStorage | null;
  readonly children: ReactNode;
}

export function MoneyProvider({apiBase, accountAccess, walletSdk, fetch, storage: suppliedStorage, children}: MoneyProviderProps) {
  const privyMounted = useContext(ProductPrivyMountedContext);
  const storage = useMemo(() => suppliedStorage === undefined ? browserMoneyStorage() : suppliedStorage, [suppliedStorage]);
  const [sdk, setSdk] = useState<ProductWalletSdkPort | null>(walletSdk ?? null);
  const [sdkFailed, setSdkFailed] = useState(false);
  const holder = useRef<EmbeddedSolanaSnapshot | null>(null);
  const [bridgeKey, setBridgeKey] = useState('');
  const account = apiBase && accountAccess ? accountAccess : null;
  useEffect(() => {
    if (walletSdk || !account || !privyMounted) return;
    let active = true;
    void loadProductWalletSdk().then(value => {if (active) setSdk(value);}, () => {if (active) setSdkFailed(true);});
    return () => {active = false;};
  }, [walletSdk, account, privyMounted]);

  const setup = useMemo(() => {
    if (!apiBase || !account) return null;
    const bearer = async () => account.signal.aborted ? null : account.freshAccessToken();
    const request = fetch ?? globalThis.fetch.bind(globalThis);
    const wallet = new MoneyWallet({access: account, embedded: () => holder.current,
      client: new AccountWalletClient({baseUrl: apiBase, accountId: account.accountId, bearer, fetch: request})});
    return {wallet, orders: new LiveOrderClient({baseUrl: apiBase, bearer, fetch: request, signal: account.signal}),
      mode: new MoneyModeStore(storage, apiBase, account.accountId), terms: new IssuerTermsStore(storage, account.accountId),
      pending: new PendingOrderStore(storage, apiBase, account.accountId)};
  }, [apiBase, account, fetch, storage]);
  useEffect(() => () => setup?.wallet.close(), [setup]);

  const noopSubscribe = useCallback(() => () => {}, []);
  const wallet = useSyncExternalStore(setup?.wallet.subscribe ?? noopSubscribe, setup?.wallet.getState ?? (() => closedWallet));
  const [real, setRealState] = useState(() => {
    if (!setup) return false;
    if (setup.mode.real) return true;
    // A guest who chose Real before signing in lands in Real once the account is verified.
    if (!consumeRealIntent()) return false;
    setup.mode.set(true);
    return true;
  });
  const [capabilities, setCapabilities] = useState<TradingCapabilities | null>(null);
  const [capabilitiesFailed, setCapabilitiesFailed] = useState(false);
  const [fundWalletOpen, setFundWalletOpen] = useState(false);
  const capabilitiesRequest = useRef<{promise: Promise<void>; at: number} | null>(null);
  const [clock, setClock] = useState(Date.now);

  const refreshCapabilities = useCallback((force = false): Promise<void> => {
    const orders = setup?.orders;
    if (!orders) return Promise.resolve();
    const recent = capabilitiesRequest.current;
    if (recent && (!force || Date.now() - recent.at < 1_000) && Date.now() - recent.at < 60_000) return recent.promise;
    const promise = orders.capabilities().then(value => {setCapabilities(value); setCapabilitiesFailed(false);},
      () => {if (orders.current) {setCapabilitiesFailed(true); capabilitiesRequest.current = null;}});
    capabilitiesRequest.current = {promise, at: Date.now()};
    return promise;
  }, [setup]);
  const refreshWallet = useCallback(() => setup?.wallet.refresh() ?? Promise.resolve(), [setup]);

  // Real mode keeps holdings current while the page is visible, like mobile's 25-second refresh.
  useEffect(() => {
    if (!setup || !real) return;
    const update = () => {if (document.visibilityState !== 'hidden' && navigator.onLine) void setup.wallet.refresh();};
    void refreshCapabilities(); update();
    const timer = window.setInterval(() => {update(); setClock(Date.now());}, 25_000);
    window.addEventListener('focus', update); window.addEventListener('online', update); document.addEventListener('visibilitychange', update);
    return () => {clearInterval(timer); window.removeEventListener('focus', update); window.removeEventListener('online', update); document.removeEventListener('visibilitychange', update);};
  }, [setup, real, refreshCapabilities]);

  const setReal = useCallback((next: boolean) => {
    if (!setup) return;
    setup.mode.set(next); setRealState(next);
  }, [setup]);
  const openFundWallet = useCallback(() => {
    if (setup && !real) setReal(true);
    setFundWalletOpen(true);
  }, [setup, real, setReal]);
  const sdkState = !account ? 'unavailable' : sdkFailed || !sdk && !privyMounted ? 'unavailable' : holder.current?.ready ? 'ready' : 'loading';
  void bridgeKey; void clock;
  const api: MoneyApi = {
    available: setup !== null, accountId: account?.accountId ?? null, real: setup !== null && real, setReal,
    wallet, walletFresh: setup?.wallet.fresh() ?? false, walletSdk: sdkState, canSetUpWallet: setup?.wallet.canSetUpWallet ?? false,
    setUpWallet: () => setup?.wallet.setUpWallet() ?? Promise.resolve('unavailable' as const), refreshWallet,
    capabilities, capabilitiesFailed, refreshCapabilities, terms: setup?.terms ?? null, orders: setup?.orders ?? null,
    createOrderSession: () => setup ? new LiveOrderSession({client: setup.orders, wallet: setup.wallet, pending: setup.pending,
      visible: () => document.visibilityState !== 'hidden'}) : null,
    fundWalletOpen, openFundWallet, closeFundWallet: () => setFundWalletOpen(false),
  };
  return <MoneyContext.Provider value={api}>
    {sdk && account && <BridgeBoundary onFailure={() => setSdkFailed(true)}><WalletBridge sdk={sdk} holder={holder} onChange={setBridgeKey}/></BridgeBoundary>}
    {children}
    {fundWalletOpen && <FundWalletSheet onClose={() => setFundWalletOpen(false)}/>}
  </MoneyContext.Provider>;
}
