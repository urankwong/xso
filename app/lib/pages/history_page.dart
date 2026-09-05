import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_providers.dart';
import '../providers/search_providers.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  Future<void> _reload() async => setState(() {});

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDbProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史'),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                await db.historyDao.clear();
                await _reload();
              }),
        ],
      ),
      body: FutureBuilder(
        future: db.historyDao.all(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('暂无搜索历史'));
          }
          return ListView(
            children: items
                .map((h) => ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(h.keyword),
                      onTap: () async {
                        await ref
                            .read(searchSessionProvider.notifier)
                            .search(h.keyword);
                        if (mounted) {
                          // 回到搜索页查看结果
                          DefaultTabController.maybeOf(context);
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
