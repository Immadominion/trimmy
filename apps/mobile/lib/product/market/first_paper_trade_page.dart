import 'package:flutter/material.dart';

import '../../ui_review/review_amount_picker.dart';
import '../../ui_review/review_components.dart';
import '../../ui_review/review_feedback.dart';
import '../../ui_review/review_spotlight.dart';
import '../../ui_review/review_stock_coin.dart';
import '../../ui_review/review_trade_ticket.dart';
import '../../ui_review/ui_review_app.dart';
import '../design/product_success_mark.dart';
import 'market_craft.dart';
import 'market_models.dart';
import 'paper_order_flow.dart';
import 'paper_order_repository.dart';

const _softSurface = Color(0xFFF6F5F8);

/// The approved first-choice presentation backed by real market identities and
/// the existing server quote/submission flow. Skips never manufacture progress.
class FirstPaperTradePage extends StatefulWidget {
  const FirstPaperTradePage({
    super.key,
    required this.companies,
    required this.repository,
    required this.availablePaper,
    required this.clientOrderId,
    required this.onConfirmed,
    required this.onFinished,
    required this.onExit,
    this.loading = false,
    this.message,
    this.onRetry,
  });

  final List<MarketCompany> companies;
  final PaperOrderRepository? repository;
  final String? availablePaper;
  final String Function() clientOrderId;
  final ValueChanged<PaperOrderReceipt> onConfirmed;
  final Future<void> Function() onFinished, onExit;
  final bool loading;
  final String? message;
  final Future<void> Function()? onRetry;

  @override
  State<FirstPaperTradePage> createState() => _FirstPaperTradePageState();
}

class _FirstPaperTradePageState extends State<FirstPaperTradePage> {
  String? _selectedAssetId;
  int get _companyIndex =>
      _companies.indexWhere((company) => company.assetId == _selectedAssetId);
  double _amount = 100;
  bool _showGuidance = true;
  bool _validAmount = true;
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _companyKey = GlobalKey();
  final _amountKey = GlobalKey();
  final _reviewKey = GlobalKey();
  bool _reviewOpen = false;
  PaperOrderReceipt? _receipt;
  MarketCompany? _confirmedCompany;
  bool _leaving = false;
  String? _exitError;

  List<MarketCompany> get _companies => widget.companies
      .where((company) => company.primaryVariant != null)
      .take(3)
      .toList(growable: false);
  double? get _balance {
    final value = double.tryParse(widget.availablePaper ?? '');
    return value != null && value.isFinite && value >= 1 ? value : null;
  }

