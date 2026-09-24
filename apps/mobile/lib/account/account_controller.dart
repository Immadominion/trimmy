import 'wallet_trade_signer.dart';
import 'onramp_wallet_signer.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../design_study/progress.dart';
import '../practice_sync/account_progress_session.dart';
import '../practice_sync/coordinator.dart';
import '../practice_sync/durable_state.dart';
import '../practice_sync/http_transport.dart';
import '../practice_sync/protocol.dart';
import '../markets/followed_stocks.dart';
import '../markets/followed_stocks_controller.dart';
import '../social/http_invitations_client.dart';
import '../social/invitation_create_store.dart';
import '../social/invitations_controller.dart';
import '../social/http_relationships_client.dart';
import '../social/relationship_mutation_store.dart';
import '../social/relationships_controller.dart';
import 'account_closure_client.dart';
import 'account_portfolio.dart';
import 'auth.dart';
import 'http_account_data_client.dart';
import 'guest_session.dart';
import 'server_account_binding.dart';
import 'wallet_possession_client.dart';
import 'wallet_possession_controller.dart';
import 'wallet_possession_signer.dart';
import 'wallet_setup.dart';

enum AccountPhase { initializing, guest, connecting, active, error }

enum AccountSyncStatus {
  local,
  syncing,
  saved,
  offline,
  conflict,
  protected,
  loginRequired,
}

typedef PracticeTimerFactory = Timer Function(Duration, void Function());
typedef PracticeAccountSessionFactory =
    Future<AccountProgressSession> Function(String, PracticeTransport);

