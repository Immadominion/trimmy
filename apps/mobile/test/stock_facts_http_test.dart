import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/product/market/http_stock_facts_repository.dart';
import 'package:trimmy/product/market/stock_facts.dart';

import 'stock_facts_models_test.dart' as fixtures;

HttpStockFactsRepository repository(
  Future<http.Response> Function(http.Request request) handler,
) => HttpStockFactsRepository(
  transport: MockClient(handler),
  baseUri: Uri.parse('https://api.example.test'),
  timeout: const Duration(seconds: 2),
);

http.Response json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'cards sends a bare GET with the query and limit and no credential',
    () async {
      late http.Request seen;
      final api = repository((request) async {
        seen = request;
        return json(fixtures.cardsPage());
      });
      final page = await api.cards('apple', limit: 5);
      expect(seen.method, 'GET');
      expect(seen.url.path, '/v1/markets/stocks/cards');
      expect(seen.url.queryParameters, {'query': 'apple', 'limit': '5'});
      expect(seen.headers.containsKey('authorization'), isFalse);
      expect(seen.followRedirects, isFalse);
      expect(page.results.single.assetId, 'apple');
    },
  );

  test('facts binds the requested asset id', () async {
    final api = repository((request) async {
      expect(request.url.path, '/v1/markets/stocks/facts');
      expect(request.url.queryParameters, {'assetId': 'apple'});
      return json(fixtures.facts());
    });
    expect((await api.facts('apple')).description, isNotNull);
    final other = repository((_) async => json(fixtures.facts()));
    expect(
      () => other.facts('tesla'),
      throwsA(
        isA<StockFactsException>().having(
          (error) => error.failure,
          'failure',
          StockFactsFailure.invalidResponse,
        ),
      ),
    );
  });

  test('rejects bad inputs before any request', () async {
    var calls = 0;
    final api = repository((_) async {
      calls++;
      return json(fixtures.cardsPage());
    });
    for (final query in ['', ' apple', 'a' * 81, 'ap\nple']) {
      await expectLater(
        api.cards(query),
        throwsA(
          isA<StockFactsException>().having(
            (error) => error.failure,
            'failure',
            StockFactsFailure.invalidInput,
          ),
        ),
      );
    }
    await expectLater(
      api.cards('apple', limit: 21),
      throwsA(isA<StockFactsException>()),
    );
    await expectLater(api.facts('../x'), throwsA(isA<StockFactsException>()));
    expect(calls, 0);
  });

  test(
    'maps statuses, retry-after, redirects, bad content and offline',
    () async {
      Future<StockFactsFailure> failureFor(
        Future<http.Response> Function(http.Request) handler,
      ) async {
        try {
          await repository(handler).facts('apple');
        } on StockFactsException catch (error) {
          return error.failure;
        }
        fail('expected a failure');
      }

      expect(
        await failureFor(
          (_) async => http.Response('', 429, headers: {'retry-after': '7'}),
        ),
        StockFactsFailure.rateLimited,
      );
      try {
        await repository(
          (_) async => http.Response('', 429, headers: {'retry-after': '7'}),
        ).facts('apple');
      } on StockFactsException catch (error) {
        expect(error.retryAfter, const Duration(seconds: 7));
      }
      expect(
        await failureFor((_) async => http.Response('', 504)),
        StockFactsFailure.timeout,
      );
      expect(
        await failureFor((_) async => http.Response('', 503)),
        StockFactsFailure.unavailable,
      );
      expect(
        await failureFor((_) async => http.Response('', 400)),
        StockFactsFailure.invalidInput,
      );
      expect(
        await failureFor(
          (_) async =>
              http.Response('', 302, headers: {'location': 'https://x'}),
        ),
        StockFactsFailure.unavailable,
      );
      expect(
        await failureFor(
          (_) async => http.Response(
            '<html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
        StockFactsFailure.invalidResponse,
      );
      expect(
        await failureFor(
          (_) async => http.Response(
            '{"broken',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        StockFactsFailure.invalidResponse,
      );
      expect(
        await failureFor((_) async => throw http.ClientException('down')),
        StockFactsFailure.offline,
      );
    },
  );

  test('refuses an unsafe base origin', () {
    for (final origin in [
      'http://api.example.test',
      'https://user:pw@api.example.test',
      'https://api.example.test/v1',
      'https://api.example.test?x=1',
    ]) {
      expect(
        () => HttpStockFactsRepository(
          transport: MockClient((_) async => json(fixtures.facts())),
          baseUri: Uri.parse(origin),
        ),
        throwsA(isA<StockFactsException>()),
        reason: origin,
      );
    }
  });
}
