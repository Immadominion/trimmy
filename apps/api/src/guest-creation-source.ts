import {createHmac, createSecretKey} from 'node:crypto';
import {isIP} from 'node:net';

const sha256 = /^[a-f0-9]{64}$/;
const base64url = /^[A-Za-z0-9_-]+$/;
const MAX_PROXY_HOPS = 16;
const MAX_FORWARDED_BYTES = 2048;

type IpFamily = 4 | 6;
interface ParsedIp {
  readonly family: IpFamily;
  readonly inputFamily: IpFamily;
  readonly bytes: Buffer;
}
interface Cidr {
  readonly family: IpFamily;
  readonly prefix: number;
  readonly network: Buffer;
}

export interface GuestSourceRequest {
  readonly headers?: Readonly<Record<string, string | readonly string[] | undefined>>;
  readonly raw: {
    readonly rawHeaders: readonly string[];
    readonly socket: {readonly remoteAddress: string | undefined};
  };
}

export interface GuestCreationSource {
  hash(request: GuestSourceRequest): string;
}

export interface GuestCreationSourceConfig {
  readonly mode: 'direct' | 'trusted_proxy';
  readonly hmacKey: Buffer;
  readonly trustedProxyCidrs: readonly string[];
}

export class GuestSourceError extends Error {
  constructor() {
    super('Guest creation source is unavailable.');
    this.name = 'GuestSourceError';
  }
}

function fail(): never { throw new GuestSourceError(); }

function parseIpv4(value: string): Buffer {
  const parts = value.split('.');
  if (parts.length !== 4) return fail();
  const bytes = parts.map(part => {
    if (!/^(0|[1-9][0-9]{0,2})$/.test(part)) return fail();
    const byte = Number(part);
    if (byte > 255) return fail();
    return byte;
  });
  return Buffer.from(bytes);
}

function parseIpv6(value: string): Buffer {
  let expanded = value.toLowerCase();
  if (expanded.includes('.')) {
    const separator = expanded.lastIndexOf(':');
    if (separator < 0) return fail();
    const ipv4 = parseIpv4(expanded.slice(separator + 1));
    expanded = `${expanded.slice(0, separator)}:${ipv4.readUInt16BE(0).toString(16)}:${ipv4.readUInt16BE(2).toString(16)}`;
  }
  const halves = expanded.split('::');
  if (halves.length > 2) return fail();
  const left = halves[0] === '' ? [] : halves[0]!.split(':');
  const right = halves.length === 1 || halves[1] === '' ? [] : halves[1]!.split(':');
  if ([...left, ...right].some(part => !/^[0-9a-f]{1,4}$/.test(part))) return fail();
  const missing = 8 - left.length - right.length;
  if ((halves.length === 1 && missing !== 0) || (halves.length === 2 && missing < 1)) return fail();
  const words = [...left, ...Array.from({length: missing}, () => '0'), ...right].map(part => Number.parseInt(part, 16));
  if (words.length !== 8) return fail();
  const bytes = Buffer.alloc(16);
  words.forEach((word, index) => bytes.writeUInt16BE(word, index * 2));
  return bytes;
}

function parseIp(value: string): ParsedIp {
  const inputFamily = isIP(value);
  if (inputFamily !== 4 && inputFamily !== 6) return fail();
  const bytes = inputFamily === 4 ? parseIpv4(value) : parseIpv6(value);
  if (inputFamily === 6 && bytes.subarray(0, 10).every(byte => byte === 0) &&
      bytes[10] === 0xff && bytes[11] === 0xff) {
    return Object.freeze({family: 4, inputFamily, bytes: Buffer.from(bytes.subarray(12))});
  }
  return Object.freeze({family: inputFamily, inputFamily, bytes});
}

function masked(bytes: Buffer, prefix: number): Buffer {
  const result = Buffer.from(bytes);
  for (let bit = prefix; bit < result.length * 8; bit++) {
    result[Math.floor(bit / 8)]! &= ~(1 << (7 - (bit % 8)));
  }
  return result;
}

function parseCidr(value: string): Cidr {
  if (value.trim() !== value || value.length > 80) return fail();
  const parts = value.split('/');
  if (parts.length !== 2 || !/^\d{1,3}$/.test(parts[1]!)) return fail();
  const parsed = parseIp(parts[0]!);
  // Mapped IPv6 must be written as an IPv4 CIDR so prefix width is explicit.
  if (parsed.inputFamily !== parsed.family) return fail();
  const prefix = Number(parts[1]);
  const maximum = parsed.family === 4 ? 32 : 128;
  if (!Number.isInteger(prefix) || prefix < 0 || prefix > maximum) return fail();
  const network = masked(parsed.bytes, prefix);
  if (!network.equals(parsed.bytes)) return fail();
  return Object.freeze({family: parsed.family, prefix, network});
}

function inCidr(ip: ParsedIp, cidr: Cidr): boolean {
  return ip.family === cidr.family && masked(ip.bytes, cidr.prefix).equals(cidr.network);
}

