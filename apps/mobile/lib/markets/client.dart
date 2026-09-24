import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'discovery.dart';
import 'estimate.dart';
import 'validation.dart';

class StockResearchCancellation {
  final _cancelled = Completer<void>();
  final _listeners = <int, void Function()>{};
  var _nextListenerId = 0;
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  /// Registers a synchronous cancellation callback and returns an idempotent
  /// detach function. Transports must detach it when an operation settles so a
  /// reusable token does not retain completed request closures.
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
        // One observer cannot prevent the remaining transports from stopping.
      }
    }
  }
}

enum _StockResearchEndpoint { discovery, estimate }

abstract interface class StockResearchClient {
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  });
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  });
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  });
}

/// Public research reads only. Does not own the injected HTTP client, credentials
/// or wallets. Cancellation and close prevent late responses from being used.
class HttpStockResearchClient implements StockResearchClient {
  HttpStockResearchClient({
    required this._client,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) : _baseUri = baseUri,
       _timeout = timeout {
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(baseUri.host.toLowerCase());
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
      throw const StockResearchException('STOCK_INVALID_CONFIGURATION');
    }
  }
  final http.Client _client;
  final Uri _baseUri;
  final Duration _timeout;
  final _active = <StockResearchCancellation>{};
  bool _closed = false;
  static const maxResponseBytes = 1048576;

  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) async {
    try {
      researchText(query, 80);
      researchInteger(limit, 1, 20);
    } catch (_) {
      throw const StockResearchException('STOCK_INPUT_INVALID');
    }
    final page = StockSearchPage.fromJson(
      await _get(
        '/v1/markets/stocks/search',
        {'query': query, 'limit': '$limit'},
        _StockResearchEndpoint.discovery,
        cancellation,
      ),
    );
    if (page.query != query || page.limit != limit) researchInvalid();
    _checkCancellation(cancellation);
    return page;
  }

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) async {
    try {
      researchAssetId(assetId);
    } catch (_) {
      throw const StockResearchException('STOCK_INPUT_INVALID');
    }
    final page = StockVariantsPage.fromJson(
      await _get(
        '/v1/markets/stocks/variants',
        {'assetId': assetId},
        _StockResearchEndpoint.discovery,
        cancellation,
      ),
    );
    if (page.assetId != assetId) researchInvalid();
    _checkCancellation(cancellation);
    return page;
  }

  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) async {
    request.validate();
    final result = StockEstimate.fromJson(
      await _get(
        '/v1/markets/stocks/estimate',
        request.queryParameters,
        _StockResearchEndpoint.estimate,
        cancellation,
      ),
    );
    if (result.request != request) researchInvalid();
    _checkCancellation(cancellation);
    return result;
  }

  void _checkCancellation(StockResearchCancellation? cancellation) {
    if (_closed || cancellation?.isCancelled == true) {
      throw const StockResearchException('STOCK_CANCELLED');
    }
  }

  void close() {
    _closed = true;
    for (final cancellation in _active.toList()) {
      cancellation.cancel();
    }
  }

  Future<Object?> _get(
    String path,
    Map<String, String> query,
    _StockResearchEndpoint endpoint,
    StockResearchCancellation? cancellation,
  ) async {
    if (_closed || cancellation?.isCancelled == true) {
      throw const StockResearchException('STOCK_CANCELLED');
    }
    final operation = StockResearchCancellation();
    _active.add(operation);
    final abort = Completer<void>();
    final stopped = Completer<Object?>();
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

    // The future race is installed synchronously before cancellation callbacks.
    final timer = Timer(_timeout, () => stop('STOCK_TIMEOUT'));
    final detachOperation = operation.addCancellationListener(
      () => stop('STOCK_CANCELLED'),
    );
    void Function()? detachCaller;
    try {
      detachCaller = cancellation?.addCancellationListener(operation.cancel);
    } catch (_) {
      timer.cancel();
      detachOperation();
      operation.cancel();
      _active.remove(operation);
      throw const StockResearchException('STOCK_CANCELLED');
    }

    Future<Object?> perform() async {
      try {
        if (failure != null || _closed || cancellation?.isCancelled == true) {
          throw const StockResearchException('STOCK_CANCELLED');
        }
        final expectedUri = _baseUri.replace(
          path: path,
          queryParameters: query,
        );
        final request =
            http.AbortableRequest(
                'GET',
                expectedUri,
                abortTrigger: abort.future,
              )
              ..followRedirects = false
              ..maxRedirects = 0
              ..headers['accept'] = 'application/json';
        final response = await _client.send(request);
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
          throw const StockResearchException('STOCK_REDIRECT_REJECTED');
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          unawaited(
            response.stream.listen(null).cancel().catchError((Object _) {}),
          );
          throw const StockResearchException('STOCK_REDIRECT_REJECTED');
        }
        final declared = response.headers['content-length'];
        if (declared != null) {
          if (!RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(declared)) {
            unawaited(
              response.stream.listen(null).cancel().catchError((Object _) {}),
            );
            throw const StockResearchException('STOCK_RESPONSE_INVALID');
          }
          if (BigInt.parse(declared) > BigInt.from(maxResponseBytes)) {
            unawaited(
              response.stream.listen(null).cancel().catchError((Object _) {}),
            );
            throw const StockResearchException('STOCK_RESPONSE_TOO_LARGE');
          }
        }
        if ((response.contentLength ?? 0) > maxResponseBytes) {
          unawaited(
            response.stream.listen(null).cancel().catchError((Object _) {}),
          );
          throw const StockResearchException('STOCK_RESPONSE_TOO_LARGE');
        }
        final bytes = <int>[];
        final body = StreamIterator(response.stream);
        iterator = body;
        var completed = false;
        try {
          while (await body.moveNext()) {
            if (failure != null) throw failure!;
            if (bytes.length + body.current.length > maxResponseBytes) {
              throw const StockResearchException('STOCK_RESPONSE_TOO_LARGE');
            }
            bytes.addAll(body.current);
          }
          completed = true;
        } finally {
          // Avoid cancelling already exhausted streams across FakeAsync zones.
          if (!completed) unawaited(body.cancel().catchError((Object _) {}));
          iterator = null;
        }
        if (failure != null) throw failure!;
        final contentType = response.headers['content-type']
            ?.toLowerCase()
            .split(';')
            .map((value) => value.trim())
            .toList();
        if (contentType == null ||
            contentType.first != 'application/json' ||
            contentType
                .skip(1)
                .any(
                  (part) =>
                      part != 'charset=utf-8' && part != 'charset="utf-8"',
                )) {
          researchInvalid();
        }
        Object? value;
        try {
          value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        } catch (_) {
          researchInvalid();
        }
        if (response.statusCode != 200) {
          _serverFailure(endpoint, response.statusCode, value);
        }
        return value;
      } on StockResearchException {
        rethrow;
      } catch (_) {
        throw failure ?? const StockResearchException('STOCK_NETWORK_ERROR');
      }
    }

    try {
      return await Future.any([perform(), stopped.future]);
    } finally {
      timer.cancel();
      try {
        detachCaller?.call();
      } catch (_) {
        // Cleanup is terminal even for a malformed injected token subtype.
      }
      try {
        detachOperation();
      } catch (_) {
        // The internal token is currently infallible; keep shutdown contained.
      }
      _active.remove(operation);
    }
  }
}

