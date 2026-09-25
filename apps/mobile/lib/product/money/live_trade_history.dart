import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../account/account_controller.dart';
import '../../ui_review/review_animated_splash.dart';
import '../design/product_components.dart';
import '../design/product_motion_icon.dart';
import '../design/product_theme.dart';
import '../market/live_trading.dart';
import '../market/market_craft.dart';

enum LiveTradeStatus { pending, confirmed, failed, expired }

class LiveTradeRecord {
  const LiveTradeRecord({
    required this.id,
    required this.wallet,
    required this.status,
    required this.signature,
    required this.createdAt,
    required this.updatedAt,
    required this.assetId,
    required this.mint,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.buy,
    required this.inputAmountRaw,
    required this.quotedOutputAmountRaw,
    required this.minimumOutputAmountRaw,
  });
  final String id, wallet, signature, assetId, mint, symbol, name;
  final LiveTradeStatus status;
  final DateTime createdAt, updatedAt;
  final int decimals;
  final bool buy;
  final String inputAmountRaw, quotedOutputAmountRaw, minimumOutputAmountRaw;
  LiveTradeRecord withStatus(LiveTradeStatus next) => LiveTradeRecord(
    id: id,
    wallet: wallet,
    status: next,
    signature: signature,
    createdAt: createdAt,
    updatedAt: updatedAt,
    assetId: assetId,
    mint: mint,
    symbol: symbol,
    name: name,
    decimals: decimals,
    buy: buy,
    inputAmountRaw: inputAmountRaw,
    quotedOutputAmountRaw: quotedOutputAmountRaw,
    minimumOutputAmountRaw: minimumOutputAmountRaw,
  );

  String get inputLabel =>
      '${liveDecimal(inputAmountRaw, buy ? 6 : decimals)} ${buy ? 'USDC' : '$symbol raw units'}';
  String get quotedOutputLabel =>
      '${liveDecimal(quotedOutputAmountRaw, buy ? decimals : 6)} ${buy ? '$symbol raw units' : 'USDC'}';
  String get minimumOutputLabel =>
      '${liveDecimal(minimumOutputAmountRaw, buy ? decimals : 6)} ${buy ? '$symbol raw units' : 'USDC'}';
  Uri get explorer => Uri.https('solscan.io', '/tx/$signature');
  String get statusLabel => switch (status) {
    LiveTradeStatus.pending => 'Confirming',
    LiveTradeStatus.confirmed => 'Confirmed',
    LiveTradeStatus.failed => 'Not completed',
    LiveTradeStatus.expired => 'Expired',
  };

  factory LiveTradeRecord.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid trade');
    String field(Map source, String key, RegExp pattern) {
      final result = source[key];
      if (result is! String || !pattern.hasMatch(result)) {
        throw const FormatException('Invalid trade field');
      }
      return result;
    }

    final key = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
    final asset = value['asset'], terms = value['terms'];
    final status = LiveTradeStatus.values
        .where((s) => s.name == value['status'])
        .firstOrNull;
    if (asset is! Map ||
        terms is! Map ||
        status == null ||
        value['amountUnits'] != 'raw_token_units' ||
        value['amountsStatus'] != 'reviewed_quote' ||
        asset['decimals'] is! int ||
        (asset['decimals'] as int) < 0 ||
        (asset['decimals'] as int) > 18 ||
        !const {'buy', 'sell'}.contains(terms['side'])) {
      throw const FormatException('Invalid trade contract');
    }
    final mint = field(asset, 'mint', key);
    final buy = terms['side'] == 'buy';
    if (terms['inputMint'] != (buy ? liveUsdcMint : mint) ||
        terms['outputMint'] != (buy ? mint : liveUsdcMint)) {
      throw const FormatException('Invalid trade pair');
    }
    DateTime date(String name) {
      final raw = value[name];
      final parsed = raw is String && raw.length <= 40
          ? DateTime.tryParse(raw)
          : null;
      if (parsed == null || !parsed.isUtc) {
        throw const FormatException('Invalid trade date');
      }
      return parsed;
    }

    String amount(String name) {
      final raw = field(terms, name, RegExp(r'^(?:0|[1-9][0-9]{0,19})$'));
      if (BigInt.parse(raw) > BigInt.parse('18446744073709551615')) {
        throw const FormatException('Invalid trade amount');
      }
      return raw;
    }

