import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../account/account_amounts.dart';
import '../../account/account_controller.dart';
import '../../account/account_data_models.dart';
import '../../ui_review/review_animated_splash.dart';
import '../design/product_components.dart';
import '../design/product_notice.dart';
import '../design/product_success_mark.dart';
import '../design/product_theme.dart';
import '../money/real_holdings.dart';
import 'live_trading.dart';
import 'market_craft.dart';
import 'market_models.dart';
import '../../l10n/l10n.dart';

class LiveOrderFailure implements Exception {
  const LiveOrderFailure(this.code);
  final String code;

  /// What went wrong, in the reader's language. The server's code stays the
  /// same in every language.
  String message(AppLocalizations l10n) => switch (code) {
    'ADD_USDC' => l10n.liveOrderErrorAddUsdc,
    'ADD_SOL' => l10n.liveOrderErrorAddSol,
    'INSUFFICIENT_HOLDINGS' => l10n.liveOrderErrorInsufficientHoldings,
    'TRADE_LIMIT' => l10n.liveOrderErrorTradeLimit,
    'APP_UPDATE_REQUIRED' => l10n.liveOrderErrorAppUpdate,
    'TERMS_REQUIRED' => l10n.liveOrderErrorTermsRequired,
    'WALLET_REQUIRED' => l10n.liveOrderErrorWalletRequired,
    'ORDER_PENDING' => l10n.liveOrderErrorOrderPending,
    'QUOTE_EXPIRED' => l10n.liveOrderErrorQuoteExpired,
    'LIVE_BUSY' => l10n.liveOrderErrorBusy,
    'NO_ROUTE' => l10n.liveOrderErrorNoRoute,
    'MARKET_CLOSED' => l10n.liveOrderErrorMarketClosed,
    'BELOW_MINIMUM' => l10n.liveOrderErrorBelowMinimum,
    'PRICE_OFF_MARKET' => l10n.liveOrderErrorPriceOffMarket,
    'FEE_TOO_HIGH' => l10n.liveOrderErrorFeeTooHigh,
    'ACCOUNT_REQUIRED' => l10n.liveOrderErrorAccountRequired,
    'INVALID_REVIEW' || 'INVALID_SIGNATURE' => l10n.liveOrderErrorFreshQuote,
    'LIVE_UNAVAILABLE' => l10n.liveOrderErrorUnavailable,
    _ => l10n.liveOrderErrorGeneric,
  };
}

/// A notice on the order screen, written when it is shown so it follows the
/// current language.
typedef _NoticeText =
    String Function(AppLocalizations l10n, AppFormats formats);

_NoticeText _failureNotice(LiveOrderFailure failure) =>
    (l10n, _) => failure.message(l10n);

/// Eligibility ticks per account, issuer and terms version. They are held for
/// the app session and saved, so the same terms are not asked for again. A
/// new terms version needs a new tick.
abstract final class LiveIssuerTerms {
  static final Map<String, Set<String>> _accepted = {};

  static String _key(String account) => 'trimmy.issuer-terms.v1.$account';

  static String _entry(LiveTradingIssuer issuer) =>
      jsonEncode([issuer.issuerId, issuer.attestation.version]);

  static bool accepted(String account, LiveTradingIssuer issuer) =>
      _accepted[account]?.contains(_entry(issuer)) ?? false;

  /// Adds this account's saved ticks to the session.
  static Future<void> restore(String account) async {
    final saved = (await SharedPreferences.getInstance()).getStringList(
      _key(account),
    );
    (_accepted[account] ??= {}).addAll(saved ?? const []);
  }

  /// Updates the session at once, then saves. A failed save still leaves
  /// the choice in place for this session.
  static Future<void> record(
    String account,
    LiveTradingIssuer issuer,
    bool accepted,
  ) async {
    final entries = _accepted[account] ??= {};
    if (accepted) {
      entries.add(_entry(issuer));
    } else {
      entries.remove(_entry(issuer));
    }
    await (await SharedPreferences.getInstance()).setStringList(
      _key(account),
      entries.toList()..sort(),
    );
  }

  @visibleForTesting
  static void resetSession() => _accepted.clear();
}

