import '../../account/wallet_possession_models.dart';

/// Only the deployed Trimmy recovery origin is accepted. The wallet is a public
/// address in the fragment, never an authentication token or server query.
Uri? walletRecoveryLink(String configuredUrl, String address) {
  if (!isWalletPossessionAddress(address)) return null;
  final uri = Uri.tryParse(configuredUrl);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'web-production-e8138.up.railway.app' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.path != '/wallet-recovery' ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri.replace(fragment: 'address=$address');
}
