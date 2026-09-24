#!/usr/bin/env node
// Starts the real built API against a real migrated PostgreSQL and exercises
// the authenticated practice path over HTTP, the way a deployment serves it.
// The database URL it is given is the RESTRICTED runtime role, never the owner
// credential used to migrate.
//
// The harness in infra/tests/run-deployment-smoke.sh provisions the database,
// applies migrations with tool/runtime/apply-migrations.mjs and then runs this.
import assert from 'node:assert/strict';
import { generateKeyPairSync, randomBytes, randomUUID, sign } from 'node:crypto';
import { spawn } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectDir = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const APP_ID = 'deployment-smoke-app';
const PORT = Number(process.env['TRIMMY_SMOKE_PORT'] ?? '4455');
const ORIGIN = `http://127.0.0.1:${PORT}`;
const SUBJECT = `did:privy:smoke${Date.now().toString(36)}`;

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

/** A locally signed ES256 token stands in for a Privy session. */
function token(privateKey, subject) {
  const now = Math.floor(Date.now() / 1000);
  const claims = {iss: 'privy.io', aud: APP_ID, sub: subject, iat: now - 5, exp: now + 3600, sid: 'deployment-smoke'};
  const unsigned = [{alg: 'ES256', typ: 'JWT'}, claims]
    .map(value => Buffer.from(JSON.stringify(value)).toString('base64url')).join('.');
  const signature = sign('sha256', Buffer.from(unsigned), {key: privateKey, dsaEncoding: 'ieee-p1363'});
  return `${unsigned}.${signature.toString('base64url')}`;
}

async function call(path, {method = 'GET', bearer, guest, accept, body} = {}) {
  const response = await fetch(`${ORIGIN}${path}`, {
    method,
    headers: {
      ...(bearer ? {authorization: `Bearer ${bearer}`} : {}),
      ...(guest ? {authorization: `Guest ${guest}`} : {}),
      ...(accept ? {accept} : {}),
      ...(body === undefined ? {} : {'content-type': 'application/json'}),
    },
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
  });
  const text = await response.text();
  let json;
  try { json = text ? JSON.parse(text) : undefined; } catch { json = undefined; }
  return {status: response.status, json, text};
}

async function waitForHealth() {
  for (let attempt = 0; attempt < 80; attempt++) {
    try {
      const response = await fetch(`${ORIGIN}/health`);
      if (response.ok) return true;
    } catch { /* not listening yet */ }
    await new Promise(resolvePromise => setTimeout(resolvePromise, 250));
  }
  return false;
}

/**
 * A real payload-6 history whose completions satisfy every prerequisite up to
 * and including the requested activity, so the server accepts it as genuine
 * acknowledged progress rather than a forged jump.
 */
function historyThrough(catalog, lastActivityId, completedAt) {
  const ids = catalog.practiceCatalogActivityIds;
  const byId = catalog.practiceCatalogById;
  const completions = {};
  for (const id of ids) {
    const entry = byId[id];
    completions[id] = {
      activityId: id,
      selectedChoiceId: entry.correctChoiceId,
      // The correct answer is an accepted answer, so it was not corrected.
      corrected: false,
      completedAt,
      importedFromLegacy: false,
    };
    if (id === lastActivityId) break;
  }
  return {version: 6, active: null, completions};
}

