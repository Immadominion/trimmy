import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui_review/welcome_review_screen.dart';
import '../design/product_components.dart';
import '../design/product_theme.dart';
import 'onboarding_art.dart';
import 'onboarding_controller.dart';
import 'onboarding_models.dart';

/// The complete pre-trade onboarding. Storage and navigation stay with its host.
typedef CompleteOnboarding = FutureOr<void> Function(OnboardingResult result);

class TrimmyOnboarding extends StatefulWidget {
  const TrimmyOnboarding({
    super.key,
    required this.onCompleted,
    required this.onHaveAccount,
    this.requestNotificationPermission,
    this.controller,
  });

  final CompleteOnboarding onCompleted;
  final FutureOr<void> Function() onHaveAccount;
  final RequestOnboardingNotificationPermission? requestNotificationPermission;
  final OnboardingController? controller;

  @override
  State<TrimmyOnboarding> createState() => _TrimmyOnboardingState();
}

class _TrimmyOnboardingState extends State<TrimmyOnboarding> {
  late final OnboardingController _controller;
  late final bool _ownsController;
  late final TextEditingController _handleController;
  bool _finishing = false;
  String? _finishError;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? OnboardingController();
    _handleController = TextEditingController(text: _controller.handle);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _handleController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (_handleController.text != _controller.handle) {
      _handleController.value = TextEditingValue(
        text: _controller.handle,
        selection: TextSelection.collapsed(offset: _controller.handle.length),
      );
    }
    if (mounted) setState(() {});
  }

  void _advance() {
    FocusManager.instance.primaryFocus?.unfocus();
    _controller.advance();
  }

  Future<void> _persistCompletion(OnboardingNotificationStatus status) async {
    final result = _controller.complete(status);
    if (result == null) {
      if (mounted) setState(() => _finishing = false);
      return;
    }
    try {
      await widget.onCompleted(result);
      if (mounted) setState(() => _finishing = false);
    } catch (_) {
      if (!mounted) return;
      _controller.retryCompletion();
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _finishError = 'Your setup was not saved. Try again.';
      });
    }
  }

  Future<void> _finish(OnboardingNotificationStatus status) async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _finishError = null;
    });
    await _persistCompletion(status);
  }

  Future<void> _requestNotifications() async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _finishError = null;
    });
    try {
      final request = widget.requestNotificationPermission;
      final status = request == null
          ? OnboardingNotificationStatus.unavailable
          : await request();
      if (!mounted) return;
      await _persistCompletion(status);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _finishError = 'The phone did not open the request. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = _controller.stage;
    return PopScope<void>(
      canPop: stage == OnboardingStage.welcome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _controller.goBack();
      },
      child: stage == OnboardingStage.welcome
          ? WelcomeReviewScreen(
              onStart: _advance,
              onHaveAccount: widget.onHaveAccount,
            )
          : Scaffold(
              backgroundColor: ProductColor.paper,
              body: SafeArea(
                child: AnimatedSwitcher(
                  duration: productDuration(context, 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey(stage),
                    child: _screenFor(stage),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _screenFor(OnboardingStage stage) => switch (stage) {
    OnboardingStage.welcome => throw StateError('Welcome has its own frame'),
    OnboardingStage.salHello => _SalHelloScreen(onContinue: _advance),
    OnboardingStage.goal ||
    OnboardingStage.knowledge ||
    OnboardingStage.persona ||
    OnboardingStage.dailyGoal ||
    OnboardingStage.handle => _QuestionScreen(
      controller: _controller,
      handleController: _handleController,
      onContinue: _advance,
    ),
    OnboardingStage.notifications => _NotificationScreen(
      available: widget.requestNotificationPermission != null,
      busy: _finishing,
      error: _finishError,
      onAllow: _requestNotifications,
      onNotNow: () =>
          unawaited(_finish(OnboardingNotificationStatus.notRequested)),
      onReview: _controller.goBack,
    ),
    OnboardingStage.completed => const _CompletedScreen(),
  };
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.children, this.centered = false});

  final List<Widget> children;
  final bool centered;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        children: [if (centered) const SizedBox(height: 20), ...children],
      ),
    ),
  );
}

