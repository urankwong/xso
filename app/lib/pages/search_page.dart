import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/search_providers.dart';
import '../providers/data_providers.dart';
import '../providers/dht_providers.dart';
import 'source_manage_page.dart';
import '../providers/player_providers.dart';
import '../providers/player_provider.dart' show QueueItem, playbackHeaders;
import '../providers/downloads.dart';
import '../providers/lyric.dart' show parseQualities;
import '../widgets/download_confirm.dart';
import 'album_page.dart';
import 'book_detail_page.dart';
import 'mv_page.dart';

/// 单曲下载（多音质时弹选择）
///
/// MusicFree 插件的搜索结果普遍不带直链，`url` 常常是空的，
/// 必须先用插件的 getMediaSource 解析出真实地址再入队，否则下载的只是空串。
Future<void> downloadMusic(BuildContext context, WidgetRef ref,
    {required String url,
    required String title,
    String? artist,
    String? sourceId,
    SearchResult? result,
    Map<String, String>? extra,
    DownloadKind kind = DownloadKind.music}) async {
  var target = url;
  // 同播放：插件来源即使带 url 也要重新解析，否则会下载到无效内容
  final fromPlugin = (result?.extra?['__item'] ?? '').isNotEmpty;
  if ((fromPlugin || !target.startsWith('http')) &&
      sourceId != null &&
      result != null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在解析下载地址…')));
    }
    try {
      final assembler = await ref.read(sourceAssemblerProvider.future);
      target = await assembler.resolveMedia(sourceId, result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载地址解析失败：$e')));
      }
      return;
    }
  }
  if (!target.startsWith('http')) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该来源没有可下载的直链')));
    }
    return;
  }
  // 解析地址可能经过了 await，用前先确认 context 仍然有效
  if (!context.mounted) return;
  final qualities = parseQualities(extra);
  // 下载前确认：无论音质档数都先弹统一确认面板（可在设置里关闭）。
  // 原实现只有 qualities.length>1 才弹，0/1 档源直接入队 → 用户感知为「秒下、无确认」。
  String? label;
  if (await downloadConfirmEnabled()) {
    label = await showDownloadConfirm(
      context,
      kind: kind,
      title: title,
      artist: artist,
      qualities: qualities,
    );
    if (label == null) return; // 用户取消
    if (!context.mounted) return;
  } else {
    label = qualities.isEmpty ? '默认音质' : qualities.first.name;
  }
  final added = await ref.read(downloadsProvider).enqueue(
        url: target,
        title: title,
        artist: artist,
        qualityLabel: label ?? '默认音质',
        subDir: subDirOfKind(kind),
        // 同样要带取流请求头，否则下载下来的也是 403 页面
        headers: playbackHeaders(result?.extra ?? extra),
      );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added ? '已加入下载队列（“下载”页可看进度）' : '该文件已在下载队列中')));
  }
}

const _typeLabels = {
  SourceType.magnet: '磁力',
  SourceType.ed2k: '电驴',
  SourceType.pan: '网盘',
  SourceType.music: '音乐',
  SourceType.audiobook: '有声播客',
  // novel（Legado 文本型源 = 网文小说）与 book（电子书文件，zlib/安娜）
  // 是两类东西：前者"追更阅读"，后者"下载文件"，必须分开标注
  SourceType.novel: '小说',
  SourceType.book: '书籍',
  // Legado 图片型/视频型书源：阅读生态里漫画与影视都是一等公民
  SourceType.comic: '漫画',
  SourceType.video: '影视',
  SourceType.game: '游戏',
};

const _typeIcons = {
  SourceType.magnet: Icons.attractions,
  // 不能和磁力同图标：结果列表里两者会完全无法区分
  // （与源管理页 _typeIcons 的 ed2k 图标保持一致）
  SourceType.ed2k: Icons.alternate_email,
  SourceType.pan: Icons.cloud,
  SourceType.music: Icons.music_note,
  SourceType.audiobook: Icons.podcasts,
  // 小说用"打开的书"，书籍用"书签/书架"，视觉上可区分
  SourceType.novel: Icons.auto_stories,
  SourceType.book: Icons.menu_book,
  SourceType.comic: Icons.collections_bookmark,
  SourceType.video: Icons.movie,
  SourceType.game: Icons.sports_esports,
};

const _providerLabels = {
  'baidu': '百度网盘',
  'quark': '夸克网盘',
  'aliyun': '阿里云盘',
  'pan123': '123 云盘',
  'xunlei': '迅雷云盘',
};

/// 标题中匹配关键词高亮（不区分大小写），返回 TextSpan 供 RichText 使用
TextSpan _highlightTitle(
    String title, String keyword, TextStyle baseStyle, Color highlightColor) {
  if (keyword.isEmpty || title.isEmpty) {
    return TextSpan(text: title, style: baseStyle);
  }
  final lower = title.toLowerCase();
  final kw = keyword.toLowerCase();
  final spans = <TextSpan>[];
  var start = 0;
  while (true) {
    final idx = lower.indexOf(kw, start);
    if (idx < 0) {
      if (start < title.length) {
        spans.add(TextSpan(text: title.substring(start), style: baseStyle));
      }
      break;
    }
    if (idx > start) {
      spans.add(TextSpan(text: title.substring(start, idx), style: baseStyle));
    }
    spans.add(TextSpan(
      text: title.substring(idx, idx + kw.length),
      style: baseStyle.copyWith(
          color: highlightColor, fontWeight: FontWeight.bold),
    ));
    start = idx + kw.length;
  }
  return TextSpan(children: spans);
}

