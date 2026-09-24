import 'package:flutter/material.dart';

import 'review_components.dart';
import 'review_feedback.dart';
import 'review_first_play.dart';
import 'review_followup_questions.dart';
import 'ui_review_app.dart';

/// A desk built from the completed practice session, with optional next steps.
class ReviewFirstDeskPage extends StatefulWidget {
  const ReviewFirstDeskPage({
    super.key,
    required this.position,
    required this.onSaveProgress,
    required this.onReminder,
    required this.onWidget,
    required this.onPersona,
    required this.onExplore,
    required this.onStartPractice,
    required this.onOpenCareer,
    this.persona = 'oracle',
    this.username,
    this.initialReason = '',
    this.onReasonChanged,
  });

  final ReviewPracticePosition? position;
  final String persona;
  final String? username;
  final String initialReason;
  final ValueChanged<String>? onReasonChanged;
  final VoidCallback onSaveProgress,
      onReminder,
      onWidget,
      onPersona,
      onExplore,
      onStartPractice,
      onOpenCareer;

  @override
  State<ReviewFirstDeskPage> createState() => _ReviewFirstDeskPageState();
}

class _ReviewFirstDeskPageState extends State<ReviewFirstDeskPage> {
  late final TextEditingController _reasonController;
  late String _savedReason;
  late bool _editingReason;

