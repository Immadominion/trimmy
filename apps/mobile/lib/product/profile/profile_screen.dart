import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
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
    this.personaId,
  });
  final String handle, persona;

  /// The trader's id (`wolf`, `oracle` or `shark`), which picks the portrait.
  /// Without it the portrait is guessed from [persona], the shown name.
  final String? personaId;
  final bool signedIn;
  final VoidCallback onSettings, onSignIn;
  final VoidCallback? onChangePersona, onOpenCareer, onRetryCareer;
  final CareerSummary? career;
  final String? careerMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
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
                        l10n.profileTitle,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('profile-settings'),
                      tooltip: l10n.commonSettings,
                      onPressed: onSettings,
                      icon: const ProductMotionIcon(file: 'settings-gear.png'),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                if (signedIn) ...[
                  Center(
                    child: _Avatar(
                      persona: persona,
                      personaId: personaId,
                      onEdit: onChangePersona,
                    ),
                  ),
                  const SizedBox(height: 17),
                  Text(
                    handle.isEmpty ? l10n.profileYourProfile : '@$handle',
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
                      career!.rank.id.label(l10n),
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
                    l10n.profileGuestTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.profileGuestBody, textAlign: TextAlign.center),
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const ValueKey('profile-save-desk'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ProductColor.violet,
                      minimumSize: const Size(double.infinity, 54),
                      shape: productSquircle(22),
                    ),
                    onPressed: onSignIn,
                    child: Text(l10n.commonSignIn),
                  ),
                ],
                const SizedBox(height: 28),
                if (careerMessage != null)
                  Padding(
                    key: const ValueKey('profile-career-stale'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(l10n.profileProgressRefreshFailed),
                        ),
                        if (onRetryCareer != null)
                          TextButton(
                            onPressed: onRetryCareer,
                            child: Text(l10n.commonRetry),
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
                    child: Text(l10n.profileLoadProgress),
                  ),
                const SizedBox(height: 22),
                if (onChangePersona != null && persona.isEmpty)
                  _ProfileRow(
                    title: persona.isEmpty
                        ? l10n.profileChooseTrader
                        : l10n.profileYourTrader,
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
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.persona, this.personaId, this.onEdit});
  final String persona;
  final String? personaId;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final id = switch (personaId) {
      'wolf' || 'oracle' || 'shark' => personaId!,
      _ =>
        persona.toLowerCase().contains('oracle')
            ? 'oracle'
            : persona.toLowerCase().contains('shark')
            ? 'shark'
            : 'wolf',
    };
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
                tooltip: context.l10n.profileChangeTrader,
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formats = context.formats;
    return Material(
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
                      l10n.careerYourProgress,
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
                      value: l10n.careerTrimsCount(
                        career.trims.total,
                        formats.number('${career.trims.total}'),
                      ),
                      label: l10n.careerPointsLabel,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _Stat(
                      value: l10n.profileStreakDays(
                        career.streak.days,
                        formats.number('${career.streak.days}'),
                      ),
                      label: l10n.profileStreakLabel,
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
