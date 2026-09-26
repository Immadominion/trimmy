import {solanaAddress} from '../account/account-data-models.js';
import {validPrivySubject} from '../account/token-binding.js';

export type RecoveryTarget = Readonly<{kind: 'none'} | {kind: 'invalid'} | {kind: 'expected'; address: string}>;
export type RecoveryConfig = Readonly<{kind: 'disabled' | 'invalid'} | {kind: 'enabled'; appId: string; clientId?: string}>;
export type RecoveryIdentity = Readonly<{subject: string; addresses: readonly string[]}>;

export function readRecoveryConfig(env: Record<string, unknown> = import.meta.env ?? {}): RecoveryConfig {
  const appId = env['VITE_PRIVY_APP_ID'], clientId = env['VITE_PRIVY_APP_CLIENT_ID'];
  const valid = (value: unknown): value is string => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.exec(value)?.[0] === value;
  if (!appId && !clientId) return {kind: 'disabled'};
  if (!valid(appId) || clientId !== undefined && clientId !== '' && !valid(clientId)) return {kind: 'invalid'};
  return {kind: 'enabled', appId, ...(valid(clientId) ? {clientId} : {})};
}

/** The app passes a public address only, never a session token or recovery key. */
export function parseRecoveryTarget(fragment: string): RecoveryTarget {
  if (fragment === '' || fragment === '#') return {kind: 'none'};
  if (!/^#address=[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(fragment)) return {kind: 'invalid'};
  try {return {kind: 'expected', address: solanaAddress(fragment.slice(9))};}
  catch {return {kind: 'invalid'};}
}

/** Only linked Privy Solana wallets; external wallets are not exportable here. */
export function recoveryIdentity(user: unknown): RecoveryIdentity | null {
  if (!user || typeof user !== 'object') return null;
  const value = user as {id?: unknown; linkedAccounts?: unknown};
  if (!validPrivySubject(value.id) || !Array.isArray(value.linkedAccounts) || value.linkedAccounts.length > 100) return null;
  const addresses = new Set<string>();
  for (const account of value.linkedAccounts) {
    if (!account || typeof account !== 'object' || account.type !== 'wallet' ||
        account.walletClientType !== 'privy' || account.chainType !== 'solana') continue;
    try {addresses.add(solanaAddress(account.address));} catch {return null;}
  }
  return {subject: value.id, addresses: [...addresses].sort()};
}

export function canExportWallet(identity: RecoveryIdentity | null, target: RecoveryTarget, selected: string): boolean {
  return identity !== null && target.kind !== 'invalid' && identity.addresses.includes(selected) &&
    (target.kind !== 'expected' || target.address === selected);
}
