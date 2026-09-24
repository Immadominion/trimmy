import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/markets/raydium_quotes.dart';

import 'support/raydium_quote_fixtures.dart';

Matcher quoteHttpFailure(String value) =>
    isA<StockResearchException>().having((error) => error.code, 'code', value);

http.Response quoteResponse({
  String? body,
  int statusCode = 200,
  Map<String, String>? headers,
}) => http.Response(
  body ?? raydiumQuoteJson(),
  statusCode,
  headers: headers ?? {'content-type': 'application/json; charset=utf-8'},
);

http.Response quoteServerError(String code, int statusCode) => http.Response(
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

HttpRaydiumQuoteClient quoteClient(
  http.Client client, {
  Duration timeout = const Duration(seconds: 10),
  Uri? baseUri,
  bool allowLoopbackForTests = false,
}) => HttpRaydiumQuoteClient(
  client: client,
  baseUri: baseUri ?? Uri.parse('https://api.trimmy.example'),
  timeout: timeout,
  allowLoopbackForTests: allowLoopbackForTests,
);

void main() {
  test(
    'one same-origin GET carries only the exact pinned quote request',
    () async {
      var calls = 0;
      late http.Request captured;
      final client = quoteClient(
        MockClient((request) async {
          calls++;
          captured = request;
          return quoteResponse();
        }),
      );
      addTearDown(client.close);

      final quote = await client.quote(raydiumBuyRequest);
      expect(calls, 1);
      expect(captured.method, 'GET');
      expect(captured.followRedirects, isFalse);
      expect(captured.maxRedirects, 0);
      expect(captured.url.origin, 'https://api.trimmy.example');
      expect(captured.url.path, raydiumStockQuoteRoute);
      expect(captured.url.queryParameters, raydiumBuyRequest.queryParameters);
      expect(captured.headers['accept'], 'application/json');
      expect(captured.headers.containsKey('authorization'), isFalse);
      expect(captured.headers.containsKey('x-api-key'), isFalse);
      expect(captured.body, isEmpty);
      expect(quote.request, raydiumBuyRequest);
      expect(quote.output.estimatedAmountRaw, '2978849');
    },
  );

  test('invalid requests and unsafe API roots fail before transport', () async {
    var calls = 0;
    final mock = MockClient((_) async {
      calls++;
      return quoteResponse();
    });
    final client = quoteClient(mock);
    addTearDown(client.close);
    await expectLater(
      client.quote(
        const RaydiumQuoteRequest.appleAaplx(
          side: RaydiumQuoteSide.buy,
          amountRaw: '01',
        ),
      ),
      throwsA(quoteHttpFailure('MARKET_INPUT_INVALID')),
    );
    expect(calls, 0);

    for (final value in [
      'http://api.trimmy.example',
      'https://user:secret@api.trimmy.example',
      'https://api.trimmy.example/path',
      'https://api.trimmy.example?token=secret',
      'https://api.trimmy.example/#fragment',
    ]) {
      expect(
        () => quoteClient(mock, baseUri: Uri.parse(value)),
        throwsA(quoteHttpFailure('RAYDIUM_QUOTE_INVALID_CONFIGURATION')),
      );
    }
    expect(
      () => quoteClient(mock, baseUri: Uri.parse('http://127.0.0.1:8787')),
      throwsA(quoteHttpFailure('RAYDIUM_QUOTE_INVALID_CONFIGURATION')),
    );
    final loopback = quoteClient(
      mock,
      baseUri: Uri.parse('http://127.0.0.1:8787'),
      allowLoopbackForTests: true,
    );
    expect(loopback, isA<HttpRaydiumQuoteClient>());
    loopback.close();
  });

  test('the route-specific status and error-code matrix is exact', () async {
    const matrix = <int, Set<String>>{
      400: {'MARKET_INPUT_INVALID'},
      429: {'MARKET_RATE_LIMITED'},
      502: {
        'MARKET_PROVIDER_AUTH_FAILED',
        'MARKET_PROVIDER_UNAVAILABLE',
        'MARKET_RESPONSE_INVALID',
      },
      503: {'MARKET_UNAVAILABLE'},
      504: {'MARKET_TIMEOUT', 'MARKET_ESTIMATE_STALE'},
    };
    for (final entry in matrix.entries) {
      for (final code in entry.value) {
        final client = quoteClient(
          MockClient((_) async => quoteServerError(code, entry.key)),
        );
        await expectLater(
          client.quote(raydiumBuyRequest),
          throwsA(quoteHttpFailure(code)),
        );
        client.close();
      }
    }
    for (final mismatch in [
      (503, 'MARKET_PROVIDER_AUTH_FAILED'),
      (502, 'MARKET_TIMEOUT'),
      (504, 'MARKET_PROVIDER_UNAVAILABLE'),
      (500, 'MARKET_PROVIDER_UNAVAILABLE'),
    ]) {
      final client = quoteClient(
        MockClient((_) async => quoteServerError(mismatch.$2, mismatch.$1)),
      );
      await expectLater(
        client.quote(raydiumBuyRequest),
        throwsA(quoteHttpFailure('RAYDIUM_QUOTE_SERVICE_UNAVAILABLE')),
      );
      client.close();
    }

    final extraErrorField = quoteServerError('MARKET_UNAVAILABLE', 503);
    final decoded = jsonDecode(extraErrorField.body) as Map<String, Object?>;
    (decoded['error']! as Map<String, Object?>)['providerDetail'] = 'private';
    final client = quoteClient(
      MockClient(
        (_) async => quoteResponse(body: jsonEncode(decoded), statusCode: 503),
      ),
    );
    await expectLater(
      client.quote(raydiumBuyRequest),
      throwsA(quoteHttpFailure('RAYDIUM_QUOTE_SERVICE_UNAVAILABLE')),
    );
    client.close();
  });

  test('redirect, media type, UTF-8, JSON, and schema fail closed', () async {
    final cases = <(http.Response, String)>[
      (
        http.Response(
          '',
          302,
          headers: {'location': 'https://other.example/quote'},
        ),
        'RAYDIUM_QUOTE_REDIRECT_REJECTED',
      ),
      (
        quoteResponse(headers: {'content-type': 'text/html'}),
        'RAYDIUM_QUOTE_RESPONSE_INVALID',
      ),
      (
        quoteResponse(
          headers: {'content-type': 'application/json; charset=iso-8859-1'},
        ),
        'RAYDIUM_QUOTE_RESPONSE_INVALID',
      ),
      (
        http.Response.bytes(
          [0xff],
          200,
          headers: {'content-type': 'application/json'},
        ),
        'RAYDIUM_QUOTE_RESPONSE_INVALID',
      ),
      (
        quoteResponse(
          headers: {'content-type': 'application/json', 'content-length': '01'},
        ),
        'RAYDIUM_QUOTE_RESPONSE_INVALID',
      ),
      (quoteResponse(body: '{'), 'RAYDIUM_QUOTE_RESPONSE_INVALID'),
      (quoteResponse(body: '{}'), 'RAYDIUM_QUOTE_RESPONSE_INVALID'),
    ];
    for (final value in cases) {
      final client = quoteClient(MockClient((_) async => value.$1));
      await expectLater(
        client.quote(raydiumBuyRequest),
        throwsA(quoteHttpFailure(value.$2)),
      );
      client.close();
    }
  });

  test('a 200 response cannot claim a different final request', () async {
    for (final finalRequest in [
      http.Request(
        'GET',
        Uri.parse('https://other.example/v1/markets/stocks/quotes/raydium'),
      ),
      http.Request(
        'POST',
        Uri.https(
          'api.trimmy.example',
          raydiumStockQuoteRoute,
          raydiumBuyRequest.queryParameters,
        ),
      ),
    ]) {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = quoteClient(
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
        client.quote(raydiumBuyRequest),
        throwsA(quoteHttpFailure('RAYDIUM_QUOTE_REDIRECT_REJECTED')),
      );
      expect(cancelled, isTrue);
      client.close();
      await body.close();
    }
  });

  test(
    'declared and streamed response budgets cancel oversized bodies',
    () async {
      var declaredCancelled = false;
      final declaredBody = StreamController<List<int>>(
        onCancel: () => declaredCancelled = true,
      );
      final declaredClient = quoteClient(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            declaredBody.stream,
            200,
            contentLength: HttpRaydiumQuoteClient.maxResponseBytes + 1,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        declaredClient.quote(raydiumBuyRequest),
        throwsA(quoteHttpFailure('RAYDIUM_QUOTE_RESPONSE_TOO_LARGE')),
      );
      expect(declaredCancelled, isTrue);
      declaredClient.close();
      await declaredBody.close();

      var streamedCancelled = false;
      late final StreamController<List<int>> streamedBody;
      streamedBody = StreamController<List<int>>(
        onListen: () {
          streamedBody.add(
            List.filled(HttpRaydiumQuoteClient.maxResponseBytes, 32),
          );
          streamedBody.add([32]);
        },
        onCancel: () => streamedCancelled = true,
      );
      final streamedClient = quoteClient(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            streamedBody.stream,
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        streamedClient.quote(raydiumBuyRequest),
        throwsA(quoteHttpFailure('RAYDIUM_QUOTE_RESPONSE_TOO_LARGE')),
      );
      expect(streamedCancelled, isTrue);
      streamedClient.close();
      await streamedBody.close();
    },
  );

  test('network failure is sanitized and the client never retries', () async {
    var calls = 0;
    final client = quoteClient(
      MockClient((_) async {
        calls++;
        throw http.ClientException('private host and query');
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.quote(raydiumBuyRequest),
      throwsA(quoteHttpFailure('RAYDIUM_QUOTE_NETWORK_ERROR')),
    );
    expect(calls, 1);
  });

  test('deadline cancels a late body and reports one fixed timeout', () async {
    final send = Completer<http.StreamedResponse>();
    final client = quoteClient(
      MockClient.streaming((_, _) => send.future),
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(client.close);
    await expectLater(
      client.quote(raydiumBuyRequest),
      throwsA(quoteHttpFailure('MARKET_TIMEOUT')),
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
  });

  test('caller cancellation, cleanup, and close are terminally safe', () async {
    final settledToken = RaydiumQuoteCancellation();
    var validResponse = true;
    final settledClient = quoteClient(
      MockClient(
        (_) async =>
            validResponse ? quoteResponse() : quoteResponse(body: '{}'),
      ),
    );
    await settledClient.quote(raydiumBuyRequest, cancellation: settledToken);
    expect(settledToken.debugListenerCount, 0);
    validResponse = false;
    await expectLater(
      settledClient.quote(raydiumBuyRequest, cancellation: settledToken),
      throwsA(quoteHttpFailure('RAYDIUM_QUOTE_RESPONSE_INVALID')),
    );
    expect(settledToken.debugListenerCount, 0);
    settledClient.close();

    var calls = 0;
    var bodyCancelled = false;
    final started = Completer<void>();
    final body = StreamController<List<int>>(
      onCancel: () => bodyCancelled = true,
    );
    final client = quoteClient(
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
    final already = RaydiumQuoteCancellation()..cancel();
    expect(
      () => already.addCancellationListener(
        () => throw StateError('late private listener failure'),
      ),
      returnsNormally,
    );
    await expectLater(
      client.quote(raydiumBuyRequest, cancellation: already),
      throwsA(quoteHttpFailure('RAYDIUM_QUOTE_CANCELLED')),
    );
    expect(calls, 0);

    final cancellation = RaydiumQuoteCancellation();
    final pending = client.quote(raydiumBuyRequest, cancellation: cancellation);
    final assertion = expectLater(
      pending,
      throwsA(quoteHttpFailure('RAYDIUM_QUOTE_CANCELLED')),
    );
    await started.future;
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    await assertion;
    expect(bodyCancelled, isTrue);
    expect(cancellation.debugListenerCount, 0);
    expect(calls, 1);

    client.close();
    client.close();
    await expectLater(
      client.quote(raydiumBuyRequest),
      throwsA(quoteHttpFailure('RAYDIUM_QUOTE_CANCELLED')),
    );
    expect(calls, 1);
    await body.close();
  });
}