  double get _maximum => (_balance ?? 1).clamp(1, 10000).toDouble();
  bool get _ready => widget.repository != null && _balance != null;

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() {
      _leaving = true;
      _exitError = null;
    });
    try {
      await (_receipt == null ? widget.onExit() : widget.onFinished());
    } catch (_) {
      if (mounted) {
        setState(() => _exitError = 'Couldn’t continue. Try again.');
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  void _select(VoidCallback update) {
    ReviewFeedback.shared.press(selection: true);
    setState(update);
  }

  Future<void> _reviewBuy() async {
    if (_receipt != null ||
        _leaving ||
        _reviewOpen ||
        _companyIndex < 0 ||
        !_validAmount ||
        !_ready) {
      return;
    }
    final companies = _companies;
    if (_companyIndex >= companies.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _showGuidance = false);
    _reviewOpen = true;
    final company = companies[_companyIndex];
    final repository = widget.repository!;
    final availablePaper = widget.availablePaper!;
    final amount = _amount.clamp(1, _maximum).toStringAsFixed(2);
    final outcome = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      // The sheet handle dismisses via maybePop so in-flight submissions
      // cannot be dismissed by a drag that bypasses the order PopScope.
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.white,
      barrierColor: UiReviewColor.ink.withValues(alpha: .2),
      sheetAnimationStyle: AnimationStyle(
        duration: uiReviewDuration(context, 240),
        reverseDuration: uiReviewDuration(context, 180),
      ),
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) => PaperOrderFlow(
        company: company,
        side: PaperOrderSide.buy,
        repository: repository,
        clientOrderId: widget.clientOrderId,
        availablePaper: availablePaper,
        availableShares: '0',
        firstTradeAmount: amount,
        reasonCaptureAvailable: false,
        onExitFirstTrade: () => Navigator.of(sheetContext).pop(false),
        onConfirmed: (receipt) => Navigator.of(sheetContext).pop(receipt),
      ),
    );
    _reviewOpen = false;
    if (!mounted) return;
    if (outcome is PaperOrderReceipt) {
      ReviewFeedback.shared.workCue(WorkSound.complete);
      setState(() {
        _receipt = outcome;
        _confirmedCompany = company;
      });
      try {
        widget.onConfirmed(outcome);
      } catch (_) {
        // A host refresh cannot erase the server-confirmed receipt.
      }
    } else if (outcome == false) {
      await _leave();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _chooseCompany(int index) {
    _select(() => _selectedAssetId = _companies[index].assetId);
    if (_showGuidance) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _amountKey.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: .35,
            duration: uiReviewDuration(context, 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  Widget _available({required bool enabled, required Widget child}) =>
      ExcludeFocus(
        excluding: !enabled,
        child: ExcludeSemantics(
          excluding: !enabled,
          child: IgnorePointer(ignoring: !enabled, child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final choosingCompany = _companyIndex < 0;
    final companies = _companies;
    final canReview =
        !choosingCompany &&
        _companyIndex < companies.length &&
        _validAmount &&
        _ready &&
        !_leaving;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 23;
    if (_receipt != null) {
      return _FirstPaperTradeResult(
        company: _confirmedCompany!,
        receipt: _receipt!,
        busy: _leaving,
        message: _exitError,
        onContinue: _leave,
      );
    }
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        // The scroll viewport shrinks above the keyboard; the footer stays in
        // that resized viewport. No second viewInsets padding is added.
        resizeToAvoidBottomInset: true,
        body: DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamily: 'Dejanire Sans',
            color: UiReviewColor.ink,
          ),
          child: ReviewSpotlight(
            enabled: _showGuidance && _ready && companies.isNotEmpty,
            targets: [choosingCompany ? _companyKey : _amountKey],
            fixedTargets: [if (!choosingCompany) _reviewKey],
            scrollController: _scroll,
            viewportKey: _viewportKey,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        child: ReviewIconButton(
                          icon: Icons.close_rounded,
                          label: 'Skip first trade',
                          onPressed: _leave,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: _viewportKey,
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Your first move.',
                                style: TextStyle(
                                  fontFamily: reviewDisplay,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                  height: 1.06,
                                  letterSpacing: -.9,
                                ),
                              ),
                              if (!_ready || companies.isEmpty) ...[
                                const SizedBox(height: 16),
                                Text(
                                  widget.message ??
                                      (widget.loading
                                          ? 'Opening your paper desk…'
                                          : 'Your paper desk is unavailable. Try again.'),
                                ),
                                if (widget.onRetry != null)
                                  TextButton(
                                    onPressed: widget.loading
                                        ? null
                                        : widget.onRetry,
                                    child: const Text('Try again'),
                                  ),
                              ],
                              if (_exitError != null) Text(_exitError!),
                              const SizedBox(height: 28),
                              Column(
                                key: _companyKey,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: _SectionTitle('Pick a company.'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          FocusManager.instance.primaryFocus
                                              ?.unfocus();
                                          _select(
                                            () =>
                                                _showGuidance = !_showGuidance,
                                          );
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              _showGuidance && !choosingCompany
                                              ? UiReviewColor.ink
                                              : UiReviewColor.violet,
                                          minimumSize: const Size(48, 48),
                                          textStyle: const TextStyle(
                                            fontFamily: 'Dejanire Sans',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        child: Semantics(
                                          toggled: _showGuidance,
                                          child: const Text('Hint'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_showGuidance &&
                                      choosingCompany &&
                                      _ready &&
                                      companies.isNotEmpty)
                                    const ReviewGuideCue(
                                      key: ValueKey('company-guide'),
                                      text:
                                          'A share is a small piece of a company. Pick one.',
                                    ),
                                  const SizedBox(height: 8),
                                  _available(
                                    enabled: !_showGuidance || choosingCompany,
                                    child: largeText
                                        ? Column(
                                            children: [
                                              for (
                                                var i = 0;
                                                i < companies.length;
                                                i++
                                              ) ...[
                                                if (i > 0)
                                                  const SizedBox(height: 8),
                                                _CompanyChoice(
                                                  company: companies[i],
                                                  selected: i == _companyIndex,
                                                  horizontal: true,
                                                  onTap: () =>
                                                      _chooseCompany(i),
                                                ),
                                              ],
                                            ],
                                          )
                                        : Row(
                                            children: [
                                              for (
                                                var i = 0;
                                                i < companies.length;
                                                i++
                                              ) ...[
                                                if (i > 0)
                                                  const SizedBox(width: 10),
                                                Expanded(
                                                  child: _CompanyChoice(
                                                    company: companies[i],
                                                    selected:
                                                        i == _companyIndex,
                                                    onTap: () =>
                                                        _chooseCompany(i),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),
                              _available(
                                enabled:
                                    _ready &&
                                    (!_showGuidance || !choosingCompany),
                                child: Column(
                                  key: _amountKey,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const _SectionTitle('Select price'),
                                    if (_showGuidance &&
                                        !choosingCompany &&
                                        _ready)
                                      const ReviewGuideCue(
                                        key: ValueKey('amount-guide'),
                                        text:
                                            'Pick an amount to try. It’s free.',
                                      ),
                                    const SizedBox(height: 16),
                                    ReviewAmountPicker(
                                      value: _amount
                                          .clamp(1, _maximum)
                                          .toDouble(),
                                      max: _maximum,
                                      onChanged: (value) => setState(() {
                                        _validAmount = value != null;
                                        if (value != null) _amount = value;
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: _available(
                        enabled: _ready && (!_showGuidance || !choosingCompany),
                        child: SizedBox(
                          key: _reviewKey,
                          child: ReviewPrimaryButton(
                            background: UiReviewColor.violet,
                            label: 'Review buy',
                            onPressed: canReview ? _reviewBuy : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyChoice extends StatelessWidget {
  const _CompanyChoice({
    required this.company,
    required this.selected,
    required this.onTap,
    this.horizontal = false,
  });

  final MarketCompany company;
  final bool selected, horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(22),
    );
    final label = Text(
      company.name,
      textAlign: horizontal ? TextAlign.start : TextAlign.center,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '${company.name}, ${company.symbol}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: uiReviewDuration(context, 160),
          curve: Curves.easeOutCubic,
          // Inset yields an exact 2px edge and 4px base without nonuniform
          // border/radius rendering artifacts. Outer size stays constant.
          decoration: ShapeDecoration(
            color: selected ? UiReviewColor.violet : _softSurface,
            shape: shape,
          ),
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
          child: Material(
            color: selected ? const Color(0xFFFAF8FF) : _softSurface,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal ? 14 : 4,
                  vertical: 12,
                ),
                child: horizontal
                    ? Row(
                        children: [
                          _CompanyCoin(company: company, size: 42),
                          const SizedBox(width: 14),
                          Expanded(child: label),
                        ],
                      )
                    : Column(
                        children: [
                          _CompanyCoin(company: company, size: 42),
                          const SizedBox(height: 9),
                          label,
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
  );
}

class _CompanyCoin extends StatelessWidget {
  const _CompanyCoin({required this.company, required this.size});
  final MarketCompany company;
  final double size;

  @override
  Widget build(BuildContext context) =>
      const {'AAPL', 'NVDA', 'MSFT', 'TSLA', 'META'}.contains(company.symbol)
      ? ReviewStockCoin(symbol: company.symbol, size: size)
      : SizedBox.square(
          dimension: size,
          child: CompanyLogo(
            name: company.name,
            logoUrl: company.logoUrl,
            color: Colors.white,
          ),
        );
}

class _FirstPaperTradeResult extends StatelessWidget {
  const _FirstPaperTradeResult({
    required this.company,
    required this.receipt,
    required this.busy,
    required this.message,
    required this.onContinue,
  });

  final MarketCompany company;
  final PaperOrderReceipt receipt;
  final bool busy;
  final String? message;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !busy) onContinue();
    },
    child: Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 40, 22, 24),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: .7, end: 1),
                      duration: uiReviewDuration(context, 560),
                      curve: Curves.easeOutBack,
                      builder: (_, value, child) =>
                          Transform.scale(scale: value, child: child),
                      child: const ProductSuccessMark(size: 64),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'You’ve placed your first order!',
                    style: TextStyle(
                      fontFamily: reviewDisplay,
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      height: 1.06,
                      letterSpacing: -.9,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Now let’s create your trader profile.'),
                  const SizedBox(height: 28),
                  ReviewTradeTicket(
                    upper: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _CompanyCoin(company: company, size: 46),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                company.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Semantics(
                              label: 'Buy confirmed',
                              child: const ProductSuccessMark(size: 34),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        const Text('Invested'),
                        const SizedBox(height: 7),
                        PaperAmount(
                          receipt.filledPaper,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text('Shares  ${receipt.filledShares}'),
                      ],
                    ),
                    lower: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Buy confirmed',
                          style: TextStyle(color: UiReviewColor.pine),
                        ),
                        if (receipt.trimsEarned > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            '+${receipt.trimsEarned} Trims',
                            style: const TextStyle(
                              color: UiReviewColor.pine,
                              fontSize: 29,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (receipt.missionProgress != null) ...[
                          const SizedBox(height: 8),
                          Text(receipt.missionProgress!),
                        ],
                      ],
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 16),
                    Text(message!),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
              child: ReviewPrimaryButton(
                background: UiReviewColor.violet,
                label: 'Continue',
                onPressed: busy ? null : onContinue,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
