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
            return const Center(child: Text('暂无收藏（搜索结果菜单里可收藏）'));
          }
          return ListView(
            children: items
                .map((f) => ListTile(
                      title: Text(f.title,
                          style: f.isDead
                              ? const TextStyle(
                                  color: Colors.red,
                                  decoration: TextDecoration.lineThrough)
                              : null),
                      subtitle: Text(f.url,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (f.extractCode != null) Text('码: ${f.extractCode}'),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
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
                      onLongPress: () async {
                        await Clipboard.setData(ClipboardData(
                            text: '${f.url} 提取码: ${f.extractCode ?? ''}'));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制')));
                        }
                      },
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
