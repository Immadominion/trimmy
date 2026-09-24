import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/product_motion_icon.dart';
import '../design/product_notice.dart';
import '../design/product_theme.dart';

enum ProductInformation { contact, terms, privacy }

/// Legal text mirrors the existing published site source, dated 14 Sep 2026.
class ProductInformationScreen extends StatelessWidget {
  const ProductInformationScreen({super.key, required this.information});
  final ProductInformation information;
  @override
  Widget build(BuildContext context) {
    final contact = information == ProductInformation.contact;
    final title = switch (information) {
      ProductInformation.contact => 'Help',
      ProductInformation.terms => 'Terms',
      ProductInformation.privacy => 'Privacy',
    };
    final url = contact
        ? 'https://x.com/trimmyhq'
        : 'https://trimmy.xyz/${information.name}/';
    final blocks = information == ProductInformation.privacy
        ? _privacy
        : _terms;
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
              'Talk to us',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            const Text('Find @trimmyhq on X for help or feedback.'),
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
                      message: 'Link copied',
                      onDismiss: messenger.hideCurrentSnackBar,
                    ),
                  ),
                );
              },
              child: Text(contact ? 'Copy contact link' : 'Copy website link'),
            ),
          ),
        ],
      ),
    );
  }
}

const _privacy = <(String, String)>[
  ("h1", "Privacy, in plain words."),
  ("p", "Last updated 14 September 2026"),
  (
    "p",
    "This notice explains information handled by the Trimmy team through trimmy.xyz and, where you have been invited to use one, our private app tests.",
  ),
  (
    "p",
    "The public website is a product introduction. You can read it and try the sample question without creating an account or connecting a wallet.",
  ),
  ("h2", "When you visit this website"),
  (
    "p",
    "Our hosting and network providers may process ordinary request information, such as your IP address, browser or device information, the page requested, request time, and technical errors. This supports delivery of the site, security, and troubleshooting.",
  ),
  (
    "p",
    "This version of the public website does not include advertising pixels, third-party analytics, sign-in forms, or a mailing-list form. Its fonts and illustrations are served with the site. The practice question runs in your browser; the site does not send your selection to a server or write it to cookies or local storage.",
  ),
  (
    "p",
    "Following a link to X or another website takes you to that service, which handles your visit under its own policies. We do not embed an X feed or load X's sign-in tools on this public page.",
  ),
  ("h2", "When you contact us"),
  (
    "p",
    "If you contact @trimmyhq on X, we receive the profile information and message you share. We use it to respond, investigate an issue, or follow up on your request. X also processes that interaction under its privacy policy.",
  ),
  ("h2", "If you use a private app test"),
  (
    "p",
    "The following applies only to an app test that you separately choose to use. Reading this website does not create an app account.",
  ),
  (
    "li",
    "Practice and preferences. The app can save activity choices, completed activities, progress, and settings on your device. In an account-enabled test, practice progress and a watchlist can also be associated with your account on our server so they can be recovered.",
  ),
  (
    "li",
    "Optional sign-in. Account-enabled tests use Privy for authentication. Depending on the method you choose, Privy and the identity provider process sign-in information. Trimmy receives a provider account identifier and authentication tokens needed to establish your session, along with available linked-account information such as an X user identifier, handle, display name, or profile image.",
  ),
  (
    "li",
    "Wallet information. Where an account test includes an embedded Solana wallet, Trimmy may read its public address and public balances for the account view. A public wallet address and on-chain activity can be visible to anyone using the blockchain. This public site does not connect wallets, request signatures, or accept deposits.",
  ),
  (
    "li",
    "Technical records. App and server testing may produce request identifiers, timestamps, errors, and security records to diagnose failures and protect accounts.",
  ),
  (
    "p",
    "We use this information to provide the test features you request, recover your progress, authenticate access, resolve support issues, and investigate abuse or technical failures. The current test does not ask X for permission to post on your behalf.",
  ),
  ("h2", "Services involved"),
  (
    "p",
    "For account-enabled app tests, Privy provides identity and embedded-wallet infrastructure. Review Privy's privacy policy for its practices. If you choose X sign-in, X also processes the authorization under its own policy. A provider may handle information in countries other than your own.",
  ),
  (
    "p",
    "Hosting and database services support the website and app-test infrastructure. Market-data and blockchain providers can receive the stock, network, or public wallet queries necessary for requested features. We do not send your practice answers to those market-data providers.",
  ),
  (
    "p",
    "We may share information with service providers to operate these features, or when needed to respond to a valid legal request, address abuse, or protect the security of the service. We do not sell the information collected through this website or use it for targeted advertising.",
  ),
  ("h2", "Keeping and removing information"),
  (
    "p",
    "Information is kept for the purpose it was collected for, such as maintaining an active test account, resolving a support request, or investigating a security issue. Test data may be reset as development progresses. Hosting logs and provider records follow the applicable service's retention controls; a single retention period does not apply to every kind of record.",
  ),
  (
    "p",
    "You can clear local app data through your device settings. That does not automatically remove server records or records held by Privy or X. You can ask us about access, correction, or deletion of information we hold by contacting @trimmyhq. We may need to verify that the request is yours. Please request a private conversation rather than posting personal information publicly.",
  ),
  (
    "p",
    "Where applicable, you may also have rights to object to or restrict processing, withdraw consent for optional features, receive a copy of your information, or contact your local data-protection authority. Applicable legal requirements and information needed to resolve security or legal matters may limit deletion. We cannot remove public blockchain records or independently control another provider's records.",
  ),
  ("h2", "Private tests and age"),
  (
    "p",
    "Private app tests are intended for adults. We do not knowingly invite children to create test accounts. If you believe a child has provided account information, contact us so we can investigate and address it.",
  ),
  ("h2", "As Trimmy develops"),
  (
    "p",
    "We will update this notice when our features or data practices change and show the date above. New account, financial, or communications features may require additional information and notices before you use them.",
  ),
  ("p", "For privacy questions, contact the Trimmy team at @trimmyhq on X."),
];

