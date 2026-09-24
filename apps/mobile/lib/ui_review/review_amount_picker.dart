import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'review_feedback.dart';
import 'ui_review_app.dart';

/// A spend amount, with quick choices and a native decimal editor.
///
/// [value] is the last valid amount and must stay within [min] and [max].
/// Invalid drafts emit null. The caller retains its last numeric [value] while
/// disabling its next action, so clearing the field can never submit old money.
class ReviewAmountPicker extends StatefulWidget {
  const ReviewAmountPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 10000,
    this.onEditingChanged,
  }) : assert(min > 0),
       assert(max >= min),
       assert(max < double.infinity),
       assert(value >= min && value <= max);

  final double value, min, max;
  final ValueChanged<double?> onChanged;
  final ValueChanged<bool>? onEditingChanged;

  @override
  State<ReviewAmountPicker> createState() => _ReviewAmountPickerState();
}

class _ReviewAmountPickerState extends State<ReviewAmountPicker> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  bool _editing = false;
  bool _draftEdited = false;
  late double _increment;
  String? _error;
  double? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _inputText(widget.value));
    _increment = widget.value;
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant ReviewAmountPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent echoing a valid keystroke must not move the caret or drop a dot.
    if (widget.value != oldWidget.value && widget.value != _lastEmitted) {
      _controller.text = _inputText(widget.value);
      _error = _validation(_controller.text);
      _increment = widget.value;
      _draftEdited = false;
    }
  }

  void _focusChanged() {
    widget.onEditingChanged?.call(_focus.hasFocus);
    if (!_focus.hasFocus && _editing && _error == null && mounted) {
      _finishEditing();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  static String _inputText(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

  double? _parse(String text) => double.tryParse(text.replaceAll(',', '.'));

  String? _validation(String text) {
    final amount = _parse(text);
    if (amount == null || !amount.isFinite) return 'Enter an amount.';
    if (!RegExp(r'^(?:\d{1,7}([.,]\d{0,2})?|[.,]\d{1,2})$').hasMatch(text)) {
      return 'Use up to 2 decimal places.';
    }
    if (amount < widget.min) {
      return 'Choose at least \$${_inputText(widget.min)}.';
    }
    if (amount > widget.max) {
      return 'Choose up to \$${_inputText(widget.max)}.';
    }
    return null;
  }

  void _draftChanged(String text) {
    final error = _validation(text);
    final amount = error == null ? _parse(text) : null;
    setState(() {
      _error = error;
      _draftEdited = true;
    });
    _lastEmitted = amount;
    widget.onChanged(amount);
  }

  void _edit() {
    ReviewFeedback.shared.impact(selection: true);
    setState(() {
      _editing = true;
      _draftEdited = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing) return;
      _focus.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  // A valid manual draft becomes the next increment only when committed, or
  // when +/- is explicitly tapped. Merely focusing the editor changes nothing.
  double get _effectiveIncrement => _editing && _draftEdited && _error == null
      ? _parse(_controller.text)!
      : _increment;

  void _finishEditing() {
    if (_error != null) return;
    setState(() {
      _increment = _effectiveIncrement;
      _draftEdited = false;
      _editing = false;
    });
  }

  void _choose(double amount, {bool resetIncrement = true}) {
    final next = (amount * 100).round() / 100;
    ReviewFeedback.shared.press(selection: true);
    setState(() {
      if (resetIncrement) _increment = next;
      _editing = false;
      _draftEdited = false;
      _error = null;
      _controller.text = _inputText(next);
    });
    _focus.unfocus();
    _lastEmitted = next;
    widget.onChanged(next);
  }

  void _step(int direction) {
    // Keep the increment independent of the running amount: 50, 100, 150.
    // Invalid drafts retain the previous increment and can still be repaired
    // by a quick control, with every result clamped to the allowed bounds.
    final draft = _parse(_controller.text);
    final base = draft != null && draft.isFinite ? draft : widget.value;
    _increment = _effectiveIncrement;
    _choose(
      (base + direction * _increment).clamp(widget.min, widget.max).toDouble(),
      resetIncrement: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final effective = _error == null ? widget.value : null;
    final presets = [
      25.0,
      50.0,
      100.0,
    ].where((amount) => amount >= widget.min && amount <= widget.max).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: ShapeDecoration(
            color: const Color(0xFFF4F3F7),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: largeText
              ? Column(
                  children: [
                    _amount(context),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _stepButton(-1, effective),
                        if (_editing) _doneButton(),
                        _stepButton(1, effective),
                      ],
                    ),
                  ],
                )
              : Column(
                  children: [
                    Row(
                      children: [
                        _stepButton(-1, effective),
                        Expanded(child: _amount(context)),
                        _stepButton(1, effective),
                      ],
                    ),
                    if (_editing)
                      Align(
                        alignment: Alignment.centerRight,
                        child: _doneButton(),
                      ),
                  ],
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFF9F344E),
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ),
          ),
        if (presets.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final amount in presets) _preset(amount, effective),
            ],
          ),
        ],
      ],
    );
  }

  Widget _doneButton() => TextButton(
    onPressed: () {
      _focus.unfocus();
      _finishEditing();
    },
    style: TextButton.styleFrom(
      foregroundColor: UiReviewColor.violet,
      minimumSize: const Size(64, 48),
    ),
    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
  );

  Widget _amount(BuildContext context) {
    const style = TextStyle(
      fontFamily: 'Dejanire Sans',
      fontSize: 36,
      height: 1.2,
      letterSpacing: -1.4,
      color: UiReviewColor.ink,
      fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    if (_editing) {
      return TextField(
        key: const ValueKey('review-amount-input'),
        controller: _controller,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        textAlign: TextAlign.center,
        style: style,
        cursorColor: UiReviewColor.violet,
        inputFormatters: [_DecimalAmountFormatter()],
        onChanged: _draftChanged,
        onSubmitted: (_) => _focus.unfocus(),
        onTapOutside: (_) => _focus.unfocus(),
        scrollPadding: const EdgeInsets.fromLTRB(24, 40, 24, 130),
        decoration: const InputDecoration(
          labelText: 'Amount in dollars',
          floatingLabelBehavior: FloatingLabelBehavior.never,
          prefixText: '\$',
          prefixStyle: TextStyle(color: Color(0xFF98929F), fontSize: 26),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Amount, ${widget.value.toStringAsFixed(2)} dollars. Edit amount',
      onTap: _edit,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('review-amount-edit'),
          onTap: _edit,
          borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '\$',
                        style: style.copyWith(color: const Color(0xFF98929F)),
                      ),
                      const SizedBox(width: 5),
                      _RollingAmount(value: widget.value, style: style),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepButton(int direction, double? effective) {
    final enabled =
        effective == null ||
        (direction < 0 ? effective > widget.min : effective < widget.max);
    return IconButton(
      tooltip: direction < 0
          ? 'Decrease amount by ${_inputText(_effectiveIncrement)} dollars'
          : 'Increase amount by ${_inputText(_effectiveIncrement)} dollars',
      onPressed: enabled ? () => _step(direction) : null,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      color: UiReviewColor.violet,
      disabledColor: const Color(0xFFC8C3D0),
      iconSize: 25,
      icon: Icon(direction < 0 ? Icons.remove_rounded : Icons.add_rounded),
    );
  }

  Widget _preset(double amount, double? effective) {
    final selected = effective != null && _effectiveIncrement == amount;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Set amount to ${amount.toStringAsFixed(0)} dollars',
      onTap: () => _choose(amount),
      excludeSemantics: true,
      child: Material(
        color: selected ? UiReviewColor.lilac : const Color(0xFFF6F5F8),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _choose(amount),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                '\$${amount.toStringAsFixed(0)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Dejanire Sans',
                  color: selected
                      ? UiReviewColor.violet
                      : const Color(0xFF696373),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DecimalAmountFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,7}([.,]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    return _pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// Each changed digit rolls once; unchanged digits and decimal stay still.
/// Text editing deliberately uses the ordinary native caret without animation.
class _RollingAmount extends StatefulWidget {
  const _RollingAmount({required this.value, required this.style});
  final double value;
  final TextStyle style;

  @override
  State<_RollingAmount> createState() => _RollingAmountState();
}

class _RollingAmountState extends State<_RollingAmount> {
  double _direction = 1;

  @override
  void didUpdateWidget(covariant _RollingAmount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _direction = widget.value > oldWidget.value ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final number = widget.value.toStringAsFixed(2);
    final duration = uiReviewDuration(context, 260);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < number.length; i++)
          _digit(number[i], number.length - i, duration),
      ],
    );
  }

  Widget _digit(String character, int place, Duration duration) => ClipRect(
    key: ValueKey('amount-place-$place'),
    child: AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        // Capture this digit, never a mutable index into a changing amount.
        final arriving = child.key == ValueKey(character);
        final offset = Tween<Offset>(
          begin: Offset(0, arriving ? _direction * .6 : -_direction * .6),
          end: Offset.zero,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: animation.drive(offset),
            child: child,
          ),
        );
      },
      child: Text(character, key: ValueKey(character), style: widget.style),
    ),
  );
}
