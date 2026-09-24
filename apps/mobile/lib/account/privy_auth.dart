import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:privy_flutter/privy_flutter.dart' as privy;

import 'auth.dart';
import 'config.dart';
import 'wallet_possession_models.dart';
import 'wallet_possession_signer.dart';
import 'wallet_setup.dart';
import 'wallet_trade_signer.dart';
import 'onramp_wallet_signer.dart';

/// Only this factory is used by composition. Importing the SDK on the browser
/// does not construct it, subscribe to its channels, or initiate native work.
PracticeAuth createPracticeAuth(PracticeAccountConfig config) {
  if (!config.enabled ||
      kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return const DisabledPracticeAuth();
  }
  return PrivyPracticeAuth(
    appId: config.appId!,
    sdk: NativePrivySdkFacade(config),
    // Debug builds narrate state transitions and local token rejections so a
    // device run can be diagnosed from logcat without exposing a token.
    diagnostics: kDebugMode
        ? (event) => debugPrint('trimmy.account.auth $event')
        : null,
  );
}

class PrivySdkState {
  const PrivySdkState({required this.ready, this.subject});
  final bool ready;
  final String? subject;
}

class PrivySdkLogin {
  const PrivySdkLogin.signedIn(String this.subject) : cancelled = false;
  const PrivySdkLogin.failed() : subject = null, cancelled = false;
  const PrivySdkLogin.cancelled() : subject = null, cancelled = true;
  final String? subject;
  final bool cancelled;
}

/// Small SDK boundary for deterministic tests; production always uses the
/// published SDK below. No fake users, wallet operations or token persistence.
abstract interface class PrivySdkFacade {
  Stream<PrivySdkState> get changes;
  Future<PrivySdkState> readState();
  Future<PrivySdkLogin> loginWithOAuth(PracticeOAuthProvider provider);

  /// True when the provider accepted the request to email a code.
  Future<bool> sendEmailCode(String email);
  Future<PrivySdkLogin> loginWithEmailCode({
    required String email,
    required String code,
  });
  Future<void> logout();
  Future<String?> accessToken(String expectedSubject);
}

/// Optional capability: existing authentication-only facades need no wallet API.
abstract interface class PrivyWalletSigningFacade {
  Future<String> signWalletPossession({
    required String expectedSubject,
    required WalletPossessionChallenge challenge,
  });
}

abstract interface class PrivyWalletSetupFacade {
  Future<String> ensureSolanaWallet({required String expectedSubject});
}

