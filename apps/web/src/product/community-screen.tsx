import {useCallback, useEffect, useRef, useState} from 'react';
import {read} from './product-api';
import type {ProductApiClient} from './product-api';
import type {PracticeAccountProof} from './practice-client';
import {newMutationId} from './career-actions';
import {reasonSavedAt} from './company-social';
import {Loading, art} from './ui';

/* Mobile's community.dart: GET /v1/community (everyone, following, notifications)
 * and PUT /v1/community/following/:socialId. Accounts only, as on mobile. */

export type CommunityScope = 'everyone' | 'following' | 'notifications';
export interface CommunityPost {
  readonly reasonId: string; readonly socialId: string; readonly handle: string | null; readonly persona: string | null;
  readonly assetId: string; readonly variantMint: string; readonly symbol: string; readonly note: string; readonly savedAt: string;
  readonly following: boolean; readonly notifications: boolean; readonly isViewer: boolean;
}
export interface CommunityPage {readonly posts: readonly CommunityPost[]; readonly next: {readonly at: string; readonly id: string} | null}
export function parseCommunity(value: unknown): CommunityPage {
  const v = read.record(value, ['items', 'next']);
  const posts = read.array(v['items'], 20).map(item => {
    const p = read.record(item, ['reasonId', 'socialId', 'handle', 'persona', 'assetId', 'variantMint', 'symbol', 'note', 'savedAt', 'following', 'notifications', 'isViewer']);
    const handle = read.nullable(p['handle'], h => {const text = read.string(h, 18); if (!/^[a-z][a-z0-9_]{2,17}$/u.test(text)) read.invalid(); return text;});
    const asset = read.string(p['assetId'], 100); if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(asset)) read.invalid();
    return Object.freeze({reasonId: read.uuid(p['reasonId']), socialId: read.uuid(p['socialId']), handle,
      persona: read.nullable(p['persona'], x => read.oneOf(x, ['wolf', 'oracle', 'shark'])), assetId: asset,
      variantMint: read.string(p['variantMint'], 44), symbol: read.string(p['symbol'], 30), note: read.string(p['note'], 180),
      savedAt: read.instant(p['savedAt']), following: read.boolean(p['following']), notifications: read.boolean(p['notifications']), isViewer: read.boolean(p['isViewer'])});
  });
  const next = read.nullable(v['next'], n => {const r = read.record(n, ['at', 'id']); return Object.freeze({at: read.instant(r['at']), id: read.uuid(r['id'])});});
  return Object.freeze({posts, next});
}
export const communityApi = {
  read: (api: ProductApiClient, account: PracticeAccountProof, scope: CommunityScope, cursor?: {at: string; id: string} | null, signal?: AbortSignal) =>
    api.request({path: '/v1/community', identity: account, signal, query: {scope, at: cursor?.at, id: cursor?.id}, maxBytes: 65_536, parse: parseCommunity}),
  follow: (api: ProductApiClient, account: PracticeAccountProof, socialId: string, following: boolean, notifications: boolean) =>
    api.request({path: `/v1/community/following/${read.uuid(socialId)}`, method: 'PUT', identity: account, body: {following, notifications},
      parse: value => read.boolean(read.record(value, ['following'])['following'])}),
  report: (api: ProductApiClient, account: PracticeAccountProof, reasonId: string, category: string) =>
    api.request({path: '/v1/social/reason-reports', method: 'POST', identity: account, expectedStatus: [200, 202],
      body: {schemaVersion: 1, mutationId: newMutationId(), reasonId, category}, parse: value => {read.record(value, ['schemaVersion', 'report']); return true;}}),
  async block(api: ProductApiClient, account: PracticeAccountProof, socialId: string) {
    const current = await api.request({path: `/v1/social/blocks/${read.uuid(socialId)}`, identity: account,
      parse: value => read.integer(read.record(read.record(value, ['schemaVersion', 'block'])['block'])['revision'])});
    return api.request({path: `/v1/social/blocks/${read.uuid(socialId)}`, method: 'PUT', identity: account,
      body: {schemaVersion: 1, mutationId: newMutationId(), baseRevision: current, blocked: true},
      parse: value => read.boolean(read.record(read.record(value, ['schemaVersion', 'mutationId', 'appliedRevision', 'block'])['block'])['blocked'])});
  },
};

