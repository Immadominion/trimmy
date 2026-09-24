import '../../ui_review/review_animated_splash.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../account/guest_session.dart';
import '../design/product_theme.dart';
import '../design/product_motion_icon.dart';

class CommunityPost {
  CommunityPost.fromJson(Map<String, dynamic> json)
    : id = json['reasonId'] as String,
      socialId = json['socialId'] as String,
      handle = json['handle'] as String? ?? '',
      persona = json['persona'] as String?,
      assetId = json['assetId'] as String,
      symbol = json['symbol'] as String,
      note = json['note'] as String,
      at = DateTime.parse(json['savedAt'] as String),
      following = json['following'] as bool,
      notifications = json['notifications'] as bool,
      isViewer = json['isViewer'] as bool;
  final String id, socialId, handle, assetId, symbol, note;
  final String? persona;
  final DateTime at;
  final bool following, notifications, isViewer;
}

class CommunityPageData {
  const CommunityPageData(this.posts, this.next);
  final List<CommunityPost> posts;
  final Map<String, String>? next;
}

class CommunityRepository {
  CommunityRepository(this.origin, this.authorization, {http.Client? client})
    : _client = client ?? http.Client() {
    if (origin.scheme != 'https' || origin.userInfo.isNotEmpty) {
      throw ArgumentError('HTTPS API required');
    }
  }
  final Uri origin;
  final Future<PaperAuthorization> Function() authorization;
  final http.Client _client;
  bool _closed = false;
  void close() {
    _closed = true;
    _client.close();
  }