class LiveOrderClient {
  LiveOrderClient(this.origin, this.account, {http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _identity = account.accountId,
      _epoch = account.navigationEpoch {
    if (origin.scheme != 'https' || origin.userInfo.isNotEmpty) {
      throw ArgumentError('HTTPS required');
    }
  }
  final Uri origin;
  final AccountController account;
  final String? _identity;
  final int _epoch;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;
  bool get current =>
      !_closed &&
      _identity != null &&
      account.accountId == _identity &&
      account.navigationEpoch == _epoch &&
      account.phase == AccountPhase.active;
  void close() {
    _closed = true;
    if (_ownsClient) _client.close();
  }

  Future<LiveTradingCapabilities> capabilities() async {
    final value = await fetchLiveTradingCapabilities(origin, client: _client);
    if (!current) throw const LiveOrderFailure('ACCOUNT_REQUIRED');
    return value;
  }

  Future<Map<String, dynamic>?> request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (!current) throw const LiveOrderFailure('ACCOUNT_REQUIRED');
    final token = await account.freshAccessToken();
    if (!current || token.accountId != _identity) {
      throw const LiveOrderFailure('ACCOUNT_REQUIRED');
    }
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            origin.resolve('/v1/trading/$path'),
          )
          ..followRedirects = false
          ..headers.addAll({
            'authorization': 'Bearer ${token.token}',
            'accept': 'application/json',
          });
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 45),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 32768) {
        throw const LiveOrderFailure('LIVE_UNAVAILABLE');
      }
    }
    if (!current) throw const LiveOrderFailure('ACCOUNT_REQUIRED');
    final decoded = jsonDecode(utf8.decode(bytes)) as Map;
    if (response.statusCode != 200) {
      throw LiveOrderFailure(decoded['code'] as String? ?? 'LIVE_UNAVAILABLE');
    }
    final order = decoded['order'];
    if (order == null) return null;
    if (order is! Map ||
        order['id'] is! String ||
        !const {
          'reviewed',
          'pending',
          'confirmed',
          'failed',
          'expired',
        }.contains(order['status'])) {
      throw const LiveOrderFailure('LIVE_UNAVAILABLE');
    }
    final terms = order['terms'];
    bool raw(Object? value) =>
        value is String && RegExp(r'^(?:0|[1-9][0-9]{0,19})$').hasMatch(value);
    bool mint(Object? value) =>
        value is String &&
        RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(value);
    final fees = terms is Map ? terms['platformFeeBps'] : null;
    final confirmedSlot = order['confirmedSlot'];
    if (terms is! Map ||
        !const {'buy', 'sell'}.contains(terms['side']) ||
        !mint(terms['inputMint']) ||
        !mint(terms['outputMint']) ||
        !raw(terms['inputAmountRaw']) ||
        !raw(terms['quotedOutputAmountRaw']) ||
        !raw(terms['minimumOutputAmountRaw']) ||
        !raw(terms['totalLamportsUpperBound']) ||
        fees is! int ||
        fees < 0 ||
        fees > 10000 ||
        (confirmedSlot != null &&
            (confirmedSlot is! int ||
                confirmedSlot < 1 ||
                confirmedSlot > 9007199254740991)) ||
        order['wallet'] is! String ||
        order['expiresAt'] is! String ||
        DateTime.tryParse(order['expiresAt'] as String) == null ||
        (order['signature'] != null && order['signature'] is! String) ||
        (order['status'] == 'reviewed' &&
            (order['transaction'] is! String ||
                order['reviewDigest'] is! String))) {
      throw const LiveOrderFailure('LIVE_UNAVAILABLE');
    }
    return Map<String, dynamic>.from(order);
  }
}

class LiveOrderFlow extends StatefulWidget {
  const LiveOrderFlow({
    super.key,
    required this.account,
    required this.origin,
    required this.onBack,
    required this.onAddMoney,
    this.company,
    this.variantMint,
    this.initialSell = false,
    this.httpClient,
  });
  final MarketCompany? company;

  /// The exact token chosen for this order. When it stops being tradeable
  /// the flow says so instead of trading another issuer's token.
  final String? variantMint;
  final bool initialSell;
  final AccountController account;
  final Uri origin;
  final VoidCallback onBack;
  final Future<void> Function() onAddMoney;

  /// A supplied transport is caller-owned. Production creates its own client.
  final http.Client? httpClient;
  @override
  State<LiveOrderFlow> createState() => _LiveOrderFlowState();
}