/** Mobile's CommunityScreen. The Updates inbox is the notifications scope. */
export function CommunityScreen({api, account, initialScope, onOpenAsset, onBack}: {
  api: ProductApiClient; account: PracticeAccountProof; initialScope: CommunityScope; onOpenAsset: (assetId: string) => void; onBack: () => void;
}) {
  const [scope, setScope] = useState<CommunityScope>(initialScope);
  const [posts, setPosts] = useState<readonly CommunityPost[]>([]), [next, setNext] = useState<CommunityPage['next']>(null);
  const [loading, setLoading] = useState(true), [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<ReadonlySet<string>>(new Set()), [menu, setMenu] = useState<string | null>(null);
  const [hidden, setHidden] = useState<ReadonlySet<string>>(new Set()), [notice, setNotice] = useState<string | null>(null);
  const heading = useRef<HTMLHeadingElement>(null), generation = useRef(0);
  useEffect(() => {heading.current?.focus();}, [scope]);
  const load = useCallback(async (more = false) => {
    const turn = more ? generation.current : ++generation.current;
    setLoading(true); setError(null);
    try {
      const page = await communityApi.read(api, account, scope, more ? next : null);
      if (turn !== generation.current) return;
      setPosts(prior => more ? [...prior, ...page.posts.filter(post => !prior.some(item => item.reasonId === post.reasonId))] : page.posts); setNext(page.next);
    } catch {if (turn === generation.current) setError('Couldn’t load activity. Try again.');}
    finally {if (turn === generation.current) setLoading(false);}
  }, [api, account, scope, next]);
  useEffect(() => {setPosts([]); setNext(null); void load(false);
    // Reload only when the scope changes; paging uses the stored cursor.
  }, [scope, api, account]);
  async function change(post: CommunityPost, work: () => Promise<unknown>, done?: string) {
    if (busy.has(post.socialId)) return;
    setBusy(prior => new Set([...prior, post.socialId])); setMenu(null); setNotice(null);
    try {await work(); if (done) setNotice(done); await load(false);}
    catch {setError('That change didn’t save. Try again.');}
    finally {setBusy(prior => {const nextSet = new Set(prior); nextSet.delete(post.socialId); return nextSet;});}
  }
  const visible = posts.filter(post => !hidden.has(post.reasonId) && !hidden.has(post.socialId));
  const empty = scope === 'notifications' ? ['You’re all caught up', 'New comments from people you follow appear here.']
    : scope === 'following' ? ['Your people, here', 'Follow a trader from Everyone.'] : ['No shared comments yet', 'Public comments will appear here.'];
  return <section className="community-screen" aria-labelledby="community-heading">
    <button className="company-back" onClick={onBack}>← Back to my desk</button>
    <div className="page-intro"><h1 id="community-heading" ref={heading} tabIndex={-1}>{scope === 'notifications' ? 'Updates' : 'Community'}</h1></div>
    {scope !== 'notifications' && <div className="market-lists" role="tablist" aria-label="Community lists">{(['everyone', 'following'] as const).map(item =>
      <button key={item} role="tab" aria-selected={scope === item} className={scope === item ? 'active' : ''} onClick={() => setScope(item)}>{item === 'everyone' ? 'Everyone' : 'Following'}</button>)}</div>}
    {notice && <p className="company-social-note" role="status">{notice}</p>}
    {error && <div className="company-social-state" role="alert"><p>{error}</p><button className="text-button" onClick={() => void load(false)}>Retry</button></div>}
    {loading && !posts.length && !error && <Loading>Opening community…</Loading>}
    {!loading && !error && !visible.length && <div className="company-social-state"><img src={art('icons/career-comments.png')} alt="" width="32" height="32"/><strong>{empty[0]}</strong><p>{empty[1]}</p></div>}
    <div className="community-posts">{visible.map(post => <article key={post.reasonId} className="comment-card community-post">
      <header><strong>{post.handle ? `@${post.handle}` : 'Trader'}</strong>
        {!post.isViewer && <button className={`follow-button${post.following ? ' following' : ''}`} disabled={busy.has(post.socialId)} aria-pressed={post.following}
          onClick={() => void change(post, () => communityApi.follow(api, account, post.socialId, !post.following, true))}>{post.following ? 'Following' : '+ Follow'}</button>}
        {!post.isViewer && <button className="community-more" aria-label="Comment options" aria-expanded={menu === post.reasonId} onClick={() => setMenu(menu === post.reasonId ? null : post.reasonId)}>⋯</button>}
      </header>
      {menu === post.reasonId && <div className="community-menu" role="menu">
        {post.following && <button role="menuitem" onClick={() => void change(post, () => communityApi.follow(api, account, post.socialId, true, !post.notifications))}>{post.notifications ? 'Mute updates' : 'Turn on updates'}</button>}
        <button role="menuitem" onClick={() => void change(post, async () => {await communityApi.report(api, account, post.reasonId, 'other'); setHidden(prior => new Set([...prior, post.reasonId]));}, 'Report received.')}>Report</button>
        <button role="menuitem" onClick={() => void change(post, async () => {await communityApi.block(api, account, post.socialId); setHidden(prior => new Set([...prior, post.socialId]));}, `${post.handle ? `@${post.handle}` : 'This trader'} is blocked.`)}>Block trader</button>
      </div>}
      <button className="community-symbol text-button" onClick={() => onOpenAsset(post.assetId)}>${post.symbol}</button>
      <p>{post.note}</p>
      <footer><span>{reasonSavedAt(post.savedAt)}</span></footer>
    </article>)}</div>
    {next && <button className="secondary" disabled={loading} onClick={() => void load(true)}>Load more</button>}
  </section>;
}

/** Home's Community block: two recent public comments, or an invitation to look. */
export function CommunityPreview({api, account, onOpen}: {api: ProductApiClient | null; account: PracticeAccountProof | null; onOpen: () => void}) {
  const [posts, setPosts] = useState<readonly CommunityPost[] | null>(null), [failed, setFailed] = useState(false);
  const accountRef = useRef(account); accountRef.current = account;
  const signedIn = account !== null;
  useEffect(() => {
    const current = accountRef.current;
    if (!api || !current) {setPosts(null); return;}
    const controller = new AbortController(); setFailed(false);
    void communityApi.read(api, current, 'everyone', null, controller.signal).then(page => {if (!controller.signal.aborted) setPosts(page.posts);}, () => {if (!controller.signal.aborted) setFailed(true);});
    return () => controller.abort();
  }, [api, signedIn]);
  return <section className="desk-section home-community" aria-labelledby="home-community-heading">
    <div className="section-line"><h2 id="home-community-heading">Community</h2><button className="text-button" onClick={onOpen}>Open<span aria-hidden="true">↗</span></button></div>
    {!signedIn ? <button className="home-community-row" onClick={onOpen}><img src={art('icons/career-comments.png')} alt=""/><span><strong>See what traders are saying</strong><small>Sign in to join the conversation.</small></span></button>
      : posts && posts.length ? posts.slice(0, 2).map(post => <button key={post.reasonId} className="home-community-row" onClick={onOpen}><img src={art('icons/career-comments.png')} alt=""/>
        <span><strong>{post.handle ? `@${post.handle}` : 'A trader'} on ${post.symbol}</strong><small>{post.note}</small></span></button>)
      : <button className="home-community-row" onClick={onOpen}><img src={art('icons/career-comments.png')} alt=""/><span><strong>{failed ? 'Community couldn’t load' : posts === null ? 'Opening community…' : 'Start a conversation'}</strong><small>Public comments from other traders.</small></span></button>}
  </section>;
}
