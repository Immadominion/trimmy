import {randomUUID, randomBytes} from 'node:crypto';
import {writeFileSync, mkdirSync} from 'node:fs';
const API = process.env.API ?? 'https://127.0.0.1:4443';
const out = process.env.OUT;
const steps = [];
let token = null;
async function call(name, method, path, {body, auth = true, accept} = {}) {
  const headers = {'content-type': 'application/json'};
  if (auth && token) headers['authorization'] = `Guest ${token}`;
  if (accept) headers['accept'] = accept;
  const res = await fetch(API + path, {method, headers, body: body ? JSON.stringify(body) : undefined});
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  const record = {name, method, path, status: res.status, cacheControl: res.headers.get('cache-control'), body: redact(json)};
  steps.push(record);
  console.log(`${name}: ${method} ${path} -> ${res.status}`);
  return {status: res.status, json};
}
function redact(v) {
  if (v && typeof v === 'object') {
    const c = Array.isArray(v) ? [] : {};
    for (const [k, val] of Object.entries(v)) c[k] = (k === 'token' || k === 'replaySecret') ? '[redacted]' : redact(val);
    return c;
  }
  return v;
}
const b64url = (buf) => buf.toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
// 1 guest
const guest = await call('create guest', 'POST', '/v1/guest/session', {auth: false, body: {schemaVersion: 1, requestId: randomUUID(), replaySecret: 'gr1_' + b64url(randomBytes(32))}});
if (guest.status !== 201) throw new Error('guest failed');
token = guest.json.token;
// 1b product profile so Career accepts reasons
const prof0 = await call('profile read', 'GET', '/v1/product/profile');
console.log('profile read body', JSON.stringify(prof0.json).slice(0,300));
const baseRev = prof0.json.profile?.revision ?? prof0.json.revision ?? 0;
const handle = 'live' + Math.random().toString(36).slice(2, 10).replace(/[^a-z0-9]/g, 'x');
const prof1 = await call('profile write', 'PUT', '/v1/product/profile', {body: {schemaVersion: 1, mutationId: randomUUID(), baseRevision: baseRev, onboarding: {goal: 'learn', knowledge: 'basics', persona: 'oracle', dailyGoal: 'one-mission', handle}, launchCheckpoint: 'first-trade'}});
if (prof1.status !== 200 && prof1.status !== 201) { console.log(JSON.stringify(prof1.json).slice(0,400)); throw new Error('profile failed'); }
// 2 privacy default
const p0 = await call('privacy default', 'GET', '/v1/career/reason-privacy');
// 3 self empty
await call('self reasons empty', 'GET', '/v1/career/trade-reasons?scope=self');
// 4 search apple
const search = await call('search apple', 'GET', '/v1/markets/stocks/search?query=apple&limit=3', {auth: false});
const apple = (search.json.assets ?? search.json.results ?? []).find(a => a.assetId === 'apple') ?? (search.json.assets ?? search.json.results ?? [])[0];
if (!apple) { console.log(JSON.stringify(search.json).slice(0, 600)); throw new Error('no apple'); }
const mint = apple.providerPrimaryVariantMint ?? apple.variants?.[0]?.mint;
console.log('asset', apple.assetId, 'mint', mint);
// 5 everyone read before any reason (should be empty, 200)
await call('everyone before', 'GET', `/v1/career/trade-reasons?scope=everyone&assetId=${apple.assetId}&variantMint=${mint}`);
// 6 buy 100 paper
const preview = await call('preview buy', 'POST', '/v1/account/paper/orders/preview', {body: {schemaVersion: 1, requestId: randomUUID(), action: 'buy', assetId: apple.assetId, variantMint: mint, amount: {kind: 'paper_amount', paperMicros: '100000000'}}});
if (preview.status !== 200 && preview.status !== 201) { console.log(JSON.stringify(preview.json).slice(0,400)); throw new Error('preview failed'); }
const find=(o,k)=>{if(!o||typeof o!=='object')return undefined;if(k in o)return o[k];for(const v of Object.values(o)){const r=find(v,k);if(r!==undefined)return r;}return undefined;};
console.log('preview object', JSON.stringify(preview.json.preview).slice(0,400));
const previewId = preview.json.preview?.previewId ?? preview.json.preview?.id ?? find(preview.json,'previewId') ?? find(preview.json,'id');
const commit = await call('commit buy', 'POST', '/v1/account/paper/orders/commit', {body: {schemaVersion: 1, previewId, idempotencyKey: randomUUID()}});
if (commit.status !== 200 && commit.status !== 201) { console.log(JSON.stringify(commit.json).slice(0,400)); throw new Error('commit failed'); }
const orderId = commit.json.order?.orderId ?? commit.json.order?.id ?? find(commit.json,'orderId');
console.log('orderId', orderId);
// 7 reason
const reason = await call('write reason', 'POST', '/v1/career/trade-reasons', {body: {schemaVersion: 1, mutationId: randomUUID(), orderId, note: 'Live check after migration 0024. Margins looked steady.'}});
// 8 everyone read while private
const evPrivate = await call('everyone while nobody', 'GET', `/v1/career/trade-reasons?scope=everyone&assetId=${apple.assetId}&variantMint=${mint}`);
// 9 opt in
const m1 = randomUUID();
const put1 = await call('privacy put everyone', 'PUT', '/v1/career/reason-privacy', {body: {schemaVersion: 1, mutationId: m1, baseRevision: p0.json.reasonPrivacy.revision, visibility: 'everyone'}});
const replay = await call('privacy replay', 'PUT', '/v1/career/reason-privacy', {body: {schemaVersion: 1, mutationId: m1, baseRevision: p0.json.reasonPrivacy.revision, visibility: 'everyone'}});
const stale = await call('privacy stale revision', 'PUT', '/v1/career/reason-privacy', {body: {schemaVersion: 1, mutationId: randomUUID(), baseRevision: p0.json.reasonPrivacy.revision, visibility: 'nobody'}});
const rebind = await call('privacy rebind conflict', 'PUT', '/v1/career/reason-privacy', {body: {schemaVersion: 1, mutationId: m1, baseRevision: put1.json.reasonPrivacy?.revision ?? 2, visibility: 'nobody'}});
// 10 everyone read now
const evPublic = await call('everyone after opt-in', 'GET', `/v1/career/trade-reasons?scope=everyone&assetId=${apple.assetId}&variantMint=${mint}&limit=1`);
const self = await call('self after', 'GET', '/v1/career/trade-reasons?scope=self');
// 11 cursor misuse
const cursor = evPublic.json.nextCursor ?? evPublic.json.cursor ?? null;
if (cursor) await call('cursor on other scope', 'GET', `/v1/career/trade-reasons?scope=self&cursor=${encodeURIComponent(cursor)}`);
// 12 friends stored but unavailable
const putFriends = await call('privacy put friends', 'PUT', '/v1/career/reason-privacy', {body: {schemaVersion: 1, mutationId: randomUUID(), baseRevision: put1.json.reasonPrivacy.revision, visibility: 'friends'}});
const evFriends = await call('everyone after friends', 'GET', `/v1/career/trade-reasons?scope=everyone&assetId=${apple.assetId}&variantMint=${mint}`);
const summary = {
  api: API, at: new Date().toISOString(), guestId: guest.json.guestId, asset: apple.assetId, mint, orderId,
  checks: {
    defaultPrivate: p0.json.reasonPrivacy?.visibility === 'nobody' && p0.json.reasonPrivacy?.configured === false && p0.json.reasonPrivacy?.friendsSharing === 'unavailable',
    reasonCreated: reason.status === 201,
    hiddenWhileNobody: evPrivate.status === 200 && (evPrivate.json.items ?? evPrivate.json.reasons ?? []).length === 0,
    optInRevision2: put1.status === 200 && put1.json.reasonPrivacy?.revision === 2 && put1.json.reasonPrivacy?.configured === true,
    replaySame: replay.status === 200 && JSON.stringify(replay.json.reasonPrivacy) === JSON.stringify(put1.json.reasonPrivacy),
    staleConflict: stale.status === 409,
    rebindConflict: rebind.status === 409,
    visibleAfterOptIn: evPublic.status === 200 && (evPublic.json.items ?? evPublic.json.reasons ?? []).length === 1,
    publicOmitsOrderId: evPublic.status === 200 && !JSON.stringify(evPublic.json).includes(orderId),
    selfHasOrderId: self.status === 200 && JSON.stringify(self.json).includes(orderId),
    friendsHidesAgain: evFriends.status === 200 && (evFriends.json.items ?? evFriends.json.reasons ?? []).length === 0,
    noStore: steps.filter(s => s.path.startsWith('/v1/career')).every(s => s.cacheControl === 'no-store'),
  },
};
console.log(JSON.stringify(summary.checks, null, 2));
if (out) { mkdirSync(out, {recursive: true}); writeFileSync(`${out}/live-http.json`, JSON.stringify({summary, steps}, null, 2)); console.log('wrote', `${out}/live-http.json`); }