async function main() {
  const databaseUrl = requireEnv('TRIMMY_SMOKE_DATABASE_URL');
  const caFile = process.env['TRIMMY_SMOKE_DATABASE_CA_FILE'];
  const socialModeratorRole = requireEnv('TRIMMY_SMOKE_SOCIAL_MODERATOR_ROLE');
  const catalog = await import('@trimmy/domain');

  const {privateKey, publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
  const verificationKey = publicKey.export({type: 'spki', format: 'pem'}).toString();
  const bearer = token(privateKey, SUBJECT);

  const api = spawn(process.execPath, [join(projectDir, 'apps', 'api', 'dist', 'index.js')], {
    cwd: projectDir,
    env: {
      PATH: process.env['PATH'], HOME: process.env['HOME'],
      HOST: '127.0.0.1', PORT: String(PORT), LOG_LEVEL: 'warn',
      PRIVY_APP_ID: APP_ID, PRIVY_VERIFICATION_KEY: verificationKey,
      PRACTICE_DATABASE_URL: databaseUrl,
      TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE: socialModeratorRole,
      TRIMMY_GUEST_SOURCE_MODE: 'direct',
      TRIMMY_GUEST_SOURCE_HMAC_KEY: randomBytes(32).toString('base64url'),
      ...(caFile ? {PRACTICE_DATABASE_CA_FILE: caFile} : {}),
    },
    stdio: ['ignore', 'inherit', 'inherit'],
  });
  let exited = null;
  api.on('exit', code => { exited = code; });

  try {
    if (!await waitForHealth()) {
      throw new Error(`The API never became healthy (child exit code: ${exited}).`);
    }
    console.log('health: ok');

    // Readiness is the answer a load balancer needs, and it is a different
    // question from liveness: this instance has a database, so it must say so.
    const ready = await call('/ready');
    assert.equal(ready.status, 200, ready.text);
    assert.equal(ready.json.database, 'ok', 'a deployed instance with a database must report it reachable');
    assert.equal(ready.json.status, 'ready');
    assert.equal(ready.json.financialOperationsEnabled, false);
    for (const secret of ['password', 'sslmode', 'postgresql://']) {
      assert.ok(!ready.text.includes(secret), `the readiness body must not carry ${secret}`);
    }
    console.log('ready: database reachable, no connection detail exposed');

    const config = await call('/v1/config');
    assert.equal(config.status, 200, config.text);
    assert.equal(config.json.practiceAccountsEnabled, true, 'practice accounts must be enabled');
    // A real deployment must still report every money capability as off.
    for (const [key, value] of Object.entries(config.json)) {
      if (/gift|trade|order|withdraw|deposit|financial|purchase/i.test(key)) {
        assert.equal(value, false, `${key} must remain disabled`);
      }
    }
    console.log('config: practice accounts enabled, money capabilities disabled');

    const guestCreation = await call('/v1/guest/session', {method: 'POST', body: {
      schemaVersion: 1, requestId: randomUUID(), replaySecret: `gr1_${randomBytes(32).toString('base64url')}`,
    }});
    assert.equal(guestCreation.status, 201, guestCreation.text);
    const guest = guestCreation.json.token;
    const accept = 'application/vnd.trimmy.product-profile.v2+json';
    const unanswered = {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null};
    const initialGuestProfile = await call('/v1/product/profile', {method: 'PUT', guest, body: {
      schemaVersion: 2, mutationId: randomUUID(), baseRevision: 0,
      onboarding: unanswered, launchCheckpoint: 'first-trade',
    }});
    assert.equal(initialGuestProfile.status, 200, initialGuestProfile.text);
    assert.equal(initialGuestProfile.json.schemaVersion, 2);
    assert.deepEqual(initialGuestProfile.json.profile.onboarding, unanswered);
    assert.equal(initialGuestProfile.json.profile.hasConfirmedPaperTrade, false);
    const noTradeCompletion = await call('/v1/product/launch', {method: 'POST', guest, body: {
      schemaVersion: 2, mutationId: randomUUID(), baseRevision: 1, action: 'introduction-completed',
    }});
    assert.equal(noTradeCompletion.status, 409, noTradeCompletion.text);
    assert.equal(noTradeCompletion.json.error.code, 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED');
    const skipCommand = {schemaVersion: 2, mutationId: randomUUID(), baseRevision: 1,
      action: 'introduction-skipped'};
    const skipped = await call('/v1/product/launch', {method: 'POST', guest, body: skipCommand});
    assert.equal(skipped.status, 200, skipped.text);
    assert.equal(skipped.json.profile.launchCheckpoint, 'app');
    assert.equal(skipped.json.profile.hasConfirmedPaperTrade, false);
    assert.deepEqual(skipped.json.profile.onboarding, unanswered);
    const skipReplay = await call('/v1/product/launch', {method: 'POST', guest, body: skipCommand});
    assert.deepEqual(skipReplay.json, skipped.json);
    const restoredSkip = await call('/v1/product/profile', {guest, accept});
    assert.deepEqual(restoredSkip.json, skipped.json);
    const legacySkip = await call('/v1/product/profile', {guest});
    assert.equal(legacySkip.status, 409, legacySkip.text);
    assert.equal(legacySkip.json.error.code, 'PRODUCT_PROFILE_UPGRADE_REQUIRED');
    console.log('introduction: real guest nullable profile and skip persisted idempotently; no trade claimed');

    const catalogResponse = await call('/v1/practice/catalog');
    assert.equal(catalogResponse.status, 200, catalogResponse.text);
    assert.equal(catalogResponse.json.activities.length, 14);
    assert.equal(catalogResponse.json.currentPayloadVersion, 6);
    assert.deepEqual(catalogResponse.json.supportedPayloadVersions, [3, 4, 5, 6]);
    assert.equal(catalogResponse.json.floors['4'], 'Make the plan');
    console.log(`catalog: ${catalogResponse.json.activities.length} activities, `
      + `payload v${catalogResponse.json.currentPayloadVersion}, content ${catalogResponse.json.contentVersion}`);

    const anonymous = await call('/v1/practice/progress');
    assert.equal(anonymous.status, 401, anonymous.text);
    const forged = await call('/v1/practice/progress', {bearer: `${bearer}x`});
    assert.equal(forged.status, 401, forged.text);
    console.log('auth: unauthenticated and tampered tokens are refused');

    // The progress routes require an account that already exists; the session
    // route is what provisions it from a verified token.
    const session = await call('/v1/practice/session', {method: 'POST', bearer, body: {}});
    assert.equal(session.status, 200, session.text);
    assert.equal(session.json.schemaVersion, 1);
    assert.match(session.json.userId, /^[0-9a-f-]{36}$/);
    console.log('session: a verified token provisioned a real account row');

    const onboarding = {
      goal: 'learn', knowledge: 'nothing', persona: 'wolf', dailyGoal: 'one-mission', handle: 'smoke_rookie',
    };
    const profile = await call('/v1/product/profile', {
      method: 'PUT', bearer,
      body: {
        schemaVersion: 1, mutationId: randomUUID(), baseRevision: 0,
        onboarding, launchCheckpoint: 'first-trade',
      },
    });
    assert.equal(profile.status, 200, profile.text);
    assert.equal(profile.json.profile.revision, 1);
    assert.equal(profile.json.profile.launchCheckpoint, 'first-trade');

    // A generic profile write cannot forge launch progress, and the explicit
    // action endpoint checks immutable server evidence before moving it.
    const forgedCheckpoint = await call('/v1/product/profile', {
      method: 'PUT', bearer,
      body: {
        schemaVersion: 1, mutationId: randomUUID(), baseRevision: 1,
        onboarding, launchCheckpoint: 'first-position',
      },
    });
    assert.equal(forgedCheckpoint.status, 409, forgedCheckpoint.text);
    assert.equal(forgedCheckpoint.json.error.code, 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT');
    const unevidencedLaunch = await call('/v1/product/launch', {
      method: 'POST', bearer,
      body: {
        schemaVersion: 1, mutationId: randomUUID(), baseRevision: 1,
        action: 'paper-trade-confirmed',
      },
    });
    assert.equal(unevidencedLaunch.status, 409, unevidencedLaunch.text);
    assert.equal(unevidencedLaunch.json.error.code, 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED');
    const unchangedProfile = await call('/v1/product/profile', {bearer});
    assert.equal(unchangedProfile.status, 200, unchangedProfile.text);
    assert.equal(unchangedProfile.json.profile.revision, 1);
    assert.equal(unchangedProfile.json.profile.launchCheckpoint, 'first-trade');
    console.log('launch: generic checkpoint forgery and an action without server evidence were refused');

    const empty = await call('/v1/practice/progress', {bearer});
    assert.equal(empty.status, 200, empty.text);
    assert.equal(empty.json.revision, 0);
    assert.equal(empty.json.progress, null);
    console.log('account: first read returns revision 0 with no progress');

    // A genuine fourth-floor completion, which only payload v6 and migration
    // 0008 make storable.
    const completedAt = '2026-09-15T18:30:00.123456Z';
    const progress = historyThrough(catalog, 'set-a-loss-limit', completedAt);
    assert.equal(Object.keys(progress.completions).length, 12);
    const mutationId = randomUUID();
    const saved = await call('/v1/practice/progress', {
      method: 'PUT', bearer, body: {schemaVersion: 1, mutationId, baseRevision: 0, progress},
    });
    assert.equal(saved.status, 200, saved.text);
    assert.equal(saved.json.revision, 1);
    assert.equal(saved.json.progress.version, 6);
    assert.equal(saved.json.progress.completions['set-a-loss-limit'].selectedChoiceId, 'commit-spare-only');
    console.log('write: a payload v6 history including a Floor 4 completion persisted at revision 1');

    const readBack = await call('/v1/practice/progress', {bearer});
    assert.equal(readBack.status, 200, readBack.text);
    assert.equal(readBack.json.revision, 1);
    assert.equal(readBack.json.progress.completions['set-a-loss-limit'].completedAt, completedAt);
    console.log('read: the saved Floor 4 completion returns with its exact microsecond timestamp');

    // Replaying the same mutation must return the original acknowledgement.
    const replay = await call('/v1/practice/progress', {
      method: 'PUT', bearer, body: {schemaVersion: 1, mutationId, baseRevision: 0, progress},
    });
    assert.equal(replay.status, 200, replay.text);
    assert.equal(replay.json.revision, 1);
    console.log('retry: replaying the same mutation id returns the original revision');

    // A version this build does not support must not reach storage.
    const future = await call('/v1/practice/progress', {
      method: 'PUT', bearer,
      body: {schemaVersion: 1, mutationId: randomUUID(), baseRevision: 1, progress: {...progress, version: 7}},
    });
    assert.equal(future.status, 400, future.text);
    assert.equal(future.json.error.code, 'PRACTICE_INVALID_INPUT');
    console.log('guard: a payload v7 write is refused before storage');

    const stillOne = await call('/v1/practice/progress', {bearer});
    assert.equal(stillOne.json.revision, 1);

    // Closing is the last thing this account can do, so it goes last.
    const wrongWords = await call('/v1/account/closure', {
      method: 'POST', bearer, body: {schemaVersion: 1, confirm: 'yes please'},
    });
    assert.equal(wrongWords.status, 400, wrongWords.text);
    assert.equal(wrongWords.json.error.code, 'ACCOUNT_CLOSURE_INVALID_INPUT');
    const closed = await call('/v1/account/closure', {
      method: 'POST', bearer, body: {schemaVersion: 1, confirm: 'close my account'},
    });
    assert.equal(closed.status, 200, closed.text);
    assert.equal(closed.json.closed, true);
    console.log('closure: the account was closed through the built API');

    // A closed account cannot authenticate, so its own history is unreachable
    // and it cannot start a new session.
    const afterClosure = await call('/v1/practice/progress', {bearer});
    assert.equal(afterClosure.status, 401, afterClosure.text);
    // Signing in again does not quietly create a second account: the server
    // says the account exists and is unavailable.
    const reopened = await call('/v1/practice/session', {method: 'POST', bearer, body: {}});
    assert.equal(reopened.status, 403, reopened.text);
    assert.equal(reopened.json.error.code, 'PRACTICE_ACCOUNT_UNAVAILABLE');
    console.log('closure: the closed account cannot read its progress or be provisioned again');

    console.log('\nPASS: the built API served a real migrated PostgreSQL over HTTP, '
      + 'provisioned a verified account, enforced server-evidenced launch progress, '
      + 'stored and returned a Floor 4 payload v6 history, '
      + 'replayed a mutation idempotently, refused an unsupported version, and '
      + 'closed the account so it could no longer sign in.');
  } finally {
    api.kill('SIGTERM');
    await new Promise(resolvePromise => {
      if (exited !== null) return resolvePromise();
      api.once('exit', resolvePromise);
      setTimeout(() => { api.kill('SIGKILL'); resolvePromise(); }, 5000);
    });
  }
}

main().catch(error => {
  process.stderr.write(`${error instanceof Error ? error.message : 'Deployment smoke failed.'}\n`);
  process.exitCode = 1;
});
