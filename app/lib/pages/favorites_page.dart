import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/data_providers.dart';
import '../providers/engine_providers.dart';

class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDbProvider);
    final checking = ValueNotifier<bool>(false);

    Future<void> checkAll() async {
      checking.value = true;
      try {
        final checker = ref.read(livenessCheckerProvider);
        final items = await db.favoriteDao.all();
        for (final f in items) {
          final dead = await checker.check(f.url);
          await db.favoriteDao.markDead(f.id, dead: dead);
        }
      } finally {
        checking.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: checking,
            builder: (_, running, __) => IconButton(
              icon: running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: running ? null : checkAll,
              tooltip: '批量活性检测',
            ),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: db.favoriteDao.watchAll(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_border, size: 60,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('暂无收藏'),
                  const SizedBox(height: 6),
                  Text('搜索结果的菜单里可以收藏',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12)),
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
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12),
                    child: Icon(
                      Icons.cloud_outlined,
                      size: 18,
                      color: f.isDead
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: Text(f.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: f.isDead
                          ? const TextStyle(
                              color: Colors.red,
                              decoration: TextDecoration.lineThrough)
                          : null),
                  subtitle: Text(
                    f.extractCode != null
                        ? '提取码 ${f.extractCode} · ${f.url}'
                        : f.url,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
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
                        onPressed: () => db.favoriteDao.remove(f.id),
                      ),
                    ],
                  ),
                  onTap: () async {
                    final uri = Uri.parse(f.url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
