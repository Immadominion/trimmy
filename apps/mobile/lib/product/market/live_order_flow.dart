import 'market_models.dart';
import '../../ui_review/review_animated_splash.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../account/account_controller.dart';
import '../design/product_theme.dart';

const liveAppleMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';

class LiveOrderFailure implements Exception {
  const LiveOrderFailure(this.code);
  final String code;
  String get message => switch (code) {
    'ADD_USDC' => 'Add USDC to your Solana wallet first.',
    'ADD_SOL' => 'Add a little SOL for network fees.',
    'WALLET_REQUIRED' => 'Set up your wallet to continue.',
    'ORDER_PENDING' => 'Your previous trade is still confirming.',
    'QUOTE_EXPIRED' => 'That quote expired. Get a fresh price.',
    'LIVE_BUSY' => 'The quote desk is busy. Try again in a moment.',
    'NO_ROUTE' => 'No route for this order right now.',
    'FEE_TOO_HIGH' => 'The fees are too high for this order. Try later.',
    'ACCOUNT_REQUIRED' => 'Sign in to use your real wallet.',
    _ => 'Couldn’t complete this step. Try again.',
  };
}

class LiveOrderClient {
  LiveOrderClient(this.origin, this.account, {http.Client? client})
    : _client = client ?? http.Client(),
      _identity = account.accountId {
    if (origin.scheme != 'https' || origin.userInfo.isNotEmpty) {
      throw ArgumentError('HTTPS required');
    }
  }
  final Uri origin;
  final AccountController account;
  final String? _identity;
  final http.Client _client;
  bool _closed = false;
  void close() {
    _closed = true;
    _client.close();
  }

  Future<bool> enabled() async {
    final response = await _client
        .get(origin.resolve('/v1/trading/capabilities'))
        .timeout(const Duration(seconds: 12));
    if (_closed ||
        response.statusCode != 200 ||
        response.bodyBytes.length > 4096) {
      return false;
    }
    return (jsonDecode(response.body) as Map)['enabled'] == true;
  }

  Future<Map<String, dynamic>?> request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = await account.freshAccessToken();
    if (_closed || _identity == null || account.accountId != _identity) {
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
    if (_closed || account.accountId != _identity) {
      throw const LiveOrderFailure('ACCOUNT_REQUIRED');
    }
    final decoded = jsonDecode(utf8.decode(bytes)) as Map;
    if (response.statusCode != 200) {
      throw LiveOrderFailure(decoded['code'] as String? ?? 'LIVE_UNAVAILABLE');
    }
    final order = decoded['order'];
    return order == null ? null : Map<String, dynamic>.from(order as Map);
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
  });
  final MarketCompany? company;
  final bool initialSell;
  final AccountController account;
  final Uri origin;
  final VoidCallback onBack;
  final Future<void> Function() onAddMoney;
  @override
  State<LiveOrderFlow> createState() => _LiveOrderFlowState();
}

