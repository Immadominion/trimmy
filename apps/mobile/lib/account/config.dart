import 'package:flutter/foundation.dart';

/// Public build configuration. Never place an app secret or signing key here.
class PracticeAccountConfig {
  const PracticeAccountConfig._({
    required this.enabled,
    this.appId,
    this.appClientId,
    this.apiUri,
  });

  static const oauthScheme = 'com.trimmy.trimmy.privy';
  final bool enabled;
  final String? appId;
  final String? appClientId;
  final Uri? apiUri;

  factory PracticeAccountConfig.fromEnvironment() =>
      PracticeAccountConfig.parse(
        appId: const String.fromEnvironment('PRIVY_APP_ID'),
        appClientId: const String.fromEnvironment('PRIVY_APP_CLIENT_ID'),
        apiUrl: const String.fromEnvironment('TRIMMY_API_URL'),
        nativeSupported:
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS),
      );

  factory PracticeAccountConfig.parse({
    required String appId,
    required String appClientId,
    required String apiUrl,
    required bool nativeSupported,
    bool allowLoopbackForTests = false,
  }) {
    if (appId.isEmpty && appClientId.isEmpty && apiUrl.isEmpty) {
      return const PracticeAccountConfig._(enabled: false);
    }
    final idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
    bool validId(String value) => idPattern.stringMatch(value) == value;
    if (!validId(appId) || !validId(appClientId) || apiUrl.isEmpty) {
      throw const PracticeConfigurationException();
    }
    final uri = Uri.tryParse(apiUrl);
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(uri?.host.toLowerCase());
    if (apiUrl.length > 2048 ||
        RegExp(r'\s').hasMatch(apiUrl) ||
        uri == null ||
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
      throw const PracticeConfigurationException();
    }
    return PracticeAccountConfig._(
      enabled: nativeSupported,
      appId: appId,
      appClientId: appClientId,
      apiUri: uri,
    );
  }
}

class PracticeConfigurationException implements Exception {
  const PracticeConfigurationException();
  @override
  String toString() =>
      'PracticeConfigurationException(PRACTICE_CONFIGURATION_INVALID)';
}