  Future<dynamic> _request(
    String path, {
    Map<String, String>? query,
    Map<String, bool>? body,
  }) async {
    final auth = await authorization();
    if (_closed || auth is! PrivyPaperAuthorization) {
      throw StateError('Account required');
    }
    final request =
        http.Request(
            body == null ? 'GET' : 'PUT',
            origin.resolve(path).replace(queryParameters: query),
          )
          ..followRedirects = false
          ..headers.addAll({
            'authorization': 'Bearer ${auth.token}',
            'accept': 'application/json',
          });
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw StateError('Community unavailable');
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 65536) throw StateError('Invalid response');
    }
    if (_closed) throw StateError('Session changed');
    return jsonDecode(utf8.decode(bytes));
  }

  Future<CommunityPageData> read(
    String scope, {
    Map<String, String>? cursor,
  }) async {
    final json =
        await _request('/v1/community', query: {'scope': scope, ...?cursor})
            as Map<String, dynamic>;
    final posts = (json['items'] as List)
        .map((e) => CommunityPost.fromJson(e as Map<String, dynamic>))
        .toList();
    if (posts.length > 20) throw StateError('Invalid page');
    return CommunityPageData(
      posts,
      json['next'] == null
          ? null
          : Map<String, String>.from(json['next'] as Map),
    );
  }

  Future<void> follow(
    CommunityPost post, {
    required bool following,
    required bool notifications,
  }) async {
    await _request(
      '/v1/community/following/${Uri.encodeComponent(post.socialId)}',
      body: {'following': following, 'notifications': notifications},
    );
  }
}

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    required this.repository,
    required this.onOpenAsset,
    this.initialScope = 'everyone',
    this.onReport,
    this.onBlock,
  });
  final CommunityRepository repository;
  final ValueChanged<String> onOpenAsset;
  final String initialScope;
  final Future<void> Function(CommunityPost)? onReport, onBlock;
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late String _scope = widget.initialScope;
  List<CommunityPost> _posts = [];
  Map<String, String>? _next;
  bool _loading = false;
  String? _error;
  int _generation = 0;
  final Set<String> _busy = {};
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.read(
        _scope,
        cursor: more ? _next : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _posts = more
            ? [
                ..._posts,
                ...page.posts.where(
                  (p) => !_posts.any((old) => old.id == p.id),
                ),
              ]
            : page.posts;
        _next = page.next;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Couldn’t load activity. Try again.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _follow(CommunityPost post, {bool? notify}) async {
    if (!_busy.add(post.socialId)) return;
    setState(() {});
    try {
      await widget.repository.follow(
        post,
        following: notify == null ? !post.following : true,
        notifications: notify ?? true,
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'That change didn’t save. Try again.');
      }
    } finally {
      _busy.remove(post.socialId);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(_scope == 'notifications' ? 'Updates' : 'Community'),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
        children: [
          if (_scope != 'notifications')
            Wrap(
              spacing: 12,
              children: [
                for (final scope in ['everyone', 'following'])
                  TextButton(
                    onPressed: () => setState(() {
                      _scope = scope;
                      _posts = [];
                      unawaited(_load());
                    }),
                    style: TextButton.styleFrom(
                      backgroundColor: _scope == scope
                          ? const Color(0xFFF1ECFC)
                          : Colors.transparent,
                    ),
                    child: Text(scope == 'everyone' ? 'Everyone' : 'Following'),
                  ),
              ],
            ),
          if (_error != null)
            Row(
              children: [
                Expanded(child: Text(_error!)),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          if (_loading && _posts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: TrimmyLiquidMark(size: 88)),
            ),
          if (!_loading && _posts.isEmpty && _error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 55),
              child: Column(
                children: [
                  const ProductMotionIcon(
                    file: 'career-comments.png',
                    size: 54,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _scope == 'notifications'
                        ? 'You’re all caught up'
                        : _scope == 'following'
                        ? 'Your people, here'
                        : 'No shared comments yet',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scope == 'notifications'
                        ? 'New comments from people you follow appear here.'
                        : _scope == 'following'
                        ? 'Follow a trader from Everyone.'
                        : 'Public comments will appear here.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          for (final post in _posts)
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(17),
                decoration: ShapeDecoration(
                  color: const Color(0xFFF8F6FC),
                  shape: productSquircle(25),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: post.persona == null
                              ? const ProductMotionIcon(
                                  file: 'nav-plumpy-profile.png',
                                )
                              : Image.asset(
                                  'assets/images/ui_review/persona-${post.persona}-avatar-v1.png',
                                  errorBuilder: (_, _, _) =>
                                      const ProductMotionIcon(
                                        file: 'nav-plumpy-profile.png',
                                      ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            post.handle.isEmpty ? 'Trader' : '@${post.handle}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (!post.isViewer)
                          TextButton(
                            onPressed: _busy.contains(post.socialId)
                                ? null
                                : () => _follow(post),
                            child: Text(
                              post.following ? 'Following' : '+ Follow',
                            ),
                          ),
                        if (!post.isViewer &&
                            (post.following ||
                                widget.onReport != null ||
                                widget.onBlock != null))
                          PopupMenuButton<String>(
                            tooltip: 'Comment options',
                            onSelected: (value) async {
                              if (value == 'notify') {
                                await _follow(
                                  post,
                                  notify: !post.notifications,
                                );
                              }
                              if (value == 'report' &&
                                  widget.onReport != null) {
                                await widget.onReport!(post);
                                if (mounted) await _load();
                              }
                              if (value == 'block' && widget.onBlock != null) {
                                await widget.onBlock!(post);
                                if (mounted) await _load();
                              }
                            },
                            itemBuilder: (_) => [
                              if (post.following)
                                PopupMenuItem(
                                  value: 'notify',
                                  child: Text(
                                    post.notifications
                                        ? 'Mute updates'
                                        : 'Turn on updates',
                                  ),
                                ),
                              if (!post.isViewer && widget.onReport != null)
                                const PopupMenuItem(
                                  value: 'report',
                                  child: Text('Report'),
                                ),
                              if (!post.isViewer && widget.onBlock != null)
                                const PopupMenuItem(
                                  value: 'block',
                                  child: Text('Block trader'),
                                ),
                            ],
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => widget.onOpenAsset(post.assetId),
                      child: Text('\$${post.symbol}'),
                    ),
                    Text(
                      post.note,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${post.at.toLocal().day}/${post.at.toLocal().month} · ${post.at.toLocal().hour.toString().padLeft(2, '0')}:${post.at.toLocal().minute.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          if (_next != null)
            TextButton(
              onPressed: _loading ? null : () => _load(more: true),
              child: const Text('Load more'),
            ),
        ],
      ),
    ),
  );
}
