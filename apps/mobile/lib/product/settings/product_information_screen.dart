import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../design/product_motion_icon.dart';
import '../design/product_notice.dart';
import '../design/product_theme.dart';

enum ProductInformation { contact, terms, privacy }

/// In-app disclosures describe implemented features, not the marketing site.
/// Keep these in sync when wallet capabilities or data handling change.
class ProductInformationScreen extends StatelessWidget {
  const ProductInformationScreen({super.key, required this.information});
  final ProductInformation information;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final contact = information == ProductInformation.contact;
    final title = switch (information) {
      ProductInformation.contact => l10n.infoHelpTitle,
      ProductInformation.terms => l10n.infoTermsTitle,
      ProductInformation.privacy => l10n.infoPrivacyTitle,
    };
    final url = contact
        ? 'https://x.com/trimmyhq'
        : 'https://trimmy.xyz/${information.name}/';
    final updated = l10n.infoLastUpdated(
      _longDate(context.formats, _lastUpdated),
    );
    final blocks = information == ProductInformation.privacy
        ? _privacy(l10n, updated)
        : _terms(l10n, updated);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        children: [
          if (contact) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: ProductMotionIcon(file: 'career-comments.png', size: 48),
            ),
            const SizedBox(height: 22),
            Text(
              l10n.infoContactTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(l10n.infoContactBody),
            const SizedBox(height: 18),
          ] else ...[
            for (final block in blocks)
              Padding(
                padding: EdgeInsets.only(
                  bottom: 14,
                  top: block.$1 == 'h2' ? 12 : 0,
                ),
                child: SelectableText(
                  block.$2,
                  style: switch (block.$1) {
                    'h1' => Theme.of(context).textTheme.headlineMedium,
                    'h2' => Theme.of(context).textTheme.titleLarge,
                    _ => Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.5),
                  },
                ),
              ),
          ],
          SelectableText(url, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: ProductColor.violet),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (!context.mounted) return;
                final messenger = ScaffoldMessenger.of(context);
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    content: ProductNotice(
                      message: l10n.infoLinkCopied,
                      onDismiss: messenger.hideCurrentSnackBar,
                    ),
                  ),
                );
              },
              child: Text(
                contact ? l10n.infoCopyContactLink : l10n.infoCopyWebsiteLink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// When the Terms and Privacy notices last changed.
final _lastUpdated = DateTime(2026, 9, 26);

/// "26 September 2026" in English, as the notices have always read; the
/// reader's long date elsewhere ("26 de septiembre de 2026", "26 septembre
/// 2026"). AppFormats has no long-month date, so this builds on its locale.
String _longDate(AppFormats formats, DateTime date) => formats.isEnglish
    ? DateFormat('d MMMM y', 'en_US').format(date)
    : DateFormat.yMMMMd(formats.dateLocale).format(date);

List<(String, String)> _privacy(AppLocalizations l10n, String updated) => [
  ('h1', l10n.infoPrivacyHeading),
  ('p', updated),
  ('p', l10n.infoPrivacyIntro),
  ('h2', l10n.infoPrivacyAccountTitle),
  ('p', l10n.infoPrivacyAccountBody),
  ('h2', l10n.infoPracticeAndCareerTitle),
  ('p', l10n.infoPrivacyPracticeBody),
  ('h2', l10n.infoPrivacyCommentsTitle),
  ('p', l10n.infoPrivacyCommentsBody),
  ('h2', l10n.infoPrivacyWalletsTitle),
  ('p', l10n.infoPrivacyWalletsBody),
  ('h2', l10n.infoPrivacyFundingTitle),
  ('p', l10n.infoPrivacyFundingBody),
  ('h2', l10n.settingsReminders),
  ('p', l10n.infoPrivacyRemindersBody),
  ('h2', l10n.infoPrivacyUsageTitle),
  ('p', l10n.infoPrivacyUsageBody),
  ('h2', l10n.infoPrivacyServicesTitle),
  ('p', l10n.infoPrivacyServicesBody),
  ('h2', l10n.infoPrivacyChoicesTitle),
  ('p', l10n.infoPrivacyChoicesBody),
  ('p', l10n.infoPrivacyRequestsBody),
  ('h2', l10n.infoPrivacyProvidersTitle),
  (
    'p',
    l10n.infoProviderPolicyLink('Privy', 'https://www.privy.io/privacy-policy'),
  ),
  (
    'p',
    l10n.infoProviderPolicyLink(
      'Crossmint',
      'https://www.crossmint.com/legal/privacy-policy',
    ),
  ),
];

List<(String, String)> _terms(AppLocalizations l10n, String updated) => [
  ('h1', l10n.infoTermsHeading),
  ('p', updated),
  ('p', l10n.infoTermsIntro),
  ('h2', l10n.infoPracticeAndCareerTitle),
  ('p', l10n.infoTermsPracticeBody),
  ('h2', l10n.infoTermsRealMoneyTitle),
  ('p', l10n.infoTermsRealMoneyBody),
  ('p', l10n.infoTermsTokenizedBody),
  ('h2', l10n.infoTermsFundingTitle),
  ('p', l10n.infoTermsFundingBody),
  ('h2', l10n.infoTermsAccessTitle),
  ('p', l10n.infoTermsAccessBody),
  ('h2', l10n.infoTermsEligibilityTitle),
  ('p', l10n.infoTermsEligibilityBody),
  ('h2', l10n.infoTermsCommunityTitle),
  ('p', l10n.infoTermsCommunityBody),
  ('h2', l10n.infoTermsAvailabilityTitle),
  ('p', l10n.infoTermsAvailabilityBody),
];
