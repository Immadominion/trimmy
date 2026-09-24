import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/config.dart';
import 'package:trimmy/markets/stock_research.dart';

void main() {
  test(
    'stock configuration is optional and independent from account configuration',
    () {
      expect(StockResearchConfig.parse(apiUrl: '').enabled, isFalse);
      expect(StockResearchConfig.parse(apiUrl: '').apiUri, isNull);
      final stock = StockResearchConfig.parse(
        apiUrl: 'https://stocks.example/',
      );
      expect(stock.enabled, isTrue);
      expect(stock.apiUri.toString(), 'https://stocks.example');
      final account = PracticeAccountConfig.parse(
        appId: '',
        appClientId: '',
        apiUrl: '',
        nativeSupported: true,
      );
      expect(account.enabled, isFalse);
      expect(
        StockResearchConfig.parse(
          apiUrl: 'https://stocks.example:8443',
        ).apiUri!.port,
        8443,
      );
    },
  );
  test(
    'configuration rejects credentials, paths, queries, whitespace and unsafe origins',
    () {
      for (final value in [
        ' ',
        ' https://stocks.example',
        'https://stocks.example\n',
        'http://stocks.example',
        'https://user:secret@stocks.example',
        'https://stocks.example/research',
        'https://stocks.example?token=x',
        'https://stocks.example#fragment',
        'file:///stocks',
        'https://stocks.example:0',
        'https://stocks.example:65536',
        'HTTPS://STOCKS.EXAMPLE',
      ]) {
        expect(
          () => StockResearchConfig.parse(apiUrl: value),
          throwsA(
            isA<StockResearchException>().having(
              (e) => e.code,
              'code',
              'STOCK_INVALID_CONFIGURATION',
            ),
          ),
          reason: value,
        );
      }
    },
  );
  test('HTTP is restricted to explicitly allowed loopback tests', () {
    for (final url in [
      'http://127.0.0.1:8080',
      'http://localhost:8080',
      'http://[::1]:8080',
    ]) {
      expect(
        () => StockResearchConfig.parse(apiUrl: url),
        throwsA(isA<StockResearchException>()),
      );
      expect(
        StockResearchConfig.parse(
          apiUrl: url,
          allowLoopbackForTests: true,
        ).enabled,
        isTrue,
      );
    }
    expect(
      () => StockResearchConfig.parse(
        apiUrl: 'http://127.0.0.1.example:8080',
        allowLoopbackForTests: true,
      ),
      throwsA(isA<StockResearchException>()),
    );
    expect(
      () => StockResearchConfig.parse(
        apiUrl: 'http://192.168.1.2:8080',
        allowLoopbackForTests: true,
      ),
      throwsA(isA<StockResearchException>()),
    );
  });
}
