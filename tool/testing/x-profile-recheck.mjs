/** Explicit one-request recheck after the owner reports X billing is funded.
 * Preserves the original 402 record; never writes credentials or raw errors. */
import {readFile, writeFile, mkdir, access} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {XProfileLookup, XProfileLookupError} from '../../apps/api/src/x-profile-lookup.ts';

export async function recheckXProfile({bearerToken, fetchImpl = globalThis.fetch} = {}) {
  const record = {schemaVersion: 1, checkedAt: new Date().toISOString(),
    endpoint: 'https://api.x.com/2/users/by/username/trimmyhq', method: 'GET',
    credentialClass: 'X application bearer token', attempts: 0, httpStatus: null,
    passed: false, loginVerified: false, ownershipVerified: false, walletUsed: false,
    providerMutation: false, profile: null, errorCode: null,
    precedingObservation: 'X_PROFILE_LOOKUP_SMOKE.json'};
  try {
    const resolver = new XProfileLookup({bearerToken, fetch: async (url, init) => {
      record.attempts++;
      const response = await fetchImpl(url, init);
      record.httpStatus = response.status;
      return response;
    }});
    record.profile = await resolver.lookup('trimmyhq'); record.passed = true;
  } catch (error) {
    record.errorCode = error instanceof XProfileLookupError ? error.code : 'X_LOCAL_CONFIGURATION_UNAVAILABLE';
  }
  return Object.freeze(record);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 3 || process.argv[2] !== '--read-only') {
    console.error('Use --read-only for one authorized trimmyhq public-profile recheck.'); process.exitCode = 1;
  } else {
    try {
      const output = new URL('../../artifacts/verification/X_PROFILE_LOOKUP_RECHECK.json', import.meta.url);
      let exists = false;
      try { await access(output); exists = true; } catch {}
      if (exists) throw new Error(); // Avoid spending quota again on accidental re-runs.
      const supplied = JSON.parse(await readFile(join(homedir(), '.config/trimmy/providers/tip-x.json'), 'utf8'));
      const result = await recheckXProfile({bearerToken: supplied.bearerToken});
      const source = await readFile(new URL('../../apps/api/src/x-profile-lookup.ts', import.meta.url));
      const record = {...result, sourceSha256: createHash('sha256').update(source).digest('hex')};
      await mkdir(new URL('.', output), {recursive: true});
      await writeFile(output, JSON.stringify(record, null, 2) + '\n', {flag: 'wx'});
      console.log(JSON.stringify({passed: record.passed, attempts: record.attempts,
        httpStatus: record.httpStatus, errorCode: record.errorCode, profile: record.profile,
        loginVerified: false, output: output.pathname}));
      if (!record.passed) process.exitCode = 1;
    } catch { console.error('X_RECHECK_LOCAL_UNAVAILABLE_OR_ALREADY_RECORDED'); process.exitCode = 1; }
  }
}
