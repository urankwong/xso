import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/data_providers.dart';
import '../providers/engine_providers.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});
  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  bool _checking = false;

  Future<void> _reload() async => setState(() {});

  Future<void> _checkAll() async {
    setState(() => _checking = true);
    try {
      final db = ref.read(appDbProvider);
      final checker = ref.read(livenessCheckerProvider);
      final items = await db.favoriteDao.all();
      for (final f in items) {
        final dead = await checker.check(f.url);
        await db.favoriteDao.markDead(f.id, dead: dead);
      }
      await _reload();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDbProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏'),
        actions: [
          IconButton(
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _checking ? null : _checkAll,
            tooltip: '批量活性检测',
          ),
        ],
      ),
      body: FutureBuilder(
        future: db.favoriteDao.all(),
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
                      subtitle: Text(f.url),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (f.extractCode != null)
                            Text('码: ${f.extractCode}'),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await db.favoriteDao.remove(f.id);
                              await _reload();
                            },
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
                            text:
                                '${f.url} 提取码: ${f.extractCode ?? ''}'));
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
