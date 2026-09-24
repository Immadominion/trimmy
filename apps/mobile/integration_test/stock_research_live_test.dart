import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:trimmy/markets/stock_research.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android client reads live stock discovery and indicative quotes',
    (_) async {
      const rawApiUrl = String.fromEnvironment('TRIMMY_STOCK_API_URL');
      final config = StockResearchConfig.parse(
        apiUrl: rawApiUrl,
        allowLoopbackForTests: true,
      );
      expect(config.enabled, isTrue);

      final transport = http.Client();
      addTearDown(transport.close);
      final client = HttpStockResearchClient(
        client: transport,
        baseUri: config.apiUri!,
        timeout: const Duration(seconds: 15),
        allowLoopbackForTests: true,
      );
      addTearDown(client.close);

      final search = await client.search('Apple', limit: 5);
      expect(search.query, 'Apple');
      expect(search.results, isNotEmpty);
      expect(search.provenance.provider, 'tokens-xyz-v1');
      expect(search.provenance.executionEnabled, isFalse);

      // The server paces discovery reads; this is one explicit follow-up.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final variants = await client.variants('apple');
      expect(variants.assetId, 'apple');
      expect(
        variants.variants.any(
          (variant) =>
              variant.mint == 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
        ),
        isTrue,
      );

      const buy = StockEstimateRequest(
        assetId: 'apple',
        variantMint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
        side: StockEstimateSide.buy,
        amountRaw: '10000000',
      );
      final estimate = await client.estimate(buy);
      expect(estimate.request, buy);
      expect(estimate.input.symbol, 'USDC');
      expect(estimate.output.symbol, 'AAPLx');
      expect(
        BigInt.parse(estimate.output.estimatedAmountRaw),
        greaterThan(BigInt.zero),
      );
      expect(estimate.executable, isFalse);
      expect(estimate.executionEnabled, isFalse);
      expect(estimate.walletChecked, isFalse);
      expect(estimate.eligibility, 'unverified');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
