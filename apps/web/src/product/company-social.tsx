import {useCallback, useEffect, useRef, useState} from 'react';
import {PracticeError} from './practice-client';
import {read} from './product-api';
import type {ProductApiClient, ProductIdentity} from './product-api';
import {careerApi, newMutationId} from './career-actions';
import type {ReasonPrivacy, SharedReason} from './career-actions';
import {FollowButton, followNoticeText} from './market-social';
import type {FollowNotice, FollowingState} from './market-social';
import type {StockCard} from './market-client';
import {Loading} from './ui';
import {useT, type Translator} from '../i18n/react';
import type {MessageKey} from '../i18n/runtime';
import * as fmt from '../i18n/format';
import {rankName} from './career-milestones';
import {useModalFocus} from './use-modal-focus';

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
/** A token balance grouped the English way, then written in the page's language. */
function quantity(amount: string): string {
  const [whole = '0', fraction = ''] = amount.split('.');
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/gu, ',');
  return fmt.number(fraction ? `${grouped}.${fraction.slice(0, 4).replace(/0+$/u, '')}`.replace(/\.$/u, '') : grouped);
}
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** When a comment was saved: "27 Sep 2026, 09:00" in English, the reader's own date and time style elsewhere. */
export function reasonSavedAt(value: string): string {
  const date = new Date(value);
  if (!fmt.isEnglish()) return fmt.dateTime(date, undefined, {day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit'});
  return `${date.getDate()} ${months[date.getMonth()]} ${date.getFullYear()}, ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

export function CompanyFollow({card, social}: {card: StockCard; social: CompanySocial}) {
  const tr = useT();
  const [notice, setNotice] = useState<{notice: FollowNotice; signIn: boolean} | null>(null);
  return <div className="company-follow"><FollowButton card={card} following={social.following} onNotice={(next, signIn) => setNotice({notice: next, signIn})}/>
    {notice && <span className="company-follow-notice" role="status">{followNoticeText(tr, notice.notice)}{notice.signIn && <button className="text-button" onClick={social.onSignIn}>{tr('common.signIn')}</button>}</span>}</div>;
}

export function CompanySections({assetId, mint, social}: {assetId: string; mint: string; social: CompanySocial}) {
  const tr = useT();
  const [section, setSection] = useState<'comments' | 'holders'>('comments');
  return <section className="company-social" aria-label={tr('market.social.label')}>
    <div className="market-lists company-tabs" role="tablist" aria-label={tr('market.social.sections')}>
      {(['comments', 'holders'] as const).map(item => <button key={item} role="tab" aria-selected={section === item} className={section === item ? 'active' : ''} onClick={() => setSection(item)}>{tr(item === 'comments' ? 'market.social.comments' : 'market.social.holders')}</button>)}
    </div>
    {section === 'holders' ? <HoldersPanel key={mint} api={social.api} mint={mint}/> : <CommentsPanel key={`${assetId}:${mint}`} assetId={assetId} mint={mint} social={social}/>}
  </section>;
}

function HoldersPanel({api, mint}: {api: ProductApiClient; mint: string}) {
  const tr = useT();
  const [page, setPage] = useState<PublicHoldersPage | null>(null), [failed, setFailed] = useState(false), [copied, setCopied] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const controller = new AbortController(); setFailed(false);
    void api.request({path: '/v1/markets/stocks/holders', query: {mint}, signal: controller.signal, parse: value => parseHolders(value, mint)})
      .then(value => {if (!controller.signal.aborted) setPage(value);}, () => {if (!controller.signal.aborted) setFailed(true);});
    return () => controller.abort();
  }, [api, mint, revision]);
  if (failed && !page) return <div className="company-social-state" role="alert"><strong>{tr('market.holders.failedTitle')}</strong><p>{tr('market.holders.failedBody')}</p><button className="text-button" onClick={() => setRevision(n => n + 1)}>{tr('market.holders.retry')}</button></div>;
  if (!page) return <Loading>{tr('market.holders.loading')}</Loading>;
  if (!page.holders.length) return <div className="company-social-state"><strong>{tr('market.holders.empty')}</strong></div>;
  async function copy(owner: string) {
    try {await navigator.clipboard.writeText(owner); setCopied(owner);} catch {setCopied(null);}
  }
  return <div className="holders">
    <div className="holders-head" aria-hidden="true"><span>{tr('market.holders.headHolder')}</span><span>{tr('market.holders.headTokens')}</span></div>
    <ol className="holders-list">{page.holders.map(holder => <li key={holder.owner}><button className="holder-row" onClick={() => void copy(holder.owner)} aria-label={tr('market.holders.copy', {address: holder.owner})}>
      <span className="holder-name"><strong>{holder.primaryDomain ?? shortAddress(holder.owner)}</strong>{holder.primaryDomain && <small>{shortAddress(holder.owner)}</small>}</span>
      <span className="holder-amount" title={fmt.number(holder.amount)}>{quantity(holder.amount)}</span></button></li>)}</ol>
    {copied && <p className="company-social-note" role="status">{tr('market.holders.copied')}</p>}
    <p className="company-social-note">{tr('market.holders.note', {count: page.sampledAccounts})}</p>
  </div>;
}

const reportCategories = [['spam', 'market.report.category.spam'], ['harassment', 'market.report.category.harassment'], ['impersonation', 'market.report.category.impersonation'],
  ['unsafe', 'market.report.category.unsafe'], ['other', 'market.report.category.other']] as const satisfies readonly (readonly [string, MessageKey])[];
function commentsFailure(tr: Translator, error: unknown): string {
  if (error instanceof PracticeError) {
    if (error.status === 401) return tr('market.comments.error.session');
    if (error.code === 'PRACTICE_NETWORK_ERROR') return tr('market.comments.error.offline');
    if (error.code === 'PRACTICE_TIMEOUT') return tr('market.comments.error.timeout');
    if (error.status === 429) return tr('market.comments.error.rateLimited');
  }
  return tr('market.comments.error.failed');
}
function CommentsPanel({assetId, mint, social}: {assetId: string; mint: string; social: CompanySocial}) {
  const {api, identity, privacy} = social;
  const tr = useT();
  const [audience, setAudience] = useState<'everyone' | 'friends'>('everyone');
  const [items, setItems] = useState<readonly SharedReason[] | null>(null), [cursor, setCursor] = useState<string | null>(null);
  const [error, setError] = useState<unknown>(null), [loadingMore, setLoadingMore] = useState(false), [ownCurrent, setOwnCurrent] = useState(false);
  const [reporting, setReporting] = useState<SharedReason | null>(null), [reported, setReported] = useState<ReadonlySet<string>>(new Set()), [notice, setNotice] = useState<MessageKey | null>(null);
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
  // Without a desk the feed cannot be read, so say that instead of claiming there are no comments.
  if (!identity) return <div className="company-social-state"><strong>{tr('market.comments.guestTitle')}</strong><p>{tr('market.comments.guestBody')}</p></div>;
  const visible = (items ?? []).filter(item => !reported.has(item.reasonId));
  const sharedHere = audience === 'everyone' ? privacy?.visibility === 'everyone' : friendsAvailable && privacy?.visibility === 'friends';
  async function report(reason: SharedReason, category: string) {
    const current = identityRef.current;
    if (!current || !('subject' in current)) return;
    try {
      await api.request({path: '/v1/social/reason-reports', method: 'POST', identity: current, expectedStatus: [200, 202],
        body: {schemaVersion: 1, mutationId: newMutationId(), reasonId: reason.reasonId, category},
        parse: value => {const v = read.record(value, ['schemaVersion', 'report']); if (v['schemaVersion'] !== 1) read.invalid(); return true;}});
      setReported(prior => new Set([...prior, reason.reasonId])); setReporting(null); setNotice('market.comments.reported');
    } catch {setNotice('market.comments.actionFailed');}
  }
  return <div className="comments">
    {friendsAvailable && <div className="market-lists" role="tablist" aria-label={tr('market.comments.audience')}>{(['everyone', 'friends'] as const).map(item =>
      <button key={item} role="tab" aria-selected={audience === item} className={audience === item ? 'active' : ''} onClick={() => setAudience(item)}>{tr(item === 'everyone' ? 'market.comments.everyone' : 'market.comments.friends')}</button>)}</div>}
    {ownCurrent && privacy && !sharedHere && <div className="comment-private" role="note"><strong>{tr('market.comments.private')}</strong><button className="text-button" onClick={social.onOpenSettings}>{tr('market.comments.settings')}</button></div>}
    {notice && <p className="company-social-note" role="status">{tr(notice)}</p>}
    {items === null && error === null && <Loading>{tr('market.comments.loading')}</Loading>}
    {items === null && error !== null && <div className="company-social-state" role="alert"><p>{commentsFailure(tr, error)}</p><button className="text-button" onClick={() => setRevision(n => n + 1)}>{tr('common.tryAgain')}</button></div>}
    {items !== null && !visible.length && <div className="company-social-state"><strong>{tr(audience === 'friends' ? 'market.comments.emptyFriends' : 'market.comments.empty')}</strong></div>}
    {visible.map(reason => <article key={reason.reasonId} className="comment-card">
      <header><strong>@{reason.author.handle}</strong><span>{rankName(reason.author.rank)}</span>{reason.author.isViewer && <span className="comment-you">{tr('market.comments.you')}</span>}</header>
      <p>{reason.note}</p>
      <footer><span>{tr('market.comments.saved', {date: reasonSavedAt(reason.savedAt)})}</span>{social.accountSignedIn && !reason.author.isViewer && <button className="text-button" onClick={() => setReporting(reason)}>{tr('market.comments.report')}</button>}</footer>
    </article>)}
    {items !== null && error !== null && <div className="company-social-state" role="alert"><p>{commentsFailure(tr, error)}</p><button className="text-button" onClick={() => void more()}>{tr('common.tryAgain')}</button></div>}
    {items !== null && error === null && cursor && <button className="secondary" disabled={loadingMore} onClick={() => void more()}>{tr(loadingMore ? 'market.comments.loadingMore' : 'market.comments.more')}</button>}
    {reporting && <ReportDialog reason={reporting} onCancel={() => setReporting(null)} onReport={category => report(reporting, category)}/>}
  </div>;
}
function ReportDialog({reason, onCancel, onReport}: {reason: SharedReason; onCancel: () => void; onReport: (category: string) => Promise<void>}) {
  const reportDialogDialog = useRef<HTMLDivElement>(null);
  useModalFocus(reportDialogDialog);
  const tr = useT();
  const [category, setCategory] = useState<string | null>(null), [busy, setBusy] = useState(false);
  const chosen = reportCategories.some(([id]) => id === category);
  return <div className="settings-modal-backdrop" onClick={event => {if (event.target === event.currentTarget && !busy) onCancel();}}>
    <div className="settings-modal" ref={reportDialogDialog} role="dialog" aria-modal="true" aria-labelledby="report-title">
      <h2 id="report-title">{tr('market.report.title')}</h2>
      <p>{tr('market.report.body')}</p>
      <div className="setup-choices" role="radiogroup" aria-label={tr('market.report.reasons')}>{reportCategories.map(([id, key]) => <button key={id} className="setup-choice" role="radio" aria-checked={category === id} onClick={() => setCategory(id)}><span><strong>{tr(key)}</strong></span></button>)}</div>
      {chosen && <p>{tr('market.report.summary', {category, handle: reason.author.handle})}</p>}
      <div className="settings-modal-actions"><button className="text-button" disabled={busy} onClick={onCancel}>{tr('common.cancel')}</button>
        <button className="primary danger" disabled={!category || busy} onClick={async () => {if (!category) return; setBusy(true); try {await onReport(category);} finally {setBusy(false);}}}>{tr('market.report.submit')}</button></div>
    </div>
  </div>;
}