class _SalHelloScreen extends StatelessWidget {
  const _SalHelloScreen({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => _PageFrame(
    centered: true,
    children: [
      const SizedBox(height: 20),
      const Center(child: SalPortrait(size: 178)),
      const SizedBox(height: 22),
      const _SpeechBubble(
        text: 'Five quick questions, then your first paper trade.',
        large: true,
      ),
      const SizedBox(height: 34),
      ProductButton(label: 'Continue', onPressed: onContinue),
    ],
  );
}

class _QuestionScreen extends StatelessWidget {
  const _QuestionScreen({
    required this.controller,
    required this.handleController,
    required this.onContinue,
  });

  final OnboardingController controller;
  final TextEditingController handleController;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final index = controller.questionIndex;
    return _PageFrame(
      children: [
        _ProgressHeader(index: index, progress: controller.progress),
        const SizedBox(height: 26),
        _SalQuestion(question: _questionFor(controller.stage)),
        const SizedBox(height: 24),
        ..._answerWidgets(context),
        const SizedBox(height: 26),
        ProductButton(
          key: const Key('onboarding-primary'),
          label: 'Continue',
          onPressed: controller.canContinue ? onContinue : null,
        ),
      ],
    );
  }

  String _questionFor(OnboardingStage stage) => switch (stage) {
    OnboardingStage.goal => 'Why are you here?',
    OnboardingStage.knowledge => 'How much do you know about trading?',
    OnboardingStage.persona => 'Pick your trader.',
    OnboardingStage.dailyGoal => 'Pick your daily goal.',
    OnboardingStage.handle => 'What should the floor call you?',
    _ => '',
  };

  List<Widget> _answerWidgets(BuildContext context) =>
      switch (controller.stage) {
        OnboardingStage.goal => [
          for (final value in OnboardingGoal.values.where(
            (value) => value != OnboardingGoal.friends,
          )) ...[
            _ChoiceCard(
              key: ValueKey('goal-${value.name}'),
              label: value.label,
              description: value.description,
              selected: controller.goal == value,
              onPressed: () => controller.selectGoal(value),
            ),
            const SizedBox(height: 12),
          ],
        ],
        OnboardingStage.knowledge => [
          for (var i = 0; i < TradingKnowledge.values.length; i++) ...[
            _ChoiceCard(
              key: ValueKey('knowledge-${TradingKnowledge.values[i].name}'),
              label: TradingKnowledge.values[i].label,
              leading: _ScaleNumber(i + 1),
              selected: controller.knowledge == TradingKnowledge.values[i],
              onPressed: () =>
                  controller.selectKnowledge(TradingKnowledge.values[i]),
            ),
            const SizedBox(height: 12),
          ],
        ],
        OnboardingStage.persona => [
          for (final value in TraderPersona.values) ...[
            _ChoiceCard(
              key: ValueKey('persona-${value.name}'),
              label: value.label,
              description: value.description,
              leading: PersonaPortrait(value),
              selected: controller.persona == value,
              onPressed: () => controller.selectPersona(value),
            ),
            const SizedBox(height: 12),
          ],
        ],
        OnboardingStage.dailyGoal => [
          for (final value in OnboardingDailyGoal.values) ...[
            _ChoiceCard(
              key: ValueKey('daily-${value.name}'),
              label: value.label,
              description: value.description,
              selected: controller.dailyGoal == value,
              onPressed: () => controller.selectDailyGoal(value),
            ),
            const SizedBox(height: 12),
          ],
        ],
        OnboardingStage.handle => [
          TextField(
            key: const Key('onboarding-handle'),
            controller: handleController,
            autofocus: false,
            maxLength: 18,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.text,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_@]')),
            ],
            decoration: InputDecoration(
              labelText: 'Handle',
              hintText: 'marketmira',
              prefixText: '@',
              helperText: '3 to 18 characters',
              errorText: controller.handleError,
            ),
            onChanged: controller.setHandle,
            onSubmitted: (_) {
              if (controller.canContinue) onContinue();
            },
          ),
        ],
        _ => const [],
      };
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.index, required this.progress});

  final int index;
  final double progress;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          label: 'Onboarding progress',
          value: '${(progress * 100).round()} percent',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progress,
              color: const Color(0xFFE84F79),
              backgroundColor: ProductColor.line,
            ),
          ),
        ),
      ),
      const SizedBox(width: 14),
      Text('${index + 1} of 5', style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}

