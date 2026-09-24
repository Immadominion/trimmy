import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _WorkdayScreenState extends State<WorkdayScreen> {
  late String _id = widget.assignmentId;
  final _number = TextEditingController(), _note = TextEditingController();
  final _selected = <String>{};
  String? _choice, _error;
  int _displayStep = -1;
  bool _busy = false, _hint = false, _sources = false, _canLeave = false;
  Timer? _draftTimer;
  String _draftStatus = '';
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
    setState(() => _draftStatus = 'Saving…');
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
        setState(() => _draftStatus = 'Saved');
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => _draftStatus = 'Not saved yet');
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
            title: const Text('Leave this note?'),
            content: const Text('Your latest edits haven’t saved yet.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep writing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Leave without saving'),
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
                  ? _number.text.trim()
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
      if (mounted) setState(() => _error = 'Couldn’t save yet. Try again.');
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

  @override
  Widget build(BuildContext context) {
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
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: Text('Day ${work.ordinal}', style: theme.titleMedium),
          actions: [
            IconButton(
              onPressed: _busy ? null : _leave,
              tooltip: 'Save and close',
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
                        Text('Filed.', style: theme.headlineLarge),
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
                                '+20 Trims',
                                style: theme.titleMedium?.copyWith(
                                  color: ProductColor.gain,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                          Text(
                            work.evidence['prompt'] as String,
                            style: theme.titleLarge,
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
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.\-]'),
                                    ),
                                    LengthLimitingTextInputFormatter(18),
                                  ],
                                  onChanged: (_) =>
                                      setState(() => _error = null),
                                  style: theme.headlineLarge,
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: '0',
                                    prefixText: work.decision['unit'] == '\$'
                                        ? '\$ '
                                        : null,
                                    suffixText: work.decision['unit'] == '%'
                                        ? '%'
                                        : null,
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
                            TextButton(
                              onPressed: () => setState(() => _hint = !_hint),
                              child: Text(_hint ? 'Hide hint' : 'Hint?'),
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
                            Text(
                              'Send the desk an update',
                              style: theme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Keep the two facts the source supports.',
                              style: theme.bodyMedium,
                            ),
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
                                onChanged: _draftChanged,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Add a note (optional)',
                                  counterText: '',
                                ),
                              ),
                            ),
                            if (_draftStatus.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _draftStatus,
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
                            _error!,
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
                        ? () {
                            final next = widget.controller.journey?.current;
                            if (next == null) {
                              unawaited(_leave());
                              return;
                            }
                            ReviewFeedback.shared.workCue(WorkSound.paper);
                            setState(() {
                              _id = next.id;
                              _note.text = next.draft;
                              _draftStatus = '';
                              _error = null;
                              _selected.clear();
                              _displayStep = -1;
                            });
                          }
                        : ready
                        ? _submit
                        : null,
                    child: Text(
                      _busy
                          ? 'Saving…'
                          : complete
                          ? (widget.controller.journey?.current == null
                                ? 'Back to the street'
                                : 'Next day')
                          : work.step == 0
                          ? 'Check the evidence'
                          : work.step == 1
                          ? 'Send your decision'
                          : 'File update',
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
    hint: selected ? 'Unpin detail' : 'Pin detail',
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
