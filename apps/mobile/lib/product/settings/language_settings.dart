import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../design/product_theme.dart';

/// What the Language row in Settings shows: "Phone language" until someone
/// picks, then the chosen language's own name.
String languageChoiceLabel(BuildContext context, AppLanguage language) =>
    language.nativeName ?? context.l10n.settingsLanguagePhone;

/// Lists "Phone language" and every language Trimmy speaks, each by its own
/// name. Picking one saves it and the whole app switches at once.
Future<void> showLanguagePicker(
  BuildContext context,
  AppLocaleController controller,
) async {
  final choice = await showModalBottomSheet<AppLanguage>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ProductColor.paper,
    shape: productSquircle(28),
    builder: (_) => LanguagePickerSheet(current: controller.language),
  );
  if (choice == null) return;
  await controller.setLanguage(choice);
}

class LanguagePickerSheet extends StatelessWidget {
  const LanguagePickerSheet({super.key, required this.current});

  final AppLanguage current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.settingsLanguage, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final language in AppLanguage.values) ...[
              _LanguageOption(
                key: ValueKey('language-option-${language.name}'),
                title: languageChoiceLabel(context, language),
                subtitle: language == AppLanguage.phone
                    ? l10n.settingsLanguagePhoneDetail
                    : null,
                // Each name is in its own language, so it is read that way.
                locale: language.locale,
                selected: language == current,
                onSelected: () => Navigator.of(context).pop(language),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.locale,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final String? subtitle;
  final Locale? locale;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0xFFECE7FA) : ProductColor.paperRaised,
        shape: productSquircle(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        locale: locale,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 22,
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 22,
                          color: ProductColor.violet,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