/// 类型徽章色：全部由 ColorScheme 派生（primary/error/tertiary 调和），不硬编码外部色值
Color _typeColor(ColorScheme scheme, SourceType type) => switch (type) {
      SourceType.music => scheme.primary,
      SourceType.pan => scheme.tertiary, // 蓝紫系容器色
      SourceType.magnet ||
      SourceType.ed2k => Color.lerp(scheme.error, scheme.tertiary, 0.35)!, // 橙红系
      SourceType.book => Color.lerp(scheme.tertiary, scheme.primary, 0.45)!, // 紫系
      // 小说（Legado 文本型源）：与书籍同族但偏暖，避免与"电子书文件"混淆
      SourceType.novel => Color.lerp(scheme.tertiary, scheme.secondary, 0.5)!,
      SourceType.game => scheme.secondary,
      SourceType.audiobook => Color.lerp(scheme.secondary, scheme.tertiary, 0.4)!,
      // 漫画（Legado 图片型书源）：与书籍同族但用偏暖的橙系区分
      SourceType.comic => Color.lerp(scheme.error, scheme.secondary, 0.35)!,
      // 影视（Legado 视频型书源）：贴近 error 色，与磁力/电驴的下载类区分开
      SourceType.video => Color.lerp(scheme.error, scheme.primary, 0.25)!,
    };

/// 类型 chips 顺序：全部 → 内容类（音乐/有声/小说/书籍/漫画/影视）
/// → 下载类（网盘/磁力/电驴）→ 游戏（预留）。
///
/// 注意：chips 用 `Wrap` 渲染（见 `_TypeChips`）。此前是横向 ListView，
/// 只露出前 5 项，书籍/漫画等被挤到屏外，用户根本不知道可以横滑。
const _chipOrder = <SourceType?>[
  null,
  SourceType.music,
  SourceType.audiobook,
  SourceType.novel,
  SourceType.book,
  SourceType.comic,
  SourceType.video,
  SourceType.pan,
  SourceType.magnet,
  SourceType.ed2k,
  SourceType.game, // 预留：禁用态
];

/// 切换类型筛选。
/// 已经搜过关键词时用新类型**重新搜索**：只过滤旧结果的话，
/// 用户切到没参与上一次搜索的类型只会看到空白，与「筛选」的预期不符。
void _applyTypeFilter(WidgetRef ref, SourceType? type) {
  if (ref.read(searchTypeFilterProvider) == type) return;
  ref.read(searchTypeFilterProvider.notifier).set(type);
  final session = ref.read(searchSessionProvider);
  if (session != null && session.keyword.isNotEmpty) {
    ref.read(searchSessionProvider.notifier).search(session.keyword);
  }
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    // 只在「空 ↔ 非空」切换时刷新，避免每敲一个字都重建整个结果列表
    _controller.addListener(() {
      final v = _controller.text.isNotEmpty;
      if (v != _hasText) setState(() => _hasText = v);
    });
    // 提前创建 DHT 客户端并后台预热：它靠查询过程逐步积累路由表，
    // 不预热的话用户第一次点「查询做种情况」只问到几个节点就误判"暂无做种"
    ref.read(dhtClientProvider);

    // 首页"最近搜索"等入口：回填关键词并自动搜索一次（消费后置空）
    ref.listenManual(pendingSearchKeywordProvider, (prev, next) {
      if (next == null || next.isEmpty) return;
      _controller.text = next;
      ref.read(pendingSearchKeywordProvider.notifier).state = null;
      _submit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // 收起键盘：否则软键盘会盖住大半个结果列表
    FocusManager.instance.primaryFocus?.unfocus();
    // 新搜索要清掉来源筛选：源集合可能变了，旧筛选指向的源未必还在
    ref.read(searchSourceFilterProvider.notifier).state = null;
    ref.read(searchSessionProvider.notifier).search(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(searchSessionProvider);
    final hasSources =
        ref.watch(searchableSourcesProvider).value?.isNotEmpty == true;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索磁力 / 网盘 / 音乐…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _hasText
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: '清空',
                      onPressed: () {
                        _controller.clear();
                      },
                    )
                  : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(onPressed: _submit, child: const Text('搜索')),
          ),
        ],
      ),
      body: Column(
        children: [
          _TypeChips(),
          Expanded(
            child: session == null
                ? _EmptyState(hasSources: hasSources, onGoSources: _goSources)
                : _ResultsView(
                    session: session,
                    onRetry: _submit,
                    onGoSources: _goSources,
                  ),
          ),
        ],
      ),
    );
  }

  // 跳源管理：直接推全屏页面（源管理已并入"我的"Tab）
  void _goSources() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SourceManagePage()),
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
          Text('汇搜', style: Theme.of(context).textTheme.headlineSmall),
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

/// 类型筛选 chips：固定集合，选中态用 primary；游戏预留禁用。
///
/// 用 `Wrap` 自动换行而不是横向滚动：横向滚动会把「书籍/漫画/影视」
/// 等类型挤到屏幕外，用户看不到也想不到要横滑（实测只露出前 5 项）。
class _TypeChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(searchTypeFilterProvider);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final t in _chipOrder)
            FilterChip(
              label: Text(t == null ? '全部' : _typeLabels[t]!),
              selected: filter == t,
              selectedColor: scheme.primary.withValues(alpha: 0.18),
              checkmarkColor: scheme.primary,
              // 全局主题把 chip 的勾选标记关掉了，这里必须显式打开：
              // 否则选中态只剩 18% 底色差异，几乎看不出当前选的是哪个类型
              showCheckmark: true,
              visualDensity: VisualDensity.compact,
              onSelected: t == SourceType.game
                  ? null // 游戏源类型预留
                  : (_) => _applyTypeFilter(ref, t),
            ),
        ],
      ),
    );
  }
}

/// 结果视图：统计行 + 二次检索 + 来源健康条 + 聚合混排信息流
class _ResultsView extends ConsumerStatefulWidget {
  final SearchSession session;
  final VoidCallback onRetry;
  final VoidCallback onGoSources;
  const _ResultsView({
    required this.session,
    required this.onRetry,
    required this.onGoSources,
  });

  @override
  ConsumerState<_ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends ConsumerState<_ResultsView> {
  static const _pageSize = 50;
  int _visibleCount = _pageSize;
  String _lastKeyword = '';

  @override
  void didUpdateWidget(covariant _ResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.keyword != _lastKeyword) {
      _lastKeyword = widget.session.keyword;
      _visibleCount = _pageSize;
    }
  }

