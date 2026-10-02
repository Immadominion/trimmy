/** Run release checks without hosted Actions. Logs stay on this machine.
 * Only explicitly requested --publish writes commit statuses, never raw logs.
 * Use a disposable, short-path worktree: public asset preparation changes files.
 */
import {spawn, execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, writeFileSync, openSync, closeSync, readFileSync} from 'node:fs';
import {homedir} from 'node:os';
import {resolve, join, relative} from 'node:path';
import {fileURLToPath} from 'node:url';

export const CHECKS = {
  api: [['npm', ['run', 'check']]],
  database: [
    ['bash', ['infra/tests/run-postgres.sh']],
    ['bash', ['infra/tests/run-workdays-postgres.sh']],
    ['npm', ['run', 'test:mobile-sync']],
    ['npm', ['run', 'test:migration-db']],
    ['npm', ['run', 'test:deployment']],
    // Every other PostgreSQL suite runs too: suites left out of this list
    // went stale unnoticed (red-day dates, reason sharing's schema).
    ['bash', ['infra/tests/run-daily-desk-postgres.sh']],
    ['bash', ['infra/tests/run-community-postgres.sh']],
    ['npm', ['run', 'test:career-red-day-db']],
    ['npm', ['run', 'test:paper-reset-db']],
    ['npm', ['run', 'test:career-reason-sharing-db']],
  ],
  mobile: [
    ['dart', ['format', '--output=none', '--set-exit-if-changed', 'lib', 'test'], 'apps/mobile'],
    ['flutter', ['analyze'], 'apps/mobile'],
    ['flutter', ['test'], 'apps/mobile'],
    ['flutter', ['build', 'apk', '--debug', '--flavor', 'production'], 'apps/mobile'],
  ],
  ios: [['flutter', ['build', 'ios', '--debug', '--no-codesign'], 'apps/mobile']],
  site: [['npm', ['ci', '--no-audit', '--no-fund'], 'apps/site-v2'], ['npm', ['run', 'build'], 'apps/site-v2']],
};

export function parseOptions(args) {
  const options = {checks: ['api', 'database', 'mobile'], root: process.cwd(), publish: false, allowDirty: false};
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--publish') options.publish = true;
    else if (arg === '--allow-dirty') options.allowDirty = true;
    else if (arg === '--repo' && args[i + 1]) options.root = resolve(args[++i]);
    else if (arg === '--checks' && args[i + 1]) options.checks = args[++i].split(',');
    else throw new Error(`Unknown or incomplete option: ${arg}`);
  }
  if (!options.checks.length || options.checks.some(name => !Object.hasOwn(CHECKS, name)) || new Set(options.checks).size !== options.checks.length) {
    throw new Error('Use distinct checks: api,database,mobile,ios,site');
  }
  if (options.publish && options.allowDirty) throw new Error('Cannot publish results from an uncommitted working tree.');
  return options;
}

export function sourceFingerprint(root) {
  const git = (...args) => execFileSync('git', args, {cwd: root, maxBuffer: 32 * 1024 * 1024});
  const hash = createHash('sha256').update(git('rev-parse', 'HEAD'));
  // Read tracked contents, including preparation changes, plus untracked source.
  const paths = git('ls-files', '-z', '--cached', '--others', '--exclude-standard').toString().split('\0').filter(Boolean).sort();
  for (const path of [...new Set(paths)]) {
    hash.update(path).update('\0');
    try { hash.update(readFileSync(join(root, path))); }
    catch (error) { if (error.code !== 'ENOENT') throw error; hash.update('<deleted>'); }
    hash.update('\0');
  }
  return hash.digest('hex');
}

