import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../account/account_controller.dart';
import '../../account/onramp_wallet_signer.dart';
import '../design/product_theme.dart';
import '../design/product_motion_icon.dart';
import '../design/product_success_mark.dart';

class OnrampFailure implements Exception {
  const OnrampFailure(this.code);
  final String code;
  String get message => switch (code) {
    'ONRAMP_NOT_ENABLED' =>
      'Card deposits aren’t available yet. You can still transfer from another wallet.',
    'ACCOUNT_REQUIRED' => 'Sign in again to continue.',
    'ONRAMP_EXPIRED' =>
      'This checkout needs to be checked with support. Your wallet balance will still update.',
    'ONRAMP_BUSY' => 'Give it a moment, then try again.',
    'ONRAMP_AMOUNT_INVALID' => 'Enter an amount from \$5 to \$10,000.',
    'WALLET_REQUIRED' ||
    'ONRAMP_WALLET_CHANGED' => 'Refresh your wallet before continuing.',
    _ => 'Couldn’t open payment. Try again in a moment.',
  };
}

/// Uses the documented Crossmint checkout URL. Card details and identity
/// documents stay in the system browser, outside Trimmy's app and API.
Uri crossmintCheckoutUri(Map<String, dynamic> order) {
  final environment = order['environment'];
  final clientKey = order['clientKey'];
  if ((environment != 'staging' && environment != 'production') ||
      clientKey is! String ||
      !clientKey.startsWith('ck_${environment}_') ||
      order['clientSecret'] is! String ||
      order['orderId'] is! String) {
    throw const OnrampFailure('ONRAMP_UNAVAILABLE');
  }
  return Uri.https(
    environment == 'staging' ? 'staging.crossmint.com' : 'www.crossmint.com',
    '/sdk/2024-03-05/embedded-checkout',
    {
      'apiKey': clientKey,
      'orderId': order['orderId'],
      'clientSecret': order['clientSecret'],
      'payment': jsonEncode({
        'crypto': {'enabled': false},
        'fiat': {
          'enabled': true,
          'allowedMethods': {'card': true, 'applePay': true, 'googlePay': true},
        },
      }),
      'appearance': jsonEncode({
        'variables': {
          'colors': {'accent': '#8056D9', 'backgroundPrimary': '#FFFFFF'},
        },
        'rules': {
          'DestinationInput': {'display': 'hidden'},
          'ReceiptEmailInput': {'display': 'hidden'},
        },
      }),
    },
  );
}

class CrossmintOnrampClient {
  CrossmintOnrampClient(this.origin, this.account, {http.Client? transport})
    : _http = transport ?? http.Client(),
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
  final http.Client _http;
  bool _closed = false;
  bool get current =>
      !_closed &&
      account.accountId == _identity &&
      _identity != null &&
      account.navigationEpoch == _epoch &&
      account.phase == AccountPhase.active;
  void close() {
    _closed = true;
    _http.close();
  }

  Future<Map<String, dynamic>> request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (!current) throw const OnrampFailure('ACCOUNT_REQUIRED');
    final token = await account.freshAccessToken();
    if (!current) throw const OnrampFailure('ACCOUNT_REQUIRED');
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            origin.resolve('/v1/funding/$path'),
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
    final response = await _http
        .send(request)
        .timeout(const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 32768) throw const OnrampFailure('ONRAMP_UNAVAILABLE');
    }
    if (!current) throw const OnrampFailure('ACCOUNT_REQUIRED');
    final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw OnrampFailure(value['code'] as String? ?? 'ONRAMP_UNAVAILABLE');
    }
    return value;
  }
}

class CrossmintOnrampForm extends StatefulWidget {
  const CrossmintOnrampForm({
    super.key,
    required this.account,
    required this.origin,
    required this.onTransfer,
  });
  final AccountController account;
  final Uri origin;
  final VoidCallback onTransfer;
  @override
  State<CrossmintOnrampForm> createState() => _CrossmintOnrampFormState();
}

