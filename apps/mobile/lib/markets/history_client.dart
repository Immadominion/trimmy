import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'client.dart' show StockResearchCancellation;
import 'history_models.dart';
import 'validation.dart';

abstract interface class StockHistoryClient {
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  });
}

/// Public read-only history transport. It has no wallet, credential, signer,
/// transaction, simulation, quote, or execution method.
final class HttpStockHistoryClient implements StockHistoryClient {
  HttpStockHistoryClient({
    required this._client,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
    DateTime Function()? now,
  }) : _baseUri = baseUri,
       _timeout = timeout,
       _now = now ?? DateTime.now {
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
      throw const StockResearchException('STOCK_HISTORY_INVALID_CONFIGURATION');
    }
  }

  static const maxResponseBytes = 1048576;

  final http.Client _client;
  final Uri _baseUri;
  final Duration _timeout;
  final DateTime Function() _now;
  final _active = <StockResearchCancellation>{};
  bool _closed = false;

  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) async {
    final nowUnixSeconds = _readNow().millisecondsSinceEpoch ~/ 1000;
    request.validateAt(nowUnixSeconds);
    return _request(request, cancellation);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final operation in _active.toList(growable: false)) {
      operation.cancel();
    }
  }

  Future<StockHistoryPage> _request(
    StockHistoryRequest request,
    StockResearchCancellation? cancellation,
  ) async {
    if (_closed || cancellation?.isCancelled == true) {
      throw const StockResearchException('STOCK_HISTORY_CANCELLED');
    }
    final operation = StockResearchCancellation();
    _active.add(operation);
    final abort = Completer<void>();
    final stopped = Completer<StockHistoryPage>();
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

    final timer = Timer(_timeout, () => stop('STOCK_HISTORY_TIMEOUT'));
    final detachOperation = operation.addCancellationListener(
      () => stop('STOCK_HISTORY_CANCELLED'),
    );
    void Function()? detachCaller;
    try {
      detachCaller = cancellation?.addCancellationListener(operation.cancel);
    } catch (_) {
      timer.cancel();
      detachOperation();
      operation.cancel();
      _active.remove(operation);
      throw const StockResearchException('STOCK_HISTORY_CANCELLED');
    }

    Future<StockHistoryPage> perform() async {
      try {
        if (failure != null || _closed || cancellation?.isCancelled == true) {
          throw const StockResearchException('STOCK_HISTORY_CANCELLED');
        }
        final expectedUri = _baseUri.replace(
          path: stockHistoryRoute,
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
          throw const StockResearchException('STOCK_HISTORY_REDIRECT_REJECTED');
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          unawaited(
            response.stream.listen(null).cancel().catchError((Object _) {}),
          );
          throw const StockResearchException('STOCK_HISTORY_REDIRECT_REJECTED');
        }
        final declaredHeader = response.headers['content-length'];
        if (declaredHeader != null) {
          if (!RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(declaredHeader)) {
            unawaited(
              response.stream.listen(null).cancel().catchError((Object _) {}),
            );
            throw const StockResearchException(
              'STOCK_HISTORY_RESPONSE_INVALID',
            );
          }
          if (BigInt.parse(declaredHeader) > BigInt.from(maxResponseBytes)) {
            unawaited(
              response.stream.listen(null).cancel().catchError((Object _) {}),
            );
            throw const StockResearchException(
              'STOCK_HISTORY_RESPONSE_TOO_LARGE',
            );
          }
        }
        if ((response.contentLength ?? 0) > maxResponseBytes) {
          unawaited(
            response.stream.listen(null).cancel().catchError((Object _) {}),
          );
          throw const StockResearchException(
            'STOCK_HISTORY_RESPONSE_TOO_LARGE',
          );
        }
        if (!_validJsonContentType(response.headers['content-type'])) {
          unawaited(
            response.stream.listen(null).cancel().catchError((Object _) {}),
          );
          throw const StockResearchException('STOCK_HISTORY_RESPONSE_INVALID');
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
                'STOCK_HISTORY_RESPONSE_TOO_LARGE',
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
        String source;
        try {
          source = utf8.decode(bytes, allowMalformed: false);
        } catch (_) {
          throw const StockResearchException('STOCK_HISTORY_RESPONSE_INVALID');
        }
        if (response.statusCode != 200) {
          final code = parseStockHistoryServerError(
            source,
            response.statusCode,
          );
          throw StockResearchException(code);
        }
        final page = StockHistoryPage.parse(source, request: request);
        final receivedAt = _readNow();
        if (page.provenance.observedAt.isAfter(
          receivedAt.add(const Duration(seconds: 60)),
        )) {
          throw const StockResearchException('STOCK_HISTORY_RESPONSE_INVALID');
        }
        if (failure != null || _closed || cancellation?.isCancelled == true) {
          throw const StockResearchException('STOCK_HISTORY_CANCELLED');
        }
        return page;
      } on StockResearchException {
        rethrow;
      } catch (_) {
        throw failure ??
            const StockResearchException('STOCK_HISTORY_NETWORK_ERROR');
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

  DateTime _readNow() {
    try {
      final value = _now().toUtc();
      if (value.year < 1 || value.year > 9999) {
        throw const StockResearchException(
          'STOCK_HISTORY_INVALID_CONFIGURATION',
        );
      }
      return value;
    } on StockResearchException {
      rethrow;
    } catch (_) {
      throw const StockResearchException('STOCK_HISTORY_INVALID_CONFIGURATION');
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
