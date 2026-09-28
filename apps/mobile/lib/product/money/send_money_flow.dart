import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../account/account_amounts.dart';
import '../../account/account_controller.dart';
import '../../account/account_data_models.dart';
import '../../account/wallet_trade_signer.dart';
import '../../ui_review/review_animated_splash.dart';
import '../design/product_components.dart';
import '../design/product_notice.dart';
import '../design/product_success_mark.dart';
import '../design/product_theme.dart';
import '../market/live_trading.dart';
import 'real_holdings.dart';

final _address = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
final _raw = RegExp(r'^(?:0|[1-9][0-9]{0,19})$');

/// SOL kept back by Max, so the wallet can still pay fees afterwards.
final _solReserve = BigInt.from(2000000);

class SendFailure implements Exception {
  const SendFailure(this.code);
  final String code;
  String get message => switch (code) {
    'DESTINATION_INVALID' ||
    'TRANSFER_INPUT_INVALID' => 'Check the address and the amount.',
    'DESTINATION_SELF' => 'That’s your own wallet. Enter another address.',
    'DESTINATION_NOT_WALLET' =>
      'That address isn’t a wallet. It may be a token account or a program. Ask for the wallet address instead.',
    'DESTINATION_FROZEN' => 'That wallet can’t receive this token right now.',
    'ASSET_UNSUPPORTED' => 'This token can’t be sent from Trimmy.',
    'ASSET_NOT_TRANSFERABLE' =>
      'This token has transfer rules Trimmy can’t send with.',
    'ASSET_PAUSED' => 'Its issuer has paused transfers for now.',
    'ASSET_FROZEN' =>
      'This token is frozen in your wallet. Contact its issuer.',
    'INSUFFICIENT_BALANCE' => 'You don’t have that much ready to send.',
    'ADD_SOL' => 'Add a little SOL to cover the network fee.',
    'LEAVES_TOO_LITTLE_SOL' => 'Leave at least 0.001 SOL, or send all of it.',
    'AMOUNT_TOO_SMALL' => 'A new wallet needs at least 0.001 SOL to open.',
    'SIMULATION_FAILED' || 'SIMULATION_MISMATCH' =>
      'This send didn’t pass its check. Nothing was sent.',
    'REVIEW_EXPIRED' ||
    'INVALID_REVIEW' ||
    'INVALID_SIGNATURE' => 'This review expired. Review it again.',
    'TRANSFER_NOT_SENT' =>
      'It wasn’t sent, so nothing left your wallet. Try again.',
    'TRANSFER_BUSY' => 'One moment, then try again.',
    'ACCOUNT_REQUIRED' ||
    'WALLET_REQUIRED' => 'Sign in again to use your wallet.',
    'SIGNING_CANCELLED' => 'Signing was cancelled. Nothing was sent.',
    'TRANSFER_UNAVAILABLE' => 'Sending is paused right now. Try again later.',
    _ => 'Sending couldn’t connect. Try again.',
  };
}

/// Something the wallet can send: USDC, SOL or a stock token, with what is
/// ready to send from its main account.
@immutable
class SendAsset {
  const SendAsset({
    required this.id,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.availableRaw,
    required this.scale,
  });

  /// `USDC`, `SOL` or the token's mint, as the server takes it.
  final String id;
  final String symbol, name;
  final int decimals;
  final String availableRaw;
  final LiveShareScale scale;

  bool get stock => id != 'USDC' && id != 'SOL';

  /// What Max fills in: everything, except SOL keeps a little for fees.
  String get maxRaw {
    if (id != 'SOL') return availableRaw;
    final left = BigInt.parse(availableRaw) - _solReserve;
    return left > BigInt.zero ? left.toString() : '0';
  }

  String label(String raw) =>
      stock ? scale.label(raw) : formatRawUnits(raw, decimals) ?? raw;

  /// Raw units for what someone typed; shares for a stock token.
  String? rawFor(String text) =>
      stock ? scale.raw(text) : liveAmountRaw(text, decimals);
}