  /// 各源结果按轮次交错排列 + 按标题去重。
  ///
  /// 原实现是「源 A 的全部 → 源 B 的全部」，谁先返回谁占满首屏：
  /// 实测搜 adele 时前 7 条全来自同一个源，用户看不到其他源的结果，
  /// 也感受不到「多源聚合」的价值。交错后每屏都能看到多个来源。
  List<SearchResult> _flat(String? sourceFilter) {
    final groups = <List<SearchResult>>[];
    widget.session.resultsBySource.forEach((id, results) {
      if (sourceFilter != null && id != sourceFilter) return;
      groups.add(List<SearchResult>.of(results));
    });
    final out = <SearchResult>[];
    var round = 0;
    var added = true;
    while (added) {
      added = false;
      for (final g in groups) {
        if (round < g.length) {
          out.add(g[round]);
          added = true;
        }
      }
      round++;
    }
    // 去重：按标题（不区分大小写）保留首次出现
    final seen = <String>{};
    return out.where((r) {
      final key = r.title.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();
  }

  /// 来源展示名：优先用结果里带的 sourceName，查不到再退回源 id
  String _sourceNameOf(String id) {
    final first = widget.session.resultsBySource[id]?.firstOrNull;
    if (first != null && first.sourceName.isNotEmpty) return first.sourceName;
    return id;
  }

  /// 解析 extra 中的日期为 YYYYMMDD 可比较字符串
  String _dateOf(SearchResult r) {
    final raw = r.extra?['date'] ?? '';
    if (raw.isEmpty) return '';
    final m = RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(raw);
    if (m != null) {
      return '${m.group(1)!}${m.group(2)!.padLeft(2, '0')}${m.group(3)!.padLeft(2, '0')}';
    }
    return raw;
  }

  /// 解析 extra 中的大小为字节数
  int _sizeOf(SearchResult r) {
    final raw = r.extra?['size'] ?? '';
    if (raw.isEmpty) return 0;
    final m = RegExp(r'([\d.]+)\s*([KMGT]?B)', caseSensitive: false)
        .firstMatch(raw);
    if (m != null) {
      final v = double.tryParse(m.group(1)!) ?? 0;
      final unit = m.group(2)!.toUpperCase();
      return (v * switch (unit) {
            'KB' => 1024,
            'MB' => 1024 * 1024,
            'GB' => 1024 * 1024 * 1024,
            'TB' => 1024 * 1024 * 1024 * 1024,
            _ => 1,
          }).round();
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(searchTypeFilterProvider);
    final sortMode = ref.watch(searchSortModeProvider);
    final sourceFilter = ref.watch(searchSourceFilterProvider);
    final inResult = ref.watch(searchInResultProvider);
    final scheme = Theme.of(context).colorScheme;

    var all = _flat(sourceFilter);
    List<SearchResult> flat =
        filter == null ? all : all.where((r) => r.type == filter).toList();

    // 二次检索：前端过滤
    if (inResult.isNotEmpty) {
      final kw = inResult.toLowerCase();
      flat = flat.where((r) => r.title.toLowerCase().contains(kw)).toList();
    }

    // 排序
    if (sortMode == SearchSortMode.type) {
      flat = [...flat]..sort((a, b) => a.type.name.compareTo(b.type.name));
    } else if (sortMode == SearchSortMode.time) {
      flat = [...flat]..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    } else if (sortMode == SearchSortMode.size) {
      flat = [...flat]..sort((a, b) => _sizeOf(b).compareTo(_sizeOf(a)));
    }

    final done = widget.session.statusBySource.values
        .where((s) => s == SourceStatus.done)
        .length;
    final running = widget.session.statusBySource.values
        .where((s) => s == SourceStatus.running)
        .length;

    final visible = flat.take(_visibleCount).toList();
    final hasMore = flat.length > _visibleCount;

    return Column(
      children: [
        // 统计行 + 排序
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.session.statusBySource.length} 个来源 · ${flat.length} 条结果'
                  '${filter != null && flat.length != all.length ? '（已按${_typeLabels[filter]}筛选）' : ''}'
                  '${sourceFilter != null ? '（仅看：${_sourceNameOf(sourceFilter)}）' : ''}'
                  '${inResult.isNotEmpty ? '（结果中搜：$inResult）' : ''}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (sourceFilter != null)
                InkWell(
                  onTap: () => ref
                      .read(searchSourceFilterProvider.notifier)
                      .state = null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 14, color: scheme.primary),
                        Text('全部来源',
                            style: TextStyle(
                                fontSize: 12, color: scheme.primary)),
                      ],
                    ),
                  ),
                ),
              PopupMenuButton<SearchSortMode>(
                initialValue: sortMode,
                onSelected: (m) =>
                    ref.read(searchSortModeProvider.notifier).state = m,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: SearchSortMode.relevance,
                      child: Text('综合排序')),
                  PopupMenuItem(
                      value: SearchSortMode.type, child: Text('按类型分组')),
                  PopupMenuItem(
                      value: SearchSortMode.time, child: Text('按时间排序')),
                  PopupMenuItem(
                      value: SearchSortMode.size, child: Text('按大小排序')),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        switch (sortMode) {
                          SearchSortMode.relevance => '综合排序',
                          SearchSortMode.type => '按类型分组',
                          SearchSortMode.time => '按时间',
                          SearchSortMode.size => '按大小',
                        },
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.primary)),
                    Icon(Icons.keyboard_arrow_down,
                        size: 16, color: scheme.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 二次检索输入框
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: SizedBox(
            height: 36,
            child: TextField(
              decoration: InputDecoration(
                hintText: '在结果中筛选…',
                prefixIcon:
                    const Icon(Icons.filter_alt_outlined, size: 18),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              ),
              onChanged: (v) =>
                  ref.read(searchInResultProvider.notifier).state = v,
            ),
          ),
        ),
        // 来源健康条
        _HealthBar(
          session: widget.session,
          onRetry: widget.onRetry,
          selected: sourceFilter,
          onToggle: (id) =>
              ref.read(searchSourceFilterProvider.notifier).state = id,
        ),
        Expanded(
          child: flat.isEmpty
              ? (all.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('该类型下暂无结果',
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => _applyTypeFilter(ref, null),
                            child: const Text('清除类型筛选'),
                          ),
                        ],
                      ),
                    )
                  : widget.session.finished && done == 0
                      ? _NoResult(onGoSources: widget.onGoSources)
                      : _Searching(session: widget.session))
              : _buildList(visible, flat.length, hasMore, running,
                  sortMode, scheme),
        ),
      ],
    );
  }

  Widget _buildList(
    List<SearchResult> visible,
    int total,
    bool hasMore,
    int running,
    SearchSortMode sortMode,
    ColorScheme scheme,
  ) {
    // 按类型分组：在类型边界插入标题分隔器
    final items = <_DisplayItem>[];
    if (sortMode == SearchSortMode.type) {
      final groups = <SourceType, List<SearchResult>>{};
      for (final r in visible) {
        groups.putIfAbsent(r.type, () => []).add(r);
      }
      for (final entry in groups.entries) {
        items.add(_DisplayItem.header(entry.key));
        for (final r in entry.value) {
          items.add(_DisplayItem.result(r));
        }
      }
    } else {
      for (final r in visible) {
        items.add(_DisplayItem.result(r));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) {
          return _buildFooter(hasMore, running, total, scheme);
        }
        final item = items[index];
        if (item.isHeader) {
          return _GroupHeader(type: item.headerType!);
        }
        return _ResultTile(
            result: item.result!, keyword: widget.session.keyword);
      },
    );
  }

  Widget _buildFooter(
      bool hasMore, int running, int total, ColorScheme scheme) {
    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: OutlinedButton(
            onPressed: () => setState(() => _visibleCount += _pageSize),
            child: Text('加载更多（共 $total 条）'),
          ),
        ),
      );
    }
    if (running > 0) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('正在从 $running 个来源获取…',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text('已展示全部 $total 条结果',
            style: TextStyle(color: scheme.outline, fontSize: 12)),
      ),
    );
  }
}

