import '../money/money_mode.dart';
import '../money/real_holdings.dart';
import '../money/live_trade_history.dart';
import '../onboarding/first_stock_followup.dart';
import '../notifications/notification_permission.dart';
import '../workdays/workdays.dart';
import '../workdays/workday_screen.dart';
import '../workdays/career_world.dart';
import '../market/fast_buy_sheet.dart';
import '../market/live_order_flow.dart';
import '../market/live_trading.dart';
import '../community/community.dart';
import '../desk/desk_activity.dart';
import '../../social/relationship.dart';
import '../../ui_review/review_feedback.dart';
import '../settings/product_information_screen.dart';
import '../market/market_catalog.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../account/account_controller.dart';
import '../../account/config.dart';
import '../../account/guest_session.dart';
import '../../markets/discovery.dart';
import '../../markets/stock_research_host.dart';
import '../../ui_review/review_animated_splash.dart';
import '../account/fund_wallet_sheet.dart';
import '../account/wallet_recovery_link.dart';
import '../account/guest_desk_preserved_screen.dart';
import '../account/guest_desk_recovery_screen.dart';
import '../account/product_sign_in_screen.dart';
import '../design/product_motion_icon.dart';
import '../design/product_notice.dart';
import '../design/product_state_page.dart';
import '../design/product_components.dart';
import '../design/product_theme.dart';
import '../design/product_feedback_scope.dart';
import '../desk/desk_models.dart';
import '../desk/desk_portfolio_projection.dart';
import '../desk/desk_screen.dart';
import '../desk/persona_picker_page.dart';
import '../desk/wall_street_clock.dart';
import '../floor/floor_screen.dart';
import '../market/market.dart';
import '../market/paper_portfolio_cache.dart';
import '../onboarding/onboarding.dart';
import '../onboarding/product_introduction.dart';
import '../profile/profile_screen.dart';
import '../settings/settings.dart';
import '../shell/product_shell.dart';
import 'http_product_profile_repository.dart';
import 'launch_moments.dart';
import 'product_market_session.dart';
import 'product_session.dart';
import 'package:url_launcher/url_launcher.dart';

class TrimmyProductApp extends StatefulWidget {
  const TrimmyProductApp({
    super.key,
    required this.preferences,
    required this.account,
    required this.accountConfigurationFailed,
    this.stockFactsRepository,
    this.showStartupSplash = false,
  });

  final SharedPreferences preferences;
  final AccountController? account;
  final bool accountConfigurationFailed;
  final bool showStartupSplash;

  /// Test/native injection only. Production constructs the credential-free
  /// HTTP reader from the configured public stock API origin.
  final StockFactsRepository? stockFactsRepository;

  @override
  State<TrimmyProductApp> createState() => _TrimmyProductAppState();
}

class _TrimmyProductAppState extends State<TrimmyProductApp> {
  bool _startupFinished = false;
  late final _moneyMode = MoneyModeController(
    widget.preferences,
    widget.account,
  );
  late final ProductSession _session = ProductSession.fromPreferences(
    widget.preferences,
  );

  @override
  void dispose() {
    _moneyMode.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MoneyModeScope(
    controller: _moneyMode,
    child: MaterialApp(
      title: 'Trimmy',
      debugShowCheckedModeBanner: false,
      theme: productTheme(),
      builder: (context, child) => ProductFeedbackScope(child: child!),
      home: Stack(
        fit: StackFit.expand,
        children: [
          ProductExperience(
            preferences: widget.preferences,
            session: _session,
            account: widget.account,
            accountConfigurationFailed: widget.accountConfigurationFailed,
            stockFactsRepository: widget.stockFactsRepository,
            holdStartupPresentation:
                widget.showStartupSplash && !_startupFinished,
          ),
          if (widget.showStartupSplash && !_startupFinished)
            ReviewColdLaunchPage(
              onContinue: () => setState(() => _startupFinished = true),
            ),
        ],
      ),
    ),
  );
}

class ProductExperience extends StatefulWidget {
  const ProductExperience({
    super.key,
    required this.preferences,
    required this.session,
    required this.account,
    required this.accountConfigurationFailed,
    this.stockFactsRepository,
    this.holdStartupPresentation = false,
  });

  final SharedPreferences preferences;
  final ProductSession session;
  final AccountController? account;
  final bool accountConfigurationFailed;
  final StockFactsRepository? stockFactsRepository;
  final bool holdStartupPresentation;

  @override
  State<ProductExperience> createState() => _ProductExperienceState();
}

class _ProductExperienceState extends State<ProductExperience>
    with WidgetsBindingObserver {
  CommunityRepository? _community;
  WorkdayController? _dailyDesk;
  int _communityEpoch = 0;
  static const guestChoiceKey = 'trimmy.entry.guest-chosen.v1';
  late bool _guestAccessApproved =
      widget.preferences.getBool(guestChoiceKey) == true;
  bool _acceptingGuest = false;
  bool _entryAccountGateOpen = false;
  bool _skipIntroAfterAuth = false;
  bool _accountEntryRunning = false;
  bool _accountEntryFailed = false;
  final _shellKey = GlobalKey<ProductShellState>();
  final _http = http.Client();
  final _career = CareerController();
  final _missions = CareerMissionsController();
  late final _careerDayContext = CareerDayContextController(
    mutationStore: PreferencesCareerDayContextMutationStore(widget.preferences),
  );
  Timer? _careerDateTimer;
  ProductMarketSession? _market;
  LiveTradingCapabilities? _liveCapabilities;
  Future<void>? _liveCapabilitiesRequest;
  bool _liveCapabilitiesFailed = false;

  Future<void> _refreshLiveCapabilities() {
    return _liveCapabilitiesRequest ??= _readLiveCapabilities().whenComplete(
      () {
        _liveCapabilitiesRequest = null;
      },
    );
  }

  Future<void> _readLiveCapabilities() async {
    final origin = PracticeAccountConfig.fromEnvironment().apiUri;
    if (origin == null) return;
    try {
      final capabilities = await fetchLiveTradingCapabilities(
        origin,
        client: _http,
      );
      if (!mounted) return;
      setState(() {
        _liveCapabilities = capabilities;
        _liveCapabilitiesFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liveCapabilities = null;
        _liveCapabilitiesFailed = true;
      });
    }
    if (mounted) _portfolioViewRevision.value++;
  }

  Future<List<MarketCompany>> _availableLiveCompanies() async {
    await _refreshLiveCapabilities();
    final caps = _liveCapabilities;
    if (caps == null) throw const FormatException('Trading unavailable');
    if (!caps.enabled) return const [];
    final companies = await Future.wait(
      caps.assets.map((asset) async {
        try {
          return _knownCompany(asset.assetId) ??
              await _market?.findCompany(asset.assetId);
        } catch (_) {
          return null;
        }
      }),
    );
    final available = <MarketCompany>[];
    for (final company in companies) {
      if (company == null) continue;
      final asset = caps.forCompany(company);
      if (asset != null) available.add(company.withVariant(asset.mint));
    }
    if (available.isEmpty && caps.assets.isNotEmpty) {
      throw const FormatException('Market unavailable');
    }
    return available;
  }

  void _realPortfolioChanged() {
    if (!mounted) return;
    _portfolioViewRevision.value++;
    unawaited(_resolveHoldingCompanies());
  }

  Future<void> _refreshRealPortfolio() async {
    await widget.account?.refreshPortfolio();
    if (mounted) _portfolioViewRevision.value++;
  }

  http.Client? _stockFactsTransport;
  HttpStockFactsRepository? _httpStockFacts;
  MarketFactsController? _marketFacts;
  AccountController? _orderAccount;
  AccountPhase? _paperAccountPhase;
  String? _paperPrincipalHint;
  String? _paperPrincipalKey;
  String? _routeIdentity;
  HttpPaperOrderRepository? _httpOrders;
  HttpPaperPortfolioRepository? _httpPortfolio;
  HttpPaperResetRepository? _httpPaperReset;
  PaperResetController? _paperReset;
  HttpProductProfileRepository? _httpProductProfile;
  HttpReasonSharingRepository? _httpReasonSharing;
  OwnReasonHistory? _ownReasons;
  late final _reasonPrivacy = ReasonPrivacyController(
    mutationStore: PreferencesReasonPrivacyMutationStore(widget.preferences),
  );
  Route<PaperOrderReceipt>? _companyRoute;
  Route<PaperReasonReceipt>? _reasonRoute;
  final PaperPortfolioSession _portfolioSession = PaperPortfolioSession();
  final ValueNotifier<int> _portfolioViewRevision = ValueNotifier(0);
  PaperPortfolioBinding? _portfolioBinding;
  Timer? _portfolioValuationTimer;
  PaperPortfolioSnapshot? get _portfolio => _portfolioSession.snapshot;
  PaperOrderReceipt? get _latestReceipt => _portfolioSession.pendingReceipt;
  MarketCompany? _latestCompany;
  final Map<String, MarketCompany> _holdingCompanies = {};
  final Set<String> _resolvingHoldings = {};
  final Set<String> _reasonedOrderIds = <String>{};
  bool _portfolioLoading = false;
  bool _paperOpening = false;
  bool _portfolioRefreshQueued = false;
  bool _paperResetApplying = false;
  int _portfolioGeneration = 0;
  PaperOrderFailure? _portfolioFailure;
  GuestSessionFailure? _guestDeskRecovery;
  bool _preservedGuestNoticeAcknowledged = false;
  String? _promotionMutationId;
  String? _promotionPrincipalKey;
  String? _promotionStorageKey;
  CareerRank? _promotionTarget;
  bool _promotionPreparing = false;
  bool _reminderCareerPending = false;

  void _onReminderCareer() {
    if (!mounted) return;
    setState(() => _reminderCareerPending = true);
  }

  Future<void> _consumeReminderCareer() async {
    if (await ProductNotificationPermission.consumeOpenCareer() && mounted) {
      _onReminderCareer();
    }
  }

  void _syncReminder() {
    unawaited(ReminderPreferences.sync(widget.preferences, _paperPrincipalKey));
  }

  bool get _realMoney => MoneyModeScope.isReal(context);

  bool get _signedIn => widget.account?.phase == AccountPhase.active;

  bool get _needsAccountChoice {
    if (_signedIn || _guestAccessApproved) return false;
    if (_entryAccountGateOpen) return true;
    return switch (widget.session.launchStep) {
      ProductLaunchStep.onboarding || ProductLaunchStep.firstTrade => false,
      ProductLaunchStep.firstPosition =>
        (widget.preferences.getInt(
                  FirstStockFollowup.stepKey(_paperPrincipalKey ?? 'local'),
                ) ??
                0) >=
            1,
      ProductLaunchStep.dayOne ||
      ProductLaunchStep.saveDesk ||
      ProductLaunchStep.app => true,
    };
  }

  GuestSessionFailure? get _guestRecoveryFailure {
    if (widget.account?.phase != AccountPhase.guest) return null;
    for (final failure in [
      _guestDeskRecovery,
      widget.session.remoteGuestFailure,
      _career.guestSessionFailure,
      _missions.guestSessionFailure,
      _careerDayContext.guestSessionFailure,
      _reasonPrivacy.guestSessionFailure,
    ]) {
      if (_isTerminalGuestFailure(failure)) return failure;
    }
    return null;
  }

  bool _isTerminalGuestFailure(GuestSessionFailure? failure) =>
      failure == GuestSessionFailure.expired ||
      failure == GuestSessionFailure.revoked;

  void _recordGuestSessionFailure(GuestSessionFailure failure, int generation) {
    if (!mounted ||
        generation != _portfolioGeneration ||
        widget.account?.phase != AccountPhase.guest ||
        !_isTerminalGuestFailure(failure)) {
      return;
    }
    if (_guestDeskRecovery != failure) {
      setState(() => _guestDeskRecovery = failure);
    }
    Navigator.maybeOf(context)?.popUntil((route) => route.isFirst);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _career.addListener(_careerChanged);
    _missions.addListener(_careerChanged);
    _careerDayContext.addListener(_careerDayContextChanged);
    _reasonPrivacy.addListener(_reasonPrivacyChanged);
    widget.account?.addListener(_realPortfolioChanged);
    unawaited(_refreshLiveCapabilities());
    ProductNotificationPermission.setOnOpenCareer(() {
      unawaited(_consumeReminderCareer());
    });
    unawaited(_consumeReminderCareer());
  }

  void _reasonPrivacyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _syncReminder();
    unawaited(_consumeReminderCareer());
    if (_dailyDesk != null) unawaited(_dailyDesk!.refresh());
    _expirePortfolioValuation();
    unawaited(_refreshPortfolio());
    unawaited(_refreshLiveCapabilities());
    unawaited(_refreshCareerDayContext(refreshDependents: true));
  }

