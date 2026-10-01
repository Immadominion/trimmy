import '../../ui_review/review_feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../design/product_notice.dart';
import '../design/product_success_mark.dart';
import '../design/paper_format.dart';
import 'order_amount_math.dart';

import '../../ui_review/review_components.dart';
import '../../ui_review/review_trade_ticket.dart';
import '../../ui_review/ui_review_app.dart';
import '../career/career_repository.dart';
import 'market_craft.dart';
import 'market_models.dart';
import 'paper_order_repository.dart';

enum _OrderStep { amount, review, report }

/// Copy produced when it is shown, so a notice follows a language change.
typedef _Copy = String Function(AppLocalizations l10n);

/// The grammatical count for an exact share decimal. Only picks a plural
/// form; amounts themselves stay exact strings.
num _shareCount(String shares) => num.tryParse(shares) ?? 0;

class PaperOrderFlow extends StatefulWidget {
  const PaperOrderFlow({
    super.key,
    required this.company,
    required this.side,
    required this.repository,
    required this.clientOrderId,
    required this.availablePaper,
    required this.availableShares,
    this.referencePrice,
    this.onConfirmed,
    this.onReasonSaved,
    this.reasonCaptureAvailable = true,
    this.reasonMutationId,
    this.firstTradeAmount,
    this.onExitFirstTrade,
    this.onBackToSearch,
  });

  final MarketCompany company;
  final PaperOrderSide side;
  final PaperOrderRepository repository;

  /// Must return a fresh idempotency key for each accepted quote. Retries of
  /// that quote reuse the same key so an ambiguous response can be recovered.
  final String Function() clientOrderId;
  final String availablePaper;
  final String availableShares;
  final double? referencePrice;
  final ValueChanged<PaperOrderReceipt>? onConfirmed;
  final ValueChanged<PaperReasonReceipt>? onReasonSaved;
  final bool reasonCaptureAvailable;
  final String Function()? reasonMutationId;

  /// Opens a real quote in the first-trade confirmation sheet. All quote,
  /// expiry, idempotency and receipt handling remains in this flow.
  final String? firstTradeAmount;
  final VoidCallback? onExitFirstTrade;
  final VoidCallback? onBackToSearch;

  @override
  State<PaperOrderFlow> createState() => _PaperOrderFlowState();
}

