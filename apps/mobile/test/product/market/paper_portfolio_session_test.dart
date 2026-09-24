import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/market.dart';

const _guest = '11111111-1111-4111-8111-111111111111';
const _account = '22222222-2222-4222-8222-222222222222';
const _mint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';

void main() {
  test('same-principal rebind preserves state and rejects suspended work', () {
    final session = PaperPortfolioSession();
    final guest = session.bind(_guest);
    expect(session.acceptSnapshot(guest, _snapshot(1)), isTrue);
    expect(session.acceptReceipt(guest, _receipt(revision: 2)), isTrue);

    session.suspend();
    expect(session.acceptSnapshot(guest, _snapshot(2)), isFalse);

    final claimed = session.bind(_guest);
    expect(session.snapshot?.revision, 1);
    expect(session.pendingReceipt?.orderId, _receiptId);
    expect(session.isCurrent(claimed), isTrue);
  });

  test('different principal clears all confirmed and pending state', () {
    final session = PaperPortfolioSession();
    final guest = session.bind(_guest);
    session.acceptSnapshot(guest, _snapshot(1));
    session.acceptReceipt(guest, _receipt(revision: 2));

    final account = session.bind(_account);

    expect(session.isCurrent(guest), isFalse);
    expect(session.isCurrent(account), isTrue);
    expect(session.snapshot, isNull);
    expect(session.pendingReceipt, isNull);
  });

  test('revision reconciles a receipt once and older snapshots cannot win', () {
    final session = PaperPortfolioSession();
    final binding = session.bind(_guest);
    session.acceptSnapshot(binding, _snapshot(1));
    final receipt = _receipt(revision: 2);

    expect(session.acceptReceipt(binding, receipt), isTrue);
    expect(session.acceptReceipt(binding, receipt), isFalse);
    expect(session.pendingReceipt, same(receipt));

    expect(session.acceptSnapshot(binding, _snapshot(2)), isTrue);
    expect(session.pendingReceipt, isNull);
    expect(session.acceptReceipt(binding, receipt), isFalse);
    expect(session.acceptSnapshot(binding, _snapshot(1)), isFalse);
    expect(session.snapshot?.revision, 2);
  });

  test('older receipt callbacks cannot replace a newer pending revision', () {
    final session = PaperPortfolioSession();
    final binding = session.bind(_guest);
    session.acceptSnapshot(binding, _snapshot(1));
    final revisionThree = _receipt(
      revision: 3,
      orderId: '55555555-5555-4555-8555-555555555555',
    );
    final delayedRevisionTwo = _receipt(revision: 2);
    final revisionFour = _receipt(
      revision: 4,
      orderId: '66666666-6666-4666-8666-666666666666',
    );

    expect(session.acceptReceipt(binding, revisionThree), isTrue);
    expect(session.acceptReceipt(binding, delayedRevisionTwo), isFalse);
    expect(session.pendingReceipt, same(revisionThree));
    expect(session.acceptReceipt(binding, revisionFour), isTrue);
    expect(session.pendingReceipt, same(revisionFour));
  });

  test('reset advances the cycle and blocks delayed old portfolio work', () {
    final session = PaperPortfolioSession();
    final binding = session.bind(_guest);
    session.acceptSnapshot(binding, _snapshot(2));
    session.acceptReceipt(binding, _receipt(revision: 3));
    final reset = _snapshot(3);

    expect(
      session.acceptResetSnapshot(binding, reset, previousRevision: 2),
      isTrue,
    );
    expect(session.snapshot?.revision, 3);
    expect(session.snapshot?.positions, isEmpty);
    expect(session.pendingReceipt, isNull);
    expect(session.acceptSnapshot(binding, _snapshot(2)), isFalse);
    expect(session.acceptReceipt(binding, _receipt(revision: 3)), isFalse);
  });

  test('reset rejects a skipped revision or nonempty cycle', () {
    final session = PaperPortfolioSession();
    final binding = session.bind(_guest);
    session.acceptSnapshot(binding, _snapshot(2));
    final nonempty = PaperPortfolioSnapshot(
      revision: 3,
      startingCashPaper: '10000',
      cashPaper: '9750',
      positions: const [],
      recentOrders: [
        PaperPortfolioOrder(
          orderId: _receiptId,
          assetId: 'apple',
          variantMint: _mint,
          symbol: 'AAPLx',
          action: 'buy',
          pricePaper: '250',
          quantity: '1',
          cashAfterPaper: '9750',
          committedAt: DateTime.utc(2026, 9, 20, 12),
        ),
      ],
      valuation: PaperPortfolioValuation.notIncluded(
        portfolioRevision: 3,
        cashPaper: '9750',
        openPositions: const [],
      ),
      openedAt: null,
      updatedAt: null,
    );

    expect(
      session.acceptResetSnapshot(binding, _snapshot(4), previousRevision: 2),
      isFalse,
    );
    expect(
      session.acceptResetSnapshot(binding, nonempty, previousRevision: 2),
      isFalse,
    );
    expect(session.snapshot?.revision, 2);
  });

  test('historical reset receipt preserves a newer desk revision', () {
    final session = PaperPortfolioSession();
    final binding = session.bind(_guest);
    final newer = _snapshot(5);
    session.acceptSnapshot(binding, newer);

    expect(
      session.acceptResetSnapshot(binding, _snapshot(4), previousRevision: 3),
      isFalse,
    );
    expect(session.snapshot, same(newer));
    expect(session.snapshot?.revision, 5);
  });
}

const _receiptId = '44444444-4444-4444-8444-444444444444';

PaperOrderReceipt _receipt({
  required int revision,
  String orderId = _receiptId,
}) => PaperOrderReceipt(
  orderId: orderId,
  accountRevision: revision,
  assetId: 'apple',
  variantMint: _mint,
  symbol: 'AAPLx',
  side: PaperOrderSide.buy,
  filledShares: '1',
  filledPaper: '250',
  cashAfterPaper: '9750',
  positionShares: '1',
  positionCostBasisPaper: '250',
  positionValuePaper: '250',
  trimsEarned: 0,
  confirmedAt: DateTime.utc(2026, 9, 20, 12),
);

PaperPortfolioSnapshot _snapshot(int revision) {
  const cash = '10000';
  return PaperPortfolioSnapshot(
    revision: revision,
    startingCashPaper: cash,
    cashPaper: cash,
    positions: const [],
    recentOrders: const [],
    valuation: PaperPortfolioValuation.notIncluded(
      portfolioRevision: revision,
      cashPaper: cash,
      openPositions: const [],
    ),
    openedAt: revision == 0 ? null : DateTime.utc(2026, 9, 20, 12),
    updatedAt: revision == 0 ? null : DateTime.utc(2026, 9, 20, 12),
  );
}