  void _careerChanged() {
    _scheduleCareerDateRefresh();
    if (mounted) setState(() {});
  }

  void _careerDayContextChanged() => _scheduleCareerDateRefresh();

  void _scheduleCareerDateRefresh() {
    _careerDateTimer?.cancel();
    if (_careerDayContext.principalKey == null) return;
    final now = DateTime.now().toUtc();
    final nextDayAt = _careerDayContext.failure == null
        ? _careerDayContext.context?.nextDayAt
        : null;
    final delay = careerDayRefreshDelay(now: now, nextDayAt: nextDayAt);
    _careerDateTimer = Timer(delay, () {
      if (mounted) {
        if (_dailyDesk != null) unawaited(_dailyDesk!.refresh());
        unawaited(_refreshCareerDayContext(refreshDependents: true));
      }
    });
  }

  Future<void> _refreshCareerDayContext({
    required bool refreshDependents,
  }) async {
    final generation = _portfolioGeneration;
    final principalKey = _paperPrincipalKey;
    if (principalKey == null) return;
    final previousDate = _careerDayContext.context?.serverDate;
    final configured = await _careerDayContext.synchronize();
    if (!mounted ||
        generation != _portfolioGeneration ||
        principalKey != _paperPrincipalKey) {
      return;
    }
    final dateChanged =
        previousDate != null &&
        _careerDayContext.context?.serverDate != previousDate;
    if (refreshDependents || configured || dateChanged) {
      await Future.wait([_career.refresh(), _missions.refresh()]);
      if (!mounted ||
          generation != _portfolioGeneration ||
          principalKey != _paperPrincipalKey) {
        return;
      }
    }
    _scheduleCareerDateRefresh();
  }

