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
import {DailyStoryScreen} from './progress-screens';
import {ProductAuthProvider, useProductAuth, type ProductAuthConfig, type ProductAccountAccess, type ConnectProductAccount} from './product-auth';
import type {ProductAuthSdkPort} from './product-auth-sdk-loader';
import {createProductAccountConnector} from './product-account';
import {SignInScreen} from './sign-in-screen';
import {CompanyLogo, Failure, Loading, SalArt, art, dateLabel, errorCopy, micros, shares} from './ui';

type Page = 'desk' | 'market' | 'career' | 'profile' | 'start' | 'welcome' | 'sign-in' | 'daily' | 'work';
type Route = {page: Page; assetId?: string; mint?: string; assignmentId?: string};
const pages: readonly {page: Page; title: string; icon: string}[] = [
  {page: 'desk', title: 'Desk', icon: 'nav-plumpy-desk.png'},
  {page: 'market', title: 'Market', icon: 'nav-plumpy-market-shop.png'},
  {page: 'career', title: 'Career', icon: 'nav-plumpy-career.png'},
  {page: 'profile', title: 'Profile', icon: 'nav-plumpy-profile.png'},
];
function readRoute(): Route {
  const [path = '', search = ''] = window.location.hash.replace(/^#\/?/, '').split('?');
  const [page, assetId] = path.split('/');
  if (page === 'work') return {page, ...(assetId && /^[a-z][a-z0-9-]{0,79}$/.test(assetId) ? {assignmentId: assetId} : {})};
  if (page === 'market' && assetId && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(assetId)) {
    const mint = new URLSearchParams(search).get('mint');
    return {page, assetId, ...(mint && /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(mint) ? {mint} : {})};
  }
  return {page: page === 'start' || page === 'welcome' || page === 'sign-in' || page === 'daily' || pages.some(item => item.page === page) ? page as Page : 'desk'};
}
function browserStorage(): PracticeStorage {
  try {return window.localStorage;} catch {return {getItem() {throw new Error('Storage unavailable');}, setItem() {throw new Error('Storage unavailable');}};}
}
type Snapshot = {portfolio: PaperPortfolio | null; profile: ProductProfile | null; career: CareerSummary | null; missions: CareerMissionBoard | null; checkedAt: number | null};
const emptySnapshot: Snapshot = {portfolio: null, profile: null, career: null, missions: null, checkedAt: null};

export interface ProductAppProps {
  readonly apiBase?: string | null;
  readonly practiceClient?: PracticeClient;
  readonly marketClient?: ProductMarketClient;
  readonly storage?: PracticeStorage;
  readonly authConfig?: ProductAuthConfig;
  readonly authSdk?: ProductAuthSdkPort;
  readonly connectAccount?: ConnectProductAccount;
  readonly accountAccess?: ProductAccountAccess;
}
export function ProductApp(props: ProductAppProps) {
  const apiBase = props.apiBase === undefined ? productApiBase() : props.apiBase;
  const storage = useMemo(() => props.storage ?? browserStorage(), [props.storage]);
  const client = useMemo(() => props.practiceClient ?? (apiBase ? new PracticeClient({baseUrl: apiBase}) : null), [apiBase, props.practiceClient]);
  const connect = useMemo(() => props.connectAccount ?? (client ? createProductAccountConnector({client, storage}) : async () => {throw new Error('Sign-in unavailable');}), [client, storage, props.connectAccount]);
  return <ProductAuthProvider apiBase={apiBase} connectAccount={connect} {...(props.authConfig ? {config: props.authConfig} : {})} {...(props.authSdk ? {sdk: props.authSdk} : {})}>
    <IdentityWorkspace {...props} apiBase={apiBase} storage={storage} {...(client ? {practiceClient: client} : {})}/>
  </ProductAuthProvider>;
}
function IdentityWorkspace(props: ProductAppProps) {
  const auth = useProductAuth();
  const binding = useRef<{access: ProductAccountAccess | null; epoch: number}>({access: null, epoch: 0});
  if (binding.current.access !== auth.accountAccess) binding.current = {access: auth.accountAccess, epoch: binding.current.epoch + 1};
  if (auth.phase === 'restoring') return <div className="auth-restore"><img src={art('trimmy-mark.png')} alt="Trimmy"/><Loading>Opening Trimmy…</Loading></div>;
  return <ProductWorkspace key={`${props.apiBase ?? 'unconfigured'}:${binding.current.epoch}`} {...props} {...(auth.accountAccess ? {accountAccess: auth.accountAccess} : {})}/>;
}
function ProductWorkspace({apiBase = productApiBase(), practiceClient, marketClient, storage, accountAccess}: ProductAppProps) {
  const auth = useProductAuth();
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
    introSettled.current = session?.isAccount === true || profile?.launchCheckpoint === 'app' || profile?.hasConfirmedPaperTrade === true || session?.lastReceipt?.action === 'buy';
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
    if (step !== 'welcome' && routeRef.current.page !== 'start') {routeRef.current = {page: 'start'}; setRoute({page: 'start'});}
  }, []);
  async function exitIntroduction(completed: boolean) {
    if (!session) throw new Error('Practice unavailable');
    await restoreGuest();
    if (!workspaceActive.current) return;
    // Replaying a saved exit can already return app. Never send a second transition.
    const profile = await session.ensureProfile();
    if (!workspaceActive.current) return;
    if (profile.launchCheckpoint !== 'app') await session.advanceLaunch(completed ? 'introduction-completed' : 'introduction-skipped');
    if (!workspaceActive.current) return;
    introSettled.current = true;
    await refresh();
    if (workspaceActive.current) navigate({page: 'desk'}, true);
  }
  async function introCommitted(_receipt: PaperReceipt) {
    if (!workspaceActive.current) return;
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
    // A launch failure cannot turn a durable receipt into a failed order.
    try {if (session && snapshot.profile?.launchCheckpoint !== 'app') {
      const profile = snapshot.profile ?? await session.readProfile();
      if (workspaceActive.current && profile?.launchCheckpoint !== 'app') await session.advanceLaunch('introduction-completed');
    }} catch { /* Resume later; ledger remains authoritative. */ }
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
  const firstDay = !signIn && (route.page === 'start' || route.page === 'welcome' || (route.page === 'desk' && !hasGuest && !busy));

  return <div className={`product-shell${firstDay || signIn ? ' onboarding-shell' : ''}${route.page === 'market' && !route.assetId ? ' market-shell' : ''}${route.page === 'career' || route.page === 'daily' && !progress.pending ? ' career-shell' : ''}`} data-revision={revision}>
    <a className="skip" href="#main-content" onClick={event => {event.preventDefault(); heading.current?.focus();}}>Skip to content</a>
    <aside className="product-nav"><button className="product-brand" aria-label="Trimmy desk" onClick={() => navigate({page: 'desk'})}><img src={art('trimmy-mark.png')} alt=""/>trimmy</button>
      <nav aria-label="Main navigation">{pages.map(item => <button key={item.page} aria-current={route.page === item.page || (route.page === 'daily' || route.page === 'work') && item.page === 'career' ? 'page' : undefined} onClick={() => navigate({page: item.page})}><img src={art(`icons/${item.icon}`)} alt=""/><span>{item.title}</span></button>)}</nav>
      {snapshot.profile?.onboarding.persona && <button className="nav-identity" onClick={() => navigate({page:'profile'})}><img src={art(`persona-${snapshot.profile.onboarding.persona}-avatar-v1.png`)} alt=""/><span><strong>{snapshot.profile.onboarding.handle ? `@${snapshot.profile.onboarding.handle}` : `The ${snapshot.profile.onboarding.persona[0]!.toUpperCase()}${snapshot.profile.onboarding.persona.slice(1)}`}</strong>{snapshot.career && <small>{snapshot.career.rank.label}</small>}</span></button>}
    </aside>
    <div className="product-body">{(firstDay || signIn) && <header className="onboard-header"><span className="product-brand"><img src={art('trimmy-mark.png')} alt=""/>trimmy</span>{firstDay && <button className="text-button" onClick={() => navigate({page: 'sign-in'})}>Sign in</button>}</header>}
      <main id="main-content" ref={heading} tabIndex={-1} className="product-main">
      {!apiBase ? <div className="empty-page"><SalArt motion={motion}/><h1>Your desk is almost ready.</h1><p>Practice is unavailable here right now. Please try again later.</p></div>
      : storageChanged ? <div className="empty-page"><h1>Your desk changed in another tab.</h1><p>Reload to restore the latest desk before making another move.</p><button className="primary" onClick={() => window.location.reload()}>Reload your desk</button></div>
      : <>
        {error !== null && <Failure title="Your desk needs a moment." message={errorCopy(error)} onRetry={() => void retryDesk()}/>}
        {session?.pendingCommit && <div className="pending-order" role="status"><strong>Let’s check your last order.</strong><p>The connection ended before its receipt arrived. Checking uses the same order so it won’t be placed twice.</p><button className="text-button" disabled={busy} onClick={() => void recover()}>{busy ? 'Checking…' : 'Check order'}</button></div>}
        {recovered && <div className="notice" role="status">Your order is confirmed. The same receipt and updated desk are restored.</div>}
        {workdays.pending && !['career', 'work', 'daily'].includes(route.page) && <div className="work-recovery" role="status"><span>Your assignment has an unconfirmed save.</span><button className="text-button" disabled={workdays.working} onClick={() => void workdays.recover()}>{workdays.working ? 'Checking…' : 'Check saved work'}</button></div>}
        {signIn ? <SignInScreen motion={motion} hasDesk={hasGuest} onBack={() => navigate({page: hasGuest ? 'desk' : 'welcome'}, true)} onAccount={() => navigate({page: 'desk'}, true)}/> : firstDay && session && market ? (restoring ? <Loading/> : <FirstDay initialStep={introInitial} motion={motion} market={market} session={session} portfolio={snapshot.portfolio} career={snapshot.career} ensureDesk={ensureDesk} onExplore={() => navigate({page: 'market'})} onExit={exitIntroduction} onCommitted={introCommitted} onPending={() => setRevision(value => value + 1)} onStep={firstDayStep} onSignIn={() => navigate({page: 'sign-in'})}/>) : <>
        {route.page === 'market' && market && (route.assetId && session ? <StockScreen key={`${route.assetId}:${route.mint ?? ''}`} assetId={route.assetId} {...(selectedCard ? {card: selectedCard} : {})} {...(route.mint ? {selectedMint: route.mint} : {})} market={market} session={session} portfolio={snapshot.portfolio} ensureDesk={ensureDesk} onBack={() => navigate({page: 'market'})} onDesk={() => navigate({page: 'desk'})} onCommitted={committed} onPending={() => setRevision(value => value + 1)}/> : <MarketScreen client={market} onSelect={select}/>)}
        {route.page === 'desk' && market && (busy && !snapshot.portfolio ? <Loading/> : snapshot.portfolio ? <Desk snapshot={snapshot} market={market} workdays={workdays} onWork={openWork} motion={motion} onMarket={() => navigate({page: 'market'})} onCareer={() => navigate({page: 'career'})} onSignIn={auth.authenticated ? undefined : () => navigate({page: 'sign-in'})} onPosition={(assetId, mint) => navigate({page: 'market', assetId, mint})}/> : null)}
        {(route.page === 'career' || route.page === 'daily' && !progress.pending) && (!hasGuest ? <GuestInvitation title="Your career starts here." onStart={start} motion={motion}/> : <CareerJourneyScreen workdays={workdays} career={snapshot.career} missions={snapshot.missions} week={progress.week} progressError={careerError !== null} onRetry={() => {void refresh(); void progress.refresh();}} onMarket={() => navigate({page: 'market'})} onOpen={openWork} motion={motion} sound={workSound.enabled} onSound={workSound.toggle}/>)}
        {progress.pending && route.page !== 'daily' && <div className="work-recovery" role="status"><span>Your earlier desk story needs confirmation.</span><button className="text-button" onClick={() => navigate({page:'daily'})}>Check clock-out</button></div>}
        {route.page === 'daily' && progress.pending && <DailyStoryScreen progress={progress} onBack={() => navigate({page:'career'})}/>}
        {route.page === 'work' && (!hasGuest ? <GuestInvitation title="Your first assignment awaits." onStart={start} motion={motion}/> : assignment ? canOpenWork(assignment, workdays.journey!.assignments) ? <WorkdayScreen key={assignment.id} assignment={assignment} working={workdays.working} error={workdays.error} pending={Boolean(workdays.pending)} onSubmit={workdays.saveStep} onSaveDraft={workdays.saveDraft} onRecover={workdays.recover} onBack={() => commitNavigation({page:'career'})} registerLeaveGuard={registerLeaveGuard} onCue={workSound.play}/> : <div className="empty-page"><h1>{assignment.title}</h1><p>File day {assignment.ordinal - 1} to open this assignment.</p><button className="primary" onClick={() => navigate({page:'career'})}>Back to Career</button></div> : workdays.loading ? <Loading>Opening your assignment…</Loading> : <div className="empty-page"><h1>Your assignment couldn’t open.</h1><button className="text-button" onClick={() => void workdays.refresh()}>Try again</button><button className="primary" onClick={() => navigate({page:'career'})}>Back to Career</button></div>)}
        {route.page === 'profile' && <WebProfile profile={snapshot.profile} career={snapshot.career} missions={snapshot.missions} hasIdentity={hasGuest} signedIn={auth.authenticated} authBusy={auth.busy} busy={busy} progressError={careerError !== null} motion={motion} onMotion={motionSetting} onStart={start} onCareer={() => navigate({page: 'career'})} onSignIn={() => navigate({page: 'sign-in'})} onSignOut={() => {navigate({page: 'sign-in'}, true); void auth.logout();}} onRetry={() => void refresh()} {...(hasGuest ? {onPersona: changePersona} : {})}/>}
        </>}
      </>}
      </main>
    </div>
  </div>;
}

