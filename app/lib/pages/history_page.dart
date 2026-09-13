import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart' show homeTabIndexProvider;
import '../providers/data_providers.dart';
import '../providers/search_providers.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  /// 清空是不可恢复操作，先确认再执行
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空搜索历史'),
        content: const Text('将删除全部搜索记录，且不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(appDbProvider).historyDao.clear();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDbProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史'),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空历史',
              onPressed: () => _confirmClear(context, ref)),
        ],
      ),
      body: StreamBuilder(
        stream: db.historyDao.watchAll(),
        builder: (context, snapshot) {
          // 首帧数据未到时显示加载，避免先闪一下「暂无搜索历史」
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 60, color: scheme.outline),
                  const SizedBox(height: 12),
                  const Text('暂无搜索历史'),
                  const SizedBox(height: 6),
                  Text('搜索过的关键词会出现在这里',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView(
            children: items
                .map((h) => ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(h.keyword),
                      onTap: () async {
                        // 必须先切到搜索 Tab：结果渲染在搜索页，
                        // 只 pop 回首页容器的话用户仍停在「我的」，看不到任何变化
                        ref.read(homeTabIndexProvider.notifier).state = 1;
                        await ref
                            .read(searchSessionProvider.notifier)
                            .search(h.keyword);
                        if (context.mounted) {
                          Navigator.popUntil(context, (r) => r.isFirst);
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
