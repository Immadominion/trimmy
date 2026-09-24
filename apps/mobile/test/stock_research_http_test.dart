import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'support/stock_research_fixtures.dart';

Matcher code(String code) =>
    isA<StockResearchException>().having((error) => error.code, 'code', code);
http.Response response(Object? value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
http.Response serverError(String errorCode, int status) => http.Response(
  jsonEncode({
    'error': {
      'code': errorCode,
      'message': 'private upstream details',
      'requestId': 'aaaaaaaa-1234-5678-aaaa-123456789abc',
    },
  }),
  status,
  headers: {'content-type': 'application/json'},
);
HttpStockResearchClient client(
  http.Client httpClient, {
  Duration timeout = const Duration(seconds: 10),
}) => HttpStockResearchClient(
  client: httpClient,
  baseUri: Uri.parse('https://research.example'),
  timeout: timeout,
);
const buy = StockEstimateRequest(
  assetId: 'apple',
  variantMint: researchAaplxMint,
  side: StockEstimateSide.buy,
  amountRaw: '10000000',
);

class _CountingCancellation extends StockResearchCancellation {
  int attached = 0;
  int peak = 0;

  @override
  void Function() addCancellationListener(void Function() listener) {
    attached++;
    if (attached > peak) peak = attached;
    final detach = super.addCancellationListener(listener);
    var active = true;
    return () {
      if (!active) return;
      active = false;
      attached--;
      detach();
    };
  }
}

class _ThrowingRegistrationCancellation extends StockResearchCancellation {
  @override
  void Function() addCancellationListener(void Function() listener) =>
      throw StateError('private registration failure');
}

void main() {
  test(
    'cancellation isolates listener failures and still drains observers',
    () {
      final cancellation = StockResearchCancellation();
      var secondCalled = false;
      cancellation.addCancellationListener(
        () => throw StateError('private listener failure'),
      );
      cancellation.addCancellationListener(() => secondCalled = true);

      expect(cancellation.cancel, returnsNormally);
      expect(cancellation.isCancelled, isTrue);
      expect(secondCalled, isTrue);
      expect(
        () => cancellation.addCancellationListener(
          () => throw StateError('late private listener failure'),
        ),
        returnsNormally,
      );
    },
  );

  test('a malformed cancellation adapter fails before dispatch', () async {
    var calls = 0;
    final transport = client(
      MockClient((_) async {
        calls++;
        return response(stockSearchFixture());
      }),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.search(
        'Apple',
        cancellation: _ThrowingRegistrationCancellation(),
      ),
      throwsA(code('STOCK_CANCELLED')),
    );
    expect(calls, 0);
  });

  test(
    'public GETs bind exact requests without tokens or wallet parameters',
    () async {
      final requests = <http.Request>[];
      final transport = client(
        MockClient((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(request.followRedirects, isFalse);
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.body, isEmpty);
          return response(switch (request.url.path) {
            '/v1/markets/stocks/search' => stockSearchFixture(
              query: 'Apple & Co',
              limit: 2,
            ),
            '/v1/markets/stocks/variants' => stockVariantsFixture(),
            _ => stockEstimateFixture(),
          });
        }),
      );
      await transport.search('Apple & Co', limit: 2);
      await transport.variants('apple');
      final estimate = await transport.estimate(buy);
      expect(requests.first.url.queryParameters, {
        'query': 'Apple & Co',
        'limit': '2',
      });
      expect(requests[1].url.queryParameters, {'assetId': 'apple'});
      expect(requests.last.url.queryParameters, buy.queryParameters);
      expect(estimate.output.estimatedAmountRaw, '18446744073709551615');
    },
  );

  test(
    'mismatched query, asset, amount or side response is rejected',
    () async {
      await expectLater(
        client(
          MockClient((_) async => response(stockSearchFixture(query: 'Tesla'))),
        ).search('Apple'),
        throwsA(code('STOCK_RESPONSE_INVALID')),
      );
      await expectLater(
        client(
          MockClient(
            (_) async => response(stockVariantsFixture(assetId: 'tesla')),
          ),
        ).variants('apple'),
        throwsA(code('STOCK_RESPONSE_INVALID')),
      );
      for (final data in [
        stockEstimateFixture(raw: '10000001'),
        stockEstimateFixture(side: StockEstimateSide.sell),
      ]) {
        await expectLater(
          client(MockClient((_) async => response(data))).estimate(buy),
          throwsA(code('STOCK_RESPONSE_INVALID')),
        );
      }
    },
  );

  test('invalid input and unsafe base URI fail before requests', () async {
    var calls = 0;
    final httpClient = MockClient((_) async {
      calls++;
      return response({});
    });
    final transport = client(httpClient);
    await expectLater(
      transport.search('Apple\n'),
      throwsA(code('STOCK_INPUT_INVALID')),
    );
    await expectLater(
      transport.variants('../apple'),
      throwsA(code('STOCK_INPUT_INVALID')),
    );
    await expectLater(
      transport.estimate(
        const StockEstimateRequest(
          assetId: 'apple',
          variantMint: researchAaplxMint,
          side: StockEstimateSide.buy,
          amountRaw: '100000001',
        ),
      ),
      throwsA(code('MARKET_INPUT_INVALID')),
    );
    expect(calls, 0);
    for (final uri in [
      'http://research.example',
      'https://user:secret@research.example',
      'https://research.example/path',
      'https://research.example?key=x',
    ]) {
      expect(
        () => HttpStockResearchClient(
          client: httpClient,
          baseUri: Uri.parse(uri),
        ),
        throwsA(code('STOCK_INVALID_CONFIGURATION')),
      );
    }
  });

  test(
    'bounded JSON, redirects, malformed UTF8 and wrong content types fail closed',
    () async {
      for (final pair in [
        (
          http.Response(
            '',
            302,
            headers: {'location': 'https://other.example'},
          ),
          'STOCK_REDIRECT_REJECTED',
        ),
        (
          http.Response(
            ' ' * (HttpStockResearchClient.maxResponseBytes + 1),
            200,
            headers: {'content-type': 'application/json'},
          ),
          'STOCK_RESPONSE_TOO_LARGE',
        ),
        (
          http.Response(
            '{}',
            200,
            headers: {
              'content-type': 'application/json',
              'content-length': '+2',
            },
          ),
          'STOCK_RESPONSE_INVALID',
        ),
        (
          http.Response(
            '{}',
            200,
            headers: {
              'content-type': 'application/json',
              'content-length': '999999999999999999999999999999999999',
            },
          ),
          'STOCK_RESPONSE_TOO_LARGE',
        ),
        (
          http.Response('{}', 200, headers: {'content-type': 'text/html'}),
          'STOCK_RESPONSE_INVALID',
        ),
        (
          http.Response.bytes(
            [0xff],
            200,
            headers: {'content-type': 'application/json'},
          ),
          'STOCK_RESPONSE_INVALID',
        ),
        (
          http.Response(
            '{',
            200,
            headers: {'content-type': 'application/json'},
          ),
          'STOCK_RESPONSE_INVALID',
        ),
      ]) {
        await expectLater(
          client(MockClient((_) async => pair.$1)).search('Apple'),
          throwsA(code(pair.$2)),
        );
      }
    },
  );

  test('a 200 response cannot claim a different final GET request', () async {
    final expected = Uri.parse(
      'https://research.example/v1/markets/stocks/search?query=Apple&limit=10',
    );
    for (final finalRequest in [
      http.Request('POST', expected),
      http.Request(
        'GET',
        Uri.parse(
          'https://other.example/v1/markets/stocks/search?query=Apple&limit=10',
        ),
      ),
      http.Request(
        'GET',
        Uri.parse(
          'https://research.example/v1/markets/stocks/search?query=Tesla&limit=10',
        ),
      ),
    ]) {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final transport = client(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'application/json'},
            request: finalRequest,
          ),
        ),
      );

      await expectLater(
        transport.search('Apple'),
        throwsA(code('STOCK_REDIRECT_REJECTED')),
      );
      expect(cancelled, isTrue);
      transport.close();
      await body.close();
    }
  });

  test(
    'fixed server codes survive but private provider diagnostics do not',
    () async {
      final transport = client(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'STOCK_RATE_LIMITED',
                'message': 'private upstream details',
                'requestId': 'id',
              },
            }),
            429,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        transport.search('Apple'),
        throwsA(code('STOCK_RATE_LIMITED')),
      );
      final unknown = client(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 'secret', 'message': 'private'},
            }),
            500,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        unknown.search('Apple'),
        throwsA(code('STOCK_SERVICE_UNAVAILABLE')),
      );
      await expectLater(
        client(
          MockClient((_) async => throw http.ClientException('secret URL')),
        ).search('Apple'),
        throwsA(code('STOCK_NETWORK_ERROR')),
      );
    },
  );

  test('server codes require their exact endpoint and HTTP status', () async {
    const discovery = <int, Set<String>>{
      400: {'STOCK_INPUT_INVALID'},
      429: {'STOCK_RATE_LIMITED'},
      502: {'STOCK_PROVIDER_UNAVAILABLE', 'STOCK_RESPONSE_INVALID'},
      503: {'STOCK_DISCOVERY_UNAVAILABLE', 'STOCK_PROVIDER_AUTH_FAILED'},
      504: {'STOCK_TIMEOUT'},
    };
    const estimate = <int, Set<String>>{
      400: {'MARKET_INPUT_INVALID'},
      429: {'MARKET_RATE_LIMITED'},
      502: {'MARKET_PROVIDER_UNAVAILABLE', 'MARKET_RESPONSE_INVALID'},
      503: {'MARKET_UNAVAILABLE', 'MARKET_PROVIDER_AUTH_FAILED'},
      504: {'MARKET_TIMEOUT', 'MARKET_ESTIMATE_STALE'},
    };
    for (final entry in discovery.entries) {
      for (final errorCode in entry.value) {
        await expectLater(
          client(
            MockClient((_) async => serverError(errorCode, entry.key)),
          ).search('Apple'),
          throwsA(code(errorCode)),
        );
      }
    }
    for (final entry in estimate.entries) {
      for (final errorCode in entry.value) {
        await expectLater(
          client(
            MockClient((_) async => serverError(errorCode, entry.key)),
          ).estimate(buy),
          throwsA(code(errorCode)),
        );
      }
    }
    for (final mismatch in [
      (502, 'STOCK_TIMEOUT', false),
      (504, 'MARKET_TIMEOUT', false),
      (502, 'MARKET_TIMEOUT', true),
      (504, 'STOCK_TIMEOUT', true),
    ]) {
      final transport = client(
        MockClient((_) async => serverError(mismatch.$2, mismatch.$1)),
      );
      final request = mismatch.$3
          ? transport.estimate(buy)
          : transport.search('Apple');
      await expectLater(request, throwsA(code('STOCK_SERVICE_UNAVAILABLE')));
    }
  });

  test(
    'timeout is bounded even if send ignores abort and a late response is discarded',
    () async {
      final send = Completer<http.StreamedResponse>();
      final transport = client(
        MockClient.streaming((_, _) => send.future),
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        transport.search('Apple'),
        throwsA(code('STOCK_TIMEOUT')),
      );
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      send.complete(
        http.StreamedResponse(
          stream.stream,
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      await stream.close();
    },
  );

  test(
    'cancellation before dispatch, during body read and close stop research without retries',
    () async {
      var calls = 0;
      var bodyCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          bodyCancelled = true;
        },
      );
      final started = Completer<void>();
      final transport = client(
        MockClient.streaming((_, _) async {
          calls++;
          started.complete();
          return http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final already = StockResearchCancellation()..cancel();
      await expectLater(
        transport.search('Apple', cancellation: already),
        throwsA(code('STOCK_CANCELLED')),
      );
      expect(calls, 0);
      final cancel = StockResearchCancellation();
      final pending = transport.search('Apple', cancellation: cancel);
      final assertion = expectLater(pending, throwsA(code('STOCK_CANCELLED')));
      await started.future;
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      await assertion;
      expect(bodyCancelled, isTrue);
      expect(calls, 1);
      transport.close();
      await expectLater(
        transport.variants('apple'),
        throwsA(code('STOCK_CANCELLED')),
      );
      await body.close();
    },
  );

  test(
    'a reusable cancellation token detaches every settled request',
    () async {
      var calls = 0;
      final cancellation = _CountingCancellation();
      final transport = client(
        MockClient((_) async {
          calls++;
          expect(cancellation.attached, 1);
          return response(stockSearchFixture());
        }),
      );
      for (var index = 0; index < 25; index++) {
        expect(
          await transport.search('Apple', cancellation: cancellation),
          isA<StockSearchPage>(),
        );
        expect(cancellation.attached, 0);
      }
      expect(cancellation.peak, 1);
      cancellation.cancel();
      expect(calls, 25);
    },
  );

  test(
    'timeout cancels a stalled response body independently of HTTP abort support',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final transport = client(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        transport.search('Apple'),
        throwsA(code('STOCK_TIMEOUT')),
      );
      expect(cancelled, isTrue);
      await body.close();
    },
  );
}
