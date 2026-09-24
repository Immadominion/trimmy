import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {test} from 'node:test';
import {
  GuestSourceError, createGuestCreationSource, readGuestCreationSourceConfig,
} from '../src/guest-creation-source.js';
import type {GuestSourceRequest} from '../src/guest-creation-source.js';

const rawKey = randomBytes(32).toString('base64url');
const key = Buffer.from(rawKey, 'base64url');
const request = (remoteAddress: string | undefined, headers: readonly string[] = []): GuestSourceRequest => ({
  raw: {rawHeaders: headers, socket: {remoteAddress}},
});
const fails = (fn: () => unknown) => assert.throws(fn, error => error instanceof GuestSourceError);

test('direct mode hashes only the transport peer and normalizes mapped IPv4', () => {
  const source = createGuestCreationSource({mode: 'direct', hmacKey: key, trustedProxyCidrs: []});
  const ipv4 = source.hash(request('192.0.2.10'));
  assert.match(ipv4, /^[a-f0-9]{64}$/);
  assert.equal(source.hash(request('::ffff:192.0.2.10')), ipv4);
  assert.equal(source.hash(request('192.0.2.10', ['X-Forwarded-For', '198.51.100.1'])), ipv4);
  assert.notEqual(source.hash(request('192.0.2.11')), ipv4);
});

test('native IPv6 sources share only their /64 and keep another network separate', () => {
  const source = createGuestCreationSource({mode: 'direct', hmacKey: key, trustedProxyCidrs: []});
  assert.equal(source.hash(request('2001:db8:abcd:12::1')), source.hash(request('2001:db8:abcd:12:ffff::9')));
  assert.notEqual(source.hash(request('2001:db8:abcd:12::1')), source.hash(request('2001:db8:abcd:13::1')));
});

test('trusted proxy mode walks a validated chain and uses the first untrusted source', () => {
  const source = createGuestCreationSource({
    mode: 'trusted_proxy', hmacKey: key,
    trustedProxyCidrs: ['127.0.0.0/8', '10.0.0.0/8', '2001:db8:ffff::/48'],
  });
  const throughTwo = source.hash(request('127.0.0.1', ['X-Forwarded-For', '198.51.100.42, 10.3.4.5']));
  const throughOne = source.hash(request('127.0.0.2', ['X-Forwarded-For', '198.51.100.42']));
  assert.equal(throughTwo, throughOne);
  assert.notEqual(throughOne, source.hash(request('127.0.0.2', ['X-Forwarded-For', '198.51.100.43'])));
});

test('trusted proxy mode fails closed on untrusted, missing, duplicate, malformed or ambiguous forwarding', () => {
  const source = createGuestCreationSource({
    mode: 'trusted_proxy', hmacKey: key, trustedProxyCidrs: ['127.0.0.0/8', '10.0.0.0/8'],
  });
  for (const candidate of [
    request('192.0.2.1', ['X-Forwarded-For', '198.51.100.1']),
    request('127.0.0.1'),
    request('127.0.0.1', ['X-Forwarded-For', '198.51.100.1', 'X-Forwarded-For', '198.51.100.2']),
    request('127.0.0.1', ['X-Forwarded-For', '198.51.100.1:443']),
    request('127.0.0.1', ['X-Forwarded-For', '198.51.100.1', 'Forwarded', 'for=198.51.100.1']),
    request('127.0.0.1', ['X-Forwarded-For', '10.1.1.1']),
    request(undefined, ['X-Forwarded-For', '198.51.100.1']),
  ]) fails(() => source.hash(candidate));
});

test('source configuration requires a canonical 32-byte key and an explicit proxy boundary', () => {
  assert.equal(readGuestCreationSourceConfig({}), null);
  const direct = readGuestCreationSourceConfig({
    TRIMMY_GUEST_SOURCE_MODE: 'direct', TRIMMY_GUEST_SOURCE_HMAC_KEY: rawKey,
  });
  assert.equal(direct?.mode, 'direct');
  assert.deepEqual(direct?.trustedProxyCidrs, []);
  const proxy = readGuestCreationSourceConfig({
    TRIMMY_GUEST_SOURCE_MODE: 'trusted_proxy', TRIMMY_GUEST_SOURCE_HMAC_KEY: rawKey,
    TRIMMY_GUEST_TRUSTED_PROXY_CIDRS: '["10.0.0.0/8","2001:db8::/32"]',
  });
  assert.equal(proxy?.mode, 'trusted_proxy');
  for (const env of [
    {TRIMMY_GUEST_SOURCE_MODE: 'direct'},
    {TRIMMY_GUEST_SOURCE_MODE: 'direct', TRIMMY_GUEST_SOURCE_HMAC_KEY: Buffer.alloc(31).toString('base64url')},
    {TRIMMY_GUEST_SOURCE_MODE: 'direct', TRIMMY_GUEST_SOURCE_HMAC_KEY: Buffer.alloc(33).toString('base64url')},
    {TRIMMY_GUEST_SOURCE_MODE: 'direct', TRIMMY_GUEST_SOURCE_HMAC_KEY: `${rawKey}=`},
    {TRIMMY_GUEST_SOURCE_MODE: 'direct', TRIMMY_GUEST_SOURCE_HMAC_KEY: rawKey,
      TRIMMY_GUEST_TRUSTED_PROXY_CIDRS: '["10.0.0.0/8"]'},
    {TRIMMY_GUEST_SOURCE_MODE: 'trusted_proxy', TRIMMY_GUEST_SOURCE_HMAC_KEY: rawKey},
    {TRIMMY_GUEST_SOURCE_MODE: 'trusted_proxy', TRIMMY_GUEST_SOURCE_HMAC_KEY: rawKey,
      TRIMMY_GUEST_TRUSTED_PROXY_CIDRS: '["10.0.0.1/8"]'},
    {TRIMMY_GUEST_SOURCE_MODE: 'trusted_proxy', TRIMMY_GUEST_SOURCE_HMAC_KEY: rawKey,
      TRIMMY_GUEST_TRUSTED_PROXY_CIDRS: '["::ffff:10.0.0.0/104"]'},
  ]) fails(() => readGuestCreationSourceConfig(env));
});
