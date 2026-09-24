// Keep the real SDK behind the same JS interop boundary as account/privy-sdk-loader.
// Privy 3.42.0 has broken transitive declaration references. No token or provider
// profile is copied to application storage by this adapter.
export async function loadProductAuthSdk() {
  const sdk = await import('@privy-io/react-auth');
  for (const key of ['PrivyProvider', 'usePrivy', 'useLoginWithEmail', 'useLoginWithOAuth']) {
    if (typeof sdk[key] !== 'function') throw new Error('PRODUCT_AUTH_SDK_UNAVAILABLE');
  }
  function callbacks(value) {
    return {
      onComplete(result) {
        if (!result || typeof result.user?.id !== 'string') {
          value.onError('invalid_login_result'); return;
        }
        const method = ['email', 'google', 'twitter'].includes(result.loginMethod) ? result.loginMethod : null;
        value.onComplete({user: {id: result.user.id}, loginMethod: method});
      },
      onError(error) {
        value.onError(error === 'exited_auth_flow' || error === 'user_cancelled' ? 'cancelled' : 'login_failed');
      },
    };
  }
  return {
    PrivyProvider: sdk.PrivyProvider,
    usePrivy() {
      const value = sdk.usePrivy();
      if (!value || typeof value.ready !== 'boolean' || typeof value.authenticated !== 'boolean' ||
          typeof value.getAccessToken !== 'function' || typeof value.logout !== 'function') {
        throw new Error('PRODUCT_AUTH_SDK_UNAVAILABLE');
      }
      return {
        ready: value.ready, authenticated: value.authenticated,
        user: value.user && typeof value.user.id === 'string' ? {id: value.user.id} : null,
        error: Boolean(value.error),
        async getAccessToken() {const token = await value.getAccessToken(); return typeof token === 'string' ? token : null;},
        async logout() {await value.logout();},
      };
    },
    useLoginWithEmail(value) {
      const hook = sdk.useLoginWithEmail(callbacks(value));
      if (typeof hook?.sendCode !== 'function' || typeof hook?.loginWithCode !== 'function') {
        throw new Error('PRODUCT_AUTH_SDK_UNAVAILABLE');
      }
      return {sendCode: async options => {await hook.sendCode(options);}, loginWithCode: async options => {await hook.loginWithCode(options);}};
    },
    useLoginWithOAuth(value) {
      const hook = sdk.useLoginWithOAuth(callbacks(value));
      if (typeof hook?.initOAuth !== 'function') throw new Error('PRODUCT_AUTH_SDK_UNAVAILABLE');
      if (!['initial', 'loading', 'done', 'error'].includes(hook.state?.status)) throw new Error('PRODUCT_AUTH_SDK_UNAVAILABLE');
      return {status: hook.state.status, initOAuth: async options => {await hook.initOAuth(options);}};
    },
  };
}
