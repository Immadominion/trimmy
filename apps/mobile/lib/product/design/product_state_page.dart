import 'package:flutter/material.dart';

import 'product_theme.dart';

/// Existing Wall Street illustrations, kept sharp at full-page hero sizes.
class ProductStateArtwork extends StatelessWidget {
  const ProductStateArtwork({super.key, required this.file, this.size = 176});
  final String file;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: .92, end: 1),
      duration: productDuration(context, 500),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Transform.scale(scale: value, child: child),
      child: Image.asset(
        'assets/images/career_world/$file',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}

/// One quiet, scrollable layout for account notices, recovery and milestones.
/// Actions stay reachable on small screens and with enlarged text.
class ProductStatePage extends StatelessWidget {
  const ProductStatePage({
    super.key,
    required this.artwork,
    required this.title,
    this.message,
    this.details,
    this.actions = const [],
  });

  final Widget artwork;
  final String title;
  final String? message;
  final Widget? details;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ProductColor.paper,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 64).clamp(0, double.infinity),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: artwork),
                    const SizedBox(height: 28),
                    Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: ProductColor.muted,
                        ),
                      ),
                    ],
                    if (details != null) ...[
                      const SizedBox(height: 24),
                      details!,
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      ...actions,
                    ],
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
