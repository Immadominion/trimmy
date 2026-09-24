import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'review_components.dart';
import 'ui_review_app.dart';

class ReviewQuestionFrame extends StatelessWidget {
  const ReviewQuestionFrame({
    super.key,
    this.step,
    required this.title,
    required this.onSkip,
    required this.onContinue,
    required this.child,
    this.caption,
    this.salMood,
    this.skipLabel = 'Skip questions',
    this.continueLabel = 'Continue',
    this.secondaryLabel,
  });

  final int? step;
  final String skipLabel, continueLabel;
  final String? secondaryLabel;
  final String title;
  final String? caption, salMood;
  final VoidCallback onSkip;
  final VoidCallback? onContinue;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: onSkip,
                        tooltip: skipLabel,
                        icon: const Icon(Icons.close_rounded, size: 27),
                        color: UiReviewColor.ink,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                      ),
                      const Spacer(),
                      if (step != null) ...[
                        Text(
                          '$step',
                          style: const TextStyle(
                            fontFamily: 'Dejanire Sans',
                            color: UiReviewColor.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 9),
                        SizedBox(
                          width: 67,
                          child: ReviewProgress(value: step! / 4),
                        ),
                        const SizedBox(width: 9),
                        const Text(
                          '4',
                          style: TextStyle(
                            fontFamily: 'Dejanire Sans',
                            color: Color(0xFF898592),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Dejanire Sans',
                      color: UiReviewColor.ink,
                      fontSize: 32,
                      height: 1.08,
                      letterSpacing: -.7,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 21),
                    if (salMood == null)
                      Text(
                        caption!,
                        style: const TextStyle(
                          fontFamily: 'Dejanire Sans',
                          color: Color(0xFF666172),
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      Row(
                        children: [
                          ReviewSal(mood: salMood!, width: 54),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              caption!,
                              style: const TextStyle(
                                fontFamily: 'Dejanire Sans',
                                color: Color(0xFF666172),
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 25),
                  child,
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(22, 9, 22, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReviewPrimaryButton(
                  label: continueLabel,
                  background: UiReviewColor.violet,
                  onPressed: onContinue,
                ),
                if (secondaryLabel != null)
                  ReviewTextButton(label: secondaryLabel!, onPressed: onSkip),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ReviewAnswerRow extends StatelessWidget {
  const ReviewAnswerRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.number,
    required this.selected,
    required this.onTap,
    this.minHeight = 78,
  });

  final String title, subtitle, number;
  final bool selected;
  final VoidCallback onTap;
  final double minHeight;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? const Color(0xFFF0EDFF) : const Color(0xFFF7F8FA),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      animationDuration: uiReviewDuration(context, 180),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Dejanire Sans',
                      color: UiReviewColor.violet,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Dejanire Sans',
                          color: UiReviewColor.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Dejanire Sans',
                          color: Color(0xFF797585),
                          fontSize: 12.5,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_rounded,
                    size: 23,
                    color: UiReviewColor.violet,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ReviewKnowledgeQuestion extends StatefulWidget {
  const ReviewKnowledgeQuestion({
    super.key,
    required this.onSkip,
    required this.onContinue,
  });
  final VoidCallback onSkip, onContinue;
  @override
  State<ReviewKnowledgeQuestion> createState() =>
      _ReviewKnowledgeQuestionState();
}

class _ReviewKnowledgeQuestionState extends State<ReviewKnowledgeQuestion> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    const answers = [
      ('New to it', 'I’m starting from zero.'),
      ('I know the basics', 'I know what a stock is.'),
      ('I’ve practiced', 'I’ve used a simulator.'),
      ('I invest', 'I’ve owned stocks.'),
      ('I trade often', 'I make trades regularly.'),
    ];
    return ReviewQuestionFrame(
      step: 2,
      title: 'How much do you know?',
      caption: 'Start where you are.',
      salMood: 'skeptical',
      onSkip: widget.onSkip,
      onContinue: selected == null ? null : widget.onContinue,
      child: Column(
        children: [
          for (var i = 0; i < answers.length; i++) ...[
            ReviewAnswerRow(
              title: answers[i].$1,
              subtitle: answers[i].$2,
              number: (i + 1).toString().padLeft(2, '0'),
              selected: selected == i,
              onTap: () => setState(() => selected = i),
            ),
            if (i != answers.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

const reviewPersonas = <(String, String, String, String)>[
  ('wolf', 'The Wolf', 'Bold moves', 'assets/images/cast/wolf-neutral-v2.png'),
  (
    'oracle',
    'The Oracle',
    'Patient choices',
    'assets/images/cast/oracle-neutral-v2.png',
  ),
  (
    'shark',
    'The Shark',
    'Questions the crowd',
    'assets/images/cast/shark-neutral-v2.png',
  ),
];

class ReviewPersonaQuestion extends StatefulWidget {
  const ReviewPersonaQuestion({
    super.key,
    required this.onSkip,
    required this.onContinue,
    required this.onSelected,
    this.initialSelection,
  });
  final VoidCallback onSkip, onContinue;
  final ValueChanged<String> onSelected;
  final String? initialSelection;
  @override
  State<ReviewPersonaQuestion> createState() => _ReviewPersonaQuestionState();
}

class _ReviewPersonaQuestionState extends State<ReviewPersonaQuestion> {
  String? selected;
  @override
  void initState() {
    super.initState();
    selected = widget.initialSelection;
  }

  @override
  Widget build(BuildContext context) => ReviewQuestionFrame(
    title: 'Pick your persona.',
    caption: 'Just your look. Change it whenever you like.',
    skipLabel: 'Skip persona',
    secondaryLabel: 'Choose later',
    onSkip: widget.onSkip,
    onContinue: selected == null ? null : widget.onContinue,
    child: Column(
      children: [
        for (var i = 0; i < reviewPersonas.length; i++) ...[
          _PersonaArtRow(
            persona: reviewPersonas[i],
            selected: selected == reviewPersonas[i].$1,
            onTap: () {
              final value = reviewPersonas[i].$1;
              setState(() => selected = value);
              widget.onSelected(value);
            },
          ),
          if (i != reviewPersonas.length - 1) const SizedBox(height: 11),
        ],
      ],
    ),
  );
}

class _PersonaArtRow extends StatelessWidget {
  const _PersonaArtRow({
    required this.persona,
    required this.selected,
    required this.onTap,
  });
  final (String, String, String, String) persona;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? const Color(0xFFF0EDFF) : const Color(0xFFF7F8FA),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(26)),
      clipBehavior: Clip.antiAlias,
      animationDuration: uiReviewDuration(context, 180),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 126),
          child: Row(
            children: [
              SizedBox(
                width: 118,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    persona.$4,
                    height: 116,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      persona.$2,
                      style: const TextStyle(
                        fontFamily: 'Dejanire Sans',
                        color: UiReviewColor.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      persona.$3,
                      style: const TextStyle(
                        fontFamily: 'Dejanire Sans',
                        color: Color(0xFF797585),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(right: 17),
                  child: Icon(
                    Icons.check_rounded,
                    size: 23,
                    color: UiReviewColor.violet,
                  ),
                )
              else
                const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

class ReviewHandleQuestion extends StatefulWidget {
  const ReviewHandleQuestion({
    super.key,
    required this.persona,
    required this.onSkip,
    required this.onContinue,
    this.initialName = '',
    this.onNameChanged,
  });
  final String initialName;
  final ValueChanged<String>? onNameChanged;
  final String persona;
  final VoidCallback onSkip, onContinue;
  @override
  State<ReviewHandleQuestion> createState() => _ReviewHandleQuestionState();
}

class _ReviewHandleQuestionState extends State<ReviewHandleQuestion> {
  late final controller = TextEditingController(text: widget.initialName);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final persona = reviewPersonas.firstWhere(
      (entry) => entry.$1 == widget.persona,
      orElse: () => reviewPersonas[1],
    );
    final name = controller.text.trim();
    return ReviewQuestionFrame(
      title: 'What should we call you?',
      caption: 'Your name on Trimmy.',
      skipLabel: 'Close profile setup',
      secondaryLabel: 'Later',
      onSkip: widget.onSkip,
      onContinue: name.length < 3
          ? null
          : () {
              widget.onNameChanged?.call(name);
              widget.onContinue();
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            shadowColor: const Color(0x160F1830),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: double.infinity,
              height: 196,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 98,
                    child: Image.asset(
                      'assets/images/ui_review/profile-sky.webp',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -.3),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    right: 16,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .9),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        child: Text(
                          'ROOKIE',
                          style: TextStyle(
                            fontFamily: 'Dejanire Sans',
                            color: UiReviewColor.ink,
                            fontSize: 11,
                            letterSpacing: .4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 60,
                    left: 19,
                    child: Container(
                      width: 86,
                      height: 86,
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: ColoredBox(
                          color: const Color(0xFFEDECF5),
                          child: Transform.scale(
                            scale: 1.32,
                            alignment: Alignment.topCenter,
                            child: Image.asset(
                              persona.$4,
                              width: 78,
                              height: 78,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 112,
                    left: 117,
                    right: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${name.isEmpty ? 'yourname' : name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Dejanire Sans',
                            color: UiReviewColor.ink,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          persona.$2,
                          style: const TextStyle(
                            fontFamily: 'Dejanire Sans',
                            color: Color(0xFF797585),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 33),
          const Text(
            'Username',
            style: TextStyle(
              fontFamily: 'Dejanire Sans',
              color: UiReviewColor.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            onChanged: (value) {
              setState(() {});
            },
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            maxLength: 20,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
            ],
            decoration: InputDecoration(
              prefixText: '@',
              hintText: 'Choose a username',
              helperText: '3–20 letters, numbers or underscores',
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF7F8FA),
              contentPadding: const EdgeInsets.fromLTRB(19, 17, 19, 17),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: UiReviewColor.violet,
                  width: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