const _discoveryErrorCodesByStatus = <int, Set<String>>{
  400: {'STOCK_INPUT_INVALID'},
  429: {'STOCK_RATE_LIMITED'},
  502: {'STOCK_PROVIDER_UNAVAILABLE', 'STOCK_RESPONSE_INVALID'},
  503: {'STOCK_DISCOVERY_UNAVAILABLE', 'STOCK_PROVIDER_AUTH_FAILED'},
  504: {'STOCK_TIMEOUT'},
};
const _estimateErrorCodesByStatus = <int, Set<String>>{
  400: {'MARKET_INPUT_INVALID'},
  429: {'MARKET_RATE_LIMITED'},
  502: {'MARKET_PROVIDER_UNAVAILABLE', 'MARKET_RESPONSE_INVALID'},
  503: {'MARKET_UNAVAILABLE', 'MARKET_PROVIDER_AUTH_FAILED'},
  504: {'MARKET_TIMEOUT', 'MARKET_ESTIMATE_STALE'},
};

Never _serverFailure(
  _StockResearchEndpoint endpoint,
  int status,
  Object? body,
) {
  final matrix = endpoint == _StockResearchEndpoint.discovery
      ? _discoveryErrorCodesByStatus
      : _estimateErrorCodesByStatus;
  if (body is Map<String, dynamic> &&
      body.length == 1 &&
      body['error'] is Map<String, dynamic>) {
    final error = body['error'] as Map<String, dynamic>;
    final code = error['code'];
    final message = error['message'];
    final requestId = error['requestId'];
    if (error.length == 3 &&
        error.containsKey('code') &&
        error.containsKey('message') &&
        error.containsKey('requestId') &&
        code is String &&
        message is String &&
        message.length <= 1024 &&
        requestId is String &&
        requestId.isNotEmpty &&
        requestId.length <= 128 &&
        matrix[status]?.contains(code) == true) {
      throw StockResearchException(code);
    }
  }
  throw const StockResearchException('STOCK_SERVICE_UNAVAILABLE');
}
