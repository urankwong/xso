import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/data_providers.dart';
import '../providers/dht_providers.dart';
import '../providers/engine_providers.dart';
import 'book_detail_page.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  /// 批量检测的状态必须挂在 State 上。
  /// 原先在 build() 里 new ValueNotifier，收藏流一刷新就重建，
  /// 检测还在跑、转圈却消失了，用户会误以为已经结束。
  bool _checking = false;
  int _checked = 0;
  int _total = 0;
  bool _canceled = false;

  /// 类型筛选（存 SourceType.name；null = 全部）
  String? _filterType;

  Future<void> _checkAll() async {
    if (_checking) return;
    final db = ref.read(appDbProvider);
    final items = await db.favoriteDao.all();
    if (items.isEmpty || !mounted) return;

    setState(() {
      _checking = true;
      _canceled = false;
      _checked = 0;
      _total = items.length;
    });

    final checker = ref.read(livenessCheckerProvider);
    // 同时准备 DHT 客户端（首次 read 会后台预热路由表）
    final dht = ref.read(dhtClientProvider);
    for (final f in items) {
      if (_canceled) break;
      bool dead;
      final hash = infoHashFromMagnet(f.url);
      if (hash != null) {
        // 磁力链必须用 DHT 判活。走 HTTP 的话 fetcher 请求不了 magnet:
        // 会直接抛异常，原实现会把它一律判成"已失效"。
        final r = await dht.getPeers(hash);
        assert(() {
          // ignore: avoid_print
          print('[FavoriteCheck] DHT "${f.title}" peers=${r.peerCount} '
              'responded=${r.respondedNodes} → '
              '${r.unknown ? "未知(保守判活)" : (r.isDead ? "判失效" : "判有效")}');
          return true;
        }());
        // 网络不通时保守判活：不能因为查不到就告诉用户链接死了
        dead = r.unknown ? false : r.isDead;
      } else {
        // 网盘等仍走页面探测 + 失效特征判定
        dead = await checker.check(f.url);
      }
      await db.favoriteDao.markDead(f.id, dead: dead);
      if (!mounted) return;
      setState(() => _checked++);
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _confirmDelete(int id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏'),
        content: Text('确定删除「$title」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(appDbProvider).favoriteDao.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDbProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏'),
        actions: [
          if (_checking)
            TextButton(
              onPressed: () => setState(() => _canceled = true),
              child: const Text('停止'),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _checkAll,
              tooltip: '批量活性检测',
            ),
        ],
      ),
      body: Column(
        children: [
          // 检测进度：逐条串行请求，没有进度用户不知道还要等多久
          if (_checking)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '正在检测 $_checked/$_total…',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder(
                stream: db.favoriteDao.watchAll(),
                builder: (context, snapshot) {
                  // 首帧数据未到时显示加载，避免先闪一下「暂无收藏」
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snapshot.data ?? [];
                  // 类型筛选：收藏此前完全没有分类，音乐/小说/磁力混在一个列表里
                  final items = _filterType == null
                      ? all
                      : all.where((f) => f.type == _filterType).toList();
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star_border, size: 60, color: scheme.outline),
                        const SizedBox(height: 12),
                        const Text('暂无收藏'),
                        const SizedBox(height: 6),
                        Text('搜索结果的菜单里可以收藏',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final f = items[i];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 17,
                          backgroundColor: f.isDead
                              ? scheme.errorContainer
                              : _typeColor(scheme, f.type)
                                  .withValues(alpha: 0.14),
                          child: Icon(
                            _typeIcon(f.type),
                            size: 18,
                            color: f.isDead
                                ? scheme.error
                                : _typeColor(scheme, f.type),
                          ),
                        ),
                        title: Text(f.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: f.isDead
                                // 用主题色而非硬编码红色，深色模式下对比度才可控
                                ? TextStyle(
                                    color: scheme.error,
                                    decoration: TextDecoration.lineThrough)
                                : null),
                        subtitle: Text(
                          f.extractCode != null
                              ? '提取码 ${f.extractCode} · ${f.url}'
                              : f.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20),
                              tooltip: '复制',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(
                                    text:
                                        '${f.url} 提取码: ${f.extractCode ?? ''}'));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('已复制')));
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: '删除',
                              onPressed: () => _confirmDelete(
                                  f.id, f.title.isEmpty ? f.url : f.title),
                            ),
                          ],
                        ),
                        onTap: () => _onTapFavorite(f),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 类型识别与点击分发 ──────────────────────────────────────────

  /// 收藏记录的 type 存的是 SourceType.name 字符串
  SourceType _typeOf(Favorite f) => SourceType.values.firstWhere(
        (t) => t.name == f.type,
        // 老数据可能没有 type：按 url 协议兜底推断，不要再一律当网盘
        orElse: () {
          final u = f.url;
          if (u.startsWith('magnet:')) return SourceType.magnet;
          if (u.startsWith('ed2k:')) return SourceType.ed2k;
          return SourceType.pan;
        },
      );

  IconData _typeIcon(String type) {
    switch (type) {
      case 'novel':
        return Icons.auto_stories;
      case 'book':
        return Icons.menu_book;
      case 'comic':
        return Icons.collections_bookmark;
      case 'video':
        return Icons.movie;
      case 'music':
        return Icons.music_note;
      case 'audiobook':
        return Icons.podcasts;
      case 'magnet':
        return Icons.attractions;
      case 'ed2k':
        return Icons.alternate_email;
      case 'pan':
      default:
        return Icons.cloud_outlined;
    }
  }

  Color _typeColor(ColorScheme scheme, String type) {
    switch (type) {
      case 'novel':
        return Color.lerp(scheme.tertiary, scheme.secondary, 0.5)!;
      case 'book':
        return Color.lerp(scheme.tertiary, scheme.primary, 0.45)!;
      case 'comic':
        return Color.lerp(scheme.error, scheme.secondary, 0.35)!;
      case 'video':
        return Color.lerp(scheme.error, scheme.primary, 0.25)!;
      case 'music':
        return scheme.primary;
      case 'audiobook':
        return Color.lerp(scheme.secondary, scheme.tertiary, 0.4)!;
      case 'magnet':
      case 'ed2k':
        return Color.lerp(scheme.error, scheme.tertiary, 0.35)!;
      case 'pan':
      default:
        return scheme.tertiary;
    }
  }

  /// 点击收藏项：**按类型分发**，不再一律 `launchUrl` 跳浏览器。
  ///
  /// 原实现对所有条目都外部打开：小说/书籍跳到浏览器看网页、音乐跳到浏览器
  /// 播放（而非应用内播放），磁力等非 http 协议还会静默失败。
  Future<void> _onTapFavorite(Favorite f) async {
    final type = _typeOf(f);
    final messenger = ScaffoldMessenger.of(context);
    switch (type) {
      case SourceType.novel:
      case SourceType.book:
      case SourceType.comic:
      case SourceType.video:
        // 进详情页：小说可在线阅读，电子书看元信息/下载
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BookDetailPage(
            result: SearchResult(
              sourceId: f.sourceId,
              sourceName: f.sourceName,
              type: type,
              title: f.title,
              url: f.url,
              extractCode: f.extractCode,
            ),
          ),
        ));
      case SourceType.magnet:
      case SourceType.ed2k:
      case SourceType.pan:
      case SourceType.music:
      case SourceType.audiobook:
      case SourceType.game:
        // 这几类先给"复制链接"：磁力/电驴/网盘的打开方式本来就是复制到下载器；
        // 音乐收藏目前只有直链、缺少播放队列上下文，直接播放会在下一轮接入。
        await Clipboard.setData(ClipboardData(
          text: f.extractCode != null
              ? '${f.url} 提取码: ${f.extractCode}'
              : f.url,
        ));
        messenger.showSnackBar(
            const SnackBar(content: Text('已复制链接，可粘贴到对应应用打开')));
    }
  }