class _PaperOrderFlowState extends State<PaperOrderFlow> {
  final _reason = TextEditingController();
  _OrderStep _step = _OrderStep.amount;
  late PaperQuantityUnit _unit;
  String _input = '0';
  PaperOrderQuote? _quote;
  PaperOrderSubmission? _submission;
  PaperOrderReceipt? _receipt;
  PaperOrderReason? _pendingReason;
  PaperReasonReceipt? _reasonReceipt;
  _Copy? _notice;
  Timer? _noticeTimer;
  _Copy? get _message => _notice;
  set _message(_Copy? value) {
    _noticeTimer?.cancel();
    _notice = value;
    if (value != null) {
      _noticeTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _notice = null);
      });
    }
  }

  Widget _messageView() => ProductNotice(
    key: const ValueKey('paper-order-message'),
    message: _message!(context.l10n),
    onDismiss: () => setState(() => _message = null),
  );
  bool _busy = false;
  bool _savingReason = false;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _unit = widget.side == PaperOrderSide.buy
        ? PaperQuantityUnit.paper
        : PaperQuantityUnit.shares;
    if (widget.firstTradeAmount case final amount?) {
      _input = amount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestQuote();
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _noticeTimer?.cancel();
    _reason.dispose();
    super.dispose();
  }

  void _key(String key) {
    if (_busy) return;
    if (ReviewFeedback.shared.haptics) {
      ReviewFeedback.shared.impact(selection: true);
    }
    setState(() {
      _message = null;
      if (key == 'backspace') {
        _input = _input.length <= 1
            ? '0'
            : _input.substring(0, _input.length - 1);
        return;
      }
      if (key == '.') {
        if (!_input.contains('.')) _input = '$_input.';
        return;
      }
      if (_input == '0') {
        _input = key;
      } else if (_input.length < 20) {
        final decimals = _input.contains('.')
            ? _input.length - _input.indexOf('.') - 1
            : 0;
        final maxDecimals = _unit == PaperQuantityUnit.paper ? 2 : 6;
        if (!_input.contains('.') || decimals < maxDecimals) _input += key;
      }
    });
  }

  void _setPreset(String value) {
    setState(() {
      _input = value;
      _message = null;
    });
  }

  String? get _price {
    final price = widget.referencePrice ?? widget.company.priceUsd;
    return price != null && price.isFinite && price > 0
        ? price.toStringAsFixed(6)
        : null;
  }

  String _maxValue() => _unit == PaperQuantityUnit.paper
      ? OrderAmountMath.cents(widget.availablePaper)
      : _price == null
      ? '0'
      : OrderAmountMath.sharesForCash(widget.availablePaper, _price!);

  void _switchUnit(PaperQuantityUnit value) {
    if (_busy || value == _unit) return;
    if (ReviewFeedback.shared.haptics) {
      ReviewFeedback.shared.impact(selection: true);
    }
    setState(() {
      _input = _price == null
          ? '0'
          : value == PaperQuantityUnit.shares
          ? OrderAmountMath.sharesForCash(
              _trimDecimal(_input),
              _price!,
              selling: widget.side == PaperOrderSide.sell,
            )
          : OrderAmountMath.cents(
              OrderAmountMath.cashForShares(_trimDecimal(_input), _price!),
            );
      _unit = value;
      _message = null;
    });
  }

  String _equivalent(AppLocalizations l10n, AppFormats formats) {
    if (_price == null) return l10n.paperOrderConversionAtReview;
    if (_unit == PaperQuantityUnit.paper) {
      final shares = OrderAmountMath.sharesForCash(
        _trimDecimal(_input),
        _price!,
        selling: widget.side == PaperOrderSide.sell,
      );
      return l10n.paperOrderEquivalentShares(
        _shareCount(shares),
        formats.number(shares),
      );
    }
    final cash = OrderAmountMath.cashForShares(_trimDecimal(_input), _price!);
    return l10n.paperOrderEquivalentPaper(
      formats.number(formatPaperForDisplay(cash)),
    );
  }

  static String _trimDecimal(String value) {
    if (!value.contains('.')) return value;
    return value
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// The typed amount with the reader's grouping and decimal mark. The
  /// typed value itself stays a plain decimal ("1234.5").
  String _displayInput(AppFormats formats) {
    final parts = _input.split('.');
    final whole = parts.first;
    final grouped = StringBuffer();
    for (var index = 0; index < whole.length; index++) {
      if (index > 0 && (whole.length - index) % 3 == 0) {
        grouped.write(formats.groupSeparator);
      }
      grouped.write(whole[index]);
    }
    return parts.length == 1
        ? grouped.toString()
        : '$grouped${formats.decimalSeparator}${parts[1]}';
  }

  Future<void> _requestQuote() async {
    final variant = widget.company.primaryVariant;
    if (variant == null) {
      setState(() => _message = (l10n) => l10n.paperOrderNoVersion);
      return;
    }
    late final PaperOrderIntent intent;
    try {
      intent = PaperOrderIntent(
        assetId: widget.company.assetId,
        variantMint: variant.mint,
        side: widget.side,
        quantityUnit: _unit,
        quantity: _trimDecimal(_input),
      );
    } on PaperOrderException catch (error) {
      setState(() => _message = _failureMessage(error.failure));
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final quote = await widget.repository.quote(intent);
      if (!mounted || generation != _generation) return;
      if (quote.intent != intent) {
        throw const PaperOrderException(PaperOrderFailure.rejected);
      }
      if (!DateTime.now().toUtc().isBefore(quote.expiresAt)) {
        throw const PaperOrderException(PaperOrderFailure.quoteExpired);
      }
      setState(() {
        _quote = quote;
        _submission = null;
        _busy = false;
        _step = _OrderStep.review;
      });
    } on PaperOrderException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _message = _failureMessage(error.failure);
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _message = _failureMessage(PaperOrderFailure.unavailable);
      });
    }
  }

  Future<void> _confirm() async {
    final quote = _quote;
    if (quote == null || _busy) return;
    if (_submission == null &&
        !DateTime.now().toUtc().isBefore(quote.expiresAt)) {
      setState(() {
        _step = _OrderStep.amount;
        _quote = null;
        _submission = null;
        _message = _failureMessage(PaperOrderFailure.quoteExpired);
      });
      return;
    }
    late final PaperOrderSubmission submission;
    try {
      submission =
          _submission ??
          PaperOrderSubmission(
            quoteId: quote.quoteId,
            clientOrderId: widget.clientOrderId(),
          );
      _submission = submission;
    } on PaperOrderException catch (error) {
      setState(() => _message = _failureMessage(error.failure));
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    late final PaperOrderReceipt receipt;
    try {
      receipt = await widget.repository.submit(submission);
      if (!mounted || generation != _generation) return;
      if (receipt.assetId != widget.company.assetId ||
          receipt.side != widget.side) {
        throw const PaperOrderException(PaperOrderFailure.rejected);
      }
    } on PaperOrderException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _message = _failureMessage(error.failure);
        if (error.failure == PaperOrderFailure.quoteExpired ||
            error.failure == PaperOrderFailure.priceChanged) {
          _step = _OrderStep.amount;
          _quote = null;
          _submission = null;
        }
      });
      return;
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _message = _failureMessage(PaperOrderFailure.unavailable);
      });
      return;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _receipt = receipt;
      _busy = false;
      _step = _OrderStep.report;
    });
    if (ReviewFeedback.shared.haptics) {
      ReviewFeedback.shared.impact();
    }
    try {
      widget.onConfirmed?.call(receipt);
    } catch (_) {
      // The durable receipt owns completion. A host refresh callback cannot
      // turn a confirmed order back into a failed one.
    }
  }

  Future<void> _saveReason() async {
    final receipt = _receipt;
    if (receipt == null ||
        receipt.side != PaperOrderSide.buy ||
        _savingReason ||
        _reasonReceipt != null) {
      return;
    }
    late final PaperOrderReason reason;
    try {
      reason =
          _pendingReason ??
          PaperOrderReason(
            mutationId: (widget.reasonMutationId ?? widget.clientOrderId)(),
            orderId: receipt.orderId,
            note: _reason.text,
          );
      _pendingReason = reason;
    } on CareerException catch (error) {
      setState(() => _message = _reasonFailureMessage(error.failure));
      return;
    } catch (_) {
      setState(() => _message = (l10n) => l10n.paperOrderReasonNotSaved);
      return;
    }
    setState(() {
      _savingReason = true;
      _message = null;
    });
    try {
      final saved = await widget.repository.saveReason(reason);
      if (!mounted) return;
      if (saved.orderId != receipt.orderId ||
          saved.assetId != receipt.assetId ||
          saved.variantMint != widget.company.primaryVariant?.mint ||
          saved.note != reason.note) {
        throw const CareerException(CareerFailure.invalidResponse);
      }
      setState(() {
        _savingReason = false;
        _reasonReceipt = saved;
        _message = null;
      });
      try {
        widget.onReasonSaved?.call(saved);
      } catch (_) {
        // The server receipt owns the save. A host refresh cannot undo it.
      }
    } on CareerException catch (error) {
      if (!mounted) return;
      setState(() {
        _savingReason = false;
        _message = _reasonFailureMessage(error.failure);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingReason = false;
        _message = (l10n) => l10n.paperOrderReasonNotSavedDone;
      });
    }
  }

  static _Copy _reasonFailureMessage(CareerFailure failure) =>
      (l10n) => switch (failure) {
        CareerFailure.invalidInput => l10n.paperOrderReasonTooLong,
        CareerFailure.offline => l10n.paperOrderReasonOffline,
        CareerFailure.timeout => l10n.paperOrderReasonTimeout,
        CareerFailure.accountRequired => l10n.paperOrderReasonSessionExpired,
        CareerFailure.profileRequired => l10n.paperOrderReasonProfileRequired,
        CareerFailure.orderNotFound => l10n.paperOrderReasonOrderNotFound,
        CareerFailure.buyOrderRequired => l10n.paperOrderReasonBuyRequired,
        CareerFailure.positionRequired => l10n.paperOrderReasonPositionRequired,
        CareerFailure.reasonExists => l10n.paperOrderReasonExists,
        CareerFailure.idempotencyConflict => l10n.paperOrderReasonRetryMismatch,
        CareerFailure.rateLimited => l10n.paperOrderReasonBusy,
        CareerFailure.invalidResponse ||
        CareerFailure.unavailable ||
        CareerFailure.dayContextRevisionConflict ||
        CareerFailure.timeZoneChangeTooSoon ||
        CareerFailure.revisionExhausted ||
        CareerFailure.rejected => l10n.paperOrderReasonNotSaved,
      };

  static _Copy _failureMessage(PaperOrderFailure failure) =>
      (l10n) => switch (failure) {
        PaperOrderFailure.invalidAmount => l10n.paperOrderErrorInvalidAmount,
        PaperOrderFailure.insufficientPaper =>
          l10n.paperOrderErrorInsufficientPaper,
        PaperOrderFailure.insufficientShares =>
          l10n.paperOrderErrorInsufficientShares,
        PaperOrderFailure.quoteExpired => l10n.paperOrderErrorQuoteExpired,
        PaperOrderFailure.priceChanged => l10n.paperOrderErrorPriceChanged,
        PaperOrderFailure.offline => l10n.paperOrderErrorOffline,
        PaperOrderFailure.timeout => l10n.paperOrderErrorTimeout,
        PaperOrderFailure.accountRequired =>
          l10n.paperOrderErrorAccountRequired,
        PaperOrderFailure.duplicate => l10n.paperOrderErrorDuplicate,
        PaperOrderFailure.rejected => l10n.paperOrderErrorRejected,
        PaperOrderFailure.unavailable => l10n.paperOrderErrorUnavailable,
      };

  void _back() {
    if (_busy || _savingReason) return;
    if (_step == _OrderStep.review) {
      setState(() {
        _step = _OrderStep.amount;
        _quote = null;
        _submission = null;
        _message = null;
      });
      return;
    }
    if (_step == _OrderStep.amount && widget.onBackToSearch != null) {
      widget.onBackToSearch!();
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.firstTradeAmount != null) return _firstTradeReview();
    final l10n = context.l10n;
    final buying = widget.side == PaperOrderSide.buy;
    final title = switch (_step) {
      _OrderStep.amount =>
        buying
            ? l10n.paperOrderBuyTitle(widget.company.symbol)
            : l10n.paperOrderSellTitle(widget.company.symbol),
      _OrderStep.review =>
        buying ? l10n.paperOrderReviewBuyTitle : l10n.paperOrderReviewSellTitle,
      _OrderStep.report => l10n.paperOrderConfirmedTitle,
    };
    // System back steps back like the arrow: from the review to the amount,
    // and from the amount to search in Fast buy, not out of the whole sheet.
    final stepsBack =
        _step == _OrderStep.review ||
        (_step == _OrderStep.amount && widget.onBackToSearch != null);
    return PopScope(
      canPop: !_busy && !_savingReason && !stepsBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: MarketPalette.paper,
        appBar: AppBar(
          backgroundColor: MarketPalette.paper,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: _step == _OrderStep.report
                ? l10n.commonClose
                : l10n.commonBack,
            onPressed: _busy || _savingReason ? null : _back,
            icon: Icon(
              _step == _OrderStep.report
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            child: switch (_step) {
              _OrderStep.amount => _amountScreen(),
              _OrderStep.review => _reviewScreen(),
              _OrderStep.report => _reportScreen(),
            },
          ),
        ),
      ),
    );
  }

  Widget _firstTradeReview() {
    final quote = _quote;
    final l10n = context.l10n;
    final formats = context.formats;
    return PopScope<Object?>(
      canPop: !_busy,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .88,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontFamily: 'Dejanire Sans',
                color: UiReviewColor.ink,
              ),
              child: Column(
                key: const ValueKey('first-paper-order-review'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: Semantics(
                            label: l10n.paperOrderFirstTradeSwipeHint,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragEnd: (details) {
                                if (!_busy &&
                                    (details.primaryVelocity ?? 0) > 50) {
                                  Navigator.of(context).maybePop();
                                }
                              },
                              child: SizedBox(
                                width: 96,
                                height: 32,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    width: 34,
                                    height: 4,
                                    margin: const EdgeInsets.only(top: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE4E1EA),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: l10n.paperOrderFirstTradeSkip,
                            onPressed: _busy ? null : widget.onExitFirstTrade,
                            icon: const Icon(Icons.close_rounded, size: 29),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.paperOrderFirstTradeReviewTitle,
                    style: const TextStyle(
                      fontFamily: reviewDisplay,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.08,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (quote != null && _step != _OrderStep.amount)
                    ReviewTradeTicket(
                      upperColor: const Color(0xFFF6F5F8),
                      lowerColor: const Color(0xFFF2EEFF),
                      upper: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              CompanyLogo(
                                name: widget.company.name,
                                logoUrl: widget.company.logoUrl,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.company.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 26),
                          _DetailRow(
                            label: l10n.paperOrderSharesLabel,
                            value: Text(formats.number(quote.estimatedShares)),
                          ),
                          const SizedBox(height: 14),
                          _DetailRow(
                            label: l10n.paperOrderPricePerShare,
                            value: PaperAmount(quote.unitPricePaper),
                          ),
                          const SizedBox(height: 14),
                          _DetailRow(
                            label: l10n.paperOrderFee,
                            value: PaperAmount(quote.feePaper),
                          ),
                        ],
                      ),
                      lower: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.paperOrderTotal),
                          const SizedBox(height: 7),
                          PaperAmount(
                            quote.totalPaper,
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  if (_message != null) ...[
                    const SizedBox(height: 14),
                    _messageView(),
                  ],
                  const SizedBox(height: 22),
                  ReviewPrimaryButton(
                    key: const ValueKey('paper-order-confirm-button'),
                    background: UiReviewColor.violet,
                    label: _busy
                        ? (_step == _OrderStep.review
                              ? l10n.paperOrderConfirmingBuy
                              : l10n.paperOrderCheckingPrice)
                        : _step == _OrderStep.amount
                        ? l10n.commonTryAgain
                        : l10n.paperOrderConfirmBuy,
                    onPressed: _busy || _receipt != null
                        ? null
                        : _step == _OrderStep.amount
                        ? _requestQuote
                        : _confirm,
                    icon: Icons.check_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _amountScreen() {
    final l10n = context.l10n;
    final formats = context.formats;
    final display = _displayInput(formats);
    final available = _trimDecimal(widget.availableShares);
    return Column(
      key: const ValueKey('paper-order-amount'),
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        CompanyLogo(
                          name: widget.company.name,
                          logoUrl: widget.company.logoUrl,
                          color: widget.company.brandColor,
                          size: 48,
                        ),
                        const SizedBox(height: 20),
                        Semantics(
                          label: _unit == PaperQuantityUnit.paper
                              ? l10n.paperAmount(display)
                              : l10n.paperOrderSharesValue(
                                  _shareCount(_trimDecimal(_input)),
                                  display,
                                ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              display,
                              key: const ValueKey('order-amount-value'),
                              style: const TextStyle(
                                fontSize: 58,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.8,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _equivalent(l10n, formats),
                          key: const ValueKey('order-equivalent'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: MarketPalette.muted,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: 220,
                          child: _UnitSwitch(
                            value: _unit,
                            onChanged: _switchUnit,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _presets(l10n, formats),
                      ],
                    ),
                    Column(
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          widget.side == PaperOrderSide.sell
                              ? l10n.paperOrderSharesAvailable(
                                  _shareCount(available),
                                  formats.number(available),
                                )
                              : l10n.paperOrderPaperAvailable(
                                  formats.number(
                                    formatPaperForDisplay(
                                      widget.availablePaper,
                                    ),
                                  ),
                                ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: MarketPalette.muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _Keypad(onKey: _key),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _BottomAction(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_message != null) ...[
                _messageView(),
                const SizedBox(height: 10),
              ],
              MarketPrimaryButton(
                key: const ValueKey('paper-order-review-button'),
                label: l10n.commonContinue,
                color: MarketPalette.violet,
                onPressed: _busy ? null : _requestQuote,
                busy: _busy,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _presets(AppLocalizations l10n, AppFormats formats) {
    final selling = widget.side == PaperOrderSide.sell;
    // (id for the widget key, label shown, exact value entered). The id
    // stays the English label so keys never depend on the language.
    final presets = selling
        ? <(String, String, String)>[
            (
              '25%',
              formats.percent('25'),
              OrderAmountMath.portion(widget.availableShares, 25),
            ),
            (
              '50%',
              formats.percent('50'),
              OrderAmountMath.portion(widget.availableShares, 50),
            ),
            (
              '75%',
              formats.percent('75'),
              OrderAmountMath.portion(widget.availableShares, 75),
            ),
            ('Max', l10n.commonMax, widget.availableShares),
          ]
        : _unit == PaperQuantityUnit.paper
        ? <(String, String, String)>[
            ('100', formats.number('100'), '100'),
            ('500', formats.number('500'), '500'),
            ('1,000', formats.number('1,000'), '1000'),
            ('Max', l10n.commonMax, _maxValue()),
          ]
        : <(String, String, String)>[
            ('1', formats.number('1'), '1'),
            ('5', formats.number('5'), '5'),
            ('10', formats.number('10'), '10'),
            ('Max', l10n.commonMax, _maxValue()),
          ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final preset in presets)
          ActionChip(
            key: ValueKey('paper-preset-${preset.$1}'),
            label: Text(preset.$2),
            onPressed: _busy
                ? null
                : () {
                    if (ReviewFeedback.shared.haptics) {
                      ReviewFeedback.shared.impact(selection: true);
                    }
                    // Percentages and Max always sell exact shares, never a rounded
                    // cash equivalent that can oversell or leave fractional dust.
                    if (selling) _unit = PaperQuantityUnit.shares;
                    _setPreset(preset.$3);
                  },
            backgroundColor: const Color(0xFFF5F3FA),
            side: BorderSide.none,
            labelStyle: const TextStyle(
              color: Color(0xFF6650AF),
              fontWeight: FontWeight.w700,
            ),
            shape: marketSquircle(16),
          ),
      ],
    );
  }

  Widget _reviewScreen() {
    final quote = _quote!;
    final l10n = context.l10n;
    final formats = context.formats;
    final buying = widget.side == PaperOrderSide.buy;
    final shares = formats.number(quote.estimatedShares);
    final count = _shareCount(quote.estimatedShares);
    return Column(
      key: const ValueKey('paper-order-review'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            children: [
              ReviewTradeTicket(
                upperColor: const Color(0xFFF7F6FA),
                lowerColor: const Color(0xFFF0EBFF),
                upper: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CompanyLogo(
                          name: widget.company.name,
                          logoUrl: widget.company.logoUrl,
                          color: widget.company.brandColor,
                          size: 48,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.company.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                cashtag(
                                  widget.company.primaryVariant?.symbol ??
                                      widget.company.symbol,
                                ),
                                style: const TextStyle(
                                  color: MarketPalette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      buying
                          ? l10n.paperOrderBuyingShares(count, shares)
                          : l10n.paperOrderSellingShares(count, shares),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _DetailRow(
                      label: l10n.paperOrderPricePerShare,
                      value: PaperAmount(quote.unitPricePaper),
                    ),
                    const SizedBox(height: 20),
                    _DetailRow(
                      label: l10n.paperOrderFee,
                      value: PaperAmount(quote.feePaper),
                    ),
                  ],
                ),
                lower: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      buying
                          ? l10n.paperOrderYouPay
                          : l10n.paperOrderYouReceive,
                      style: const TextStyle(
                        color: Color(0xFF66558A),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PaperAmount(
                      quote.totalPaper,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _BottomAction(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_message != null) ...[
                _messageView(),
                const SizedBox(height: 10),
              ],
              MarketPrimaryButton(
                key: const ValueKey('paper-order-confirm-button'),
                label: buying
                    ? l10n.paperOrderConfirmBuy
                    : l10n.paperOrderConfirmSell,
                color: MarketPalette.violet,
                onPressed: _busy ? null : _confirm,
                busy: _busy,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reportScreen() {
    final receipt = _receipt!;
    final savedReason = _reasonReceipt;
    final l10n = context.l10n;
    final formats = context.formats;
    final buying = widget.side == PaperOrderSide.buy;
    final symbol = widget.company.symbol;
    final filled = formats.number(receipt.filledShares);
    final filledCount = _shareCount(receipt.filledShares);
    return ListView(
      key: const ValueKey('paper-order-report'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Semantics(
          liveRegion: true,
          label: buying
              ? l10n.paperOrderBuyConfirmed
              : l10n.paperOrderSaleConfirmed,
          child: const Center(child: ProductSuccessMark(size: 66)),
        ),
        const SizedBox(height: 12),
        Text(
          buying
              ? l10n.paperOrderOnYourDesk(symbol)
              : receipt.positionShares == '0'
              ? l10n.paperOrderLeftYourDesk(symbol)
              : l10n.paperOrderPositionChanged(symbol),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          buying
              ? l10n.paperOrderBoughtShares(filledCount, filled)
              : l10n.paperOrderSoldShares(filledCount, filled),
          textAlign: TextAlign.center,
          style: const TextStyle(color: MarketPalette.muted),
        ),
        const SizedBox(height: 20),
        MarketPanel(
          color: const Color(0xFFF3EFFB),
          child: Column(
            children: [
              _DetailRow(
                label: l10n.paperOrderYourPosition,
                value: Text(
                  l10n.paperOrderSharesValue(
                    _shareCount(receipt.positionShares),
                    formats.number(receipt.positionShares),
                  ),
                ),
                strong: true,
              ),
              const SizedBox(height: 22),
              _DetailRow(
                label: l10n.paperOrderPositionValue,
                value: PaperAmount(receipt.positionValuePaper),
              ),
              if (receipt.trimsEarned > 0) ...[
                const SizedBox(height: 22),
                _DetailRow(
                  label: l10n.paperOrderTrimsEarned,
                  value: Text(formats.number('+${receipt.trimsEarned}')),
                ),
              ],
              if (receipt.missionProgress != null) ...[
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    receipt.missionProgress!,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (receipt.side == PaperOrderSide.buy &&
            widget.reasonCaptureAvailable) ...[
          if (savedReason == null) ...[
            TextField(
              key: const ValueKey('paper-order-reason'),
              controller: _reason,
              readOnly: _pendingReason != null,
              maxLength: 180,
              maxLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.paperOrderReasonLabel,
                hintText: l10n.paperOrderReasonHint,
                filled: true,
                fillColor: const Color(0xFFF7F6FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              _messageView(),
            ],
            const SizedBox(height: 12),
            MarketPrimaryButton(
              color: MarketPalette.violet,
              key: const ValueKey('paper-order-save-reason'),
              label: _pendingReason == null
                  ? l10n.paperOrderSaveReason
                  : l10n.paperOrderRetryReason,
              onPressed: _savingReason ? null : _saveReason,
              busy: _savingReason,
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const ValueKey('paper-order-skip-reason'),
              onPressed: _savingReason
                  ? null
                  : () => Navigator.of(context).pop(receipt),
              child: Text(l10n.commonSkip),
            ),
          ] else ...[
            MarketPanel(
              color: const Color(0xFFF3EFFB),
              child: Column(
                children: [
                  const ProductSuccessMark(size: 44),
                  const SizedBox(height: 8),
                  Text(
                    savedReason.trimsAwarded > 0
                        ? l10n.paperOrderReasonTrims(
                            formats.number('${savedReason.trimsAwarded}'),
                          )
                        : l10n.paperOrderReasonSaved,
                    key: const ValueKey('paper-order-reason-reward'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.paperOrderReasonQuote(savedReason.note),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: MarketPalette.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            MarketPrimaryButton(
              color: MarketPalette.violet,
              key: const ValueKey('paper-order-reason-done'),
              label: l10n.commonDone,
              onPressed: () => Navigator.of(context).pop(receipt),
            ),
          ],
        ] else ...[
          if (receipt.side == PaperOrderSide.buy) ...[
            Text(
              l10n.paperOrderReasonUnavailable,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MarketPalette.muted),
            ),
            const SizedBox(height: 14),
          ],
          MarketPrimaryButton(
            color: MarketPalette.violet,
            key: const ValueKey('paper-order-done'),
            label: l10n.commonDone,
            onPressed: () => Navigator.of(context).pop(receipt),
          ),
        ],
      ],
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: MarketPalette.paper),
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: child,
    ),
  );
}

class _UnitSwitch extends StatelessWidget {
  const _UnitSwitch({required this.value, required this.onChanged});
  final PaperQuantityUnit value;
  final ValueChanged<PaperQuantityUnit> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: context.l10n.paperOrderUnitLabel,
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: const Color(0xFFF4F2F8),
        shape: marketSquircle(18),
      ),
      child: Row(
        children: [
          for (final unit in PaperQuantityUnit.values)
            Expanded(
              child: Semantics(
                selected: value == unit,
                button: true,
                child: Material(
                  color: value == unit
                      ? MarketPalette.white
                      : Colors.transparent,
                  shape: marketSquircle(14),
                  child: InkWell(
                    key: ValueKey('paper-unit-${unit.name}'),
                    onTap: () => onChanged(unit),
                    customBorder: marketSquircle(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      // The switch keeps its width; a longer word shrinks a
                      // little instead of wrapping.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          unit == PaperQuantityUnit.paper
                              ? context.l10n.paperOrderUnitPaper
                              : context.l10n.paperOrderUnitShares,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The decimal key types a plain '.' whatever it shows, so the typed value
    // stays the exact decimal the order math reads.
    final decimalMark = context.formats.decimalSeparator;
    const keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '.',
      '0',
      'backspace',
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 56,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        return Semantics(
          label: key == 'backspace'
              ? l10n.paperOrderKeyDelete
              : key == '.'
              ? l10n.paperOrderKeyDecimal
              : key,
          button: true,
          child: Material(
            color: MarketPalette.white,
            shape: marketSquircle(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('paper-key-$key'),
              onTap: () => onKey(key),
              child: Center(
                child: key == 'backspace'
                    ? const Icon(Icons.backspace_outlined)
                    : Text(
                        key == '.' ? decimalMark : key,
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final Widget value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: strong ? MarketPalette.ink : MarketPalette.muted,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: DefaultTextStyle.merge(
          textAlign: TextAlign.end,
          style: TextStyle(
            color: MarketPalette.ink,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          child: value,
        ),
      ),
    ],
  );
}
