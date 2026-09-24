import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/stock_research.dart';

final class _QuietResearchClient implements StockResearchClient {
  var calls = 0;

  Never _unexpected() {
    calls++;
    throw StateError('A lifecycle host must not start market reads.');
  }

  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) async => _unexpected();

  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) async => _unexpected();

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) async => _unexpected();
}

final class _QuietHistoryClient implements StockHistoryClient {
  var calls = 0;

  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) async {
    calls++;
    throw StateError('A lifecycle host must not start history reads.');
  }
}

final class _QuietRaydiumClient implements RaydiumQuoteClient {
  var calls = 0;

  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) async {
    calls++;
    throw StateError('A lifecycle host must not start quote reads.');
  }
}

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  testWidgets(
    'scope exposes the injected runtime and lifecycle never starts a read',
    (tester) async {
      _resume(tester);
      final research = _QuietResearchClient();
      final history = _QuietHistoryClient();
      final raydium = _QuietRaydiumClient();
      final controller = StockResearchController.withClients(
        researchClient: research,
        historyClient: history,
        raydiumClient: raydium,
        clock: () => DateTime.parse('2026-09-14T18:00:02Z'),
      );
      addTearDown(controller.dispose);
      StockResearchScope? captured;

      await tester.pumpWidget(
        StockResearchHost(
          controller: controller,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                captured = StockResearchScope.of(context);
                return const Text('office remains unchanged');
              },
            ),
          ),
        ),
      );

      expect(captured!.controller, same(controller));
      expect(captured!.configurationFailed, isFalse);
      expect(controller.isForeground, isTrue);
      expect(find.text('office remains unchanged'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(controller.isForeground, isFalse);
      expect(controller.state.phase, StockResearchRuntimePhase.background);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.isForeground, isTrue);
      expect(controller.state.phase, StockResearchRuntimePhase.active);
      expect(research.calls, 0);
      expect(history.calls, 0);
      expect(raydium.calls, 0);

      await tester.pumpWidget(const SizedBox());
      expect(
        controller.state.phase,
        StockResearchRuntimePhase.active,
        reason: 'The caller retains ownership of an injected controller.',
      );
    },
  );

  testWidgets('an unconfigured host owns a disabled, request-free runtime', (
    tester,
  ) async {
    _resume(tester);
    StockResearchController? controller;
    await tester.pumpWidget(
      StockResearchHost(
        config: StockResearchConfig.parse(apiUrl: ''),
        child: Builder(
          builder: (context) {
            final scope = StockResearchScope.of(context);
            controller = scope.controller;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(controller, isNotNull);
    expect(controller!.enabled, isFalse);
    expect(controller!.state.phase, StockResearchRuntimePhase.disabled);

    await tester.pumpWidget(const SizedBox());
    expect(controller!.state.phase, StockResearchRuntimePhase.closed);
  });
}