/// Owns one mounted account. Authentication subjects and server account UUIDs
/// remain separate, and every asynchronous callback is tied to its generation.
class AccountController extends ChangeNotifier {
  AccountController({
    required this._auth,
    required this.guestRepository,
    required this._store,
    required this._httpClient,
    required this._baseUri,
    Duration debounce = const Duration(milliseconds: 350),
    List<Duration> retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 4),
    ],
    PracticeTimerFactory? timerFactory,
    this._sessionFactory,
    String? bindingAppId,
    WalletPossessionSigner? walletSigner,
    WalletSetup? walletSetup,
    this.guestSessions,
    InvitationCreateMutationStore? invitationCreateMutationStore,
    RelationshipMutationStore? relationshipMutationStore,
    bool allowLoopbackForTests = false,
  }) : _repository = guestRepository,
       _debounce = debounce,
       _retryDelays = List.unmodifiable(retryDelays),
       _timerFactory = timerFactory ?? Timer.new,
       _walletSigner =
           walletSigner ??
           (_auth is WalletPossessionSigner
               ? _auth as WalletPossessionSigner
               : null),
       _walletSetup =
           walletSetup ?? (_auth is WalletSetup ? _auth as WalletSetup : null),
       _allowLoopback = allowLoopbackForTests {
    _invitationCreateMutationStore =
        invitationCreateMutationStore ?? MemoryInvitationCreateMutationStore();
    _relationshipMutationStore =
        relationshipMutationStore ?? MemoryRelationshipMutationStore();
    if (debounce.isNegative || retryDelays.any((delay) => delay.isNegative)) {
      throw ArgumentError('Sync delays must be non-negative.');
    }
    _bindings = bindingAppId == null
        ? null
        : ServerAccountBindingStore(
            store: _store,
            apiUri: _baseUri,
            appId: bindingAppId,
            allowLoopbackForTests: _allowLoopback,
          );
    _watchRepository();
  }

  final PracticeAuth _auth;
  final OfficeProgressRepository guestRepository;
  final PracticeSyncStore _store;
  final http.Client _httpClient;
  final Uri _baseUri;
  final Duration _debounce;
  final List<Duration> _retryDelays;
  final PracticeTimerFactory _timerFactory;
  final PracticeAccountSessionFactory? _sessionFactory;
  final bool _allowLoopback;
  final WalletPossessionSigner? _walletSigner;
  final WalletSetup? _walletSetup;
  final GuestSessionPort? guestSessions;
  late final InvitationCreateMutationStore _invitationCreateMutationStore;
  late final RelationshipMutationStore _relationshipMutationStore;
  bool _walletSetupBusy = false;
  late final ServerAccountBindingStore? _bindings;
  bool _serverVerified = false;
  OfficeProgressRepository _repository;
  AccountProgressSession? _session;
  AccountPortfolioRepository? _portfolioRepository;
  VoidCallback? _portfolioListener;
  StreamSubscription<PracticeAuthState>? _authSubscription;
  final _retiring = <String, Future<void>>{};
  final _opening = <String, Future<void>>{};
  Future<void>? _initializing, _connection, _syncing;
  Timer? _timer;
  String? _subject, _accountId, _errorCode;
  AccountPhase _phase = AccountPhase.initializing;
  AccountSyncStatus _syncStatus = AccountSyncStatus.local;
  int _generation = 0, _intent = 0, _navigationEpoch = 0, _retry = 0;
  int _observedLocalRevision = 0;
  String _observedProgress = '';
  bool _disposed = false, _foreground = true, _syncAgain = false;
  bool _networkAvailable = true;
  bool _signedOutExplicitly = false;
  bool _hasPreservedGuestDesk = false;
  bool _hasExpiredGuestDesk = false;
  AccountClosureOutcome? _lastClosure;
  InvitationsController? _invitations;
  VoidCallback? _invitationsListener;
  RelationshipsController? _relationships;
  VoidCallback? _relationshipsListener;
  FollowedStocksController? _followedStocks;
  VoidCallback? _followedStocksListener;
  WalletPossessionController? _walletPossession;
  VoidCallback? _walletPossessionListener;

  OfficeProgressRepository get repository => _repository;
  AccountPortfolioRepository? get portfolioRepository => _portfolioRepository;

  /// Present only while a verified account is mounted.
  InvitationsController? get invitationsController => _invitations;

  /// Present only while one verified saved account is mounted.
  RelationshipsController? get relationshipsController => _relationships;

  /// The verified account's real followed list, or null for a guest.
  FollowedStocksController? get followedStocksController => _followedStocks;
  WalletPossessionController? get walletPossessionController =>
      _walletPossession;
  AccountPortfolioState? get portfolioState => _portfolioRepository?.state;
  String? get accountId => _accountId;
  AccountPhase get phase => _phase;
  AccountSyncStatus get syncStatus => _syncStatus;
  String? get errorCode => _errorCode;
  int get navigationEpoch => _navigationEpoch;
  bool get isForeground => _foreground;
  bool get isServerVerified => _serverVerified;

  /// True when sign-in opened an existing verified account without claiming
  /// the guest desk. The guest credential remains available after sign-out.
  bool get hasPreservedGuestDesk => _hasPreservedGuestDesk;
  bool get hasExpiredGuestDesk =>
      _hasPreservedGuestDesk && _hasExpiredGuestDesk;
  bool get canStartNewGuestDesk =>
      !_disposed &&
      _phase == AccountPhase.guest &&
      guestSessions is GuestSessionRecoveryPort;
  bool get canSignIn => _auth.state.status != PracticeAuthStatus.disabled;
  bool get walletSetupBusy => _walletSetupBusy;
  bool get canSetUpWallet =>
      !_disposed &&
      _foreground &&
      _networkAvailable &&
      _serverVerified &&
      _walletSetup != null &&
      !_walletSetupBusy;
  OfficeProgress? get conflictingProgress =>
      _session?.coordinator.state?.conflict?.progress;

  /// Closing needs a verified account, because the server closes the account
  /// the token proves rather than one the client names.
  bool get canCloseAccount =>
      !_disposed && _serverVerified && _accountId != null && _session != null;

  /// Set after a successful closure so the interface can say what happened
  /// before the session is gone.
  AccountClosureOutcome? get lastClosure => _lastClosure;

  bool get canImportGuestProgress =>
      _session != null &&
      guestRepository.loadIssue == null &&
      _session!.coordinator.state!.base != null &&
      canonicalProgressContent(
            _session!.coordinator.state!.base!.progress ??
                OfficeProgress.empty(),
          ) ==
          canonicalProgressContent(OfficeProgress.empty()) &&
      _session!.coordinator.state!.conflict == null &&
      _session!.coordinator.state!.pending == null &&
      canonicalProgressContent(repository.state) ==
          canonicalProgressContent(OfficeProgress.empty()) &&
      canonicalProgressContent(guestRepository.state) !=
          canonicalProgressContent(OfficeProgress.empty());

  /// Returns a fresh bearer bound to the currently verified account.
  ///
  /// Product API clients use this boundary instead of retaining credentials.
  /// The account identity is checked before and after the asynchronous provider
  /// read so a sign-out or account switch cannot dispatch a late request.
  Future<PracticeAccessToken> freshAccessToken() async {
    final subject = _subject;
    final account = _accountId;
    final generation = _generation;
    if (subject == null ||
        account == null ||
        !_portfolioIdentityCurrent(subject, account, generation)) {
      throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
    }
    final token = await _token(subject, generation);
    if (!_portfolioIdentityCurrent(subject, account, generation)) {
      throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
    }
    return PracticeAccessToken(accountId: account, token: token);
  }

  Future<String> signReviewedStockTransaction({
    required String wallet,
    required String transaction,
    required DateTime expiresAt,
  }) async {
    final subject = _subject,
        account = _accountId,
        generation = _generation,
        signer = _auth;
    if (subject == null ||
        account == null ||
        signer is! WalletTradeSigner ||
        !_portfolioIdentityCurrent(subject, account, generation) ||
        !DateTime.now().toUtc().isBefore(expiresAt)) {
      throw const WalletTradeException('ACCOUNT_CHANGED');
    }
    await freshAccessToken();
    if (!_portfolioIdentityCurrent(subject, account, generation)) {
      throw const WalletTradeException('ACCOUNT_CHANGED');
    }
    final signed = await (signer as WalletTradeSigner)
        .signReviewedTransaction(
          expectedSubject: subject,
          wallet: wallet,
          transaction: transaction,
        )
        .timeout(const Duration(seconds: 45));
    if (!_portfolioIdentityCurrent(subject, account, generation) ||
        !DateTime.now().toUtc().isBefore(expiresAt)) {
      throw const WalletTradeException('QUOTE_EXPIRED');
    }
    return signed;
  }

  Future<String> signOnrampOwnership(OnrampWalletChallenge challenge) async {
    final subject = _subject,
        account = _accountId,
        generation = _generation,
        signer = _auth;
    if (subject == null ||
        account == null ||
        signer is! OnrampWalletSigner ||
        !_portfolioIdentityCurrent(subject, account, generation) ||
        portfolioState?.context?.embeddedSolanaWallet.address !=
            challenge.wallet) {
      throw const WalletTradeException('ACCOUNT_CHANGED');
    }
    await freshAccessToken();
    if (!_portfolioIdentityCurrent(subject, account, generation)) {
      throw const WalletTradeException('ACCOUNT_CHANGED');
    }
    final signature = await (signer as OnrampWalletSigner).signOnrampOwnership(
      expectedSubject: subject,
      challenge: challenge,
    );
    if (!_portfolioIdentityCurrent(subject, account, generation)) {
      throw const WalletTradeException('ACCOUNT_CHANGED');
    }
    return checkedOnrampSignature(signature);
  }

  /// Paper orders use the saved account bearer after claim, or the revocable
  /// guest credential before sign-in. No wallet authority crosses this port.
  Future<PaperAuthorization> paperAuthorization() async {
    if (_phase == AccountPhase.active) {
      if (!_serverVerified || _accountId == null) {
        throw const GuestSessionException(GuestSessionFailure.unavailable);
      }
      return PrivyPaperAuthorization((await freshAccessToken()).token);
    }
    if (_phase == AccountPhase.initializing ||
        _phase == AccountPhase.connecting) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    final guests = guestSessions;
    if (guests == null) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    return guests.paperAuthorization();
  }

  /// Identity key for paper UI state, with no bearer or guest credential.
  ///
  /// The unresolved phases refuse access so a returning signed-in installation
  /// cannot open a guest desk before Privy restoration finishes.
  Future<String> paperPrincipalKey() async {
    if (_disposed) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    final generation = _generation;
    if (_phase == AccountPhase.active) {
      final account = _accountId;
      if (!_serverVerified || account == null) {
        throw const GuestSessionException(GuestSessionFailure.unavailable);
      }
      return account;
    }
    if (_phase != AccountPhase.guest) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    final guests = guestSessions;
    if (guests == null) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    final guest = await guests.guestId();
    if (!_current(generation) ||
        _phase != AccountPhase.guest ||
        _subject != null ||
        _accountId != null) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    return guest;
  }

  /// Replaces an expired anonymous desk only after explicit recovery UI.
  ///
  /// Ordinary reads, retries, sign-in cancellation and app relaunch never call
  /// this boundary, so the secure credential remains intact until the player
  /// deliberately starts over.
  Future<void> startNewGuestDesk({GuestSessionFailure? observedFailure}) async {
    if (!canStartNewGuestDesk) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    final generation = _generation;
    await (guestSessions! as GuestSessionRecoveryPort).startNewGuestDesk(
      observedFailure: observedFailure,
    );
    if (!_current(generation) || _phase != AccountPhase.guest) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    _errorCode = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void _watchRepository() {
    _observedLocalRevision = _repository.localRevision;
    _observedProgress = canonicalProgressContent(_repository.state);
    _repository.addListener(_repositoryChanged);
  }

  void _replaceRepository(OfficeProgressRepository next) {
    if (identical(next, _repository)) return;
    _repository.removeListener(_repositoryChanged);
    _repository = next;
    _navigationEpoch++;
    _watchRepository();
  }

  void _repositoryChanged() {
    if (_disposed) return;
    final progress = canonicalProgressContent(_repository.state);
    final locallyChanged = _repository.localRevision != _observedLocalRevision;
    if (!locallyChanged && progress != _observedProgress) _navigationEpoch++;
    _observedLocalRevision = _repository.localRevision;
    _observedProgress = progress;
    if (_repository.loadIssue != null) {
      _syncStatus = AccountSyncStatus.protected;
      _cancelTimer();
    } else if (locallyChanged && _session != null) {
      _retry = 0;
      if (!_terminalStatus) {
        _syncStatus = _syncing == null
            ? AccountSyncStatus.local
            : AccountSyncStatus.syncing;
        _schedule(_debounce);
      }
    }
    _notify();
  }

  Future<void> initialize() {
    if (_disposed) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    final intent = _intent;
    _authSubscription ??= _auth.changes.listen(
      _authChanged,
      onError: (Object _) {
        if (!_disposed) _authFailure('PRACTICE_AUTH_UNAVAILABLE');
      },
    );
    try {
      await _auth.initialize();
      if (_disposed || intent != _intent) return;
      _authChanged(_auth.state);
      await _connection;
    } catch (_) {
      if (!_disposed && intent == _intent) {
        _authFailure('PRACTICE_AUTH_UNAVAILABLE');
      }
    }
  }

  void _authChanged(PracticeAuthState state) {
    if (_disposed) return;
    switch (state.status) {
      case PracticeAuthStatus.initializing:
        return;
      case PracticeAuthStatus.disabled:
      case PracticeAuthStatus.signedOut:
        _showGuest();
      case PracticeAuthStatus.failed:
        _authFailure('PRACTICE_AUTH_UNAVAILABLE');
      case PracticeAuthStatus.signedIn:
        if (_signedOutExplicitly) return;
        final subject = state.subject;
        if (subject == null) {
          _authFailure('PRACTICE_AUTH_UNAVAILABLE');
          return;
        }
        if (_subject == subject && (_session != null || _connection != null)) {
          if (_session != null &&
              _syncStatus == AccountSyncStatus.loginRequired) {
            _syncStatus = AccountSyncStatus.local;
            _retry = 0;
            _schedule(Duration.zero);
          }
          return;
        }
        _beginConnection(subject);
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _retire(AccountProgressSession session) {
    session.close();
    final account = session.coordinator.accountId;
    final previous = _retiring[account];
    late final Future<void> barrier;
    barrier = Future.wait<void>([?previous, session.whenIdle])
        .then<void>((_) {})
        .whenComplete(() {
          if (identical(_retiring[account], barrier)) _retiring.remove(account);
        });
    _retiring[account] = barrier;
  }

  bool _portfolioIdentityCurrent(
    String subject,
    String account,
    int generation,
  ) =>
      _bindingCurrent(subject, generation) &&
      _serverVerified &&
      _session != null &&
      _subject == subject &&
      _accountId == account;

  void _clearFollowedStocks() {
    final previous = _followedStocks;
    final listener = _followedStocksListener;
    _followedStocks = null;
    _followedStocksListener = null;
    if (previous == null) return;
    if (listener != null) previous.removeListener(listener);
    previous.dispose();
  }

  /// The followed list lives for exactly as long as the verified account does,
  /// like invitations and the portfolio. It reads nothing until something asks.
  void _mountFollowedStocks(String subject, String account, int generation) {
    _clearFollowedStocks();
    if (!_portfolioIdentityCurrent(subject, account, generation)) return;
    Future<PracticeAccessToken> token() async {
      if (!_portfolioIdentityCurrent(subject, account, generation)) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
      final value = await _token(subject, generation);
      if (!_portfolioIdentityCurrent(subject, account, generation)) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
      return PracticeAccessToken(accountId: account, token: value);
    }

    final controller = FollowedStocksController(
      client: HttpFollowedStocksClient(
        client: _httpClient,
        baseUri: _baseUri,
        accountId: account,
        accessToken: token,
        allowLoopbackForTests: _allowLoopback,
      ),
    );
    if (!_portfolioIdentityCurrent(subject, account, generation)) {
      controller.dispose();
      return;
    }
    void changed() {
      if (identical(_followedStocks, controller) &&
          _portfolioIdentityCurrent(subject, account, generation)) {
        _notify();
      }
    }

    _followedStocks = controller;
    _followedStocksListener = changed;
    controller.addListener(changed);
  }

  void _clearInvitations() {
    final previous = _invitations;
    final listener = _invitationsListener;
    _invitations = null;
    _invitationsListener = null;
    if (previous == null) return;
    if (listener != null) previous.removeListener(listener);
    previous.dispose();
  }

  void _clearRelationships() {
    final previous = _relationships;
    final listener = _relationshipsListener;
    _relationships = null;
    _relationshipsListener = null;
    if (previous == null) return;
    if (listener != null) previous.removeListener(listener);
    previous.dispose();
  }

  /// Invitations live for exactly as long as the verified account does. X
  /// lookup and linked-identity proof stay on the server.
  void _mountInvitations(String subject, String account, int generation) {
    _clearInvitations();
    if (!_portfolioIdentityCurrent(subject, account, generation)) return;
    Future<PracticeAccessToken> token() async {
      if (!_portfolioIdentityCurrent(subject, account, generation)) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
      final value = await _token(subject, generation);
      if (!_portfolioIdentityCurrent(subject, account, generation)) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
      return PracticeAccessToken(accountId: account, token: value);
    }

    final controller = InvitationsController(
      client: HttpInvitationsClient(
        client: _httpClient,
        baseUri: _baseUri,
        accountId: account,
        accessToken: token,
        allowLoopbackForTests: _allowLoopback,
      ),
      createMutationStore: _invitationCreateMutationStore,
    );
    if (!_portfolioIdentityCurrent(subject, account, generation)) {
      controller.dispose();
      return;
    }
    // Invitations are their own notifier, so forward their changes. Without
    // this, anything reading the count would keep showing a stale one.
    void changed() {
      if (identical(_invitations, controller) &&
          _portfolioIdentityCurrent(subject, account, generation)) {
        _notify();
      }
    }

    _invitations = controller;
    _invitationsListener = changed;
    controller.addListener(changed);
    unawaited(controller.resumePendingCreate());
  }

  /// Friends, blocks and reports live only for the mounted verified account.
  /// Confirmed rows stay in memory; ambiguous writes use the account-scoped
  /// mutation journal injected by the application host.
  void _mountRelationships(String subject, String account, int generation) {
    _clearRelationships();
    if (!_portfolioIdentityCurrent(subject, account, generation)) return;
    Future<PracticeAccessToken> token() async {
      if (!_portfolioIdentityCurrent(subject, account, generation)) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
      final value = await _token(subject, generation);
      if (!_portfolioIdentityCurrent(subject, account, generation)) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
      return PracticeAccessToken(accountId: account, token: value);
    }

    final controller = RelationshipsController(
      client: HttpRelationshipsClient(
        client: _httpClient,
        baseUri: _baseUri,
        accountId: account,
        accessToken: token,
        allowLoopbackForTests: _allowLoopback,
      ),
      mutationStore: _relationshipMutationStore,
    );
    if (!_portfolioIdentityCurrent(subject, account, generation)) {
      controller.dispose();
      return;
    }
    void changed() {
      if (identical(_relationships, controller) &&
          _portfolioIdentityCurrent(subject, account, generation)) {
        _notify();
      }
    }

    _relationships = controller;
    _relationshipsListener = changed;
    controller.addListener(changed);
    unawaited(controller.resumePendingMutations());
  }

  void _clearPortfolio() {
    final previous = _portfolioRepository;
    final listener = _portfolioListener;
    _portfolioRepository = null;
    _portfolioListener = null;
    if (previous == null) return;
    if (listener != null) previous.removeListener(listener);
    previous.dispose();
  }

  void _clearWalletPossession() {
    final previous = _walletPossession;
    final listener = _walletPossessionListener;
    _walletPossession = null;
    _walletPossessionListener = null;
    if (previous == null) return;
    if (listener != null) previous.removeListener(listener);
    previous.dispose();
  }

  void _mountWalletPossession(String subject, String account, int generation) {
    _clearWalletPossession();
    final signer = _walletSigner;
    if (signer == null ||
        !_portfolioIdentityCurrent(subject, account, generation)) {
      return;
    }
    Future<PracticeAccessToken> accessToken() async {
      if (!_portfolioIdentityCurrent(subject, account, generation)) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
      final token = await _token(subject, generation);
      if (!_portfolioIdentityCurrent(subject, account, generation)) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
      return PracticeAccessToken(accountId: account, token: token);
    }

    final contextClient = HttpAccountDataClient(
      client: _httpClient,
      baseUri: _baseUri,
      accountId: account,
      accessToken: accessToken,
      allowLoopbackForTests: _allowLoopback,
    );
    final controller = WalletPossessionController(
      client: HttpWalletPossessionClient(
        client: _httpClient,
        baseUri: _baseUri,
        accountId: account,
        accessToken: accessToken,
        allowLoopbackForTests: _allowLoopback,
      ),
      signer: signer,
      subject: subject,
      readContext: contextClient.readContext,
      cancelContext: contextClient.cancelPending,
      closeContext: contextClient.close,
      isAccountCurrent: () =>
          _portfolioIdentityCurrent(subject, account, generation),
    );
    if (!_portfolioIdentityCurrent(subject, account, generation)) {
      controller.dispose();
      return;
    }
    controller.setForeground(_foreground);
    controller.setNetworkAvailable(_networkAvailable);
    void changed() {
      if (identical(_walletPossession, controller) &&
          _portfolioIdentityCurrent(subject, account, generation)) {
        _notify();
      }
    }

    _walletPossession = controller;
    _walletPossessionListener = changed;
    controller.addListener(changed);
  }

  void _mountPortfolio(String subject, String account, int generation) {
    _clearPortfolio();
    if (!_portfolioIdentityCurrent(subject, account, generation)) return;
    final client = HttpAccountDataClient(
      client: _httpClient,
      baseUri: _baseUri,
      accountId: account,
      accessToken: () async {
        if (!_portfolioIdentityCurrent(subject, account, generation)) {
          throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
        }
        final token = await _token(subject, generation);
        if (!_portfolioIdentityCurrent(subject, account, generation)) {
          throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
        }
        return PracticeAccessToken(accountId: account, token: token);
      },
      allowLoopbackForTests: _allowLoopback,
    );
    final repository = AccountPortfolioRepository.fromHttp(client: client);
    if (!_portfolioIdentityCurrent(subject, account, generation)) {
      repository.dispose();
      return;
    }
    void changed() {
      if (identical(_portfolioRepository, repository) &&
          _portfolioIdentityCurrent(subject, account, generation)) {
        _notify();
      }
    }

    _portfolioRepository = repository;
    _portfolioListener = changed;
    repository.addListener(changed);
    if (!_networkAvailable) repository.setNetworkAvailable(false);
  }

  void _refreshPortfolioUnawaited() {
    final repository = _portfolioRepository;
    if (repository == null ||
        repository.state.phase == AccountPortfolioPhase.accountChanged ||
        repository.state.phase == AccountPortfolioPhase.closed) {
      return;
    }
    unawaited(refreshPortfolio().catchError((Object _) {}));
  }

  void _detach() {
    _cancelTimer();
    _generation++;
    _connection = null;
    _syncing = null;
    _syncAgain = false;
    _retry = 0;
    _serverVerified = false;
    _hasPreservedGuestDesk = false;
    _hasExpiredGuestDesk = false;
    _clearPortfolio();
    _clearInvitations();
    _clearRelationships();
    _clearFollowedStocks();
    _clearWalletPossession();
    if (_session case final previous?) _retire(previous);
    _session = null;
    _replaceRepository(guestRepository);
  }

  void _showGuest() {
    final returningToGuest =
        _subject != null || _session != null || _phase != AccountPhase.guest;
    if (returningToGuest) {
      if (guestSessions case final GuestSessionAccountLifecyclePort lifecycle) {
        lifecycle.resumeGuestAccessAfterSignOut();
      }
      _detach();
    }
    _subject = null;
    _accountId = null;
    _errorCode = null;
    _phase = AccountPhase.guest;
    _syncStatus = guestRepository.loadIssue == null
        ? AccountSyncStatus.local
        : AccountSyncStatus.protected;
    _notify();
  }

  void _authFailure(String code) {
    _detach();
    _subject = null;
    _accountId = null;
    _errorCode = code;
    _phase = AccountPhase.error;
    _syncStatus = AccountSyncStatus.loginRequired;
    _notify();
  }

  void _beginConnection(String subject) {
    _detach();
    _subject = subject;
    _accountId = null;
    _errorCode = null;
    _phase = AccountPhase.connecting;
    _syncStatus = AccountSyncStatus.local;
    final generation = _generation;
    late final Future<void> operation;
    operation = _connect(subject, generation).whenComplete(() {
      if (identical(_connection, operation)) _connection = null;
    });
    _connection = operation;
    _notify();
  }

  Future<String> _token(String subject, int generation) async {
    if (!_current(generation) || _auth.state.subject != subject) {
      throw const PracticeSyncException('PRACTICE_TOKEN_UNAVAILABLE');
    }
    final token = await _auth.accessToken(expectedSubject: subject);
    if (!_current(generation) ||
        _auth.state.status != PracticeAuthStatus.signedIn ||
        _auth.state.subject != subject ||
        token == null) {
      throw const PracticeSyncException('PRACTICE_TOKEN_UNAVAILABLE');
    }
    return token;
  }

  Future<void> _connect(String subject, int generation) async {
    try {
      final bindings = _bindings;
      final cached = await bindings?.read(
        subject,
        isCurrent: () => _bindingCurrent(subject, generation),
      );
      if (!_bindingCurrent(subject, generation)) return;
      String account;
      try {
        account = await _serverAccount(subject, generation);
      } catch (error) {
        if (!_bindingCurrent(subject, generation)) return;
        if (cached == null || !_offlineSessionFailure(error)) rethrow;
        await _mountAccount(
          cached.accountId,
          subject,
          generation,
          verified: false,
        );
        return;
      }
      if (!_bindingCurrent(subject, generation)) return;
      await bindings?.confirmVerified(
        subject,
        account,
        isCurrent: () => _bindingCurrent(subject, generation),
      );
      if (!_bindingCurrent(subject, generation)) return;
      await _mountAccount(account, subject, generation, verified: true);
    } catch (error) {
      if (!_current(generation)) return;
      _errorCode = _code(error);
      _phase = AccountPhase.error;
      _syncStatus = _status(error);
      _notify();
    }
  }

  bool _bindingCurrent(String subject, int generation) =>
      _current(generation) &&
      _auth.state.status == PracticeAuthStatus.signedIn &&
      _auth.state.subject == subject;

  bool _offlineSessionFailure(Object error) => const {
    'PRACTICE_NETWORK_ERROR',
    'PRACTICE_TIMEOUT',
    'PRACTICE_SYNC_UNAVAILABLE',
  }.contains(_code(error));

  Future<String> _serverAccount(String subject, int generation) async {
    // Claim comes before account provisioning. If it fails, the server has not
    // created a competing account and the credential remains on the device.
    final guests = guestSessions;
    var preservedGuestDesk = false;
    var expiredGuestDesk = false;
    if (guests != null) {
      final bearer = await _token(subject, generation);
      try {
        await guests.claimGuestDesk(bearer);
      } on GuestSessionException catch (error) {
        // An existing account or an expired anonymous desk cannot be claimed.
        // In either case, keep the guest credential untouched and open the
        // verified account as a separate desk.
        switch (error.failure) {
          case GuestSessionFailure.accountAlreadySaved:
            preservedGuestDesk = true;
          case GuestSessionFailure.expired:
            // Expiry makes the anonymous desk unclaimable. Sign-in can still
            // open a separate saved account, while the old credential remains
            // untouched for explicit recovery policy or an explicit restart.
            preservedGuestDesk = true;
            expiredGuestDesk = true;
          default:
            rethrow;
        }
      }
      if (!_bindingCurrent(subject, generation)) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
    }
    final account = await HttpPracticeSessionClient(
      client: _httpClient,
      baseUri: _baseUri,
      accessToken: () => _token(subject, generation),
      allowLoopbackForTests: _allowLoopback,
    ).openSession();
    if (!_bindingCurrent(subject, generation)) {
      throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
    }
    _hasPreservedGuestDesk = preservedGuestDesk;
    _hasExpiredGuestDesk = expiredGuestDesk;
    return account;
  }

  Future<void> _mountAccount(
    String account,
    String subject,
    int generation, {
    required bool verified,
  }) async {
    try {
      if (!_bindingCurrent(subject, generation)) return;
      _accountId = account;
      while (_current(generation) &&
          (_retiring.containsKey(account) || _opening.containsKey(account))) {
        await Future.wait<void>([?_retiring[account], ?_opening[account]]);
      }
      if (!_current(generation)) return;
      if (!verified) {
        String? local;
        try {
          local = await _store.read(
            PracticeSyncCoordinator.storageKeyFor(account),
          );
        } catch (_) {
          throw const PracticeSyncException(
            'PRACTICE_BINDING_LOCAL_READ_FAILED',
          );
        }
        if (!_bindingCurrent(subject, generation)) return;
        // Cache alone cannot manufacture an empty replacement for an account
        // whose first local record never finished being saved.
        if (local == null) {
          throw const PracticeSyncException('PRACTICE_BINDING_LOCAL_MISSING');
        }
      }
      _serverVerified = verified;
      final transport = HttpPracticeTransport(
        client: _httpClient,
        baseUri: _baseUri,
        accountId: account,
        accessToken: () async {
          if (!_serverVerified) {
            throw const PracticeSyncException('PRACTICE_BINDING_UNVERIFIED');
          }
          final token = await _token(subject, generation);
          if (!_serverVerified) {
            throw const PracticeSyncException('PRACTICE_BINDING_UNVERIFIED');
          }
          return PracticeAccessToken(accountId: account, token: token);
        },
        allowLoopbackForTests: _allowLoopback,
      );
      final opening = Completer<void>();
      _opening[account] = opening.future;
      late final AccountProgressSession session;
      try {
        session =
            await (_sessionFactory?.call(account, transport) ??
                AccountProgressSession.open(
                  accountId: account,
                  store: _store,
                  transport: transport,
                ));
        if (!_current(generation)) {
          _retire(session);
          await session.whenIdle;
          return;
        }
      } finally {
        if (identical(_opening[account], opening.future)) {
          _opening.remove(account);
        }
        opening.complete();
      }
      if (!_current(generation)) {
        _retire(session);
        return;
      }
      _session = session;
      _replaceRepository(session.progressRepository);
      _phase = AccountPhase.active;
      _syncStatus = session.coordinator.state!.conflict != null
          ? AccountSyncStatus.conflict
          : verified
          ? AccountSyncStatus.local
          : AccountSyncStatus.offline;
      if (!verified) _errorCode = 'PRACTICE_BINDING_OFFLINE';
      if (verified) {
        _mountPortfolio(subject, account, generation);
        _mountInvitations(subject, account, generation);
        _mountRelationships(subject, account, generation);
        _mountFollowedStocks(subject, account, generation);
        _mountWalletPossession(subject, account, generation);
      }
      _notify();
      if (verified) _refreshPortfolioUnawaited();
      if (verified && !_terminalStatus) _schedule(Duration.zero);
      if (!verified) _scheduleRetry();
    } catch (error) {
      if (!_current(generation)) return;
      _errorCode = _code(error);
      _phase = AccountPhase.error;
      _syncStatus = _status(error);
      _notify();
    }
  }

  Future<void> _verifyMountedAccount() {
    if (_connection != null) return _connection!;
    final subject = _subject;
    final account = _accountId;
    if (_disposed ||
        !_foreground ||
        _session == null ||
        subject == null ||
        account == null) {
      return Future.value();
    }
    final generation = _generation;
    late final Future<void> operation;
    operation = _reverify(subject, account, generation).whenComplete(() {
      if (identical(_connection, operation)) _connection = null;
    });
    _connection = operation;
    return operation;
  }

  Future<void> _reverify(String subject, String account, int generation) async {
    try {
      final verified = await _serverAccount(subject, generation);
      if (!_bindingCurrent(subject, generation)) return;
      if (verified != account) {
        throw const PracticeSyncException('PRACTICE_BINDING_ACCOUNT_MISMATCH');
      }
      await _bindings?.confirmVerified(
        subject,
        verified,
        isCurrent: () => _bindingCurrent(subject, generation),
      );
      if (!_bindingCurrent(subject, generation)) return;
      _serverVerified = true;
      _errorCode = null;
      _syncStatus = _session!.coordinator.state!.conflict != null
          ? AccountSyncStatus.conflict
          : AccountSyncStatus.local;
      _mountPortfolio(subject, account, generation);
      _mountInvitations(subject, account, generation);
      _mountRelationships(subject, account, generation);
      _mountFollowedStocks(subject, account, generation);
      _mountWalletPossession(subject, account, generation);
      _notify();
      _refreshPortfolioUnawaited();
      if (!_terminalStatus) await _synchronize();
    } catch (error) {
      if (!_current(generation)) return;
      _errorCode = _code(error);
      _syncStatus = _status(error);
      if (_syncStatus == AccountSyncStatus.offline) _scheduleRetry();
      _notify();
    }
  }

  void _scheduleRetry() {
    if (_retry >= _retryDelays.length || !_foreground || _disposed) return;
    final generation = _generation;
    final delay = _retryDelays[_retry++];
    _cancelTimer();
    _timer = _timerFactory(delay, () {
      _timer = null;
      if (_current(generation)) unawaited(_synchronize());
    });
  }

  /// Opens the provider's browser flow, then binds the verified server account.
  Future<PracticeSignInResult> signIn([
    PracticeOAuthProvider provider = PracticeOAuthProvider.x,
  ]) => _signIn(() => _auth.signInWithOAuth(provider));

  /// Requests a one-time email code. This changes no account or sync state.
  Future<PracticeEmailCodeResult> sendEmailCode(String email) async {
    if (_disposed) return PracticeEmailCodeResult.unavailable;
    try {
      return await _auth.sendEmailCode(email);
    } catch (_) {
      return PracticeEmailCodeResult.failed;
    }
  }

  /// Exchanges the emailed code, then binds the verified server account.
  Future<PracticeSignInResult> signInWithEmailCode({
    required String email,
    required String code,
  }) => _signIn(() => _auth.signInWithEmailCode(email: email, code: code));

  Future<PracticeSignInResult> _signIn(
    Future<PracticeSignInResult> Function() attempt,
  ) async {
    if (_disposed) return PracticeSignInResult.unavailable;
    _signedOutExplicitly = false;
    final intent = ++_intent;
    _phase = AccountPhase.connecting;
    _errorCode = null;
    _notify();
    try {
      final result = await attempt();
      if (_disposed || intent != _intent) {
        return PracticeSignInResult.sessionChanged;
      }
      if (result == PracticeSignInResult.signedIn ||
          result == PracticeSignInResult.sessionChanged) {
        _authChanged(_auth.state);
        await _connection;
        if (_session != null) _phase = AccountPhase.active;
      } else {
        _phase = _session == null ? AccountPhase.guest : AccountPhase.active;
        if (result != PracticeSignInResult.cancelled) {
          _errorCode = 'PRACTICE_SIGN_IN_FAILED';
        }
      }
      _notify();
      return result;
    } catch (_) {
      if (_disposed || intent != _intent) {
        return PracticeSignInResult.sessionChanged;
      }
      _phase = _session == null ? AccountPhase.error : AccountPhase.active;
      _errorCode = 'PRACTICE_SIGN_IN_FAILED';
      _notify();
      return PracticeSignInResult.failed;
    }
  }

  /// Closes this account on the server, then signs out, because a closed
  /// account can never authenticate again.
  ///
  /// Closing is a lockout, not an erasure. Saved history stays on the server as
  /// immutable records, and practice saved on this device stays on this device
  /// exactly as it does after an ordinary sign-out.
  Future<void> closeAccount() async {
    if (_disposed || !canCloseAccount) return;
    final subject = _auth.state.subject;
    final account = _accountId;
    if (subject == null || account == null) return;
    final generation = _generation;
    _errorCode = null;
    final client = AccountClosureClient(
      client: _httpClient,
      baseUri: _baseUri,
      accountId: account,
      accessToken: () async {
        if (!_current(generation)) {
          throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
        }
        final token = await _token(subject, generation);
        if (!_current(generation)) {
          throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
        }
        return PracticeAccessToken(accountId: account, token: token);
      },
      allowLoopbackForTests: _allowLoopback,
    );
    AccountClosureOutcome outcome;
    try {
      outcome = await client.closeAccount();
    } on AccountClosureException catch (error) {
      client.close();
      if (_disposed || !_current(generation)) return;
      _errorCode =
          'PRACTICE_ACCOUNT_CLOSURE_${error.failure.name.toUpperCase()}';
      _notify();
      return;
    } catch (_) {
      client.close();
      if (_disposed || !_current(generation)) return;
      _errorCode = 'PRACTICE_ACCOUNT_CLOSURE_FAILED';
      _notify();
      return;
    }
    client.close();
    if (_disposed) return;
    _lastClosure = outcome;
    // The account cannot serve another request, so end the session locally
    // whatever else happens.
    await signOut();
  }

  Future<void> signOut() async {
    if (_disposed) return;
    _signedOutExplicitly = true;
    final intent = ++_intent;
    _showGuest();
    try {
      await _auth.signOut();
    } catch (_) {
      if (_disposed || intent != _intent) return;
      _errorCode = 'PRACTICE_SIGN_OUT_FAILED';
      _notify();
    }
  }

  /// Retry server identity resolution or a protected local record without
  /// opening another OAuth flow. Existing bytes remain protected on failure.
  Future<void> retryConnection() async {
    if (_disposed || _signedOutExplicitly) return;
    final state = _auth.state;
    if (state.status != PracticeAuthStatus.signedIn || state.subject == null) {
      return;
    }
    if (_session != null) {
      await synchronize();
      return;
    }
    _beginConnection(state.subject!);
    await _connection;
  }

  bool get _terminalStatus => const {
    AccountSyncStatus.conflict,
    AccountSyncStatus.protected,
    AccountSyncStatus.loginRequired,
  }.contains(_syncStatus);

  void _schedule(Duration delay) {
    if (!_foreground || _disposed || _session == null || _terminalStatus) {
      return;
    }
    if (_syncing != null) {
      _syncAgain = true;
      return;
    }
    _cancelTimer();
    final generation = _generation;
    _timer = _timerFactory(delay, () {
      _timer = null;
      if (_current(generation)) unawaited(_synchronize());
    });
  }

  /// Explicit retry starts a finite retry budget; it never clears a conflict.
  Future<void> synchronize() {
    if (_disposed || !_foreground || _session == null) return Future.value();
    _retry = 0;
    _cancelTimer();
    return _synchronize();
  }

  Future<void> _synchronize() {
    if (_syncing != null) return _syncing!;
    final session = _session;
    if (_disposed || !_foreground || session == null || _terminalStatus) {
      return Future.value();
    }
    if (!_serverVerified) return _verifyMountedAccount();
    final generation = _generation;
    late final Future<void> operation;
    operation = _runSync(session, generation).whenComplete(() {
      if (identical(_syncing, operation)) _syncing = null;
      if (!_current(generation)) return;
      if (_syncAgain &&
          !_terminalStatus &&
          _syncStatus != AccountSyncStatus.offline) {
        _syncAgain = false;
        _schedule(_debounce);
      }
    });
    _syncing = operation;
    return operation;
  }

  Future<void> _runSync(AccountProgressSession session, int generation) async {
    _syncStatus = AccountSyncStatus.syncing;
    _errorCode = null;
    _notify();
    try {
      await session.synchronize();
      if (!_current(generation)) return;
      final state = session.coordinator.state!;
      final clean =
          state.pending == null &&
          state.base != null &&
          canonicalProgressContent(state.local) ==
              canonicalProgressContent(
                state.base!.progress ?? OfficeProgress.empty(),
              );
      _syncStatus = clean ? AccountSyncStatus.saved : AccountSyncStatus.local;
      if (!clean) _syncAgain = true;
    } catch (error) {
      if (!_current(generation)) return;
      _errorCode = _code(error);
      _syncStatus = _status(error);
      if (_syncStatus == AccountSyncStatus.offline) _scheduleRetry();
    }
    _notify();
  }

  String _code(Object error) {
    if (error is PracticeSyncException) return error.code;
    if (error is GuestSessionException) {
      return 'GUEST_${error.failure.name.toUpperCase()}';
    }
    return 'PRACTICE_NETWORK_ERROR';
  }

  AccountSyncStatus _status(Object error) {
    final code = _code(error);
    if (code.startsWith('PRACTICE_BINDING_')) {
      return code == 'PRACTICE_BINDING_OFFLINE'
          ? AccountSyncStatus.offline
          : AccountSyncStatus.protected;
    }
    if (code == 'GUEST_ACCOUNTALREADYSAVED' ||
        code == 'GUEST_ALREADYCLAIMED' ||
        code == 'GUEST_PROTECTEDSTORAGE') {
      return AccountSyncStatus.protected;
    }
    if (code.contains('CONFLICT')) return AccountSyncStatus.conflict;
    if (code == 'PRACTICE_VERSION_DOWNGRADE' ||
        code.contains('LOCAL_') ||
        code.contains('STATE_') ||
        code.contains('INVALID_RESPONSE') ||
        code.contains('INVALID_PROTOCOL') ||
        code.contains('ACK_MISMATCH')) {
      return AccountSyncStatus.protected;
    }
    if (code.contains('TOKEN') ||
        code.contains('AUTH') ||
        code.contains('ACCOUNT_MISMATCH')) {
      return AccountSyncStatus.loginRequired;
    }
    return AccountSyncStatus.offline;
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    _walletPossession?.setForeground(foreground);
    if (!foreground) {
      _cancelTimer();
      _portfolioRepository?.cancelRefresh();
    } else {
      _retry = 0;
      if (_session != null &&
          !_serverVerified &&
          _syncStatus != AccountSyncStatus.protected &&
          _syncStatus != AccountSyncStatus.loginRequired) {
        unawaited(_verifyMountedAccount());
      } else {
        _schedule(Duration.zero);
        if (_serverVerified) _refreshPortfolioUnawaited();
      }
    }
    _notify();
  }

  /// Refreshes read-only account context and holdings for the verified mount.
  /// Cached offline account bindings cannot cross this gate.
  Future<void> refreshPortfolio() {
    final repository = _portfolioRepository;
    final subject = _subject;
    final account = _accountId;
    if (_disposed ||
        !_foreground ||
        !_networkAvailable ||
        !_serverVerified ||
        repository == null ||
        subject == null ||
        account == null ||
        repository.accountId != account ||
        !_portfolioIdentityCurrent(subject, account, _generation)) {
      return Future<void>.value();
    }
    return repository.refresh();
  }

  /// User-initiated setup. The SDK ensures one wallet and the server independently
  /// checks its link before the UI treats it as an account wallet.
  Future<WalletSetupOutcome> setUpWallet() async {
    if (!canSetUpWallet) return WalletSetupOutcome.unavailable;
    final subject = _subject;
    final account = _accountId;
    final generation = _generation;
    if (subject == null || account == null) {
      return WalletSetupOutcome.unavailable;
    }
    bool current() => _portfolioIdentityCurrent(subject, account, generation);
    _walletSetupBusy = true;
    _notify();
    HttpAccountDataClient? client;
    var providerMayHaveRun = false;
    try {
      // A fresh bearer is obtained before the provider mutation. A cached local
      // login alone is insufficient to start wallet creation.
      await _token(subject, generation);
      if (!current() || !_foreground || !_networkAvailable) {
        return WalletSetupOutcome.accountChanged;
      }
      providerMayHaveRun = true;
      final address = await _walletSetup!
          .ensureSolanaWallet(expectedSubject: subject)
          .timeout(const Duration(seconds: 30));
      if (!current()) return WalletSetupOutcome.accountChanged;
      if (!_foreground || !_networkAvailable) {
        return WalletSetupOutcome.awaitingServer;
      }
      client = HttpAccountDataClient(
        client: _httpClient,
        baseUri: _baseUri,
        accountId: account,
        accessToken: () async {
          if (!current()) {
            throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
          }
          final token = await _token(subject, generation);
          if (!current()) {
            throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
          }
          return PracticeAccessToken(accountId: account, token: token);
        },
        allowLoopbackForTests: _allowLoopback,
      );
      final context = await client.readContext(fresh: true);
      if (!current()) return WalletSetupOutcome.accountChanged;
      if (!context.embeddedSolanaWallet.isCandidate ||
          context.embeddedSolanaWallet.address != address) {
        return WalletSetupOutcome.awaitingServer;
      }
      // Cancel an older cached-context read so it cannot overwrite setup with
      // its earlier “missing wallet” observation.
      _portfolioRepository?.cancelRefresh();
      await _portfolioRepository?.whenIdle;
      await refreshPortfolio();
      if (!current()) return WalletSetupOutcome.accountChanged;
      return portfolioState?.context?.embeddedSolanaWallet.address == address
          ? WalletSetupOutcome.ready
          : WalletSetupOutcome.awaitingServer;
    } on WalletSetupException catch (error) {
      return error.failure == WalletSetupFailure.accountChanged
          ? WalletSetupOutcome.accountChanged
          : WalletSetupOutcome.unavailable;
    } catch (_) {
      return current()
          ? (providerMayHaveRun
                ? WalletSetupOutcome.awaitingServer
                : WalletSetupOutcome.unavailable)
          : WalletSetupOutcome.accountChanged;
    } finally {
      client?.close();
      _walletSetupBusy = false;
      _notify();
    }
  }

  /// Updates the repository's connectivity state. Reconnection explicitly
  /// refreshes only a still-current, server-verified account.
  void setNetworkAvailable(bool available) {
    if (_disposed || _networkAvailable == available) return;
    _networkAvailable = available;
    _portfolioRepository?.setNetworkAvailable(available);
    _walletPossession?.setNetworkAvailable(available);
    if (available && _foreground && _serverVerified) {
      _refreshPortfolioUnawaited();
    }
  }

  Future<void> importGuestProgress() async {
    final session = _session;
    if (_disposed || session == null || !canImportGuestProgress) {
      throw const PracticeSyncException('PRACTICE_IMPORT_NOT_EMPTY');
    }
    final generation = _generation;
    await session.importProgress(guestRepository.state);
    if (!_current(generation)) return;
    _syncStatus = AccountSyncStatus.local;
    _retry = 0;
    _schedule(_debounce);
    _notify();
  }

  Future<void> resolveConflict(OfficeProgress reconciled) async {
    final session = _session;
    if (_disposed || session == null) {
      throw const PracticeSyncException('PRACTICE_NO_CONFLICT');
    }
    final generation = _generation;
    await session.resolveConflict(reconciled);
    if (!_current(generation)) return;
    _syncStatus = AccountSyncStatus.local;
    _errorCode = null;
    _retry = 0;
    _schedule(_debounce);
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _intent++;
    _generation++;
    _cancelTimer();
    _clearPortfolio();
    _clearInvitations();
    _clearRelationships();
    _clearFollowedStocks();
    _clearWalletPossession();
    _repository.removeListener(_repositoryChanged);
    unawaited(_authSubscription?.cancel());
    if (_session case final session?) _retire(session);
    _session = null;
    super.dispose();
  }
}
