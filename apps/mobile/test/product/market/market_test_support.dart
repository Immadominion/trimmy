import 'package:flutter/foundation.dart';
import 'package:trimmy/markets/discovery.dart';
import 'package:trimmy/product/market/market.dart';

const testMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const testOrderId = '44444444-4444-4444-8444-444444444444';
const testReasonMutationId = '66666666-6666-4666-8666-666666666666';

MarketCompany testCompany({
  String assetId = 'apple',
  String name = 'Apple',
  String symbol = 'AAPL',
  double price = 231.42,
  double change = 1.4,
  Set<MarketList> lists = const {
    MarketList.starterPicks,
    MarketList.trending,
    MarketList.tech,
  },
}) {
  final asset = StockDiscoveryAsset.fromJson({
    'assetId': assetId,
    'name': name,
    'symbol': symbol,
    'category': 'equity',
    'providerPrimaryVariantMint': testMint,
    'variants': [
      {
        'variantId': '$assetId-xstocks',
        'mint': testMint,
        'chain': 'solana',
        'kind': 'tokenized-equity',
        'issuer': 'Backed',
        'label': '${symbol}x',
        'name': '$name xStock',
        'symbol': '${symbol}x',
        'providerRedemptionTier': null,
        'advisory': null,
        'market': {
          'displayOnly': true,
          'priceUsd': price,
          'liquidityUsd': 100000,
          'volume24hUsd': 50000,
          'decimals': 8,
          'source': 'tokens.xyz',
          'metricsSource': null,
          'providerTimestamps': {
            'asOf': null,
            'lastFetchedAt': null,
            'lastTradeAt': null,
            'unit': 'not_declared',
          },
        },
      },
    ],
    'advisories': [],
  });
  return MarketCompany.fromDiscovery(
    asset,
    description: '$name makes products people use every day.',
    sector: 'Tech',
    dayChangePercent: change,
    asOf: DateTime.utc(2026, 9, 20, 12, 30),
    weekTrend: const [1, 1.4, 1.2, 1.9, 2.2, 2.0, 2.6],
    floorHolders: 41,
    friendFaces: const [
      MarketFriendFace(handle: 'nia', initials: 'NI'),
      MarketFriendFace(handle: 'tobi', initials: 'TO'),
    ],
    lists: lists,
  );
}

final class FakeMarketSearchGateway extends ChangeNotifier
    implements MarketSearchGateway {
  FakeMarketSearchGateway({Map<String, List<MarketCompany>>? results})
    : results = results ?? const {};

  final Map<String, List<MarketCompany>> results;
  final List<String> queries = [];
  MarketSearchSnapshot _snapshot = const MarketSearchSnapshot.idle();

  @override
  MarketSearchSnapshot get snapshot => _snapshot;

  @override
  Future<void> search(String query) async {
    queries.add(query);
    _snapshot = MarketSearchSnapshot(
      phase: MarketSearchPhase.loading,
      query: query,
      companies: const [],
    );
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    _snapshot = MarketSearchSnapshot(
      phase: MarketSearchPhase.ready,
      query: query,
      companies: List.unmodifiable(results[query] ?? const []),
    );
    notifyListeners();
  }

  @override
  void cancel() {
    _snapshot = const MarketSearchSnapshot.idle();
    notifyListeners();
  }
}

final class FakePaperOrderRepository implements PaperOrderRepository {
  Future<PaperOrderQuote> Function(PaperOrderIntent intent)? onQuote;
  Future<PaperOrderReceipt> Function(PaperOrderSubmission submission)? onSubmit;
  Future<PaperReasonReceipt> Function(PaperOrderReason reason)? onSaveReason;

  final List<PaperOrderIntent> intents = [];
  final List<PaperOrderSubmission> submissions = [];
  final List<PaperOrderReason> reasons = [];

  @override
  Future<PaperOrderQuote> quote(PaperOrderIntent intent) {
    intents.add(intent);
    final callback = onQuote;
    if (callback != null) return callback(intent);
    return Future.value(
      PaperOrderQuote(
        quoteId: 'quote-1',
        intent: intent,
        unitPricePaper: '231.42',
        estimatedShares: '2.1605',
        feePaper: '0',
        totalPaper: '500',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      ),
    );
  }

  @override
  Future<PaperOrderReceipt> submit(PaperOrderSubmission submission) {
    submissions.add(submission);
    final callback = onSubmit;
    if (callback != null) return callback(submission);
    return Future.value(testReceipt());
  }

  @override
  Future<PaperReasonReceipt> saveReason(PaperOrderReason reason) {
    reasons.add(reason);
    return onSaveReason?.call(reason) ??
        SynchronousFuture<PaperReasonReceipt>(testReasonReceipt(reason));
  }
}

PaperReasonReceipt testReasonReceipt(
  PaperOrderReason reason, {
  int trimsAwarded = 10,
}) => PaperReasonReceipt(
  orderId: reason.orderId,
  assetId: 'apple',
  variantMint: testMint,
  note: reason.note,
  trimsAwarded: trimsAwarded,
  dailyAwardNumber: trimsAwarded == 0 ? null : 1,
  savedAt: DateTime.utc(2026, 9, 20, 12, 32),
);

PaperOrderReceipt testReceipt() => PaperOrderReceipt(
  orderId: testOrderId,
  accountRevision: 1,
  assetId: 'apple',
  variantMint: testMint,
  symbol: 'AAPLx',
  side: PaperOrderSide.buy,
  filledShares: '2.1605',
  filledPaper: '500',
  cashAfterPaper: '9500',
  positionShares: '2.1605',
  positionCostBasisPaper: '500',
  positionValuePaper: '500',
  trimsEarned: 0,
  confirmedAt: DateTime.utc(2026, 9, 20, 12, 31),
);