/// 分组展示项：结果或类型标题
class _DisplayItem {
  final SearchResult? result;
  final SourceType? headerType;
  _DisplayItem.result(this.result) : headerType = null;
  _DisplayItem.header(this.headerType) : result = null;
  bool get isHeader => headerType != null;
}

/// 类型分组标题分隔器
class _GroupHeader extends StatelessWidget {
  final SourceType type;
  const _GroupHeader({required this.type});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _typeColor(scheme, type);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(_typeIcons[type] ?? Icons.link, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            _typeLabels[type] ?? type.name,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(height: 1, color: color.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }
}

/// 搜索进行中的占位：把「还在搜」和「没结果」区分开，
/// 否则源全部 pending 时是一整片空白，用户无法判断状态。
class _Searching extends ConsumerWidget {
  final SearchSession session;
  const _Searching({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.5),
          const SizedBox(height: 12),
          Text(
            '正在从 ${session.statusBySource.length} 个来源搜索…',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(searchSessionProvider.notifier).cancel(),
            icon: const Icon(Icons.stop, size: 16),
            label: const Text('停止搜索'),
          ),
        ],
      ),
    );
  }
}

/// 来源健康条：每源一个胶囊（正常 ✓ / 失败 ✕ 重试 / 进行中 / 无结果）
class _HealthBar extends ConsumerWidget {
  final SearchSession session;
  final VoidCallback onRetry;

  /// 当前被筛选的 sourceId（null = 全部）
  final String? selected;

  /// 切换来源筛选；传 null 表示取消
  final ValueChanged<String?> onToggle;

  const _HealthBar({
    required this.session,
    required this.onRetry,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (session.statusBySource.isEmpty) return const SizedBox.shrink();
    // 源无结果时拿不到 sourceName，原实现直接显示仓库 id（builtin.pan.cms），
    // 用户看不懂；这里按 id 查一次启用源列表拿展示名
    final names = {
      for (final s in ref.watch(searchableSourcesProvider).value ??
          const <SearchableSource>[])
        s.meta.id: s.meta.name,
    };
    final showFade = session.statusBySource.length > 5;
    return SizedBox(
      height: 34,
      child: Stack(
        children: [
          ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              for (final e in session.statusBySource.entries)
                _HealthCapsule(
                  name: session.resultsBySource[e.key]?.firstOrNull?.sourceName ??
                      names[e.key] ??
                      e.key,
                  status: e.value,
                  message: session.errorsBySource[e.key],
                  onRetry: e.value == SourceStatus.failed ? onRetry : null,
                  count: session.resultsBySource[e.key]?.length,
                  selected: selected == e.key,
                  onToggle: (session.resultsBySource[e.key]?.isNotEmpty ?? false)
                      ? () => onToggle(selected == e.key ? null : e.key)
                      : null,
                ),
            ],
          ),
          if (showFade)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 20,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                        Theme.of(context).colorScheme.surface,
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthCapsule extends StatelessWidget {
  final String name;
  final SourceStatus status;
  final String? message;
  final VoidCallback? onRetry;
  final bool selected;
  final int? count;
  final VoidCallback? onToggle;
  const _HealthCapsule({
    required this.name,
    required this.status,
    this.message,
    this.onRetry,
    this.selected = false,
    this.count,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label, icon) = switch (status) {
      SourceStatus.done => (scheme.primary, '✓', Icons.check_circle,),
      SourceStatus.empty => (scheme.outline, '无结果', Icons.remove_circle_outline),
      SourceStatus.failed => (scheme.error, '✕ 重试', Icons.cancel),
      SourceStatus.running => (scheme.outline, '…', Icons.sync),
    };
    final failed = status == SourceStatus.failed;
    // 有结果的源可以点着筛选；失败的源点着是重试（没结果可筛）
    final tappable = onToggle ?? onRetry;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: tappable,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            // 选中态：实心底色 + 粗边框，一眼能看出当前在看哪个源
            color: selected
                ? scheme.primary.withValues(alpha: 0.24)
                : color.withValues(alpha: 0.10),
            border: Border.all(
                color: selected ? scheme.primary : color.withValues(alpha: 0.5),
                width: selected ? 2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: selected ? scheme.primary : color),
              const SizedBox(width: 4),
              Text(
                  count != null && status == SourceStatus.done
                      ? '$name $count'
                      : '$name $label',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                      color: failed || selected ? color : null)),
              if (selected) ...[
                const SizedBox(width: 2),
                Icon(Icons.close, size: 11, color: color),
              ],
              if (failed && message != null)
                Tooltip(
                  message: message!,
                  triggerMode: TooltipTriggerMode.tap,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(Icons.info_outline, size: 12, color: color),
                  ),
                ),
            ],
          ),
        ),
      ),
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