/// Everything in the wallet that can be sent now, largest cash first.
List<SendAsset> sendableAssets(
  AccountHoldingsSnapshot holdings, {
  String? Function(String mint)? nameFor,
}) {
  bool positive(String raw) => BigInt.tryParse(raw)?.sign == 1;
  return [
    if (positive(holdings.usdc.availableToTradeRaw))
      SendAsset(
        id: 'USDC',
        symbol: 'USDC',
        name: 'US dollars (USDC)',
        decimals: 6,
        availableRaw: holdings.usdc.availableToTradeRaw,
        scale: LiveShareScale.plain(6),
      ),
    if (positive(holdings.nativeSol.amountRaw))
      SendAsset(
        id: 'SOL',
        symbol: 'SOL',
        name: 'Solana (SOL)',
        decimals: 9,
        availableRaw: holdings.nativeSol.amountRaw,
        scale: LiveShareScale.plain(9),
      ),
    for (final token in holdings.stockTokens)
      if (positive(token.availableToTradeRaw))
        SendAsset(
          id: token.mint,
          symbol: token.symbol,
          name: nameFor?.call(token.mint) ?? token.name,
          decimals: token.decimals,
          availableRaw: token.availableToTradeRaw,
          scale: LiveShareScale.fromDisplay(
            decimals: token.decimals,
            amountRaw: token.amountRaw,
            displayAmount: token.displayAmount,
          ),
        ),
  ];
}

/// The server's review of one send, checked field by field.
@immutable
class SendReview {
  const SendReview._({
    required this.assetId,
    required this.symbol,
    required this.decimals,
    required this.uiMultiplier,
    required this.from,
    required this.destination,
    required this.amountRaw,
    required this.receivedRaw,
    required this.createsAccount,
    required this.accountRentLamports,
    required this.networkFeeLamports,
    required this.expiresAt,
    required this.unsignedTransaction,
    required this.reviewToken,
  });

  final String assetId, symbol, uiMultiplier, from, destination;
  final int decimals;
  final String amountRaw, receivedRaw;
  final bool createsAccount;
  final String accountRentLamports, networkFeeLamports;
  final DateTime expiresAt;
  final String unsignedTransaction, reviewToken;

  static SendReview parse(Object? value) {
    Never invalid() => throw const SendFailure('TRANSFER_UNAVAILABLE');
    if (value is! Map) invalid();
    final review = value['review'],
        asset = review is Map ? review['asset'] : null;
    if (review is! Map || asset is! Map) invalid();
    final kind = asset['kind'],
        mint = asset['mint'],
        decimals = asset['decimals'];
    final expires = review['expiresAt'] is String
        ? DateTime.tryParse(review['expiresAt'] as String)
        : null;
    final wire = value['unsignedTransaction'], token = value['reviewToken'];
    bool raw(Object? v) => v is String && _raw.hasMatch(v);
    bool address(Object? v) => v is String && _address.hasMatch(v);
    if (!(kind == 'sol' && mint == null || kind == 'token' && address(mint)) ||
        asset['symbol'] is! String ||
        (asset['symbol'] as String).length > 24 ||
        decimals is! int ||
        decimals < 0 ||
        decimals > 18 ||
        asset['uiMultiplier'] is! String ||
        !address(review['from']) ||
        !address(review['destination']) ||
        !raw(review['amountRaw']) ||
        !raw(review['receivedRaw']) ||
        review['createsAccount'] is! bool ||
        !raw(review['accountRentLamports']) ||
        !raw(review['networkFeeLamports']) ||
        expires == null ||
        wire is! String ||
        wire.length > 1644 ||
        token is! String ||
        token.length > 1200) {
      invalid();
    }
    return SendReview._(
      assetId: kind == 'sol'
          ? 'SOL'
          : mint == 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'
          ? 'USDC'
          : mint as String,
      symbol: asset['symbol'] as String,
      decimals: decimals,
      uiMultiplier: asset['uiMultiplier'] as String,
      from: review['from'] as String,
      destination: review['destination'] as String,
      amountRaw: review['amountRaw'] as String,
      receivedRaw: review['receivedRaw'] as String,
      createsAccount: review['createsAccount'] as bool,
      accountRentLamports: review['accountRentLamports'] as String,
      networkFeeLamports: review['networkFeeLamports'] as String,
      expiresAt: expires.toUtc(),
      unsignedTransaction: wire,
      reviewToken: token,
    );
  }
}

/// Signed-in calls to the wallet transfer routes, for the account that
/// opened the flow only.
class WalletTransferClient {
  WalletTransferClient(this.origin, this.account, {http.Client? client})
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
  final http.Client _client;
  final bool _ownsClient;
  final String? _identity;
  final int _epoch;
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