  Future<void> _bindCareerDayContext({
    required String principalKey,
    required CareerRepository repository,
    required int generation,
  }) async {
    final configured = await _careerDayContext.bind(
      principalKey: principalKey,
      repository: repository,
    );
    if (!mounted ||
        generation != _portfolioGeneration ||
        principalKey != _paperPrincipalKey) {
      return;
    }
    if (configured) {
      await Future.wait([_career.refresh(), _missions.refresh()]);
      if (!mounted ||
          generation != _portfolioGeneration ||
          principalKey != _paperPrincipalKey) {
        return;
      }
    }
    _scheduleCareerDateRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_market == null) {
      final controller = StockResearchScope.of(
        context,
        listen: false,
      ).controller;
      final origin = controller.apiOrigin;
      if (origin != null) {
        try {
          final injected = widget.stockFactsRepository;
          StockFactsRepository repository;
          if (injected != null) {
            repository = injected;
          } else {
            final transport = http.Client();
            final httpRepository = HttpStockFactsRepository(
              transport: transport,
              baseUri: origin,
            );
            _stockFactsTransport = transport;
            _httpStockFacts = httpRepository;
            repository = httpRepository;
          }
          _marketFacts = MarketFactsController(repository: repository);
        } catch (_) {
          _httpStockFacts?.close();
          _stockFactsTransport?.close();
          _httpStockFacts = null;
          _stockFactsTransport = null;
          _marketFacts = null;
        }
      }
      final market = ProductMarketSession(
        controller,
        facts: _marketFacts,
        catalog: origin == null ? null : HttpMarketCatalogGateway(origin),
      )..addListener(_marketChanged);
      _market = market;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_market, market)) {
          unawaited(market.loadStarterPicks());
          unawaited(market.loadCatalog());
        }
      });
    }
    _syncPaperRepositories();
  }

  @override
  void didUpdateWidget(covariant ProductExperience oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      oldWidget.account?.removeListener(_realPortfolioChanged);
      widget.account?.addListener(_realPortfolioChanged);
    }
    _syncPaperRepositories();
  }

  void _marketChanged() {
    if (mounted) setState(() {});
  }

  void _syncPaperRepositories() {
    final account = widget.account;
    final phase = account?.phase;
    if (phase == AccountPhase.active) _entryAccountGateOpen = false;
    if (phase == AccountPhase.active && _guestAccessApproved) {
      _guestAccessApproved = false;
      unawaited(widget.preferences.remove(guestChoiceKey));
    }
    final ready = phase == AccountPhase.guest || phase == AccountPhase.active;
    final principalHint = phase == AccountPhase.active
        ? account?.accountId
        : phase == AccountPhase.guest
        ? 'guest'
        : null;
    final accountControllerChanged =
        _orderAccount != null && !identical(account, _orderAccount);
    if (identical(account, _orderAccount) &&
        phase == AccountPhase.guest &&
        _guestDeskRecovery != null) {
      return;
    }
    if (identical(account, _orderAccount) &&
        ready == (_httpOrders != null || _paperOpening) &&
        _paperPrincipalHint == principalHint) {
      return;
    }
    _dismissTradingRoutes();
    if (accountControllerChanged) _dismissIdentityBoundRoutes();
    if (phase == AccountPhase.error &&
        _routeIdentity?.startsWith('active:') == true) {
      _dismissIdentityBoundRoutes();
    }
    _career.unbind();
    _missions.unbind();
    _careerDayContext.unbind();
    _reasonPrivacy.unbind();
    _httpOrders?.close();
    _httpPortfolio?.close();
    _httpPaperReset?.close();
    _paperReset?.dispose();
    _httpProductProfile?.close();
    _dailyDesk?.dispose();
    _dailyDesk = null;
    _community?.close();
    _community = null;
    _httpReasonSharing?.close();
    _ownReasons?.clear(notify: false);
    _httpOrders = null;
    _httpPortfolio = null;
    _httpPaperReset = null;
    _paperReset = null;
    _httpProductProfile = null;
    _httpReasonSharing = null;
    _ownReasons = null;
    _portfolioValuationTimer?.cancel();
    _portfolioBinding = null;
    if (account == null || accountControllerChanged) {
      _portfolioSession.unbind();
    } else {
      _portfolioSession.suspend();
    }
    _latestCompany = null;
    _reasonedOrderIds.clear();
    _portfolioFailure = null;
    _guestDeskRecovery = null;
    _paperPrincipalKey = null;
    _syncReminder();
    _accountEntryFailed = false;
    _accountEntryRunning = false;
    _forgetPendingPromotion();
    _paperOpening = false;
    _portfolioRefreshQueued = false;
    _paperResetApplying = false;
    _portfolioLoading = ready;
    _portfolioGeneration++;
    _orderAccount = account;
    _paperAccountPhase = phase;
    _paperPrincipalHint = principalHint;
    _preservedGuestNoticeAcknowledged = false;
    widget.session.unbindRemote(useLocalFallback: account == null);
    if (account == null) {
      if (_routeIdentity != null) {
        _routeIdentity = null;
        _dismissIdentityBoundRoutes();
      }
      return;
    }
    if (!ready) return;
    _paperOpening = true;
    unawaited(
      _openPaperRepositories(
        account: account,
        phase: phase!,
        principalHint: principalHint!,
        generation: _portfolioGeneration,
      ),
    );
  }

  Future<void> _openPaperRepositories({
    required AccountController account,
    required AccountPhase phase,
    required String principalHint,
    required int generation,
  }) async {
    HttpPaperOrderRepository? orders;
    HttpPaperPortfolioRepository? portfolio;
    HttpPaperResetRepository? paperResetRepository;
    PaperResetController? paperReset;
    HttpProductProfileRepository? productProfile;
    HttpReasonSharingRepository? reasonSharing;
    try {
      final principalKey = await account.paperPrincipalKey();
      if (!mounted ||
          generation != _portfolioGeneration ||
          !identical(account, widget.account) ||
          account.phase != phase ||
          _paperPrincipalHint != principalHint) {
        return;
      }
      if (phase == AccountPhase.active && principalKey != account.accountId) {
        throw const PaperOrderException(PaperOrderFailure.accountRequired);
      }
      _acceptRouteIdentity(phase, principalKey);
      final config = PracticeAccountConfig.fromEnvironment();
      final api = config.apiUri;
      if (!config.enabled || api == null) {
        throw const PaperOrderException(PaperOrderFailure.unavailable);
      }
      orders = HttpPaperOrderRepository(
        client: _http,
        baseUri: api,
        authorization: account.paperAuthorization,
        onGuestSessionFailure: (failure) =>
            _recordGuestSessionFailure(failure, generation),
      );
      portfolio = HttpPaperPortfolioRepository(
        transport: _http,
        baseUri: api,
        authorizationProvider: account.paperAuthorization,
        onGuestSessionFailure: (failure) =>
            _recordGuestSessionFailure(failure, generation),
      );
      paperResetRepository = HttpPaperResetRepository(
        transport: _http,
        baseUri: api,
        authorizationProvider: account.paperAuthorization,
        onGuestSessionFailure: (failure) =>
            _recordGuestSessionFailure(failure, generation),
      );
      paperReset = PaperResetController(
        principalKey: principalKey,
        repository: paperResetRepository,
        store: PreferencesPaperResetMutationStore(widget.preferences),
        mutationId: paperUuidV4,
      );
      try {
        await paperReset.initialize();
      } on PaperResetException {
        // A corrupt pending record blocks reset without blocking the desk.
      }
      productProfile = HttpProductProfileRepository(
        transport: _http,
        baseUri: api,
        authorizationProvider: account.paperAuthorization,
        onGuestSessionFailure: (failure) =>
            _recordGuestSessionFailure(failure, generation),
      );
      reasonSharing = HttpReasonSharingRepository(
        client: _http,
        baseUri: api,
        authorizationProvider: account.paperAuthorization,
        onGuestSessionFailure: (failure) =>
            _recordGuestSessionFailure(failure, generation),
      );
      final cachedPortfolio = PaperPortfolioCache.read(
        widget.preferences,
        principalKey,
      );
      await widget.session.bindRemote(
        principalKey: principalKey,
        repository: productProfile,
        mutationIdFactory: paperUuidV4,
      );
      final restoredPortfolio = await cachedPortfolio;
      if (!mounted ||
          generation != _portfolioGeneration ||
          !identical(account, widget.account) ||
          account.phase != phase) {
        orders.close();
        portfolio.close();
        paperResetRepository.close();
        paperReset.dispose();
        productProfile.close();
        reasonSharing.close();
        return;
      }
      setState(() {
        final binding = _portfolioSession.bind(principalKey);
        _portfolioBinding = binding;
        _paperPrincipalKey = principalKey;
        _syncReminder();
        _httpOrders = orders;
        _httpPortfolio = portfolio;
        _httpPaperReset = paperResetRepository;
        _paperReset = paperReset;
        _httpProductProfile = productProfile;
        _httpReasonSharing = reasonSharing;
        _ownReasons = OwnReasonHistory(reasonSharing!);
        if (phase == AccountPhase.active) {
          _community = CommunityRepository(api, account.paperAuthorization);
        }
        final restore = PaperPortfolioCache.selectForRestore(
          cached: restoredPortfolio,
          current: _portfolioSession.snapshot,
          pendingResetBaseRevision: paperReset!.state.pending?.baseRevision,
        );
        if (restore != null) {
          _portfolioSession.acceptSnapshot(binding, restore);
        }
        _paperOpening = false;
        _portfolioLoading = false;
      });
      _schedulePortfolioValuationExpiry();
      unawaited(
        _career.bind(principalKey: principalKey, repository: orders.career),
      );
      unawaited(
        _missions.bind(principalKey: principalKey, repository: orders.career),
      );
      unawaited(
        _bindCareerDayContext(
          principalKey: principalKey,
          repository: orders.career,
          generation: generation,
        ),
      );
      unawaited(
        _reasonPrivacy.bind(
          principalKey: principalKey,
          repository: reasonSharing,
        ),
      );
      unawaited(_refreshPortfolio());
      if (paperReset.state.hasPendingMutation) {
        unawaited(_resumePendingPaperReset());
      }
    } catch (error) {
      orders?.close();
      portfolio?.close();
      paperResetRepository?.close();
      paperReset?.dispose();
      productProfile?.close();
      reasonSharing?.close();
      if (mounted && generation == _portfolioGeneration) {
        setState(() {
          _paperOpening = false;
          _portfolioLoading = false;
          if (error is GuestSessionException &&
              _isTerminalGuestFailure(error.failure)) {
            _guestDeskRecovery = error.failure;
            _portfolioFailure = null;
          } else {
            _portfolioFailure = error is PaperOrderException
                ? error.failure
                : PaperOrderFailure.unavailable;
          }
        });
      }
    }
  }

  Future<void> _retryPaperDesk() async {
    if (_httpPortfolio != null) {
      await _refreshPortfolio();
      return;
    }
    _syncPaperRepositories();
  }

  Future<void> _resumePendingPaperReset() async {
    try {
      await _performPaperReset(resumePending: true);
    } catch (_) {
      // The exact mutation remains durable after ambiguous failures. Terminal
      // guest failures also flow through the existing recovery screen.
    }
  }

  Future<SettingsPaperResetReceipt> _resetPaperFromSettings() async {
    try {
      final result = await _performPaperReset(resumePending: false);
      final current = _portfolio;
      final currentIsNewer =
          current != null && current.revision > result.receipt.revision;
      return SettingsPaperResetReceipt(
        revision: result.receipt.revision,
        currentRevision: currentIsNewer
            ? current.revision
            : result.receipt.revision,
        paperBalance: _groupPaperBalance(
          currentIsNewer ? current.cashPaper : result.portfolio.cashPaper,
        ),
        resetAt: result.receipt.resetAt,
      );
    } on PaperResetException catch (error) {
      if (error.failure == PaperResetFailure.staleRevision) {
        await _refreshPortfolio();
      }
      throw SettingsPaperResetException(_settingsResetFailure(error.failure));
    } on GuestSessionException {
      throw const SettingsPaperResetException(
        SettingsPaperResetFailure.accountRequired,
      );
    }
  }

  Future<PaperResetResult> _performPaperReset({
    required bool resumePending,
  }) async {
    final controller = _paperReset;
    final repository = _httpPaperReset;
    final orders = _httpOrders;
    final binding = _portfolioBinding;
    final principalKey = _paperPrincipalKey;
    final current = _portfolio;
    final generation = _portfolioGeneration;
    if (controller == null ||
        repository == null ||
        orders == null ||
        binding == null ||
        principalKey == null ||
        current == null ||
        _paperResetApplying ||
        !_portfolioSession.isCurrent(binding)) {
      throw const PaperResetException(PaperResetFailure.unavailable);
    }
    if (controller.state.failure == PaperResetFailure.protectedStorage &&
        !controller.state.hasPendingMutation) {
      throw const PaperResetException(PaperResetFailure.protectedStorage);
    }

    _dismissTradingRoutes();
    setState(() => _paperResetApplying = true);
    try {
      final result = resumePending
          ? await controller.resumePending()
          : await controller.submit(baseRevision: current.revision);
      if (!mounted ||
          generation != _portfolioGeneration ||
          principalKey != _paperPrincipalKey ||
          !identical(controller, _paperReset) ||
          !identical(repository, _httpPaperReset) ||
          !identical(orders, _httpOrders) ||
          !_portfolioSession.isCurrent(binding)) {
        return result;
      }

      final snapshot = result.portfolio.toSnapshot();
      var applied = false;
      setState(() {
        applied = _portfolioSession.acceptResetSnapshot(
          binding,
          snapshot,
          previousRevision: result.receipt.previousRevision,
        );
        if (applied) {
          _latestCompany = null;
          _reasonedOrderIds.clear();
          _portfolioFailure = null;
        }
      });
      if (applied) {
        _portfolioValuationTimer?.cancel();
        orders.invalidateOpenQuotes();
        // A reset starts a new desk cycle, which changes which of the
        // viewer's reasons count as current.
        _ownReasons?.clear();
      }
      var resetFloorPersisted = false;
      try {
        await PaperPortfolioCache.invalidate(
          widget.preferences,
          principalKey,
          minimumRevision: result.receipt.revision,
        );
        final confirmed = _portfolioSession.snapshot;
        if (confirmed != null &&
            confirmed.revision >= result.receipt.revision) {
          await PaperPortfolioCache.write(
            widget.preferences,
            principalKey,
            confirmed,
          );
        }
        resetFloorPersisted = true;
      } catch (_) {
        // Keep the exact reset pending when the durable floor or confirmed
        // current snapshot could not be handled safely.
      }
      if (resetFloorPersisted) {
        try {
          await controller.acknowledgeApplied(result);
        } catch (_) {
          // The reset and its durable revision floor are confirmed. Keeping
          // the exact mutation is safe and lets a later replay clean it up.
        }
      }
      await _refreshPortfolio();
      return result;
    } finally {
      if (mounted &&
          generation == _portfolioGeneration &&
          identical(controller, _paperReset)) {
        setState(() => _paperResetApplying = false);
      }
    }
  }

  SettingsPaperResetFailure _settingsResetFailure(
    PaperResetFailure failure,
  ) => switch (failure) {
    PaperResetFailure.staleRevision => SettingsPaperResetFailure.staleRevision,
    PaperResetFailure.notNeeded => SettingsPaperResetFailure.notNeeded,
    PaperResetFailure.offline => SettingsPaperResetFailure.offline,
    PaperResetFailure.timeout => SettingsPaperResetFailure.timeout,
    PaperResetFailure.accountRequired =>
      SettingsPaperResetFailure.accountRequired,
    PaperResetFailure.rateLimited => SettingsPaperResetFailure.rateLimited,
    PaperResetFailure.unavailable => SettingsPaperResetFailure.unavailable,
    PaperResetFailure.conflict ||
    PaperResetFailure.revisionExhausted ||
    PaperResetFailure.rejected ||
    PaperResetFailure.protectedStorage => SettingsPaperResetFailure.rejected,
  };

  String _groupPaperBalance(String value) {
    final parts = value.split('.');
    final whole = parts.first;
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.length == 1 ? grouped : '$grouped.${parts.last}';
  }

  Future<void> _retryProductProfile() async {
    if (widget.session.remotePrincipalKey != null) {
      await widget.session.retryRemoteRead();
      return;
    }
    final account = widget.account;
    if (account?.phase == AccountPhase.error) {
      await account!.retryConnection();
      if (!mounted || !identical(account, widget.account)) return;
    }
    _syncPaperRepositories();
  }

  Future<void> _startNewGuestDesk() async {
    final account = widget.account;
    if (account == null || !account.canStartNewGuestDesk) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    await account.startNewGuestDesk(observedFailure: _guestRecoveryFailure);
    if (!mounted || !identical(account, widget.account)) return;
    _guestDeskRecovery = null;
    _invalidatePaperIdentity();
  }

  PaperOrderRepository get _orders =>
      _paperDeskReady ? _httpOrders! : const _UnavailablePaperOrderRepository();

  bool get _paperDeskReady =>
      _httpOrders != null &&
      _portfolio != null &&
      !_portfolioLoading &&
      !_paperResetApplying &&
      _portfolioFailure == null;

  String get _paperDeskMessage {
    if (_portfolioLoading || _paperAccountPhase == AccountPhase.initializing) {
      return 'Opening your paper desk.';
    }
    return switch (_portfolioFailure) {
      PaperOrderFailure.offline =>
        'Your paper desk is offline. Check your connection and try again.',
      PaperOrderFailure.timeout =>
        'Your paper desk took too long to open. Try again.',
      PaperOrderFailure.accountRequired =>
        'Your paper desk needs a fresh session. Try again.',
      _ => 'Your paper desk is unavailable. Try again.',
    };
  }

  String? get _careerStatusMessage {
    if (_career.stale) {
      return 'Showing your last confirmed career record. Refresh to update it.';
    }
    return _career.failure == null ? null : _career.message;
  }

  String? get _missionsStatusMessage {
    if (_careerMissionMismatch) {
      return 'Your career changed while missions were loading. Refresh to match them.';
    }
    if (_missions.stale) {
      return 'Showing your last confirmed missions. Refresh to update them.';
    }
    return switch (_missions.failure) {
      CareerFailure.offline =>
        'Your missions are offline. Check your connection and try again.',
      CareerFailure.timeout =>
        'Your missions took too long to open. Try again.',
      CareerFailure.accountRequired =>
        'Your missions need a fresh session. Try again.',
      CareerFailure.rateLimited =>
        'Your missions are refreshing too quickly. Try again shortly.',
      CareerFailure.profileRequired =>
        'Finish setting up your Trimmy profile, then try again.',
      null => null,
      _ => 'Your missions are unavailable. Try again.',
    };
  }

  bool get _careerMissionMismatch {
    final summary = _career.summary;
    final board = _missions.board;
    return summary != null &&
        board != null &&
        (summary.revision != board.revision ||
            summary.rank.id != board.currentRank);
  }

  CareerMissionBoard? get _coherentMissionBoard {
    final summary = _career.summary;
    final board = _missions.board;
    if (summary == null ||
        board == null ||
        summary.revision != board.revision ||
        summary.rank.id != board.currentRank) {
      return null;
    }
    return board;
  }

  Future<void> _refreshPortfolio() async {
    final repository = _httpPortfolio;
    final account = _orderAccount;
    final principalKey = _paperPrincipalKey;
    final binding = _portfolioBinding;
    if (repository == null ||
        account == null ||
        principalKey == null ||
        binding == null ||
        !mounted) {
      return;
    }
    if (_portfolioLoading) {
      _portfolioRefreshQueued = true;
      return;
    }
    _portfolioLoading = true;
    final generation = _portfolioGeneration;
    try {
      if (await account.paperPrincipalKey() != principalKey) {
        _invalidatePaperIdentity();
        return;
      }
      final snapshot = await repository.read();
      if (!mounted ||
          generation != _portfolioGeneration ||
          !identical(repository, _httpPortfolio)) {
        return;
      }
      final currentPrincipalKey = await account.paperPrincipalKey();
      if (!mounted ||
          generation != _portfolioGeneration ||
          !identical(repository, _httpPortfolio)) {
        return;
      }
      if (currentPrincipalKey != principalKey) {
        _invalidatePaperIdentity();
        return;
      }
      var accepted = false;
      setState(() {
        accepted = _portfolioSession.acceptSnapshot(binding, snapshot);
        if (accepted) _portfolioFailure = null;
      });
      if (!accepted) return;
      _schedulePortfolioValuationExpiry();
      unawaited(_resolveHoldingCompanies());
      unawaited(
        PaperPortfolioCache.write(widget.preferences, principalKey, snapshot),
      );
      final resetState = _paperReset?.state;
      if (!_paperResetApplying &&
          resetState?.hasPendingMutation == true &&
          resetState?.failure != PaperResetFailure.rateLimited &&
          resetState?.failure != PaperResetFailure.protectedStorage) {
        unawaited(_resumePendingPaperReset());
      }
      if (snapshot.hasTraded &&
          widget.session.launchStep != ProductLaunchStep.firstTrade &&
          widget.session.profile != null &&
          !widget.session.firstTradeComplete) {
        await _markFirstTrade();
      }
    } catch (error) {
      if (mounted && generation == _portfolioGeneration) {
        setState(() {
          if (error is GuestSessionException &&
              _isTerminalGuestFailure(error.failure)) {
            _guestDeskRecovery = error.failure;
            _portfolioFailure = null;
          } else {
            _portfolioFailure = error is PaperOrderException
                ? error.failure
                : PaperOrderFailure.unavailable;
          }
        });
      }
    } finally {
      if (generation == _portfolioGeneration) {
        _portfolioLoading = false;
        if (mounted) {
          setState(() {});
          _portfolioViewRevision.value++;
        }
        if (_portfolioRefreshQueued) {
          _portfolioRefreshQueued = false;
          unawaited(_refreshPortfolio());
        }
      }
    }
  }

  void _schedulePortfolioValuationExpiry() {
    _portfolioValuationTimer?.cancel();
    final snapshot = _portfolio;
    final binding = _portfolioBinding;
    if (snapshot == null || binding == null) return;
    final now = DateTime.now().toUtc();
    final expiresAt = snapshot.valuation.nextExpiryAfter(now);
    if (expiresAt == null) return;
    _portfolioValuationTimer = Timer(expiresAt.difference(now), () {
      if (!mounted || !_portfolioSession.isCurrent(binding)) return;
      _expirePortfolioValuation();
      unawaited(_refreshPortfolio());
    });
  }

  void _expirePortfolioValuation() {
    final snapshot = _portfolio;
    final binding = _portfolioBinding;
    if (snapshot == null || binding == null) return;
    final current = snapshot.valuation.currentAt(DateTime.now().toUtc());
    if (current.pricedPositionCount == snapshot.valuation.pricedPositionCount) {
      _schedulePortfolioValuationExpiry();
      return;
    }
    if (_portfolioSession.acceptSnapshot(
      binding,
      snapshot.withValuation(current),
    )) {
      if (mounted) setState(() {});
    }
    _schedulePortfolioValuationExpiry();
  }

  void _invalidatePaperIdentity() {
    _dismissIdentityBoundRoutes();
    _career.unbind();
    _missions.unbind();
    _careerDayContext.unbind();
    _reasonPrivacy.unbind();
    _httpOrders?.close();
    _httpPortfolio?.close();
    _httpPaperReset?.close();
    _paperReset?.dispose();
    _httpProductProfile?.close();
    _dailyDesk?.dispose();
    _dailyDesk = null;
    _community?.close();
    _community = null;
    _httpReasonSharing?.close();
    _ownReasons?.clear(notify: false);
    _httpOrders = null;
    _httpPortfolio = null;
    _httpPaperReset = null;
    _paperReset = null;
    _httpProductProfile = null;
    _httpReasonSharing = null;
    _ownReasons = null;
    _portfolioValuationTimer?.cancel();
    _portfolioBinding = null;
    _portfolioSession.unbind();
    _latestCompany = null;
    _reasonedOrderIds.clear();
    _paperPrincipalKey = null;
    _syncReminder();
    _accountEntryFailed = false;
    _accountEntryRunning = false;
    _forgetPendingPromotion();
    _portfolioFailure = null;
    _portfolioLoading = false;
    _paperOpening = false;
    _portfolioRefreshQueued = false;
    _paperResetApplying = false;
    _portfolioGeneration++;
    if (mounted) setState(() {});
    _syncPaperRepositories();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.account?.removeListener(_realPortfolioChanged);
    ProductNotificationPermission.setOnOpenCareer(null);
    _careerDateTimer?.cancel();
    _portfolioValuationTimer?.cancel();
    _market?.removeListener(_marketChanged);
    _market?.dispose();
    _marketFacts?.dispose();
    _httpStockFacts?.close();
    _stockFactsTransport?.close();
    _career.removeListener(_careerChanged);
    _career.dispose();
    _missions.removeListener(_careerChanged);
    _missions.dispose();
    _careerDayContext.removeListener(_careerDayContextChanged);
    _careerDayContext.dispose();
    _reasonPrivacy.removeListener(_reasonPrivacyChanged);
    _reasonPrivacy.dispose();
    _httpOrders?.close();
    _httpPortfolio?.close();
    _httpPaperReset?.close();
    _paperReset?.dispose();
    _httpProductProfile?.close();
    _dailyDesk?.dispose();
    _dailyDesk = null;
    _community?.close();
    _community = null;
    _httpReasonSharing?.close();
    _ownReasons?.clear(notify: false);
    _portfolioSession.unbind();
    _portfolioGeneration++;
    _http.close();
    _portfolioViewRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      // Session and repository initialization run while the one-time splash
      // plays. Delay mounting Welcome so its entrance begins when visible.
      if (widget.holdStartupPresentation) return const SizedBox.expand();
      final account = widget.account;
      final phase = account?.phase;
      if (_needsAccountChoice && phase != AccountPhase.initializing) {
        _entryAccountGateOpen = true;
        return ProductSignInScreen(
          key: const ValueKey('startup-sign-in-gate'),
          controller: account,
          configurationFailed: widget.accountConfigurationFailed,
          entryGate: true,
          onLater: _continueAsGuest,
        );
      }
      if (account != null) {
        final guestRecovery = _guestRecoveryFailure;
        if (phase == AccountPhase.guest && guestRecovery != null) {
          return GuestDeskRecoveryScreen(
            failure: guestRecovery,
            onSignIn: account.canSignIn
                ? () => _openSignIn(expiredGuestRecovery: true)
                : null,
            onStartNew: _startNewGuestDesk,
          );
        }
        final bound =
            _paperPrincipalKey != null &&
            widget.session.remoteBoundTo(_paperPrincipalKey!);
        final loading =
            phase == AccountPhase.initializing ||
            phase == AccountPhase.connecting ||
            _paperOpening ||
            widget.session.remoteLoading;
        if (!bound || !widget.session.remoteProfileUsable) {
          return _ProductProfileUnavailable(
            loading: loading,
            message: loading
                ? 'Opening your Trimmy profile.'
                : widget.session.loadIssue ??
                      'Your Trimmy profile is unavailable. Try again.',
            onRetry: _retryProductProfile,
          );
        }
        if (phase == AccountPhase.active &&
            account.hasPreservedGuestDesk &&
            !_preservedGuestNoticeAcknowledged) {
          return GuestDeskPreservedScreen(
            expired: account.hasExpiredGuestDesk,
            onContinue: () =>
                setState(() => _preservedGuestNoticeAcknowledged = true),
          );
        }
      }
      if (_signedIn &&
          _skipIntroAfterAuth &&
          widget.session.launchStep != ProductLaunchStep.app) {
        if (!_accountEntryRunning && !_accountEntryFailed) {
          _accountEntryRunning = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _completeSignedInEntry(),
          );
        }
        return _ProductProfileUnavailable(
          loading: !_accountEntryFailed,
          message: _accountEntryFailed
              ? 'Your account is connected. Try opening your desk again.'
              : 'Opening your desk.',
          onRetry: () async {
            setState(() => _accountEntryFailed = false);
          },
        );
      }
      final profile = widget.session.profile;
      return switch (widget.session.launchStep) {
        ProductLaunchStep.onboarding => ProductIntroduction(
          showWelcomeNote: true,
          onContinue: widget.session.beginIntroduction,
          onSkip: widget.session.skipIntroduction,
          onHaveAccount: _openSignIn,
        ),
        ProductLaunchStep.firstTrade => _firstTradePage(),
        ProductLaunchStep.firstPosition ||
        ProductLaunchStep.dayOne ||
        ProductLaunchStep.saveDesk => _firstStockFollowup(),
        ProductLaunchStep.app => _shell(profile!),
      };
    },
  );

  Future<void> _continueAsGuest() async {
    if (_acceptingGuest) return;
    _acceptingGuest = true;
    try {
      if (!await widget.preferences.setBool(guestChoiceKey, true)) {
        throw StateError('GUEST_CHOICE_NOT_SAVED');
      }
      if (mounted) {
        setState(() {
          _guestAccessApproved = true;
          _entryAccountGateOpen = false;
        });
      }
    } catch (_) {
      if (mounted) _message('Couldn’t save your choice. Try again.');
    } finally {
      _acceptingGuest = false;
    }
  }

  Future<void> _startFirstStockFollowup() async {
    final generation = _portfolioGeneration;
    final principal = _paperPrincipalKey ?? 'local';
    if (_career.summary?.firstConfirmedBuy == null && _latestReceipt == null) {
      await _career.refresh();
    }
    if (!mounted || generation != _portfolioGeneration) {
      throw StateError('INTRODUCTION_PRINCIPAL_CHANGED');
    }
    final orderId =
        _career.summary?.firstConfirmedBuy?.orderId ?? _latestReceipt?.orderId;
    if (orderId == null) throw StateError('CONFIRMED_ORDER_REQUIRED');
    await FirstStockFollowup.acknowledgeCelebration(
      widget.preferences,
      principal,
      orderId,
    );
    if (!mounted || generation != _portfolioGeneration) {
      throw StateError('INTRODUCTION_PRINCIPAL_CHANGED');
    }
    await widget.session.markFirstTradeComplete();
    if (mounted) setState(() {});
  }

  Widget _firstStockFollowup() {
    final first = _career.summary?.firstConfirmedBuy;
    final receipt = _latestReceipt;
    final company = first == null
        ? _latestCompany
        : _knownCompany(first.assetId);
    final symbol = first?.symbol ?? company?.symbol;
    final shares = first?.displayQuantity ?? receipt?.filledShares;
    if (symbol == null || shares == null) {
      return _CareerUnavailable(
        message: 'Opening your first stock.',
        loading: _career.loading,
        onRetry: _retryFirstPositionEvidence,
      );
    }
    final principal = _paperPrincipalKey ?? 'local';
    return FirstStockFollowup(
      key: ValueKey('first-stock-setup:$principal'),
      preferences: widget.preferences,
      principal: principal,
      name: company?.name ?? symbol,
      symbol: symbol,
      shares: shares,
      logoUrl: company?.logoUrl,
      orderId: first?.orderId ?? receipt?.orderId,
      amount: receipt?.filledPaper,
      initialStep: widget.session.launchStep == ProductLaunchStep.saveDesk
          ? 2
          : widget.session.launchStep == ProductLaunchStep.dayOne
          ? 1
          : 0,
      onCelebrationContinue: _startFirstStockFollowup,
      onFinish: (addMoney) async {
        await widget.session.finishIntroduction();
        if (mounted && addMoney) await _openFunding();
      },
    );
  }

  Future<void> _retryFirstPositionEvidence() async {
    await Future.wait<void>([_career.refresh(), _retryPaperDesk()]);
  }

  void _ensureDailyDesk() {
    final account = widget.account;
    if (_dailyDesk != null ||
        account == null ||
        _paperPrincipalKey == null ||
        _httpOrders == null) {
      return;
    }
    final api = PracticeAccountConfig.fromEnvironment().apiUri;
    if (api == null) return;
    final controller = WorkdayController(
      WorkdayRepository(api, account.paperAuthorization),
    );
    _dailyDesk = controller;
    scheduleMicrotask(controller.refresh);
  }

  Future<void> _openDailyDesk(String assignmentId) async {
    final controller = _dailyDesk;
    if (controller?.journey?.find(assignmentId) == null) return;
    final generation = _portfolioGeneration;
    final finished = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkdayScreen(
          assignmentId: assignmentId,
          controller: controller!,
          onCompleted: () async {
            if (!mounted || generation != _portfolioGeneration) return;
            await Future.wait([_career.refresh(), _missions.refresh()]);
          },
        ),
      ),
    );
    if (finished == true && mounted && generation == _portfolioGeneration) {
      _shellKey.currentState?.select(ProductTab.desk);
    }
  }

  Widget _shell(OnboardingProfile profile) {
    _ensureDailyDesk();
    if (_reminderCareerPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_reminderCareerPending ||
            _needsAccountChoice ||
            widget.session.launchStep != ProductLaunchStep.app) {
          return;
        }
        final shell = _shellKey.currentState;
        if (shell == null) return;
        _reminderCareerPending = false;
        Navigator.of(context).popUntil((route) => route.isFirst);
        shell.select(ProductTab.floor);
      });
    }
    return ProductShell(
      key: _shellKey,
      onTabChanged: _productTabChanged,
      desk: !_realMoney && _portfolio == null && _latestReceipt == null
          ? _PaperDeskUnavailable(
              message: _paperDeskMessage,
              loading:
                  _portfolioLoading ||
                  _paperAccountPhase == AccountPhase.initializing ||
                  _paperAccountPhase == AccountPhase.connecting,
              onRetry: _retryPaperDesk,
            )
          : DeskScreen(
              snapshot: _deskSnapshot(profile),
              real: _realMoney,
              onSwitchMode: _switchMoneyMode,
              realBalance: realCashBalance(widget.account),
              realSolBalance: realSolBalance(widget.account),
              realBalanceNote:
                  widget.account?.portfolioState?.portfolioIsFresh == true
                  ? 'USDC available'
                  : 'Updating balance…',
              realHoldings: RealHoldings(
                account: widget.account,
                logoForAsset: (holding) =>
                    _knownCompany(holding.assetId)?.logoUrl,
                onAddMoney: _openFunding,
                onAsset: (holding) => unawaited(
                  _openAssetId(holding.assetId, variantMint: holding.mint),
                ),
                onExplore: _openFastBuy,
              ),
              dailyDesk: _dailyDesk == null
                  ? null
                  : WorkdayEntry(
                      controller: _dailyDesk!,
                      onOpen: _openDailyDesk,
                    ),
              persona: profile.persona,
              statusMessage: _realMoney
                  ? null
                  : _portfolioFailure != null && _career.stale
                  ? 'Showing your last confirmed paper desk and career record. Trading is paused until Trimmy reconnects.'
                  : _portfolioFailure != null
                  ? 'Showing your last confirmed paper desk. Trading is paused until Trimmy reconnects.'
                  : _career.stale
                  ? 'Showing your last confirmed career record. Refresh to update it.'
                  : null,
              onRetry: _portfolioFailure == null && !_career.stale
                  ? null
                  : () {
                      unawaited(_retryPaperDesk());
                      unawaited(_career.refresh());
                    },
              onOpenMarket: () =>
                  _shellKey.currentState?.select(ProductTab.market),
              onFastBuy: _openFastBuy,
              onOpenCareer: () =>
                  _shellKey.currentState?.select(ProductTab.floor),
              onChoosePersona: profile.persona == null ? _openPersona : null,
              onOpenProfile: () =>
                  _shellKey.currentState?.select(ProductTab.profile),
              onSignIn: _signedIn ? null : _openSignIn,
              onAddMoney: _openFunding,
              onOpenHolding: (holding) =>
                  unawaited(_openAssetId(holding.assetId)),
              onOpenPortfolio: _openHistory,
              onInbox: _signedIn
                  ? () => _openCommunity(scope: 'notifications')
                  : null,
              onRefresh: () async {
                await Future.wait([
                  if (_dailyDesk != null) _dailyDesk!.refresh(),
                  if (_realMoney)
                    _refreshRealPortfolio()
                  else
                    _retryPaperDesk(),
                  _career.refresh(),
                  _missions.refresh(),
                ]);
                if (mounted) setState(() => _communityEpoch++);
              },
              activity: _realMoney
                  ? null
                  : DeskActivity(
                      key: ValueKey(
                        'desk-activity-$_paperPrincipalKey-$_communityEpoch',
                      ),
                      orders: _portfolio?.recentOrders ?? const [],
                      community: _community,
                      onCommunity: _signedIn ? _openCommunity : _openSignIn,
                      onOpenAsset: (id) => unawaited(_openAssetId(id)),
                    ),
            ),
      market: _marketPage(),
      floor: FloorScreen(
        key: ValueKey('career-${_career.principalKey}'),
        dailyDesk: _dailyDesk == null
            ? null
            : CareerWorld(controller: _dailyDesk!, onOpen: _openDailyDesk),
        personaId: profile.persona?.id,
        principalKey: _career.principalKey,
        activityWeekLoader: _career.activityWeek,
        signedIn: _signedIn,
        career: _career.summary,
        careerLoading: _career.loading && !_career.hasConfirmedSummary,
        careerMessage: _careerStatusMessage,
        missions: _coherentMissionBoard,
        missionsLoading: _missions.loading && !_missions.hasConfirmedBoard,
        missionsMessage: _missionsStatusMessage,
        onRetryCareer: _career.failure == null ? null : _refreshCareer,
        onRetryMissions: _missions.failure == null && !_careerMissionMismatch
            ? null
            : _refreshCareer,
        onOpenMission:
            _career.stale || _missions.stale || _careerMissionMismatch
            ? null
            : _openCareerMission,
        promotion: _missions.lastPromotion,
        promotionLoading: _promotionPreparing || _missions.promoting,
        onPromote: _career.stale || _missions.stale ? null : _promoteCareer,
        onSignIn: _signedIn
            ? () => _message('Your desk is already saved.')
            : _openSignIn,
        onOpenMarket: () => _shellKey.currentState?.select(ProductTab.market),
      ),
      profile: ProfileScreen(
        handle: profile.handle ?? '',
        persona: profile.persona?.label ?? '',
        signedIn: _signedIn,
        career: _career.summary,
        careerMessage: _careerStatusMessage,
        onRetryCareer: () => unawaited(_career.refresh()),
        onSettings: _openSettings,
        onSignIn: _openSignIn,
        onChangePersona: _openPersona,
        onOpenCareer: () => _shellKey.currentState?.select(ProductTab.floor),
      ),
    );
  }

  Widget _firstTradePage() {
    final generation = _portfolioGeneration;
    final principalKey = _paperPrincipalKey;
    final repository = _httpOrders;
    return FirstPaperTradePage(
      key: ValueKey('first-paper-trade:$principalKey'),
      companies: _market?.starterCompanies ?? const [],
      repository: _paperDeskReady ? repository : null,
      availablePaper: _portfolio?.cashPaper,
      clientOrderId: paperUuidV4,
      loading:
          _market?.starterStatus == MarketPageStatus.loading ||
          _portfolioLoading,
      message: !_paperDeskReady ? _paperDeskMessage : _market?.starterMessage,
      onRetry: () async {
        await Future.wait<void>([
          if (_market != null) _market!.loadStarterPicks(),
          _retryPaperDesk(),
        ]);
      },
      onConfirmed: (receipt) {
        final company = _knownCompany(receipt.assetId);
        if (company == null) return;
        _orderConfirmed(
          company,
          receipt,
          generation: generation,
          principalKey: principalKey,
          repository: repository,
        );
      },
      onFinished: _startFirstStockFollowup,
      onExit: widget.session.skipIntroduction,
    );
  }

  Widget _marketPage({bool firstTrade = false}) {
    final market = _market;
    if (market == null) {
      return const Scaffold(body: Center(child: TrimmyLiquidMark(size: 112)));
    }
    return FoundationMarketPage(
      companies: market.companies,
      searchGateway: market.search,
      recents: market.recents,
      following: widget.account?.followedStocksController,
      initialList: MarketList.all,
      resolveCompany: market.findCompany,
      onSignIn: _openSignIn,
      total: market.total,
      hasMore: market.hasMore,
      loadingMore: market.loadingMore,
      loadMoreMessage: market.loadMoreMessage,
      onLoadMore: market.loadMore,
      status: market.status,
      statusMessage: market.message,
      onRetry: () async {
        await market.loadCatalog();
        await _retryPaperDesk();
      },
      onRefresh: () async {
        await market.loadCatalog();
        await _retryPaperDesk();
      },
      intro: firstTrade
          ? _FirstTradePrompt(
              ready: _paperDeskReady,
              message: _paperDeskMessage,
              onRetry: _retryPaperDesk,
            )
          : null,
      onOpenCompany: _openCompany,
    );
  }

  Future<void> _switchMoneyMode() async {
    final mode = MoneyModeScope.of(context);
    if (mode == null) return;
    if (!mode.real && !_signedIn) await _openSignIn();
    if (!mounted || !_signedIn) return;
    ReviewFeedback.shared.press(selection: true);
    await mode.select(!mode.real);
    if (mode.real) {
      unawaited(_refreshLiveCapabilities());
      unawaited(_refreshRealPortfolio());
    }
  }

  Future<void> _openLiveAsset(
    MarketCompany company, {
    bool sell = false,
  }) async {
    if (!_realMoney || !_signedIn || widget.account == null) return;
    final account = widget.account;
    final generation = _portfolioGeneration;
    final origin = PracticeAccountConfig.fromEnvironment().apiUri;
    if (origin == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: productSquircle(30),
      clipBehavior: Clip.antiAlias,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .91,
        child: LiveOrderFlow(
          account: widget.account!,
          origin: origin,
          company: company,
          initialSell: sell,
          onBack: () => Navigator.pop(sheet),
          onAddMoney: _openFunding,
        ),
      ),
    );
    if (mounted &&
        identical(account, widget.account) &&
        generation == _portfolioGeneration &&
        _signedIn &&
        _realMoney) {
      await _refreshRealPortfolio();
    }
  }

  Future<void> _openFunding() async {
    if (!_signedIn) await _openSignIn();
    if (!mounted || !_signedIn || widget.account == null) return;
    final mode = MoneyModeScope.of(context);
    if (mode != null && !mode.real) await mode.select(true);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: productSquircle(30),
      builder: (_) => FundWalletSheet(account: widget.account!),
    );
    if (mounted) await _refreshRealPortfolio();
  }

  Future<void> _openFastBuy() async {
    final market = _market;
    if (market == null) return;
    if (!_realMoney && (_httpOrders == null || _portfolio == null)) {
      await _retryPaperDesk();
    }
    if (!mounted) return;
    if (!_realMoney &&
        (_httpOrders == null || _portfolio == null || _paperResetApplying)) {
      _message('Your desk is reconnecting. Try again in a moment.');
      return;
    }
    final generation = _portfolioGeneration;
    final principalKey = _paperPrincipalKey;
    final repository = _httpOrders;
    ReviewFeedback.shared.press();
    await showModalBottomSheet<PaperOrderReceipt>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      showDragHandle: false,
      shape: productSquircle(30),
      clipBehavior: Clip.antiAlias,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: .91,
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: FastBuySheet(
              gateway: market.search,
              loadAvailableCompanies: _realMoney
                  ? _availableLiveCompanies
                  : null,
              canSelect: _realMoney
                  ? (company) =>
                        _liveCapabilities?.enabled == true &&
                        _liveCapabilities?.forCompany(company) != null
                  : null,
              companies: market.companies.isEmpty
                  ? market.starterCompanies
                  : market.companies,
              orderBuilder: (company, back) =>
                  _realMoney && widget.account != null
                  ? LiveOrderFlow(
                      account: widget.account!,
                      origin: PracticeAccountConfig.fromEnvironment().apiUri!,
                      company: company,
                      onBack: back,
                      onAddMoney: _openFunding,
                    )
                  : PaperOrderFlow(
                      key: ValueKey('fast-buy-${company.assetId}'),
                      company: company,
                      side: PaperOrderSide.buy,
                      repository: _orders,
                      clientOrderId: paperUuidV4,
                      availablePaper:
                          _latestReceipt?.cashAfterPaper ??
                          _portfolio?.cashPaper ??
                          '0',
                      availableShares:
                          _portfolio
                              ?.positionFor(
                                company.assetId,
                                variantMint: company.primaryVariant?.mint,
                              )
                              ?.quantity ??
                          '0',
                      referencePrice: company.priceUsd,
                      onBackToSearch: back,
                      reasonCaptureAvailable: _paperDeskReady,
                      onConfirmed: (receipt) => _orderConfirmed(
                        company,
                        receipt,
                        generation: generation,
                        principalKey: principalKey,
                        repository: repository,
                      ),
                      onReasonSaved: (saved) => _reasonSaved(
                        saved,
                        generation: generation,
                        principalKey: principalKey,
                        repository: repository,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    if (mounted && generation == _portfolioGeneration && _realMoney) {
      await _refreshRealPortfolio();
    }
  }

  Future<void> _openCompany(MarketCompany company) async {
    if (_realMoney) unawaited(_refreshLiveCapabilities());
    final generation = _portfolioGeneration;
    final principalKey = _paperPrincipalKey;
    final orderRepository = _httpOrders;
    final route = MaterialPageRoute<PaperOrderReceipt>(
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: _portfolioViewRevision,
        builder: (context, revision, _) {
          // Keep an already-open asset route aligned with mode changes made in Settings.
          MoneyModeScope.of(context);
          final liveAsset = _liveCapabilities?.forCompany(company);
          final selectedCompany = _realMoney && liveAsset != null
              ? company.withVariant(liveAsset.mint)
              : company;
          final liveHolding = realWalletHoldings(widget.account)
              ?.holdingForMint(
                liveAsset?.mint ?? company.primaryVariant?.mint ?? '',
              );
          final primaryMint = selectedCompany.primaryVariant?.mint;
          final receipt =
              _latestReceipt?.assetId == company.assetId &&
                  _latestReceipt?.variantMint == primaryMint
              ? _latestReceipt
              : null;
          final persisted = _portfolio?.positionFor(
            company.assetId,
            variantMint: company.primaryVariant?.mint,
          );
          final position = receipt != null
              ? pendingMarketPosition(receipt)
              : persisted == null
              ? null
              : confirmedMarketPosition(
                  portfolio: _portfolio!,
                  position: persisted,
                  now: DateTime.now().toUtc(),
                );
          return CompanyStockPage(
            details: MarketStockDetails(
              company: selectedCompany,
              position: _realMoney ? null : position,
              versions: company.asset.variants.map(_version).toList(),
            ),
            orderRepository: _orders,
            clientOrderId: paperUuidV4,
            availablePaper:
                _latestReceipt?.cashAfterPaper ?? _portfolio?.cashPaper ?? '0',
            availableShares: _realMoney
                ? liveHolding == null
                      ? '0'
                      : liveDecimal(
                          liveHolding.availableToTradeRaw,
                          liveHolding.decimals,
                        )
                : receipt?.positionShares ?? persisted?.quantity ?? '0',
            realPositionLabel: liveHolding == null
                ? null
                : '${liveHolding.displayAmount ?? liveHolding.rawTokenUnits} ${liveHolding.symbol}',
            onRetryTrading: _realMoney && _liveCapabilitiesFailed
                ? () => unawaited(_refreshLiveCapabilities())
                : null,
            recentOrders: _realMoney
                ? const []
                : _portfolio?.recentOrders ?? const [],
            researchController: _market!.controller,
            factsController: _marketFacts,
            following: widget.account?.followedStocksController,
            reasonSharing: _httpReasonSharing,
            ownReasons: _ownReasons,
            reasonPrivacy: _reasonPrivacy.bound ? _reasonPrivacy : null,
            relationships: widget.account?.relationshipsController,
            onOpenSettings: () => unawaited(_openSettings()),
            onOrderConfirmed: (confirmed) => _orderConfirmed(
              company,
              confirmed,
              generation: generation,
              principalKey: principalKey,
              repository: orderRepository,
            ),
            onReasonSaved: (saved) => _reasonSaved(
              saved,
              generation: generation,
              principalKey: principalKey,
              repository: orderRepository,
            ),
            reasonCaptureAvailable: _paperDeskReady,
            onRealTrade: _realMoney
                ? (side) =>
                      _openLiveAsset(company, sell: side == PaperOrderSide.sell)
                : null,
            tradingAvailable: _realMoney
                ? _liveCapabilities?.enabled == true && liveAsset != null
                : _paperDeskReady,
            tradingMessage: _realMoney
                ? _liveCapabilitiesFailed
                      ? 'Trading could not connect.'
                      : _liveCapabilities == null
                      ? 'Checking trading…'
                      : !_liveCapabilities!.enabled
                      ? 'Trading is temporarily paused.'
                      : liveAsset == null
                      ? 'This stock isn’t available to trade yet.'
                      : null
                : _paperDeskReady
                ? null
                : _paperDeskMessage,
          );
        },
      ),
    );
    _companyRoute = route;
    PaperOrderReceipt? result;
    try {
      result = await Navigator.of(context).push<PaperOrderReceipt>(route);
    } finally {
      if (identical(_companyRoute, route)) _companyRoute = null;
    }
    if (result != null) {
      _orderConfirmed(
        company,
        result,
        generation: generation,
        principalKey: principalKey,
        repository: orderRepository,
      );
    }
  }

  MarketVersionInfo _version(StockVariant variant) => MarketVersionInfo(
    symbol: variant.symbol ?? variant.label ?? variant.variantId,
    issuer: variant.issuer ?? 'Issuer unavailable',
    mint: variant.mint,
    backingDisclosure: 'Backing details are not available in this market read.',
    tradingHours: 'Trades on chain. Issuer hours are unavailable.',
    status: variant.advisory == null
        ? MarketVersionStatus.unknown
        : switch (variant.advisory!.status) {
            StockAdvisoryStatus.blocked => MarketVersionStatus.paused,
            StockAdvisoryStatus.caution ||
            StockAdvisoryStatus.compromised => MarketVersionStatus.risky,
            StockAdvisoryStatus.unknown => MarketVersionStatus.unknown,
          },
  );

  void _orderConfirmed(
    MarketCompany company,
    PaperOrderReceipt receipt, {
    required int generation,
    required String? principalKey,
    required HttpPaperOrderRepository? repository,
  }) {
    if (!_ownsPaperIdentity(
          generation: generation,
          principalKey: principalKey,
          repository: repository,
        ) ||
        receipt.assetId != company.assetId ||
        receipt.variantMint != company.primaryVariant?.mint ||
        receipt.side != PaperOrderSide.buy &&
            receipt.side != PaperOrderSide.sell) {
      return;
    }
    if (!_portfolioSession.acceptReceipt(_portfolioBinding, receipt)) return;
    setState(() {
      _latestCompany = company;
    });
    if (widget.session.launchStep != ProductLaunchStep.firstTrade &&
        !widget.session.firstTradeComplete) {
      unawaited(_markFirstTrade());
    }
    unawaited(_refreshPortfolio());
    unawaited(_career.refresh());
    unawaited(_missions.refresh());
  }

  bool _ownsPaperIdentity({
    required int generation,
    required String? principalKey,
    required HttpPaperOrderRepository? repository,
  }) =>
      mounted &&
      principalKey != null &&
      generation == _portfolioGeneration &&
      principalKey == _paperPrincipalKey &&
      identical(repository, _httpOrders);

  void _reasonSaved(
    PaperReasonReceipt saved, {
    required int generation,
    required String? principalKey,
    required HttpPaperOrderRepository? repository,
  }) {
    if (!_ownsPaperIdentity(
      generation: generation,
      principalKey: principalKey,
      repository: repository,
    )) {
      return;
    }
    _reasonedOrderIds.add(saved.orderId);
    _ownReasons?.invalidate(
      assetId: saved.assetId,
      variantMint: saved.variantMint,
    );
    unawaited(_career.refresh());
    unawaited(_missions.refresh());
  }

  void _dismissIdentityBoundRoutes() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.maybeOf(context)?.popUntil((candidate) => candidate.isFirst);
    });
  }

  void _dismissTradingRoutes() {
    final companyRoute = _companyRoute;
    final reasonRoute = _reasonRoute;
    if (companyRoute == null && reasonRoute == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(companyRoute, _companyRoute) ||
          !identical(reasonRoute, _reasonRoute)) {
        return;
      }
      Navigator.maybeOf(context)?.popUntil((candidate) => candidate.isFirst);
    });
  }

  void _acceptRouteIdentity(AccountPhase phase, String principalKey) {
    final next = '${phase.name}:$principalKey';
    final previous = _routeIdentity;
    _routeIdentity = next;
    if (previous != null && previous != next) {
      _dismissIdentityBoundRoutes();
    }
  }

  void _productTabChanged(ProductTab tab) {
    if (_dailyDesk != null) unawaited(_dailyDesk!.refresh());
    if (tab == ProductTab.desk) {
      if (_realMoney) unawaited(_refreshRealPortfolio());
      unawaited(_refreshPortfolio());
      unawaited(_career.refresh());
      unawaited(_missions.refresh());
      return;
    }
    if (tab == ProductTab.floor || tab == ProductTab.profile) {
      unawaited(_career.refresh());
      unawaited(_missions.refresh());
    }
  }

  void _refreshCareer() {
    unawaited(_career.refresh());
    unawaited(_missions.refresh());
  }

  void _openCareerMission(CareerMission mission) {
    if (_realMoney) {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: productSquircle(30),
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A simulator assignment',
                  style: Theme.of(sheet).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text('Complete this task on your training desk.'),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(sheet);
                    await MoneyModeScope.of(context)?.select(false);
                    if (mounted) _openCareerMission(mission);
                  },
                  child: const Text('Open training desk'),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    if (_career.stale ||
        _missions.stale ||
        mission.status != CareerMissionStatus.ready) {
      return;
    }
    final currentMission = _coherentMissionBoard?.missions
        .where((candidate) => candidate.id == mission.id)
        .firstOrNull;
    if (currentMission?.status != CareerMissionStatus.ready) return;
    if (mission.id == CareerMissionId.writeAReason) {
      if (_reasonedOrderIds.isNotEmpty) {
        _message('Your saved reason is being checked. Refresh your Career.');
        unawaited(_missions.refresh());
        return;
      }
      final portfolio = _portfolio;
      if (!_paperDeskReady || portfolio == null) {
        _message(
          'Your confirmed paper desk must be online before you can write this reason.',
        );
        unawaited(_retryPaperDesk());
        return;
      }
      final target =
          selectPaperReasonTarget(
            portfolio: portfolio,
            firstConfirmedBuy: _career.summary?.firstConfirmedBuy,
            excludedOrderIds: _reasonedOrderIds,
          ) ??
          _pendingBuyReasonTarget(portfolio);
      if (target == null) {
        _shellKey.currentState?.select(ProductTab.market);
        _message(
          'This mission needs a confirmed paper buy you still hold. Choose a stock when you are ready.',
        );
        return;
      }
      unawaited(_openPaperReason(target));
      return;
    }
    _shellKey.currentState?.select(ProductTab.market);
  }

  PaperReasonTarget? _pendingBuyReasonTarget(PaperPortfolioSnapshot portfolio) {
    final receipt = _latestReceipt;
    if (receipt == null ||
        receipt.side != PaperOrderSide.buy ||
        !_positive(receipt.positionShares) ||
        _reasonedOrderIds.contains(receipt.orderId) ||
        portfolio.revision >= receipt.accountRevision) {
      return null;
    }
    return PaperReasonTarget(
      orderId: receipt.orderId,
      assetId: receipt.assetId,
      variantMint: receipt.variantMint,
      symbol: receipt.symbol,
      heldShares: receipt.positionShares,
      confirmedAt: receipt.confirmedAt,
    );
  }

  Future<void> _promoteCareer(CareerMission mission) async {
    if (_promotionPreparing || _missions.promoting) return;
    final generation = _portfolioGeneration;
    final principalKey = _paperPrincipalKey;
    final repository = _httpOrders;
    final summary = _career.summary;
    final board = _coherentMissionBoard;
    final eligible = summary == null || board == null
        ? null
        : eligibleCareerPromotion(summary: summary, board: board);
    if (eligible == null ||
        eligible.id != mission.id ||
        eligible.promotesToRank != mission.promotesToRank ||
        principalKey == null ||
        repository == null ||
        _career.stale ||
        _missions.stale) {
      _message('Refresh the Floor before claiming this promotion.');
      _refreshCareer();
      return;
    }
    final target = eligible.promotesToRank!;
    setState(() => _promotionPreparing = true);
    try {
      final mutationId = await _promotionMutation(
        principalKey: principalKey,
        target: target,
      );
      final currentSummary = _career.summary;
      final currentBoard = _coherentMissionBoard;
      final currentEligible = currentSummary == null || currentBoard == null
          ? null
          : eligibleCareerPromotion(
              summary: currentSummary,
              board: currentBoard,
            );
      if (mutationId == null ||
          currentEligible?.id != mission.id ||
          currentEligible?.promotesToRank != target ||
          !_ownsPaperIdentity(
            generation: generation,
            principalKey: principalKey,
            repository: repository,
          )) {
        if (mounted && mutationId == null) {
          _message('Your promotion could not be prepared. Try again.');
        } else if (mounted && currentEligible == null) {
          _message('Your career changed. Refresh the Floor and try again.');
        }
        return;
      }
      final receipt = await _missions.promote(
        CareerPromotionCommand(mutationId: mutationId, targetRank: target),
      );
      if (!_ownsPaperIdentity(
            generation: generation,
            principalKey: principalKey,
            repository: repository,
          ) ||
          receipt == null) {
        return;
      }
      _completePendingPromotion();
      await _career.refresh();
      if (!mounted ||
          !_ownsPaperIdentity(
            generation: generation,
            principalKey: principalKey,
            repository: repository,
          )) {
        return;
      }
      final navigator = Navigator.of(context);
      await navigator.push<void>(
        MaterialPageRoute(
          builder: (_) =>
              PromotionMoment(receipt: receipt, onContinue: navigator.pop),
        ),
      );
    } finally {
      if (mounted) setState(() => _promotionPreparing = false);
    }
  }

  Future<String?> _promotionMutation({
    required String principalKey,
    required CareerRank target,
  }) async {
    if (_promotionMutationId != null &&
        _promotionPrincipalKey == principalKey &&
        _promotionTarget == target) {
      return _promotionMutationId!;
    }
    final storageKey =
        'trimmy.product.pending-promotion.v1.$principalKey.${target.name}';
    var mutationId = widget.preferences.getString(storageKey);
    if (mutationId != null) {
      try {
        CareerPromotionCommand(mutationId: mutationId, targetRank: target);
      } on CareerException {
        mutationId = null;
      }
    }
    mutationId ??= paperUuidV4();
    try {
      if (widget.preferences.getString(storageKey) != mutationId &&
          !await widget.preferences.setString(storageKey, mutationId)) {
        return null;
      }
    } catch (_) {
      return null;
    }
    _promotionMutationId = mutationId;
    _promotionPrincipalKey = principalKey;
    _promotionStorageKey = storageKey;
    _promotionTarget = target;
    return mutationId;
  }

  void _completePendingPromotion() {
    final storageKey = _promotionStorageKey;
    _forgetPendingPromotion();
    if (storageKey != null) {
      unawaited(_removePromotionMutation(storageKey));
    }
  }

  Future<void> _removePromotionMutation(String storageKey) async {
    try {
      await widget.preferences.remove(storageKey);
    } catch (_) {
      // Replaying a committed mutation is safe and returns the same receipt.
    }
  }

  void _forgetPendingPromotion() {
    _promotionMutationId = null;
    _promotionPrincipalKey = null;
    _promotionStorageKey = null;
    _promotionTarget = null;
  }

  Future<void> _openPaperReason(PaperReasonTarget target) async {
    final generation = _portfolioGeneration;
    final principalKey = _paperPrincipalKey;
    final repository = _httpOrders;
    if (repository == null || principalKey == null || _reasonRoute != null) {
      _message('Your paper desk is still opening. Try again.');
      return;
    }
    var company = _knownCompany(target.assetId);
    if (company?.logoUrl?.isNotEmpty != true) {
      try {
        company = await _market?.findCompany(target.assetId) ?? company;
      } catch (_) {
        // Comment capture remains available when optional artwork is offline.
      }
    }
    if (!mounted ||
        !_ownsPaperIdentity(
          generation: generation,
          principalKey: principalKey,
          repository: repository,
        ) ||
        _reasonRoute != null) {
      return;
    }
    final route = MaterialPageRoute<PaperReasonReceipt>(
      fullscreenDialog: true,
      builder: (_) => PaperReasonFlow(
        target: target,
        company: company,
        repository: repository,
        mutationId: paperUuidV4,
        onSaved: (saved) => _reasonSaved(
          saved,
          generation: generation,
          principalKey: principalKey,
          repository: repository,
        ),
      ),
    );
    _reasonRoute = route;
    try {
      await Navigator.of(context).push<PaperReasonReceipt>(route);
    } finally {
      if (identical(_reasonRoute, route)) _reasonRoute = null;
      if (_ownsPaperIdentity(
        generation: generation,
        principalKey: principalKey,
        repository: repository,
      )) {
        unawaited(_career.refresh());
        unawaited(_missions.refresh());
      }
    }
  }

  Future<void> _markFirstTrade() async {
    try {
      await widget.session.markFirstTradeComplete();
    } catch (_) {
      if (mounted) _message('The trade is safe, but this step was not saved.');
    }
  }

  DeskSnapshot _deskSnapshot(OnboardingProfile profile) {
    final portfolio = _portfolio;
    final receipt = _latestReceipt;
    final career = _career.summary;
    final receiptIsPending = receipt != null;
    if (portfolio?.hasTraded != true && receipt == null) {
      return DeskSnapshot.newRookie(
        handle: profile.handle ?? '',
        wallStreetLine: WallStreetClock.label(DateTime.now()),
        rank: career?.rank.label,
        streak: career?.streak.days,
        trims: career?.trims.total,
      );
    }
    final projection = projectDeskPortfolio(
      portfolio: portfolio,
      pendingReceipt: receiptIsPending ? receipt : null,
      now: DateTime.now().toUtc(),
      assetName: (assetId) => _knownCompany(assetId)?.name,
      assetLogo: (assetId) => _knownCompany(assetId)?.logoUrl,
    );
    return DeskSnapshot(
      handle: profile.handle ?? '',
      paperValue: projection.paperValue,
      paperValueState: projection.valueState,
      wallStreetLine: WallStreetClock.label(DateTime.now()),
      rank: career?.rank.label,
      streak: career?.streak.days,
      trims: career?.trims.total,
      holdings: projection.holdings,
      mission: _coherentMissionBoard?.missions
          .where((m) => m.status != CareerMissionStatus.complete)
          .firstOrNull
          ?.title,
    );
  }

  MarketCompany? _knownCompany(String assetId) {
    MarketCompany? fallback;
    for (final company in [
      ?_latestCompany,
      ..._holdingCompanies.values,
      ...?_market?.companies,
      ...?_market?.starterCompanies,
      ...?_market?.recents.companies,
    ]) {
      if (company.assetId != assetId) continue;
      fallback ??= company;
      if (company.logoUrl?.isNotEmpty == true) return company;
    }
    return fallback;
  }

  Future<void> _resolveHoldingCompanies() async {
    final generation = _portfolioGeneration;
    final ids = <String>{
      ...?_portfolio?.positions.map((p) => p.assetId),
      ...?realWalletHoldings(widget.account)?.stockTokens.map((p) => p.assetId),
    };
    await Future.wait(
      ids.map((id) async {
        if (_knownCompany(id)?.logoUrl != null || !_resolvingHoldings.add(id)) {
          return;
        }
        try {
          final company = await _market?.findCompany(id);
          if (mounted &&
              generation == _portfolioGeneration &&
              company != null) {
            setState(() => _holdingCompanies[id] = company);
          }
        } catch (_) {
          // The next portfolio refresh retries metadata independently of values.
        } finally {
          _resolvingHoldings.remove(id);
        }
      }),
    );
  }

  Future<void> _openAssetId(String id, {String? variantMint}) async {
    final generation = _portfolioGeneration;
    try {
      final company = _knownCompany(id) ?? await _market?.findCompany(id);
      if (!mounted || generation != _portfolioGeneration) return;
      if (company == null) {
        _message('This stock couldn’t open. Try again.');
        return;
      }
      await _openCompany(
        variantMint == null ? company : company.withVariant(variantMint),
      );
    } catch (_) {
      if (mounted) _message('This stock couldn’t open. Try again.');
    }
  }

  void _openHistory() {
    if (_realMoney) {
      final account = widget.account;
      final origin = PracticeAccountConfig.fromEnvironment().apiUri;
      if (!_signedIn || account == null) {
        unawaited(_openSignIn());
        return;
      }
      if (origin == null) {
        _message('History couldn’t connect. Try again.');
        return;
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (pageContext) => LiveTradeHistoryScreen(
            account: account,
            origin: origin,
            onBack: () => Navigator.pop(pageContext),
            logoForAsset: (assetId, mint) => _knownCompany(assetId)?.logoUrl,
            onOpenAsset: (assetId, mint) =>
                _openAssetId(assetId, variantMint: mint),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('History'),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: DeskActivity(
              orders: _portfolio?.recentOrders ?? const [],
              preview: false,
              onOpenAsset: (id) => unawaited(_openAssetId(id)),
            ),
          ),
        ),
      ),
    );
  }

  void _openCommunity({String scope = 'everyone'}) {
    final repository = _community;
    if (repository == null) {
      unawaited(_openSignIn());
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CommunityScreen(
          repository: repository,
          initialScope: scope,
          onOpenAsset: (id) => unawaited(_openAssetId(id)),
          onReport: widget.account?.relationshipsController == null
              ? null
              : (post) async {
                  final done = await widget.account!.relationshipsController!
                      .reportReason(
                        reasonId: post.id,
                        category: ReasonReportCategory.other,
                      );
                  if (mounted && !done) {
                    _message('Report didn’t send. Try again.');
                  }
                },
          onBlock: widget.account?.relationshipsController == null
              ? null
              : (post) async {
                  final done = await widget.account!.relationshipsController!
                      .setBlocked(
                        socialId: post.socialId,
                        blocked: true,
                        knownHandle: post.handle,
                      );
                  if (mounted && !done) {
                    _message('Couldn’t block this trader. Try again.');
                  }
                },
        ),
      ),
    );
  }

  Future<void> _completeSignedInEntry() async {
    final generation = _portfolioGeneration;
    try {
      await widget.session.enterSignedInApp();
    } catch (_) {
      if (mounted && generation == _portfolioGeneration) {
        setState(() => _accountEntryFailed = true);
      }
    } finally {
      if (mounted && generation == _portfolioGeneration) {
        setState(() => _accountEntryRunning = false);
      }
    }
  }

  Future<void> _openSignIn({bool expiredGuestRecovery = false}) async {
    _skipIntroAfterAuth = widget.session.launchStep == ProductLaunchStep.app;
    var finished = false;
    void close() {
      if (finished || !mounted) return;
      finished = true;
      final navigator = Navigator.maybeOf(context);
      if (navigator?.canPop() == true) navigator!.pop();
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductSignInScreen(
          controller: widget.account,
          configurationFailed: widget.accountConfigurationFailed,
          expiredGuestRecovery: expiredGuestRecovery,
          onLater: close,
          onSignedIn: close,
        ),
      ),
    );
  }

  Future<void> _openPersona() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            PersonaPickerPage(onChoose: widget.session.choosePersona),
      ),
    );
  }

  Future<void> _openSettings() async {
    final generation = _portfolioGeneration;
    final account = widget.account;
    final principalKey = _paperPrincipalKey;
    final portfolio = account?.portfolioRepository;
    if (_signedIn && portfolio != null) {
      try {
        await portfolio.refresh();
      } catch (_) {
        // The screen keeps wallet details explicitly unavailable.
      }
    }
    if (!mounted ||
        generation != _portfolioGeneration ||
        !identical(account, widget.account) ||
        principalKey != _paperPrincipalKey ||
        widget.session.profile == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ListenableBuilder(
          listenable: Listenable.merge([
            ReviewFeedback.shared,
            widget.session,
            if (widget.account != null) widget.account!,
          ]),
          builder: (context, _) => ProductSettingsScreen(
            onSoundChanged: (value) =>
                unawaited(ReviewFeedback.shared.setSound(value)),
            onHapticsChanged: (value) =>
                unawaited(ReviewFeedback.shared.setHaptics(value)),
            onChangePersona: _openPersona,
            onMoney: () => unawaited(_openFunding()),
            onReminderPreferences: () {
              final principal = _paperPrincipalKey ?? 'local';
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (pageContext) => ReminderPreferencePage(
                    preferences: widget.preferences,
                    principal: principal,
                    onDone: () async {
                      if (pageContext.mounted) Navigator.pop(pageContext);
                    },
                  ),
                ),
              );
            },
            onHelp: () => _openInformation(ProductInformation.contact),
            onTerms: () => _openInformation(ProductInformation.terms),
            onPrivacy: () => _openInformation(ProductInformation.privacy),
            state: _settingsState(),
            reasonPrivacy: _reasonPrivacy.bound ? _reasonPrivacy : null,
            onSignIn: _openSignIn,
            onSignOut: _signedIn
                ? () => unawaited(_signOutFromSettings())
                : null,
            onWalletCopy: (address) => unawaited(
              Clipboard.setData(ClipboardData(text: address)).then((_) {
                if (mounted) _message('Wallet address copied.');
              }),
            ),
            onWalletExport: _walletRecoveryUri == null
                ? null
                : () => unawaited(_openWalletRecovery()),
            onCloseAccount: widget.account?.canCloseAccount == true
                ? () => unawaited(_confirmCloseAccount())
                : null,
            onResetPaper:
                _paperReset != null &&
                    _portfolio != null &&
                    (_paperReset?.state.failure !=
                            PaperResetFailure.protectedStorage ||
                        _paperReset?.state.hasPendingMutation == true)
                ? _resetPaperFromSettings
                : null,
          ),
        ),
      ),
    );
  }

  void _openInformation(ProductInformation information) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProductInformationScreen(information: information),
      ),
    );
  }

  ProductSettingsState _settingsState() {
    final profile = widget.session.profile!;
    final paperLimit = int.tryParse(_career.summary?.rank.paperLimit ?? '');
    final wallet =
        widget.account?.portfolioState?.context?.embeddedSolanaWallet;
    final walletAddress = wallet?.isCandidate == true ? wallet!.address : null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ProductSettingsState(
      account: SettingsAccountState(
        signedIn: _signedIn,
        handle: profile.handle == null ? '' : '@${profile.handle}',
        persona: profile.persona?.label ?? '',
      ),
      notifications: const {},
      quietHours: const SettingsQuietHours(
        enabled: false,
        startLabel: '10:00 PM',
        endLabel: '7:00 AM',
        available: false,
      ),
      appearance: SettingsAppearanceState(
        soundEnabled: ReviewFeedback.shared.sound,
        hapticsEnabled: ReviewFeedback.shared.haptics,
        animationsEnabled: !reduceMotion,
        systemReduceMotionEnabled: reduceMotion,
        languageLabel: 'English',
      ),
      paper: SettingsPaperState(
        limit: paperLimit ?? 10000,
        resetAvailable:
            _paperReset != null &&
            _portfolio != null &&
            (_paperReset?.state.failure != PaperResetFailure.protectedStorage ||
                _paperReset?.state.hasPendingMutation == true),
        resetPending: _paperReset?.state.hasPendingMutation == true,
      ),
      money: SettingsMoneyState(
        availability: _signedIn
            ? SettingsFeatureAvailability.available
            : SettingsFeatureAvailability.unavailable,
      ),
      wallet: SettingsWalletState(
        availability: walletAddress == null
            ? SettingsFeatureAvailability.unavailable
            : SettingsFeatureAvailability.available,
        address: walletAddress,
      ),
    );
  }

  Future<void> _signOutFromSettings() async {
    _guestAccessApproved = false;
    _entryAccountGateOpen = true;
    _skipIntroAfterAuth = false;
    await widget.preferences.remove(guestChoiceKey);
    await widget.account?.signOut();
    if (!mounted) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator?.canPop() == true) navigator!.pop();
  }

  Future<void> _confirmCloseAccount() async {
    final close = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close your account?'),
        content: Text(
          widget
                      .account
                      ?.portfolioState
                      ?.context
                      ?.embeddedSolanaWallet
                      .isCandidate !=
                  true
              ? 'You will lose access to the saved account. Records that must be kept stay protected.'
              : 'Keep access to your wallet before closing your account. Closing will not move its funds. You will lose access to your saved desk.',
        ),
        actions: [
          if (_walletRecoveryUri != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
                unawaited(_openWalletRecovery());
              },
              child: const Text('Back up wallet'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ProductColor.loss),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close account'),
          ),
        ],
      ),
    );
    if (close != true) return;
    await widget.account?.closeAccount();
    if (!mounted) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator?.canPop() == true) navigator!.pop();
  }

  Uri? get _walletRecoveryUri {
    if (!_signedIn) return null;
    final wallet =
        widget.account?.portfolioState?.context?.embeddedSolanaWallet;
    if (wallet?.isCandidate != true || wallet?.address == null) return null;
    return walletRecoveryLink(
      const String.fromEnvironment('TRIMMY_WALLET_RECOVERY_URL'),
      wallet!.address!,
    );
  }

  Future<void> _openWalletRecovery() async {
    final uri = _walletRecoveryUri;
    if (uri == null) return;
    final generation = _portfolioGeneration;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Never log the browser session or credentials. The page authenticates
      // independently; only the expected public address leaves this app.
    }
    if (mounted && generation == _portfolioGeneration) {
      _message('Couldn’t open wallet backup. Try again.');
    }
  }

  void _message(String text) {
    showProductNotice(context, text);
  }
}

