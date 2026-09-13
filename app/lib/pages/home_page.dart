import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';
import '../main.dart' show homeTabIndexProvider;
import '../providers/data_providers.dart';
import '../providers/search_providers.dart';
import 'source_manage_page.dart';

/// 首页·发现：内容宫格 + 源状态 + 最近搜索
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  /// 写入搜索页类型筛选并清空当前结果（不自动发起搜索）
  void _applyTypeFilter(WidgetRef ref, SourceType? type) {
    ref.read(searchTypeFilterProvider.notifier).set(type);
    ref.read(searchSessionProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sources =
        ref.watch(searchableSourcesProvider).value ?? const <SearchableSource>[];

    // 按源类型统计启用源数量
    final counts = <SourceType, int>{};
    for (final s in sources) {
      counts[s.meta.type] = (counts[s.meta.type] ?? 0) + 1;
    }

    // 顺序与搜索页类型 chips 保持一致。注意 novel（Legado 文本型源=网文小说）
    // 与 book（电子书文件，zlib/安娜）是两个不同分类：
    // 若这里只放"书籍"，点进来会按 book 筛选，而内置的 legado 源全是 novel，
    // 结果是筛出 0 个源、看起来像功能坏了。
    final entries = [
      const _Entry('音乐', Icons.music_note, SourceType.music),
      const _Entry('有声播客', Icons.podcasts, SourceType.audiobook),
      const _Entry('小说', Icons.auto_stories, SourceType.novel),
      const _Entry('书籍', Icons.menu_book, SourceType.book),
      const _Entry('漫画', Icons.collections_bookmark, SourceType.comic),
      const _Entry('网盘', Icons.cloud, SourceType.pan),
      const _Entry('磁力', Icons.attractions, SourceType.magnet),
      const _Entry('电驴', Icons.link, SourceType.ed2k),
      const _Entry('游戏', Icons.sports_esports, SourceType.game,
          comingSoon: true),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            // 顶部大标题
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child:
                  Text('发现', style: Theme.of(context).textTheme.headlineMedium),
            ),
            // 内容入口宫格：列数随屏宽自适应，宽屏（平板/横屏）下不再 3 列失衡
            LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              final columns = w >= 900
                  ? 6
                  : w >= 640
                      ? 5
                      : w >= 420
                          ? 4
                          : 3;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: [
                  for (final e in entries)
                    _EntryCard(
                      entry: e,
                      count: counts[e.type] ?? 0,
                      // 「即将上线」才是真正的禁用态；「0 个源」是可补救状态，
                      // 点了要说明原因并给导入入口，不能静默无反应
                      // （电驴目前就是 0 个源，不提示用户只会以为按钮坏了）
                      onTap: e.comingSoon
                          ? null
                          : () {
                              final count = counts[e.type] ?? 0;
                              if (count == 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('「${e.label}」暂无可用源'),
                                    action: SnackBarAction(
                                      label: '去导入',
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const SourceManagePage()),
                                      ),
                                    ),
                                  ),
                                );
                                return;
                              }
                              _applyTypeFilter(ref, e.type);
                              ref.read(homeTabIndexProvider.notifier).state = 1;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        '已切换到「${e.label}」，输入关键词开始搜索')),
                              );
                            },
                    ),
                ],
              );
            }),
            const SizedBox(height: 8),
            // 源状态卡片：只陈述可确认的事实（启用数量）。
            // 原实现恒定显示「全部正常」，但没有真实健康检测，属于误导；
            // 点击也只切到「我的」Tab，与入口语义不符，改为直接进源管理。
            Card(
              child: ListTile(
                leading:
                    Icon(Icons.monitor_heart_outlined, color: scheme.primary),
                title: const Text('源状态'),
                subtitle: Text(
                  sources.isEmpty
                      ? '尚未启用任何源，去导入吧'
                      : '已启用 ${sources.length} 个源 · 点击查看/管理',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SourceManagePage()),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 最近搜索
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history, size: 18, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text('最近搜索',
                            style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _RecentSearches(onPick: (keyword) {
                      // 回填关键词到搜索框并自动搜索一次
                      ref.read(searchTypeFilterProvider.notifier).set(null);
                      ref.read(searchSessionProvider.notifier).clear();
                      ref.read(pendingSearchKeywordProvider.notifier).state =
                          keyword;
                      ref.read(homeTabIndexProvider.notifier).state = 1;
                    }),
                  ],
                ),
              ),
            ),
            // TODO(P3): 最近播放（播放记录落盘后实现）
          ],
        ),
      ),
    );
  }
}

class _Entry {
  final String label;
  final IconData icon;
  final SourceType? type;
  final bool comingSoon;
  const _Entry(this.label, this.icon, this.type, {this.comingSoon = false});
}

class _EntryCard extends StatelessWidget {
  final _Entry entry;
  final int count;
  final VoidCallback? onTap;
  const _EntryCard({required this.entry, required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 0 个源是「可补救」状态：文案直接给出下一步动作，而不是只报一个数字
    final subtitle = entry.comingSoon
        ? '即将上线'
        : (count > 0 ? '$count 个源' : '暂无源·去导入');
    final enabled = !entry.comingSoon && count > 0;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(entry.icon,
                  size: 30, color: enabled ? scheme.primary : scheme.outline),
              const SizedBox(height: 8),
              Text(entry.label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 最近搜索：流式读取历史库，空态给引导文案
class _RecentSearches extends ConsumerWidget {
  final ValueChanged<String> onPick;
  const _RecentSearches({required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDbProvider);
    return StreamBuilder(
      stream: db.historyDao.watchAll(),
      builder: (context, snapshot) {
        // 首帧数据未到时不渲染，避免「还没有搜索记录」闪一下又被列表顶掉
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 24);
        }
        final items = (snapshot.data ?? const <History>[])
            .map((h) => h.keyword)
            .take(10)
            .toList();
        if (items.isEmpty) {
          return Text(
            '还没有搜索记录，去搜索页试试吧',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final keyword in items)
              ActionChip(
                label: Text(keyword),
                onPressed: () => onPick(keyword),
              ),
          ],
        );
      },
    );
  }
}