  @override
  void initState() {
    super.initState();
    _savedReason = widget.initialReason.trim();
    _reasonController = TextEditingController(text: _savedReason);
    _editingReason = _savedReason.isEmpty;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _saveReason() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _savedReason = reason;
      _editingReason = false;
    });
    widget.onReasonChanged?.call(reason);
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.position;
    final persona = reviewPersonas.firstWhere(
      (entry) => entry.$1 == widget.persona,
      orElse: () => reviewPersonas[1],
    );
    final username = widget.username?.trim() ?? '';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your desk.',
                          style: TextStyle(
                            fontFamily: reviewDisplay,
                            color: UiReviewColor.ink,
                            fontSize: 35,
                            height: 1.05,
                            letterSpacing: -1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          username.isEmpty ? persona.$2 : '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _bodyStyle.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Semantics(
                    button: true,
                    label: 'Change persona. ${persona.$2} selected.',
                    child: Tooltip(
                      message: 'Change persona',
                      child: Material(
                        color: const Color(0xFFF0EDFF),
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            ReviewFeedback.shared.press();
                            widget.onPersona();
                          },
                          child: ExcludeSemantics(
                            child: SizedBox(
                              width: 62,
                              height: 62,
                              child: Image.asset(
                                'assets/images/ui_review/persona-${persona.$1}-avatar-v1.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              if (position != null) ...[
                _PracticePositionPanel(position: position),
                const SizedBox(height: 25),
                _reasonSection(position),
                const SizedBox(height: 13),
                if (_editingReason)
                  _DeskAction(
                    title: 'Explore stocks',
                    icon: Icons.search_rounded,
                    onTap: widget.onExplore,
                  )
                else
                  ReviewPrimaryButton(
                    background: UiReviewColor.violet,
                    label: 'Explore stocks',
                    onPressed: widget.onExplore,
                  ),
              ] else ...[
                const _DeskPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReviewSal(mood: 'teaching', width: 95),
                      SizedBox(height: 12),
                      Text(
                        'Your first trade is waiting.',
                        style: _sectionStyle,
                      ),
                      SizedBox(height: 9),
                      Text(
                        'Come back whenever you’re ready.',
                        style: _bodyStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ReviewPrimaryButton(
                  background: UiReviewColor.violet,
                  label: 'Try a trade',
                  onPressed: widget.onStartPractice,
                ),
              ],
              if (position == null)
                _DeskAction(
                  title: 'Browse stocks',
                  icon: Icons.search_rounded,
                  onTap: widget.onExplore,
                ),
              _DeskAction(
                title: 'Explore your career',
                icon: Icons.route_rounded,
                onTap: widget.onOpenCareer,
              ),
              const SizedBox(height: 29),
              const Text('Make it yours', style: _sectionStyle),
              const SizedBox(height: 6),
              const Text('Whenever you’re ready.', style: _bodyStyle),
              const SizedBox(height: 10),
              _DeskAction(
                title: 'Save progress',
                caption: 'Add a username and see sign-in options.',
                icon: Icons.bookmark_border_rounded,
                onTap: widget.onSaveProgress,
              ),
              _DeskAction(
                title: 'Remind me',
                caption: 'A nudge to come back.',
                icon: Icons.notifications_none_rounded,
                onTap: widget.onReminder,
              ),
              _DeskAction(
                title: 'Home screen widget',
                caption: 'Preview your desk at a glance.',
                icon: Icons.widgets_outlined,
                onTap: widget.onWidget,
              ),
              const SizedBox(height: 18),
              const Text(
                'Practice desk · No real money',
                style: TextStyle(
                  fontFamily: 'Dejanire Sans',
                  color: Color(0xFF797585),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reasonSection(ReviewPracticePosition position) => _DeskPanel(
    color: const Color(0xFFF4F1FF),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Why this company?', style: _sectionStyle),
                  const SizedBox(height: 7),
                  Text(
                    _editingReason
                        ? 'What made ${position.company} your pick? One sentence is enough.'
                        : 'Your reason for choosing ${position.company}.',
                    style: _bodyStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const ReviewSal(mood: 'teaching', width: 66),
          ],
        ),
        const SizedBox(height: 17),
        if (_editingReason) ...[
          TextField(
            controller: _reasonController,
            onChanged: (_) => setState(() {}),
            minLines: 2,
            maxLines: 4,
            maxLength: 180,
            textCapitalization: TextCapitalization.sentences,
            style: _bodyStyle.copyWith(color: UiReviewColor.ink, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'I picked ${position.company} because…',
              hintStyle: _bodyStyle,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(19),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(19),
                borderSide: const BorderSide(color: UiReviewColor.violet),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ReviewPrimaryButton(
            background: UiReviewColor.violet,
            label: _savedReason.isEmpty ? 'Save my reason' : 'Save changes',
            icon: Icons.check_rounded,
            onPressed: _reasonController.text.trim().isEmpty
                ? null
                : _saveReason,
          ),
          if (_savedReason.isNotEmpty)
            Center(
              child: ReviewTextButton(
                label: 'Cancel',
                onPressed: () {
                  _reasonController.text = _savedReason;
                  FocusScope.of(context).unfocus();
                  setState(() => _editingReason = false);
                },
              ),
            ),
        ] else ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _savedReason,
              style: _bodyStyle.copyWith(
                color: UiReviewColor.ink,
                fontSize: 16,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 16,
                color: UiReviewColor.pine,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Saved for this session',
                  style: TextStyle(
                    fontFamily: 'Dejanire Sans',
                    fontSize: 12,
                    color: UiReviewColor.pine,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ReviewTextButton(
                label: 'Edit',
                onPressed: () {
                  ReviewFeedback.shared.press();
                  setState(() => _editingReason = true);
                },
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

const _sectionStyle = TextStyle(
  fontFamily: 'Dejanire Sans',
  color: UiReviewColor.ink,
  fontSize: 20,
  height: 1.15,
  fontWeight: FontWeight.w700,
  letterSpacing: -.3,
);

const _bodyStyle = TextStyle(
  fontFamily: 'Dejanire Sans',
  color: Color(0xFF6F687B),
  fontSize: 14,
  height: 1.4,
);

class _PracticePositionPanel extends StatelessWidget {
  const _PracticePositionPanel({required this.position});

  final ReviewPracticePosition position;

  @override
  Widget build(BuildContext context) => _DeskPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('YOUR PRACTICE POSITION', style: _labelStyle),
        const SizedBox(height: 15),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(position.company, style: _sectionStyle),
                  const SizedBox(height: 5),
                  Text(position.symbol, style: _bodyStyle),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${reviewCount(position.amount, decimals: 2)}',
                  style: _sectionStyle.copyWith(fontSize: 25),
                ),
                const SizedBox(height: 5),
                const Text('Practice buy', style: _bodyStyle),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${reviewCount(position.shares, decimals: 4)} shares · '
          '\$${reviewCount(position.price, decimals: 2)} per share',
          style: _bodyStyle.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 19),
        const Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _DeskMilestone(icon: Icons.stars_rounded, label: '20 Trims'),
            _DeskMilestone(
              icon: Icons.check_circle_rounded,
              label: 'Day 1 complete',
            ),
          ],
        ),
      ],
    ),
  );
}

const _labelStyle = TextStyle(
  fontFamily: 'Dejanire Sans',
  color: Color(0xFF797585),
  fontSize: 10,
  letterSpacing: 1,
  fontWeight: FontWeight.w700,
);

class _DeskMilestone extends StatelessWidget {
  const _DeskMilestone({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: UiReviewColor.pine),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          fontFamily: 'Dejanire Sans',
          color: UiReviewColor.pine,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _DeskPanel extends StatelessWidget {
  const _DeskPanel({required this.child, this.color = const Color(0xFFF7F8FA)});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(27)),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(19), child: child),
  );
}

class _DeskAction extends StatelessWidget {
  const _DeskAction({
    required this.title,
    required this.icon,
    required this.onTap,
    this.caption,
  });

  final String title;
  final String? caption;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(18)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () {
        ReviewFeedback.shared.press();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
        child: Row(
          children: [
            Icon(icon, size: 22, color: UiReviewColor.ink),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: _bodyStyle.copyWith(
                      color: UiReviewColor.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 3),
                    Text(caption!, style: _bodyStyle.copyWith(fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF797585),
            ),
          ],
        ),
      ),
    ),
  );
}
