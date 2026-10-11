/** Independent incoming-wallet rollout. Values never appear in thrown errors. */
export function readWalletFundingConfig(env: Readonly<Record<string, string | undefined>>): Readonly<{enabled: boolean; reviewKey?: Buffer}> {
  const flag = env['TRIMMY_MWA_FUNDING'];
  if (flag !== undefined && flag !== '' && flag !== 'disabled' && flag !== 'enabled') {
    throw new Error('TRIMMY_MWA_FUNDING must be disabled or enabled.');
  }
  const enabled = flag === 'enabled';
  const rawKey = env['TRIMMY_WALLET_REVIEW_KEY'];
  if (rawKey !== undefined && rawKey !== '' && !/^[a-fA-F0-9]{64}$/.test(rawKey)) {
    throw new Error('TRIMMY_WALLET_REVIEW_KEY must encode exactly 32 bytes as hex.');
  }
  if (enabled && !rawKey) throw new Error('Incoming wallet funding requires TRIMMY_WALLET_REVIEW_KEY.');
  return Object.freeze({enabled, ...(rawKey ? {reviewKey: Buffer.from(rawKey, 'hex')} : {})});
}
