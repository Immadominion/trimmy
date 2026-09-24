import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'raydium_quote_models.dart';
import 'validation.dart' show StockResearchException;

/// A reusable cancellation token dedicated to Raydium quote reads.
///
/// Settled requests detach their callbacks so retaining and reusing a token
/// cannot retain old transport closures.
final class RaydiumQuoteCancellation {
  final _cancelled = Completer<void>();
  final _listeners = <int, void Function()>{};
  var _nextListenerId = 0;

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  /// Exposed only so focused transport tests can prove listener cleanup.
  int get debugListenerCount => _listeners.length;

  void Function() addCancellationListener(void Function() listener) {
    if (isCancelled) {
      try {
        listener();
      } catch (_) {
        // A late observer cannot make an already completed cancellation throw.
      }
      return () {};
    }
    final id = _nextListenerId++;
    _listeners[id] = listener;
    var attached = true;
    return () {
      if (!attached) return;
      attached = false;
      _listeners.remove(id);
      if (_listeners.isEmpty) _nextListenerId = 0;
    };
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    final listeners = _listeners.values.toList(growable: false);
    _listeners.clear();
    _nextListenerId = 0;
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {
        // One observer cannot stop transport cancellation or listener cleanup.
      }
    }
  }
}

abstract interface class RaydiumQuoteClient {
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  });
}

/// Public, read-only transport for Trimmy's fixed Raydium quote route.
///
/// It owns no wallet or credentials, does not retry, and has no transaction,
/// simulation, signing, or broadcast method. Closing it does not close the
/// injected HTTP client.
final class HttpRaydiumQuoteClient implements RaydiumQuoteClient {
  HttpRaydiumQuoteClient({
    required this._client,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) : _baseUri = baseUri,
       _timeout = timeout {
    final host = baseUri.host.toLowerCase();
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(host);
    if (!baseUri.hasAuthority ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.path.isNotEmpty && baseUri.path != '/') ||
        baseUri.port < 1 ||
        baseUri.port > 65535 ||
        (baseUri.scheme != 'https' &&
            !(allowLoopbackForTests && baseUri.scheme == 'http' && loopback)) ||
        timeout <= Duration.zero ||
        timeout > const Duration(seconds: 30)) {
      throw const StockResearchException('RAYDIUM_QUOTE_INVALID_CONFIGURATION');
    }
  }

  static const maxResponseBytes = 65536;

