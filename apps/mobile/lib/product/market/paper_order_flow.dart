import '../../ui_review/review_feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String? _notice;
  Timer? _noticeTimer;
  String? get _message => _notice;
  set _message(String? value) {
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
    message: _message!,
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

  String get _verb => widget.side == PaperOrderSide.buy ? 'Buy' : 'Sell';

  void _key(String key) {
    if (_busy) return;
    if (ReviewFeedback.shared.haptics) {
      HapticFeedback.selectionClick();
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
      HapticFeedback.selectionClick();
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

  String get _equivalent {
    if (_price == null) return 'Conversion shown at review';
    if (_unit == PaperQuantityUnit.paper) {
      return '≈ ${OrderAmountMath.sharesForCash(_trimDecimal(_input), _price!, selling: widget.side == PaperOrderSide.sell)} shares';
    }
    final cash = OrderAmountMath.cashForShares(_trimDecimal(_input), _price!);
    return '≈ ${formatPaperForDisplay(cash)} paper';
  }

  static String _trimDecimal(String value) {
    if (!value.contains('.')) return value;
    return value
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _displayInput() {
    final parts = _input.split('.');
    final whole = parts.first;
    final grouped = StringBuffer();
    for (var index = 0; index < whole.length; index++) {
      if (index > 0 && (whole.length - index) % 3 == 0) grouped.write(',');
      grouped.write(whole[index]);
    }
    return parts.length == 1 ? grouped.toString() : '$grouped.${parts[1]}';
  }

  Future<void> _requestQuote() async {
    final variant = widget.company.primaryVariant;
    if (variant == null) {
      setState(() => _message = 'This company has no available version.');
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
      HapticFeedback.lightImpact();
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
      setState(
        () =>
            _message = 'Trade confirmed. Your reason was not saved. Try again.',
      );
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
        _message =
            'The trade is done, but the reason was not saved. Try again.';
      });
    }
  }

  String _reasonFailureMessage(CareerFailure failure) => switch (failure) {
    CareerFailure.invalidInput => 'Use one line and 180 characters or fewer.',
    CareerFailure.offline =>
      'Trade confirmed. You are offline, so your reason was not saved. Try again.',
    CareerFailure.timeout =>
      'Trade confirmed. Saving the reason took too long. Try again.',
    CareerFailure.accountRequired =>
      'Trade confirmed. Your session needs to be refreshed before saving the reason.',
    CareerFailure.profileRequired =>
      'Trade confirmed. Finish setting up your profile before saving the reason.',
    CareerFailure.orderNotFound =>
      'Trade confirmed. This order was not found. Refresh your desk.',
    CareerFailure.buyOrderRequired =>
      'Reasons can be saved only after a confirmed paper buy.',
    CareerFailure.positionRequired =>
      'Trade confirmed. Hold this stock before saving a reason.',
    CareerFailure.reasonExists =>
      'This trade already has a saved reason. Refresh your career.',
    CareerFailure.idempotencyConflict =>
      'Trade confirmed. This retry could not be matched. Refresh your career.',
    CareerFailure.rateLimited =>
      'Trade confirmed. Reasons are busy right now. Try again shortly.',
    CareerFailure.invalidResponse ||
    CareerFailure.unavailable ||
    CareerFailure.dayContextRevisionConflict ||
    CareerFailure.timeZoneChangeTooSoon ||
    CareerFailure.revisionExhausted ||
    CareerFailure.rejected =>
      'Trade confirmed. Your reason was not saved. Try again.',
  };

  String _failureMessage(PaperOrderFailure failure) => switch (failure) {
    PaperOrderFailure.invalidAmount => 'Enter an amount above zero.',
    PaperOrderFailure.insufficientPaper =>
      'There is not enough paper for this order.',
    PaperOrderFailure.insufficientShares =>
      'There are not enough shares to sell.',
    PaperOrderFailure.quoteExpired => 'That price expired. Check a new quote.',
    PaperOrderFailure.priceChanged => 'The price moved. Check the new quote.',
    PaperOrderFailure.offline =>
      'You are offline. Check your connection and try again.',
    PaperOrderFailure.timeout => 'That took too long. Try again.',
    PaperOrderFailure.accountRequired =>
      'Save your desk before placing this order.',
    PaperOrderFailure.duplicate =>
      'This order was already received. Refresh your desk.',
    PaperOrderFailure.rejected => 'The order was not accepted.',
    PaperOrderFailure.unavailable => 'The order did not go through. Try again.',
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
    final title = switch (_step) {
      _OrderStep.amount => '$_verb ${widget.company.symbol}',
      _OrderStep.review => 'Review your ${_verb.toLowerCase()}',
      _OrderStep.report => 'Trade confirmed',
    };
    return PopScope(
      canPop: !_busy && !_savingReason,
      child: Scaffold(
        backgroundColor: MarketPalette.paper,
        appBar: AppBar(
          backgroundColor: MarketPalette.paper,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: _step == _OrderStep.report ? 'Close' : 'Back',
            onPressed: _busy || _savingReason ? null : _back,
            icon: Icon(
              _step == _OrderStep.report
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
            ),
          ),
          title: Text(
            title,
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
                            label: 'Swipe down to edit your buy',
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
                            tooltip: 'Skip first trade',
                            onPressed: _busy ? null : widget.onExitFirstTrade,
                            icon: const Icon(Icons.close_rounded, size: 29),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Review your buy.',
                    style: TextStyle(
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
                            label: 'Shares',
                            value: Text(quote.estimatedShares),
                          ),
                          const SizedBox(height: 14),
                          _DetailRow(
                            label: 'Price per share',
                            value: PaperAmount(quote.unitPricePaper),
                          ),
                          const SizedBox(height: 14),
                          _DetailRow(
                            label: 'Fee',
                            value: PaperAmount(quote.feePaper),
                          ),
                        ],
                      ),
                      lower: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total'),
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
                              ? 'Confirming buy…'
                              : 'Checking price…')
                        : _step == _OrderStep.amount
                        ? 'Try again'
                        : 'Confirm buy',
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

  Widget _amountScreen() => Column(
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
                        label:
                            '${_displayInput()} ${_unit == PaperQuantityUnit.paper ? 'paper' : 'shares'}',
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _displayInput(),
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
                        _equivalent,
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
                      _presets(),
                    ],
                  ),
                  Column(
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        widget.side == PaperOrderSide.sell
                            ? '${_trimDecimal(widget.availableShares)} shares available'
                            : '${formatPaperForDisplay(widget.availablePaper)} paper available',
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
              label: 'Continue',
              color: MarketPalette.violet,
              onPressed: _busy ? null : _requestQuote,
              busy: _busy,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _presets() {
    final selling = widget.side == PaperOrderSide.sell;
    final presets = selling
        ? <(String, String)>[
            ('25%', OrderAmountMath.portion(widget.availableShares, 25)),
            ('50%', OrderAmountMath.portion(widget.availableShares, 50)),
            ('75%', OrderAmountMath.portion(widget.availableShares, 75)),
            ('Max', widget.availableShares),
          ]
        : _unit == PaperQuantityUnit.paper
        ? <(String, String)>[
            ('100', '100'),
            ('500', '500'),
            ('1,000', '1000'),
            ('Max', _maxValue()),
          ]
        : <(String, String)>[
            ('1', '1'),
            ('5', '5'),
            ('10', '10'),
            ('Max', _maxValue()),
          ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final preset in presets)
          ActionChip(
            key: ValueKey('paper-preset-${preset.$1}'),
            label: Text(preset.$1),
            onPressed: _busy
                ? null
                : () {
                    if (ReviewFeedback.shared.haptics) {
                      HapticFeedback.selectionClick();
                    }
                    // Percentages and Max always sell exact shares, never a rounded
                    // cash equivalent that can oversell or leave fractional dust.
                    if (selling) _unit = PaperQuantityUnit.shares;
                    _setPreset(preset.$2);
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
                      '${widget.side == PaperOrderSide.buy ? 'Buying' : 'Selling'} ${quote.estimatedShares} shares',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _DetailRow(
                      label: 'Price per share',
                      value: PaperAmount(quote.unitPricePaper),
                    ),
                    const SizedBox(height: 20),
                    _DetailRow(
                      label: 'Fee',
                      value: PaperAmount(quote.feePaper),
                    ),
                  ],
                ),
                lower: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.side == PaperOrderSide.buy
                          ? 'You pay'
                          : 'You receive',
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
                label: 'Confirm ${_verb.toLowerCase()}',
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
    return ListView(
      key: const ValueKey('paper-order-report'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Semantics(
          liveRegion: true,
          label: widget.side == PaperOrderSide.buy
              ? 'Buy confirmed'
              : 'Sale confirmed',
          child: const Center(child: ProductSuccessMark(size: 66)),
        ),
        const SizedBox(height: 12),
        Text(
          widget.side == PaperOrderSide.buy
              ? '${widget.company.symbol} is on your desk.'
              : receipt.positionShares == '0'
              ? '${widget.company.symbol} left your desk.'
              : 'Your ${widget.company.symbol} position changed.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.side == PaperOrderSide.buy ? 'Bought' : 'Sold'} ${receipt.filledShares} shares',
          textAlign: TextAlign.center,
          style: const TextStyle(color: MarketPalette.muted),
        ),
        const SizedBox(height: 20),
        MarketPanel(
          color: const Color(0xFFF3EFFB),
          child: Column(
            children: [
              _DetailRow(
                label: 'Your position',
                value: Text('${receipt.positionShares} shares'),
                strong: true,
              ),
              const SizedBox(height: 22),
              _DetailRow(
                label: 'Position value',
                value: PaperAmount(receipt.positionValuePaper),
              ),
              if (receipt.trimsEarned > 0) ...[
                const SizedBox(height: 22),
                _DetailRow(
                  label: 'Trims earned',
                  value: Text('+${receipt.trimsEarned}'),
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
                labelText: 'Why did you buy?',
                hintText: 'One clear line',
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
              label: _pendingReason == null ? 'Save reason' : 'Retry reason',
              onPressed: _savingReason ? null : _saveReason,
              busy: _savingReason,
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const ValueKey('paper-order-skip-reason'),
              onPressed: _savingReason
                  ? null
                  : () => Navigator.of(context).pop(receipt),
              child: const Text('Skip'),
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
                        ? '+${savedReason.trimsAwarded} Trims'
                        : 'Reason saved',
                    key: const ValueKey('paper-order-reason-reward'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '“${savedReason.note}”',
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
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(receipt),
            ),
          ],
        ] else ...[
          if (receipt.side == PaperOrderSide.buy) ...[
            const Text(
              'Your trade is confirmed. Saving a reason is unavailable right now.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MarketPalette.muted),
            ),
            const SizedBox(height: 14),
          ],
          MarketPrimaryButton(
            color: MarketPalette.violet,
            key: const ValueKey('paper-order-done'),
            label: 'Done',
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
    label: 'Order amount unit',
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
                      child: Text(
                        unit == PaperQuantityUnit.paper ? 'Paper' : 'Shares',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
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
              ? 'Delete'
              : key == '.'
              ? 'Decimal point'
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
                        key,
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