class _FirstTradePrompt extends StatelessWidget {
  const _FirstTradePrompt({
    required this.ready,
    required this.message,
    required this.onRetry,
  });

  final bool ready;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => ProductCard(
    color: ProductColor.paperRaised,
    radius: 26,
    padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
    child: Row(
      children: [
        const ProductMotionIcon(
          file: 'goal-chart-animated.png',
          animatedFile: 'goal-chart-animated.gif',
          size: 48,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ready ? 'Pick a company. Your first trade is free.' : message,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              if (!ready) ...[
                const SizedBox(height: 5),
                TextButton(
                  key: const ValueKey('first-trade-paper-retry'),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProductProfileUnavailable extends StatelessWidget {
  const _ProductProfileUnavailable({
    required this.message,
    required this.loading,
    required this.onRetry,
  });
  final String message;
  final bool loading;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => ProductStatePage(
    artwork: TrimmyLiquidMark(size: 112, animate: loading),
    title: loading ? 'Opening Trimmy' : 'Couldn’t open Trimmy',
    message: loading ? null : 'Try again to pick up where you left off.',
    actions: [
      if (!loading) ProductButton(label: 'Try again', onPressed: onRetry),
    ],
  );
}

class _PaperDeskUnavailable extends StatelessWidget {
  const _PaperDeskUnavailable({
    required this.message,
    required this.loading,
    required this.onRetry,
  });
  final String message;
  final bool loading;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => ProductStatePage(
    artwork: loading
        ? const TrimmyLiquidMark(size: 112)
        : const ProductMotionIcon(
            file: 'nav-plumpy-desk.png',
            animatedFile: 'nav-plumpy-desk.gif',
            size: 96,
          ),
    title: loading ? 'Opening your desk' : 'Couldn’t open your desk',
    message: loading ? null : message,
    actions: [
      if (!loading) ProductButton(label: 'Try again', onPressed: onRetry),
    ],
  );
}

class _CareerUnavailable extends StatelessWidget {
  const _CareerUnavailable({
    required this.message,
    required this.loading,
    required this.onRetry,
  });
  final String message;
  final bool loading;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => ProductStatePage(
    artwork: loading
        ? const TrimmyLiquidMark(size: 112)
        : const ProductMotionIcon(
            file: 'goal-chart-animated.png',
            animatedFile: 'goal-chart-animated.gif',
            size: 96,
          ),
    title: loading ? 'Opening your trade' : 'Couldn’t load your trade',
    message: loading ? null : 'Try again to see your confirmed order.',
    actions: [
      if (!loading) ProductButton(label: 'Try again', onPressed: onRetry),
    ],
  );
}

final class _UnavailablePaperOrderRepository implements PaperOrderRepository {
  const _UnavailablePaperOrderRepository();

  @override
  Future<PaperOrderQuote> quote(PaperOrderIntent intent) =>
      Future.error(const PaperOrderException(PaperOrderFailure.unavailable));

  @override
  Future<PaperReasonReceipt> saveReason(PaperOrderReason reason) =>
      Future.error(const CareerException(CareerFailure.unavailable));

  @override
  Future<PaperOrderReceipt> submit(PaperOrderSubmission submission) =>
      Future.error(const PaperOrderException(PaperOrderFailure.unavailable));
}

bool _positive(String value) =>
    (_paperMicros(value) ?? BigInt.zero) > BigInt.zero;

BigInt? _paperMicros(String raw) {
  final value = raw.replaceAll(',', '');
  if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,6})?$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('.');
  final fraction = (parts.length == 2 ? parts[1] : '').padRight(6, '0');
  return BigInt.parse(parts.first) * BigInt.from(1000000) +
      BigInt.parse(fraction.isEmpty ? '0' : fraction);
}