export async function main(args = process.argv.slice(2)) {
  const options = parseOptions(args);
  const root = options.root;
  const git = (...args) => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();
  if (Number(process.versions.node.split('.')[0]) !== 24) throw new Error('Use Node 24, matching CI and package.json.');
  if (execFileSync('npm', ['--version'], {encoding: 'utf8'}).trim() !== '10.9.8') throw new Error('Use npm 10.9.8, matching the lockfile checks.');
  const commit = git('rev-parse', 'HEAD');
  const dirty = git('status', '--porcelain', '--untracked-files=all');
  if (dirty && !options.allowDirty) throw new Error('Use a clean disposable worktree. --allow-dirty is for unpublished development checks only.');
  if (options.checks.includes('database') && join(root, 'infra/.deployment-runtime').length > 80) throw new Error('Database tests need a shorter worktree path (for example ~/trimmy-verify).');
  if (options.publish && !/^https:\/\/github\.com\/Immadominion\/trimmy(?:\.git)?$|^git@github\.com:Immadominion\/trimmy\.git$/.test(git('remote', 'get-url', 'origin'))) throw new Error('Publishing is restricted to the Trimmy repository.');
  const dir = join(homedir(), 'Library/Logs/Trimmy/verify', `${new Date().toISOString().replaceAll(':', '-')}-${commit.slice(0, 8)}`);
  mkdirSync(dir, {recursive: true, mode: 0o700});
  const report = {commit, startedAt: new Date().toISOString(), dirtyAtStart: !!dirty, checks: [], preparation: [], sourceUnchanged: null};
  const save = () => writeFileSync(join(dir, 'report.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  save();
  console.log(`Commit: ${commit}\nPrivate logs: ${dir}`);
  const status = (name, state, description) => {
    if (!options.publish) return;
    execFileSync('gh', ['api', '--method', 'POST', `repos/Immadominion/trimmy/statuses/${commit}`,
      '-f', `state=${state}`, '-f', `context=local-verification/${name}`, '-f', `description=${description}`], {stdio: 'ignore'});
  };
  const run = async (name, [command, args, cwd = '.']) => {
    const log = openSync(join(dir, `${name}.log`), 'a', 0o600);
    console.log(`${name}: ${command} ${args.join(' ')}`);
    const result = await new Promise(resolveResult => {
      const child = spawn(command, args, {cwd: join(root, cwd), env: process.env, stdio: ['ignore', log, log]});
      child.once('error', error => resolveResult({exitCode: null, error: error.code ?? 'SPAWN_ERROR'}));
      child.once('exit', (exitCode, signal) => resolveResult({exitCode, ...(signal ? {signal} : {})}));
    });
    closeSync(log);
    return result;
  };
  const prep = [];
  if (options.checks.some(name => ['api', 'database'].includes(name))) prep.push(['npm', ['ci', '--no-audit', '--no-fund']]);
  prep.push(['node', ['tool/prepare-public-assets.mjs']]);
  if (options.checks.some(name => ['mobile', 'database', 'ios'].includes(name))) prep.push(['flutter', ['pub', 'get', '--enforce-lockfile'], 'apps/mobile']);
  let fingerprint;
  try {
    for (const name of options.checks) status(name, 'pending', 'Checks running on the local Mac; no hosted Actions minutes.');
    for (const command of prep) {
      const result = await run('prepare', command);
      report.preparation.push({command, ...result}); save();
      if (result.exitCode !== 0) throw new Error('Preparation failed; inspect prepare.log.');
    }
    report.preparedDiff = git('diff', '--stat');
    fingerprint = sourceFingerprint(root);
    for (const name of options.checks) {
      const check = {name, startedAt: new Date().toISOString(), steps: [], passed: false};
      report.checks.push(check);
      for (const command of CHECKS[name]) {
        const result = await run(name, command);
        check.steps.push({command, ...result}); save();
        if (result.exitCode !== 0) break;
      }
      check.passed = check.steps.length === CHECKS[name].length && check.steps.every(step => step.exitCode === 0);
      check.finishedAt = new Date().toISOString(); save();
      console.log(`${name}: ${check.passed ? 'PASS' : 'FAIL'} (see ${name}.log)`);
    }
    report.sourceUnchanged = fingerprint === sourceFingerprint(root) && git('rev-parse', 'HEAD') === commit;
    for (const check of report.checks) {
      status(check.name, check.passed && report.sourceUnchanged ? 'success' : 'failure',
        !report.sourceUnchanged ? 'Source changed during checks; rerun on an unchanged checkout.' : check.passed ? 'Passed on local Mac; detailed logs retained locally.' : 'Failed on local Mac; inspect the local verification log.');
    }
    process.exitCode = report.sourceUnchanged && report.checks.every(check => check.passed) ? 0 : 1;
  } catch (error) {
    report.error = error.message;
    for (const name of options.checks) { try { status(name, 'error', 'Local verification interrupted or setup failed.'); } catch {} }
    process.exitCode = 1;
    console.error(error.message);
  } finally {
    report.finishedAt = new Date().toISOString(); save();
    console.log(`Report: ${join(dir, 'report.json')}`);
  }
}

if (process.argv[1] && relative(resolve(process.argv[1]), fileURLToPath(import.meta.url)) === '') {
  main().catch(error => {console.error(error.message); process.exitCode = 1;});
}
