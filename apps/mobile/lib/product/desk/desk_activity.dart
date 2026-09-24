import 'package:flutter/material.dart';
import '../market/paper_portfolio.dart';
import '../design/product_theme.dart';
import '../design/product_motion_icon.dart';
import '../community/community.dart';

class DeskActivity extends StatelessWidget {
  const DeskActivity({
    super.key,
    required this.orders,
    required this.onOpenAsset,
    this.community,
    this.onCommunity,
    this.preview = true,
  });
  final List<PaperPortfolioOrder> orders;
  final ValueChanged<String> onOpenAsset;
  final CommunityRepository? community;
  final VoidCallback? onCommunity;
  final bool preview;
  @override
  Widget build(BuildContext context) {
    final sorted = [...orders]
      ..sort((a, b) => b.committedAt.compareTo(a.committedAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your activity',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('Your first trade starts the story.'),
          ),
        for (final order in preview ? sorted.take(3) : sorted)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 38,
              height: 38,
              decoration: ShapeDecoration(
                color: const Color(0xFFF1ECFC),
                shape: productSquircle(13),
              ),
              child: Icon(
                order.action == 'buy'
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
                color: ProductColor.violet,
                size: 20,
              ),
            ),
            title: Text(
              '${order.action == 'buy' ? 'Bought' : 'Sold'} ${order.symbol}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text('${order.quantity} shares'),
            trailing: Text(
              '${order.committedAt.toLocal().day}/${order.committedAt.toLocal().month}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: () => onOpenAsset(order.assetId),
          ),
        if (onCommunity != null) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Community',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              TextButton(onPressed: onCommunity, child: const Text('Open')),
            ],
          ),
          if (community != null)
            _CommunityPreview(repository: community!, onOpen: onCommunity!)
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const ProductMotionIcon(file: 'career-comments.png'),
              title: const Text('See what traders are saying'),
              onTap: onCommunity,
            ),
        ],
      ],
    );
  }
}

class _CommunityPreview extends StatefulWidget {
  const _CommunityPreview({required this.repository, required this.onOpen});
  final CommunityRepository repository;
  final VoidCallback onOpen;
  @override
  State<_CommunityPreview> createState() => _CommunityPreviewState();
}

class _CommunityPreviewState extends State<_CommunityPreview> {
  late Future<CommunityPageData> _read = widget.repository.read('everyone');
  @override
  void didUpdateWidget(_CommunityPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _read = widget.repository.read('everyone');
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CommunityPageData>(
    future: _read,
    builder: (context, snapshot) {
      final posts = snapshot.data?.posts ?? const <CommunityPost>[];
      if (posts.isEmpty) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const ProductMotionIcon(file: 'career-comments.png'),
          title: Text(
            snapshot.hasError
                ? 'Community couldn’t load'
                : snapshot.connectionState == ConnectionState.waiting
                ? 'Opening community…'
                : 'Start a conversation',
          ),
          subtitle: const Text('Public comments from other traders.'),
          onTap: widget.onOpen,
        );
      }
      return Column(
        children: [
          for (final post in posts.take(2))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const ProductMotionIcon(file: 'career-comments.png'),
              title: Text(
                '${post.handle.isEmpty ? 'A trader' : '@${post.handle}'} on \$${post.symbol}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                post.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: widget.onOpen,
            ),
        ],
      );
    },
  );
}
