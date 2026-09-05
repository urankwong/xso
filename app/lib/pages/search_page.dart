import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show homeTabIndexProvider;
import '../providers/search_providers.dart';
import '../providers/data_providers.dart';
import '../providers/player_providers.dart';

const _typeLabels = {
  SourceType.magnet: '磁力',
  SourceType.ed2k: 'ed2k',
  SourceType.pan: '网盘',
  SourceType.music: '音乐',
  SourceType.book: '书籍',
  SourceType.game: '游戏',
};

const _typeIcons = {
  SourceType.magnet: Icons.link,
  SourceType.ed2k: Icons.alternate_email,
  SourceType.pan: Icons.cloud_outlined,
  SourceType.music: Icons.music_note,
  SourceType.book: Icons.menu_book_outlined,
  SourceType.game: Icons.sports_esports_outlined,
};

const _providerLabels = {
  'baidu': '百度网盘',
  'quark': '夸克网盘',
  'aliyun': '阿里云盘',
  'pan123': '123 云盘',
  'xunlei': '迅雷云盘',
};

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  SourceType? _filter;

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
    final hasSources = ref.watch(searchableSourcesProvider).value?.isNotEmpty == true;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索磁力 / 网盘 / 音乐…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _controller.clear();
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _submit),
        ],
      ),
      body: session == null
          ? _EmptyState(hasSources: hasSources, onGoSources: () {
              ref.read(homeTabIndexProvider.notifier).state = 1;
            })
          : _ResultsView(
              session: session,
              filter: _filter,
              onFilterChanged: (t) => setState(() => _filter = t),
              onGoSources: () {
                ref.read(homeTabIndexProvider.notifier).state = 1;
              },
            ),
    );
  }
}

/// 空态：引导导入源
class _EmptyState extends StatelessWidget {
  final bool hasSources;
  final VoidCallback onGoSources;
  const _EmptyState({required this.hasSources, required this.onGoSources});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.travel_explore, size: 72, color: scheme.primary),
          const SizedBox(height: 16),
          Text('聚合搜索', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            hasSources ? '输入关键词，多源并发搜索、流式出结果' : '先导入搜索源，才能开始搜索',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (!hasSources)
            FilledButton.icon(
              onPressed: onGoSources,
              icon: const Icon(Icons.extension),
              label: const Text('去导入源'),
            )
          else
            OutlinedButton.icon(
              onPressed: onGoSources,
              icon: const Icon(Icons.extension),
              label: const Text('管理源'),
            ),
        ],
      ),
    );
  }
}

/// 结果视图：状态条 + 类型筛选 + 分组卡片
class _ResultsView extends StatelessWidget {
  final SearchSession session;
  final SourceType? filter;
  final ValueChanged<SourceType?> onFilterChanged;
  final VoidCallback onGoSources;
  const _ResultsView({
    required this.session,
    required this.filter,
    required this.onFilterChanged,
    required this.onGoSources,
  });

  @override
  Widget build(BuildContext context) {
    final done = session.statusBySource.values
        .where((s) => s == SourceStatus.done)
        .length;
    final failedIds = session.statusBySource.entries
        .where((e) => e.value == SourceStatus.failed)
        .map((e) => e.key)
        .toList();
    final total = session.statusBySource.length;

    // 应用类型筛选
    final groups = <String, List<SearchResult>>{};
    session.resultsBySource.forEach((sourceId, results) {
      final filtered =
          filter == null ? results : results.where((r) => r.type == filter).toList();
      if (filtered.isNotEmpty) groups[sourceId] = filtered;
    });
    final sourceIds = groups.keys.toList();

    final presentTypes = session.resultsBySource.values
        .expand((r) => r.map((e) => e.type))
        .toSet();

    return Column(
      children: [
        // 类型筛选 chips
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('全部'),
                  selected: filter == null,
                  onSelected: (_) => onFilterChanged(null),
                  showCheckmark: false,
                ),
              ),
              for (final t in presentTypes)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: Icon(_typeIcons[t] ?? Icons.circle, size: 16),
                    label: Text(_typeLabels[t] ?? t.name),
                    selected: filter == t,
                    onSelected: (_) => onFilterChanged(t),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        // 状态条
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              if (!session.finished)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(session.finished && sourceIds.isEmpty && done == 0
                    ? Icons.info_outline
                    : Icons.check_circle_outline,
                    size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.finished
                      ? '完成：$done/$total 源成功'
                      : '搜索中…（$done/$total 源成功）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (failedIds.isNotEmpty)
                Tooltip(
                  message: '失败源：${failedIds.join('、')}',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Text('${failedIds.length} 源失败',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ),
            ],
          ),
        ),
        Expanded(
          child: session.finished && sourceIds.isEmpty
              ? _NoResult(onGoSources: onGoSources)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: sourceIds.length,
                  itemBuilder: (context, index) {
                    final sourceId = sourceIds[index];
                    return _SourceGroup(
                        sourceId: sourceId, results: groups[sourceId]!);
                  },
                ),
        ),
      ],
    );
  }
}

