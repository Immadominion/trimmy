import 'validation.dart';

/// Independent public configuration for stock research; no account or provider
/// credentials. Empty configuration leaves research disabled.
class StockResearchConfig {
  const StockResearchConfig._(this.apiUri);
  final Uri? apiUri;
  bool get enabled => apiUri != null;

  factory StockResearchConfig.fromEnvironment() => StockResearchConfig.parse(
    apiUrl: const String.fromEnvironment('TRIMMY_STOCK_API_URL'),
  );

  factory StockResearchConfig.parse({
    required String apiUrl,
    bool allowLoopbackForTests = false,
  }) {
    if (apiUrl.isEmpty) return const StockResearchConfig._(null);
    final uri = Uri.tryParse(apiUrl);
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(uri?.host);
    if (apiUrl.length > 2048 ||
        RegExp(r'\s').hasMatch(apiUrl) ||
        uri == null ||
        uri.toString() != apiUrl ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535 ||
        (uri.scheme != 'https' &&
            !(allowLoopbackForTests && loopback && uri.scheme == 'http'))) {
      throw const StockResearchException('STOCK_INVALID_CONFIGURATION');
    }
    return StockResearchConfig._(uri.replace(path: ''));
  }
}
