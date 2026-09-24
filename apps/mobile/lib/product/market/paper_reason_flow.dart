import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../career/career_repository.dart';
import 'market_craft.dart';
import 'market_models.dart';
import '../design/product_success_mark.dart';
import 'paper_order_repository.dart';
import 'paper_portfolio.dart';

@immutable
final class PaperReasonTarget {
  const PaperReasonTarget({
    required this.orderId,
    required this.assetId,
    required this.variantMint,
    required this.symbol,
    required this.heldShares,
    required this.confirmedAt,
  });

  final String orderId;
  final String assetId;
  final String variantMint;
  final String symbol;
  final String heldShares;
  final DateTime confirmedAt;
}

/// Finds a confirmed buy whose exact stock version is still held.
///
/// The immutable first buy remains the clearest Career evidence only when it
/// also belongs to the current paper cycle. If it was reset, sold, or omitted
/// from the current orders, the newest recent buy for a held position is used.
/// A caller can exclude locally saved orders while it waits for the mission
/// board to refresh.
PaperReasonTarget? selectPaperReasonTarget({
  required PaperPortfolioSnapshot portfolio,
  CareerFirstConfirmedBuy? firstConfirmedBuy,
  Set<String> excludedOrderIds = const <String>{},
}) {
  PaperReasonTarget? target({
    required String orderId,
    required String assetId,
    required String variantMint,
    required String symbol,
    required DateTime confirmedAt,
  }) {
    if (excludedOrderIds.contains(orderId)) return null;
    final position = portfolio.positionFor(assetId, variantMint: variantMint);
    if (position == null || !_positiveDecimal(position.quantity)) return null;
    return PaperReasonTarget(
      orderId: orderId,
      assetId: assetId,
      variantMint: variantMint,
      symbol: symbol,
      heldShares: position.quantity,
      confirmedAt: confirmedAt,
    );
  }

  if (firstConfirmedBuy case final first?) {
    for (final order in portfolio.recentOrders) {
      if (order.orderId == first.orderId &&
          order.action == 'buy' &&
          order.assetId == first.assetId &&
          order.variantMint == first.variantMint) {
        final firstTarget = target(
          orderId: first.orderId,
          assetId: first.assetId,
          variantMint: first.variantMint,
          symbol: first.symbol,
          confirmedAt: first.confirmedAt,
        );
        if (firstTarget != null) return firstTarget;
        break;
      }
    }
  }

  final buys =
      portfolio.recentOrders
          .where((order) => order.action == 'buy')
          .toList(growable: false)
        ..sort((left, right) {
          final byTime = right.committedAt.compareTo(left.committedAt);
          return byTime == 0 ? right.orderId.compareTo(left.orderId) : byTime;
        });
  for (final order in buys) {
    final recentTarget = target(
      orderId: order.orderId,
      assetId: order.assetId,
      variantMint: order.variantMint,
      symbol: order.symbol,
      confirmedAt: order.committedAt,
    );
    if (recentTarget != null) return recentTarget;
  }
  return null;
}

bool _positiveDecimal(String value) {
  final parsed = num.tryParse(value);
  return parsed != null && parsed.isFinite && parsed > 0;
}

class PaperReasonFlow extends StatefulWidget {
  const PaperReasonFlow({
    super.key,
    required this.target,
    required this.repository,
    required this.mutationId,
    this.onSaved,
    this.company,
  });

  final PaperReasonTarget target;
  final MarketCompany? company;
  final PaperOrderRepository repository;

  /// Returns a fresh idempotency key when the user first submits. A retry in
  /// this route reuses that key and the exact normalized note.
  final String Function() mutationId;
  final ValueChanged<PaperReasonReceipt>? onSaved;

  @override
  State<PaperReasonFlow> createState() => _PaperReasonFlowState();
}

