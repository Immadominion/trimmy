import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui_review/review_welcome_note.dart';
import '../../ui_review/welcome_review_screen.dart';

/// The approved first-use presentation. Its host persists real launch state;
/// this widget never supplies answers or creates a practice position.
class ProductIntroduction extends StatefulWidget {
  const ProductIntroduction({
    super.key,
    required this.onContinue,
    required this.onSkip,
    required this.onHaveAccount,
    this.startAtNote = false,
    this.showWelcomeNote = true,
  });

  final Future<void> Function() onContinue, onSkip;
  final FutureOr<void> Function() onHaveAccount;
  final bool startAtNote;
  final bool showWelcomeNote;

  @override
  State<ProductIntroduction> createState() => _ProductIntroductionState();
}

class _ProductIntroductionState extends State<ProductIntroduction> {
  late bool _showNote = widget.startAtNote;
  bool _busy = false;
  String? _error;
  int _welcomeAttempt = 0;

  Future<void> _finish(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not save that step. Try again.';
          _welcomeAttempt++;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_showNote,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _showNote) unawaited(_finish(widget.onSkip));
    },
    child: Stack(
      children: [
        AbsorbPointer(
          absorbing: _busy,
          child: !_showNote
              ? WelcomeReviewScreen(
                  key: ValueKey('welcome-$_welcomeAttempt'),
                  onStart: () {
                    if (widget.showWelcomeNote) {
                      setState(() => _showNote = true);
                    } else {
                      unawaited(_finish(widget.onContinue));
                    }
                  },
                  onHaveAccount: widget.onHaveAccount,
                )
              : ReviewWelcomeNotePage(
                  onContinue: () => unawaited(_finish(widget.onContinue)),
                  onSkip: () => unawaited(_finish(widget.onSkip)),
                ),
        ),
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: LinearProgressIndicator(
                minHeight: 2,
                color: Color(0xFF7867E8),
                backgroundColor: Colors.white,
                semanticsLabel: 'Saving your place',
              ),
            ),
          ),
        if (_error != null)
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 82,
            left: 24,
            right: 24,
            child: Material(
              color: Colors.white,
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB73549)),
              ),
            ),
          ),
      ],
    ),
  );
}
