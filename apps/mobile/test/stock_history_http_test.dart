import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/markets/stock_history.dart';

import 'support/stock_history_fixtures.dart';

Matcher historyFailure(String value) =>
    isA<StockResearchException>().having((error) => error.code, 'code', value);

http.Response historyResponse({
  String? body,
  int statusCode = 200,
  Map<String, String>? headers,
}) => http.Response(
  body ?? stockHistoryJson(),
  statusCode,
  headers: headers ?? {'content-type': 'application/json; charset=utf-8'},
);

http.Response historyServerError(String code, int statusCode) => http.Response(
  jsonEncode({
    'error': {
      'code': code,
      'message': 'Safe public message.',
      'requestId': 'aaaaaaaa-1234-5678-aaaa-123456789abc',
    },
  }),
  statusCode,
  headers: {'content-type': 'application/json'},
);

HttpStockHistoryClient historyClient(
  http.Client client, {
  Duration timeout = const Duration(seconds: 10),
  Uri? baseUri,
  bool allowLoopbackForTests = false,
  DateTime Function()? now,
}) => HttpStockHistoryClient(
  client: client,
  baseUri: baseUri ?? Uri.parse('https://research.example'),
  timeout: timeout,
  allowLoopbackForTests: allowLoopbackForTests,
  now: now ?? () => DateTime.parse('2026-09-14T20:00:00.000Z'),
);

final class _ThrowingRegistrationCancellation
    extends StockResearchCancellation {
  @override
  void Function() addCancellationListener(void Function() listener) =>
      throw StateError('private registration failure');
}