class _PaperReasonFlowState extends State<PaperReasonFlow> {
  final _note = TextEditingController();
  PaperOrderReason? _pendingReason;
  PaperReasonReceipt? _receipt;
  String? _message;
  bool _saving = false;
  bool _reasonAlreadyExists = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _receipt != null) return;
    late final PaperOrderReason reason;
    try {
      reason =
          _pendingReason ??
          PaperOrderReason(
            mutationId: widget.mutationId(),
            orderId: widget.target.orderId,
            note: _note.text,
          );
      _pendingReason = reason;
    } on CareerException catch (error) {
      setState(() => _message = _failureMessage(error.failure));
      return;
    } catch (_) {
      setState(() => _message = _failureMessage(CareerFailure.rejected));
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final saved = await widget.repository.saveReason(reason);
      if (!mounted) return;
      if (saved.orderId != widget.target.orderId ||
          saved.assetId != widget.target.assetId ||
          saved.variantMint != widget.target.variantMint ||
          saved.note != reason.note ||
          saved.trimsAwarded < 0 ||
          saved.savedAt.isUtc == false) {
        throw const CareerException(CareerFailure.invalidResponse);
      }
      setState(() {
        _saving = false;
        _receipt = saved;
        _message = null;
      });
      try {
        widget.onSaved?.call(saved);
      } catch (_) {
        // The durable receipt owns the save. A host refresh cannot undo it.
      }
    } on CareerException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = _failureMessage(error.failure);
        _reasonAlreadyExists = error.failure == CareerFailure.reasonExists;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = _failureMessage(CareerFailure.rejected);
      });
    }
  }

  String _failureMessage(CareerFailure failure) => switch (failure) {
    CareerFailure.invalidInput => 'Use one line and 180 characters or fewer.',
    CareerFailure.offline =>
      'You are offline. Your reason was not saved. Try again.',
    CareerFailure.timeout => 'Saving took too long. Try again.',
    CareerFailure.accountRequired =>
      'Refresh your session before saving this reason.',
    CareerFailure.profileRequired =>
      'Finish setting up your profile before saving this reason.',
    CareerFailure.orderNotFound =>
      'This paper buy was not found. Refresh your desk.',
    CareerFailure.buyOrderRequired =>
      'A reason can be added only to a confirmed paper buy.',
    CareerFailure.positionRequired =>
      'You need to still hold this stock before saving a reason.',
    CareerFailure.reasonExists =>
      'This paper buy already has a reason. Refresh your Career.',
    CareerFailure.idempotencyConflict =>
      'This retry could not be matched. Refresh your Career.',
    CareerFailure.rateLimited =>
      'Reasons are busy right now. Try again shortly.',
    CareerFailure.invalidResponse ||
    CareerFailure.unavailable ||
    CareerFailure.dayContextRevisionConflict ||
    CareerFailure.timeZoneChangeTooSoon ||
    CareerFailure.revisionExhausted ||
    CareerFailure.rejected => 'Your reason was not saved. Try again.',
  };

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    final saved = receipt != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          key: const ValueKey('paper-reason-close'),
          tooltip: 'Close',
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          children: [
            if (saved) ...[
              const SizedBox(height: 12),
              const Center(child: ProductSuccessMark(size: 86)),
              const SizedBox(height: 22),
            ],
            Text(
              saved ? 'Reason saved' : 'Write your reason',
              textAlign: saved ? TextAlign.center : TextAlign.start,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            if (!saved) ...[
              const SizedBox(height: 8),
              Text(
                'What made you buy?',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 26),
            _HeldBuyCard(target: widget.target, company: widget.company),
            const SizedBox(height: 20),
            if (!saved) ...[
              TextField(
                key: const ValueKey('paper-reason-note'),
                controller: _note,
                readOnly: _pendingReason != null,
                autofocus: true,
                maxLength: 180,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                ],
                decoration: InputDecoration(
                  hintText: 'Your take on this stock…',
                  filled: true,
                  fillColor: const Color(0xFFF6F4FA),
                  contentPadding: const EdgeInsets.all(20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                _ReasonMessage(_message!),
              ],
              const SizedBox(height: 18),
              if (_reasonAlreadyExists)
                MarketPrimaryButton(
                  key: const ValueKey('paper-reason-close-existing'),
                  color: MarketPalette.violet,
                  label: 'Close and refresh',
                  onPressed: () => Navigator.maybePop(context),
                )
              else
                MarketPrimaryButton(
                  key: const ValueKey('paper-reason-save'),
                  color: MarketPalette.violet,
                  label: _pendingReason == null
                      ? 'Save reason'
                      : 'Retry reason',
                  onPressed: _saving ? null : _save,
                  busy: _saving,
                ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(22),
                decoration: ShapeDecoration(
                  color: const Color(0xFFF4F0FC),
                  shape: marketSquircle(25),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pendingReason?.note ?? _note.text,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      receipt.trimsAwarded > 0
                          ? '+${receipt.trimsAwarded} Trims'
                          : 'Mission recorded',
                      key: const ValueKey('paper-reason-reward'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: MarketPalette.violet,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              MarketPrimaryButton(
                key: const ValueKey('paper-reason-done'),
                color: MarketPalette.violet,
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(receipt),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeldBuyCard extends StatelessWidget {
  const _HeldBuyCard({required this.target, this.company});
  final PaperReasonTarget target;
  final MarketCompany? company;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      CompanyLogo(
        name: company?.name ?? target.symbol,
        logoUrl: company?.logoUrl,
        color: Colors.white,
        size: 52,
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              company?.name ?? target.symbol,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${target.heldShares} ${num.tryParse(target.heldShares) == 1 ? 'share' : 'shares'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      const ProductSuccessMark(size: 30),
    ],
  );
}

class _ReasonMessage extends StatelessWidget {
  const _ReasonMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      key: const ValueKey('paper-reason-message'),
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: MarketPalette.softLoss,
        shape: marketSquircle(15),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: MarketPalette.loss,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
