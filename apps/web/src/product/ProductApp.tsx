import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {productApiBase} from './config';
import {ProductMarketClient} from './market-client';
import type {StockCard} from './market-client';
import {PracticeClient} from './practice-client';
import type {CareerMissionBoard, CareerSummary, PaperPortfolio, PaperReceipt, ProductProfile} from './practice-client';
import {PracticeSession} from './practice-session';
import type {PracticeStorage} from './practice-session';
import {MarketScreen} from './market-screen';
import {StockScreen} from './stock-screen';
import {FirstDay} from './onboarding';
import {WebProfile} from './web-profile';
import {useCompanyIdentities} from './company-identity';
import {useProgress} from './use-progress';
import {useWorkdays, type WorkdaysState} from './use-workdays';
import {useWorkSound} from './work-sound';
import {CareerJourneyScreen, WorkdayEntry, canOpenWork} from './career-journey-screen';
import {WorkdayScreen} from './workday-screen';
import {scheduleNotice} from './workday-schedule';
import {DailyStoryScreen} from './progress-screens';
import {ProductAuthProvider, useProductAuth, type ProductAuthConfig, type ProductAccountAccess, type ConnectProductAccount} from './product-auth';
import type {ProductAuthSdkPort} from './product-auth-sdk-loader';
import {createProductAccountConnector} from './product-account';
import {SignInScreen} from './sign-in-screen';
// Own money (Real mode): see money/money-api.ts for the entry points other screens use.
import {MoneyProvider} from './money/money-context';
import {requestRealAfterSignIn, useMoney, type MoneyApi} from './money/money-api';
import {MoneyModeSwitch, RealBalanceCard, RealHoldings} from './money/real-desk';
import {TradeHistoryScreen} from './money/trade-history';
import {FastBuySheet as LiveFastBuySheet, type FastBuyChoice} from './money/fast-buy-sheet';
import type {ProductWalletSdkPort} from './money/wallet-sdk-loader';
import type {MoneyStorage} from './money/stores';
import {coherentHoldings} from './money/wallet-controller';
import {JourneyScreens} from './journey-screens';
import {useFirstDayJourney} from './use-first-day-journey';
import {isJourneyScreen} from './journey';
import type {SignInIntent} from './journey-store';
import {openFundWallet, registerFundWalletOpener, type FundWalletSource} from './fund-wallet';
import {GuestDeskRecovery} from './guest-desk-recovery';
import {SettingsScreen, type PaperResetOutcome} from './settings-screen';
import {ProductApiClient} from './product-api';
import {PAPER_RESET_CONFIRMATION, PendingMutations, ambiguous, careerApi, newMutationId, type PaperResetWrite} from './career-actions';
import {useReasonPrivacy} from './use-reason-privacy';
import {rankName, useCareerMilestones} from './career-milestones';
import {useCareerDayContext} from './use-career-day-context';
import {useFollowing, useSearchRecents} from './market-social';
import type {CompanySocial} from './company-social';
import {CommunityPreview, CommunityScreen} from './community-screen';
import {FastBuySheet as PracticeFastBuySheet} from './fast-buy';
import {HomeActions, HomeInvitations, type HomeParity} from './home-extras';
import {EntryDoodle, type DoodleScene} from './entry-doodle';
import {useHoldingPrices} from './money/holding-values';
import {PracticeError} from './practice-client';
import {CompanyLogo, Failure, Loading, SalArt, art, dateLabel, errorCopy, micros, scrollBehavior, shares, sharesPlain} from './ui';
import {useT, type Translator} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';
import * as fmt from '../i18n/format';
import {onboardingStep, startupStage, UsageProvider, useUsageObserver} from './usage';
import type {ProductEvents} from './product-events';

type Page = 'desk' | 'market' | 'career' | 'profile' | 'start' | 'welcome' | 'sign-in' | 'daily' | 'work' | 'history' | 'settings' | 'community' | 'updates';

