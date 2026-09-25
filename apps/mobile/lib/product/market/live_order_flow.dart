import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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

class LiveOrderFailure implements Exception {
  const LiveOrderFailure(this.code);
  final String code;
  String get message => switch (code) {
    'ADD_USDC' => 'Add USDC to your Solana wallet first.',
    'ADD_SOL' => 'Add SOL to cover network and account fees.',
    'INSUFFICIENT_HOLDINGS' => 'You don’t have enough of this token to sell.',
    'WALLET_REQUIRED' => 'Create your wallet to continue.',
    'ORDER_PENDING' => 'Your previous trade is still confirming.',
    'QUOTE_EXPIRED' => 'That price expired. Get a fresh quote.',
    'LIVE_BUSY' => 'Quotes are busy. Try again in a moment.',
    'NO_ROUTE' => 'No route for this order right now. Try another amount.',
    'FEE_TOO_HIGH' => 'The fees are too high for this order. Try later.',
    'ACCOUNT_REQUIRED' => 'Sign in again to use your wallet.',
    'INVALID_REVIEW' ||
    'INVALID_SIGNATURE' => 'This order needs a fresh quote.',
    'LIVE_UNAVAILABLE' => 'Trading couldn’t connect. Try again.',
    _ => 'Couldn’t complete this step. Try again.',
  };
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
    if (!current) throw const LiveOrderFailure('ACCOUNT_REQUIRED');
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
    this.initialSell = false,
    this.httpClient,
  });
  final MarketCompany? company;
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
  Map<String, dynamic>? _order;
  LiveTradingCapabilities? _capabilities;
  Timer? _poll, _noticeTimer, _quoteTimer;
  bool _busy = false, _checking = true, _sell = false, _terms = false;
  bool _restoring = false, _recoveryFailed = false, _capabilitiesFailed = false;
  bool _foreground = true, _polling = false, _initialAmountSet = false;
  bool _fundingNeeded = false;
  String? _error, _uncertainId;
  late final _pendingKey =
      'trimmy.pending-live-order.${widget.account.accountId}';

  LiveTradingAsset? get _asset => widget.company == null
      ? _capabilities?.assets.firstOrNull
      : _capabilities?.forCompany(widget.company!);
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
  int get _decimals => _sell ? (_asset?.decimals ?? 8) : 6;
  BigInt get _limitRaw =>
      BigInt.parse(_sell ? _asset!.maxSellInputRaw : _asset!.maxBuyInputRaw);
  BigInt? get _maxRaw {
    final balance = _balanceRaw;
    if (balance == null || _asset == null) return null;
    return balance < _limitRaw ? balance : _limitRaw;
  }

  String get _symbol => _asset?.symbol ?? widget.company?.symbol ?? 'token';
  bool get _scaledHolding {
    String normalize(String value) => value.contains('.')
        ? value
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '')
        : value;
    final holding = _holding;
    return holding?.displayAmount != null &&
        normalize(holding!.displayAmount!) != normalize(holding.rawTokenUnits);
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
    if (mounted) setState(() {});
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

  void _notice(String message) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(() => _error = message);
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
            if (order?['status'] == 'confirmed') await _refreshBalance();
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

    await Future.wait([readOrder(), readCapabilities(), _refreshBalance()]);
    if (mounted) {
      _setInitialAmount();
      setState(() => _checking = false);
    }
    _restoring = false;
  }

  void _setInitialAmount() {
    if (_initialAmountSet || _asset == null) return;
    _initialAmountSet = true;
    final max = _maxRaw;
    if (_sell) {
      if (max != null && max > BigInt.zero) {
        _amount.text = liveDecimal(max.toString(), _decimals);
      }
    } else if (max != null && max > BigInt.zero && max < BigInt.from(5000000)) {
      _amount.text = liveDecimal(max.toString(), 6);
    }
  }

  void _selectPercent(int percent) {
    final balance = _balanceRaw;
    if (balance == null || _asset == null) return;
    final portion = balance * BigInt.from(percent) ~/ BigInt.from(100);
    final raw = portion > _limitRaw ? _limitRaw : portion;
    setState(() => _amount.text = liveDecimal(raw.toString(), _decimals));
  }

  void _switchSide() {
    setState(() {
      _sell = !_sell;
      _terms = false;
      _error = null;
      _fundingNeeded = false;
      _initialAmountSet = false;
      _amount.text = _sell ? '' : '5';
      _setInitialAmount();
    });
  }

  Future<void> _preview() async {
    final asset = _asset;
    if (_busy ||
        asset == null ||
        _capabilities?.enabled != true ||
        _recoveryFailed) {
      return;
    }
    final raw = liveAmountRaw(_amount.text, _decimals);
    if (raw == null) {
      _notice('Enter a valid ${_sell ? 'token amount' : 'USDC amount'}.');
      return;
    }
    if (BigInt.parse(raw) > _limitRaw) {
      _notice(
        'Up to ${_sell ? '' : r'$'}${liveDecimal(_limitRaw.toString(), _decimals)} ${_sell ? _symbol : 'USDC'} per order.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _terms = false;
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
      _notice(error.message);
      if (error.code == 'ORDER_PENDING') await _restore();
    } catch (_) {
      _notice('Couldn’t get a verified quote. Try again.');
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
      setState(() {
        _order = {..._order!, 'status': 'expired'};
        _terms = false;
      });
    }
  }

  Future<void> _confirm() async {
    final order = _order;
    if (order == null || _busy || !_terms || order['status'] != 'reviewed') {
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
      if (result['status'] == 'confirmed') await _refreshBalance();
    } catch (_) {
      if (!mounted) return;
      if (dispatchStarted) {
        setState(() => _order = {...order, 'status': 'pending'});
        _notice('Checking the result. Your order won’t be sent twice.');
        _schedule();
      } else {
        _notice('Signing didn’t finish. No order was sent.');
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
        if (result['status'] == 'confirmed') await _refreshBalance();
      }
    } catch (_) {
      _notice('Reconnecting to check your order…');
    } finally {
      _polling = false;
      if (mounted && _pending) _schedule();
    }
  }

  Future<void> _openIssuer() async {
    try {
      if (!await launchUrl(
        Uri.parse('https://assets.backed.fi/legal-documentation'),
        mode: LaunchMode.externalApplication,
      )) {
        _notice('Couldn’t open the issuer’s terms. Try again.');
      }
    } catch (_) {
      _notice('Couldn’t open the issuer’s terms. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _order?['status'];
    final terminal =
        status == 'confirmed' || status == 'failed' || status == 'expired';
    final name =
        _orderAsset?.name ?? _asset?.name ?? widget.company?.name ?? 'Trade';
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _busy ? null : widget.onBack,
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
                if (_pending || terminal)
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
                        ? 'Let’s check your last order'
                        : 'Trading couldn’t connect',
                    'Try again when you’re connected.',
                    retry: true,
                  )
                else if (_capabilities?.enabled != true)
                  ..._unavailable(
                    context,
                    'Trading is temporarily paused',
                    'Your wallet and holdings are still here.',
                    retry: true,
                  )
                else if (_asset == null)
                  ..._unavailable(
                    context,
                    'This token isn’t tradable here yet',
                    'Choose another stock to trade.',
                    retry: false,
                  )
                else if (status == 'reviewed' && _order?['terms'] is Map)
                  ..._review(context)
                else
                  ..._entry(context),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ProductNotice(
                      key: const ValueKey('live-order-notice'),
                      message: _error!,
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
      label: retry ? 'Try again' : 'Back to stocks',
      onPressed: retry ? _restore : widget.onBack,
    ),
  ];

  List<Widget> _entry(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final balance = _balanceRaw;
    final available = balance == null
        ? 'Checking balance…'
        : '${liveDecimal(balance.toString(), _decimals)} ${_sell ? '$_symbol raw units' : 'USDC'} available';
    return [
      Row(
        children: [
          CompanyLogo(
            name: _asset!.name,
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
                  '${_sell ? 'Sell' : 'Buy'} $_symbol',
                  style: type.headlineMedium,
                ),
                Text('Solana', style: type.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _switchSide,
            child: Text(_sell ? 'Buy instead' : 'Sell instead'),
          ),
        ],
      ),
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
            Text(_sell ? 'Raw token units' : 'You pay', style: type.bodyMedium),
            TextField(
              key: const ValueKey('live-order-amount'),
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                LengthLimitingTextInputFormatter(40),
              ],
              style: type.displayLarge?.copyWith(fontSize: 40),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: '0',
                prefixText: _sell ? null : r'$ ',
                suffixText: _sell ? null : 'USDC',
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
                  child: const Text('Max'),
                ),
              ],
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
                label: Text('$percent%'),
                side: BorderSide.none,
                backgroundColor: ProductColor.paperRaised,
                onPressed: _busy || _maxRaw == null
                    ? null
                    : () => _selectPercent(percent),
              )
          else
            for (final amount in [5, 10, 25, 50])
              ActionChip(
                label: Text('\$$amount'),
                side: BorderSide.none,
                backgroundColor: ProductColor.paperRaised,
                onPressed: _busy
                    ? null
                    : () => setState(() => _amount.text = '$amount'),
              ),
        ],
      ),
      const SizedBox(height: 12),
      if (_sell && _scaledHolding) ...[
        Text(
          'Holdings shows ${_holding!.displayAmount} $_symbol. Orders use raw token units.',
          style: type.bodySmall,
        ),
        const SizedBox(height: 12),
      ],
      Text(
        'Order limit: ${_sell ? '' : r'$'}${liveDecimal(_limitRaw.toString(), _decimals)} ${_sell ? '$_symbol raw units' : 'USDC'}',
        style: type.bodySmall,
      ),
      const SizedBox(height: 26),
      ProductButton(
        key: const ValueKey('live-order-review'),
        label: _busy
            ? 'Checking price and fees…'
            : 'Review ${_sell ? 'sell' : 'buy'}',
        onPressed: _busy ? null : _preview,
      ),
      if (_fundingNeeded ||
          (!_sell && (balance == null || balance == BigInt.zero))) ...[
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : widget.onAddMoney,
          child: const Text('Add money'),
        ),
      ],
    ];
  }

  List<Widget> _review(BuildContext context) {
    final terms = _order!['terms'] as Map;
    final asset = _orderAsset!;
    final buying = terms['side'] == 'buy';
    final inputDecimals = buying ? 6 : asset.decimals,
        outputDecimals = buying ? asset.decimals : 6;
    final inputSymbol = buying ? 'USDC' : '${asset.symbol} raw units',
        outputSymbol = buying ? '${asset.symbol} raw units' : 'USDC';
    return [
      Text(
        'Review your ${buying ? 'buy' : 'sell'}',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 22),
      ProductCard(
        color: const Color(0xFFF6F3FB),
        child: Column(
          children: [
            _line(
              'You pay',
              '${liveDecimal(terms['inputAmountRaw'] as String, inputDecimals)} $inputSymbol',
            ),
            _line(
              'You receive ≈',
              '${liveDecimal(terms['quotedOutputAmountRaw'] as String, outputDecimals)} $outputSymbol',
            ),
            _line(
              'Minimum received',
              '${liveDecimal(terms['minimumOutputAmountRaw'] as String, outputDecimals)} $outputSymbol',
            ),
            _line(
              'Network + account fees',
              '≤ ${liveDecimal(terms['totalLamportsUpperBound'] as String, 9)} SOL',
            ),
            _line('Swap fee', '${(terms['platformFeeBps'] as num) / 100}%'),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '${asset.symbol} is a tokenized stock. Raw units can differ from the amount in Holdings.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      CheckboxListTile(
        key: const ValueKey('live-order-terms'),
        contentPadding: EdgeInsets.zero,
        value: _terms,
        onChanged: _busy
            ? null
            : (value) => setState(() => _terms = value ?? false),
        title: const Text('I’m eligible under the issuer’s terms.'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _openIssuer,
          child: const Text('Issuer terms ↗'),
        ),
      ),
      const SizedBox(height: 12),
      ProductButton(
        key: const ValueKey('live-order-confirm'),
        label: _busy ? 'Confirming…' : 'Confirm ${buying ? 'buy' : 'sell'}',
        onPressed: _busy || !_terms ? null : _confirm,
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () {
                _quoteTimer?.cancel();
                setState(() {
                  _order = null;
                  _terms = false;
                });
              },
        child: const Text('Edit amount'),
      ),
    ];
  }

  List<Widget> _result(BuildContext context) {
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
            ? 'Trade confirmed'
            : _pending
            ? 'Confirming your trade'
            : expired
            ? 'Quote expired'
            : 'Trade didn’t complete',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 12),
      Text(
        done
            ? 'Your order is confirmed on Solana.'
            : _pending
            ? 'You can close this. Reopen the trade to check its status.'
            : expired
            ? 'Get a fresh price to continue.'
            : 'Your order wasn’t filled.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 22),
      if (_order?['signature'] case final String signature)
        TextButton(
          onPressed: () async {
            try {
              await launchUrl(
                Uri.https('solscan.io', '/tx/$signature'),
                mode: LaunchMode.externalApplication,
              );
            } catch (_) {
              _notice('Couldn’t open the transaction. Try again.');
            }
          },
          child: const Text('View transaction ↗'),
        ),
      if (done)
        ProductButton(label: 'Done', onPressed: widget.onBack)
      else if (!_pending)
        ProductButton(
          label: expired ? 'Get fresh price' : 'Try again',
          onPressed: () {
            setState(() {
              _order = null;
              _error = null;
              _terms = false;
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
