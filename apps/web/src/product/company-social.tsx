import {useCallback, useEffect, useRef, useState} from 'react';
import {PracticeError} from './practice-client';
import {read} from './product-api';
import type {ProductApiClient, ProductIdentity} from './product-api';
import {careerApi, newMutationId} from './career-actions';
import type {ReasonPrivacy, SharedReason} from './career-actions';
import {FollowButton} from './market-social';
import type {FollowingState} from './market-social';
import type {StockCard} from './market-client';
import {Loading} from './ui';

/* Mobile's company page Holders and Comments sections (public_holders.dart, stock_reasons_tab.dart). */

export interface CompanySocial {
  readonly api: ProductApiClient; readonly identity: ProductIdentity | null; readonly accountSignedIn: boolean;
  readonly following: FollowingState; readonly privacy: ReasonPrivacy | null;
  readonly onOpenSettings: () => void; readonly onSignIn: () => void;
}
export interface PublicHolder {readonly owner: string; readonly primaryDomain: string | null; readonly amount: string; readonly tokenAccounts: number}
export interface PublicHoldersPage {readonly mint: string; readonly observedAt: string; readonly sampledAccounts: number; readonly holders: readonly PublicHolder[]}
const BASE58 = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/u;
export function parseHolders(value: unknown, mint: string): PublicHoldersPage {
  const v = read.record(value, ['schemaVersion', 'mint', 'network', 'scope', 'complete', 'observedAt', 'slot', 'sampledAccounts', 'holders']);
  if (v['schemaVersion'] !== 1 || v['mint'] !== mint || v['network'] !== 'solana-mainnet' || v['scope'] !== 'largest-20-token-accounts' || v['complete'] !== false) read.invalid();
  if (typeof v['slot'] !== 'string' || !/^\d{1,20}$/u.test(v['slot'])) read.invalid();
  const holders = read.array(v['holders'], 20).map(item => {
    const h = read.record(item, ['owner', 'primaryDomain', 'amount', 'tokenAccounts']);
    const owner = read.string(h['owner'], 44); if (!BASE58.test(owner)) read.invalid();
    const domain = read.nullable(h['primaryDomain'], d => {const text = read.string(d, 68); if (!/^[\p{L}\p{N}_-]{1,64}\.sol$/u.test(text)) read.invalid(); return text;});
    const amount = read.string(h['amount'], 60); if (!/^(?:0|[1-9]\d*)(?:\.\d+)?$/u.test(amount)) read.invalid();
    return Object.freeze({owner, primaryDomain: domain, amount, tokenAccounts: read.integer(h['tokenAccounts'], 1, 20)});
  });
  return Object.freeze({mint, observedAt: read.instant(v['observedAt']), sampledAccounts: read.integer(v['sampledAccounts'], 0, 20), holders});
}
const shortAddress = (owner: string) => `${owner.slice(0, 4)}…${owner.slice(-4)}`;
function quantity(amount: string): string {
  const [whole = '0', fraction = ''] = amount.split('.');
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/gu, ',');
  return fraction ? `${grouped}.${fraction.slice(0, 4).replace(/0+$/u, '')}`.replace(/\.$/u, '') : grouped;
}
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export function reasonSavedAt(value: string): string {
  const date = new Date(value);
  return `${date.getDate()} ${months[date.getMonth()]} ${date.getFullYear()}, ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

export function CompanyFollow({card, social}: {card: StockCard; social: CompanySocial}) {
  const [notice, setNotice] = useState<{message: string; signIn: boolean} | null>(null);
  return <div className="company-follow"><FollowButton card={card} following={social.following} onNotice={(message, signIn) => setNotice({message, signIn})}/>
    {notice && <span className="company-follow-notice" role="status">{notice.message}{notice.signIn && <button className="text-button" onClick={social.onSignIn}>Sign in</button>}</span>}</div>;
}

export function CompanySections({assetId, mint, social}: {assetId: string; mint: string; social: CompanySocial}) {
  const [section, setSection] = useState<'comments' | 'holders'>('comments');
  return <section className="company-social" aria-label="Community">
    <div className="market-lists company-tabs" role="tablist" aria-label="Company sections">
      {(['comments', 'holders'] as const).map(item => <button key={item} role="tab" aria-selected={section === item} className={section === item ? 'active' : ''} onClick={() => setSection(item)}>{item === 'comments' ? 'Comments' : 'Holders'}</button>)}
    </div>
    {section === 'holders' ? <HoldersPanel key={mint} api={social.api} mint={mint}/> : <CommentsPanel key={`${assetId}:${mint}`} assetId={assetId} mint={mint} social={social}/>}
  </section>;
}

function HoldersPanel({api, mint}: {api: ProductApiClient; mint: string}) {
  const [page, setPage] = useState<PublicHoldersPage | null>(null), [failed, setFailed] = useState(false), [copied, setCopied] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const controller = new AbortController(); setFailed(false);
    void api.request({path: '/v1/markets/stocks/holders', query: {mint}, signal: controller.signal, parse: value => parseHolders(value, mint)})
      .then(value => {if (!controller.signal.aborted) setPage(value);}, () => {if (!controller.signal.aborted) setFailed(true);});
    return () => controller.abort();
  }, [api, mint, revision]);
  if (failed && !page) return <div className="company-social-state" role="alert"><strong>Holders couldn’t load</strong><p>Try again in a moment.</p><button className="text-button" onClick={() => setRevision(n => n + 1)}>Retry</button></div>;
  if (!page) return <Loading>Loading holders…</Loading>;
  if (!page.holders.length) return <div className="company-social-state"><strong>No holders to show</strong></div>;
  async function copy(owner: string) {
    try {await navigator.clipboard.writeText(owner); setCopied(owner);} catch {setCopied(null);}
  }
  return <div className="holders">
    <div className="holders-head" aria-hidden="true"><span>Holder</span><span>Tokens</span></div>
    <ol className="holders-list">{page.holders.map(holder => <li key={holder.owner}><button className="holder-row" onClick={() => void copy(holder.owner)} aria-label={`Copy address ${holder.owner}`}>
      <span className="holder-name"><strong>{holder.primaryDomain ?? shortAddress(holder.owner)}</strong>{holder.primaryDomain && <small>{shortAddress(holder.owner)}</small>}</span>
      <span className="holder-amount" title={holder.amount}>{quantity(holder.amount)}</span></button></li>)}</ol>
    {copied && <p className="company-social-note" role="status">Address copied</p>}
    <p className="company-social-note">Balances from the largest {page.sampledAccounts} token accounts. Not the full holder list. Owners may be pools or custodians, not people.</p>
  </div>;
}

const reportCategories = [['spam', 'Spam'], ['harassment', 'Harassment'], ['impersonation', 'Impersonation'], ['unsafe', 'Unsafe content'], ['other', 'Something else']] as const;
function commentsFailure(error: unknown): string {
  if (error instanceof PracticeError) {
    if (error.status === 401) return 'Your session needs a refresh before comments can load.';
    if (error.code === 'PRACTICE_NETWORK_ERROR') return 'You are offline. Comments couldn’t load.';
    if (error.code === 'PRACTICE_TIMEOUT') return 'Comments took too long to load.';
    if (error.status === 429) return 'Comments are refreshing too quickly. Try again shortly.';
  }
  return 'Comments couldn’t load.';
}
function CommentsPanel({assetId, mint, social}: {assetId: string; mint: string; social: CompanySocial}) {
  const {api, identity, privacy} = social;
  const [audience, setAudience] = useState<'everyone' | 'friends'>('everyone');
  const [items, setItems] = useState<readonly SharedReason[] | null>(null), [cursor, setCursor] = useState<string | null>(null);
  const [error, setError] = useState<unknown>(null), [loadingMore, setLoadingMore] = useState(false), [ownCurrent, setOwnCurrent] = useState(false);
  const [reporting, setReporting] = useState<SharedReason | null>(null), [reported, setReported] = useState<ReadonlySet<string>>(new Set()), [notice, setNotice] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);
  const identityRef = useRef(identity); identityRef.current = identity;
  const hasIdentity = identity !== null;
  const friendsAvailable = privacy?.friendsSharing === 'available';
  useEffect(() => {
    const current = identityRef.current;
    if (!current) return;
    const controller = new AbortController(); setItems(null); setError(null); setCursor(null);
    void careerApi.listReasons(api, current, {scope: audience, assetId, variantMint: mint, limit: 20}, controller.signal)
      .then(page => {if (!controller.signal.aborted) {setItems(page.reasons); setCursor(page.nextCursor);}}, reason => {if (!controller.signal.aborted) setError(reason);});
    // The viewer's own comment may be private; mobile explains that beside the list.
    void careerApi.listReasons(api, current, {scope: 'self', assetId, variantMint: mint, limit: 20}, controller.signal)
      .then(page => {if (!controller.signal.aborted) setOwnCurrent(page.reasons.some(reason => reason.deskCycle === 'current'));}, () => undefined);
    return () => controller.abort();
  }, [api, hasIdentity, assetId, mint, audience, revision]);
  const more = useCallback(async () => {
    const current = identityRef.current;
    if (!current || !cursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await careerApi.listReasons(api, current, {scope: audience, assetId, variantMint: mint, limit: 20, cursor});
      setItems(prior => {const known = new Set((prior ?? []).map(item => item.reasonId)); return [...(prior ?? []), ...page.reasons.filter(item => !known.has(item.reasonId))];});
      setCursor(page.nextCursor);
    } catch (reason) {setError(reason);} finally {setLoadingMore(false);}
  }, [api, cursor, loadingMore, audience, assetId, mint]);
  if (!identity) return <div className="company-social-state"><strong>No comments yet</strong><p>Start practicing or sign in to see what other traders think.</p></div>;
  const visible = (items ?? []).filter(item => !reported.has(item.reasonId));
  const sharedHere = audience === 'everyone' ? privacy?.visibility === 'everyone' : friendsAvailable && privacy?.visibility === 'friends';
  async function report(reason: SharedReason, category: string) {
    const current = identityRef.current;
    if (!current || !('subject' in current)) return;
    try {
      await api.request({path: '/v1/social/reason-reports', method: 'POST', identity: current, expectedStatus: [200, 202],
        body: {schemaVersion: 1, mutationId: newMutationId(), reasonId: reason.reasonId, category},
        parse: value => {const v = read.record(value, ['schemaVersion', 'report']); if (v['schemaVersion'] !== 1) read.invalid(); return true;}});
      setReported(prior => new Set([...prior, reason.reasonId])); setReporting(null); setNotice('Report received.');
    } catch {setNotice('That action could not be completed. Try again.');}
  }
  return <div className="comments">
    {friendsAvailable && <div className="market-lists" role="tablist" aria-label="Choose whose comments to see">{(['everyone', 'friends'] as const).map(item =>
      <button key={item} role="tab" aria-selected={audience === item} className={audience === item ? 'active' : ''} onClick={() => setAudience(item)}>{item === 'everyone' ? 'Everyone' : 'Friends'}</button>)}</div>}
    {ownCurrent && privacy && !sharedHere && <div className="comment-private" role="note"><strong>Your comment is private.</strong><button className="text-button" onClick={social.onOpenSettings}>Settings</button></div>}
    {notice && <p className="company-social-note" role="status">{notice}</p>}
    {items === null && error === null && <Loading>Loading comments…</Loading>}
    {items === null && error !== null && <div className="company-social-state" role="alert"><p>{commentsFailure(error)}</p><button className="text-button" onClick={() => setRevision(n => n + 1)}>Try again</button></div>}
    {items !== null && !visible.length && <div className="company-social-state"><strong>{audience === 'friends' ? 'No comments from friends yet' : 'No comments yet'}</strong></div>}
    {visible.map(reason => <article key={reason.reasonId} className="comment-card">
      <header><strong>@{reason.author.handle}</strong><span>{reason.author.rank.label}</span>{reason.author.isViewer && <span className="comment-you">You</span>}</header>
      <p>{reason.note}</p>
      <footer><span>Saved {reasonSavedAt(reason.savedAt)}</span>{social.accountSignedIn && !reason.author.isViewer && <button className="text-button" onClick={() => setReporting(reason)}>Report</button>}</footer>
    </article>)}
    {items !== null && error !== null && <div className="company-social-state" role="alert"><p>{commentsFailure(error)}</p><button className="text-button" onClick={() => void more()}>Try again</button></div>}
    {items !== null && error === null && cursor && <button className="secondary" disabled={loadingMore} onClick={() => void more()}>{loadingMore ? 'Loading…' : 'Show more'}</button>}
    {reporting && <ReportDialog reason={reporting} onCancel={() => setReporting(null)} onReport={category => report(reporting, category)}/>}
  </div>;
}
function ReportDialog({reason, onCancel, onReport}: {reason: SharedReason; onCancel: () => void; onReport: (category: string) => Promise<void>}) {
  const [category, setCategory] = useState<string | null>(null), [busy, setBusy] = useState(false);
  const label = reportCategories.find(([id]) => id === category)?.[1];
  return <div className="settings-modal-backdrop" onClick={event => {if (event.target === event.currentTarget && !busy) onCancel();}}>
    <div className="settings-modal" role="dialog" aria-modal="true" aria-labelledby="report-title">
      <h2 id="report-title">Why are you reporting this?</h2>
      <p>Choose the closest reason. The author will not see who reported it.</p>
      <div className="setup-choices" role="radiogroup" aria-label="Report reason">{reportCategories.map(([id, text]) => <button key={id} className="setup-choice" role="radio" aria-checked={category === id} onClick={() => setCategory(id)}><span><strong>{text}</strong></span></button>)}</div>
      {label && <p>Trimmy will review @{reason.author.handle}’s comment as {label.toLowerCase()}. It will leave this page after the report is received.</p>}
      <div className="settings-modal-actions"><button className="text-button" disabled={busy} onClick={onCancel}>Cancel</button>
        <button className="primary danger" disabled={!category || busy} onClick={async () => {if (!category) return; setBusy(true); try {await onReport(category);} finally {setBusy(false);}}}>Report</button></div>
    </div>
  </div>;
}