  final http.Client _client;
  final Uri _baseUri;
  final Duration _timeout;
  final _active = <RaydiumQuoteCancellation>{};
  var _closed = false;

  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) async {
    request.validate();
    return _request(request, cancellation);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final operation in _active.toList(growable: false)) {
      operation.cancel();
    }
  }

  Future<RaydiumStockQuote> _request(
    RaydiumQuoteRequest request,
    RaydiumQuoteCancellation? cancellation,
  ) async {
    if (_closed || cancellation?.isCancelled == true) {
      throw const StockResearchException('RAYDIUM_QUOTE_CANCELLED');
    }
    final operation = RaydiumQuoteCancellation();
    _active.add(operation);
    final abort = Completer<void>();
    final stopped = Completer<RaydiumStockQuote>();
    StockResearchException? failure;
    StreamIterator<List<int>>? iterator;

    void stop(String code) {
      if (failure != null) return;
      failure = StockResearchException(code);
      if (!abort.isCompleted) abort.complete();
      final body = iterator;
      if (body != null) unawaited(body.cancel().catchError((Object _) {}));
      if (!stopped.isCompleted) stopped.completeError(failure!);
    }

    final timer = Timer(_timeout, () => stop('MARKET_TIMEOUT'));
    final detachOperation = operation.addCancellationListener(
      () => stop('RAYDIUM_QUOTE_CANCELLED'),
    );
    void Function()? detachCaller;
    try {
      detachCaller = cancellation?.addCancellationListener(operation.cancel);
    } catch (_) {
      timer.cancel();
      detachOperation();
      operation.cancel();
      _active.remove(operation);
      throw const StockResearchException('RAYDIUM_QUOTE_CANCELLED');
    }

    Future<RaydiumStockQuote> perform() async {
      try {
        if (failure != null || _closed || cancellation?.isCancelled == true) {
          throw const StockResearchException('RAYDIUM_QUOTE_CANCELLED');
        }
        final expectedUri = _baseUri.replace(
          path: raydiumStockQuoteRoute,
          queryParameters: request.queryParameters,
        );
        final outbound =
            http.AbortableRequest(
                'GET',
                expectedUri,
                abortTrigger: abort.future,
              )
              ..followRedirects = false
              ..maxRedirects = 0
              ..headers['accept'] = 'application/json';
        final response = await _client.send(outbound);
        if (failure != null) {
          unawaited(
            response.stream.listen(null).cancel().catchError((Object _) {}),
          );
          throw failure!;
        }
        final finalRequest = response.request;
        if (finalRequest != null &&
            (finalRequest.method != 'GET' || finalRequest.url != expectedUri)) {
          unawaited(
            response.stream.listen(null).cancel().catchError((Object _) {}),
          );
          throw const StockResearchException('RAYDIUM_QUOTE_REDIRECT_REJECTED');
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          unawaited(
            response.stream.listen(null).cancel().catchError((Object _) {}),
          );
          throw const StockResearchException('RAYDIUM_QUOTE_REDIRECT_REJECTED');
        }
        final declared = response.headers['content-length'];
        if (declared != null) {
          if (!RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(declared)) {
            unawaited(
              response.stream.listen(null).cancel().catchError((Object _) {}),
            );
            throw const StockResearchException(
              'RAYDIUM_QUOTE_RESPONSE_INVALID',
            );
          }
          if (BigInt.parse(declared) > BigInt.from(maxResponseBytes)) {
            unawaited(
              response.stream.listen(null).cancel().catchError((Object _) {}),
            );
            throw const StockResearchException(
              'RAYDIUM_QUOTE_RESPONSE_TOO_LARGE',
            );
          }
        }
        if ((response.contentLength ?? 0) > maxResponseBytes) {
          unawaited(
            response.stream.listen(null).cancel().catchError((Object _) {}),
          );
          throw const StockResearchException(
            'RAYDIUM_QUOTE_RESPONSE_TOO_LARGE',
          );
        }
        final bytes = <int>[];
        final body = StreamIterator(response.stream);
        iterator = body;
        var completed = false;
        try {
          while (await body.moveNext()) {
            if (failure != null) throw failure!;
            if (bytes.length + body.current.length > maxResponseBytes) {
              throw const StockResearchException(
                'RAYDIUM_QUOTE_RESPONSE_TOO_LARGE',
              );
            }
            bytes.addAll(body.current);
          }
          completed = true;
        } finally {
          if (!completed) unawaited(body.cancel().catchError((Object _) {}));
          iterator = null;
        }
        if (failure != null) throw failure!;
        if (!_validJsonContentType(response.headers['content-type'])) {
          throw const StockResearchException('RAYDIUM_QUOTE_RESPONSE_INVALID');
        }
        String source;
        try {
          source = utf8.decode(bytes, allowMalformed: false);
        } catch (_) {
          throw const StockResearchException('RAYDIUM_QUOTE_RESPONSE_INVALID');
        }
        if (response.statusCode != 200) {
          final code = parseRaydiumQuoteServerError(
            source,
            response.statusCode,
          );
          throw StockResearchException(code);
        }
        final quote = RaydiumStockQuote.parse(source, request: request);
        if (failure != null || _closed || cancellation?.isCancelled == true) {
          throw const StockResearchException('RAYDIUM_QUOTE_CANCELLED');
        }
        return quote;
      } on StockResearchException {
        rethrow;
      } catch (_) {
        throw failure ??
            const StockResearchException('RAYDIUM_QUOTE_NETWORK_ERROR');
      }
    }

    try {
      return await Future.any([perform(), stopped.future]);
    } finally {
      timer.cancel();
      try {
        detachCaller?.call();
      } catch (_) {
        // Cleanup stays terminal for a malformed injected token subtype.
      }
      try {
        detachOperation();
      } catch (_) {
        // The internal token is infallible; contain adapter failures anyway.
      }
      _active.remove(operation);
    }
  }
}

bool _validJsonContentType(String? raw) {
  if (raw == null) return false;
  final parts = raw
      .toLowerCase()
      .split(';')
      .map((value) => value.trim())
      .toList(growable: false);
  return parts.first == 'application/json' &&
      parts
          .skip(1)
          .every(
            (value) => value == 'charset=utf-8' || value == 'charset="utf-8"',
          );
}