type Route = {page: Page; assetId?: string; mint?: string; assignmentId?: string};
const pages: readonly {page: Page; title: MessageKey; icon: string}[] = [
  {page: 'desk', title: 'shell.nav.desk', icon: 'nav-plumpy-desk.png'},
  {page: 'market', title: 'shell.nav.market', icon: 'nav-plumpy-market-shop.png'},
  {page: 'career', title: 'shell.nav.career', icon: 'nav-plumpy-career.png'},
  {page: 'profile', title: 'shell.nav.profile', icon: 'nav-plumpy-profile.png'},
];
function readRoute(): Route {
  const [path = '', search = ''] = window.location.hash.replace(/^#\/?/, '').split('?');
  const [page, assetId] = path.split('/');
  if (page === 'work') return {page, ...(assetId && /^[a-z][a-z0-9-]{0,79}$/.test(assetId) ? {assignmentId: assetId} : {})};
  if (page === 'market' && assetId && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(assetId)) {
    const mint = new URLSearchParams(search).get('mint');
    return {page, assetId, ...(mint && /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(mint) ? {mint} : {})};
  }
  return {page: page === 'start' || page === 'welcome' || page === 'sign-in' || page === 'daily' || page === 'history' || page === 'settings' || page === 'community' || page === 'updates' || pages.some(item => item.page === page) ? page as Page : 'desk'};
}
function browserStorage(): PracticeStorage {
  try {return window.localStorage;} catch {return {getItem() {throw new Error('Storage unavailable');}, setItem() {throw new Error('Storage unavailable');}};}
}
type Snapshot = {portfolio: PaperPortfolio | null; profile: ProductProfile | null; career: CareerSummary | null; missions: CareerMissionBoard | null; checkedAt: number | null; profileKnown: boolean};
const emptySnapshot: Snapshot = {portfolio: null, profile: null, career: null, missions: null, checkedAt: null, profileKnown: false};

export interface ProductAppProps {
  readonly apiBase?: string | null;
  readonly practiceClient?: PracticeClient;
  readonly marketClient?: ProductMarketClient;
  readonly storage?: PracticeStorage;
  readonly authConfig?: ProductAuthConfig;
  readonly authSdk?: ProductAuthSdkPort;
  readonly connectAccount?: ConnectProductAccount;
  readonly accountAccess?: ProductAccountAccess;
  /** Own money: tests inject the Privy wallet boundary, transport and storage. */
  readonly walletSdk?: ProductWalletSdkPort;
  readonly moneyFetch?: typeof globalThis.fetch;
  readonly moneyStorage?: MoneyStorage | null;
  /** Client for the social, settings and Career action routes. Defaults to the API origin. */
  readonly productApi?: ProductApiClient;
  /** Usage events (see usage.tsx). The production entry passes one; none records nothing. */
  readonly usage?: ProductEvents | null;
}
export function ProductApp(props: ProductAppProps) {
  const apiBase = props.apiBase === undefined ? productApiBase() : props.apiBase;
  const storage = useMemo(() => props.storage ?? browserStorage(), [props.storage]);
  const client = useMemo(() => props.practiceClient ?? (apiBase ? new PracticeClient({baseUrl: apiBase}) : null), [apiBase, props.practiceClient]);
  const connect = useMemo(() => props.connectAccount ?? (client ? createProductAccountConnector({client, storage}) : async () => {throw new Error('Sign-in unavailable');}), [client, storage, props.connectAccount]);
  return <UsageProvider value={props.usage ?? null}><ProductAuthProvider apiBase={apiBase} connectAccount={connect} {...(props.authConfig ? {config: props.authConfig} : {})} {...(props.authSdk ? {sdk: props.authSdk} : {})}>
    <IdentityWorkspace {...props} apiBase={apiBase} storage={storage} {...(client ? {practiceClient: client} : {})}/>
  </ProductAuthProvider></UsageProvider>;
}
function IdentityWorkspace(props: ProductAppProps) {
  const auth = useProductAuth();
  const tr = useT();
  const binding = useRef<{access: ProductAccountAccess | null; epoch: number}>({access: null, epoch: 0});
  if (binding.current.access !== auth.accountAccess) binding.current = {access: auth.accountAccess, epoch: binding.current.epoch + 1};
  if (auth.phase === 'restoring') return <div className="auth-restore"><img src={art('trimmy-mark.png')} alt="Trimmy"/><Loading>{tr('shell.opening')}</Loading></div>;
  const key = `${props.apiBase ?? 'unconfigured'}:${binding.current.epoch}`;
  return <MoneyProvider key={key} apiBase={props.apiBase ?? null} accountAccess={auth.accountAccess}
    {...(props.walletSdk ? {walletSdk: props.walletSdk} : {})} {...(props.moneyFetch ? {fetch: props.moneyFetch} : {})}
    {...(props.moneyStorage !== undefined ? {storage: props.moneyStorage} : {})}>
    <ProductWorkspace {...props} {...(auth.accountAccess ? {accountAccess: auth.accountAccess} : {})}/>
  </MoneyProvider>;
}
function ProductWorkspace({apiBase = productApiBase(), practiceClient, marketClient, storage, accountAccess, productApi: suppliedProductApi}: ProductAppProps) {
  const auth = useProductAuth();
  const money = useMoney();
  const tr = useT();
  const [fastBuy, setFastBuy] = useState(false);
  // The first day's "Add money" (and any other caller of fund-wallet.ts) opens the money side's
  // deposit sheet, which also switches the account to Real, as mobile does. Only while own money
  // is available; otherwise callers say plainly that deposits aren't open here.
  const {available: moneyAvailable, openFundWallet: openDeposit} = money;
  useEffect(() => moneyAvailable ? registerFundWalletOpener(() => openDeposit()) : undefined, [moneyAvailable, openDeposit]);
  const setup = useMemo(() => {
    if (!apiBase) return {session: null, market: null, error: null};
    try {return {session: new PracticeSession({client: practiceClient ?? new PracticeClient({baseUrl: apiBase}), storage: storage ?? browserStorage(), ...(accountAccess ? {account: accountAccess} : {})}),
      market: marketClient ?? new ProductMarketClient({baseUrl: apiBase}), error: null};}
    catch (error) {return {session: null, market: marketClient ?? new ProductMarketClient({baseUrl: apiBase}), error};}
  }, [apiBase, practiceClient, marketClient, storage, accountAccess]);
  const [route, setRoute] = useState<Route>(readRoute);
  const [snapshot, setSnapshot] = useState<Snapshot>(emptySnapshot);
  const [restoring, setRestoring] = useState(Boolean(setup.session?.hasSavedIdentity));
  const [introInitial, setIntroInitial] = useState<'welcome' | 'note' | 'practice'>('welcome');
  const [introStep, setIntroStep] = useState('welcome');
  const routeRef = useRef(route); routeRef.current = route;
  const introSettled = useRef(false);
  const startupRoutingPending = useRef(Boolean(setup.session?.hasSavedIdentity));
  const [busy, setBusy] = useState(Boolean(setup.session?.hasSavedIdentity));
  const [error, setError] = useState<unknown>(setup.error);
  const [careerError, setCareerError] = useState<unknown>(null);
  const [revision, setRevision] = useState(0);
  const [storageChanged, setStorageChanged] = useState(false);
  const [recovered, setRecovered] = useState(false);
  const [motion, setMotion] = useState(() => {try {return localStorage.getItem('trimmy.web.motion') !== 'off';} catch {return true;}});
  const workSound = useWorkSound();
  const leaveGuard = useRef<(() => Promise<boolean>) | null>(null);
  const navigating = useRef(false);
  const registerLeaveGuard = useCallback((guard: (() => Promise<boolean>) | null) => {leaveGuard.current = guard;}, []);
  const cards = useRef(new Map<string, StockCard>());
  const heading = useRef<HTMLElement>(null);
  // Taps on the tab that is already open, per page: that page goes back to its start.
  const [tabTop, setTabTop] = useState<{page: string; count: number}>({page: '', count: 0});
  const loadEpoch = useRef(0), enterPromise = useRef<Promise<void> | null>(null);
  const restoreJob = useRef<{session: PracticeSession; promise: Promise<unknown>} | null>(null);
  const workspaceActive = useRef(true);
  const {session, market} = setup;
  useEffect(() => {workspaceActive.current = true; return () => {workspaceActive.current = false; ++loadEpoch.current;};}, []);
  const restoreGuest = useCallback(() => {
    if (!session) return Promise.reject(new Error('Practice unavailable'));
    if (restoreJob.current?.session !== session) {
      const promise = session.ensureActive();
      restoreJob.current = {session, promise};
      const release = () => {if (restoreJob.current?.promise === promise) restoreJob.current = null;};
      void promise.then(release, release);
    }
    return restoreJob.current.promise;
  }, [session]);

  const commitNavigation = useCallback((next: Route, replace = false) => {
    const hash = `#${next.page}${next.assetId ? `/${next.assetId}` : next.assignmentId ? `/${next.assignmentId}` : ''}${next.mint ? `?mint=${next.mint}` : ''}`;
    routeRef.current = next;
    if (replace) window.history.replaceState(null, '', hash);
    else if (window.location.hash !== hash) window.history.pushState(null, '', hash);
    setRoute(next); heading.current?.scrollTo?.({top: 0, behavior: 'instant'});
    window.requestAnimationFrame(() => heading.current?.focus());
  }, []);
  const navigate = useCallback((next: Route, replace = false) => {
    if (routeRef.current.page !== 'work' || !leaveGuard.current || (next.page === 'work' && next.assignmentId === routeRef.current.assignmentId)) {commitNavigation(next, replace); return;}
    if (navigating.current) return;
    navigating.current = true;
    void leaveGuard.current().then(allowed => {if (allowed && workspaceActive.current) commitNavigation(next, replace);}).finally(() => {navigating.current = false;});
  }, [commitNavigation]);
  useEffect(() => {const changed = () => {
    // The first-day surface owns Back while a checkpoint or receipt is being saved.
    if (routeRef.current.page === 'start' || routeRef.current.page === 'sign-in') return;
    const next = readRoute();
    if (routeRef.current.page === 'work' && leaveGuard.current) {
      const previous = routeRef.current;
      window.history.replaceState(null, '', `#work${previous.assignmentId ? `/${previous.assignmentId}` : ''}`);
      navigate(next, true); return;
    }
    if (next.page === 'start' && introSettled.current) {navigate({page: 'desk'}, true); return;}
    routeRef.current = next; setRoute(next); heading.current?.scrollTo?.({top: 0, behavior: 'instant'});
  }; window.addEventListener('hashchange', changed); return () => window.removeEventListener('hashchange', changed);}, [navigate]);
  useEffect(() => {if (auth.subject && !auth.authenticated && routeRef.current.page !== 'sign-in') navigate({page: 'sign-in'}, true);}, [auth.subject, auth.authenticated, navigate]);
  useEffect(() => {
    if (!session) return;
    const changed = (event: StorageEvent) => {if (event.key === session.storageKey || event.key === null) {++loadEpoch.current; setSnapshot(emptySnapshot); setStorageChanged(true);}};
    window.addEventListener('storage', changed); return () => window.removeEventListener('storage', changed);
  }, [session]);

  const refresh = useCallback(async () => {
    if (!session?.hasIdentity) return;
    const epoch = ++loadEpoch.current; setBusy(true); setError(null); setCareerError(null);
    const [portfolio, profile, career, missions] = await Promise.allSettled([
      session.readPortfolio(), session.readProfile(), session.readCareerSummary(), session.readMissions(),
    ]);
    if (epoch !== loadEpoch.current) return;
    const currentPortfolio = portfolio.status === 'fulfilled' && portfolio.value.revision >= (session.lastReceipt?.accountRevision ?? 0) ? portfolio.value : null;
    setSnapshot(prior => ({portfolio: portfolio.status === 'rejected' && prior.portfolio && prior.portfolio.revision >= (session.lastReceipt?.accountRevision ?? 0) ? prior.portfolio : currentPortfolio,
      profile: profile.status === 'fulfilled' ? profile.value : prior.profile,
      profileKnown: profile.status === 'fulfilled' || prior.profileKnown,
      career: career.status === 'fulfilled' ? career.value : prior.career,
      missions: missions.status === 'fulfilled' ? missions.value : prior.missions, checkedAt: Date.now()}));
    if (portfolio.status === 'rejected') setError(portfolio.reason);
    else if (currentPortfolio === null) setError(new Error('The desk has not caught up with your receipt yet.'));
    else if (profile.status === 'rejected') setError(profile.reason);
    if (career.status === 'rejected') setCareerError(career.reason);
    else if (missions.status === 'rejected') setCareerError(missions.reason);
    setBusy(false); setRevision(value => value + 1);
  }, [session]);

  const progress = useProgress(session, Boolean(session?.hasIdentity) && !storageChanged && !restoring && !startupRoutingPending.current, route.page, refresh, Boolean(session?.pendingDailyDesk));
  const workCompleted = useCallback(async () => {await Promise.all([refresh(), progress.refresh()]);}, [refresh, progress.refresh]);
  const workdays = useWorkdays(session, Boolean(session?.hasIdentity) && !storageChanged && !restoring && !startupRoutingPending.current, route.page, workCompleted);
  // First-day follow-up (mobile order): celebration, account choice, reminders, money choice.
  const journeyStorage = useMemo(() => storage ?? browserStorage(), [storage]);
  const [fundingUnavailable, setFundingUnavailable] = useState(false);
  const journey = useFirstDayJourney({apiBase, storage: journeyStorage, session, accountId: accountAccess?.accountId ?? null,
    profile: snapshot.profileKnown ? snapshot.profile : undefined, career: snapshot.career, guestDisposition: auth.guestDisposition,
    restoreGuest, refresh, active: () => workspaceActive.current});
  useEffect(() => {if (session?.isAccount) journey.forgetGuestChoice();}, [session, journey.forgetGuestChoice]);
  // Settings, reason privacy and Career actions (mobile parity). Identity is this workspace's desk.
  const productApi = useMemo(() => {
    if (suppliedProductApi) return suppliedProductApi;
    try {return apiBase ? new ProductApiClient({baseUrl: apiBase}) : null;} catch {return null;}
  }, [apiBase, suppliedProductApi]);
  const pendingMutations = useMemo(() => {try {return apiBase ? new PendingMutations(journeyStorage, apiBase) : null;} catch {return null;}}, [apiBase, journeyStorage]);
  const productIdentity = session?.isAccount ? accountAccess ?? null : session?.guest ?? null;
  const reasonPrivacy = useReasonPrivacy({api: productApi, identity: productIdentity, principal: journey.principal, pending: pendingMutations,
    enabled: Boolean(session?.hasIdentity) && !storageChanged && !restoring && (route.page === 'settings' || route.page === 'market' && Boolean(route.assetId))});
  // Market and company social parity: Following (accounts), recents, Holders and Comments.
  const following = useFollowing(productApi, session?.isAccount ? accountAccess ?? null : null);
  const recents = useSearchRecents(journeyStorage, apiBase);
  const marketSocial = {following, recents, onSignIn: () => openSignIn('app')};
  const companySocial: CompanySocial | undefined = productApi ? {api: productApi, identity: productIdentity, accountSignedIn: Boolean(session?.isAccount),
    following, privacy: reasonPrivacy.privacy, onOpenSettings: () => navigate({page: 'settings'}), onSignIn: () => openSignIn('app')} : undefined;
  const careerRefresh = useCallback(async () => {await Promise.all([refresh(), progress.refresh()]);}, [refresh, progress.refresh]);
  const milestones = useCareerMilestones({api: productApi, identity: productIdentity, principal: journey.principal, pending: pendingMutations,
    career: snapshot.career, missions: snapshot.missions, portfolio: snapshot.portfolio, refresh: careerRefresh});
  // Mobile's Career day context: a web-first desk gets this browser's time zone once, then refreshes at each new Career day.
  useCareerDayContext({api: productApi, identity: productIdentity, principal: journey.principal, pending: pendingMutations,
    enabled: Boolean(session?.hasIdentity) && !storageChanged && !restoring && !startupRoutingPending.current && !session?.guestRecovery,
    onConfigured: () => void careerRefresh(), onNewDay: () => {void careerRefresh(); void workdays.refresh();}});
  // Home and community parity: compact Fast buy (practice, or own money in Real mode), Updates, trader invitation and Community.
  const home: HomeParity = {onFastBuy: () => setFastBuy(true),
    onUpdates: session?.isAccount && accountAccess ? () => navigate({page: 'updates'}) : undefined,
    onChooseTrader: snapshot.profile && !snapshot.profile.onboarding.persona ? () => navigate({page: 'profile'}) : undefined,
    community: <CommunityPreview api={productApi} account={session?.isAccount ? accountAccess ?? null : null}
      onOpen={() => session?.isAccount ? navigate({page: 'community'}) : openSignIn('app')}/>};
  const [oneTimeNotice, setOneTimeNotice] = useState<string | null>(null);
  useEffect(() => {const text = journey.store?.consumeOneTimeNotice(); if (text) setOneTimeNotice(text);}, [journey.store]);
  const preservedExpired = useMemo(() => {
    if (auth.guestDisposition !== 'preserved' || !apiBase) return false;
    try {
      const guest = new PracticeSession({client: practiceClient ?? new PracticeClient({baseUrl: apiBase}), storage: journeyStorage});
      const code = guest.claimFailureCode; guest.close(); return code === 'GUEST_SESSION_EXPIRED';
    } catch {return false;}
  }, [auth.guestDisposition, apiBase, practiceClient, journeyStorage]);

  const ensureDesk = useCallback(async () => {
    if (!session) throw setup.error ?? new Error('Practice unavailable');
    if (enterPromise.current) return enterPromise.current;
    const enter = async () => {
      setBusy(true); setError(null);
      try {
        await restoreGuest();
        if (!workspaceActive.current) throw new Error('Desk closed.');
        await session.ensureProfile();
        if (workspaceActive.current) await refresh();
      }
      catch (reason) {if (workspaceActive.current) {setError(reason); setBusy(false);} throw reason;}
    };
    const promise = enter(); enterPromise.current = promise;
    try {await promise;} finally {enterPromise.current = null;}
  }, [session, setup.error, refresh, restoreGuest]);

  function routeRestoredProfile(profile: ProductProfile | null) {
    // Accounts follow their own saved checkpoint, as on mobile. A confirmed order or a
    // later checkpoint belongs to the follow-up screens, never to a second first trade.
    introSettled.current = (profile !== null && profile.launchCheckpoint !== 'first-trade') || profile?.hasConfirmedPaperTrade === true || session?.lastReceipt?.action === 'buy';
    if (routeRef.current.page === 'desk' || routeRef.current.page === 'start' || (routeRef.current.page === 'sign-in' && session?.isAccount)) {
      if (introSettled.current || session?.pendingCommit) navigate({page: 'desk'}, true);
      else {setIntroInitial(profile ? 'practice' : 'welcome'); navigate({page: 'start'}, true);}
    }
  }
  async function retryDesk() {
    try {
      await ensureDesk();
      if (workspaceActive.current && startupRoutingPending.current && session) {
        const profile = await session.readProfile();
        if (workspaceActive.current) {routeRestoredProfile(profile); startupRoutingPending.current = false;}
      }
    } catch (reason) {if (workspaceActive.current) setError(reason);}
  }

  useEffect(() => {
    let active = true;
    if (auth.subject && !session?.isAccount) {setRestoring(false); setBusy(false); return;}
    if (session?.hasSavedIdentity) {
      const restore = restoreGuest();
      void (async () => {
        try {
          await restore;
          if (!active) return;
          const existing = await session.readProfile();
          if (existing || session.isAccount) await ensureDesk(); else await refresh();
          if (!active) return;
          const profile = existing || session.isAccount ? await session.readProfile() : null;
          routeRestoredProfile(profile);
          startupRoutingPending.current = false;
          if (session.isAccount) await followSignInIntent(profile);
        }
        catch (reason) {if (active) {setError(reason); setBusy(false);}}
        finally {if (active) setRestoring(false);}
      })();
    }
    return () => {active = false; ++loadEpoch.current;};
    // Restore once per configured session; refresh never creates a desk.
  }, [session, auth.subject]);

  function start() {setIntroInitial('welcome'); navigate({page: 'welcome'});}
  const firstDayStep = useCallback((step: string) => {
    setIntroStep(step);
    if (step !== 'welcome' && routeRef.current.page !== 'start') {routeRef.current = {page: 'start'}; setRoute({page: 'start'});}
  }, []);
  /** Skip leaves the introduction. A confirmed order instead resumes its follow-up screens. */
  async function exitIntroduction(completed: boolean) {
    if (!session) throw new Error('Practice unavailable');
    await restoreGuest();
    if (!workspaceActive.current) return;
    // Replaying a saved exit can already return app. Never send a second transition.
    const profile = await session.ensureProfile();
    if (!workspaceActive.current) return;
    if (!completed && profile.launchCheckpoint !== 'app') await session.advanceLaunch('introduction-skipped');
    if (!workspaceActive.current) return;
    introSettled.current = true;
    await refresh();
    if (workspaceActive.current) navigate({page: 'desk'}, true);
  }
  /** The money choice ends the introduction; the server verifies the confirmed order first. */
  async function finishIntroduction(addMoney: boolean) {
    if (!session) throw new Error('Practice unavailable');
    await restoreGuest();
    if (!workspaceActive.current) return;
    const profile = await session.ensureProfile();
    if (!workspaceActive.current) return;
    if (profile.launchCheckpoint !== 'app') await session.advanceLaunch('introduction-completed');
    if (!workspaceActive.current) return;
    introSettled.current = true;
    await refresh();
    if (!workspaceActive.current) return;
    navigate({page: 'desk'}, true);
    if (addMoney) requestFunding('first-day');
  }
  /** A nav tap. The tab already open goes back to its start instead of reloading. */
  function tabTapped(page: Route['page']) {
    const current = routeRef.current;
    if (current.page !== page || current.assetId) {navigate({page}); return;}
    heading.current?.scrollTo?.({top: 0, behavior: scrollBehavior(motion)});
    setTabTop(prior => ({page, count: prior.page === page ? prior.count + 1 : 1}));
  }
  function openSignIn(intent: SignInIntent | null = null) {journey.setSignInIntent(intent); navigate({page: 'sign-in'});}
  /** Deposits need an account first, as mobile's `_openFunding` does (see fund-wallet.ts). */
  function requestFunding(source: FundWalletSource) {
    if (!session?.isAccount) {openSignIn('fund'); return;}
    setFundingUnavailable(!openFundWallet(source));
  }
  async function followSignInIntent(profile: ProductProfile | null) {
    const intent = journey.consumeSignInIntent();
    // Signing in from the app keeps the person in the app (mobile's _skipIntroAfterAuth).
    if (intent === 'app' && profile && profile.launchCheckpoint !== 'app') await exitIntroduction(false);
    else if (intent === 'fund' && workspaceActive.current) requestFunding('first-day');
  }
  /** Explicit, confirmed replacement of an expired guest desk. The old record is archived, never deleted. */
  async function startNewGuestDesk() {
    if (!session) throw new Error('Practice unavailable');
    await session.startNewGuestDesk();
    if (!workspaceActive.current) return;
    ++loadEpoch.current; setError(null); setSnapshot(emptySnapshot); introSettled.current = false;
    setIntroInitial('welcome'); navigate({page: 'start'}, true);
  }
  /** Mobile's settings reset: the exact command is saved before dispatch and replayed after an ambiguous result. */
  async function resetPaperDesk(): Promise<PaperResetOutcome> {
    const principal = journey.principal, portfolio = snapshot.portfolio;
    if (!session || !productApi || !productIdentity || !principal || !pendingMutations || !portfolio || session.pendingCommit) {
      throw new PracticeError('PAPER_RESET_UNAVAILABLE', 'Paper reset is unavailable.');
    }
    const saved = pendingMutations.read<PaperResetWrite>('paper-reset', principal);
    const body: PaperResetWrite = saved ?? {schemaVersion: 1, mutationId: newMutationId(), baseRevision: portfolio.revision, confirm: PAPER_RESET_CONFIRMATION};
    if (!saved) pendingMutations.save('paper-reset', principal, body);
    try {
      const receipt = await careerApi.resetPaper(productApi, productIdentity, body);
      pendingMutations.clear('paper-reset', principal);
      const current = await session.readPortfolio().catch(() => null);
      if (workspaceActive.current) await refresh();
      const newerActivity = current !== null && current.revision > receipt.revision;
      return {cashPaperMicros: newerActivity ? current.cashPaperMicros : receipt.cashPaperMicros, newerActivity};
    } catch (error) {
      if (!ambiguous(error)) pendingMutations.clear('paper-reset', principal);
      if (error instanceof PracticeError && error.code === 'PAPER_PORTFOLIO_CHANGED' && workspaceActive.current) await refresh();
      throw error;
    } finally {setRevision(value => value + 1);}
  }
  /** Account-only and irreversible; the session ends locally after the API confirms, as on mobile. */
  async function closeAccount() {
    if (!productApi || !session?.isAccount || !accountAccess) throw new PracticeError('ACCOUNT_CLOSURE_UNAVAILABLE', 'Account closure is unavailable.');
    const result = await careerApi.closeAccount(productApi, accountAccess);
    journey.store?.setOneTimeNotice(result.note);
    navigate({page: 'welcome'}, true);
    await auth.logout();
  }
  async function chooseGuest() {
    // A half-finished provider sign-in is dropped before the explicit guest choice is saved.
    if (auth.subject && !(await auth.logout())) throw new Error('Sign-out did not finish.');
    await journey.chooseGuest();
    if (routeRef.current.page === 'sign-in') navigate({page: 'desk'}, true);
  }
  const [celebrationHint, setCelebrationHint] = useState<{orderId: string; name: string; logoUrl: string | null} | null>(null);
  async function introCommitted(receipt: PaperReceipt, company?: {readonly name: string; readonly logoUrl: string | null}) {
    if (!workspaceActive.current) return;
    if (company) setCelebrationHint({orderId: receipt.id, ...company});
    ++loadEpoch.current;
    setSnapshot(prior => ({...prior, portfolio: null, career: null, missions: null}));
    setRevision(value => value + 1);
    await refresh();
  }
  async function committed(_receipt: PaperReceipt) {
    if (!workspaceActive.current) return;
    ++loadEpoch.current;
    setSnapshot(prior => ({...prior, portfolio: null, career: null, missions: null}));
    setBusy(true);
    setRevision(value => value + 1);
    // A first confirmed order opens mobile's follow-up (celebration, account choice,
    // reminders, money choice). An order never finishes the introduction by itself.
    if (workspaceActive.current) await refresh();
  }
  async function recover() {
    if (!session || busy) return; setBusy(true); setError(null);
    try {const receipt = await session.retryPendingCommit(); if (receipt) {setRecovered(true); await committed(receipt); if (workspaceActive.current && routeRef.current.page === 'start') {introSettled.current = true; navigate({page: 'desk'}, true);}}}
    catch (reason) {setError(reason);}
    finally {setBusy(false); setRevision(value => value + 1);}
  }
  useEffect(() => {
    if (!session || restoring || startupRoutingPending.current || !['desk', 'career', 'profile', 'daily', 'work'].includes(route.page)) return;
    let running = false;
    const update = async () => {
      if (running || document.visibilityState === 'hidden' || !navigator.onLine || !session.hasIdentity || session.pendingCommit) return;
      running = true; try {await refresh();} finally {running = false;}
    };
    const resume = () => void update();
    resume();
    const timer = window.setInterval(resume, 30000);
    window.addEventListener('online', resume); window.addEventListener('focus', resume); document.addEventListener('visibilitychange', resume);
    return () => {clearInterval(timer); window.removeEventListener('online', resume); window.removeEventListener('focus', resume); document.removeEventListener('visibilitychange', resume);};
  }, [session, route.page, restoring, refresh]);

  function select(card: StockCard) {cards.current.set(card.assetId, card); navigate({page: 'market', assetId: card.assetId, ...(card.primaryVariant ? {mint: card.primaryVariant.mint} : {})});}
  // Paper/Real is account-scoped. A guest who asks for Real signs in first, then lands in Real.
  function switchMoneyMode() {
    if (money.available) {money.setReal(!money.real); return;}
    requestRealAfterSignIn(); navigate({page: 'sign-in'});
  }
  function openFastBuyChoice(choice: FastBuyChoice) {
    setFastBuy(false);
    if (choice.card) cards.current.set(choice.assetId, choice.card);
    navigate({page: 'market', assetId: choice.assetId, ...(choice.mint ? {mint: choice.mint} : {})});
  }
  function motionSetting(value: boolean) {
    try {localStorage.setItem('trimmy.web.motion', value ? 'on' : 'off'); setMotion(value);} catch {setError(new Error('Motion preference could not be saved.'));}
  }
  async function changePersona(persona: 'wolf' | 'oracle' | 'shark') {
    if (!session) throw new Error('Your profile is unavailable.');
    const profile = await session.updatePersona(persona);
    if (!workspaceActive.current) return;
    setSnapshot(prior => ({...prior, profile}));
    await refresh();
  }
  const assignment = workdays.journey?.assignments.find(item => item.id === route.assignmentId) ?? (!route.assignmentId ? workdays.journey?.assignments.find(item => !item.completedAt) : undefined);
  const openWork = (id: string) => {workSound.play('paper'); navigate({page: 'work', assignmentId: id});};
  const selectedCard = route.assetId ? cards.current.get(route.assetId) : undefined;
  const hasGuest = Boolean(session?.hasIdentity);
  const signIn = route.page === 'sign-in' || (auth.subject !== null && !auth.authenticated) || auth.phase === 'connecting' || auth.phase === 'account-choice';
  const guestRecovery = session && !storageChanged ? session.guestRecovery : null;
  const journeyScreen = Boolean(apiBase && session && market && !storageChanged && !restoring && !guestRecovery && (isJourneyScreen(journey.view) || journey.preservedNotice));
  const recoveryScreen = guestRecovery !== null && !signIn;
  const firstDay = !journeyScreen && !recoveryScreen && !signIn && (route.page === 'start' || route.page === 'welcome' || (route.page === 'desk' && !hasGuest && !busy));

  const onboarding = firstDay || signIn || journeyScreen || recoveryScreen;
  useUsageObserver({
    page: onboarding ? 'onboarding' : route.page,
    step: onboardingStep({journey: journeyScreen && !journey.preservedNotice ? journey.view.kind : null, intro: firstDay ? introStep : null,
      home: !onboarding && route.page === 'desk' && hasGuest}),
    workday: route.page === 'work' && assignment ? {ordinal: assignment.ordinal, resumed: assignment.step > 0 || assignment.draft !== ''} : null,
    waiting: workdays.journey?.schedule?.state ?? null,
    fastBuy, addMoney: money.fundWalletOpen, send: money.sendOpen, real: money.real,
    failed: startupStage(error),
    desk: session && hasGuest ? {key: accountAccess?.accountId ?? session.guest?.guestId ?? 'desk', authorization: () => session.authorizationHeader()} : null,
  });
  // Mirrors the render order below: recovery, then the journey, then sign-in, then the first day.
  const doodle: DoodleScene | null = !onboarding ? null : recoveryScreen ? 'preserved'
    : journeyScreen ? (journey.preservedNotice ? 'preserved' : journey.view.kind === 'gate' ? 'account' : journey.view.kind === 'celebration' ? 'order'
      : journey.view.kind === 'reminders' ? 'reminders' : 'money')
    : signIn ? 'account' : introStep === 'receipt' ? 'order' : introStep === 'note' || introStep === 'practice' || introStep === 'review' ? introStep : 'welcome';
  return <div className={`product-shell${onboarding ? ' onboarding-shell' : ''}${doodle ? ' entry-split' : ''}${route.page === 'market' && !route.assetId ? ' market-shell' : ''}${route.page === 'career' || route.page === 'daily' && !progress.pending ? ' career-shell' : ''}`} data-revision={revision}>
    <a className="skip" href="#main-content" onClick={event => {event.preventDefault(); heading.current?.focus();}}>{tr('shell.skipToContent')}</a>
    <aside className="product-nav"><button className="product-brand" aria-label={tr('shell.nav.brandLabel')} onClick={() => navigate({page: 'desk'})}><img src={art('trimmy-mark.png')} alt=""/>trimmy</button>
      {money.real && <span className="nav-money-mode" role="status">{tr('shell.nav.realMoney')}</span>}
      <nav aria-label={tr('shell.nav.label')}>{pages.map(item => <button key={item.page} aria-current={route.page === item.page || (route.page === 'daily' || route.page === 'work') && item.page === 'career' || route.page === 'settings' && item.page === 'profile' ? 'page' : undefined} onClick={() => tabTapped(item.page)}><img src={art(`icons/${item.icon}`)} alt=""/><span>{tr(item.title)}</span></button>)}</nav>
      {(snapshot.profile?.onboarding.persona || auth.logins.length > 0) && <button className="nav-identity" onClick={() => navigate({page:'profile'})}><img src={art(snapshot.profile?.onboarding.persona ? `persona-${snapshot.profile.onboarding.persona}-avatar-v1.png` : 'icons/nav-plumpy-profile.png')} alt=""/><span><strong>{snapshot.profile?.onboarding.handle ? `@${snapshot.profile.onboarding.handle}` : auth.logins[0]?.label ?? tr('shell.nav.yourDesk')}</strong>{snapshot.career && <small>{rankName(snapshot.career.rank)}</small>}</span></button>}
    </aside>
    <div className="product-body">{(firstDay || signIn || journeyScreen || recoveryScreen) && <header className="onboard-header"><span className="product-brand"><img src={art('trimmy-mark.png')} alt=""/>trimmy</span>{firstDay && <button className="text-button" onClick={() => navigate({page: 'sign-in'})}>{tr('common.signIn')}</button>}</header>}
      <main id="main-content" ref={heading} tabIndex={-1} className="product-main">
      {!apiBase ? <div className="empty-page"><SalArt motion={motion}/><h1>{tr('shell.unconfigured.title')}</h1><p>{tr('shell.unconfigured.body')}</p></div>
      : storageChanged ? <div className="empty-page"><h1>{tr('shell.storageChanged.title')}</h1><p>{tr('shell.storageChanged.body')}</p><button className="primary" onClick={() => window.location.reload()}>{tr('shell.storageChanged.reload')}</button></div>
      : <>
        {error !== null && !recoveryScreen && !guestRecovery && <Failure title={tr('shell.deskError.title')} message={errorCopy(error)} onRetry={() => void retryDesk()}/>}
        {session?.pendingCommit && <div className="pending-order" role="status"><strong>{tr('shell.pendingOrder.title')}</strong><p>{tr('shell.pendingOrder.body')}</p><button className="text-button" disabled={busy} onClick={() => void recover()}>{busy ? tr('common.checking') : tr('shell.pendingOrder.check')}</button></div>}
        {recovered && <div className="notice" role="status">{tr('shell.recovered')}<button className="text-button" onClick={() => setRecovered(false)}>{tr('common.dismiss')}</button></div>}
        {workdays.pending && !['career', 'work', 'daily'].includes(route.page) && <div className="work-recovery" role="status"><span>{tr('shell.workPending.title')}</span><button className="text-button" disabled={workdays.working} onClick={() => void workdays.recover()}>{workdays.working ? tr('common.checking') : tr('shell.workPending.check')}</button></div>}
        {oneTimeNotice && !journeyScreen && <div className="notice" role="status">{oneTimeNotice}<button className="text-button" onClick={() => setOneTimeNotice(null)}>{tr('common.dismiss')}</button></div>}
        {fundingUnavailable && !journeyScreen && !signIn && <div className="notice" role="status">{tr('shell.fundingUnavailable')}<button className="text-button" onClick={() => setFundingUnavailable(false)}>{tr('common.dismiss')}</button></div>}
        {recoveryScreen && guestRecovery ? <GuestDeskRecovery failure={guestRecovery} canSignIn={auth.enabled} onSignIn={() => openSignIn('app')} onStartNew={startNewGuestDesk}/>
        : journeyScreen && market ? <JourneyScreens journey={journey} market={market} career={snapshot.career} portfolio={snapshot.portfolio} careerLoading={busy && !snapshot.career}
          motion={motion} preservedExpired={preservedExpired} onGuest={chooseGuest} onAccount={() => navigate({page: 'desk'}, true)}
          onRetryEvidence={() => void refresh()} onFinish={finishIntroduction} hint={celebrationHint}/>
        : signIn ? <SignInScreen motion={motion} hasDesk={hasGuest} expiredGuestRecovery={guestRecovery !== null} onBack={() => {journey.setSignInIntent(null); navigate({page: hasGuest ? 'desk' : 'welcome'}, true);}} onAccount={() => navigate({page: 'desk'}, true)}/> : firstDay && session && market ? (restoring ? <Loading/> : <FirstDay initialStep={introInitial} motion={motion} market={market} session={session} portfolio={snapshot.portfolio} career={snapshot.career} ensureDesk={ensureDesk} onExplore={() => navigate({page: 'market'})} onExit={exitIntroduction} onReceiptContinue={orderId => journey.continueAfterCelebration(orderId)} onCommitted={introCommitted} onPending={() => setRevision(value => value + 1)} onStep={firstDayStep} onSignIn={() => navigate({page: 'sign-in'})}/>) : <>
        {route.page === 'market' && market && <>
          {/* The Market stays mounted under a company page, so Back returns to the same search, list and place. */}
          <MarketScreen client={market} onSelect={select} social={marketSocial} real={money.real} capabilities={money.capabilities} active={!(route.assetId && session)} top={tabTop.page === 'market' ? tabTop.count : 0} motion={motion}/>
          {route.assetId && session && <StockScreen key={`${route.assetId}:${route.mint ?? ''}`} assetId={route.assetId} {...(selectedCard ? {card: selectedCard} : {})} {...(route.mint ? {selectedMint: route.mint} : {})} market={market} session={session} portfolio={snapshot.portfolio} ensureDesk={ensureDesk} onBack={() => navigate({page: 'market'})} onDesk={() => navigate({page: 'desk'})} onCommitted={committed} onPending={() => setRevision(value => value + 1)} onPracticeInPaper={() => money.setReal(false)} {...(companySocial ? {social: companySocial} : {})}/>}
        </>}
        {route.page === 'history' && (money.available ? <TradeHistoryScreen onBack={() => navigate({page: 'desk'})} onOpenAsset={(assetId, mint) => navigate({page: 'market', assetId, mint})}/>
          : <div className="empty-page"><h1>{tr('shell.history.title')}</h1><p>{tr('shell.history.body')}</p><button className="primary" onClick={() => openSignIn('app')}>{tr('common.signIn')}</button></div>)}
        {route.page === 'desk' && market && (busy && !snapshot.portfolio && !money.real ? <Loading/> : snapshot.portfolio || money.real ? <Desk snapshot={snapshot} market={market} workdays={workdays} onWork={openWork} motion={motion} onMarket={() => navigate({page: 'market'})} onCareer={() => navigate({page: 'career'})} onSignIn={auth.authenticated ? undefined : () => openSignIn('app')} onPosition={(assetId, mint) => navigate({page: 'market', assetId, mint})}
          money={money} onSwitchMode={switchMoneyMode} onFastBuy={() => setFastBuy(true)} onHistory={() => navigate({page: 'history'})} home={home}/> : null)}
        {(route.page === 'community' || route.page === 'updates') && (productApi && session?.isAccount && accountAccess
          ? <CommunityScreen key={route.page} api={productApi} account={accountAccess} initialScope={route.page === 'updates' ? 'notifications' : 'everyone'}
            onOpenAsset={assetId => navigate({page: 'market', assetId})} onBack={() => navigate({page: 'desk'})}/>
          : <div className="empty-page"><h1>{tr('shell.community.title')}</h1><p>{tr('shell.community.body')}</p><button className="primary" onClick={() => openSignIn('app')}>{tr('common.signIn')}</button></div>)}
        {fastBuy && market && (money.real ? <LiveFastBuySheet market={market} knownCards={cards.current} onOpen={openFastBuyChoice} onClose={() => setFastBuy(false)}/>
          : session && <PracticeFastBuySheet market={market} session={session} portfolio={snapshot.portfolio} ensureDesk={ensureDesk}
          onCommitted={committed} onPending={() => setRevision(value => value + 1)} saveReason={productApi ? milestones.saveReasonFor : null} onClose={() => setFastBuy(false)}/>)}
        {(route.page === 'career' || route.page === 'daily' && !progress.pending) && (!hasGuest ? <GuestInvitation title={tr('shell.guest.careerTitle')} onStart={start} motion={motion}/> : <CareerJourneyScreen workdays={workdays} career={snapshot.career} missions={snapshot.missions} week={progress.week} progressError={careerError !== null} onRetry={() => {void refresh(); void progress.refresh();}} onMarket={() => navigate({page: 'market'})} onOpen={openWork} motion={motion} sound={workSound.enabled} onSound={workSound.toggle} milestones={milestones} top={tabTop.page === 'career' ? tabTop.count : 0}/>)}
        {progress.pending && route.page !== 'daily' && <div className="work-recovery" role="status"><span>{tr('shell.dailyPending.title')}</span><button className="text-button" onClick={() => navigate({page:'daily'})}>{tr('shell.dailyPending.check')}</button></div>}
        {route.page === 'daily' && progress.pending && <DailyStoryScreen progress={progress} onBack={() => navigate({page:'career'})}/>}
        {route.page === 'work' && (!hasGuest ? <GuestInvitation title={tr('shell.guest.workTitle')} onStart={start} motion={motion}/> : assignment ? canOpenWork(assignment, workdays.journey!.assignments) ? <WorkdayScreen key={assignment.id} assignment={assignment} working={workdays.working} error={workdays.error} pending={Boolean(workdays.pending)} onSubmit={workdays.saveStep} onSaveDraft={workdays.saveDraft} onRecover={workdays.recover} onBack={() => commitNavigation({page:'career'})} registerLeaveGuard={registerLeaveGuard} onCue={workSound.play} next={scheduleNotice(workdays.journey)}/> : <div className="empty-page"><h1>{assignment.title}</h1><p>{tr('shell.work.locked', {day: assignment.ordinal - 1})}</p><button className="primary" onClick={() => navigate({page:'career'})}>{tr('shell.work.backToCareer')}</button></div> : workdays.journey?.upcoming && workdays.journey.upcoming.id === route.assignmentId ? <div className="empty-page"><h1>{workdays.journey.upcoming.title}</h1><p>{scheduleNotice(workdays.journey)?.body}</p><button className="primary" onClick={() => navigate({page:'career'})}>{tr('shell.work.backToCareer')}</button></div> : workdays.loading ? <Loading>{tr('shell.work.opening')}</Loading> : <div className="empty-page"><h1>{tr('shell.work.failed')}</h1><button className="text-button" onClick={() => void workdays.refresh()}>{tr('common.tryAgain')}</button><button className="primary" onClick={() => navigate({page:'career'})}>{tr('shell.work.backToCareer')}</button></div>)}
        {route.page === 'settings' && <SettingsScreen signedIn={Boolean(session?.isAccount)} authBusy={auth.busy} handle={snapshot.profile?.onboarding.handle ?? null} logins={auth.logins}
          persona={snapshot.profile?.onboarding.persona ? personaName(tr, snapshot.profile.onboarding.persona) : null}
          paperLimit={snapshot.career?.rank.paperLimit ?? null} reminder={journey.reminder} remindersAvailable={journey.principal !== null}
          onSaveReminder={journey.saveReminder} sound={workSound.enabled} onSound={workSound.toggle} motion={motion} onMotion={motionSetting}
          privacy={hasGuest ? reasonPrivacy : null}
          resetAvailable={hasGuest && Boolean(snapshot.portfolio) && !session?.pendingCommit}
          resetPending={Boolean(journey.principal && pendingMutations?.read('paper-reset', journey.principal))} onResetPaper={resetPaperDesk}
          closeAvailable={Boolean(session?.isAccount && accountAccess)} onCloseAccount={closeAccount}
          onSignIn={() => openSignIn('app')} onSignOut={() => {navigate({page: 'sign-in'}, true); void auth.logout();}}
          onTrader={() => navigate({page: 'profile'})} onAddMoney={() => requestFunding('settings')} onBack={() => navigate({page: 'profile'})}/>}
        {route.page === 'profile' && <WebProfile onSettings={() => navigate({page: 'settings'})} profile={snapshot.profile} career={snapshot.career} missions={snapshot.missions} hasIdentity={hasGuest} signedIn={auth.authenticated} accountLabel={auth.logins[0]?.label ?? null} authBusy={auth.busy} busy={busy} progressError={careerError !== null} motion={motion} onMotion={motionSetting} onStart={start} onCareer={() => navigate({page: 'career'})} onSignIn={() => openSignIn('app')} onSignOut={() => {navigate({page: 'sign-in'}, true); void auth.logout();}} onRetry={() => void refresh()} {...(hasGuest ? {onPersona: changePersona} : {})}/>}
        </>}
      </>}
      </main>
    </div>
    {doodle && <EntryDoodle scene={doodle} motion={motion}/>}
  </div>;
}

/** Real mode can open before the paper desk loads; the paper side then reads as empty, never as a balance. */
const emptyPortfolio: PaperPortfolio = {schemaVersion: 2, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, revision: 0,
  startingCashPaperMicros: '0', cashPaperMicros: '0', openedAt: null, updatedAt: null, positions: [], recentOrders: [],
  valuation: {status: 'unavailable', portfolioRevision: 0, openPositionCount: 0, pricedPositionCount: 0, cashPaperMicros: '0',
    knownValuePaperMicros: '0', totalPaperMicros: null, positions: []}};
function Desk({snapshot, market, workdays, onWork, motion, onMarket, onCareer, onSignIn, onPosition, money, onSwitchMode, onFastBuy, onHistory, home}: {snapshot: Snapshot; market: ProductMarketClient; workdays: WorkdaysState; onWork: (id: string) => void; motion: boolean; onMarket: () => void; onCareer: () => void; onSignIn?: (() => void) | undefined; onPosition: (assetId: string, mint: string) => void;
  money: MoneyApi; onSwitchMode: () => void; onFastBuy: () => void; onHistory: () => void; home?: HomeParity}) {
  const tr = useT();
  const portfolio = snapshot.portfolio ?? emptyPortfolio;
  const realHoldings = coherentHoldings(money.wallet);
  const holdingPrices = useHoldingPrices(market, money.real ? realHoldings : null);
  const identities = useCompanyIdentities(market, [...portfolio.positions.map(p => p.assetId), ...portfolio.recentOrders.map(o => o.assetId),
    ...(money.real ? realHoldings?.stockTokens.map(token => token.assetId) ?? [] : [])], money.real ? realHoldings : portfolio);
  const [clock, setClock] = useState(Date.now());
  useEffect(() => {const timer = window.setInterval(() => setClock(Date.now()), 5000); return () => clearInterval(timer);}, []);
  const open = portfolio.positions.filter(position => BigInt(position.quantityMicros) > 0n);
  const hasHistory = portfolio.recentOrders.length > 0 || snapshot.career?.careerStarted === true;
  const fresh = portfolio.valuation.status === 'complete' && portfolio.valuation.positions.every(position => position.status === 'priced' && position.expiresAt !== null && Date.parse(position.expiresAt) > clock);
  const total = fresh ? portfolio.valuation.totalPaperMicros : null;
  const career = snapshot.career;
  const firstPosition = open[0];
  const salTitle = career?.careerStarted ? tr('shell.desk.salTrims', {count: fmt.count(career.trims.total)}) : firstPosition ? tr('shell.desk.salPositions', {count: open.length}) : hasHistory ? tr('shell.desk.salRoom') : tr('shell.desk.salFirstCompany');
  // The next rank's name is the API's label.
  const salCopy = career?.careerStarted ? (career.nextRank ? tr('shell.desk.salNextRank', {count: fmt.count(career.nextRank.trimsRemaining), rank: rankName(career.nextRank)}) : tr('shell.desk.salCareer')) : firstPosition ? tr('shell.desk.salPositionsCopy') : hasHistory ? tr('shell.desk.salHistoryCopy') : tr('shell.desk.salFirstCopy');
  const salAction = career?.careerStarted ? onCareer : firstPosition ? () => onPosition(firstPosition.assetId, firstPosition.variantMint) : onMarket;
  const salActionLabel = career?.careerStarted ? tr('shell.desk.seeCareer') : firstPosition ? tr('shell.desk.reviewPosition') : hasHistory ? tr('shell.desk.exploreCompanies') : tr('shell.desk.findFirstCompany');
  return <section className="desk-screen" aria-label={tr('shell.desk.label')}>
    <div className="page-intro"><h1>{tr('shell.desk.title')}</h1>{onSignIn && <button className="secondary save-desk" onClick={onSignIn}>{tr('shell.desk.saveDesk')}</button>}</div>
    <div className="desk-overview">
      {money.real ? <RealBalanceCard onSwitch={onSwitchMode} onFastBuy={onFastBuy} onAddMoney={money.openFundWallet}
        onSend={money.transfers ? money.openSend : undefined} prices={holdingPrices}/> :
      <section className="balance-card" aria-label={tr('shell.desk.balanceLabel')}>
        <div className="balance-heading"><div className="balance-label">{total !== null ? tr('shell.desk.paperBalance') : tr('shell.desk.paperCash')}</div><MoneyModeSwitch real={false} onSwitch={onSwitchMode}/><div className="balance-coins" aria-hidden="true">{open.slice(0,3).map(position => <CompanyLogo key={position.assetId + position.variantMint} name={identities.get(position.assetId)?.name ?? position.symbol} url={identities.get(position.assetId)?.imageUrl ?? null} size={34}/>)}</div></div>
        <div className="balance-amount">{micros(total ?? portfolio.cashPaperMicros)}<small>{tr('common.paperUnit')}</small></div>
        <div className="balance-details"><div><span>{tr('shell.desk.availableToPractice')}</span><strong>{micros(portfolio.cashPaperMicros)}</strong></div><div><span>{tr('shell.desk.openPositions')}</span><strong>{fmt.integer(open.length, 'raw')}</strong></div></div>
        {open.length > 0 && !fresh && <p className="checked">{tr('shell.desk.pricesUpdating')}</p>}
        <div className="balance-actions"><button aria-label={tr('shell.desk.fastBuy')} onClick={onFastBuy}><span aria-hidden="true">+</span>{tr('shell.desk.fastBuy')}</button></div>
      </section>}
      <aside className="desk-mentor" aria-label={tr('shell.desk.salLabel')}>
        <SalArt motion={motion}/>
        <div className="desk-mentor-copy"><span className="desk-mentor-label">{tr('shell.desk.salLabel')}{career && <span>{rankName(career.rank)}</span>}</span><h2>{salTitle}</h2><p>{salCopy}</p><button className="text-button" onClick={salAction}>{salActionLabel}<span aria-hidden="true">↗</span></button></div>
      </aside>
    </div>
    {home && <HomeActions home={home}/>}
    <WorkdayEntry workdays={workdays} onOpen={onWork}/>
    {money.real ? <div className="desk-holdings"><RealHoldings identities={identities} prices={holdingPrices} onOpen={holding => onPosition(holding.assetId, holding.mint)}
      onExplore={onFastBuy} onAddMoney={money.openFundWallet} onHistory={onHistory}/></div> :
    <div className={`desk-holdings${portfolio.recentOrders.length ? ' has-activity' : ''}`}>
      <section className="desk-section desk-positions">
        <div className="section-line"><h2>{tr('shell.desk.positions')}{open.length > 0 && <span className="desk-count">{fmt.integer(open.length, 'raw')}</span>}</h2><button className="text-button" onClick={onMarket}>{tr('shell.desk.exploreMarket')}<span aria-hidden="true">↗</span></button></div>
        {!open.length ? <div className="empty-positions"><img src={art('rookie-briefcase-v1.png')} alt=""/><div><h3>{hasHistory ? tr('shell.desk.emptyHistoryTitle') : tr('shell.desk.emptyFreshTitle')}</h3><p>{hasHistory ? tr('shell.desk.emptyHistoryBody') : tr('shell.desk.emptyFreshBody')}</p></div></div> : open.map(position => {
          const value = portfolio.valuation.positions.find(item => item.assetId === position.assetId && item.variantMint === position.variantMint);
          const priced = value?.status === 'priced' && value.expiresAt !== null && Date.parse(value.expiresAt) > clock;
          return <button className="position-row" key={`${position.assetId}:${position.variantMint}`} onClick={() => onPosition(position.assetId, position.variantMint)}><CompanyLogo name={identities.get(position.assetId)?.name ?? position.symbol} url={identities.get(position.assetId)?.imageUrl ?? null}/><span className="position-main"><strong>{identities.get(position.assetId)?.name ?? position.symbol}</strong><small>{tr('shell.desk.positionShares', {symbol: position.symbol, shares: shareCount(position.quantityMicros)})}</small></span><span className="position-value">{priced && value.marketValuePaperMicros ? tr('common.paperAmount', {amount: micros(value.marketValuePaperMicros)}) : tr('shell.desk.valueUnavailable')}<small>{tr('shell.desk.positionCost', {amount: micros(position.costBasisPaperMicros)})}</small></span><span className="position-open" aria-hidden="true">↗</span></button>;
        })}
      </section>
      {portfolio.recentOrders.length > 0 && <section className="desk-section desk-activity"><div className="section-line"><h2>{tr('shell.desk.recentMoves')}</h2></div>{portfolio.recentOrders.slice(0, 5).map(order => <div className="activity-row" key={order.id}><CompanyLogo name={identities.get(order.assetId)?.name ?? order.symbol} url={identities.get(order.assetId)?.imageUrl ?? null} size={34}/><div className="activity-copy"><strong>{tr('shell.desk.moveTitle', {action: order.action, name: identities.get(order.assetId)?.name ?? order.symbol})}</strong><span>{tr('shell.desk.moveDetail', {shares: shareCount(order.quantityMicros), date: dateLabel(order.committedAt)})}</span></div><div className="activity-value">{micros(order.action === 'buy' ? order.cashDebitPaperMicros : order.cashCreditPaperMicros)}<small>{tr('common.paperUnit')}</small></div></div>)}</section>}
    </div>}
    {home && <div className="home-invitations"><HomeInvitations home={home}/></div>}
  </section>;
}

function GuestInvitation({title, onStart, motion}: {title: string; onStart: () => void; motion: boolean}) {
  const tr = useT();
  return <div className="empty-page"><SalArt motion={motion}/><h1>{title}</h1><p>{tr('shell.guest.body')}</p><button className="primary" onClick={onStart}>{tr('shell.guest.start')}</button></div>;
}

/** A share count for a message: shown in the reader's style, with the number kept for plural forms. */
function shareCount(quantityMicros: string): fmt.Shown {
  return new fmt.Shown(Number(sharesPlain(quantityMicros).replaceAll(',', '').replace('−', '-')), shares(quantityMicros));
}
/** The chosen trader for Settings: "The Wolf" in English; the names themselves are never translated. */
function personaName(tr: Translator, persona: string): string {
  return tr('shell.settings.persona', {persona, name: `${persona[0]!.toUpperCase()}${persona.slice(1)}`});
}
