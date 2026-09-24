import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { BoundedSolanaRpc } from '../src/solana-rpc-client.js';

class StageError extends Error {
  constructor(readonly code: string) { super('stage failure'); this.name = 'StageError'; }
}
const errors = {
  configuration: () => new StageError('CONFIGURATION'),
  timeout: () => new StageError('TIMEOUT'),
  unavailable: () => new StageError('UNAVAILABLE'),
  responseInvalid: () => new StageError('RESPONSE_INVALID'),
  methodNotAllowed: () => new StageError('METHOD_NOT_ALLOWED'),
};
type Method = 'getGenesisHash' | 'getMultipleAccounts';

function jsonResponse(body: unknown, init: {status?: number; contentType?: string} = {}): Response {
  return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
    status: init.status ?? 200,
    headers: {'content-type': init.contentType ?? 'application/json'},
  });
}

async function code(promise: Promise<unknown>): Promise<string> {
  try { await promise; } catch (error) { if (error instanceof StageError) return error.code; throw error; }
  return 'no error';
}

describe('BoundedSolanaRpc', () => {
  it('rejects insecure or malformed configuration with the stage code', () => {
    for (const rpcUrl of ['http://rpc.example', 'https://user:pw@rpc.example', 'https://rpc.example/#frag', '', 'not a url']) {
      assert.throws(() => new BoundedSolanaRpc<Method, StageError>({rpcUrl, methods: ['getGenesisHash'], errors}),
        (error: unknown) => error instanceof StageError && error.code === 'CONFIGURATION');
    }
    assert.throws(() => new BoundedSolanaRpc<Method, StageError>({rpcUrl: 'https://rpc.example', methods: [], errors}),
      (error: unknown) => error instanceof StageError && error.code === 'CONFIGURATION');
    assert.throws(() => new BoundedSolanaRpc<Method, StageError>({rpcUrl: 'https://rpc.example', methods: ['getGenesisHash'], errors, timeoutMs: 9_000}),
      (error: unknown) => error instanceof StageError && error.code === 'CONFIGURATION');
  });

  it('only sends allowlisted methods and echoes the request id', async () => {
    const seen: string[] = [];
    const rpc = new BoundedSolanaRpc<Method, StageError>({
      rpcUrl: 'https://rpc.example', methods: ['getGenesisHash'], errors,
      fetch: async (_url, init) => {
        const body = JSON.parse(String(init?.body)) as {id: string; method: string; params: unknown[]};
        seen.push(body.method);
        return jsonResponse({jsonrpc: '2.0', id: body.id, result: 'genesis'});
      },
    });
    const outcome = await rpc.call('getGenesisHash', []);
    assert.equal(outcome.result, 'genesis');
    assert.equal(outcome.contextSlot, null);
    assert.equal(await code(rpc.call('getMultipleAccounts', [[]])), 'METHOD_NOT_ALLOWED');
    assert.equal(await code(rpc.call('sendTransaction' as Method, [])), 'METHOD_NOT_ALLOWED');
    assert.deepEqual(seen, ['getGenesisHash']);
    assert.deepEqual(rpc.allowedMethods, ['getGenesisHash']);
  });

  it('extracts the context slot and api version from envelope results', async () => {
    const rpc = new BoundedSolanaRpc<Method, StageError>({
      rpcUrl: 'https://rpc.example', methods: ['getMultipleAccounts'], errors,
      fetch: async (_url, init) => {
        const body = JSON.parse(String(init?.body)) as {id: string};
        return jsonResponse({jsonrpc: '2.0', id: body.id, result: {context: {slot: 42, apiVersion: '3.1.10'}, value: [null]}});
      },
    });
    const outcome = await rpc.call('getMultipleAccounts', [['11111111111111111111111111111111'], {encoding: 'base64'}]);
    assert.equal(outcome.contextSlot, '42');
    assert.equal(outcome.apiVersion, '3.1.10');
    assert.deepEqual((outcome.result as {value: unknown}).value, [null]);
  });

  it('maps transport, envelope and size failures to fixed codes', async () => {
    const make = (fetch: typeof globalThis.fetch) => new BoundedSolanaRpc<Method, StageError>({
      rpcUrl: 'https://rpc.example', methods: ['getGenesisHash'], errors, fetch, maxBodyBytes: 2_048,
    });
    assert.equal(await code(make(async () => { throw new TypeError('network'); }).call('getGenesisHash', [])), 'UNAVAILABLE');
    assert.equal(await code(make(async () => jsonResponse({}, {status: 500})).call('getGenesisHash', [])), 'UNAVAILABLE');
    assert.equal(await code(make(async () => jsonResponse('{}', {contentType: 'text/plain'})).call('getGenesisHash', [])), 'RESPONSE_INVALID');
    assert.equal(await code(make(async () => jsonResponse('not json')).call('getGenesisHash', [])), 'RESPONSE_INVALID');
    assert.equal(await code(make(async (_url, init) => {
      const body = JSON.parse(String(init?.body)) as {id: string};
      return jsonResponse({jsonrpc: '2.0', id: body.id, error: {code: -32000, message: 'x'}});
    }).call('getGenesisHash', [])), 'RESPONSE_INVALID');
    assert.equal(await code(make(async () => jsonResponse({jsonrpc: '2.0', id: 'other', result: 1})).call('getGenesisHash', [])), 'RESPONSE_INVALID');
    assert.equal(await code(make(async (_url, init) => {
      const body = JSON.parse(String(init?.body)) as {id: string};
      return jsonResponse({jsonrpc: '2.0', id: body.id, result: 'x'.repeat(4_096)});
    }).call('getGenesisHash', [])), 'RESPONSE_INVALID');
  });

  it('enforces one total deadline per call', async () => {
    const rpc = new BoundedSolanaRpc<Method, StageError>({
      rpcUrl: 'https://rpc.example', methods: ['getGenesisHash'], errors, timeoutMs: 20,
      fetch: (_url, init) => new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
      }),
    });
    assert.equal(await code(rpc.call('getGenesisHash', [])), 'TIMEOUT');
  });
});
