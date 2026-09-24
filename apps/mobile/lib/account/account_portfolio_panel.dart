import 'package:flutter/material.dart';

import '../design_study/craft.dart';
import 'account_amounts.dart';
import 'account_controller.dart';
import 'account_data_models.dart';
import 'account_portfolio.dart';
import 'wallet_setup_panel.dart';

/// Read-only account section for the Portfolio tab. It renders the server's
/// last observation for the verified account exactly as received: balances
/// without prices, with explicit freshness and wallet setup kept separate from
/// the fictional activities.
class AccountPortfolioPanel extends StatelessWidget {
  const AccountPortfolioPanel({
    super.key,
    required this.controller,
    this.onSignIn,
  });
  final AccountController? controller;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null || !controller.canSignIn) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final repository = controller.portfolioRepository;
        final canCheck =
            controller.isServerVerified &&
            repository != null &&
            !repository.isBusy;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountPortfolioView(
              state: controller.portfolioState,
              signedIn: controller.phase == AccountPhase.active,
              verified: controller.isServerVerified,
              onCheckAgain: canCheck
                  ? () =>
                        controller.refreshPortfolio().catchError((Object _) {})
                  : null,
            ),
            if (controller.phase != AccountPhase.active && onSignIn != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: CraftButton(label: 'Sign in', onPressed: onSignIn),
              ),
            WalletSetupPanel(
              key: ValueKey(controller.accountId),
              controller: controller,
            ),
          ],
        );
      },
    );
  }
}

/// Pure presentation of one [AccountPortfolioState]; testable without HTTP.
class AccountPortfolioView extends StatelessWidget {
  const AccountPortfolioView({
    super.key,
    required this.state,
    required this.signedIn,
    required this.verified,
    this.onCheckAgain,
  });

  final AccountPortfolioState? state;
  final bool signedIn;
  final bool verified;
  final VoidCallback? onCheckAgain;

  @override
  Widget build(BuildContext context) => StudyPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Your account', style: display(20))),
            const _Tag('Read-only'),
          ],
        ),
        const SizedBox(height: 8),
        ..._body(),
        const SizedBox(height: 10),
        const Text(
          'Balances only. No prices, no buying or selling.',
          style: TextStyle(fontSize: 13, color: StudyColor.muted),
        ),
      ],
    ),
  );

  List<Widget> _body() {
    if (!signedIn) {
      return const [
        Text('Sign in from Settings to see the wallet linked to your account.'),
      ];
    }
    if (!verified) {
      return const [
        Text("Your account will be checked when you're back online."),
      ];
    }
    final state = this.state;
    if (state == null) return [_status('Checking your account…')];
    final portfolio = state.portfolio;
    final context = state.context;
    final widgets = <Widget>[];
    var showCheckAgain = onCheckAgain != null;
    switch (state.phase) {
      case AccountPortfolioPhase.loading:
        widgets.add(
          _status(
            portfolio == null ? 'Checking your account…' : 'Checking again…',
          ),
        );
        showCheckAgain = false;
      case AccountPortfolioPhase.ready:
        widgets.add(_status('Checked at ${_time(portfolio!)}.'));
      case AccountPortfolioPhase.stale:
        widgets.add(
          _status(
            portfolio == null
                ? 'The last check is out of date.'
                : 'Checked at ${_time(portfolio)}. This may have changed.',
          ),
        );
      case AccountPortfolioPhase.offline:
        widgets.add(
          _status(
            portfolio == null
                ? "You're offline. Your account will be checked when you're back online."
                : "You're offline. This is what we saw at ${_time(portfolio)}.",
          ),
        );
        showCheckAgain = false;
      case AccountPortfolioPhase.cancelled:
        widgets.add(_status('The check was paused.'));
      case AccountPortfolioPhase.idle:
        widgets.add(_status('Your account has not been checked yet.'));
      case AccountPortfolioPhase.error:
        widgets.add(_status(_issueMessage(state.issue)));
      case AccountPortfolioPhase.accountChanged:
      case AccountPortfolioPhase.closed:
        return const [Text('Sign in again to see your account.')];
    }
    if (context != null) widgets.addAll(_contextRows(context));
    if (portfolio != null) widgets.addAll(_balanceRows(portfolio.holdings));
    if (showCheckAgain) {
      widgets.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onCheckAgain,
            child: const Text('Check again'),
          ),
        ),
      );
    }
    return widgets;
  }

  static String _time(AccountPortfolioSnapshot portfolio) =>
      formatClockTime(portfolio.holdings.observedAt);

  static String _issueMessage(AccountPortfolioIssue? issue) => switch (issue) {
    AccountPortfolioIssue.walletMissing =>
      'No wallet is linked to this account yet.',
    AccountPortfolioIssue.walletAmbiguous =>
      'This account has more than one wallet, so balances are not shown.',
    AccountPortfolioIssue.walletChanged =>
      'The linked wallet changed. Check again.',
    AccountPortfolioIssue.unauthenticated =>
      'Sign in again to see your account.',
    AccountPortfolioIssue.notConfigured =>
      'Account details are not available on this server yet.',
    AccountPortfolioIssue.observationExpired ||
    AccountPortfolioIssue.observationInFuture =>
      'The last check is out of date.',
    _ => 'Your account could not be checked.',
  };

  static Widget _status(String text) =>
      Semantics(liveRegion: true, child: Text(text));

  static List<Widget> _contextRows(AccountContextSnapshot context) {
    final rows = <Widget>[const SizedBox(height: 12)];
    final wallet = context.embeddedSolanaWallet;
    if (wallet.isCandidate) {
      rows.add(
        _row(
          'Wallet',
          shortenAddress(wallet.address!),
          semantics: 'Wallet address ${wallet.address!}',
        ),
      );
    }
    final x = context.xIdentity;
    if (x.isVerified && x.usernameSnapshot != null) {
      rows.add(_row('X', '@${x.usernameSnapshot}'));
    }
    return rows;
  }

  static List<Widget> _balanceRows(AccountHoldingsSnapshot holdings) {
    final sol = formatRawUnits(holdings.nativeSol.amountRaw, 9);
    final usdc = formatRawUnits(
      holdings.usdc.amountRaw,
      holdings.usdc.decimals,
    );
    final aaplxRecorded = holdings.aaplx.amountRaw != '0';
    return [
      _row('SOL', sol ?? 'Unavailable'),
      _row('USDC', usdc ?? 'Unavailable'),
      if (holdings.usdc.hasFrozenAccounts)
        const _Note('Some USDC is in a frozen account.'),
      if (holdings.usdc.accountCount > 1)
        _Note('USDC is held in ${holdings.usdc.accountCount} accounts.'),
      _row('AAPLx', aaplxRecorded ? 'Amount not confirmed' : 'None'),
      if (aaplxRecorded)
        const _Note(
          'AAPLx is recorded on this wallet. Its share amount is not confirmed yet.',
        ),
    ];
  }

  static Widget _row(String label, String value, {String? semantics}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 260 ||
                MediaQuery.textScalerOf(context).scale(16) > 21;
            final name = Text(
              label,
              style: const TextStyle(color: StudyColor.muted),
            );
            final amount = Semantics(
              label: semantics,
              excludeSemantics: semantics != null,
              child: Text(
                value,
                textAlign: stacked ? TextAlign.start : TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            );
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [name, amount],
                  )
                : Row(
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: 12),
                      Flexible(flex: 2, child: amount),
                    ],
                  );
          },
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: StudyColor.muted),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: ShapeDecoration(color: StudyColor.mint, shape: studyShape(10)),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: StudyColor.deep,
      ),
    ),
  );
}