class _SalQuestion extends StatelessWidget {
  const _SalQuestion({required this.question});

  final String question;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SalPortrait(),
      const SizedBox(width: 14),
      Expanded(child: _SpeechBubble(text: question)),
    ],
  );
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text, this.large = false});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sal says: $text',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: ProductColor.ink, width: 1.5),
          ),
        ),
        child: Text(
          text,
          textAlign: large ? TextAlign.center : TextAlign.start,
          style: large
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(context).textTheme.titleMedium,
        ),
      ),
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.description,
    this.leading,
  });

  final String label;
  final String? description;
  final Widget? leading;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: [label, if (description != null) description].join(', '),
    child: ExcludeSemantics(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: AnimatedContainer(
            duration: productDuration(context, 150),
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.all(16),
            decoration: ShapeDecoration(
              color: selected
                  ? const Color(0xFFFFF1C4)
                  : ProductColor.paperRaised,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(
                  color: selected ? ProductColor.ink : ProductColor.line,
                  width: selected ? 2 : 1,
                ),
              ),
              shadows: selected
                  ? const [
                      BoxShadow(color: ProductColor.ink, offset: Offset(0, 3)),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 16)],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          description!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: ProductColor.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _SelectionMark(selected: selected),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ScaleNumber extends StatelessWidget {
  const _ScaleNumber(this.number);

  final int number;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: ShapeDecoration(
      color: ProductColor.mint,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(13)),
    ),
    child: Text('$number', style: Theme.of(context).textTheme.titleMedium),
  );
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: 25,
    height: 25,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? ProductColor.pine : Colors.transparent,
      border: Border.all(
        color: selected ? ProductColor.pine : ProductColor.muted,
        width: 2,
      ),
    ),
    child: selected
        ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
        : null,
  );
}

class _NotificationScreen extends StatelessWidget {
  const _NotificationScreen({
    required this.available,
    required this.busy,
    required this.error,
    required this.onAllow,
    required this.onNotNow,
    required this.onReview,
  });

  final bool available, busy;
  final String? error;
  final VoidCallback onAllow;
  final VoidCallback onNotNow;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => _PageFrame(
    children: [
      const _ProgressHeader(index: 4, progress: 1),
      const SizedBox(height: 26),
      _SalQuestion(
        question: available
            ? "I'll ring you when Wall Street opens and closes. Trading here stays open."
            : 'Alerts are almost ready.',
      ),
      const SizedBox(height: 22),
      if (available) ...[const PermissionPreview(), const SizedBox(height: 18)],
      Text(
        available ? 'Your phone asks next.' : 'Keep setting up your desk.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 6),
      Text(
        available
            ? 'You can change alerts any time in Settings.'
            : 'Alerts will appear here after delivery is connected.',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: ProductColor.muted),
      ),
      if (error != null) ...[
        const SizedBox(height: 14),
        Semantics(
          liveRegion: true,
          child: Text(
            error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ProductColor.loss,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
      const SizedBox(height: 28),
      ProductButton(
        key: const Key('onboarding-notifications-allow'),
        label: busy
            ? 'Saving your setup'
            : available
            ? 'Turn on alerts'
            : 'Continue',
        onPressed: busy ? null : onAllow,
      ),
      if (available) ...[
        const SizedBox(height: 14),
        ProductButton(
          label: 'Not now',
          onPressed: busy ? null : onNotNow,
          secondary: true,
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : onReview,
          child: const Text('Review my answers'),
        ),
      ],
    ],
  );
}

class _CompletedScreen extends StatelessWidget {
  const _CompletedScreen();

  @override
  Widget build(BuildContext context) => _PageFrame(
    centered: true,
    children: [
      const Center(child: TrimmyMark()),
      const SizedBox(height: 24),
      Text(
        'Opening the market',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
    ],
  );
}
