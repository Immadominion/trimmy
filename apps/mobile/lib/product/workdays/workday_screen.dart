import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';
import '../../ui_review/review_feedback.dart';
import '../design/product_theme.dart';
import 'workdays.dart';

class WorkdayScreen extends StatefulWidget {
  const WorkdayScreen({
    super.key,
    required this.controller,
    required this.assignmentId,
    required this.onCompleted,
  });
  final WorkdayController controller;
  final String assignmentId;
  final Future<void> Function() onCompleted;
  @override
  State<WorkdayScreen> createState() => _WorkdayScreenState();
}

/// Where the optional note's autosave stands.
enum _DraftStatus { none, saving, saved, failed }

class _WorkdayScreenState extends State<WorkdayScreen> {
  late final String _id = widget.assignmentId;
  final _number = TextEditingController(), _note = TextEditingController();
  final _selected = <String>{};
  String? _choice;

  /// The current error, worded at display time so a language change applies.
  String Function(AppLocalizations l10n)? _error;
  int _displayStep = -1;
  bool _busy = false, _hint = false, _sources = false, _canLeave = false;
  Timer? _draftTimer;
  _DraftStatus _draftStatus = _DraftStatus.none;
  WorkAssignment get _work => widget.controller.journey!.find(_id)!;
  @override
  void initState() {
    super.initState();
    _note.text = _work.draft;
    widget.controller.addListener(_changed);
    unawaited(ReviewFeedback.shared.prepareWork());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    widget.controller.removeListener(_changed);
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  void _draftChanged(String text) {
    _draftTimer?.cancel();
    setState(() => _draftStatus = _DraftStatus.saving);
    _draftTimer = Timer(
      const Duration(milliseconds: 650),
      () => unawaited(_saveDraft()),
    );
  }

  Future<bool> _saveDraft() async {
    if (widget.controller.closed) return false;
    final text = _note.text, id = _id;
    try {
      await widget.controller.draft(id, text);
      if (mounted && id == _id && _note.text == text) {
        setState(() => _draftStatus = _DraftStatus.saved);
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => _draftStatus = _DraftStatus.failed);
      return false;
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    _draftTimer?.cancel();
    if (_work.step == 2 && _note.text != _work.draft) {
      setState(() => _busy = true);
      final saved = await _saveDraft();
      if (!mounted) return;
      setState(() => _busy = false);
      if (!saved) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogContext.l10n.workdayLeaveTitle),
            content: Text(dialogContext.l10n.workdayLeaveBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(dialogContext.l10n.workdayLeaveKeepWriting),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(dialogContext.l10n.workdayLeaveWithoutSaving),
              ),
            ],
          ),
        );
        if (leave != true) return;
      }
    }
    if (!mounted) return;
    setState(() => _canLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _submit() async {
    final original = _work;
    final formats = context.formats;
    _draftTimer?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final answer = original.step == 1
          ? <String, dynamic>{
              'value': original.decision['kind'] == 'number'
                  ? _typedNumber(formats, _number.text)
                  : _choice,
            }
          : <String, dynamic>{'ids': _selected.toList()};
      await widget.controller.save(
        original,
        answer,
        draft: original.step == 2 ? _note.text : null,
      );
      if (!mounted) return;
      ReviewFeedback.shared.workCue(
        original.step == 2 ? WorkSound.complete : WorkSound.saved,
      );
      setState(() {
        _selected.clear();
        _choice = null;
        _hint = false;
        _sources = false;
        _number.clear();
      });
      if (original.step == 2) unawaited(widget.onCompleted());
    } on WorkdayException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = (l10n) => l10n.workdaySaveRetry);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(String id) {
    ReviewFeedback.shared.workCue(WorkSound.select);
    setState(() {
      _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      _error = null;
    });
  }

  /// The typed answer in the plain "-1234.5" form the server reads. English
  /// text is sent exactly as typed (trimmed); a comma decimal mark becomes a
  /// point. The sign is kept outside the locale normalizer.
  static String _typedNumber(AppFormats formats, String typed) {
    final text = typed.trim();
    if (!text.startsWith('-')) return formats.normalizeDecimalInput(text);
    return '-${formats.normalizeDecimalInput(text.substring(1))}';
  }

  String _draftLabel(AppLocalizations l10n) => switch (_draftStatus) {
    _DraftStatus.none => '',
    _DraftStatus.saving => l10n.commonSaving,
    _DraftStatus.saved => l10n.workdayDraftSaved,
    _DraftStatus.failed => l10n.workdayDraftNotSaved,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formats = context.formats;
    final work = _work;
    if (_displayStep != work.step) {
      _displayStep = work.step;
      _selected.clear();
      _choice = null;
    }
    final complete = work.complete;
    final theme = Theme.of(context).textTheme;
    final ready = work.step == 1
        ? (work.decision['kind'] == 'number'
              ? _number.text.trim().isNotEmpty
              : _choice != null)
        : _selected.length ==
              (work.step == 0 ? work.evidence['count'] : work.file['count']);
    return PopScope(
      // iOS swipe-back works when nothing is unsaved; an unsaved note still
      // saves first, or asks.
      canPop:
          _canLeave ||
          (!_busy && !(_work.step == 2 && _note.text != _work.draft)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: Text(
            l10n.workdayDayTitle(work.ordinal),
            style: theme.titleMedium,
          ),
          actions: [
            IconButton(
              onPressed: _busy ? null : _leave,
              tooltip: l10n.workdaySaveAndClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (!complete)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: List.generate(
                      3,
                      (i) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 5,
                          decoration: BoxDecoration(
                            color: i <= work.step
                                ? ProductColor.violet
                                : const Color(0xFFF0EDF7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey('$_id-${work.step}'),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (complete) ...[
                        Center(
                          child: Image.asset(
                            'assets/images/career_world/${work.art}.png',
                            width: 136,
                            height: 136,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.workdayFiledTitle,
                          style: theme.headlineLarge,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          work.data['feedback'] as String? ?? '',
                          style: theme.bodyLarge,
                        ),
                        const SizedBox(height: 24),
                        _surface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(work.title, style: theme.titleLarge),
                              const SizedBox(height: 16),
                              Text(
                                work.data['artifact'] as String? ?? '',
                                style: theme.bodyLarge,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                l10n.workdayTrimsEarned(work.trims),
                                style: theme.titleMedium?.copyWith(
                                  color: ProductColor.gain,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.controller.journey?.upcoming
                            case final next?) ...[
                          const SizedBox(height: 24),
                          Text(
                            next.opensLabel(l10n, formats),
                            style: theme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.workdayNextDay(next.ordinal, next.title),
                            style: theme.bodyLarge,
                          ),
                        ],
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(work.title, style: theme.headlineLarge),
                                  const SizedBox(height: 12),
                                  Text(work.brief, style: theme.bodyLarge),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Image.asset(
                              work.portrait,
                              width: 66,
                              height: 84,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),
                        if (work.data['contextNote'] case final String note)
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: _surface(
                              color: ProductColor.mint,
                              child: Text(note, style: theme.bodyLarge),
                            ),
                          ),
                        const SizedBox(height: 24),
                        if (work.step == 0) ...[
                          _pinHeading(
                            Text(
                              work.evidence['prompt'] as String,
                              style: theme.titleLarge,
                            ),
                            work.evidence['count'] as int,
                          ),
                          const SizedBox(height: 16),
                          _sourceLabel(work),
                          for (final row in work.rows)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _source(row, selectable: true),
                            ),
                        ] else ...[
                          InkWell(
                            onTap: () {
                              ReviewFeedback.shared.workCue(WorkSound.paper);
                              setState(() => _sources = !_sources);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.description_outlined,
                                    size: 20,
                                    color: ProductColor.violet,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      work.data['sourceTitle'] as String,
                                      style: theme.titleMedium,
                                    ),
                                  ),
                                  Icon(
                                    _sources
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_sources) ...[
                            _sourceLabel(work),
                            for (final row in work.rows)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _source(row, selectable: false),
                              ),
                            const SizedBox(height: 22),
                          ],
                          const SizedBox(height: 12),
                          if (work.step == 1) ...[
                            Text(
                              work.decision['prompt'] as String,
                              style: theme.headlineMedium,
                            ),
                            const SizedBox(height: 22),
                            if (work.decision['kind'] == 'number')
                              _surface(
                                child: TextField(
                                  controller: _number,
                                  autofocus: false,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                  inputFormatters: [
                                    // Digits, the locale's decimal mark(s)
                                    // and a minus sign, as before.
                                    FilteringTextInputFormatter.allow(
                                      RegExp(
                                        '${formats.decimalInputCharacters.pattern}|-',
                                      ),
                                    ),
                                    LengthLimitingTextInputFormatter(18),
                                  ],
                                  onChanged: (_) =>
                                      setState(() => _error = null),
                                  style: theme.headlineLarge,
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: '0',
                                    prefixText: _unitPrefix(
                                      formats,
                                      work.decision['unit'],
                                    ),
                                    suffixText: _unitSuffix(
                                      formats,
                                      work.decision['unit'],
                                    ),
                                  ),
                                ),
                              )
                            else
                              for (final choice
                                  in work.decision['choices'] as List)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _option(
                                    choice['label'] as String,
                                    selected: _choice == choice['id'],
                                    onTap: () {
                                      ReviewFeedback.shared.workCue(
                                        WorkSound.select,
                                      );
                                      setState(() {
                                        _choice = choice['id'] as String;
                                        _error = null;
                                      });
                                    },
                                  ),
                                ),
                            if (work.misses > 0 || _error != null)
                              TextButton(
                                onPressed: () => setState(() => _hint = !_hint),
                                child: Text(
                                  _hint
                                      ? l10n.workdayHintHide
                                      : l10n.workdayHintShow,
                                ),
                              ),
                            if (_hint)
                              _surface(
                                color: const Color(0xFFFFF4D6),
                                child: Text(
                                  work.decision['hint'] as String,
                                  style: theme.bodyLarge,
                                ),
                              ),
                          ] else ...[
                            _pinHeading(
                              Text(
                                l10n.workdayFileHeading,
                                style: theme.headlineMedium,
                              ),
                              work.file['count'] as int,
                            ),
                            const SizedBox(height: 8),
                            Text(l10n.workdayFileBody, style: theme.bodyMedium),
                            const SizedBox(height: 18),
                            for (final part in _orderedParts(work))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _option(
                                  part['text'] as String,
                                  selected: _selected.contains(part['id']),
                                  onTap: () => _toggle(part['id'] as String),
                                ),
                              ),
                            const SizedBox(height: 12),
                            _surface(
                              child: TextField(
                                controller: _note,
                                minLines: 2,
                                maxLines: 4,
                                maxLength: 280,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onChanged: _draftChanged,
                                // The limit shows only as it comes near.
                                buildCounter:
                                    (
                                      context, {
                                      required currentLength,
                                      required isFocused,
                                      maxLength,
                                    }) =>
                                        maxLength != null &&
                                            currentLength > maxLength - 40
                                        ? Text(
                                            '${formats.integer(currentLength)} / ${formats.integer(maxLength)}',
                                            key: const ValueKey(
                                              'workday-note-count',
                                            ),
                                          )
                                        : null,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: l10n.workdayNoteHint,
                                ),
                              ),
                            ),
                            if (_draftStatus != _DraftStatus.none)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _draftLabel(l10n),
                                  style: theme.bodySmall,
                                ),
                              ),
                          ],
                        ],
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _error!(l10n),
                            style: theme.bodyLarge?.copyWith(
                              color: ProductColor.loss,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ProductColor.violet,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: productSquircle(22),
                    ),
                    onPressed: _busy
                        ? null
                        : complete
                        ? _leave
                        : ready
                        ? _submit
                        : null,
                    child: Text(
                      _busy
                          ? l10n.commonSaving
                          : complete
                          ? l10n.workdayButtonBack
                          : work.step == 0
                          ? l10n.workdayButtonCheckEvidence
                          : work.step == 1
                          ? l10n.workdayButtonSendDecision
                          : l10n.workdayButtonFile,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A dollar decision shows the locale's dollar mark on its usual side
  /// (English stays "\$ " in front). The unit itself comes from the server.
  static String? _unitPrefix(AppFormats formats, Object? unit) {
    if (unit == '\$') {
      return formats.dollarFirst ? '${formats.dollarSymbol} ' : null;
    }
    if (unit == '%' && formats.percentFirst) return '%${formats.percentGap}';
    return null;
  }

  static String? _unitSuffix(AppFormats formats, Object? unit) {
    if (unit == '\$') {
      return formats.dollarFirst ? null : ' ${formats.dollarSymbol}';
    }
    if (unit == '%' && !formats.percentFirst) return '${formats.percentGap}%';
    return null;
  }

  /// The prompt with "1 / 2" beside it, as on the web, so a greyed-out
  /// button explains itself: too few or too many facts are pinned.
  Widget _pinHeading(Widget prompt, int required) {
    final formats = context.formats;
    final over = _selected.length > required;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: prompt),
        const SizedBox(width: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            '${formats.integer(_selected.length)} / ${formats.integer(required)}',
            key: const ValueKey('workday-pin-count'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: over ? ProductColor.loss : ProductColor.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  List<Map> _orderedParts(WorkAssignment work) {
    final parts = List<Map>.from(work.file['parts'] as List);
    final offset = work.ordinal % parts.length;
    return [...parts.skip(offset), ...parts.take(offset)];
  }

  Widget _sourceLabel(WorkAssignment work) => Text(
    '${work.data['sourceTitle']} · ${work.data['sourceLabel']}',
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: ProductColor.muted),
  );
  Widget _source(Map<String, dynamic> row, {required bool selectable}) {
    final selected = selectable && _selected.contains(row['id']);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row['label'] as String,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (selectable) ...[const SizedBox(width: 12), _pin(selected)],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          row['value'] as String,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          row['detail'] as String,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
    if (!selectable) return _surface(child: content);
    return _choiceSurface(
      key: ValueKey('work-evidence-${row['id']}'),
      selected: selected,
      onTap: () => _toggle(row['id'] as String),
      child: content,
    );
  }

  Widget _pin(bool selected) => Icon(
    selected ? Icons.push_pin_rounded : Icons.push_pin_outlined,
    size: 21,
    color: selected ? ProductColor.violet : ProductColor.muted,
  );

  Widget _option(
    String text, {
    required bool selected,
    required VoidCallback onTap,
  }) => _choiceSurface(
    selected: selected,
    onTap: onTap,
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
        const SizedBox(width: 12),
        _pin(selected),
      ],
    ),
  );

  Widget _choiceSurface({
    Key? key,
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) => Semantics(
    key: key,
    selected: selected,
    button: true,
    enabled: !_busy,
    hint: selected
        ? context.l10n.workdayUnpinDetail
        : context.l10n.workdayPinDetail,
    child: AnimatedContainer(
      duration: productDuration(context, 160),
      curve: Curves.easeOutCubic,
      // Match the onboarding stock choices: a 2px rim and a 4px base.
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
      decoration: ShapeDecoration(
        color: selected ? ProductColor.violet : const Color(0xFFE9E6F0),
        shape: productSquircle(24),
      ),
      child: Material(
        color: selected ? const Color(0xFFFAF8FF) : ProductColor.paperRaised,
        shape: productSquircle(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : onTap,
          child: Padding(padding: const EdgeInsets.all(18), child: child),
        ),
      ),
    ),
  );
  Widget _surface({
    required Widget child,
    Color color = ProductColor.paperRaised,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: ShapeDecoration(color: color, shape: productSquircle(26)),
    child: child,
  );
}