class _LiveOrderFlowState extends State<LiveOrderFlow> {
  late final _client = LiveOrderClient(widget.origin, widget.account);
  final _amount = TextEditingController(text: '5');
  Map<String, dynamic>? _order;
  Timer? _poll;
  bool _busy = false, _checking = true, _sell = false, _terms = false;
  String? _error;
  bool _enabled = false;
  String? _uncertainId;
  late final _pendingKey =
      'trimmy.pending-live-order.${widget.account.accountId}';
  Future<void> _remember(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setString(_pendingKey, id);
    }
    _uncertainId = id;
  }

  @override
  void initState() {
    super.initState();
    _sell = widget.initialSell;
    _amount.text = _sell ? '0.01' : '5';
    unawaited(_restore());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _client.close();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      _enabled = await _client.enabled();
      if (!_enabled) return;
      _uncertainId = (await SharedPreferences.getInstance()).getString(
        _pendingKey,
      );
      final order = await _client.request(
        _uncertainId == null ? 'order' : 'order/$_uncertainId',
      );
      if (order == null && _uncertainId != null) {
        throw const LiveOrderFailure('ORDER_PENDING');
      }
      if (mounted && (order?['status'] == 'pending' || _uncertainId != null)) {
        setState(
          () => _order = order?['status'] == 'reviewed'
              ? {...order!, 'status': 'pending'}
              : order,
        );
        if (_order?['status'] == 'pending') {
          _schedule();
        } else {
          await _remember(null);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn’t check pending trades. Try again.');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String? _raw() {
    final text = _amount.text.trim(), decimals = _sell ? 8 : 6;
    if (!RegExp('^[0-9]{1,4}(\\.[0-9]{1,$decimals})?\$').hasMatch(text)) {
      return null;
    }
    final parts = text.split('.');
    final raw =
        BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals) +
        BigInt.parse(
          (parts.length == 1 ? '' : parts[1]).padRight(decimals, '0'),
        );
    if (raw <= BigInt.zero || raw > BigInt.from(100000000)) return null;
    return raw.toString();
  }

  bool get _supported =>
      widget.company == null ||
      widget.company!.primaryVariant?.mint == liveAppleMint;
  Future<void> _preview() async {
    if (!_supported || !_enabled) return;
    final raw = _raw();
    if (raw == null) {
      setState(
        () => _error = _sell
            ? 'Enter up to 1 AAPLx token unit.'
            : r'Enter an amount from $0.000001 to $100.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await _client.request('preview', {
        'assetId': 'apple',
        'variantMint': liveAppleMint,
        'side': _sell ? 'sell' : 'buy',
        'amountRaw': raw,
      });
      if (mounted) setState(() => _order = order);
    } on LiveOrderFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
      if (e.code == 'ORDER_PENDING') await _restore();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn’t get a verified quote. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final order = _order;
    if (order == null || _busy || !_terms) return;
    final expiry = DateTime.tryParse(order['expiresAt'] as String? ?? '');
    if (expiry == null || !DateTime.now().toUtc().isBefore(expiry)) {
      setState(() {
        _order = null;
        _error = 'Quote expired. Get a fresh price.';
      });
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
      await _remember(order['id'] as String);
      dispatchStarted = true;
      final result = await _client.request('execute', {
        'id': order['id'],
        'reviewDigest': order['reviewDigest'],
        'signedTransaction': signed,
      });
      if (mounted) setState(() => _order = result);
      if (result?['status'] == 'pending') {
        _schedule();
      } else {
        await _remember(null);
      }
      if (result?['status'] == 'confirmed') {
        unawaited(widget.account.refreshPortfolio());
      }
    } catch (_) {
      if (!mounted) return;
      if (dispatchStarted) {
        setState(() {
          _order = {...order, 'status': 'pending'};
          _error = 'Checking the result. Don’t place another order yet.';
        });
        _schedule();
      } else {
        setState(() => _error = 'Signing didn’t finish. No order was sent.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _schedule() {
    _poll?.cancel();
    _poll = Timer(const Duration(seconds: 3), () => unawaited(_check()));
  }

  Future<void> _check() async {
    try {
      final result = await _client.request('order/${_order!['id']}');
      if (!mounted) return;
      if (result != null && result['id'] == _order?['id']) {
        setState(() {
          _order = result['status'] == 'reviewed' && _uncertainId != null
              ? {...result, 'status': 'pending'}
              : result;
          _error = null;
        });
        if (_order?['status'] == 'pending') {
          _schedule();
        } else {
          await _remember(null);
          if (result['status'] == 'confirmed') {
            unawaited(widget.account.refreshPortfolio());
          }
        }
      } else {
        setState(() => _error = 'Still checking your order…');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Reconnecting…');
      }
    } finally {
      if (mounted && _order?['status'] == 'pending') _schedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order, status = order?['status'];
    final terms = order?['terms'] as Map?;
    final pending = status == 'pending',
        reviewed = status == 'reviewed',
        done = status == 'confirmed';
    final theme = Theme.of(context).textTheme;
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
          title: Text(widget.company?.name ?? 'Apple', style: theme.titleLarge),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_checking)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: TrimmyLiquidMark(size: 88)),
                  )
                else if (!_enabled || !_supported) ...[
                  Image.asset(
                    'assets/images/career_world/safe.png',
                    height: 140,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Trading isn’t available yet',
                    style: theme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text('You can still add money to your wallet.'),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: widget.onAddMoney,
                    child: const Text('Add money'),
                  ),
                ] else if (pending ||
                    done ||
                    status == 'failed' ||
                    status == 'expired') ...[
                  const SizedBox(height: 20),
                  Icon(
                    done
                        ? Icons.verified_rounded
                        : pending
                        ? Icons.hourglass_top_rounded
                        : Icons.refresh_rounded,
                    size: 54,
                    color: done ? ProductColor.gain : ProductColor.violet,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    done
                        ? 'Trade confirmed'
                        : pending
                        ? 'Confirming your trade'
                        : status == 'expired'
                        ? 'Order expired'
                        : 'Trade didn’t complete',
                    textAlign: TextAlign.center,
                    style: theme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  if (order?['signature'] case final String signature)
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: signature));
                      },
                      child: const Text('Copy transaction ID'),
                    ),
                  if (!pending)
                    FilledButton(
                      onPressed: () => setState(() {
                        _order = null;
                        _error = null;
                        _terms = false;
                      }),
                      child: const Text('Back to trading'),
                    ),
                ] else if (reviewed && terms != null) ...[
                  Text(
                    terms['side'] == 'buy'
                        ? 'Review your buy'
                        : 'Review your sell',
                    style: theme.headlineLarge,
                  ),
                  const SizedBox(height: 26),
                  _line(
                    'You pay',
                    '${_decimal(terms['inputAmountRaw'] as String, terms['side'] == 'buy' ? 6 : 8)} ${terms['side'] == 'buy' ? 'USDC' : 'AAPLx units'}',
                  ),
                  _line(
                    'You receive ≈',
                    '${_decimal(terms['quotedOutputAmountRaw'] as String, terms['side'] == 'buy' ? 8 : 6)} ${terms['side'] == 'buy' ? 'AAPLx units' : 'USDC'}',
                  ),
                  _line(
                    'Minimum received',
                    _decimal(
                      terms['minimumOutputAmountRaw'] as String,
                      terms['side'] == 'buy' ? 8 : 6,
                    ),
                  ),
                  _line(
                    'Network + account fees',
                    '≤ ${_decimal(terms['totalLamportsUpperBound'] as String, 9)} SOL',
                  ),
                  _line(
                    'Swap fee',
                    '${(terms['platformFeeBps'] as num) / 100}%',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'AAPLx is a tokenized stock, not a direct Apple share. Token units can differ from displayed shares.',
                    style: theme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _terms,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _terms = value ?? false),
                    title: const Text('I’m eligible under the issuer’s terms.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(
                          text: 'https://assets.backed.fi/legal-documentation',
                        ),
                      );
                    },
                    child: const Text('Copy issuer terms link'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ProductColor.violet,
                      padding: const EdgeInsets.all(17),
                    ),
                    onPressed: _busy || !_terms ? null : _confirm,
                    child: Text(
                      _busy ? 'Confirming…' : 'Confirm ${terms['side']}',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _order = null),
                    child: const Text('Edit amount'),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text('Apple', style: theme.headlineLarge),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _sell = !_sell;
                          _amount.text = _sell ? '0.01' : '5';
                          _error = null;
                        }),
                        child: Text(_sell ? 'Switch to buy' : 'Switch to sell'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _sell ? 'Sell AAPLx token units' : 'Buy with USDC',
                    style: theme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFF4F0FC),
                      shape: productSquircle(28),
                    ),
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        LengthLimitingTextInputFormatter(14),
                      ],
                      style: theme.displayLarge,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        prefixText: _sell ? null : '\$ ',
                        suffixText: _sell ? 'AAPLx' : null,
                      ),
                    ),
                  ),
                  if (!_sell)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Wrap(
                        spacing: 10,
                        children: [
                          for (final amount in [5, 10, 25, 50])
                            ActionChip(
                              label: Text('\$$amount'),
                              side: BorderSide.none,
                              backgroundColor: ProductColor.paperRaised,
                              onPressed: () =>
                                  setState(() => _amount.text = '$amount'),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ProductColor.violet,
                      padding: const EdgeInsets.all(17),
                    ),
                    onPressed: _busy ? null : _preview,
                    child: Text(
                      _busy
                          ? 'Checking price and fees…'
                          : 'Review ${_sell ? 'sell' : 'buy'}',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : widget.onAddMoney,
                    child: const Text('Add money'),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: theme.bodyMedium?.copyWith(
                        color: ProductColor.loss,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 14),
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
  String _decimal(String raw, int decimals) {
    final text = raw.padLeft(decimals + 1, '0');
    return '${text.substring(0, text.length - decimals)}.${text.substring(text.length - decimals)}'
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