class _CrossmintOnrampFormState extends State<CrossmintOnrampForm>
    with WidgetsBindingObserver {
  late final _client = CrossmintOnrampClient(widget.origin, widget.account);
  final _storage = const FlutterSecureStorage();
  late final _storageKey =
      'trimmy.onramp.pending.v1.${widget.account.accountId}';
  final _amount = TextEditingController(text: '50');
  final _email = TextEditingController();
  Map<String, dynamic>? _capability, _order, _challenge;
  String? _walletToken, _error, _creationId;
  bool _busy = true,
      _checking = false,
      _finished = false,
      _deliveryFailed = false;
  bool _active = true;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _client.close();
    _amount.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && _order != null) unawaited(_check());
  }

  void _showError(Object error) {
    if (mounted) {
      setState(
        () => _error = error is OnrampFailure
            ? error.message
            : 'This step didn’t finish. Try again.',
      );
    }
  }

  Future<void> _load() async {
    try {
      _capability = await _client.request('capabilities');
      final saved = await _storage.read(key: _storageKey);
      if (saved != null && _client.current) {
        _order = jsonDecode(saved) as Map<String, dynamic>;
        crossmintCheckoutUri(_order!);
        _watch();
        unawaited(_check());
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continue() async {
    if (_busy || !_client.current) return;
    final amount = _amount.text.trim(), email = _email.text.trim();
    if (!RegExp(r'^(?:0|[1-9][0-9]{0,4})(?:\.[0-9]{1,2})?$').hasMatch(amount) ||
        double.parse(amount) < 5 ||
        double.parse(amount) > 10000) {
      _showError(const OnrampFailure('ONRAMP_AMOUNT_INVALID'));
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter an email for your receipt.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_walletToken == null && _challenge == null) {
        final link = await _client.request('wallet', {'email': email});
        if (link['verified'] == true) {
          _walletToken = link['walletToken'] as String;
        } else {
          _challenge = link;
          return;
        }
      } else if (_challenge != null) {
        final challenge = OnrampWalletChallenge.parse(
          wallet: _challenge!['wallet'],
          message: _challenge!['message'],
        );
        final signature = await widget.account.signOnrampOwnership(challenge);
        final link = await _client.request('verify', {
          'challengeToken': _challenge!['challengeToken'],
          'proof': signature,
        });
        _walletToken = link['walletToken'] as String;
        _challenge = null;
      }
      if (!_client.current) return;
      final order = await _client.request('orders', {
        'walletToken': _walletToken,
        'amount': amount,
        'requestId': _creationId ??= _requestId(),
      });
      if (order['wallet'] !=
          widget
              .account
              .portfolioState
              ?.context
              ?.embeddedSolanaWallet
              .address) {
        throw const OnrampFailure('ONRAMP_WALLET_CHANGED');
      }
      crossmintCheckoutUri(order);
      // Persist before opening payment. Relaunching can resume the same order;
      // credentials stay in platform secure storage, scoped to the saved account.
      await _storage.write(key: _storageKey, value: jsonEncode(order));
      if (!mounted || !_client.current) return;
      setState(() => _order = order);
      _watch();
      await _openCheckout();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCheckout() async {
    if (!_client.current || _order == null) return;
    try {
      final opened = await launchUrl(
        crossmintCheckoutUri(_order!),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw const OnrampFailure('ONRAMP_UNAVAILABLE');
    } catch (error) {
      _showError(error);
    }
  }

  void _watch() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_active) unawaited(_check());
    });
  }

  Future<void> _check() async {
    if (_checking ||
        _order == null ||
        !_client.current ||
        _finished ||
        _deliveryFailed) {
      return;
    }
    _checking = true;
    try {
      final result = await _client.request('status', {
        'orderToken': _order!['orderToken'],
      });
      if (!mounted) return;
      if (result['status'] == 'completed') {
        _timer?.cancel();
        await _storage.delete(key: _storageKey);
        if (!mounted || !_client.current) return;
        setState(() {
          _finished = true;
          _error = null;
        });
        if (result['environment'] == 'production') {
          await widget.account.refreshPortfolio();
        }
      } else if (result['status'] == 'failed') {
        _timer?.cancel();
        setState(() => _deliveryFailed = true);
      }
    } catch (error) {
      if (error is OnrampFailure && error.code == 'ONRAMP_EXPIRED') {
        _timer?.cancel();
        _showError(error);
      } else if (mounted) {
        setState(
          () => _error =
              'Couldn’t refresh this deposit. Check again before paying again.',
        );
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    if (_order != null) {
      final test = _order!['environment'] == 'staging';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 22),
          Center(
            child: _finished
                ? const ProductSuccessMark(size: 64)
                : const ProductMotionIcon(file: 'asset-bell.png', size: 64),
          ),
          const SizedBox(height: 20),
          Text(
            _finished
                ? (test ? 'Test deposit complete' : 'Money added')
                : _deliveryFailed
                ? 'Deposit needs attention'
                : 'Finish your deposit',
            style: type.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            _finished
                ? (test
                      ? 'Test USDC arrived on Solana devnet.'
                      : 'Your USDC is in your wallet.')
                : _deliveryFailed
                ? 'Contact Crossmint with this order ID. Don’t pay again.'
                : 'Finish payment in your browser, then return here.',
            style: type.bodyLarge,
          ),
          const SizedBox(height: 20),
          if (!_finished && !_deliveryFailed)
            FilledButton(
              onPressed: _openCheckout,
              child: const Text('Open payment'),
            ),

          if (_error != null) Text(_error!, style: type.bodyMedium),
          const SizedBox(height: 12),
          SelectableText('Order ${_order!['orderId']}', style: type.bodySmall),
        ],
      );
    }
    if (_capability?['enabled'] != true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          Text(
            _busy
                ? 'Checking payment options…'
                : _error ?? 'Card deposits aren’t available yet.',
            style: type.bodyLarge,
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: widget.onTransfer,
            child: const Text('Transfer from a wallet'),
          ),
          if (!_busy)
            TextButton(
              onPressed: () {
                setState(() {
                  _busy = true;
                  _error = null;
                });
                unawaited(_load());
              },
              child: const Text('Try again'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        if (_capability?['environment'] == 'staging')
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Test checkout',
              style: type.labelLarge?.copyWith(color: ProductColor.ink),
            ),
          ),
        Text('Amount', style: type.titleMedium),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: ShapeDecoration(
            color: const Color(0xFFF5F1FC),
            shape: productSquircle(24),
          ),
          child: TextField(
            key: const ValueKey('onramp-amount'),
            controller: _amount,
            onChanged: (_) => _creationId = null,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: type.headlineLarge,
            decoration: const InputDecoration(
              filled: false,
              prefixText: '\$ ',
              suffixText: 'USD',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final amount in ['25', '50', '100'])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _amount.text = amount;
                            _creationId = null;
                          }),
                    child: Text('\$$amount'),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('onramp-email'),
          controller: _email,
          enabled: !_busy && _walletToken == null && _challenge == null,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: 'Receipt email',
            filled: true,
            fillColor: ProductColor.paperRaised,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _challenge == null
              ? 'USDC on Solana · fees shown at checkout'
              : 'Confirm this wallet is yours. This signs a message, not a payment.',
          style: type.bodyMedium,
        ),
        if (_challenge != null)
          ExpansionTile(
            title: const Text('Verification message'),
            shape: const Border(),
            collapsedShape: const Border(),
            children: [
              SelectableText(
                _challenge!['message'] as String,
                style: type.bodySmall,
              ),
            ],
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: type.bodyMedium),
          ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy ? null : _continue,
          child: Text(
            _busy
                ? 'One moment…'
                : _challenge == null
                ? 'Continue'
                : 'Verify & continue',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Powered by Crossmint',
          style: type.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

String _requestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
