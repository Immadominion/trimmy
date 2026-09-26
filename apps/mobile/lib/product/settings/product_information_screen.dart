import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  ('h1', 'Privacy, in plain words.'),
  ('p', 'Last updated 26 September 2026'),
  (
    'p',
    'This notice describes information handled by the Trimmy app and its supporting services.',
  ),
  ('h2', 'Your account or guest session'),
  (
    'p',
    'Sign-in uses Privy and the email or social provider you choose. Trimmy receives account identifiers, session credentials and available linked-account details, such as your email, handle or profile image, to authenticate you and recover your progress. Continuing as a guest creates a separate session; guest activity can also be stored on our server. Signing in can link that progress to your account.',
  ),
  ('h2', 'Practice and Career'),
  (
    'p',
    'Your practice orders, balances, activity answers, completed workdays, streaks, Trims, watchlist and trader profile support the game and your progress. Preferences and unfinished activity drafts can be saved on your device; account and progress records are also stored on our server.',
  ),
  ('h2', 'Comments and following'),
  (
    'p',
    'Your comment-sharing choice controls which other users can see your comments with your handle, trader persona and the asset discussed. The community feed does not publish your order amounts or wallet balance. We store follows, sharing preferences, blocks and reports to provide these features and address abuse. Public blockchain activity remains visible independently of these settings.',
  ),
  ('h2', 'Wallets and real trades'),
  (
    'p',
    'Privy supplies the embedded wallet and signing interface. Trimmy uses your public Solana address to read balances, request quotes and prepare reviewed transactions. Our server receives signed transactions for submission and stores order terms, transaction references and status. Wallet addresses, token amounts and transaction signatures are public on the blockchain. Closing Trimmy cannot erase those records.',
  ),
  ('h2', 'Funding'),
  (
    'p',
    'When you use Crossmint checkout, Trimmy shares the email, destination wallet, requested amount and wallet-ownership proof needed to prepare the order. Crossmint handles payment and identity-verification information in its checkout. Trimmy receives order and delivery status; our onramp server does not collect card numbers or verification documents.',
  ),
  ('h2', 'Reminders'),
  (
    'p',
    'Career reminders are scheduled on your device with your permission. You can change the reminder preference in Trimmy or disable notifications in device settings. Saved social notification preferences do not mean that social or transaction push delivery is available in this build.',
  ),
  ('h2', 'Services and technical records'),
  (
    'p',
    'Hosting and database providers support the app. Market-data services receive asset queries; Jupiter and blockchain providers receive wallet or transaction queries needed for real trading. Privy, your sign-in provider and Crossmint handle information under their own policies and may process it in other countries. Network information, request times, identifiers and errors help deliver the service, limit abuse and investigate failures.',
  ),
  ('h2', 'Your choices and records'),
  (
    'p',
    'You can change sharing and reminder preferences in Settings. Signing out does not delete server records. Closing an account disables access but does not erase its historical records, delete your provider account, move assets or remove blockchain data. Clearing app data can remove local progress and access information; make sure you can recover a funded wallet before doing so.',
  ),
  (
    'p',
    'Contact @trimmyhq on X to ask about access, correction or deletion of information held by Trimmy. Ask for a private conversation and do not post credentials or personal documents publicly. We may need to verify the request. Provider records follow their own policies; blockchain records cannot be deleted by Trimmy.',
  ),
  ('h2', 'Provider privacy policies'),
  ('p', 'Privy: https://www.privy.io/privacy-policy'),
  ('p', 'Crossmint: https://www.crossmint.com/legal/privacy-policy'),
];

const _terms = <(String, String)>[
  ('h1', 'Using Trimmy.'),
  ('p', 'Last updated 26 September 2026'),
  (
    'p',
    'Trimmy combines a trading simulation with a separate real-money mode. These terms describe the app as it works today. Features remain in development.',
  ),
  ('h2', 'Practice and Career'),
  (
    'p',
    'Paper balances and orders are simulated. Trims, streaks and Career ranks record game progress; they cannot be withdrawn as money. Practice can use sample or market reference data. Completing an activity does not establish investment suitability, and comments from other users are their own views. Educational content is not personalized investment, legal or tax advice.',
  ),
  ('h2', 'Real money'),
  (
    'p',
    'Real mode uses a Solana mainnet wallet and supported tokenized stocks. An order can move real assets when you review and confirm it. Check the asset, amount, fees and destination before approving. A quote is an estimate that can expire; a submitted or pending order is not a confirmed trade. History currently shows reviewed quote amounts, not a complete statement of final fills, fees or external transfers.',
  ),
  (
    'p',
    'Tokenized stocks are subject to their issuer terms and do not necessarily give the same rights as directly holding company shares. Prices can fall, liquidity can disappear, and issuer, network or provider failures can cause loss. Trimmy does not promise returns or execution at a displayed price.',
  ),
  ('h2', 'Funding your wallet'),
  (
    'p',
    'Send only supported USDC or SOL to the displayed address on the Solana network. Verify the address and network before sending; a completed blockchain transfer cannot simply be undone by Trimmy. SOL is also needed for network fees. Crossmint card checkout is currently a test environment: its test funds do not fund mainnet trades. Its production availability, payment methods, verification and fees depend on the provider.',
  ),
  ('h2', 'Account access'),
  (
    'p',
    'Protect your sign-in method and review wallet prompts carefully. Never share a private key, recovery phrase or one-time sign-in code with support. This build does not yet provide in-app withdrawals or wallet export. Closing your account does not withdraw assets. Resolve wallet access before closing an account or removing the app from a funded device.',
  ),
  ('h2', 'Eligibility and other services'),
  (
    'p',
    'You must meet the applicable asset issuer and service-provider requirements, including location and eligibility restrictions. Seeing an asset or obtaining a quote does not establish eligibility. Privy, Crossmint, trading providers and asset issuers have separate terms. Trimmy does not promise availability in every country.',
  ),
  ('h2', 'Using the community'),
  (
    'p',
    'Share comments you have the right to publish. Do not impersonate others, expose private information, manipulate the market, harass users or interfere with accounts and services. Sharing settings, blocking and reporting tools are available for comments and community interactions.',
  ),
  ('h2', 'Availability and questions'),
  (
    'p',
    'Market data, quotes, notifications and network confirmation can be delayed or unavailable. Features and these notices may change as development continues. Nothing here removes rights that cannot be excluded under applicable law. Contact @trimmyhq on X for help or questions about these terms.',
  ),
];
