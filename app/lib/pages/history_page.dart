import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_providers.dart';
import '../providers/search_providers.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDbProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史'),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () => db.historyDao.clear()),
        ],
      ),
      body: StreamBuilder(
        stream: db.historyDao.watchAll(),
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
