import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { request as httpsRequest } from 'node:https';
import { request as httpRequest } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { buildApp } from '../src/app.js';
import { createTlsServerFactory, readTlsListenerConfig } from '../src/tls-listener.js';

const dir = mkdtempSync(join(tmpdir(), 'trimmy-tls-'));
const cert = join(dir, 'api.crt');
const key = join(dir, 'api.key');
const otherKey = join(dir, 'other.key');
let opensslAvailable = true;

before(() => {
  try {
    execFileSync('openssl', ['req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes',
      '-keyout', key, '-out', cert, '-subj', '/CN=localhost', '-days', '2',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {stdio: 'ignore'});
    execFileSync('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', otherKey], {stdio: 'ignore'});
  } catch {
    opensslAvailable = false;
  }
});
after(() => rmSync(dir, {recursive: true, force: true}));

test('no TLS variables keeps the plain listener and partial configuration fails closed', () => {
  assert.equal(readTlsListenerConfig({}), null);
  for (const partial of [{TRIMMY_TLS_CERT_FILE: cert}, {TRIMMY_TLS_KEY_FILE: key}, {TRIMMY_TLS_CERT_FILE: cert, TRIMMY_TLS_KEY_FILE: ''}]) {
    assert.throws(() => readTlsListenerConfig(partial), error => {
      assert.ok(error instanceof Error);
      assert.equal(error.message, 'TLS listener configuration is incomplete or invalid.');
      return true;
    });
  }
});

test('unreadable, malformed and mismatched material fail without exposing paths or keys', {skip: !opensslAvailable}, () => {
  const garbage = join(dir, 'garbage.pem');
  writeFileSync(garbage, '-----BEGIN CERTIFICATE-----\nnot-a-certificate\n-----END CERTIFICATE-----\n');
  for (const env of [
    {TRIMMY_TLS_CERT_FILE: join(dir, 'missing-secret-path.crt'), TRIMMY_TLS_KEY_FILE: key},
    {TRIMMY_TLS_CERT_FILE: garbage, TRIMMY_TLS_KEY_FILE: key},
    {TRIMMY_TLS_CERT_FILE: cert, TRIMMY_TLS_KEY_FILE: garbage},
    {TRIMMY_TLS_CERT_FILE: cert, TRIMMY_TLS_KEY_FILE: otherKey},
    {TRIMMY_TLS_CERT_FILE: ` ${cert}`, TRIMMY_TLS_KEY_FILE: key},
  ]) {
    assert.throws(() => readTlsListenerConfig(env), error => {
      assert.ok(error instanceof Error);
      assert.equal(error.message, 'TLS listener configuration is incomplete or invalid.');
      assert.equal(error.message.includes('missing-secret-path'), false);
      return true;
    });
  }
});

test('a matching pair serves the API over TLS 1.2+ and rejects plaintext on the same port', {skip: !opensslAvailable}, async () => {
  const config = readTlsListenerConfig({TRIMMY_TLS_CERT_FILE: cert, TRIMMY_TLS_KEY_FILE: key});
  assert.ok(config);
  assert.equal(config.cert, readFileSync(cert, 'utf8'));
  assert.equal(JSON.stringify(config).includes('PRIVATE KEY'), true, 'the configuration object is never logged; this only proves the key was read');
  const app = buildApp({logger: false, serverFactory: createTlsServerFactory(config)});
  try {
    await app.listen({host: '127.0.0.1', port: 0});
    // Fastify derives its printed scheme from its own https option, so read the
    // bound port from the raw server and prove the transport by connecting.
    const bound = app.server.address();
    assert.ok(bound && typeof bound === 'object');
    const port = bound.port;
    const secure = await new Promise<{status: number | undefined; protocol: string | null; body: string}>((resolve, reject) => {
      const req = httpsRequest({host: '127.0.0.1', port, path: '/health', ca: config.cert, servername: 'localhost', agent: false}, response => {
        // Read the negotiated protocol before the socket detaches at 'end'.
        const protocol = (response.socket as unknown as {getProtocol?: () => string | null}).getProtocol?.() ?? null;
        let body = '';
        response.setEncoding('utf8');
        response.on('data', chunk => { body += chunk; });
        response.on('end', () => resolve({status: response.statusCode, protocol, body}));
      });
      req.on('error', reject);
      req.end();
    });
    assert.equal(secure.status, 200);
    assert.equal(JSON.parse(secure.body).status, 'ok');
    assert.ok(secure.protocol === 'TLSv1.2' || secure.protocol === 'TLSv1.3', secure.protocol ?? 'unknown');
    // A plaintext request must never receive an HTTP response from the TLS port.
    // Node's TLS server may wait for more handshake bytes, so bound the wait.
    const plaintext = await new Promise<string>(resolve => {
      const req = httpRequest({host: '127.0.0.1', port, path: '/health', agent: false}, response => {
        response.resume();
        resolve(`response ${response.statusCode}`);
      });
      req.setTimeout(1500, () => { req.destroy(); resolve('no response'); });
      req.on('error', () => resolve('no response'));
      req.end();
    });
    assert.equal(plaintext, 'no response');
  } finally { await app.close(); }
});