void main() {
  test('a malformed cancellation adapter fails before dispatch', () async {
    var calls = 0;
    final client = historyClient(
      MockClient((_) async {
        calls++;
        return historyResponse();
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.history(
        stockHistoryRequest,
        cancellation: _ThrowingRegistrationCancellation(),
      ),
      throwsA(historyFailure('STOCK_HISTORY_CANCELLED')),
    );
    expect(calls, 0);
  });

  test(
    'one public GET binds only the exact Apple AAPLx history request',
    () async {
      var calls = 0;
      late http.Request captured;
      final client = historyClient(
        MockClient((request) async {
          calls++;
          captured = request;
          return historyResponse();
        }),
      );
      final page = await client.history(stockHistoryRequest);
      expect(calls, 1);
      expect(captured.method, 'GET');
      expect(captured.followRedirects, isFalse);
      expect(captured.maxRedirects, 0);
      expect(captured.url.path, stockHistoryRoute);
      expect(captured.url.queryParameters, stockHistoryRequest.queryParameters);
      expect(captured.headers['accept'], 'application/json');
      expect(captured.headers.containsKey('authorization'), isFalse);
      expect(captured.headers.containsKey('x-api-key'), isFalse);
      expect(captured.body, isEmpty);
      expect(page.candles.first.openRaw, '1.2300');
      expect(page.executionEnabled, isFalse);
    },
  );

  test('invalid requests and unsafe roots fail before an HTTP call', () async {
    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      return historyResponse();
    });
    final client = historyClient(mock);
    await expectLater(
      client.history(
        const StockHistoryRequest.appleAaplx(
          interval: StockHistoryInterval.oneHour,
          fromUnixSeconds: '01789344000',
          toUnixSeconds: stockHistoryTo,
        ),
      ),
      throwsA(historyFailure('STOCK_HISTORY_INPUT_INVALID')),
    );
    expect(calls, 0);

    for (final value in [
      'http://research.example',
      'https://user:secret@research.example',
      'https://research.example/path',
      'https://research.example?token=secret',
      'https://research.example/#fragment',
    ]) {
      expect(
        () => historyClient(mock, baseUri: Uri.parse(value)),
        throwsA(historyFailure('STOCK_HISTORY_INVALID_CONFIGURATION')),
      );
    }
    expect(
      () => historyClient(mock, baseUri: Uri.parse('http://127.0.0.1:8787')),
      throwsA(historyFailure('STOCK_HISTORY_INVALID_CONFIGURATION')),
    );
    expect(
      historyClient(
        mock,
        baseUri: Uri.parse('http://127.0.0.1:8787'),
        allowLoopbackForTests: true,
      ),
      isA<HttpStockHistoryClient>(),
    );
  });

  test('an invalid client clock fails before an HTTP call', () async {
    var calls = 0;
    final client = historyClient(
      MockClient((_) async {
        calls++;
        return historyResponse();
      }),
      now: () => DateTime.utc(10000),
    );
    addTearDown(client.close);

    await expectLater(
      client.history(stockHistoryRequest),
      throwsA(historyFailure('STOCK_HISTORY_INVALID_CONFIGURATION')),
    );
    expect(calls, 0);
  });

  test('the route status and stable error code matrix is enforced', () async {
    const matrix = <int, Set<String>>{
      400: {'STOCK_HISTORY_INPUT_INVALID'},
      429: {'STOCK_HISTORY_RATE_LIMITED'},
      502: {
        'STOCK_HISTORY_PROVIDER_UNAVAILABLE',
        'STOCK_HISTORY_RESPONSE_INVALID',
      },
      503: {'STOCK_HISTORY_UNAVAILABLE', 'STOCK_HISTORY_PROVIDER_AUTH_FAILED'},
      504: {'STOCK_HISTORY_TIMEOUT'},
    };
    for (final entry in matrix.entries) {
      for (final code in entry.value) {
        await expectLater(
          historyClient(
            MockClient((_) async => historyServerError(code, entry.key)),
          ).history(stockHistoryRequest),
          throwsA(historyFailure(code)),
        );
      }
    }
    for (final mismatch in [
      (502, 'STOCK_HISTORY_TIMEOUT'),
      (504, 'STOCK_HISTORY_PROVIDER_UNAVAILABLE'),
      (500, 'STOCK_HISTORY_PROVIDER_UNAVAILABLE'),
    ]) {
      await expectLater(
        historyClient(
          MockClient((_) async => historyServerError(mismatch.$2, mismatch.$1)),
        ).history(stockHistoryRequest),
        throwsA(historyFailure('STOCK_HISTORY_SERVICE_UNAVAILABLE')),
      );
    }
  });

  test(
    'redirects, content type, UTF8, JSON, and shape all fail closed',
    () async {
      final cases = <(http.Response, String)>[
        (
          http.Response(
            '',
            302,
            headers: {'location': 'https://other.example'},
          ),
          'STOCK_HISTORY_REDIRECT_REJECTED',
        ),
        (
          historyResponse(headers: {'content-type': 'text/html'}),
          'STOCK_HISTORY_RESPONSE_INVALID',
        ),
        (
          historyResponse(
            headers: {'content-type': 'application/json; charset=iso-8859-1'},
          ),
          'STOCK_HISTORY_RESPONSE_INVALID',
        ),
        (
          http.Response.bytes(
            [0xff],
            200,
            headers: {'content-type': 'application/json'},
          ),
          'STOCK_HISTORY_RESPONSE_INVALID',
        ),
        (historyResponse(body: '{'), 'STOCK_HISTORY_RESPONSE_INVALID'),
        (historyResponse(body: '{}'), 'STOCK_HISTORY_RESPONSE_INVALID'),
      ];
      for (final value in cases) {
        await expectLater(
          historyClient(
            MockClient((_) async => value.$1),
          ).history(stockHistoryRequest),
          throwsA(historyFailure(value.$2)),
        );
      }
    },
  );

  test('a 200 response cannot claim a different final request URL', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final client = historyClient(
      MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
          request: http.Request(
            'GET',
            Uri.parse('https://other.example/v1/markets/stocks/history'),
          ),
        ),
      ),
    );
    await expectLater(
      client.history(stockHistoryRequest),
      throwsA(historyFailure('STOCK_HISTORY_REDIRECT_REJECTED')),
    );
    expect(cancelled, isTrue);
    await body.close();
  });

  test(
    'declared and streamed body budgets cancel oversized responses',
    () async {
      var declaredCancelled = false;
      final declaredBody = StreamController<List<int>>(
        onCancel: () => declaredCancelled = true,
      );
      await expectLater(
        historyClient(
          MockClient.streaming(
            (_, _) async => http.StreamedResponse(
              declaredBody.stream,
              200,
              contentLength: HttpStockHistoryClient.maxResponseBytes + 1,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ).history(stockHistoryRequest),
        throwsA(historyFailure('STOCK_HISTORY_RESPONSE_TOO_LARGE')),
      );
      expect(declaredCancelled, isTrue);
      await declaredBody.close();

      var streamedCancelled = false;
      late final StreamController<List<int>> streamedBody;
      streamedBody = StreamController<List<int>>(
        onListen: () {
          streamedBody.add(
            List.filled(HttpStockHistoryClient.maxResponseBytes, 32),
          );
          streamedBody.add([32]);
        },
        onCancel: () => streamedCancelled = true,
      );
      await expectLater(
        historyClient(
          MockClient.streaming(
            (_, _) async => http.StreamedResponse(
              streamedBody.stream,
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ).history(stockHistoryRequest),
        throwsA(historyFailure('STOCK_HISTORY_RESPONSE_TOO_LARGE')),
      );
      expect(streamedCancelled, isTrue);
      await streamedBody.close();
    },
  );

  test('network failure is sanitized and never retried', () async {
    var calls = 0;
    final client = historyClient(
      MockClient((_) async {
        calls++;
        throw http.ClientException('private host and query');
      }),
    );
    await expectLater(
      client.history(stockHistoryRequest),
      throwsA(historyFailure('STOCK_HISTORY_NETWORK_ERROR')),
    );
    expect(calls, 1);
  });

  test('a materially future provider observation is rejected', () async {
    final future = stockHistoryJson(
      requestedAt: '2026-09-14T20:01:01.000Z',
      observedAt: '2026-09-14T20:01:01.000Z',
      refreshAfter: '2026-09-14T20:01:16.000Z',
    );
    await expectLater(
      historyClient(
        MockClient((_) async => historyResponse(body: future)),
      ).history(stockHistoryRequest),
      throwsA(historyFailure('STOCK_HISTORY_RESPONSE_INVALID')),
    );
  });

  test(
    'deadline wins when send ignores abort and discards a late body',
    () async {
      final send = Completer<http.StreamedResponse>();
      final client = historyClient(
        MockClient.streaming((_, _) => send.future),
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        client.history(stockHistoryRequest),
        throwsA(historyFailure('STOCK_HISTORY_TIMEOUT')),
      );
      var lateCancelled = false;
      final lateBody = StreamController<List<int>>(
        onCancel: () => lateCancelled = true,
      );
      send.complete(
        http.StreamedResponse(
          lateBody.stream,
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(lateCancelled, isTrue);
      await lateBody.close();
    },
  );

  test(
    'caller cancellation and close abort bodies and reject later reads',
    () async {
      var calls = 0;
      var bodyCancelled = false;
      final started = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () => bodyCancelled = true,
      );
      final client = historyClient(
        MockClient.streaming((_, _) async {
          calls++;
          if (!started.isCompleted) started.complete();
          return http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final already = StockResearchCancellation()..cancel();
      await expectLater(
        client.history(stockHistoryRequest, cancellation: already),
        throwsA(historyFailure('STOCK_HISTORY_CANCELLED')),
      );
      expect(calls, 0);

      final cancellation = StockResearchCancellation();
      final pending = client.history(
        stockHistoryRequest,
        cancellation: cancellation,
      );
      final assertion = expectLater(
        pending,
        throwsA(historyFailure('STOCK_HISTORY_CANCELLED')),
      );
      await started.future;
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      await assertion;
      expect(bodyCancelled, isTrue);
      expect(calls, 1);

      client.close();
      client.close();
      await expectLater(
        client.history(stockHistoryRequest),
        throwsA(historyFailure('STOCK_HISTORY_CANCELLED')),
      );
      expect(calls, 1);
      await body.close();
    },
  );

  test('close cancels an active body and settles the read', () async {
    var cancelled = false;
    final started = Completer<void>();
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final client = historyClient(
      MockClient.streaming((_, _) async {
        started.complete();
        return http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final pending = client.history(stockHistoryRequest);
    final assertion = expectLater(
      pending,
      throwsA(historyFailure('STOCK_HISTORY_CANCELLED')),
    );
    await started.future;
    await Future<void>.delayed(Duration.zero);
    client.close();
    await assertion;
    expect(cancelled, isTrue);
    await body.close();
  });
}
