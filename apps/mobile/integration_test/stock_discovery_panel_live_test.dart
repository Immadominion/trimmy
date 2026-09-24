import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'package:trimmy/markets/stock_research_panel.dart';

// Run through tool/testing/mobile-stock-panel-live.mjs. That runner copies this
// project and changes its Android package before Flutter may install anything.
// This mounts the real public runtime and panel, not the office or account flow.
const _isolatedPackage = 'com.trimmy.trimmy.stockcheck';
const _resultPrefix = 'TRIMMY_STOCK_DISCOVERY_PANEL_RESULT ';

Future<void> _waitForRead(
  WidgetTester tester,
  StockResearchReadPhase Function() phase,
  String channel,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (phase() == StockResearchReadPhase.idle ||
      phase() == StockResearchReadPhase.loading) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The live $channel panel read did not finish within 20 seconds.');
    }
    await tester.pump(const Duration(milliseconds: 150));
  }
  expect(
    phase(),
    StockResearchReadPhase.ready,
    reason: 'The live $channel reading must be fresh and accepted.',
  );
  await tester.pump(const Duration(milliseconds: 150));
}

void _expectOtherReadersIdle(StockResearchController controller) {
  expect(controller.jupiterEstimateState.phase, StockResearchReadPhase.idle);
  expect(controller.tokensHistoryState.phase, StockResearchReadPhase.idle);
  expect(controller.raydiumComparisonState.phase, StockResearchReadPhase.idle);
  expect(controller.capabilities.walletAccess, isFalse);
  expect(controller.capabilities.transactionConstruction, isFalse);
  expect(controller.capabilities.simulation, isFalse);
  expect(controller.capabilities.signing, isFalse);
  expect(controller.capabilities.broadcast, isFalse);
  expect(controller.capabilities.execution, isFalse);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'isolated Android panel displays live Apple discovery and versions',
    (tester) async {
      expect(
        const String.fromEnvironment('TRIMMY_STOCK_PANEL_ISOLATED'),
        _isolatedPackage,
        reason: 'Use the isolated-package runner, not flutter test directly.',
      );
      final config = StockResearchConfig.fromEnvironment();
      expect(config.enabled, isTrue);
      expect(config.apiUri!.scheme, 'https');

      // No controller, client, clock, transport, response, or credential is
      // injected. StockResearchHost constructs its normal HTTP runtime.
      await tester.pumpWidget(
        StockResearchHost(
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Stock panel live check')),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Builder(
                    builder: (context) {
                      final scope = StockResearchScope.of(context);
                      return StockResearchPanel(
                        controller: scope.controller,
                        configurationFailed: scope.configurationFailed,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 200));
      final controller = tester
          .widget<StockResearchPanel>(find.byType(StockResearchPanel))
          .controller;
      expect(controller.state.phase, StockResearchRuntimePhase.active);
      expect(
        controller.discoveryState.search.phase,
        StockResearchReadPhase.idle,
      );
      expect(
        controller.discoveryState.variants.phase,
        StockResearchReadPhase.idle,
      );
      _expectOtherReadersIdle(controller);
      expect(
        find.byKey(const ValueKey('stock-research-unavailable')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey('stock-research-query')),
        'Apple',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 200));
      final searchButton = find.byKey(const ValueKey('stock-research-search'));
      await tester.ensureVisible(searchButton);
      await tester.tap(searchButton);
      await _waitForRead(
        tester,
        () => controller.discoveryState.search.phase,
        'Apple search',
      );
      final search = controller.discoveryState.search.data!;
      expect(search.query, 'Apple');
      expect(search.provenance.provider, 'tokens-xyz-v1');
      expect(search.provenance.executionEnabled, isFalse);
      expect(search.results.any((asset) => asset.assetId == 'apple'), isTrue);
      expect(find.byKey(const ValueKey('stock-asset-apple')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('stock-research-failure')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('stock-research-refused')),
        findsNothing,
      );
      expect(
        controller.discoveryState.variants.phase,
        StockResearchReadPhase.idle,
        reason: 'Search must not start the separate versions read.',
      );

      // Exactly one explicit follow-up. Respect the API discovery pacing;
      // neither a failed request nor a stale response is automatically retried.
      await tester.pump(const Duration(milliseconds: 1200));
      final versionsButton = find.byKey(const ValueKey('stock-variants-apple'));
      await tester.ensureVisible(versionsButton);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(versionsButton);
      await _waitForRead(
        tester,
        () => controller.discoveryState.variants.phase,
        'Apple versions',
      );
      final variants = controller.discoveryState.variants.data!;
      expect(variants.assetId, 'apple');
      expect(variants.variants, isNotEmpty);
      expect(variants.provenance.provider, 'tokens-xyz-v1');
      expect(variants.provenance.executionEnabled, isFalse);
      expect(
        find.byKey(const ValueKey('stock-variants-failure-apple')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('stock-research-refused')),
        findsNothing,
      );
      for (final variant in variants.variants) {
        final row = find.byKey(ValueKey('stock-variant-${variant.variantId}'));
        expect(row, findsOneWidget);
        expect(
          tester.widget<Text>(row).data,
          variant.label ?? variant.name ?? variant.symbol ?? variant.variantId,
        );
      }
      await tester.ensureVisible(
        find.byKey(
          ValueKey('stock-variant-${variants.variants.first.variantId}'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.textContaining('not a price you could trade at'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      _expectOtherReadersIdle(controller);
      expect(tester.takeException(), isNull);

      final result = <String, Object?>{
        'schemaVersion': 1,
        'passed': true,
        'observedAt': DateTime.now().toUtc().toIso8601String(),
        'scope':
            'Isolated Android StockResearchHost and StockResearchPanel; '
            'public discovery only, not normal app navigation or account auth.',
        'package': _isolatedPackage,
        'apiOrigin': config.apiUri.toString(),
        'explicitReads': ['search:Apple', 'variants:apple'],
        'searchResultCount': search.results.length,
        'renderedAppleVariantCount': variants.variants.length,
        'provider': variants.provenance.provider,
        'searchObservedAt': search.provenance.observedAt,
        'variantsObservedAt': variants.provenance.observedAt,
        'providerFreshness': variants.provenance.providerFreshness,
        'eligibility': variants.provenance.eligibility,
        'mintVerification': variants.provenance.mintVerification,
        'otherReadersIdle': true,
        'executionEnabled': false,
        'credentialsProvided': false,
        'ordersAttempted': false,
      };
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.state.phase, StockResearchRuntimePhase.closed);
      binding.reportData = result;
      // The runner requires this marker and Flutter's successful exit together.
      // ignore: avoid_print
      print('$_resultPrefix${jsonEncode(result)}');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