function physicalHeader(request: GuestSourceRequest, name: string): readonly string[] {
  const lower = name.toLowerCase();
  const values: string[] = [];
  const headers = request.raw.rawHeaders;
  if (headers.length % 2 !== 0) return fail();
  for (let index = 0; index < headers.length; index += 2) {
    if (headers[index]?.toLowerCase() === lower) values.push(headers[index + 1] ?? '');
  }
  return values;
}

function normalizedSource(ip: ParsedIp): string {
  if (ip.family === 4) return `ipv4:${[...ip.bytes].join('.')}`;
  // A native IPv6 source is deliberately coarsened to its /64 network.
  return `ipv6:${masked(ip.bytes, 64).subarray(0, 8).toString('hex')}/64`;
}

function deriveSource(request: GuestSourceRequest, mode: GuestCreationSourceConfig['mode'], cidrs: readonly Cidr[]): string {
  const remoteValue = request.raw.socket.remoteAddress;
  if (typeof remoteValue !== 'string' || remoteValue.length > 80) return fail();
  const remote = parseIp(remoteValue);
  if (mode === 'direct') return normalizedSource(remote);

  if (!cidrs.some(cidr => inCidr(remote, cidr))) return fail();
  // X-Forwarded-For is the sole configured wire contract. Accepting both it
  // and Forwarded would make disagreement ambiguous, so that combination is
  // rejected rather than guessed.
  if (physicalHeader(request, 'forwarded').length !== 0) return fail();
  const values = physicalHeader(request, 'x-forwarded-for');
  if (values.length !== 1 || Buffer.byteLength(values[0]!, 'utf8') > MAX_FORWARDED_BYTES) return fail();
  const tokens = values[0]!.split(',').map(value => value.trim());
  if (tokens.length < 1 || tokens.length > MAX_PROXY_HOPS || tokens.some(value => value === '')) return fail();
  const forwarded = tokens.map(parseIp);

  // Start at the verified transport peer and walk toward the client. Every
  // proxy we skip must be in the configured allowlist. The first untrusted
  // address is the client source. An all-trusted chain is ambiguous.
  let current = remote;
  for (let index = forwarded.length - 1; index >= 0; index--) {
    if (!cidrs.some(cidr => inCidr(current, cidr))) return normalizedSource(current);
    current = forwarded[index]!;
  }
  if (cidrs.some(cidr => inCidr(current, cidr))) return fail();
  return normalizedSource(current);
}

/** Parse a stable deployment secret and an explicit network trust mode. */
export function readGuestCreationSourceConfig(
  env: Readonly<Record<string, string | undefined>>,
): GuestCreationSourceConfig | null {
  const rawMode = env['TRIMMY_GUEST_SOURCE_MODE'];
  const rawKey = env['TRIMMY_GUEST_SOURCE_HMAC_KEY'];
  const rawCidrs = env['TRIMMY_GUEST_TRUSTED_PROXY_CIDRS'];
  if (!rawMode && !rawKey && !rawCidrs) return null;
  if (rawMode !== 'direct' && rawMode !== 'trusted_proxy') return fail();
  if (typeof rawKey !== 'string' || rawKey.length > 128 || !base64url.test(rawKey)) return fail();
  const key = Buffer.from(rawKey, 'base64url');
  if (key.length !== 32 || key.toString('base64url') !== rawKey) return fail();
  let rawList: unknown = [];
  if (rawCidrs !== undefined && rawCidrs !== '') {
    if (rawCidrs.length > 4096) return fail();
    try { rawList = JSON.parse(rawCidrs); } catch { return fail(); }
  }
  if (!Array.isArray(rawList) || rawList.some(value => typeof value !== 'string') || rawList.length > 32) return fail();
  const trustedProxyCidrs = rawList as string[];
  if ((rawMode === 'direct' && trustedProxyCidrs.length !== 0) ||
      (rawMode === 'trusted_proxy' && trustedProxyCidrs.length === 0)) return fail();
  // Parse now so malformed or host-bit-bearing networks fail during startup.
  trustedProxyCidrs.forEach(parseCidr);
  return Object.freeze({mode: rawMode, hmacKey: Buffer.from(key), trustedProxyCidrs: Object.freeze([...trustedProxyCidrs])});
}

export function createGuestCreationSource(config: GuestCreationSourceConfig): GuestCreationSource {
  if (!Buffer.isBuffer(config.hmacKey) || config.hmacKey.length !== 32) return fail();
  if (config.mode !== 'direct' && config.mode !== 'trusted_proxy') return fail();
  const cidrs = Object.freeze(config.trustedProxyCidrs.map(parseCidr));
  if ((config.mode === 'direct' && cidrs.length !== 0) || (config.mode === 'trusted_proxy' && cidrs.length === 0)) return fail();
  const key = createSecretKey(Buffer.from(config.hmacKey));
  return Object.freeze({
    hash(request: GuestSourceRequest): string {
      const source = deriveSource(request, config.mode, cidrs);
      const digest = createHmac('sha256', key).update('trimmy.guest.source.v1\0').update(source).digest('hex');
      if (!sha256.test(digest)) return fail();
      return digest;
    },
  });
}