function Desk({snapshot, market, workdays, onWork, motion, onMarket, onCareer, onSignIn, onPosition}: {snapshot: Snapshot; market: ProductMarketClient; workdays: WorkdaysState; onWork: (id: string) => void; motion: boolean; onMarket: () => void; onCareer: () => void; onSignIn?: (() => void) | undefined; onPosition: (assetId: string, mint: string) => void}) {
  const portfolio = snapshot.portfolio!;
  const identities = useCompanyIdentities(market, [...portfolio.positions.map(p => p.assetId), ...portfolio.recentOrders.map(o => o.assetId)], portfolio);
  const [clock, setClock] = useState(Date.now());
  useEffect(() => {const timer = window.setInterval(() => setClock(Date.now()), 5000); return () => clearInterval(timer);}, []);
  const open = portfolio.positions.filter(position => BigInt(position.quantityMicros) > 0n);
  const hasHistory = portfolio.recentOrders.length > 0 || snapshot.career?.careerStarted === true;
  const fresh = portfolio.valuation.status === 'complete' && portfolio.valuation.positions.every(position => position.status === 'priced' && position.expiresAt !== null && Date.parse(position.expiresAt) > clock);
  const total = fresh ? portfolio.valuation.totalPaperMicros : null;
  const career = snapshot.career;
  const firstPosition = open[0];
  const salTitle = career?.careerStarted ? `${career.trims.total.toLocaleString()} Trims earned.` : firstPosition ? `${open.length} ${open.length === 1 ? 'position' : 'positions'} on your desk.` : hasHistory ? 'Room for your next move.' : 'Your first company awaits.';
  const salCopy = career?.careerStarted ? (career.nextRank ? `${career.nextRank.trimsRemaining.toLocaleString()} more toward ${career.nextRank.label}. See your next career step.` : 'Your career, from your first move to today.') : firstPosition ? 'Take a closer look at what you own.' : hasHistory ? 'Your earlier moves are saved below. There’s more to explore.' : 'Pick a name you know. Get curious.';
  const salAction = career?.careerStarted ? onCareer : firstPosition ? () => onPosition(firstPosition.assetId, firstPosition.variantMint) : onMarket;
  const salActionLabel = career?.careerStarted ? 'See your career' : firstPosition ? 'Review a position' : hasHistory ? 'Explore companies' : 'Find your first company';
  return <section className="desk-screen" aria-label="Your desk">
    <div className="page-intro"><h1>Your desk.</h1>{onSignIn && <button className="secondary save-desk" onClick={onSignIn}>Save your desk</button>}</div>
    <div className="desk-overview">
      <section className="balance-card" aria-label="Paper balance">
        <div className="balance-heading"><div className="balance-label">{total !== null ? 'Your paper balance' : 'Your paper cash'}</div><div className="balance-coins" aria-hidden="true">{open.slice(0,3).map(position => <CompanyLogo key={position.assetId + position.variantMint} name={identities.get(position.assetId)?.name ?? position.symbol} url={identities.get(position.assetId)?.imageUrl ?? null} size={34}/>)}</div></div>
        <div className="balance-amount">{micros(total ?? portfolio.cashPaperMicros)}<small>paper</small></div>
        <div className="balance-details"><div><span>Available to practice</span><strong>{micros(portfolio.cashPaperMicros)}</strong></div><div><span>Open positions</span><strong>{open.length}</strong></div></div>
        {open.length > 0 && !fresh && <p className="checked">Holding prices are updating.</p>}
      </section>
      <aside className="desk-mentor" aria-label="A note from Sal">
        <SalArt motion={motion}/>
        <div className="desk-mentor-copy"><span className="desk-mentor-label">A note from Sal{career && <span>{career.rank.label}</span>}</span><h2>{salTitle}</h2><p>{salCopy}</p><button className="text-button" onClick={salAction}>{salActionLabel}<span aria-hidden="true">↗</span></button></div>
      </aside>
    </div>
    <WorkdayEntry workdays={workdays} onOpen={onWork}/>
    <div className={`desk-holdings${portfolio.recentOrders.length ? ' has-activity' : ''}`}>
      <section className="desk-section desk-positions">
        <div className="section-line"><h2>Your positions{open.length > 0 && <span className="desk-count">{open.length}</span>}</h2><button className="text-button" onClick={onMarket}>Explore Market<span aria-hidden="true">↗</span></button></div>
        {!open.length ? <div className="empty-positions"><img src={art('rookie-briefcase-v1.png')} alt=""/><div><h3>{hasHistory ? 'A little room to explore.' : 'A fresh start.'}</h3><p>{hasHistory ? 'No open positions. Find a company that catches your eye.' : 'Your companies will live here after your first move.'}</p></div></div> : open.map(position => {
          const value = portfolio.valuation.positions.find(item => item.assetId === position.assetId && item.variantMint === position.variantMint);
          const priced = value?.status === 'priced' && value.expiresAt !== null && Date.parse(value.expiresAt) > clock;
          return <button className="position-row" key={`${position.assetId}:${position.variantMint}`} onClick={() => onPosition(position.assetId, position.variantMint)}><CompanyLogo name={identities.get(position.assetId)?.name ?? position.symbol} url={identities.get(position.assetId)?.imageUrl ?? null}/><span className="position-main"><strong>{identities.get(position.assetId)?.name ?? position.symbol}</strong><small>{position.symbol} · {shares(position.quantityMicros)} shares</small></span><span className="position-value">{priced && value.marketValuePaperMicros ? `${micros(value.marketValuePaperMicros)} paper` : 'Value unavailable'}<small>Cost {micros(position.costBasisPaperMicros)} paper</small></span><span className="position-open" aria-hidden="true">↗</span></button>;
        })}
      </section>
      {portfolio.recentOrders.length > 0 && <section className="desk-section desk-activity"><div className="section-line"><h2>Recent moves</h2></div>{portfolio.recentOrders.slice(0, 5).map(order => <div className="activity-row" key={order.id}><CompanyLogo name={identities.get(order.assetId)?.name ?? order.symbol} url={identities.get(order.assetId)?.imageUrl ?? null} size={34}/><div className="activity-copy"><strong>{order.action === 'buy' ? 'Bought' : 'Sold'} {identities.get(order.assetId)?.name ?? order.symbol}</strong><span>{shares(order.quantityMicros)} shares · {dateLabel(order.committedAt)}</span></div><div className="activity-value">{micros(order.action === 'buy' ? order.cashDebitPaperMicros : order.cashCreditPaperMicros)}<small>paper</small></div></div>)}</section>}
    </div>
  </section>;
}

function GuestInvitation({title, onStart, motion}: {title: string; onStart: () => void; motion: boolean}) {return <div className="empty-page"><SalArt motion={motion}/><h1>{title}</h1><p>Start a free practice desk to build your experience.</p><button className="primary" onClick={onStart}>Start practicing</button></div>;}
