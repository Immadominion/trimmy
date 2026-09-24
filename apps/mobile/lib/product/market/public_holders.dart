import '../../ui_review/review_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/product_empty_state.dart';
import '../design/product_notice.dart';
import '../../ui_review/review_animated_splash.dart';
import 'market_craft.dart';
import 'stock_facts.dart';

abstract interface class PublicHoldersReader {
  Future<PublicHoldersPage> holders(String mint);
}

class PublicHolder {
  const PublicHolder(this.owner, this.primaryDomain, this.amount);
  final String owner, amount;
  final String? primaryDomain;
  String get shortAddress =>
      '${owner.substring(0, 4)}…${owner.substring(owner.length - 4)}';
}

class PublicHoldersPage {
  const PublicHoldersPage(
    this.mint,
    this.observedAt,
    this.sampledAccounts,
    this.holders,
  );
  final String mint;
  final DateTime observedAt;
  final int sampledAccounts;
  final List<PublicHolder> holders;
  factory PublicHoldersPage.fromJson(Object? data) {
    Never invalid() =>
        throw const StockFactsException(StockFactsFailure.invalidResponse);
    bool address(Object? v) =>
        v is String && RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(v);
    if (data is! Map<String, dynamic> ||
        data['schemaVersion'] != 1 ||
        data['network'] != 'solana-mainnet' ||
        data['scope'] != 'largest-20-token-accounts' ||
        data['complete'] != false ||
        !address(data['mint'])) {
      invalid();
    }
    final rows = data['holders'];
    final count = data['sampledAccounts'];
    final time = DateTime.tryParse(
      data['observedAt'] is String ? data['observedAt'] as String : '',
    );
    if (rows is! List ||
        rows.length > 20 ||
        count is! int ||
        count < 0 ||
        count > 20 ||
        rows.length > count ||
        time == null) {
      invalid();
    }
    final seen = <String>{};
    final holders = <PublicHolder>[];
    for (final row in rows) {
      if (row is! Map ||
          !address(row['owner']) ||
          !seen.add(row['owner'] as String) ||
          row['amount'] is! String ||
          !RegExp(
            r'^\d{1,22}(?:\.\d{1,18})?$',
          ).hasMatch(row['amount'] as String) ||
          (row['primaryDomain'] != null &&
              (row['primaryDomain'] is! String ||
                  (row['primaryDomain'] as String).length > 68))) {
        invalid();
      }
      holders.add(
        PublicHolder(
          row['owner'] as String,
          row['primaryDomain'] as String?,
          row['amount'] as String,
        ),
      );
    }
    return PublicHoldersPage(
      data['mint'] as String,
      time,
      count,
      List.unmodifiable(holders),
    );
  }
}

class PublicHoldersView extends StatefulWidget {
  const PublicHoldersView({
    super.key,
    required this.mint,
    required this.reader,
  });
  final String? mint;
  final PublicHoldersReader? reader;
  @override
  State<PublicHoldersView> createState() => _PublicHoldersViewState();
}

class _PublicHoldersViewState extends State<PublicHoldersView> {
  PublicHoldersPage? _page;
  bool _loading = true;
  int _generation = 0;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PublicHoldersView old) {
    super.didUpdateWidget(old);
    if (old.mint != widget.mint || old.reader != widget.reader) {
      _page = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final mint = widget.mint;
      final reader = widget.reader;
      if (mint == null || reader == null) throw StateError('Unavailable');
      final page = await reader.holders(mint);
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: TrimmyLiquidMark(size: 56),
        ),
      );
    }
    final page = _page;
    if (page == null) {
      return ProductEmptyState(
        title: 'Holders couldn’t load',
        message: 'Try again in a moment.',
        action: TextButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (page.holders.isEmpty) {
      return const ProductEmptyState(title: 'No holders to show');
    }
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final rowHeight = 56.0 * scale.clamp(1, 4);
    final visible = page.holders.length.clamp(1, 6);
    return Material(
      key: const ValueKey('public-holders-panel'),
      color: const Color(0xFFF7F7FA),
      shape: marketSquircle(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Holder',
                    style: TextStyle(color: MarketPalette.muted, fontSize: 12),
                  ),
                ),
                const Text(
                  'Tokens',
                  style: TextStyle(color: MarketPalette.muted, fontSize: 12),
                ),
                Tooltip(
                  message:
                      'Balances from the largest ${page.sampledAccounts} token accounts. Not the full holder list.',
                  triggerMode: TooltipTriggerMode.tap,
                  child: const SizedBox(
                    width: 32,
                    height: 40,
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: MarketPalette.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: (rowHeight * visible).clamp(
              0,
              MediaQuery.sizeOf(context).height * .48,
            ),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: page.holders.length > visible,
              radius: const Radius.circular(8),
              thickness: 3,
              child: ListView.builder(
                key: const ValueKey('public-holders-scroll'),
                controller: _scroll,
                primary: false,
                padding: const EdgeInsets.only(bottom: 6),
                itemCount: page.holders.length,
                itemBuilder: (context, index) {
                  final holder = page.holders[index];
                  return InkWell(
                    onTap: () => _copy(holder),
                    child: SizedBox(
                      height: rowHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    holder.primaryDomain ?? holder.shortAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (holder.primaryDomain != null)
                                    Text(
                                      holder.shortAddress,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: MarketPalette.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Tooltip(
                                message: holder.amount,
                                child: Text(
                                  _quantity(holder.amount),
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(PublicHolder holder) async {
    await Clipboard.setData(ClipboardData(text: holder.owner));
    if (!mounted) return;
    if (ReviewFeedback.shared.haptics) {
      HapticFeedback.selectionClick();
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: ProductNotice(
          message: 'Address copied',
          onDismiss: () => messenger.hideCurrentSnackBar(),
        ),
      ),
    );
  }

  String _quantity(String value) {
    final number = double.parse(value);
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(2)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(2)}K';
    if (number != 0 && number < .001) return '<0.001';
    return number.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
