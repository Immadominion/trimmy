import { createPrivateKey, X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:https';
import type { FastifyServerFactory } from 'fastify';

/** PEM material read once at startup. Never logged, serialized or re-exported. */
export interface TlsListenerConfig {
  readonly cert: string;
  readonly key: string;
}

const MAX_PEM_BYTES = 65_536;

function invalid(): never {
  // The fixed message keeps file paths and key material out of logs.
  throw new Error('TLS listener configuration is incomplete or invalid.');
}

function readPem(path: string): string {
  if (path.length === 0 || path.length > 4096 || path.trim() !== path || /[\x00-\x1f\x7f]/.test(path)) invalid();
  let text: string;
  try {
    text = readFileSync(path, {encoding: 'utf8', flag: 'r'});
  } catch {
    return invalid();
  }
  if (text.length === 0 || Buffer.byteLength(text, 'utf8') > MAX_PEM_BYTES) invalid();
  return text;
}

/**
 * Optional native HTTPS. Both TRIMMY_TLS_CERT_FILE and TRIMMY_TLS_KEY_FILE are
 * required together; either alone fails startup instead of silently listening
 * over plain HTTP. The certificate must parse and match the private key.
 */
export function readTlsListenerConfig(env: Readonly<Record<string, string | undefined>>): TlsListenerConfig | null {
  const certPath = env['TRIMMY_TLS_CERT_FILE'];
  const keyPath = env['TRIMMY_TLS_KEY_FILE'];
  if (!certPath && !keyPath) return null;
  if (!certPath || !keyPath) invalid();
  const cert = readPem(certPath);
  const key = readPem(keyPath);
  try {
    const parsedCert = new X509Certificate(cert);
    const parsedKey = createPrivateKey(key);
    if (!parsedCert.checkPrivateKey(parsedKey)) invalid();
  } catch {
    return invalid();
  }
  return Object.freeze({cert, key});
}

/** Builds Fastify's raw server over TLS 1.2+ while keeping the default instance types. */
export function createTlsServerFactory(config: TlsListenerConfig): FastifyServerFactory {
  return handler => createServer({cert: config.cert, key: config.key, minVersion: 'TLSv1.2'}, handler);
}