/// 磁力链的 DHT 做种情况。
///
/// 按需触发而不是随列表自动查询：每次查询要向多个节点发 UDP 包、耗时数秒，
/// 几十条结果全查一遍既不现实也费流量。
class _PeerCountTile extends ConsumerStatefulWidget {
  final String url;
  const _PeerCountTile({required this.url});

  @override
  ConsumerState<_PeerCountTile> createState() => _PeerCountTileState();
}

class _PeerCountTileState extends ConsumerState<_PeerCountTile> {
  PeerLookup? _result;
  bool _loading = false;

  Future<void> _query() async {
    if (_loading) return;
    final hash = infoHashFromMagnet(widget.url);
    if (hash == null) return;
    setState(() => _loading = true);
    // 用 App 级单例：引导结果（路由表）复用，不用每次都重新找节点
    final client = ref.read(dhtClientProvider);
    try {
      final r = await client.getPeers(hash);
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const ListTile(
        leading: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
        title: Text('正在向 DHT 网络查询…'),
      );
    }

    final r = _result;
    if (r == null) {
      return ListTile(
        leading: const Icon(Icons.hub_outlined),
        title: const Text('查询做种情况'),
        subtitle: const Text('通过 DHT 网络查询当前有多少 peer',
            style: TextStyle(fontSize: 12)),
        onTap: _query,
      );
    }

    final (IconData, String, Color) state;
    if (r.unknown) {
      state = (Icons.help_outline, '无法连接 DHT 网络，结果未知', scheme.outline);
    } else if (r.peerCount == 0 && r.respondedNodes < 8) {
      // 只问到几个节点就说「没做种」不可靠 —— 路由表还没热起来，
      // 宁可说样本不足，也不能让用户误以为这个种子已经死了
      state = (
        Icons.hourglass_empty,
        '样本不足（仅 ${r.respondedNodes} 个节点响应），建议重查',
        scheme.outline,
      );
    } else if (r.isDead) {
      state = (Icons.hourglass_empty, 'DHT 中暂无做种', scheme.error);
    } else {
      state = (Icons.hub, '${r.peerCount} 个 peer 在做种/下载', scheme.primary);
    }

    return ListTile(
      leading: Icon(state.$1, color: state.$3),
      title: Text(state.$2),
      subtitle: Text('已询问 ${r.respondedNodes} 个节点',
          style: const TextStyle(fontSize: 12)),
      trailing: TextButton(onPressed: _query, child: const Text('重查')),
    );
  }
}

/// 小胶囊徽章：底色 = 类型色 12% 透明，文字 = 类型色
class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

/// 来源徽标：底色胶囊，与类型徽章视觉风格统一
class _SourceBadge extends StatelessWidget {
  final String name;
  const _SourceBadge(this.name);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: scheme.outlineVariant.withValues(alpha: 0.3),
      ),
      child: Text(name,
          style: TextStyle(
              fontSize: 10, color: scheme.onSurfaceVariant)),
    );
  }
}

/// 聚合结果条目：按 type 分形态
class _ResultTile extends ConsumerWidget {
  final SearchResult result;
  final String keyword;
  const _ResultTile({required this.result, this.keyword = ''});

  /// 是否已经是 http 直链。
  /// MusicFree 插件的搜索结果普遍不带直链（url 为空），
  /// 需要调插件的 getMediaSource 现解析，不能直接拿去播。
  bool get _hasDirectUrl => result.url.startsWith('http');

  /// 追加到队列尾部并立即播放；没有直链时先解析。
  ///
  /// 不用 play()：那会用单元素队列替换掉用户正在听的整张专辑/播客，
  /// 浏览结果时误触一下就把当前播放内容清空了。
  Future<void> _play(BuildContext context) async {
    final container = ProviderScope.containerOf(context);
    final player = container.read(playerProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);

    var url = result.url;
    // MusicFree/洛雪源的结果即便带了 url，也常常是页面地址 / 失效直链而非音频流
    // （实测网易云就是这种情况：url 非空但播放器报 Source error）。
    // 只要源给了播放解析句柄，就一律走二次解析取真实地址。
    final extra = result.extra;
    final fromPlugin = (extra?['__item'] ?? '').isNotEmpty ||
        (extra?['__lxItem'] ?? '').isNotEmpty;
    if (fromPlugin || !_hasDirectUrl) {
      messenger?.showSnackBar(const SnackBar(
          content: Text('正在解析播放地址…'), duration: Duration(seconds: 2)));
      try {
        final assembler = await container.read(sourceAssemblerProvider.future);
        url = await assembler.resolveMedia(result.sourceId, result);
      } catch (e) {
        messenger?.showSnackBar(SnackBar(content: Text('播放地址解析失败：$e')));
        return;
      }
    }
    if (!url.startsWith('http')) {
      messenger?.showSnackBar(
          const SnackBar(content: Text('该来源未返回可播放地址')));
      return;
    }

    player.playQueue(
      [
        QueueItem(
          title: result.title,
          artist: result.extra?['artist'] ?? '',
          cover: result.extra?['cover'] ?? '',
          url: url,
          sourceName: result.sourceName,
          sourceId: result.sourceId,
          extra: result.extra,
          headers: playbackHeaders(result.extra),
        ),
      ],
      replace: false,
    );
    messenger?.showSnackBar(const SnackBar(content: Text('已加入播放队列并播放')));
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
                          onPressed: () async {
                            final uri = Uri.parse(l.url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('无法打开该链接')));
                            }
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

