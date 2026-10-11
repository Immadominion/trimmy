import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../practice_sync/http_transport.dart';
import 'incoming_funding_models.dart';

abstract interface class IncomingFundingClient {
  Future<FundingReview> preview(String from, String asset, String amountRaw);
  Future<FundingReceipt> status(FundingReview review, String signature);
  void close();
}

/// Retains no bearer and cannot change the account or recipient.
class HttpIncomingFundingClient implements IncomingFundingClient {
  static Future<bool> available(http.Client client, Uri origin) async {
    try {
      final uri = origin.resolve('/v1/wallet/funding/capabilities');
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 ||
          response.isRedirect ||
          (response.contentLength ?? 0) > 1024 ||
          response.request != null && response.request!.url != uri) {
        await response.stream.listen(null).cancel();
        return false;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 1024) return false;
      }
      final value = jsonDecode(utf8.decode(bytes));
      return value is Map &&
          value['enabled'] == true &&
          value['chain'] == 'solana:mainnet' &&
          value['assets'] is List &&
          (value['assets'] as List).length == 2 &&
          (value['assets'] as List).contains('SOL') &&
          (value['assets'] as List).contains('USDC');
    } catch (_) {
      return false;
    }
  }

  HttpIncomingFundingClient({
    required this.client,
    required this.origin,
    required this.accountId,
    required this.accessToken,
    required this.isCurrent,
    this.timeout = const Duration(seconds: 15),
    bool allowLoopbackForTests = false,
  }) {
    if (!origin.hasAuthority ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        !{'', '/'}.contains(origin.path) ||
        !(origin.scheme == 'https' ||
            allowLoopbackForTests &&
                origin.scheme == 'http' &&
                {'127.0.0.1', 'localhost', '::1'}.contains(origin.host))) {
      throw const FundingFailure('UNAVAILABLE');
    }
  }
  final http.Client client;
  final Uri origin;
  final String accountId;
  final Future<PracticeAccessToken> Function() accessToken;
  final bool Function() isCurrent;
  final Duration timeout;
  bool _closed = false;
  Completer<void>? _abort;

  void _check() {
    if (_closed || !isCurrent()) throw const FundingFailure('ACCOUNT_CHANGED');
  }

  Future<Object?> _call(String path, Map<String, Object?> body) async {
    _check();
    if (_abort != null) throw const FundingFailure('BUSY');
    final abort = Completer<void>();
    _abort = abort;
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final token = await accessToken().timeout(timeout);
      _check();
      if (abort.isCompleted) throw const FundingFailure('TIMEOUT');
      if (token.accountId != accountId ||
          token.token.isEmpty ||
          token.token.length > 8192 ||
          !RegExp(r'^[A-Za-z0-9\-._~+/]+=*$').hasMatch(token.token)) {
        throw const FundingFailure('ACCOUNT_CHANGED');
      }
      final uri = origin.resolve('/v1/wallet/funding/$path');
      final req = http.AbortableRequest('POST', uri, abortTrigger: abort.future)
        ..followRedirects = false
        ..headers.addAll({
          'authorization': 'Bearer ${token.token}',
          'content-type': 'application/json',
          'accept': 'application/json',
        })
        ..body = jsonEncode(body);
      final response = await client.send(req).timeout(timeout);
      if (response.isRedirect ||
          response.statusCode >= 300 && response.statusCode < 400 ||
          (response.contentLength ?? 0) > 8192 ||
          response.request != null && response.request!.url != uri ||
          !(response.headers['content-type'] ?? '').toLowerCase().startsWith(
            'application/json',
          )) {
        await response.stream.listen(null).cancel();
        throw const FundingFailure('INVALID_RESPONSE');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        _check();
        if (abort.isCompleted) throw const FundingFailure('TIMEOUT');
        bytes.addAll(chunk);
        if (bytes.length > 8192) throw const FundingFailure('INVALID_RESPONSE');
      }
      _check();
      if (abort.isCompleted) throw const FundingFailure('TIMEOUT');
      final Object? decoded = jsonDecode(utf8.decode(bytes));
      if (response.statusCode != 200) {
        final code = decoded is Map ? decoded['code'] : null;
        throw FundingFailure(
          code is String && code.length < 80 ? code : 'UNAVAILABLE',
        );
      }
      return decoded;
    } on FundingFailure {
      rethrow;
    } catch (_) {
      _check();
      throw const FundingFailure('UNAVAILABLE');
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
    }
  }

  @override
  Future<FundingReview> preview(
    String from,
    String asset,
    String amountRaw,
  ) async {
    if (!fundingAddress(from) ||
        !{'SOL', 'USDC'}.contains(asset) ||
        fundingRaw(amountRaw, positive: true) == null) {
      throw const FundingFailure('INVALID_AMOUNT');
    }
    return FundingReview.parse(
      await _call('preview', {
        'from': from,
        'asset': asset,
        'amountRaw': amountRaw,
      }),
    );
  }

  @override
  Future<FundingReceipt> status(FundingReview review, String signature) async {
    if (!fundingSignature(signature)) {
      throw const FundingFailure('INVALID_SIGNATURE');
    }
    return FundingReceipt.parse(
      await _call('status', {
        'from': review.from,
        'reviewToken': review.token,
        'signature': signature,
      }),
    );
  }

  @override
  void close() {
    _closed = true;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    // AccountController owns the HTTP client.
  }
}
