import {it} from 'node:test';
import assert from 'node:assert/strict';
import {buildApp} from '../src/app.js';

  it('allows bounded multi-stage trade requests beyond the old ten-second socket limit', async () => {
    const app = buildApp({logger: false});
    try { assert.equal(app.initialConfig.connectionTimeout, 60_000); }
    finally { await app.close(); }
  });