  /// 有声播客专辑详情：拉取曲目列表，支持单集点播与整张连播
  void _openAlbumSheet(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final assembler = container.read(sourceAssemblerProvider).value;
    final player = container.read(playerProvider);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => FutureBuilder<List<SearchResult>>(
        future: assembler?.fetchDetail(result.sourceId, result),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return SizedBox(
                height: 170,
                child: Center(
                    child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('专辑曲目获取失败：${snap.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                )));
          }
          final tracks = snap.data ?? [];
          return SafeArea(
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.95,
              builder: (context, scrollController) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Row(children: [
                      if ((result.extra?['cover'] ?? '').startsWith('http'))
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(result.extra!['cover'] ?? '',
                              width: 72, height: 72, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(width: 72, height: 72)),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(result.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold)),
                              if (result.extra?['artist']?.isNotEmpty == true)
                                Text(result.extra!['artist'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                            ]),
                      ),
                    ]),
                  ),
                  if ((result.extra?['desc'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(result.extra!['desc'] ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: tracks.isEmpty
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  Navigator.pop(sheetContext);
                                  messenger.showSnackBar(const SnackBar(
                                      content: Text('正在解析播放地址…'),
                                      duration: Duration(seconds: 2)));
                                  final resolved = <QueueItem>[];
                                  for (final t in tracks) {
                                    try {
                                      final url = await assembler
                                              ?.resolveMedia(
                                                  result.sourceId, t) ??
                                          t.url;
                                      resolved.add(QueueItem(
                                        title: t.title,
                                        artist:
                                            t.extra?['artist'] ?? result.title,
                                        cover: t.extra?['cover'] ??
                                            result.extra?['cover'] ??
                                            '',
                                        url: url,
                                        sourceName: t.sourceName,
                                        sourceId: result.sourceId,
                                        extra: {
                                          ...?t.extra,
                                          'chapter': '1',
                                        },
                                        headers: playbackHeaders(t.extra),
                                      ));
                                    } catch (_) {}
                                  }
                                  if (resolved.isNotEmpty) {
                                    await player.playQueue(resolved);
                                  } else {
                                    messenger.showSnackBar(const SnackBar(
                                        content: Text('未能解析出可播放的曲目')));
                                  }
                                },
                          icon: const Icon(Icons.play_circle_fill),
                          label: const Text('播放全部'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: tracks.isEmpty
                              ? null
                              : () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  var label = '默认音质';
                                  if (await downloadConfirmEnabled()) {
                                    final picked = await showDownloadConfirm(
                                      context,
                                      kind: DownloadKind.audiobook,
                                      title: result.title,
                                      artist: result.extra?['artist'],
                                      qualities: [
                                        (
                                          id: '${tracks.length} 集',
                                          name: '共 ${tracks.length} 集'
                                        )
                                      ],
                                    );
                                    if (picked == null) return;
                                    label = picked;
                                  }
                                  final items = <({
                                    String url,
                                    String title,
                                    String? artist
                                  })>[];
                                  for (final t in tracks) {
                                    try {
                                      final url = await assembler?.resolveMedia(
                                              result.sourceId, t) ??
                                          t.url;
                                      if (!url.startsWith('http')) continue;
                                      items.add((
                                        url: url,
                                        title: t.title,
                                        artist: t.extra?['artist'] ?? result.title,
                                      ));
                                    } catch (_) {}
                                  }
                                  if (items.isEmpty) {
                                    messenger.showSnackBar(const SnackBar(
                                        content: Text('没有可下载的直链')));
                                    return;
                                  }
                                  final n = await container
                                      .read(downloadsProvider)
                                      .enqueueAll(items,
                                          qualityLabel: label,
                                          subDir: 'Audiobook');
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                  messenger.showSnackBar(SnackBar(
                                      content: Text(n > 0
                                          ? '已加入下载队列 $n 集'
                                          : '这些内容已在队列中')));
                                },
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('下载全部'),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: tracks.isEmpty
                        ? const Center(child: Text('专辑下没有可播放的曲目'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: tracks.length,
                            itemBuilder: (context, i) {
                              final t = tracks[i];
                              return ListTile(
                                dense: true,
                                leading: Text('${i + 1}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                                title: Text(t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: t.extra?['artist']?.isNotEmpty == true
                                    ? Text(t.extra!['artist'] ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)
                                    : null,
                                onTap: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  try {
                                    final url = await assembler?.resolveMedia(
                                            result.sourceId, t) ??
                                        t.url;
                                    if (!url.startsWith('http')) {
                                      messenger.showSnackBar(const SnackBar(
                                          content: Text('该集暂无可播放地址')));
                                      return;
                                    }
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }
                                    await player.play(
                                      url: url,
                                      title: t.title,
                                      artist: t.extra?['artist'] ??
                                          result.extra?['artist'],
                                      cover: t.extra?['cover'] ??
                                          result.extra?['cover'],
                                      extra: {
                                        ...?t.extra,
                                        'chapter': '1',
                                      },
                                      sourceName: t.sourceName,
                                    );
                                  } catch (e) {
                                    messenger.showSnackBar(SnackBar(
                                        content: Text('播放地址解析失败：$e')));
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 链接类（磁力/ed2k/网盘直链）点击菜单：复制链接 / 打开
  void _showLinkActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(result.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            // 只有磁力链才有 infohash，才查得了 DHT
            if (infoHashFromMagnet(result.url) != null)
              _PeerCountTile(url: result.url),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制链接'),
              onTap: () {
                Clipboard.setData(ClipboardData(
                    text: CopyLinkAction().clipboardContent(result)));
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已复制链接')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(sheetContext);
                final uri = Uri.parse(result.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                } else {
                  messenger.showSnackBar(
                      const SnackBar(content: Text('无法打开该链接')));
                }
              },
            ),
            // 与 ⋮ 菜单保持一致：点条目弹出的面板原先没有收藏，
            // 想收藏必须先精准点中右侧那个很小的 ⋮
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('收藏'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final db =
                    ProviderScope.containerOf(context).read(appDbProvider);
                await db.favoriteDao.add(result);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已收藏')));
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 音乐条目是否只能当链接处理。
  /// 判定必须比"是不是 http 开头"更宽：洛雪等源的 url 是**非空占位值**，
  /// 原写法 (url.isEmpty || _hasDirectUrl) 会把这类条目踢去链接菜单，
  /// 绕过了本可以救活它们的二次解析。
  bool get _musicOnlyAsLink {
    final u = result.url;
    if (u.isEmpty || u.startsWith('http')) return false;
    // 还带得回解析句柄（MusicFree 的 __item / 洛雪的 __lxItem）就别当链接
    final hasHandle = (result.extra?['__item'] ?? '').isNotEmpty ||
        (result.extra?['__lxItem'] ?? '').isNotEmpty;
    return !hasHandle;
  }

  void _onTap(BuildContext context) => switch (result.type) {
        // 音乐：有直链直接播，没有直链走插件解析；
        // 只有落到了 magnet/ed2k 之类的非 http 协议才当作链接处理
        SourceType.music =>
            _musicOnlyAsLink ? _showLinkActions(context) : _play(context),
        // 有声播客单集：_isPlayable 只认 music 类型，对 audiobook 恒为 false，
        // 导致单集点了完全没有反应。统一走解析播放。
        SourceType.audiobook => result.needsDetail
            ? _openAlbumSheet(context)
            : _play(context),
        SourceType.pan => result.needsDetail
            ? _openDetailSheet(context)
            : _showLinkActions(context),
        SourceType.magnet || SourceType.ed2k => _showLinkActions(context),
        // 小说 / 漫画 / 影视 / 电子书：统一进详情页。
        // 原先 book 是"直链就下载、否则弹菜单"，但用户点一本书的预期是
        // 看详情（封面/简介/出版社/大小/格式）再决定读还是下，
        // 下载入口仍在右侧 ⋮ 菜单里不受影响。
        SourceType.novel ||
        SourceType.book ||
        SourceType.comic ||
        SourceType.video =>
          _openBookDetail(context),
        _ => _showLinkActions(context),
      };

  /// 打开书籍详情页（小说可在线阅读，电子书看元信息）
  void _openBookDetail(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookDetailPage(result: result),
    ));
  }

  /// 书籍直链下载：落到 Books 目录，文件名后缀用格式标注；下载前弹确认面板。
  Future<void> _downloadBook(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final format = (result.extra?['format'] ?? '文件').toUpperCase();
    if (await downloadConfirmEnabled()) {
      if (!context.mounted) return;
      final ok = await showDownloadConfirm(
        context,
        kind: DownloadKind.book,
        title: result.title,
        artist: result.extra?['author'],
        qualities: [(id: format, name: format)],
      );
      if (ok == null) return;
    }
    final added = await ProviderScope.containerOf(context)
        .read(downloadsProvider)
        .enqueue(
              url: result.url,
              title: result.title,
              artist: result.extra?['author'],
              album: result.extra?['publisher'],
              qualityLabel: format,
              subDir: 'Books',
            );
    messenger.showSnackBar(SnackBar(
        content: Text(added ? '已加入下载队列：${result.title}' : '该任务已在队列中')));
  }

  List<String> get _subtitleBits {
    final bits = <String>[];
    final extra = result.extra;
    switch (result.type) {
      case SourceType.music:
        final artist = extra?['artist'] ?? '';
        if (artist.isNotEmpty) bits.add(artist);
        final album = extra?['album'] ?? '';
        if (album.isNotEmpty) bits.add(album);
      case SourceType.pan:
        if (result.extractCode != null) bits.add('提取码 ${result.extractCode}');
      case SourceType.book:
        final a = extra?['author'] ?? '';
        if (a.isNotEmpty) bits.add(a);
        final pv = [(extra?['publisher'] ?? ''), (extra?['year'] ?? '')]
            .where((e) => e.isNotEmpty)
            .join(' · ');
        if (pv.isNotEmpty) bits.add(pv);
        final fmt = extra?['format'] ?? '';
        if (fmt.isNotEmpty) bits.add(fmt.toUpperCase());
        final lang = extra?['language'] ?? '';
        if (lang.isNotEmpty) bits.add(lang);
        final bsize = extra?['size'] ?? '';
        if (bsize.isNotEmpty) bits.add(bsize);
        if (bits.isEmpty && result.url.isNotEmpty) bits.add(result.url);
        return bits;
      default:
        break;
    }
    final size = extra?['size'] ?? '';
    if (size.isNotEmpty) bits.add(size);
    final date = extra?['date'] ?? '';
    if (date.isNotEmpty) bits.add(date);
    final author = extra?['author'] ?? '';
    if (author.isNotEmpty) bits.add(author);
    if (bits.isEmpty && result.url.isNotEmpty) bits.add(result.url);
    return bits;
  }

  /// 音乐副标题：专辑名可点，进入专辑页拉取整张曲目
  Widget _musicSubtitle(BuildContext context, ColorScheme scheme) {
    final album = result.extra?['album'] ?? '';
    final others = _subtitleBits.where((b) => b != album).toList();
    final parts = <InlineSpan>[];
    if (others.isNotEmpty) {
      parts.add(TextSpan(text: others.join(' · ')));
      if (album.isNotEmpty) parts.add(const TextSpan(text: ' · '));
    }
    if (album.isNotEmpty) {
      parts.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AlbumPage(
                sourceId: result.sourceId,
                sourceName: result.sourceName,
                albumName: album,
                artist: result.extra?['artist'],
              ),
            ),
          ),
          child: Text(
            album,
            style: TextStyle(
              color: scheme.primary,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
            ),
          ),
        ),
      ));
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: parts,
      ),
    );
  }

  /// 音质徽章文案：取 qualities 首个的 name（无则不显示）
  String? get _qualityLabel {
    if (result.type != SourceType.music) return null;
    final qualities = parseQualities(result.extra);
    return qualities.isEmpty ? null : qualities.first.name;
  }

  Widget _leading(ColorScheme scheme) => switch (result.type) {
        SourceType.music => _musicLeading(scheme),
        SourceType.pan => _iconContainer(scheme, result.type),
        SourceType.magnet ||
        SourceType.ed2k =>
          _iconContainer(scheme, result.type),
        SourceType.book => _iconContainer(scheme, result.type),
        _ => _iconContainer(scheme, result.type),
      };

  /// 音乐：圆形封面（extra['cover'] 加载失败回落 icon）
  Widget _musicLeading(ColorScheme scheme) {
    Widget placeholder() => Container(
          width: 44,
          height: 44,
          color: scheme.primary.withValues(alpha: 0.12),
          child: Icon(Icons.music_note, size: 22, color: scheme.primary),
        );
    final cover = result.extra?['cover'];
    if (cover == null || cover.isEmpty) return ClipOval(child: placeholder());
    return ClipOval(
      child: Image.network(
        cover,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        cacheWidth: 88,
        cacheHeight: 88,
        errorBuilder: (_, __, ___) => placeholder(),
      ),
    );
  }

  /// 非音乐：圆角方形底色 icon 容器
  Widget _iconContainer(ColorScheme scheme, SourceType type) {
    final color = _typeColor(scheme, type);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.12),
      ),
      child: Icon(_typeIcons[type] ?? Icons.link, size: 22, color: color),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bits = _subtitleBits;
    final quality = _qualityLabel;
    // 差异化标签：音乐→音质（上方）；有声→集数/时长；书籍→格式
    String audiobookMeta = '';
    if (result.type == SourceType.audiobook) {
      final ep = result.extra?['episodes'] ??
          result.extra?['chapterCount'] ??
          result.extra?['episodeCount'] ??
          '';
      final dur = result.extra?['duration'] ?? result.extra?['time'] ?? '';
      audiobookMeta =
          [if (ep.isNotEmpty) '$ep 集', if (dur.isNotEmpty) dur].join(' · ');
    }
    final bookFormat = result.type == SourceType.book
        ? (result.extra?['format'] ?? '').toUpperCase()
        : '';
    return ListTile(
      leading: _leading(scheme),
      title: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: _highlightTitle(
          result.title,
          keyword,
          const TextStyle(fontWeight: FontWeight.w500),
          scheme.primary,
        ),
      ),
      isThreeLine: false,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bits.isNotEmpty)
            (result.type == SourceType.music &&
                    (result.extra?['album']?.isNotEmpty ?? false))
                ? _musicSubtitle(context, scheme)
                : Text(bits.join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              _Badge(_typeLabels[result.type] ?? result.type.name,
                  _typeColor(scheme, result.type)),
              if (quality != null)
                _Badge(quality, scheme.primary),
              if (audiobookMeta.isNotEmpty)
                _Badge(audiobookMeta, _typeColor(scheme, SourceType.audiobook)),
              if (bookFormat.isNotEmpty)
                _Badge(bookFormat, _typeColor(scheme, SourceType.book)),
              if ((result.extra?['bvid'] ?? '').isNotEmpty)
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          MvPage(bvid: result.extra!['bvid']!, title: result.title),
                    ),
                  ),
                  child: _Badge('MV', const Color(0xFFFF5D8F)),
                ),
              _SourceBadge(result.sourceName),
            ],
          ),
        ],
      ),
      trailing: result.needsDetail
          ? Icon(Icons.chevron_right, color: scheme.onSurfaceVariant)
          : PopupMenuButton<String>(
              onSelected: (action) async {
                switch (action) {
                  case 'play':
                    await _play(context);
                  case 'download':
                    await downloadMusic(context, ref,
                        url: result.url,
                        title: result.title,
                        artist: result.extra?['artist'],
                        sourceId: result.sourceId,
                        result: result,
                        extra: result.extra);
                  case 'audiobook_download':
                    await downloadMusic(context, ref,
                        url: result.url,
                        title: result.title,
                        artist: result.extra?['artist'] ??
                            result.extra?['author'],
                        sourceId: result.sourceId,
                        result: result,
                        extra: result.extra,
                        kind: DownloadKind.audiobook);
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
                // 音乐即使没有直链也可以「解析后播放/下载」，
                // 不能因为 url 为空就把这两个入口藏掉
                if (result.type == SourceType.music) ...[
                  const PopupMenuItem(value: 'play', child: Text('播放')),
                  const PopupMenuItem(value: 'download', child: Text('下载')),
                ],
                // 有声单集（非专辑/系列）也可解析后下载，落到 Audiobook 目录
                if (result.type == SourceType.audiobook &&
                    !result.needsDetail) ...[
                  const PopupMenuItem(value: 'play', child: Text('播放')),
                  const PopupMenuItem(
                      value: 'audiobook_download', child: Text('下载')),
                ],
                if (result.url.isNotEmpty) ...[
                  const PopupMenuItem(value: 'copy', child: Text('复制链接')),
                  const PopupMenuItem(value: 'open', child: Text('打开')),
                ],
                const PopupMenuItem(value: 'favorite', child: Text('收藏')),
              ],
            ),
      onTap: () => _onTap(context),
    );
  }
}
