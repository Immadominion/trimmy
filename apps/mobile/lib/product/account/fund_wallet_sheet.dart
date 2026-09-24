import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../account/account_controller.dart';
import '../../account/account_amounts.dart';
import '../../account/account_data_models.dart';
import '../../account/wallet_setup.dart';
import '../../account/config.dart';
import '../design/product_theme.dart';
import '../../ui_review/review_animated_splash.dart';
import 'crossmint_onramp.dart';

class FundWalletSheet extends StatefulWidget {
  const FundWalletSheet({super.key, required this.account});
  final AccountController account;
  @override
  State<FundWalletSheet> createState() => _FundWalletSheetState();
}

class _FundWalletSheetState extends State<FundWalletSheet>
    with WidgetsBindingObserver {
  bool _busy = false, _copied = false, _foreground = true, _refreshing = false;
  String? _message;
  bool _card = false;
  Timer? _poll, _copyTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!_foreground ||
        _refreshing ||
        widget.account.phase != AccountPhase.active) {
      return;
    }
    _refreshing = true;
    try {
      await widget.account.refreshPortfolio();
    } catch (_) {
      /* Retry automatically. */
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _copyTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _setup() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await widget.account.setUpWallet();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message =
          outcome == WalletSetupOutcome.ready ||
              outcome == WalletSetupOutcome.awaitingServer
          ? null
          : 'Couldn’t create your wallet. Try again.';
    });
    unawaited(_refresh());
  }

  Future<void> _copy(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() => _copied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.account,
    builder: (context, _) {
      final wallet =
          widget.account.portfolioState?.context?.embeddedSolanaWallet;
      final address = wallet?.isCandidate == true ? wallet!.address : null;
      final type = Theme.of(context).textTheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            18,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Add money', style: type.headlineMedium),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: ShapeDecoration(
                  color: const Color(0xFFF3F2F6),
                  shape: productSquircle(20),
                ),
                child: Row(
                  children: [
                    for (final card in [false, true])
                      Expanded(
                        child: Semantics(
                          selected: _card == card,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _card = card;
                              _message = null;
                            }),
                            child: AnimatedContainer(
                              duration: productDuration(context, 200),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: ShapeDecoration(
                                color: _card == card
                                    ? Colors.white
                                    : Colors.transparent,
                                shape: productSquircle(16),
                                shadows: _card == card
                                    ? [
                                        const BoxShadow(
                                          color: Color(0x12000000),
                                          offset: Offset(0, 2),
                                          blurRadius: 4,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Text(
                                card ? 'Card' : 'Crypto',
                                textAlign: TextAlign.center,
                                style: type.titleMedium,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (address == null) ...[
                const SizedBox(height: 24),
                if (wallet?.status == EmbeddedSolanaWalletStatus.missing) ...[
                  Image.asset(
                    'assets/images/career_world/safe.png',
                    height: 110,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A wallet for your money',
                    textAlign: TextAlign.center,
                    style: type.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy || !widget.account.canSetUpWallet
                        ? null
                        : _setup,
                    child: Text(_busy ? 'Creating…' : 'Create wallet'),
                  ),
                ] else
                  const Center(child: TrimmyLiquidMark(size: 64)),
              ] else if (_card &&
                  PracticeAccountConfig.fromEnvironment().apiUri != null)
                CrossmintOnrampForm(
                  account: widget.account,
                  origin: PracticeAccountConfig.fromEnvironment().apiUri!,
                  onTransfer: () => setState(() => _card = false),
                )
              else ...[
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFF2F7F4),
                      shape: productSquircle(28),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 250),
                      child: QrImageView(
                        key: const ValueKey('wallet-deposit-qr'),
                        data: address,
                        version: QrVersions.auto,
                        padding: const EdgeInsets.all(18),
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF225B48),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: Color(0xFF225B48),
                        ),
                        semanticsLabel: 'Solana deposit address $address',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Solana',
                  textAlign: TextAlign.center,
                  style: type.titleLarge,
                ),
                const SizedBox(height: 5),
                Semantics(
                  label: address,
                  child: Text(
                    shortenAddress(address),
                    textAlign: TextAlign.center,
                    style: type.bodyMedium,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'USDC or SOL · Solana network only',
                  textAlign: TextAlign.center,
                  style: type.bodySmall,
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const ValueKey('copy-deposit-address'),
                  onPressed: () => _copy(address),
                  icon: Icon(
                    _copied ? Icons.done_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(_copied ? 'Copied' : 'Copy address'),
                ),
              ],
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!, style: type.bodyMedium),
                ),
            ],
          ),
        ),
      );
    },
  );
}
