import 'package:flutter/material.dart';
import '../career/career.dart';
import '../design/product_motion_icon.dart';
import '../design/product_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.handle,
    required this.persona,
    required this.signedIn,
    required this.onSettings,
    required this.onSignIn,
    this.career,
    this.careerMessage,
    this.onRetryCareer,
    this.onChangePersona,
    this.onOpenCareer,
  });
  final String handle, persona;
  final bool signedIn;
  final VoidCallback onSettings, onSignIn;
  final VoidCallback? onChangePersona, onOpenCareer, onRetryCareer;
  final CareerSummary? career;
  final String? careerMessage;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: CustomScrollView(
      key: const PageStorageKey('product-profile'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Profile',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('profile-settings'),
                    tooltip: 'Settings',
                    onPressed: onSettings,
                    icon: const ProductMotionIcon(file: 'settings-gear.png'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (signedIn) ...[
                Center(
                  child: _Avatar(persona: persona, onEdit: onChangePersona),
                ),
                const SizedBox(height: 17),
                Text(
                  handle.isEmpty ? 'Your profile' : '@$handle',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (persona.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    persona,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (career != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    career!.rank.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: ProductColor.violet,
                    ),
                  ),
                ],
              ] else ...[
                Center(
                  child: Image.asset(
                    'assets/images/ui_review/sal-chair-welcome-v3-still.png',
                    width: 248,
                    height: 174,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Make it yours',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to keep your trades and career together.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                FilledButton(
                  key: const ValueKey('profile-save-desk'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ProductColor.violet,
                    minimumSize: const Size(double.infinity, 54),
                    shape: productSquircle(22),
                  ),
                  onPressed: onSignIn,
                  child: const Text('Sign in'),
                ),
              ],
              const SizedBox(height: 28),
              if (careerMessage != null)
                Padding(
                  key: const ValueKey('profile-career-stale'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Progress couldn’t refresh.')),
                      if (onRetryCareer != null)
                        TextButton(
                          onPressed: onRetryCareer,
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              if (career != null)
                _Progress(career: career!, onTap: onOpenCareer)
              else if (onRetryCareer != null)
                TextButton(
                  key: const ValueKey('profile-career-pending'),
                  onPressed: onRetryCareer,
                  child: const Text('Load progress'),
                ),
              const SizedBox(height: 22),
              if (onChangePersona != null && persona.isEmpty)
                _ProfileRow(
                  title: persona.isEmpty ? 'Choose your trader' : 'Your trader',
                  subtitle: persona.isEmpty ? null : persona,
                  icon: 'nav-plumpy-profile.png',
                  onTap: onChangePersona!,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.persona, this.onEdit});
  final String persona;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final id = persona.toLowerCase().contains('oracle')
        ? 'oracle'
        : persona.toLowerCase().contains('shark')
        ? 'shark'
        : 'wolf';
    return SizedBox(
      width: 116,
      height: 116,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipOval(
              child: ColoredBox(
                color: const Color(0xFFF2EFF9),
                child: persona.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(26),
                        child: ProductMotionIcon(
                          file: 'nav-plumpy-profile.png',
                          size: 64,
                        ),
                      )
                    : Image.asset(
                        'assets/images/ui_review/persona-$id-avatar-v1.png',
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
          if (onEdit != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: IconButton(
                tooltip: 'Change your trader',
                onPressed: onEdit,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  minimumSize: const Size(44, 44),
                ),
                icon: const ProductMotionIcon(
                  file: 'profile-edit.png',
                  size: 22,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.career, this.onTap});
  final CareerSummary career;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('profile-career-record'),
    color: const Color(0xFFF6F4FB),
    shape: productSquircle(26),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your progress',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
            const SizedBox(height: 17),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Stat(
                    value: '${career.trims.total} Trims',
                    label: 'Career points',
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _Stat(
                    value:
                        '${career.streak.days} ${career.streak.days == 1 ? 'day' : 'days'}',
                    label: 'Streak',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });
  final String title, icon;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: ProductColor.paperRaised,
      shape: productSquircle(23),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
        leading: ProductMotionIcon(file: icon),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      ),
    ),
  );
}
