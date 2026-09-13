import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/data_providers.dart';
import '../providers/dht_providers.dart';
import '../providers/engine_providers.dart';

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
                  final items = snapshot.data ?? [];
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
                              : scheme.primary.withValues(alpha: 0.12),
                          child: Icon(
                            Icons.cloud_outlined,
                            size: 18,
                            color: f.isDead ? scheme.error : scheme.primary,
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
                        onTap: () async {
                          final uri = Uri.parse(f.url);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          } else if (context.mounted) {
                            // 原实现静默失败，用户点了完全没反应
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('无法打开该链接')));
                          }
                        },
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
}