class _LiveOrderFlowState extends State<LiveOrderFlow>
    with WidgetsBindingObserver {
  late final _client = LiveOrderClient(
    widget.origin,
    widget.account,
    client: widget.httpClient,
  );
  final _amount = TextEditingController(text: '5');
  final _termsKey = GlobalKey();
  Map<String, dynamic>? _order;
  LiveTradingCapabilities? _capabilities;
  Timer? _poll, _noticeTimer, _quoteTimer;
  // The message sits below the form; a new one is scrolled into view.
  final _noticeKey = GlobalKey();
  bool _busy = false, _checking = true, _sell = false;
  bool _restoring = false, _recoveryFailed = false, _capabilitiesFailed = false;
  bool _foreground = true, _polling = false, _initialAmountSet = false;
  bool _fundingNeeded = false;
  _NoticeText? _error;
  String? _uncertainId;

  /// A preset writes rounded shares into the field. Its exact raw amount is
  /// kept, so Max sells everything without leaving dust behind.
  ({String text, String raw})? _preset;

  /// The preset that the order limit cut down: 100 for Max, or 25, 50, 75.
  int? _cappedPercent;
  late final _pendingKey =
      'trimmy.pending-live-order.${widget.account.accountId}';

  LiveTradingAsset? get _asset {
    final capabilities = _capabilities;
    if (capabilities == null) return null;
    final company = widget.company, mint = widget.variantMint;
    if (company == null) {
      // Only an offered issuer's token ever gets a tick or a trade button.
      final tradeable = capabilities.tradeableAssets;
      return mint == null
          ? tradeable.firstOrNull
          : tradeable.where((asset) => asset.mint == mint).firstOrNull;
    }
    final variants = capabilities.variantsFor(company);
    final preferred = mint ?? company.primaryVariant?.mint;
    return variants.where((asset) => asset.mint == preferred).firstOrNull ??
        (mint == null ? variants.firstOrNull : null);
  }

  LiveTradingIssuer? get _issuer =>
      _asset == null ? null : _capabilities!.issuerFor(_asset!);

  bool get _termsAccepted {
    final issuer = _issuer, account = widget.account.accountId;
    return issuer != null &&
        account != null &&
        LiveIssuerTerms.accepted(account, issuer);
  }

  LiveTradingAsset? get _orderAsset {
    final terms = _order?['terms'];
    if (terms is! Map) return null;
    return _capabilities?.forMint(
      terms[terms['side'] == 'buy' ? 'outputMint' : 'inputMint'] as String?,
    );
  }

  AccountHoldingsSnapshot? get _holdings => realWalletHoldings(widget.account);
  WalletStockBalance? get _holding =>
      _asset == null ? null : _holdings?.holdingForMint(_asset!.mint);
  BigInt? get _balanceRaw => _holdings == null
      ? null
      : BigInt.tryParse(
          _sell
              ? (_holding?.availableToTradeRaw ?? '0')
              : _holdings!.usdc.availableToTradeRaw,
        );
  BigInt get _limitRaw =>
      BigInt.parse(_sell ? _asset!.maxSellInputRaw : _asset!.maxBuyInputRaw);
  BigInt? get _maxRaw {
    final balance = _balanceRaw;
    if (balance == null || _asset == null) return null;
    return balance < _limitRaw ? balance : _limitRaw;
  }

  String get _symbol => _asset?.symbol ?? widget.company?.symbol ?? 'token';

  LiveShareScale get _scale =>
      liveShareScale(widget.account, _asset!.mint, _asset!.decimals);

  /// USDC for buys, shares of the token for sells, grouped for reading in
  /// the reader's language.
  String _amountLabel(BigInt raw, AppFormats formats) => _sell
      ? '${formats.number(_scale.label(raw.toString()))} $_symbol'
      : '${formats.number(_usdc(raw.toString()))} USDC';

  static String _usdc(String raw) =>
      formatRawUnits(raw, 6) ?? liveDecimal(raw, 6);

  /// The raw amount this order sends. A preset keeps its exact amount while
  /// the field still shows what the preset wrote.
  String? get _enteredRaw {
    final text = _amount.text.trim();
    final preset = _preset;
    if (preset != null && preset.text == text) return preset.raw;
    // A comma typed as the decimal mark reads as the same exact amount.
    final plain = context.formats.normalizeDecimalInput(text);
    return _sell ? _scale.raw(plain) : liveAmountRaw(plain, 6);
  }

  bool get _pending => _order?['status'] == 'pending';

  @override
  void initState() {
    super.initState();
    _sell = widget.initialSell;
    _amount.text = _sell ? '' : '5';
    widget.account.addListener(_accountChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restore());
  }

  void _accountChanged() {
    if (mounted) {
      if (!_client.current) {
        _poll?.cancel();
        _quoteTimer?.cancel();
        setState(() {
          _order = null;
          _error = _failureNotice(const LiveOrderFailure('ACCOUNT_REQUIRED'));
        });
        return;
      }
      _setInitialAmount();
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.account.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _noticeTimer?.cancel();
    _quoteTimer?.cancel();
    _client.close();
    _amount.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _poll?.cancel();
      return;
    }
    if (_pending) unawaited(_check());
    unawaited(widget.account.refreshPortfolio().catchError((Object _) {}));
    _expireQuote();
  }

  bool get _reviewing =>
      _order?['status'] == 'reviewed' &&
      _order?['terms'] is Map &&
      _orderAsset != null;

  void _editAmount() {
    _quoteTimer?.cancel();
    setState(() => _order = null);
  }

  /// Back steps from a reviewed quote to the amount, keeping what was typed,
  /// and closes the sheet from anywhere else.
  void _back() {
    if (_busy) return;
    if (_reviewing) return _editAmount();
    widget.onBack();
  }

  void _notice(_NoticeText message) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(() => _error = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notice = _noticeKey.currentContext;
      if (notice == null || !notice.mounted) return;
      Scrollable.ensureVisible(
        notice,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
    _noticeTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _error = null);
    });
  }

  Future<void> _remember(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = id == null
        ? await prefs.remove(_pendingKey)
        : await prefs.setString(_pendingKey, id);
    if (!saved) throw const LiveOrderFailure('LIVE_UNAVAILABLE');
    _uncertainId = id;
  }

  Future<void> _refreshBalance() async {
    try {
      await widget.account.refreshPortfolio();
    } catch (_) {
      /* Next foreground refresh retries. */
    }
  }

  Future<void> _refreshConfirmedBalance(Map<String, dynamic> order) async {
    try {
      await widget.account.refreshPortfolioAfterTrade(
        confirmedSlot: order['confirmedSlot'] as int?,
      );
    } catch (_) {
      // Confirmation remains valid; the account keeps holdings explicitly stale.
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    _restoring = true;
    setState(() {
      _checking = true;
      _recoveryFailed = false;
      _capabilitiesFailed = false;
    });
    Future<void> readOrder() async {
      try {
        _uncertainId = (await SharedPreferences.getInstance()).getString(
          _pendingKey,
        );
        final order = await _client.request(
          _uncertainId == null ? 'order' : 'order/$_uncertainId',
        );
        if (order == null && _uncertainId != null) {
          throw const LiveOrderFailure('ORDER_PENDING');
        }
        if (!mounted) return;
        if (order?['status'] == 'pending' || _uncertainId != null) {
          setState(
            () => _order = order?['status'] == 'reviewed'
                ? {...order!, 'status': 'pending'}
                : order,
          );
          if (_pending) {
            _schedule();
          } else {
            await _remember(null);
            if (order?['status'] == 'confirmed') {
              await _refreshConfirmedBalance(order!);
            }
          }
        }
      } catch (_) {
        if (mounted) setState(() => _recoveryFailed = true);
      }
    }

    Future<void> readCapabilities() async {
      try {
        final capabilities = await _client.capabilities();
        if (mounted) setState(() => _capabilities = capabilities);
      } catch (_) {
        if (mounted) setState(() => _capabilitiesFailed = true);
      }
    }

    Future<void> readTerms() async {
      final account = widget.account.accountId;
      if (account == null) return;
      try {
        await LiveIssuerTerms.restore(account);
      } catch (_) {
        // Unreadable storage only means the terms are asked for again.
      }
    }

    await Future.wait([
      readOrder(),
      readCapabilities(),
      _refreshBalance(),
      readTerms(),
    ]);
    if (mounted) {
      _setInitialAmount();
      setState(() => _checking = false);
    }
    _restoring = false;
  }

  /// Writes [raw] into the field as USDC or shares, in the reader's decimal
  /// mark, and keeps it exact.
  void _fill(BigInt raw) {
    _amount.text = context.formats.decimalInput(
      _sell ? _scale.shares(raw.toString()) : liveDecimal(raw.toString(), 6),
    );
    _preset = (text: _amount.text, raw: raw.toString());
  }

  void _setInitialAmount() {
    if (_initialAmountSet || _asset == null) return;
    final max = _maxRaw;
    // A zero/unknown first snapshot may predate the buy or deposit. Keep the
    // untouched field eligible for autofill when the verified balance arrives.
    if (max == null || max <= BigInt.zero) return;
    _initialAmountSet = true;
    if (_sell) {
      _fill(max);
      _cappedPercent = _balanceRaw! > _limitRaw ? 100 : null;
    } else if (max < BigInt.from(5000000)) {
      _fill(max);
    }
  }

  void _selectPercent(int percent) {
    final balance = _balanceRaw;
    if (balance == null || _asset == null) return;
    final portion = balance * BigInt.from(percent) ~/ BigInt.from(100);
    final capped = portion > _limitRaw;
    _initialAmountSet = true;
    setState(() {
      _fill(capped ? _limitRaw : portion);
      _cappedPercent = capped ? percent : null;
    });
  }

  void _typed(String _) {
    _initialAmountSet = true;
    if (_cappedPercent != null && _preset?.text != _amount.text.trim()) {
      setState(() => _cappedPercent = null);
    }
  }

  void _switchSide() {
    setState(() {
      _sell = !_sell;
      _error = null;
      _fundingNeeded = false;
      _initialAmountSet = false;
      _preset = null;
      _cappedPercent = null;
      _amount.text = _sell ? '' : '5';
      _setInitialAmount();
    });
  }

  void _setTerms(bool accepted) {
    final issuer = _issuer, account = widget.account.accountId;
    if (issuer == null || account == null) return;
    unawaited(
      LiveIssuerTerms.record(
        account,
        issuer,
        accepted,
      ).catchError((Object _) {}),
    );
    setState(() {});
  }

  void _showTerms() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _termsKey.currentContext;
      if (!mounted || target == null) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignment: .2,
          duration: productDuration(context, 280),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  /// The server wants a fresh tick, usually because the issuer's terms
  /// changed. Clear the old one, reread the terms and return to the checkbox.
  Future<void> _termsRequired(LiveTradingIssuer issuer) async {
    final account = widget.account.accountId;
    if (account != null) {
      try {
        await LiveIssuerTerms.record(account, issuer, false);
      } catch (_) {
        // The session already forgot the tick.
      }
    }
    if (!mounted) return;
    setState(() {});
    _showTerms();
    try {
      final capabilities = await _client.capabilities();
      if (mounted) setState(() => _capabilities = capabilities);
    } catch (_) {
      // Keep the last read. The next quote is checked by the server again.
    }
  }

  Future<void> _preview() async {
    final asset = _asset, issuer = _issuer;
    if (_busy ||
        asset == null ||
        issuer == null ||
        _capabilities?.enabled != true ||
        _recoveryFailed) {
      return;
    }
    // Close the keyboard first, so a message about the amount is not hidden under it.
    FocusScope.of(context).unfocus();
    if (!_termsAccepted) {
      _notice((l10n, _) => l10n.liveOrderConfirmTermsFirst);
      _showTerms();
      return;
    }
    final raw = _enteredRaw;
    if (raw == null) {
      _notice(
        (l10n, _) =>
            _sell ? l10n.liveOrderInvalidShares : l10n.liveOrderInvalidUsdc,
      );
      return;
    }
    final limit = _limitRaw;
    if (BigInt.parse(raw) > limit) {
      _notice(
        (l10n, formats) =>
            l10n.liveOrderUpToPerOrder(_amountLabel(limit, formats)),
      );
      return;
    }
    final minimum = BigInt.parse(asset.minBuyInputRaw);
    if (!_sell && BigInt.parse(raw) < minimum) {
      _notice(
        (l10n, formats) =>
            l10n.liveOrderMinimum(_amountLabel(minimum, formats)),
      );
      return;
    }
    if (!asset.marketOpen) {
      final market = asset.market!;
      _notice(
        (l10n, formats) => l10n.liveOrderMarketNotice(
          market.label(DateTime.now(), l10n, formats),
        ),
      );
      return;
    }
    final legacy = _capabilities!.legacy;
    setState(() {
      _busy = true;
      _error = null;
      _fundingNeeded = false;
    });
    try {
      await _refreshBalance();
      if (!mounted || !_client.current) return;
      final balance = _balanceRaw;
      if (widget.account.portfolioState?.portfolioIsFresh == true &&
          balance != null &&
          BigInt.parse(raw) > balance) {
        throw LiveOrderFailure(_sell ? 'INSUFFICIENT_HOLDINGS' : 'ADD_USDC');
      }
      final order = await _client.request('preview', {
        'assetId': asset.assetId,
        'variantMint': asset.mint,
        'side': _sell ? 'sell' : 'buy',
        'amountRaw': raw,
        // Issuer-aware servers require the tick. Older servers reject any
        // field they do not know, and they list only xStocks.
        if (!legacy)
          'termsAccepted': {
            'issuerId': issuer.issuerId,
            'version': issuer.attestation.version,
          },
      });
      final terms = order?['terms'];
      if (order == null ||
          order['status'] != 'reviewed' ||
          terms is! Map ||
          terms['side'] != (_sell ? 'sell' : 'buy') ||
          terms['inputAmountRaw'] != raw ||
          terms['inputMint'] != (_sell ? asset.mint : liveUsdcMint) ||
          terms['outputMint'] != (_sell ? liveUsdcMint : asset.mint)) {
        throw const LiveOrderFailure('INVALID_REVIEW');
      }
      if (mounted) {
        setState(() => _order = order);
        _watchQuote();
      }
    } on LiveOrderFailure catch (error) {
      if (mounted && (error.code == 'ADD_USDC' || error.code == 'ADD_SOL')) {
        setState(() => _fundingNeeded = true);
      }
      _notice(_failureNotice(error));
      if (error.code == 'TERMS_REQUIRED') await _termsRequired(issuer);
      if (error.code == 'ORDER_PENDING') await _restore();
    } catch (_) {
      _notice((l10n, _) => l10n.liveOrderQuoteFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _watchQuote() {
    _quoteTimer?.cancel();
    final expiry = DateTime.tryParse(_order?['expiresAt'] as String? ?? '');
    if (expiry == null) {
      _expireQuote();
      return;
    }
    final delay = expiry.difference(DateTime.now().toUtc());
    _quoteTimer = Timer(delay.isNegative ? Duration.zero : delay, _expireQuote);
  }

  void _expireQuote() {
    if (!mounted || _order?['status'] != 'reviewed' || _busy) return;
    final expiry = DateTime.tryParse(_order?['expiresAt'] as String? ?? '');
    if (expiry == null || !DateTime.now().toUtc().isBefore(expiry)) {
      setState(() => _order = {..._order!, 'status': 'expired'});
    }
  }

  Future<void> _confirm() async {
    final order = _order;
    if (order == null || _busy || order['status'] != 'reviewed') {
      return;
    }
    final expiry = DateTime.tryParse(order['expiresAt'] as String? ?? '');
    if (expiry == null || !DateTime.now().toUtc().isBefore(expiry)) {
      _expireQuote();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var dispatchStarted = false;
    try {
      final signed = await widget.account.signReviewedStockTransaction(
        wallet: order['wallet'] as String,
        transaction: order['transaction'] as String,
        expiresAt: expiry,
      );
      if (!mounted || !_client.current) return;
      await _remember(order['id'] as String);
      dispatchStarted = true;
      final result = await _client.request('execute', {
        'id': order['id'],
        'reviewDigest': order['reviewDigest'],
        'signedTransaction': signed,
      });
      if (result == null || result['id'] != order['id']) {
        throw const LiveOrderFailure('LIVE_UNAVAILABLE');
      }
      if (!mounted) return;
      setState(
        () => _order = result['status'] == 'reviewed'
            ? {...result, 'status': 'pending'}
            : result,
      );
      if (_pending) {
        _schedule();
      } else {
        await _remember(null);
      }
      if (result['status'] == 'confirmed') {
        await _refreshConfirmedBalance(result);
      }
    } catch (_) {
      if (!mounted) return;
      if (dispatchStarted) {
        setState(() => _order = {...order, 'status': 'pending'});
        _notice((l10n, _) => l10n.liveOrderCheckingResult);
        _schedule();
      } else {
        _notice((l10n, _) => l10n.liveOrderSigningFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _expireQuote();
      }
    }
  }

  void _schedule() {
    _poll?.cancel();
    if (_foreground && mounted) {
      _poll = Timer(const Duration(seconds: 3), () => unawaited(_check()));
    }
  }

  Future<void> _check() async {
    if (_polling || !_pending || !_foreground) return;
    _polling = true;
    final id = _order!['id'];
    try {
      final result = await _client.request('order/$id');
      if (!mounted || id != _order?['id']) return;
      if (result == null || result['id'] != id) {
        throw const LiveOrderFailure('ORDER_PENDING');
      }
      setState(() {
        _order = result['status'] == 'reviewed' && _uncertainId != null
            ? {...result, 'status': 'pending'}
            : result;
        _error = null;
      });
      if (!_pending) {
        await _remember(null);
        if (result['status'] == 'confirmed') {
          await _refreshConfirmedBalance(result);
        }
      }
    } catch (_) {
      _notice((l10n, _) => l10n.liveOrderReconnecting);
    } finally {
      _polling = false;
      if (mounted && _pending) _schedule();
    }
  }

  Future<void> _openTerms(LiveTradingIssuer issuer) async {
    try {
      if (!await launchUrl(
        issuer.termsUrl,
        mode: LaunchMode.externalApplication,
      )) {
        _notice((l10n, _) => l10n.liveOrderTermsOpenFailed);
      }
    } catch (_) {
      _notice((l10n, _) => l10n.liveOrderTermsOpenFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _order?['status'];
    final terminal =
        status == 'confirmed' || status == 'failed' || status == 'expired';
    final name =
        _orderAsset?.name ??
        _asset?.name ??
        widget.company?.name ??
        l10n.liveOrderTitleFallback;
    return PopScope(
      canPop: !_busy && !_reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: l10n.commonBack,
            onPressed: _busy ? null : _back,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(name, style: Theme.of(context).textTheme.titleLarge),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_client.current)
                  ..._unavailable(
                    context,
                    l10n.liveOrderAccountChangedTitle,
                    l10n.liveOrderAccountChangedBody,
                    retry: false,
                  )
                else if (_pending || terminal)
                  ..._result(context)
                else if (_checking)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: TrimmyLiquidMark(size: 72)),
                  )
                else if (_recoveryFailed || _capabilitiesFailed)
                  ..._unavailable(
                    context,
                    _recoveryFailed
                        ? l10n.liveOrderCheckLastOrderTitle
                        : l10n.liveOrderConnectFailedTitle,
                    l10n.liveOrderConnectedRetryBody,
                    retry: true,
                  )
                else if (_capabilities?.enabled != true)
                  ..._unavailable(
                    context,
                    l10n.liveOrderPausedTitle,
                    l10n.liveOrderPausedBody,
                    retry: true,
                  )
                else if (_asset == null)
                  ..._unavailable(
                    context,
                    l10n.liveOrderNotTradableTitle,
                    widget.variantMint == null
                        ? l10n.liveOrderChooseAnother
                        : _capabilities!.reasonFor(
                            widget.variantMint!,
                            l10n,
                            context.formats,
                          ),
                    retry: false,
                  )
                else if (status == 'reviewed' &&
                    _order?['terms'] is Map &&
                    _orderAsset != null)
                  ..._review(context)
                else
                  ..._entry(context),
                if (_error != null)
                  Padding(
                    key: _noticeKey,
                    padding: const EdgeInsets.only(top: 16),
                    child: ProductNotice(
                      key: const ValueKey('live-order-notice'),
                      message: _error!(l10n, context.formats),
                      onDismiss: () => setState(() => _error = null),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _unavailable(
    BuildContext context,
    String title,
    String message, {
    required bool retry,
  }) => [
    const SizedBox(height: 28),
    Text(title, style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 12),
    Text(message),
    const SizedBox(height: 24),
    ProductButton(
      key: const ValueKey('live-order-unavailable-action'),
      label: retry
          ? context.l10n.commonTryAgain
          : context.l10n.liveOrderBackToStocks,
      onPressed: retry ? _restore : widget.onBack,
    ),
  ];

  List<Widget> _entry(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final l10n = context.l10n, formats = context.formats;
    final asset = _asset!, issuer = _issuer!;
    final balance = _balanceRaw;
    final available = balance == null
        ? l10n.liveOrderCheckingBalance
        : l10n.liveOrderAvailable(_amountLabel(balance, formats));
    final limit = _amountLabel(_limitRaw, formats);
    final capped = _cappedPercent;
    final accepted = _termsAccepted;
    final identity = Row(
      children: [
        CompanyLogo(
          name: asset.name,
          logoUrl: widget.company?.logoUrl,
          color: widget.company?.brandColor ?? ProductColor.violet,
          size: 52,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sell
                    ? l10n.liveOrderSellTitle(_symbol)
                    : l10n.liveOrderBuyTitle(_symbol),
                style: type.headlineMedium,
              ),
              Text('Solana', style: type.bodySmall),
            ],
          ),
        ),
      ],
    );
    final switcher = TextButton(
      onPressed: _busy ? null : _switchSide,
      child: Text(_sell ? l10n.liveOrderBuyInstead : l10n.liveOrderSellInstead),
    );
    // Large text stacks the switch under the title instead of squeezing it.
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    return [
      if (large) ...[
        identity,
        Align(alignment: Alignment.centerLeft, child: switcher),
      ] else
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(child: identity),
              // A long label (French, Portuguese) wraps rather than
              // squeezing the title.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .45,
                ),
                child: switcher,
              ),
            ],
          ),
        ),
      if (asset.market case final market?
          when !market.open || market.usSessions) ...[
        const SizedBox(height: 18),
        _MarketStateNote(state: market),
      ],
      const SizedBox(height: 28),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        decoration: ShapeDecoration(
          color: const Color(0xFFF4F0FC),
          shape: productSquircle(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _sell ? l10n.liveOrderYouSell : l10n.liveOrderYouPay,
              style: type.bodyMedium,
            ),
            TextField(
              key: const ValueKey('live-order-amount'),
              controller: _amount,
              onChanged: _typed,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  formats.decimalInputCharacters,
                ),
                LengthLimitingTextInputFormatter(40),
              ],
              style: type.displayLarge?.copyWith(fontSize: 40),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: '0',
                prefixText: _sell || !formats.dollarFirst
                    ? null
                    : '${formats.dollarSymbol} ',
                suffixText: _sell ? _symbol : 'USDC',
                suffixStyle: type.bodyMedium,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    available,
                    key: const ValueKey('live-order-available'),
                    style: type.bodySmall,
                  ),
                ),
                TextButton(
                  key: const ValueKey('live-order-max'),
                  onPressed: _busy || _maxRaw == null || _maxRaw == BigInt.zero
                      ? null
                      : () => _selectPercent(100),
                  child: Text(l10n.commonMax),
                ),
              ],
            ),
            // The minimum is known before the first try, as on the web.
            if (!_sell && asset.minBuyInputRaw != '1')
              Text(
                l10n.liveOrderMinimum(
                  _amountLabel(BigInt.parse(asset.minBuyInputRaw), formats),
                ),
                key: const ValueKey('live-order-minimum'),
                style: type.bodySmall,
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if (_sell)
            for (final percent in [25, 50, 75])
              ActionChip(
                key: ValueKey('live-order-percent-$percent'),
                label: Text(formats.percent('$percent')),
                side: BorderSide.none,
                backgroundColor: ProductColor.paperRaised,
                onPressed: _busy || _maxRaw == null
                    ? null
                    : () => _selectPercent(percent),
              )
          else
            for (final amount in [5, 10, 25, 50])
              ActionChip(
                label: Text(formats.usd('$amount')),
                side: BorderSide.none,
                backgroundColor: ProductColor.paperRaised,
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _initialAmountSet = true;
                        _preset = null;
                        _cappedPercent = null;
                        _amount.text = '$amount';
                      }),
              ),
        ],
      ),
      const SizedBox(height: 12),
      if (_limitRaw < liveUncappedRaw)
        Text(
          capped == null
              ? l10n.liveOrderLimit(limit)
              : capped == 100
              ? l10n.liveOrderLimitCappedMax(limit)
              : l10n.liveOrderLimitCappedPercent(
                  formats.percent('$capped'),
                  limit,
                ),
          key: const ValueKey('live-order-limit'),
          style: type.bodySmall,
        ),
      const SizedBox(height: 20),
      _IssuerCard(
        key: _termsKey,
        issuer: issuer,
        transferFeeBps: asset.transferFeeBps,
        accepted: accepted,
        onAccepted: _busy ? null : _setTerms,
        onOpenTerms: () => _openTerms(issuer),
      ),
      const SizedBox(height: 22),
      ProductButton(
        key: const ValueKey('live-order-review'),
        label: _busy
            ? l10n.liveOrderCheckingPrice
            : asset.marketOpen
            ? (_sell ? l10n.liveOrderReviewSell : l10n.liveOrderReviewBuy)
            : asset.market!.label(DateTime.now(), l10n, formats),
        onPressed: _busy || !accepted || !asset.marketOpen ? null : _preview,
      ),
      if (_fundingNeeded ||
          (!_sell && (balance == null || balance == BigInt.zero))) ...[
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : widget.onAddMoney,
          child: Text(l10n.commonAddMoney),
        ),
      ],
    ];
  }

  List<Widget> _review(BuildContext context) {
    final terms = _order!['terms'] as Map;
    final asset = _orderAsset!;
    final issuer = _capabilities!.issuerFor(asset);
    final buying = terms['side'] == 'buy';
    // The multiplier in force when the server reviewed this order. Older
    // servers send none, which reads as plain token units.
    final scale = LiveShareScale.fromMultiplier(
      asset.decimals,
      terms['stockUiMultiplier'],
    );
    final l10n = context.l10n, formats = context.formats;
    String usdc(Object? raw) => '${formats.number(_usdc(raw as String))} USDC';
    String quoted(Object? raw) =>
        '${formats.number(scale.approx(raw as String))} ${asset.symbol}';
    String least(Object? raw) =>
        '${formats.number(scale.label(raw as String))} ${asset.symbol}';
    // An issuer fee comes out of every transfer, so for those tokens the
    // simulated delivery is closer to what arrives than the swap quote.
    final delivered = terms['simulatedOutputReceivedRaw'];
    final received =
        asset.transferFeeBps > 0 &&
            delivered is String &&
            RegExp(r'^(?:0|[1-9][0-9]{0,19})$').hasMatch(delivered)
        ? delivered
        : terms['quotedOutputAmountRaw'];
    return [
      Text(
        buying ? l10n.liveOrderReviewBuyTitle : l10n.liveOrderReviewSellTitle,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 22),
      ProductCard(
        color: const Color(0xFFF6F3FB),
        child: Column(
          children: [
            _line(
              l10n.liveOrderYouPay,
              buying
                  ? usdc(terms['inputAmountRaw'])
                  : quoted(terms['inputAmountRaw']),
            ),
            _line(
              l10n.liveOrderYouReceive,
              buying ? quoted(received) : usdc(received),
            ),
            _line(
              l10n.liveOrderMinimumReceived,
              buying
                  ? least(terms['minimumOutputAmountRaw'])
                  : usdc(terms['minimumOutputAmountRaw']),
            ),
            _line(
              l10n.liveOrderNetworkFees,
              '≤ ${formats.number(liveDecimal(terms['totalLamportsUpperBound'] as String, 9))} SOL',
            ),
            _line(
              l10n.liveOrderSwapFee,
              livePercent(terms['platformFeeBps'] as int, formats),
            ),
            if (terms['route'] == 'rfq')
              _line(l10n.liveOrderPrice, l10n.liveOrderFixedQuote),
            _line(l10n.liveOrderIssuer, issuer.name),
            if (asset.transferFeeBps > 0)
              _line(
                l10n.liveOrderIssuerFee,
                livePercent(asset.transferFeeBps, formats),
              ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      ProductButton(
        key: const ValueKey('live-order-confirm'),
        label: _busy
            ? l10n.commonConfirming
            : buying
            ? l10n.liveOrderConfirmBuy
            : l10n.liveOrderConfirmSell,
        onPressed: _busy ? null : _confirm,
      ),
      TextButton(
        onPressed: _busy ? null : _editAmount,
        child: Text(l10n.liveOrderEditAmount),
      ),
    ];
  }

  List<Widget> _result(BuildContext context) {
    final l10n = context.l10n;
    final done = _order?['status'] == 'confirmed';
    final expired = _order?['status'] == 'expired';
    return [
      const SizedBox(height: 28),
      Center(
        child: done
            ? const ProductSuccessMark(size: 72)
            : _pending
            ? const TrimmyLiquidMark(size: 72)
            : const Icon(
                Icons.refresh_rounded,
                size: 54,
                color: ProductColor.violet,
              ),
      ),
      const SizedBox(height: 22),
      Text(
        done
            ? l10n.liveOrderTradeConfirmed
            : _pending
            ? l10n.liveOrderConfirmingTrade
            : expired
            ? l10n.liveOrderQuoteExpired
            : l10n.liveOrderTradeIncomplete,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 12),
      Text(
        done
            ? l10n.liveOrderConfirmedBody
            : _pending
            ? l10n.liveOrderPendingBody
            : expired
            ? l10n.liveOrderExpiredBody
            : l10n.liveOrderFailedBody,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 22),
      if (_order?['signature'] case final String signature)
        TextButton(
          onPressed: () async {
            // A market maker's signature identifies an RFQ transaction, so
            // link to the wallet's activity instead of the user's signature.
            final rfq = (_order?['terms'] as Map?)?['route'] == 'rfq';
            final wallet = _order?['wallet'];
            try {
              await launchUrl(
                rfq && wallet is String
                    ? Uri.https('solscan.io', '/account/$wallet')
                    : Uri.https('solscan.io', '/tx/$signature'),
                mode: LaunchMode.externalApplication,
              );
            } catch (_) {
              _notice((l10n, _) => l10n.liveOrderTransactionOpenFailed);
            }
          },
          child: Text(
            (_order?['terms'] as Map?)?['route'] == 'rfq'
                ? l10n.liveOrderViewWalletActivity
                : l10n.liveOrderViewTransaction,
          ),
        ),
      if (done)
        ProductButton(label: l10n.commonDone, onPressed: widget.onBack)
      else if (!_pending)
        ProductButton(
          label: expired ? l10n.liveOrderGetFreshPrice : l10n.commonTryAgain,
          onPressed: () {
            setState(() {
              _order = null;
              _error = null;
            });
            if (_capabilities?.enabled == true && _asset != null) {
              unawaited(_preview());
            } else {
              unawaited(_restore());
            }
          },
        ),
    ];
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    ),
  );
}

/// The issuer behind the chosen token and the one eligibility tick it needs.
/// The face carries the facts; the tinted bottom edge carries the tick.
class _IssuerCard extends StatelessWidget {
  const _IssuerCard({
    super.key,
    required this.issuer,
    required this.transferFeeBps,
    required this.accepted,
    required this.onAccepted,
    required this.onOpenTerms,
  });
  final LiveTradingIssuer issuer;
  final int transferFeeBps;
  final bool accepted;
  final ValueChanged<bool>? onAccepted;
  final VoidCallback onOpenTerms;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final facts = [
      if (issuer.productType.isNotEmpty) issuer.productType,
      if (issuer.holderRights.isNotEmpty) issuer.holderRights,
      if (issuer.excludedRegions.isNotEmpty)
        l10n.liveOrderIssuerExcluded(issuer.excludedRegions.join(', ')),
    ];
    // The built-in statement for servers that send no issuer section is
    // Trimmy's own copy; an issuer's statement is shown as the server wrote it.
    final legacy = LiveTradingIssuer.legacyXStocks.attestation;
    final attestation =
        issuer.attestation.version == legacy.version &&
            issuer.attestation.text == legacy.text
        ? l10n.liveOrderLegacyAttestation
        : issuer.attestation.text;
    return Material(
      color: const Color(0xFFEDE7FB),
      shape: productSquircle(26),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 6, 3, 0),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: productSquircle(23),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  key: const ValueKey('live-order-issuer'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(issuer.name, style: type.titleMedium),
                    for (final fact in facts) ...[
                      const SizedBox(height: 4),
                      Text(fact, style: type.bodySmall),
                    ],
                    if (transferFeeBps > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.liveOrderIssuerFeeNote(
                          livePercent(transferFeeBps, context.formats),
                        ),
                        key: const ValueKey('live-order-issuer-fee'),
                        style: type.bodySmall?.copyWith(
                          color: ProductColor.loss,
                        ),
                      ),
                    ],
                    if (issuer.warning.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: ProductColor.loss,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              issuer.warning,
                              key: const ValueKey('live-order-issuer-warning'),
                              style: type.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          CheckboxListTile(
            key: const ValueKey('live-order-terms'),
            value: accepted,
            onChanged: onAccepted == null
                ? null
                : (value) => onAccepted!(value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.fromLTRB(8, 4, 14, 0),
            title: Text(attestation, style: type.bodyMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('live-order-issuer-terms'),
                onPressed: onOpenTerms,
                child: Text(l10n.liveOrderIssuerTerms),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// When a token can trade: shown when its market is not open, and for tokens
/// that follow US sessions even while open.
class _MarketStateNote extends StatelessWidget {
  const _MarketStateNote({required this.state});
  final LiveMarketState state;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final hours = state.hours(context.l10n);
    return Container(
      key: const ValueKey('live-order-market-state'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: ShapeDecoration(
        color: state.open ? const Color(0xFFEFF7F1) : const Color(0xFFFFF4E5),
        shape: productSquircle(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.label(DateTime.now(), context.l10n, context.formats),
            style: type.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (hours != null) ...[
            const SizedBox(height: 4),
            Text(hours, style: type.bodySmall),
          ],
        ],
      ),
    );
  }
}
