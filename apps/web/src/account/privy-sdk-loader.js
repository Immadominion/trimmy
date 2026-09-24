// Privy React 3.42.0/core 0.75.0 ship broken declaration references (including
// PrivyRecoveryInput, CryptoFns, SOLANA_CHAINS and EmbeddedSVG). Keep this one
// interop edge in JS with an explicit local declaration, not an ambient package
// replacement or skipLibCheck. Vite sees the literal import and splits the SDK.
export async function loadPrivySdk() {
  const sdk = await import('@privy-io/react-auth');
  if (typeof sdk.PrivyProvider !== 'function' ||
      typeof sdk.usePrivy !== 'function' || typeof sdk.useLogin !== 'function') {
    throw new Error('PRACTICE_AUTH_SDK_UNAVAILABLE');
  }
  return {
    PrivyProvider: sdk.PrivyProvider,
    usePrivy() {
      const value = sdk.usePrivy();
      if (!value || typeof value.ready !== 'boolean' || typeof value.authenticated !== 'boolean' ||
          typeof value.getAccessToken !== 'function' || typeof value.logout !== 'function') {
        throw new Error('PRACTICE_AUTH_SDK_UNAVAILABLE');
      }
      return {
        ready: value.ready,
        authenticated: value.authenticated,
        user: value.user && typeof value.user.id === 'string' ? { id: value.user.id } : null,
        error: Boolean(value.error),
        async getAccessToken() {
          const token = await value.getAccessToken();
          return typeof token === 'string' ? token : null;
        },
        async logout() { await value.logout(); },
      };
    },
    useLogin(callbacks) {
      const value = sdk.useLogin({
        onComplete(result) {
          if (!result || !result.user || typeof result.user.id !== 'string') {
            callbacks.onError('invalid_login_result');
            return;
          }
          callbacks.onComplete({ user: { id: result.user.id } });
        },
        onError(error) { callbacks.onError(error === 'exited_auth_flow' ? error : 'login_failed'); },
      });
      if (!value || typeof value.login !== 'function') throw new Error('PRACTICE_AUTH_SDK_UNAVAILABLE');
      return { login(options) { value.login(options); } };
    },
  };
}