  Future<Map> _call(
    String path, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    if (!current) throw const SendFailure('ACCOUNT_REQUIRED');
    final token = await account.freshAccessToken();
    if (!current || token.accountId != _identity) {
      throw const SendFailure('ACCOUNT_REQUIRED');
    }
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            origin
                .resolve('/v1/wallet/transfers/$path')
                .replace(queryParameters: query),
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
      if (bytes.length > 16384) throw const SendFailure('TRANSFER_UNAVAILABLE');
    }
    if (!current) throw const SendFailure('ACCOUNT_REQUIRED');
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const SendFailure('TRANSFER_UNAVAILABLE');
    }
    if (decoded is! Map) throw const SendFailure('TRANSFER_UNAVAILABLE');
    if (response.statusCode != 200) {
      throw SendFailure(decoded['code'] as String? ?? 'TRANSFER_UNAVAILABLE');
    }
    return decoded;
  }

  Future<SendReview> preview({
    required String asset,
    required String destination,
    required String amountRaw,
  }) async => SendReview.parse(
    await _call(
      'preview',
      body: {
        'asset': asset,
        'destination': destination,
        'amountRaw': amountRaw,
      },
    ),
  );

  Future<String> execute(SendReview review, String signedTransaction) async {
    final value = await _call(
      'execute',
      body: {
        'reviewToken': review.reviewToken,
        'signedTransaction': signedTransaction,
      },
    );
    final signature = value['signature'];
    if (signature is! String ||
        !RegExp(r'^[1-9A-HJ-NP-Za-km-z]{64,88}$').hasMatch(signature)) {
      throw const SendFailure('TRANSFER_UNAVAILABLE');
    }
    return signature;
  }

  /// 'pending', 'confirmed' or 'failed'.
  Future<String> status(String signature) async {
    final value = await _call('status', query: {'signature': signature});
    final status = value['status'];
    if (status is! String ||
        !const {'pending', 'confirmed', 'failed'}.contains(status)) {
      throw const SendFailure('TRANSFER_UNAVAILABLE');
    }
    return status;
  }
}

/// Send USDC, SOL or a stock token to another Solana wallet. The server
/// reviews and simulates the transfer; the user signs it here; nothing is
/// sent without that signature.
class SendMoneyFlow extends StatefulWidget {
  const SendMoneyFlow({
    super.key,
    required this.account,
    required this.origin,
    required this.onBack,
    this.nameFor,
    this.initialAsset,
    this.httpClient,
    this.pollInterval = const Duration(seconds: 2),
  });

  final AccountController account;
  final Uri origin;
  final VoidCallback onBack;
  final String? Function(String mint)? nameFor;

  /// `USDC`, `SOL` or a held token's mint to start with.
  final String? initialAsset;

  /// A supplied transport is caller-owned. Production creates its own client.
  final http.Client? httpClient;
  final Duration pollInterval;

  @override
  State<SendMoneyFlow> createState() => _SendMoneyFlowState();
}

enum _Stage { details, review, sending, done }

class _SendMoneyFlowState extends State<SendMoneyFlow> {
  late final _client = WalletTransferClient(
    widget.origin,
    widget.account,
    client: widget.httpClient,
  );
  final _to = TextEditingController();
  final _amount = TextEditingController();
  String? _assetId;
  SendReview? _review;
  _Stage _stage = _Stage.details;
  bool _busy = false;
  String? _error, _signature, _status;
  Timer? _poll;
  int _polls = 0;

  List<SendAsset> get _assets {
    final holdings = realWalletHoldings(widget.account);
    return holdings == null
        ? const []
        : sendableAssets(holdings, nameFor: widget.nameFor);
  }

  SendAsset? get _asset {
    final assets = _assets;
    for (final asset in assets) {
      if (asset.id == (_assetId ?? widget.initialAsset)) return asset;
    }
    return assets.isEmpty ? null : assets.first;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _client.close();
    _to.dispose();
    _amount.dispose();
    super.dispose();
  }

  String? get _ownAddress => realWalletHoldings(widget.account)?.wallet.address;

  String? _check(SendAsset asset) {
    final to = _to.text.trim();
    if (!_address.hasMatch(to)) return 'Enter a Solana wallet address.';
    if (to == _ownAddress) {
      return 'That’s your own wallet. Enter another address.';
    }
    final raw = asset.rawFor(_amount.text);
    if (raw == null) return 'Enter an amount.';
    if (BigInt.parse(raw) > BigInt.parse(asset.availableRaw)) {
      return 'You have ${asset.label(asset.availableRaw)} ${asset.symbol} ready to send.';
    }
    return null;
  }