    final input = amount('inputAmountRaw'),
        output = amount('quotedOutputAmountRaw'),
        minimum = amount('minimumOutputAmountRaw');
    if (input == '0' ||
        output == '0' ||
        BigInt.parse(minimum) > BigInt.parse(output)) {
      throw const FormatException('Invalid trade amounts');
    }
    return LiveTradeRecord(
      id: field(
        value,
        'id',
        RegExp(r'^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$'),
      ),
      wallet: field(value, 'wallet', key),
      status: status,
      signature: field(
        value,
        'signature',
        RegExp(r'^[1-9A-HJ-NP-Za-km-z]{64,88}$'),
      ),
      createdAt: date('createdAt'),
      updatedAt: date('updatedAt'),
      assetId: field(asset, 'assetId', RegExp(r'^[a-z0-9_-]{1,128}$')),
      mint: mint,
      symbol: field(asset, 'symbol', RegExp(r'^[^\x00-\x1f\x7f]{1,32}$')),
      name: field(asset, 'name', RegExp(r'^[^\x00-\x1f\x7f]{1,160}$')),
      decimals: asset['decimals'] as int,
      buy: buy,
      inputAmountRaw: input,
      quotedOutputAmountRaw: output,
      minimumOutputAmountRaw: minimum,
    );
  }
}

class LiveTradeHistoryPage {
  const LiveTradeHistoryPage(this.orders, this.nextCursor);
  final List<LiveTradeRecord> orders;
  final String? nextCursor;
  factory LiveTradeHistoryPage.fromJson(Object? value) {
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['network'] != 'solana:mainnet-beta' ||
        value['orders'] is! List) {
      throw const FormatException('Invalid trade history');
    }
    final rows = value['orders'] as List, cursor = value['nextCursor'];
    if (rows.length > 50 ||
        (cursor != null &&
            (cursor is! String || cursor.isEmpty || cursor.length > 1024))) {
      throw const FormatException('Invalid trade history page');
    }
    final orders = rows.map(LiveTradeRecord.fromJson).toList();
    if (orders.map((order) => order.id).toSet().length != orders.length ||
        (orders.isEmpty && cursor != null)) {
      throw const FormatException('Invalid trade history page');
    }
    return LiveTradeHistoryPage(List.unmodifiable(orders), cursor as String?);
  }
}

class LiveTradeHistoryFailure implements Exception {
  const LiveTradeHistoryFailure(this.code);
  final String code;
  String get message => code == 'ACCOUNT_REQUIRED'
      ? 'Sign in again to see your trades.'
      : 'Couldn’t load your trades. Try again.';
}

class LiveTradeHistoryClient {
  LiveTradeHistoryClient({
    required this.account,
    required this.origin,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _accountId = account.accountId,
       _epoch = account.navigationEpoch {
    if (origin.scheme != 'https' ||
        origin.userInfo.isNotEmpty ||
        origin.host.isEmpty) {
      throw ArgumentError('HTTPS required');
    }
  }
  final AccountController account;
  final Uri origin;
  final http.Client _client;
  final bool _ownsClient;
  final String? _accountId;
  final int _epoch;
  bool _closed = false;
  bool get current =>
      !_closed &&
      _accountId != null &&
      account.accountId == _accountId &&
      account.navigationEpoch == _epoch &&
      account.phase == AccountPhase.active;

  Future<Object?> _read(Uri url) async {
    if (!current) throw const LiveTradeHistoryFailure('ACCOUNT_REQUIRED');
    final token = await account.freshAccessToken();
    if (!current || token.accountId != _accountId) {
      throw const LiveTradeHistoryFailure('ACCOUNT_REQUIRED');
    }
    final request = http.Request('GET', url)..followRedirects = false;
    request.headers.addAll({
      'authorization': 'Bearer ${token.token}',
      'accept': 'application/json',
    });
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 15));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 131072) {
        throw const LiveTradeHistoryFailure('HISTORY_UNAVAILABLE');
      }
    }
    if (!current) throw const LiveTradeHistoryFailure('ACCOUNT_REQUIRED');
    if (response.statusCode == 401) {
      throw const LiveTradeHistoryFailure('ACCOUNT_REQUIRED');
    }
    if (response.statusCode != 200) {
      throw const LiveTradeHistoryFailure('HISTORY_UNAVAILABLE');
    }
    return jsonDecode(utf8.decode(bytes));
  }

  Future<LiveTradeHistoryPage> read({String? cursor}) async {
    if (cursor != null && (cursor.isEmpty || cursor.length > 1024)) {
      throw ArgumentError('Invalid cursor');
    }
    final data = await _read(
      origin
          .resolve('/v1/trading/history')
          .replace(queryParameters: {'limit': '20', 'cursor': ?cursor}),
    );
    final page = LiveTradeHistoryPage.fromJson(data);
    if (cursor != null && page.nextCursor == cursor) {
      throw const FormatException('Repeated history cursor');
    }
    return page;
  }

  /// Reconciliation reads chain status only. It cannot dispatch a transaction.
  Future<LiveTradeStatus> reconcile(LiveTradeRecord order) async {
    if (order.status != LiveTradeStatus.pending) return order.status;
    final value = await _read(origin.resolve('/v1/trading/order/${order.id}'));
    if (value is! Map ||
        value['order'] is! Map ||
        (value['order'] as Map)['id'] != order.id) {
      throw const FormatException('Invalid trade status');
    }
    final status = LiveTradeStatus.values
        .where((s) => s.name == (value['order'] as Map)['status'])
        .firstOrNull;
    if (status == null) throw const FormatException('Invalid trade status');
    return status;
  }

  void close() {
    _closed = true;
    if (_ownsClient) _client.close();
  }
}