class NativePrivySdkFacade
    implements
        PrivySdkFacade,
        PrivyWalletSigningFacade,
        PrivyWalletSetupFacade,
        OnrampWalletSigner,
        WalletTradeSigner {
  NativePrivySdkFacade(this._config, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final PracticeAccountConfig _config;
  final DateTime Function() _now;
  bool _walletSigningPending = false;
  // A single instance, initialized lazily on native use. The SDK has no public
  // dispose method; app composition must retain this one adapter for its life.
  late final privy.Privy _privy = privy.Privy.init(
    config: privy.PrivyConfig(
      appId: _config.appId!,
      appClientId: _config.appClientId!,
      logLevel: privy.PrivyLogLevel.none,
      disableAutomaticMigration: true,
    ),
  );

  PrivySdkState _map(privy.AuthState state) => PrivySdkState(
    ready: state is! privy.NotReady,
    subject: state is privy.Authenticated ? state.user.id : null,
  );

  @override
  Stream<PrivySdkState> get changes => _privy.authStateStream.map(_map);
  @override
  Future<PrivySdkState> readState() async => _map(await _privy.getAuthState());
  @override
  Future<void> logout() => _privy.logout();

  @override
  Future<PrivySdkLogin> loginWithOAuth(PracticeOAuthProvider provider) async {
    final result = await _privy.oAuth.login(
      provider: switch (provider) {
        PracticeOAuthProvider.x => privy.OAuthProvider.twitter,
        PracticeOAuthProvider.google => privy.OAuthProvider.google,
        PracticeOAuthProvider.apple => privy.OAuthProvider.apple,
      },
      appUrlScheme: PracticeAccountConfig.oauthScheme,
    );
    return switch (result) {
      privy.Success<privy.PrivyUser>(:final value) => PrivySdkLogin.signedIn(
        value.id,
      ),
      privy.Failure<privy.PrivyUser>(:final error) =>
        _isExplicitCancellation(error.message)
            ? const PrivySdkLogin.cancelled()
            : const PrivySdkLogin.failed(),
    };
  }

  @override
  Future<bool> sendEmailCode(String email) async =>
      switch (await _privy.email.sendCode(email)) {
        privy.Success<void>() => true,
        privy.Failure<void>() => false,
      };

  @override
  Future<PrivySdkLogin> loginWithEmailCode({
    required String email,
    required String code,
  }) async => switch (await _privy.email.loginWithCode(
    code: code,
    email: email,
  )) {
    privy.Success<privy.PrivyUser>(:final value) => PrivySdkLogin.signedIn(
      value.id,
    ),
    // A wrong or expired code is a plain failure; there is no browser to cancel.
    privy.Failure<privy.PrivyUser>() => const PrivySdkLogin.failed(),
  };

  @override
  Future<String?> accessToken(String expectedSubject) async {
    final before = await _privy.getAuthState();
    if (before is! privy.Authenticated || before.user.id != expectedSubject) {
      return null;
    }
    // The native implementation refreshes the current session as needed. Its
    // method channel is global, so a captured PrivyUser alone is insufficient.
    final result = await before.user.getAccessToken();
    final after = await _privy.getAuthState();
    if (after is! privy.Authenticated || after.user.id != expectedSubject) {
      return null;
    }
    return switch (result) {
      privy.Success<String>(:final value) => value,
      privy.Failure<String>() => null,
    };
  }

  @override
  Future<String> signReviewedTransaction({
    required String expectedSubject,
    required String wallet,
    required String transaction,
  }) async {
    if (_walletSigningPending) throw const WalletTradeException('WALLET_BUSY');
    final bytes = base64Decode(transaction);
    if (bytes.length < 65 || bytes.length > 1232 || bytes[0] != 1) {
      throw const WalletTradeException('INVALID_TRANSACTION');
    }
    _walletSigningPending = true;
    try {
      final before = _setupUser(await _privy.getAuthState(), expectedSubject);
      if (before.embeddedSolanaWallets.length != 1 ||
          before.embeddedSolanaWallets.single.address != wallet) {
        throw const WalletTradeException('WALLET_CHANGED');
      }
      final selected = before.embeddedSolanaWallets.single;
      final result = await selected.provider.signTransaction(bytes);
      final after = _setupUser(await _privy.getAuthState(), expectedSubject);
      if (after.embeddedSolanaWallets.length != 1 ||
          after.embeddedSolanaWallets.single.address != wallet ||
          after.embeddedSolanaWallets.single.id != selected.id) {
        throw const WalletTradeException('WALLET_CHANGED');
      }
      return switch (result) {
        privy.Success<String>(:final value) => value,
        privy.Failure<String>() => throw const WalletTradeException(
          'SIGNING_CANCELLED',
        ),
      };
    } finally {
      _walletSigningPending = false;
    }
  }

  @override
  Future<String> signOnrampOwnership({
    required String expectedSubject,
    required OnrampWalletChallenge challenge,
  }) async {
    if (_walletSigningPending) throw const WalletTradeException('WALLET_BUSY');
    _walletSigningPending = true;
    try {
      final before = _walletUser(await _privy.getAuthState(), expectedSubject);
      final wallet = _matchingWallet(before, challenge.wallet);
      final result = await wallet.provider.signMessage(
        base64Encode(utf8.encode(challenge.message)),
      );
      final after = _walletUser(await _privy.getAuthState(), expectedSubject);
      final current = _matchingWallet(after, challenge.wallet);
      if (current.id != wallet.id ||
          current.hdWalletIndex != wallet.hdWalletIndex) {
        throw const WalletTradeException('WALLET_CHANGED');
      }
      return switch (result) {
        privy.Success<String>(:final value) => checkedOnrampSignature(value),
        privy.Failure<String>() => throw const WalletTradeException(
          'SIGNING_CANCELLED',
        ),
      };
    } finally {
      _walletSigningPending = false;
    }
  }

  @override
  Future<String> ensureSolanaWallet({required String expectedSubject}) async {
    if (_walletSigningPending) {
      throw const WalletSetupException(WalletSetupFailure.busy);
    }
    _walletSigningPending = true;
    try {
      var user = _setupUser(await _privy.getAuthState(), expectedSubject);
      // Refresh before deciding whether to create. A previous request may have
      // succeeded even when its reply was lost, or another device created it.
      final refreshed = await user.refresh();
      if (refreshed is! privy.Success<void>) {
        throw const WalletSetupException(WalletSetupFailure.unavailable);
      }
      user = _setupUser(await _privy.getAuthState(), expectedSubject);
      if (user.embeddedSolanaWallets.length > 1) {
        throw const WalletSetupException(WalletSetupFailure.multipleWallets);
      }
      String address;
      if (user.embeddedSolanaWallets.isNotEmpty) {
        address = user.embeddedSolanaWallets.single.address;
      } else {
        final result = await user.createSolanaWallet(allowAdditional: false);
        address = switch (result) {
          privy.Success<privy.EmbeddedSolanaWallet>(:final value) =>
            value.address,
          privy.Failure<privy.EmbeddedSolanaWallet>() =>
            throw const WalletSetupException(WalletSetupFailure.unavailable),
        };
      }
      final after = _setupUser(await _privy.getAuthState(), expectedSubject);
      if (after.embeddedSolanaWallets.length != 1 ||
          after.embeddedSolanaWallets.single.address != address ||
          !isWalletPossessionAddress(address)) {
        throw const WalletSetupException(WalletSetupFailure.invalidWallet);
      }
      return address;
    } on WalletSetupException {
      rethrow;
    } catch (_) {
      throw const WalletSetupException(WalletSetupFailure.unavailable);
    } finally {
      _walletSigningPending = false;
    }
  }

  privy.PrivyUser _setupUser(privy.AuthState state, String subject) {
    if (!_validSubject(subject) ||
        state is! privy.Authenticated ||
        state.user.id != subject) {
      throw const WalletSetupException(WalletSetupFailure.accountChanged);
    }
    return state.user;
  }

  /// The same lazy SDK instance used for sign-in supplies the existing wallet.
  /// Flutter 0.10.2 passes base64 straight to the native Solana provider and
  /// returns a base64 signature. See Privy's Flutter quickstart, Solana section:
  /// https://docs.privy.io/basics/flutter/quickstart
  @override
  Future<String> signWalletPossession({
    required String expectedSubject,
    required WalletPossessionChallenge challenge,
  }) async {
    if (_walletSigningPending) {
      throw const WalletPossessionException(WalletPossessionFailure.busy);
    }
    _walletSigningPending = true;
    try {
      if (!_validSubject(expectedSubject)) {
        throw const WalletPossessionException(
          WalletPossessionFailure.unauthenticated,
        );
      }
      _requireLiveChallenge(challenge, _now());
      final before = _walletUser(await _privy.getAuthState(), expectedSubject);
      final wallet = _matchingWallet(before, challenge.walletAddress);
      _requireLiveChallenge(challenge, _now());
      // The challenge has a private constructor and a strict fixed-message
      // parser. No caller-supplied arbitrary text can enter this operation.
      final result = await wallet.provider.signMessage(
        base64.encode(utf8.encode(challenge.message)),
      );
      final after = _walletUser(await _privy.getAuthState(), expectedSubject);
      final currentWallet = _matchingWallet(after, challenge.walletAddress);
      if (currentWallet.id != wallet.id ||
          currentWallet.hdWalletIndex != wallet.hdWalletIndex) {
        throw const WalletPossessionException(
          WalletPossessionFailure.walletMismatch,
        );
      }
      _requireLiveChallenge(challenge, _now());
      return switch (result) {
        privy.Success<String>(:final value) =>
          walletPossessionSignatureFromBase64(value),
        privy.Failure<String>(:final error) => throw WalletPossessionException(
          _isExplicitCancellation(error.message)
              ? WalletPossessionFailure.cancelled
              : WalletPossessionFailure.signatureRejected,
        ),
      };
    } on WalletPossessionException {
      rethrow;
    } catch (_) {
      throw const WalletPossessionException(
        WalletPossessionFailure.unavailable,
      );
    } finally {
      // A caller's timeout does not cancel the native request. Keep this lock
      // until that request actually settles, including all identity checks.
      _walletSigningPending = false;
    }
  }

  privy.PrivyUser _walletUser(privy.AuthState state, String subject) {
    if (state is! privy.Authenticated) {
      throw const WalletPossessionException(
        WalletPossessionFailure.unauthenticated,
      );
    }
    if (state.user.id != subject) {
      throw const WalletPossessionException(
        WalletPossessionFailure.accountMismatch,
      );
    }
    return state.user;
  }

  privy.EmbeddedSolanaWallet _matchingWallet(
    privy.PrivyUser user,
    String address,
  ) {
    final wallets = user.embeddedSolanaWallets;
    if (wallets.isEmpty) {
      throw const WalletPossessionException(
        WalletPossessionFailure.walletMissing,
      );
    }
    // Match the API's account model: any second embedded Solana wallet makes
    // selection ambiguous, even when only one address matches the challenge.
    if (wallets.length != 1) {
      throw const WalletPossessionException(
        WalletPossessionFailure.walletAmbiguous,
      );
    }
    if (wallets.single.address != address) {
      throw const WalletPossessionException(
        WalletPossessionFailure.walletMismatch,
      );
    }
    return wallets.single;
  }

  // Flutter 0.10.2 discards the native OAuth error type/code and exposes only a
  // localized message. Recognize explicit cancellation wording conservatively;
  // unknown/localized cancellation is a sanitized failure, never success.
  // Android privy-core 0.15.0 reports "OAuth flow cancelled by user" when the
  // redirect activity finishes without a code and "Chrome tab closed by user
  // without completing OAuth" when the custom tab is dismissed. iOS surfaces
  // ASWebAuthenticationSession's canceledLogin (error code 1) description.
  bool _isExplicitCancellation(String message) {
    final text = message.trim().toLowerCase();
    return const {
          'cancelled',
          'canceled',
          'user cancelled',
          'user canceled',
          'user cancelled the login flow',
          'user canceled the login flow',
          'the user canceled the sign-in flow.',
          'the user cancelled the sign-in flow.',
          'oauth flow cancelled by user',
          'chrome tab closed by user without completing oauth',
        }.contains(text) ||
        text.contains('webauthenticationsession error 1') ||
        text.contains('canceledlogin');
  }
}

class PrivyPracticeAuth
    implements
        PracticeAuth,
        WalletPossessionSigner,
        WalletSetup,
        OnrampWalletSigner,
        WalletTradeSigner {
  PrivyPracticeAuth({
    required this.appId,
    required this._sdk,
    DateTime Function()? now,
    this._diagnostics,
  }) : _now = now ?? DateTime.now;

  /// Device clocks drift. A token issued a moment ago by the provider must
  /// not be rejected locally because the phone runs a second behind, and a
  /// token near expiry is refreshed by the SDK, not judged here. The API is
  /// the verifier; this local check only binds the token to the subject.
  static const clockSkewTolerance = Duration(minutes: 5);

  final String appId;
  final PrivySdkFacade _sdk;
  final DateTime Function() _now;
  // Secret-free event sink for device diagnostics (never a token or address).
  final void Function(String event)? _diagnostics;
  final _changes = StreamController<PracticeAuthState>.broadcast(sync: true);
  StreamSubscription<PrivySdkState>? _subscription;
  PracticeAuthState _state = const PracticeAuthState.initializing();
  Future<void>? _initialization;
  Future<void>? _logout;
  bool _closed = false;
  bool _loginPending = false;
  bool _walletSigningPending = false;
  bool _canRestore = true;
  int _generation = 0;
  int _eventVersion = 0;

  @override
  Future<String> signOnrampOwnership({
    required String expectedSubject,
    required OnrampWalletChallenge challenge,
  }) async {
    final generation = _generation;
    _requireSigningSubject(generation, expectedSubject);
    final sdk = _sdk;
    if (_walletSigningPending ||
        _loginPending ||
        _logout != null ||
        sdk is! OnrampWalletSigner) {
      throw const WalletTradeException('WALLET_BUSY');
    }
    _walletSigningPending = true;
    try {
      final before = await _sdk.readState();
      _requireSigningSubject(generation, expectedSubject);
      if (!before.ready || before.subject != expectedSubject) {
        throw const WalletTradeException('ACCOUNT_CHANGED');
      }
      final signature = await (sdk as OnrampWalletSigner).signOnrampOwnership(
        expectedSubject: expectedSubject,
        challenge: challenge,
      );
      final after = await _sdk.readState();
      _requireSigningSubject(generation, expectedSubject);
      if (!after.ready || after.subject != expectedSubject) {
        throw const WalletTradeException('ACCOUNT_CHANGED');
      }
      return checkedOnrampSignature(signature);
    } finally {
      _walletSigningPending = false;
    }
  }

  @override
  PracticeAuthState get state => _state;
  @override
  Stream<PracticeAuthState> get changes => _changes.stream;

  bool _current(int generation) => !_closed && generation == _generation;
  bool _bound(int generation, String subject) =>
      _current(generation) &&
      _state.status == PracticeAuthStatus.signedIn &&
      _state.subject == subject;

  void _set(PracticeAuthState next) {
    if (_closed || _state == next) return;
    if (_state.subject != next.subject) _generation++;
    _state = next;
    _diag('state ${next.status.name} subject=${next.subject != null}');
    _changes.add(next);
  }

  void _diag(String event) {
    final sink = _diagnostics;
    if (sink == null) return;
    try {
      sink(event);
    } catch (_) {
      // Diagnostics never interfere with the account lifecycle.
    }
  }

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (_closed) return;
    final generation = _generation;
    try {
      _subscription = _sdk.changes.listen(
        (_) => _refreshFromEvent(),
        onError: (Object error, StackTrace _) {
          _diag('state stream error ${error.runtimeType}');
          if (!_closed) {
            _generation++;
            _canRestore = false;
            _set(const PracticeAuthState.failed());
          }
        },
      );
      final snapshot = await _sdk.readState();
      if (_current(generation)) _acceptSnapshot(snapshot);
    } catch (error) {
      _diag('initialize failed ${error.runtimeType}');
      if (_current(generation)) {
        _canRestore = false;
        _set(const PracticeAuthState.failed());
      }
    }
  }

  void _acceptSnapshot(PrivySdkState snapshot) {
    if (!snapshot.ready) return;
    final subject = snapshot.subject;
    if (subject == null) {
      _canRestore = false;
      _set(const PracticeAuthState.signedOut());
    } else if (!_validSubject(subject)) {
      _canRestore = false;
      _set(const PracticeAuthState.failed());
    } else if (_canRestore) {
      _canRestore = false;
      _set(PracticeAuthState.signedIn(subject));
    } else if (_state.subject != subject &&
        _state.status == PracticeAuthStatus.signedIn) {
      // A spontaneous different user cannot silently bind a new account. It
      // invalidates this session; only a fresh explicit login may accept a DID.
      _set(const PracticeAuthState.signedOut());
    }
  }

  Future<void> _refreshFromEvent() async {
    if (_closed || _loginPending || _logout != null) return;
    final generation = _generation;
    final event = ++_eventVersion;
    try {
      // Treat stream events as hints: a queued old event must not overwrite the
      // current authoritative native state with its historical payload.
      final snapshot = await _sdk.readState();
      if (_current(generation) && event == _eventVersion) {
        _acceptSnapshot(snapshot);
      }
    } catch (error) {
      _diag('state refresh failed ${error.runtimeType}');
      if (_current(generation) && event == _eventVersion) {
        _canRestore = false;
        _set(const PracticeAuthState.failed());
      }
    }
  }

  @override
  Future<PracticeSignInResult> signInWithOAuth(
    PracticeOAuthProvider provider,
  ) => _signIn(() => _sdk.loginWithOAuth(provider));

  @override
  Future<PracticeEmailCodeResult> sendEmailCode(String email) async {
    await initialize();
    if (_closed ||
        _loginPending ||
        _logout != null ||
        _state.status == PracticeAuthStatus.signedIn) {
      return PracticeEmailCodeResult.unavailable;
    }
    final normalized = normalizePracticeEmail(email);
    if (normalized == null) return PracticeEmailCodeResult.invalidEmail;
    try {
      final sent = await _sdk.sendEmailCode(normalized);
      _diag('email code ${sent ? 'sent' : 'refused'}');
      return sent
          ? PracticeEmailCodeResult.sent
          : PracticeEmailCodeResult.failed;
    } catch (error) {
      _diag('email code failed ${error.runtimeType}');
      return PracticeEmailCodeResult.failed;
    }
  }

  @override
  Future<PracticeSignInResult> signInWithEmailCode({
    required String email,
    required String code,
  }) {
    final normalizedEmail = normalizePracticeEmail(email);
    final normalizedCode = normalizePracticeEmailCode(code);
    if (normalizedEmail == null || normalizedCode == null) {
      return Future.value(PracticeSignInResult.failed);
    }
    return _signIn(
      () =>
          _sdk.loginWithEmailCode(email: normalizedEmail, code: normalizedCode),
    );
  }

  /// One explicit attempt at a time. A late completion after logout, disposal
  /// or a different native user cannot bind this session.
  Future<PracticeSignInResult> _signIn(
    Future<PrivySdkLogin> Function() attempt,
  ) async {
    await initialize();
    if (_closed || _loginPending || _logout != null) {
      return PracticeSignInResult.unavailable;
    }
    if (_state.status == PracticeAuthStatus.signedIn) {
      return PracticeSignInResult.signedIn;
    }
    _loginPending = true;
    _canRestore = false;
    final generation = ++_generation;
    _set(const PracticeAuthState.signedOut());
    try {
      final result = await attempt();
      if (!_current(generation)) return PracticeSignInResult.sessionChanged;
      if (result.cancelled) {
        _diag('sign-in cancelled');
        return PracticeSignInResult.cancelled;
      }
      final subject = result.subject;
      if (subject == null || !_validSubject(subject)) {
        _diag('sign-in failed subject=${subject != null}');
        return PracticeSignInResult.failed;
      }
      final actual = await _sdk.readState();
      if (!_current(generation) || !actual.ready || actual.subject != subject) {
        _diag('sign-in session changed');
        return PracticeSignInResult.sessionChanged;
      }
      _set(PracticeAuthState.signedIn(subject));
      return PracticeSignInResult.signedIn;
    } catch (error) {
      _diag('sign-in threw ${error.runtimeType}');
      return _current(generation)
          ? PracticeSignInResult.failed
          : PracticeSignInResult.sessionChanged;
    } finally {
      _loginPending = false;
    }
  }

  @override
  Future<void> signOut() {
    if (_closed) return Future.value();
    _generation++;
    _canRestore = false;
    _set(const PracticeAuthState.signedOut());
    return _logout ??= _nativeLogout().whenComplete(() => _logout = null);
  }

  Future<void> _nativeLogout() async {
    try {
      // No native initialization just to log out an unused/disabled adapter.
      if (_initialization != null) await _sdk.logout();
    } catch (_) {
      throw const PracticeAuthException('PRACTICE_SIGN_OUT_FAILED');
    }
  }

  @override
  Future<String?> accessToken({required String expectedSubject}) async {
    final generation = _generation;
    if (!_validSubject(expectedSubject) ||
        !_bound(generation, expectedSubject)) {
      return null;
    }
    try {
      final before = await _sdk.readState();
      if (!_bound(generation, expectedSubject) ||
          !before.ready ||
          before.subject != expectedSubject) {
        _diag('token skipped: native state changed');
        return null;
      }
      final token = await _sdk.accessToken(expectedSubject);
      if (!_bound(generation, expectedSubject)) return null;
      if (token == null) {
        _diag('token unavailable from sdk');
        return null;
      }
      final rejection = _tokenRejection(token, expectedSubject);
      if (rejection != null) {
        _diag('token rejected locally: $rejection');
        return null;
      }
      final after = await _sdk.readState();
      return _bound(generation, expectedSubject) &&
              after.ready &&
              after.subject == expectedSubject
          ? token
          : null;
    } catch (error) {
      _diag('token read threw ${error.runtimeType}');
      return null;
    }
  }

  @override
  Future<String> signReviewedTransaction({
    required String expectedSubject,
    required String wallet,
    required String transaction,
  }) async {
    final sdk = _sdk, generation = _generation;
    if (!_bound(generation, expectedSubject) ||
        sdk is! WalletTradeSigner ||
        _walletSigningPending ||
        _loginPending ||
        _logout != null) {
      throw const WalletTradeException('WALLET_UNAVAILABLE');
    }
    _walletSigningPending = true;
    try {
      final before = await _sdk.readState();
      if (!_bound(generation, expectedSubject) ||
          before.subject != expectedSubject) {
        throw const WalletTradeException('ACCOUNT_CHANGED');
      }
      final signed = await (sdk as WalletTradeSigner).signReviewedTransaction(
        expectedSubject: expectedSubject,
        wallet: wallet,
        transaction: transaction,
      );
      if (!_bound(generation, expectedSubject)) {
        throw const WalletTradeException('ACCOUNT_CHANGED');
      }
      return signed;
    } finally {
      _walletSigningPending = false;
    }
  }

  @override
  Future<String> ensureSolanaWallet({required String expectedSubject}) async {
    final generation = _generation;
    void requireCurrent() {
      if (!_bound(generation, expectedSubject)) {
        throw const WalletSetupException(WalletSetupFailure.accountChanged);
      }
    }

    requireCurrent();
    final sdk = _sdk;
    if (sdk is! PrivyWalletSetupFacade) {
      throw const WalletSetupException(WalletSetupFailure.unavailable);
    }
    if (_walletSigningPending || _loginPending || _logout != null) {
      throw const WalletSetupException(WalletSetupFailure.busy);
    }
    _walletSigningPending = true;
    try {
      final before = await _sdk.readState();
      requireCurrent();
      if (!before.ready || before.subject != expectedSubject) {
        throw const WalletSetupException(WalletSetupFailure.accountChanged);
      }
      final address = await (sdk as PrivyWalletSetupFacade).ensureSolanaWallet(
        expectedSubject: expectedSubject,
      );
      requireCurrent();
      final after = await _sdk.readState();
      requireCurrent();
      if (!after.ready || after.subject != expectedSubject) {
        throw const WalletSetupException(WalletSetupFailure.accountChanged);
      }
      if (!isWalletPossessionAddress(address)) {
        throw const WalletSetupException(WalletSetupFailure.invalidWallet);
      }
      return address;
    } on WalletSetupException {
      rethrow;
    } catch (_) {
      throw const WalletSetupException(WalletSetupFailure.unavailable);
    } finally {
      // Keep the lock until native work settles, including caller timeouts.
      _walletSigningPending = false;
    }
  }

  @override
  Future<String> sign({
    required String expectedSubject,
    required WalletPossessionChallenge challenge,
  }) async {
    final generation = _generation;
    _requireSigningSubject(generation, expectedSubject);
    if (_walletSigningPending || _loginPending || _logout != null) {
      throw const WalletPossessionException(WalletPossessionFailure.busy);
    }
    final sdk = _sdk;
    if (sdk is! PrivyWalletSigningFacade) {
      throw const WalletPossessionException(
        WalletPossessionFailure.notConfigured,
      );
    }
    _requireLiveChallenge(challenge, _now());
    _walletSigningPending = true;
    try {
      final before = await _sdk.readState();
      _requireSigningSubject(generation, expectedSubject);
      if (!before.ready || before.subject != expectedSubject) {
        throw const WalletPossessionException(
          WalletPossessionFailure.accountMismatch,
        );
      }
      _requireLiveChallenge(challenge, _now());
      final signature = await (sdk as PrivyWalletSigningFacade)
          .signWalletPossession(
            expectedSubject: expectedSubject,
            challenge: challenge,
          );
      _requireSigningSubject(generation, expectedSubject);
      final after = await _sdk.readState();
      _requireSigningSubject(generation, expectedSubject);
      if (!after.ready || after.subject != expectedSubject) {
        throw const WalletPossessionException(
          WalletPossessionFailure.accountMismatch,
        );
      }
      _requireLiveChallenge(challenge, _now());
      if (!isWalletPossessionSignature(signature)) {
        throw const WalletPossessionException(
          WalletPossessionFailure.invalidSignature,
        );
      }
      return signature;
    } on WalletPossessionException {
      rethrow;
    } catch (_) {
      throw const WalletPossessionException(
        WalletPossessionFailure.unavailable,
      );
    } finally {
      _walletSigningPending = false;
    }
  }

  void _requireSigningSubject(int generation, String subject) {
    if (_closed) {
      throw const WalletPossessionException(WalletPossessionFailure.closed);
    }
    if (!_validSubject(subject) ||
        _state.status != PracticeAuthStatus.signedIn) {
      throw const WalletPossessionException(
        WalletPossessionFailure.unauthenticated,
      );
    }
    if (!_bound(generation, subject)) {
      throw const WalletPossessionException(
        WalletPossessionFailure.accountMismatch,
      );
    }
  }

  /// Defensive local binding only, NOT authentication. The API verifies JWT
  /// cryptography. A captured PrivyUser.getAccessToken uses a global native
  /// channel and can otherwise return the next user's token during a switch.
  /// Returns a secret-free reason when the token cannot bind, else null.
  String? _tokenRejection(String token, String subject) {
    if (token.length > 8185) return 'length';
    final compact = RegExp(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');
    if (compact.stringMatch(token) != token) return 'shape';
    try {
      final parts = token.split('.');
      final header = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
      );
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (header is! Map<String, dynamic> || claims is! Map<String, dynamic>) {
        return 'encoding';
      }
      if (header['alg'] != 'ES256' || header['typ'] != 'JWT') return 'header';
      if (claims['sub'] != subject) return 'subject';
      if (claims['aud'] != appId) return 'audience';
      if (claims['iss'] != 'privy.io') return 'issuer';
      final now = _now().millisecondsSinceEpoch ~/ 1000;
      final skew = clockSkewTolerance.inSeconds;
      final exp = claims['exp'];
      final iat = claims['iat'];
      final sid = claims['sid'];
      if (exp is! int || iat is! int || iat <= 0 || exp <= iat) return 'times';
      if (iat > now + skew) return 'issued in the future';
      if (exp <= now - skew) return 'expired';
      if (sid is! String ||
          RegExp(r'^[A-Za-z0-9_-]{1,256}$').stringMatch(sid) != sid) {
        return 'session id';
      }
      return null;
    } catch (_) {
      return 'unreadable';
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _state = const PracticeAuthState.signedOut();
    await _subscription?.cancel();
    await _changes.close();
  }
}

bool _validSubject(String subject) =>
    RegExp(r'^did:privy:[A-Za-z0-9]{1,128}$').stringMatch(subject) == subject;

void _requireLiveChallenge(WalletPossessionChallenge challenge, DateTime now) {
  if (challenge.isExpired(now)) {
    throw const WalletPossessionException(
      WalletPossessionFailure.challengeExpired,
    );
  }
}
