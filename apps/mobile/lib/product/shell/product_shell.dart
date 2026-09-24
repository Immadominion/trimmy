import 'dart:async';

import 'package:flutter/material.dart';

import '../design/product_theme.dart';

enum ProductTab { desk, market, floor, profile }

class ProductShell extends StatefulWidget {
  const ProductShell({
    super.key,
    required this.desk,
    required this.market,
    required this.floor,
    required this.profile,
    this.initialTab = ProductTab.desk,
    this.onTabChanged,
  });

  final Widget desk, market, floor, profile;
  final ProductTab initialTab;
  final ValueChanged<ProductTab>? onTabChanged;

  @override
  State<ProductShell> createState() => ProductShellState();
}

class ProductShellState extends State<ProductShell> {
  late var _tab = widget.initialTab;
  ProductTab? _playingIcon;
  Timer? _iconTimer;

  @override
  void initState() {
    super.initState();
    _playIcon(widget.initialTab);
  }

  @override
  void dispose() {
    _iconTimer?.cancel();
    super.dispose();
  }

  void _playIcon(ProductTab tab) {
    _iconTimer?.cancel();
    _playingIcon = tab;
    _iconTimer = Timer(const Duration(milliseconds: 1250), () {
      if (mounted) setState(() => _playingIcon = null);
    });
  }

  ProductTab get selectedTab => _tab;

  void select(ProductTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _playIcon(tab);
    });
    widget.onTabChanged?.call(tab);
  }

  @override
  void didUpdateWidget(covariant ProductShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab &&
        widget.initialTab != _tab) {
      _tab = widget.initialTab;
      _playIcon(_tab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [widget.desk, widget.market, widget.floor, widget.profile];
    return Scaffold(
      body: IndexedStack(
        index: _tab.index,
        children: [
          for (var index = 0; index < pages.length; index++)
            TickerMode(enabled: index == _tab.index, child: pages[index]),
        ],
      ),
      bottomNavigationBar: ColoredBox(
        color: ProductColor.paper,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 73,
            child: Row(
              children: [
                _destination(ProductTab.desk),
                _destination(ProductTab.market),
                _destination(ProductTab.floor),
                _destination(ProductTab.profile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _destination(ProductTab tab) {
    final selected = tab == _tab;
    final label = switch (tab) {
      ProductTab.desk => 'Desk',
      ProductTab.market => 'Market',
      ProductTab.floor => 'Career',
      ProductTab.profile => 'Profile',
    };
    final asset = switch (tab) {
      ProductTab.desk => 'desk',
      ProductTab.market => 'market',
      ProductTab.floor => 'career',
      ProductTab.profile => 'profile',
    };
    final gif =
        (tab == ProductTab.desk || tab == ProductTab.profile) &&
        _playingIcon == tab &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    final marketMotion =
        (tab == ProductTab.market || tab == ProductTab.floor) &&
        _playingIcon == tab &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    final iconFile = tab == ProductTab.market ? 'market-shop' : asset;
    final icon = Image.asset(
      'assets/images/ui_review/icons8/nav-plumpy-$iconFile.${gif ? 'gif' : 'png'}',
      key: ValueKey('nav-$asset-${gif ? 'animated' : 'still'}'),
      width: 30,
      height: 30,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkWell(
          key: ValueKey('product-tab-${tab.name}'),
          onTap: () => select(tab),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.1 : 1,
                duration: productDuration(context, selected ? 280 : 160),
                curve: Curves.easeOutCubic,
                child: marketMotion
                    ? TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: productDuration(context, 430),
                        curve: Curves.easeOutBack,
                        builder: (context, value, child) => Transform.translate(
                          offset: Offset(0, (1 - value) * 5),
                          child: Transform.rotate(
                            angle: (1 - value) * -.08,
                            child: child,
                          ),
                        ),
                        child: icon,
                      )
                    : icon,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? ProductColor.violet : ProductColor.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
