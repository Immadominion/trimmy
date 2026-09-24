import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'stock_facts.dart';
import 'public_holders.dart';

const _cardsPath = '/v1/markets/stocks/cards';
const _factsPath = '/v1/markets/stocks/facts';
const _maximumResponseBytes = 262144;

/// Reads the public stock facts routes. No credential is sent or retained,
/// no redirect is followed, and every response is bounded and parsed strictly.
final class HttpStockFactsRepository
    implements StockFactsRepository, StockInsightReader, PublicHoldersReader {
  HttpStockFactsRepository({
    required http.Client transport,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 15),
    bool allowLoopbackForTests = false,
  }) : _client = transport,
       _baseUri = _origin(baseUri, allowLoopbackForTests),
       _timeout = timeout {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw const StockFactsException(StockFactsFailure.unavailable);
    }
  }

  final http.Client _client;
  final Uri _baseUri;
  final Duration _timeout;
  bool _closed = false;

  @override
  Future<StockCardsPage> cards(String query, {int limit = 10}) async {
    if (query.isEmpty ||
        query.length > 80 ||
        query.trim() != query ||
        query.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f) ||
        limit < 1 ||
        limit > 20) {
      throw const StockFactsException(StockFactsFailure.invalidInput);
    }
    final decoded = await _get(
      _baseUri.replace(
        path: _cardsPath,
        queryParameters: {'query': query, 'limit': '$limit'},
      ),
    );
    final page = StockCardsPage.fromJson(decoded);
    if (page.query != query || page.limit != limit) {
      throw const StockFactsException(StockFactsFailure.invalidResponse);
    }
    return page;
  }

  @override
  Future<StockFacts> facts(String assetId) async {
    if (assetId.isEmpty ||
        assetId.length > 100 ||
        !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(assetId)) {
      throw const StockFactsException(StockFactsFailure.invalidInput);
    }
    final decoded = await _get(
      _baseUri.replace(path: _factsPath, queryParameters: {'assetId': assetId}),
    );
    final facts = StockFacts.fromJson(decoded);
    if (facts.assetId != assetId) {
      throw const StockFactsException(StockFactsFailure.invalidResponse);
    }
    return facts;
  }

  @override
  Future<StockInsight> insight(
    String assetId,
    String mint,
    String period,
  ) async {
    final data = await _get(
      _baseUri.replace(
        path: '/v1/markets/stocks/insight',
        queryParameters: {'assetId': assetId, 'mint': mint, 'period': period},
      ),
    );
    final insight = StockInsight.fromJson(data);
    if (insight.assetId != assetId ||
        insight.mint != mint ||
        insight.period != period) {
      throw const StockFactsException(StockFactsFailure.invalidResponse);
    }
    return insight;
  }

  @override
  Future<PublicHoldersPage> holders(String mint) async {
    final data = await _get(
      _baseUri.replace(
        path: '/v1/markets/stocks/holders',
        queryParameters: {'mint': mint},
      ),
    );
    final page = PublicHoldersPage.fromJson(data);
    if (page.mint != mint) {
      throw const StockFactsException(StockFactsFailure.invalidResponse);
    }
    return page;
  }

  Future<Object?> _get(Uri uri) async {
    if (_closed) throw const StockFactsException(StockFactsFailure.unavailable);
    var timedOut = false;
    final abort = Completer<void>();
    StreamIterator<List<int>>? iterator;

    Future<Object?> perform() async {
      final request =
          http.AbortableRequest('GET', uri, abortTrigger: abort.future)
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['accept'] = 'application/json';
      try {
        final response = await _client.send(request);
        if (timedOut || _closed) {
          await response.stream.listen(null).cancel();
          throw const StockFactsException(StockFactsFailure.timeout);
        }
        if (response.isRedirect ||
            response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.listen(null).cancel();
          throw const StockFactsException(StockFactsFailure.unavailable);
        }
        if ((response.contentLength ?? 0) > _maximumResponseBytes) {
          await response.stream.listen(null).cancel();
          throw const StockFactsException(StockFactsFailure.invalidResponse);
        }
        final bytes = <int>[];
        iterator = StreamIterator(response.stream);
        while (await iterator!.moveNext()) {
          if (timedOut || _closed) {
            throw const StockFactsException(StockFactsFailure.timeout);
          }
          final chunk = iterator!.current;
          if (bytes.length + chunk.length > _maximumResponseBytes) {
            throw const StockFactsException(StockFactsFailure.invalidResponse);
          }
          bytes.addAll(chunk);
        }
        iterator = null;
        if (response.statusCode != 200) {
          throw StockFactsException(
            _failure(response.statusCode),
            retryAfter: _retryAfter(response.headers['retry-after']),
          );
        }
        _jsonContentType(response.headers['content-type']);
        try {
          return jsonDecode(utf8.decode(bytes, allowMalformed: false));
        } catch (_) {
          throw const StockFactsException(StockFactsFailure.invalidResponse);
        }
      } on StockFactsException {
        rethrow;
      } catch (_) {
        if (timedOut) {
          throw const StockFactsException(StockFactsFailure.timeout);
        }
        throw const StockFactsException(StockFactsFailure.offline);
      }
    }

    try {
      return await perform().timeout(
        _timeout,
        onTimeout: () {
          timedOut = true;
          if (!abort.isCompleted) abort.complete();
          final current = iterator;
          if (current != null) {
            unawaited(current.cancel().catchError((Object _) {}));
          }
          throw const StockFactsException(StockFactsFailure.timeout);
        },
      );
    } finally {
      final current = iterator;
      if (current != null) {
        await current.cancel().catchError((Object _) {});
      }
    }
  }

  void close() => _closed = true;
}

StockFactsFailure _failure(int status) => switch (status) {
  400 => StockFactsFailure.invalidInput,
  429 => StockFactsFailure.rateLimited,
  504 => StockFactsFailure.timeout,
  _ => StockFactsFailure.unavailable,
};

Duration? _retryAfter(String? value) {
  final seconds = int.tryParse(value ?? '');
  if (seconds == null || seconds < 0 || seconds > 3600) return null;
  return Duration(seconds: seconds);
}

void _jsonContentType(String? value) {
  final parts = value?.toLowerCase().split(';').map((part) => part.trim());
  if (parts == null ||
      parts.first != 'application/json' ||
      parts
          .skip(1)
          .any(
            (part) => part != 'charset=utf-8' && part != 'charset="utf-8"',
          )) {
    throw const StockFactsException(StockFactsFailure.invalidResponse);
  }
}

Uri _origin(Uri value, bool allowLoopback) {
  final loopback = const {
    'localhost',
    '127.0.0.1',
    '::1',
    '[::1]',
  }.contains(value.host.toLowerCase());
  final valid =
      value.hasAuthority &&
      value.host.isNotEmpty &&
      !value.host.endsWith('.') &&
      value.userInfo.isEmpty &&
      !value.hasFragment &&
      !value.hasQuery &&
      (value.path.isEmpty || value.path == '/') &&
      (value.scheme == 'https' ||
          allowLoopback && loopback && value.scheme == 'http');
  if (!valid) throw const StockFactsException(StockFactsFailure.unavailable);
  return Uri(
    scheme: value.scheme,
    host: value.host,
    port: value.hasPort ? value.port : null,
  );
}