  Future<void> _preview() async {
    final asset = _asset;
    if (asset == null || _busy) return;
    final problem = _check(asset);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final to = _to.text.trim(), amountRaw = asset.rawFor(_amount.text)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final review = await _client.preview(
        asset: asset.id,
        destination: to,
        amountRaw: amountRaw,
      );
      // The review must be the send that was asked for, from this wallet.
      if (review.assetId != asset.id ||
          review.destination != to ||
          review.amountRaw != amountRaw ||
          review.from != _ownAddress) {
        throw const SendFailure('TRANSFER_UNAVAILABLE');
      }
      if (!mounted) return;
      setState(() {
        _review = review;
        _stage = _Stage.review;
      });
    } on SendFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) setState(() => _error = const SendFailure('').message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final review = _review;
    if (review == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signed = await widget.account.signReviewedStockTransaction(
        wallet: review.from,
        transaction: review.unsignedTransaction,
        expiresAt: review.expiresAt,
      );
      final signature = await _client.execute(review, signed);
      if (!mounted) return;
      setState(() {
        _signature = signature;
        _status = 'pending';
        _stage = _Stage.sending;
      });
      _watch();
    } on WalletTradeException catch (failure) {
      if (!mounted) return;
      setState(
        () => _error = SendFailure(switch (failure.code) {
          'SIGNING_CANCELLED' => 'SIGNING_CANCELLED',
          'QUOTE_EXPIRED' => 'REVIEW_EXPIRED',
          _ => 'ACCOUNT_REQUIRED',
        }).message,
      );
    } on SendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        if (const {
          'REVIEW_EXPIRED',
          'INVALID_REVIEW',
          'INVALID_SIGNATURE',
        }.contains(failure.code)) {
          _review = null;
          _stage = _Stage.details;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = const SendFailure('').message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Checks the sent transaction for about a minute.
  void _watch() {
    _poll?.cancel();
    _poll = Timer.periodic(widget.pollInterval, (_) async {
      final signature = _signature;
      if (signature == null || !mounted) return;
      _polls++;
      try {
        final status = await _client.status(signature);
        if (!mounted) return;
        if (status != 'pending' || _polls >= 30) {
          _poll?.cancel();
          setState(() {
            _status = status;
            _stage = _Stage.done;
          });
          unawaited(widget.account.refreshPortfolio());
        }
      } catch (_) {
        if (_polls >= 30 && mounted) {
          _poll?.cancel();
          setState(() => _stage = _Stage.done);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _busy
                ? null
                : _stage == _Stage.review
                ? () => setState(() {
                    _review = null;
                    _stage = _Stage.details;
                  })
                : widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text('Send', style: type.titleLarge),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...switch (_stage) {
                  _Stage.details => _details(context),
                  _Stage.review => _reviewStep(context),
                  _Stage.sending || _Stage.done => _result(context),
                },
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ProductNotice(
                      key: const ValueKey('send-notice'),
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

  List<Widget> _details(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final assets = _assets, asset = _asset;
    if (asset == null) {
      return [
        const SizedBox(height: 28),
        Text('Nothing to send yet', style: type.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'Add money or buy a stock first. Anything in your wallet can be sent from here.',
          style: type.bodyLarge?.copyWith(color: ProductColor.muted),
        ),
      ];
    }
    return [
      Text('Send to a Solana wallet', style: type.headlineLarge),
      const SizedBox(height: 8),
      Text(
        'Only send to a Solana address. Sends can’t be undone.',
        style: type.bodyMedium?.copyWith(color: ProductColor.muted),
      ),
      const SizedBox(height: 22),
      DropdownButtonFormField<String>(
        key: const ValueKey('send-asset'),
        initialValue: asset.id,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'What to send'),
        items: [
          for (final option in assets)
            DropdownMenuItem(
              value: option.id,
              child: Text(
                '${option.name} · ${option.label(option.availableRaw)} ${option.symbol}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _busy
            ? null
            : (value) => setState(() {
                _assetId = value;
                _amount.clear();
                _error = null;
              }),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('send-destination'),
        controller: _to,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[1-9A-HJ-NP-Za-km-z]')),
          LengthLimitingTextInputFormatter(44),
        ],
        decoration: InputDecoration(
          labelText: 'Recipient’s wallet address',
          suffixIcon: IconButton(
            key: const ValueKey('send-paste'),
            tooltip: 'Paste',
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: _busy
                ? null
                : () async {
                    final text = (await Clipboard.getData(
                      'text/plain',
                    ))?.text?.trim();
                    if (text != null && mounted) {
                      setState(() => _to.text = text);
                    }
                  },
          ),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('send-amount'),
        controller: _amount,
        enabled: !_busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          LengthLimitingTextInputFormatter(40),
        ],
        decoration: InputDecoration(
          labelText: asset.stock ? 'Shares' : 'Amount (${asset.symbol})',
          helperText:
              '${asset.label(asset.availableRaw)} ${asset.symbol} ready to send',
          suffixIcon: TextButton(
            key: const ValueKey('send-max'),
            onPressed: _busy
                ? null
                : () => setState(
                    () => _amount.text = asset.stock
                        ? asset.scale.shares(asset.maxRaw)
                        : liveDecimal(asset.maxRaw, asset.decimals),
                  ),
            child: const Text('Max'),
          ),
        ),
      ),
      if (asset.id == 'SOL')
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Max keeps 0.002 SOL so you can still pay network fees.',
            style: type.bodySmall?.copyWith(color: ProductColor.muted),
          ),
        ),
      const SizedBox(height: 24),
      ProductButton(
        key: const ValueKey('send-review'),
        label: _busy ? 'Checking…' : 'Review send',
        onPressed: _busy ? null : _preview,
      ),
    ];
  }

  List<Widget> _reviewStep(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final review = _review!;
    final asset = _asset;
    final scale = review.assetId == 'SOL' || review.assetId == 'USDC'
        ? LiveShareScale.plain(review.decimals)
        : LiveShareScale.fromMultiplier(review.decimals, review.uiMultiplier);
    String amount(String raw) => asset?.stock == true
        ? '${scale.approx(raw)} ${review.symbol}'
        : '${formatRawUnits(raw, review.decimals) ?? raw} ${review.symbol}';
    return [
      Text('Review your send', style: type.headlineLarge),
      const SizedBox(height: 22),
      ProductCard(
        color: const Color(0xFFF6F3FB),
        child: Column(
          children: [
            _line(context, 'You send', amount(review.amountRaw)),
            if (review.receivedRaw != review.amountRaw)
              _line(
                context,
                'They receive, after the issuer fee',
                amount(review.receivedRaw),
              ),
            _line(
              context,
              'Network fee',
              '${liveDecimal(review.networkFeeLamports, 9)} SOL',
            ),
            if (review.createsAccount)
              _line(
                context,
                'Opens their ${review.symbol} account (once)',
                '${liveDecimal(review.accountRentLamports, 9)} SOL',
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Text('To this Solana wallet', style: type.titleMedium),
      const SizedBox(height: 8),
      SelectableText(
        review.destination,
        key: const ValueKey('send-review-destination'),
        style: type.bodyLarge?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: .4,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Check every character. Sends can’t be undone, and Trimmy can’t get money back from a wrong address.',
        style: type.bodyMedium?.copyWith(color: ProductColor.muted),
      ),
      const SizedBox(height: 22),
      ProductButton(
        key: const ValueKey('send-confirm'),
        label: _busy ? 'Sending…' : 'Send now',
        onPressed: _busy ? null : _send,
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _review = null;
                _stage = _Stage.details;
              }),
        child: const Text('Edit'),
      ),
    ];
  }

  Widget _line(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: ProductColor.muted),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    ),
  );

  List<Widget> _result(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final confirmed = _status == 'confirmed', failed = _status == 'failed';
    final waiting = _stage == _Stage.sending;
    return [
      const SizedBox(height: 28),
      Center(
        child: confirmed
            ? const ProductSuccessMark(size: 72)
            : waiting
            ? const TrimmyLiquidMark(size: 72)
            : Icon(
                failed ? Icons.error_outline_rounded : Icons.schedule_rounded,
                size: 54,
                color: ProductColor.violet,
              ),
      ),
      const SizedBox(height: 22),
      Text(
        confirmed
            ? 'Sent'
            : waiting
            ? 'Sending'
            : failed
            ? 'It didn’t go through'
            : 'Still confirming',
        key: const ValueKey('send-result'),
        textAlign: TextAlign.center,
        style: type.headlineMedium,
      ),
      const SizedBox(height: 12),
      Text(
        confirmed
            ? 'It’s confirmed on Solana.'
            : waiting
            ? 'This usually takes a few seconds.'
            : failed
            ? 'Solana refused it. Only the network fee was spent.'
            : 'It usually lands within a minute. Check it on Solscan.',
        textAlign: TextAlign.center,
        style: type.bodyLarge?.copyWith(color: ProductColor.muted),
      ),
      const SizedBox(height: 24),
      if (_signature != null)
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse('https://solscan.io/tx/$_signature'),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('View on Solscan'),
        ),
      if (!waiting)
        ProductButton(
          key: const ValueKey('send-done'),
          label: 'Done',
          onPressed: widget.onBack,
        ),
    ];
  }
}
