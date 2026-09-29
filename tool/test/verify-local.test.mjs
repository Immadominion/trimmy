import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {parseOptions, sourceFingerprint} from '../verify-local.mjs';

test('never publish dirty development results or silently skip a misspelled check', () => {
  assert.throws(() => parseOptions(['--publish', '--allow-dirty']), /Cannot publish/);
  assert.throws(() => parseOptions(['--checks', 'api,moblie']), /distinct checks/);
  assert.throws(() => parseOptions(['--checks', 'api,api']), /distinct checks/);
  assert.deepEqual(parseOptions(['--checks', 'api,database']).checks, ['api', 'database']);
});

test('detect edits, deletions and new source even if git status filenames do not change', () => {
  const root = mkdtempSync(join(tmpdir(), 'trimmy-verification-test-'));
  const git = (...args) => execFileSync('git', args, {cwd: root, stdio: 'ignore'});
  try {
    git('init'); writeFileSync(join(root, 'source'), 'first'); git('add', 'source');
    git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture');
    const initial = sourceFingerprint(root);
    writeFileSync(join(root, 'source'), 'second'); const second = sourceFingerprint(root);
    writeFileSync(join(root, 'source'), 'third'); assert.notEqual(sourceFingerprint(root), second);
    writeFileSync(join(root, 'source'), 'first'); assert.equal(sourceFingerprint(root), initial);
    writeFileSync(join(root, 'new-source'), 'new'); assert.notEqual(sourceFingerprint(root), initial);
    rmSync(join(root, 'new-source')); rmSync(join(root, 'source')); assert.notEqual(sourceFingerprint(root), initial);
  } finally {rmSync(root, {recursive: true, force: true});}
});