class _NoResult extends StatelessWidget {
  final VoidCallback onGoSources;
  const _NoResult({required this.onGoSources});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 60, color: scheme.outline),
          const SizedBox(height: 12),
          const Text('没有搜到结果'),
          const SizedBox(height: 6),
          Text('试试换个关键词，或检查源是否可用',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onGoSources,
            icon: const Icon(Icons.build_circle_outlined, size: 18),
            label: const Text('检查源'),
          ),
        ],
      ),
    );
  }
}

class _SourceGroup extends StatelessWidget {
  final String sourceId;
  final List<SearchResult> results;
  const _SourceGroup({required this.sourceId, required this.results});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.rss_feed, size: 16,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(results.first.sourceName,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Text('${results.length} 条',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          ...results.map((r) => _ResultTile(result: r)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final SearchResult result;
  const _ResultTile({required this.result});

  bool get _isPlayable =>
      result.type == SourceType.music &&
      result.url.startsWith('http') &&
      !result.needsDetail;

  void _play(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final player = container.read(playerProvider);
    player.play(
      url: result.url,
      title: result.title,
      artist: result.extra?['artist'],
    );
  }

  String get _subtitle {
    final bits = <String>[];
    if (result.extractCode != null) bits.add('提取码 ${result.extractCode}');
    final size = result.extra?['size'] ?? '';
    if (size.isNotEmpty) bits.add(size);
    final date = result.extra?['date'] ?? '';
    if (date.isNotEmpty) bits.add(date);
    final artist = result.extra?['artist'] ?? '';
    if (artist.isNotEmpty) bits.add(artist);
    if (bits.isEmpty && result.url.isNotEmpty) bits.add(result.url);
    return bits.join(' · ');
  }

  void _openDetailSheet(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final assembler = container.read(sourceAssemblerProvider).value;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => FutureBuilder<List<SearchResult>>(
        future: assembler?.fetchDetail(result.sourceId, result),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return SizedBox(
                height: 150,
                child: Center(
                    child: Text('详情获取失败：${snap.error}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))));
          }
          final links = snap.data ?? [];
          if (links.isEmpty) {
            return const SizedBox(
                height: 120, child: Center(child: Text('详情页未识别到网盘链接')));
          }
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(result.title,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                ...links.map((l) => ListTile(
                      leading: Icon(_typeIcons[SourceType.pan],
                          color: Theme.of(context).colorScheme.primary),
                      title: Text(
                        _providerLabels[l.extra?['provider']] ?? l.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(l.extractCode != null
                          ? '提取码 ${l.extractCode} · ${l.url}'
                          : l.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          tooltip: '复制',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text: CopyLinkAction().clipboardContent(l)));
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制链接和提取码')));
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.open_in_new, size: 20),
                          tooltip: '打开',
                          onPressed: () {
                            launchUrl(Uri.parse(l.url),
                                mode: LaunchMode.externalApplication);
                          },
                        ),
                      ]),
                    )),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: scheme.primary.withValues(alpha: 0.12),
        child: Icon(
          result.needsDetail
              ? Icons.open_in_full
              : (_typeIcons[result.type] ?? Icons.link),
          size: 18,
          color: scheme.primary,
        ),
      ),
      title: Text(result.title,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: _subtitle.isEmpty
          ? null
          : Text(_subtitle,
              maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: result.needsDetail
          ? Icon(Icons.chevron_right, color: scheme.onSurfaceVariant)
          : PopupMenuButton<String>(
              onSelected: (action) async {
                switch (action) {
                  case 'play':
                    _play(context);
                  case 'copy':
                    await Clipboard.setData(ClipboardData(
                        text: CopyLinkAction().clipboardContent(result)));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('已复制')));
                    }
                  case 'open':
                    final uri = Uri.parse(result.url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
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
              itemBuilder: (_) => [
                if (_isPlayable)
                  const PopupMenuItem(value: 'play', child: Text('播放')),
                const PopupMenuItem(value: 'copy', child: Text('复制链接')),
                const PopupMenuItem(value: 'open', child: Text('打开')),
                const PopupMenuItem(value: 'favorite', child: Text('收藏')),
              ],
            ),
      onTap: result.needsDetail
          ? () => _openDetailSheet(context)
          : (_isPlayable ? () => _play(context) : null),
    );
  }
}
