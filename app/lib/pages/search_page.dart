import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/search_providers.dart';
import '../providers/data_providers.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      ref.read(searchSessionProvider.notifier).search(_controller.text);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(searchSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索资源（网盘/磁力/ed2k…）',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _submit),
        ],
      ),
      body: session == null
          ? const Center(child: Text('输入关键词开始搜索\n（请先在源管理页导入源）',
              textAlign: TextAlign.center))
          : _ResultsView(session: session),
    );
  }
}

class _ResultsView extends StatelessWidget {
  final SearchSession session;
  const _ResultsView({required this.session});

  @override
  Widget build(BuildContext context) {
    final okCount = session.statusBySource.values
        .where((s) => s == SourceStatus.done)
        .length;
    final failedCount = session.statusBySource.values
        .where((s) => s == SourceStatus.failed)
        .length;
    final totalCount = session.statusBySource.length;
    final resultSources = session.resultsBySource.keys.toList();

    return ListView.builder(
      itemCount: resultSources.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            dense: true,
            title: Text(
              session.finished
                  ? '完成：$okCount/$totalCount 源成功'
                  : '搜索中…（$okCount/$totalCount 源成功）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            subtitle: failedCount > 0
                ? Text('$failedCount 源失败',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error))
                : null,
          );
        }
        final sourceId = resultSources[index - 1];
        final results = session.resultsBySource[sourceId]!;
        return _SourceGroup(sourceId: sourceId, results: results);
      },
    );
  }
}

class _SourceGroup extends StatelessWidget {
  final String sourceId;
  final List<SearchResult> results;
  const _SourceGroup({required this.sourceId, required this.results});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(results.first.sourceName,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        ...results.map((r) => _ResultTile(result: r)),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  final SearchResult result;
  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(result.title),
      subtitle: result.extractCode != null
          ? Text('提取码: ${result.extractCode}')
          : (result.extra?['size'] != null && result.extra!['size']!.isNotEmpty
              ? Text(result.extra!['size']!)
              : null),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          switch (action) {
            case 'copy':
              await Clipboard.setData(
                  ClipboardData(text: CopyLinkAction().clipboardContent(result)));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已复制')));
              }
            case 'open':
              final uri = Uri.parse(result.url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('无法打开该链接')));
              }
            case 'favorite':
              final container = ProviderScope.containerOf(context);
              final db = container.read(appDbProvider);
              await db.favoriteDao.add(result);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已收藏')));
              }
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'copy', child: Text('复制链接')),
          PopupMenuItem(value: 'open', child: Text('打开')),
          PopupMenuItem(value: 'favorite', child: Text('收藏')),
        ],
      ),
    );
  }
}