class LiveTradeHistoryScreen extends StatefulWidget {
  const LiveTradeHistoryScreen({
    super.key,
    required this.account,
    required this.origin,
    required this.onBack,
    this.onOpenAsset,
    this.logoForAsset,
    this.httpClient,
    this.openExplorer,
  });
  final AccountController account;
  final Uri origin;
  final VoidCallback onBack;
  final Future<void> Function(String assetId, String mint)? onOpenAsset;
  final String? Function(String assetId, String mint)? logoForAsset;
  final http.Client? httpClient;
  final Future<bool> Function(Uri uri)? openExplorer;
  @override
  State<LiveTradeHistoryScreen> createState() => _LiveTradeHistoryScreenState();
}

class _LiveTradeHistoryScreenState extends State<LiveTradeHistoryScreen>
    with WidgetsBindingObserver {
  late LiveTradeHistoryClient _client;
  final _expanded = <String>{};
  List<LiveTradeRecord> _orders = [];
  String? _cursor, _error;
  bool _loading = true, _more = false, _foreground = true, _polling = false;
  bool _hasOlderPages = false;
  int _generation = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _client = LiveTradeHistoryClient(
      account: widget.account,
      origin: widget.origin,
      client: widget.httpClient,
    );
    widget.account.addListener(_accountChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(LiveTradeHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.account, widget.account) &&
        oldWidget.origin == widget.origin &&
        identical(oldWidget.httpClient, widget.httpClient)) {
      return;
    }
    _generation++;
    _poll?.cancel();
    oldWidget.account.removeListener(_accountChanged);
    _client.close();
    _client = LiveTradeHistoryClient(
      account: widget.account,
      origin: widget.origin,
      client: widget.httpClient,
    );
    widget.account.addListener(_accountChanged);
    _orders = [];
    _cursor = null;
    _expanded.clear();
    _hasOlderPages = false;
    _loading = true;
    _more = false;
    _error = null;
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _client.close();
    widget.account.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _accountChanged() {
    if (_client.current || !mounted) return;
    _generation++;
    _poll?.cancel();
    setState(() {
      _orders = [];
      _cursor = null;
      _loading = false;
      _more = false;
      _error = const LiveTradeHistoryFailure('ACCOUNT_REQUIRED').message;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _poll?.cancel();
      return;
    }
    unawaited(_refresh());
  }

  Future<void> _refresh({bool silent = false}) async {
    final generation = ++_generation;
    _poll?.cancel();
    if (!silent && mounted) {
      setState(() {
        _loading = _orders.isEmpty;
        _error = null;
        _more = false;
      });
    }
    try {
      final page = await _client.read();
      if (!mounted || generation != _generation || !_client.current) return;
      setState(() {
        if (silent && _hasOlderPages) {
          final ids = page.orders.map((o) => o.id).toSet();
          _orders = [
            ...page.orders,
            ..._orders.where((o) => !ids.contains(o.id)),
          ];
        } else {
          _orders = page.orders;
          _cursor = page.nextCursor;
          _hasOlderPages = false;
        }
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        if (!_client.current) {
          _orders = [];
          _cursor = null;
        }
        if (!silent) {
          _error = error is LiveTradeHistoryFailure
              ? error.message
              : 'Couldn’t load your trades. Try again.';
        }
      });
    }
    _schedulePoll();
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!_foreground ||
        !_client.current ||
        !_orders.any((o) => o.status == LiveTradeStatus.pending)) {
      return;
    }
    _poll = Timer(const Duration(seconds: 10), () async {
      if (!mounted ||
          !_foreground ||
          !(ModalRoute.of(context)?.isCurrent ?? true) ||
          _polling ||
          _more) {
        _schedulePoll();
        return;
      }
      _polling = true;
      final generation = _generation, client = _client;
      try {
        for (final order
            in _orders
                .where((o) => o.status == LiveTradeStatus.pending)
                .take(3)) {
          try {
            if (!mounted || generation != _generation || !client.current) break;
            final status = await client.reconcile(order);
            if (mounted &&
                generation == _generation &&
                client.current &&
                status != order.status) {
              setState(
                () => _orders = [
                  for (final existing in _orders)
                    existing.id == order.id
                        ? existing.withStatus(status)
                        : existing,
                ],
              );
            }
          } catch (_) {
            /* Preserve pending, never infer a fill. */
          }
        }
        if (mounted &&
            generation == _generation &&
            client.current &&
            _foreground) {
          await _refresh(silent: true);
        }
      } finally {
        _polling = false;
      }
    });
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (_more || _loading || cursor == null) return;
    // Supersede any in-flight status poll so it cannot discard this page.
    final generation = ++_generation;
    setState(() {
      _more = true;
      _error = null;
    });
    try {
      final page = await _client.read(cursor: cursor);
      if (!mounted || generation != _generation || !_client.current) return;
      final ids = _orders.map((o) => o.id).toSet();
      setState(() {
        _orders = [..._orders, ...page.orders.where((o) => ids.add(o.id))];
        _cursor = page.nextCursor;
        _hasOlderPages = true;
        _more = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _more = false;
        if (!_client.current) {
          _orders = [];
          _cursor = null;
        }
        _error = error is LiveTradeHistoryFailure
            ? error.message
            : 'Couldn’t load more trades. Try again.';
      });
    }
    _schedulePoll();
  }

  Future<void> _open(LiveTradeRecord order) async {
    try {
      final opened =
          await (widget.openExplorer?.call(order.explorer) ??
              launchUrl(order.explorer, mode: LaunchMode.externalApplication));
      if (!opened) throw StateError('Unavailable browser');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn’t open the transaction. Try again.');
      }
    }
  }

  Future<void> _openAsset(LiveTradeRecord order) async {
    final client = _client;
    try {
      await widget.onOpenAsset?.call(order.assetId, order.mint);
      if (mounted && identical(client, _client) && client.current) {
        await _refresh();
      }
    } catch (_) {
      if (mounted && identical(client, _client) && client.current) {
        setState(() => _error = 'Couldn’t open this stock. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: const Text('Your trades'),
      leading: IconButton(
        tooltip: 'Back',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: TrimmyLiquidMark(size: 72)),
            ),
          if (!_loading && _orders.isEmpty && _error == null) ...[
            const SizedBox(height: 64),
            const Center(
              child: ProductMotionIcon(file: 'state-empty.png', size: 88),
            ),
            const SizedBox(height: 20),
            Text(
              'Your first trade starts here',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Your orders will appear here.',
              textAlign: TextAlign.center,
            ),
          ],
          for (final order in _orders) _row(context, order),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
                  if (_orders.isEmpty && _client.current) ...[
                    const SizedBox(height: 12),
                    ProductButton(label: 'Try again', onPressed: _refresh),
                  ] else if (_client.current) ...[
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          if (_cursor != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ProductButton(
                label: _more ? 'Loading…' : 'More trades',
                secondary: true,
                onPressed: _more ? null : _loadMore,
              ),
            ),
        ],
      ),
    ),
  );
  Widget _row(BuildContext context, LiveTradeRecord order) {
    final type = Theme.of(context).textTheme;
    final expanded = _expanded.contains(order.id);
    final color = switch (order.status) {
      LiveTradeStatus.confirmed => ProductColor.gain,
      LiveTradeStatus.failed => ProductColor.loss,
      _ => ProductColor.muted,
    };
    final date = order.createdAt.toLocal();
    final dateLabel =
        '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Padding(
      key: ValueKey('trade-${order.id}'),
      padding: const EdgeInsets.only(bottom: 14),
      child: ProductCard(
        padding: const EdgeInsets.all(16),
        onTap: () => setState(
          () => expanded ? _expanded.remove(order.id) : _expanded.add(order.id),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CompanyLogo(
                  name: order.name,
                  logoUrl: widget.logoForAsset?.call(order.assetId, order.mint),
                  color: ProductColor.violet,
                  size: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.buy ? 'Buy' : 'Sell'} ${order.symbol}',
                        style: type.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(order.inputLabel, style: type.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: ProductColor.muted,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  order.statusLabel,
                  style: type.labelLarge?.copyWith(color: color),
                ),
                Text(dateLabel, style: type.bodySmall),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 18),
              Text('Quoted output', style: type.bodySmall),
              Text(order.quotedOutputLabel, style: type.titleMedium),
              const SizedBox(height: 10),
              Text('Minimum output', style: type.bodySmall),
              Text(order.minimumOutputLabel, style: type.bodyMedium),
              const SizedBox(height: 10),
              Text(
                'Order estimates. See the transaction for the final amounts.',
                style: type.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _open(order),
                    child: const Text('View transaction'),
                  ),
                  if (widget.onOpenAsset != null)
                    TextButton(
                      onPressed: () => _openAsset(order),
                      child: const Text('Open stock'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