const _terms = <(String, String)>[
  ("h1", "Terms of use."),
  ("p", "Last updated 14 September 2026"),
  (
    "p",
    "These terms describe use of trimmy.xyz, a public introduction to Trimmy and a small educational preview.",
  ),
  ("h2", "Trimmy is in development"),
  (
    "p",
    "Product descriptions and artwork show the experience we are building. They do not promise a release date, availability in a particular country, or access to a particular financial product. Features and illustrations may change.",
  ),
  (
    "p",
    "The public website does not open financial accounts, execute trades, hold deposits, send gifts, or offer a claim on any asset. Following the project on X does not create an app account or reserve access. A separate private app test may have additional conditions provided when you join it.",
  ),
  ("h2", "Practice is educational"),
  (
    "p",
    "The sample company and figures in the practice activity are fictional. They illustrate how to read a source and are not live market information. Your sample answer is not an investment instruction and does not move money.",
  ),
  (
    "p",
    "Content on this website is general educational and product information. It is not personalized investment, legal, or tax advice, and is not a recommendation or offer to buy or sell securities or digital assets. Nothing on the website promises a return or suggests that completing practice activities establishes suitability for an investment.",
  ),
  ("h2", "About the planned market features"),
  (
    "p",
    "Tokenized assets can carry market, issuer, liquidity, technology, and legal risks. A token may not provide the same rights as directly owning a share. Availability, eligibility, and asset terms vary. Future financial features will require their own terms, relevant disclosures, and an explicit action from you before use.",
  ),
  (
    "p",
    "We do not represent that decentralization removes applicable laws or user restrictions. The current public site provides no financial execution service.",
  ),
  ("h2", "Use the site responsibly"),
  (
    "p",
    "You may read the public pages, try the practice question, and share links. Do not use the site to break the law, interfere with its operation, attempt unauthorized access, impersonate the Trimmy team, or misrepresent the preview as a live financial service.",
  ),
  (
    "p",
    "Site artwork, text, and branding are provided for viewing as part of the site; publication does not grant a right to redistribute them as your own product. Third-party fonts retain their own licenses, included with the site's font files.",
  ),
  ("h2", "Links and other services"),
  (
    "p",
    "Links to X, Privy, and other services are provided for their stated purpose. Those services have their own terms and privacy practices. Their availability and content are outside our control. Our privacy notice describes the information handled by this website and optional app tests.",
  ),
  ("h2", "Availability and changes"),
  (
    "p",
    "We aim to keep the website useful and accurate, but development previews can contain mistakes or become outdated. The website and preview are provided as available, without a guarantee of uninterrupted access or fitness for a particular purpose. We may correct, change, or remove content as development continues.",
  ),
  (
    "p",
    "Nothing in these terms excludes rights or liabilities that cannot be excluded under applicable law. Updated terms will show a new date on this page.",
  ),
  ("h2", "Questions"),
  (
    "p",
    "Contact the Trimmy team at @trimmyhq on X about the website or these terms.",
  ),
];
