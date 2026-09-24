import 'package:flutter/material.dart';

import 'review_components.dart';
import 'review_amount_picker.dart';
import 'review_spotlight.dart';
import 'review_stock_coin.dart';
import 'review_trade_ticket.dart';
import 'review_feedback.dart';
import 'ui_review_app.dart';

/// An offline practice holding. Prices are fixed examples, never live quotes.
@immutable
class ReviewPracticePosition {
  const ReviewPracticePosition({
    required this.company,
    required this.symbol,
    required this.price,
    required this.amount,
  }) : assert(price > 0),
       assert(amount > 0);

  final String company, symbol;
  final double price, amount;

  double get shares => amount / price;

  static const example = ReviewPracticePosition(
    company: 'Apple',
    symbol: 'AAPL',
    price: 200,
    amount: 100,
  );
}

// Deliberately round sample prices keep the first decision easy to understand.
// These are local teaching examples, not market data or recommendations.
const _practiceCompanies = [
  ReviewPracticePosition.example,
  ReviewPracticePosition(
    company: 'Nvidia',
    symbol: 'NVDA',
    price: 125,
    amount: 100,
  ),
  ReviewPracticePosition(
    company: 'Microsoft',
    symbol: 'MSFT',
    price: 400,
    amount: 100,
  ),
];

const _softInk = Color(0xFF696373);
const _softSurface = Color(0xFFF6F5F8);

class ReviewFirstPlayPage extends StatefulWidget {
  const ReviewFirstPlayPage({
    super.key,
    required this.onExit,
    required this.onComplete,
    this.initialPosition,
  });

  final VoidCallback onExit;
  final ValueChanged<ReviewPracticePosition> onComplete;
  final ReviewPracticePosition? initialPosition;

  @override
  State<ReviewFirstPlayPage> createState() => _ReviewFirstPlayPageState();
}

class _ReviewFirstPlayPageState extends State<ReviewFirstPlayPage> {
  int _companyIndex = -1;
  double _amount = 100;
  bool _showGuidance = true;
  bool _validAmount = true;
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _companyKey = GlobalKey();
  final _amountKey = GlobalKey();
  final _reviewKey = GlobalKey();
  bool _reviewOpen = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPosition;
    if (initial != null) {
      final index = _practiceCompanies.indexWhere(
        (company) => company.symbol == initial.symbol,
      );
      if (index >= 0) _companyIndex = index;
      _amount = initial.amount;
      _showGuidance = false;
    }
  }

  ReviewPracticePosition get _position {
    final company = _practiceCompanies[_companyIndex < 0 ? 0 : _companyIndex];
    return ReviewPracticePosition(
      company: company.company,
      symbol: company.symbol,
      price: company.price,
      amount: _amount,
    );
  }

  void _select(VoidCallback update) {
    ReviewFeedback.shared.press(selection: true);
    setState(update);
  }

  Future<void> _reviewBuy() async {
    if (_completed || _reviewOpen || _companyIndex < 0 || !_validAmount) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _showGuidance = false);
    _reviewOpen = true;
    final position = _position;
    final outcome = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
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
      builder: (sheetContext) => _PracticeBuyReview(
        position: position,
        onConfirm: () {
          if (_completed) return;
          _completed = true;
          Navigator.of(sheetContext).pop(true);
        },
        onExit: () => Navigator.of(sheetContext).pop(false),
      ),
    );
    _reviewOpen = false;
    if (!mounted) return;
    if (outcome == true) {
      widget.onComplete(position);
    } else if (outcome == false) {
      widget.onExit();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _chooseCompany(int index) {
    _select(() => _companyIndex = index);
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
    final canReview = !choosingCompany && _validAmount;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 23;
    return Scaffold(
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
          enabled: _showGuidance,
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
                        onPressed: widget.onExit,
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
                                          () => _showGuidance = !_showGuidance,
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
                                if (_showGuidance && choosingCompany)
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
                                              i < _practiceCompanies.length;
                                              i++
                                            ) ...[
                                              if (i > 0)
                                                const SizedBox(height: 8),
                                              _CompanyChoice(
                                                company: _practiceCompanies[i],
                                                selected: i == _companyIndex,
                                                horizontal: true,
                                                onTap: () => _chooseCompany(i),
                                              ),
                                            ],
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            for (
                                              var i = 0;
                                              i < _practiceCompanies.length;
                                              i++
                                            ) ...[
                                              if (i > 0)
                                                const SizedBox(width: 10),
                                              Expanded(
                                                child: _CompanyChoice(
                                                  company:
                                                      _practiceCompanies[i],
                                                  selected: i == _companyIndex,
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
                              enabled: !_showGuidance || !choosingCompany,
                              child: Column(
                                key: _amountKey,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _SectionTitle('Select price'),
                                  if (_showGuidance && !choosingCompany)
                                    const ReviewGuideCue(
                                      key: ValueKey('amount-guide'),
                                      text: 'Pick an amount to try. It’s free.',
                                    ),
                                  const SizedBox(height: 16),
                                  ReviewAmountPicker(
                                    value: _amount,
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
                      enabled: !_showGuidance || !choosingCompany,
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
    );
  }
}

class ReviewFirstDayResultPage extends StatelessWidget {
  const ReviewFirstDayResultPage({
    super.key,
    required this.position,
    required this.onContinue,
  });

  final ReviewPracticePosition position;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => _PracticePage(
    title: 'Your first position.',
    bottom: ReviewPrimaryButton(
      background: UiReviewColor.violet,
      label: 'Go to my desk',
      onPressed: onContinue,
    ),
    children: [
      ReviewTradeTicket(
        upper: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TradeCompanyHeader(position: position, confirmed: true),
            const SizedBox(height: 28),
            const Text(
              'Invested',
              style: TextStyle(color: _softInk, fontSize: 14),
            ),
            const SizedBox(height: 7),
            _TradeTotal(position.amount),
            const SizedBox(height: 28),
            _ReceiptDetail(label: 'Shares', value: _shares(position.shares)),
            const SizedBox(height: 14),
            _ReceiptDetail(
              label: 'Price per share',
              value: _money(position.price),
            ),
          ],
        ),
        lower: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
            return Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Day 1 complete',
                        style: TextStyle(
                          color: UiReviewColor.pine,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '+20 Trims',
                        style: TextStyle(
                          color: UiReviewColor.pine,
                          fontSize: 29,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -.6,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!largeText) ...[
                  const SizedBox(width: 12),
                  const ExcludeSemantics(
                    child: ReviewSal(mood: 'proud', width: 68),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ],
  );
}

class _PracticeBuyReview extends StatelessWidget {
  const _PracticeBuyReview({
    required this.position,
    required this.onConfirm,
    required this.onExit,
  });

  final ReviewPracticePosition position;
  final VoidCallback onConfirm, onExit;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: DefaultTextStyle.merge(
      style: const TextStyle(
        fontFamily: 'Dejanire Sans',
        color: UiReviewColor.ink,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ReviewIconButton(
                        icon: Icons.close_rounded,
                        label: 'Skip first trade',
                        onPressed: onExit,
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
              ReviewTradeTicket(
                upperColor: _softSurface,
                lowerColor: const Color(0xFFF2EEFF),
                upper: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TradeCompanyHeader(position: position),
                    const SizedBox(height: 26),
                    _ReceiptDetail(
                      label: 'Shares',
                      value: _shares(position.shares),
                    ),
                    const SizedBox(height: 14),
                    _ReceiptDetail(
                      label: 'Sample price',
                      value: _money(position.price),
                    ),
                  ],
                ),
                lower: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(color: _softInk, fontSize: 14),
                    ),
                    const SizedBox(height: 7),
                    _TradeTotal(position.amount),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              ReviewPrimaryButton(
                background: UiReviewColor.violet,
                label: 'Confirm buy',
                onPressed: onConfirm,
                icon: Icons.check_rounded,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TradeCompanyHeader extends StatelessWidget {
  const _TradeCompanyHeader({required this.position, this.confirmed = false});
  final ReviewPracticePosition position;
  final bool confirmed;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ReviewStockCoin(symbol: position.symbol, size: 46),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              position.company,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              position.symbol,
              style: const TextStyle(color: _softInk, fontSize: 13),
            ),
          ],
        ),
      ),
      if (confirmed) ...[
        const SizedBox(width: 10),
        Semantics(
          label: 'Buy confirmed',
          child: const ExcludeSemantics(
            child: Icon(
              Icons.verified_rounded,
              size: 34,
              color: UiReviewColor.pine,
            ),
          ),
        ),
      ],
    ],
  );
}

class _TradeTotal extends StatelessWidget {
  const _TradeTotal(this.amount);
  final double amount;
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(
      _money(amount),
      style: const TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -1,
      ),
    ),
  );
}

class _ReceiptDetail extends StatelessWidget {
  const _ReceiptDetail({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked = MediaQuery.textScalerOf(context).scale(14) > 21;
      final labelText = Text(
        label,
        style: const TextStyle(color: _softInk, fontSize: 14, height: 1.4),
      );
      final valueText = Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [labelText, const SizedBox(height: 2), valueText],
        );
      }
      return Row(
        children: [
          Expanded(child: labelText),
          const SizedBox(width: 12),
          valueText,
        ],
      );
    },
  );
}

class _PracticePage extends StatelessWidget {
  const _PracticePage({
    required this.title,
    required this.children,
    required this.bottom,
  });

  final String title;
  final List<Widget> children;
  final Widget bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: DefaultTextStyle.merge(
      style: const TextStyle(
        fontFamily: 'Dejanire Sans',
        color: UiReviewColor.ink,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 30),
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: reviewDisplay,
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            height: 1.06,
                            letterSpacing: -.9,
                          ),
                        ),
                        const SizedBox(height: 28),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(22, 10, 22, 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: bottom,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CompanyChoice extends StatelessWidget {
  const _CompanyChoice({
    required this.company,
    required this.selected,
    required this.onTap,
    this.horizontal = false,
  });

  final ReviewPracticePosition company;
  final bool selected, horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(22),
    );
    final label = Text(
      company.company,
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
      label: '${company.company}, ${company.symbol}',
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
                          ReviewStockCoin(symbol: company.symbol, size: 42),
                          const SizedBox(width: 14),
                          Expanded(child: label),
                        ],
                      )
                    : Column(
                        children: [
                          ReviewStockCoin(symbol: company.symbol, size: 42),
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

String _money(double value, {bool cents = true}) =>
    '\$${reviewCount(value, decimals: cents ? 2 : 0)}';

String _shares(double value) => value
    .toStringAsFixed(4)
    .replaceFirst(RegExp(r'0+$'), '')
    .replaceFirst(RegExp(r'\.$'), '');
