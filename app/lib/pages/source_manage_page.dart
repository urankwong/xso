import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';
import '../providers/engine_providers.dart';
import '../providers/data_providers.dart';
import '../providers/builtin_sources.dart';
import '../providers/plugin_store.dart';
import 'source_config_page.dart';
import 'source_debug_page.dart';

extension _SnackBar on BuildContext {
  void tip(String msg) =>
      ScaffoldMessenger.of(this).showSnackBar(SnackBar(content: Text(msg)));
}

const _typeLabels = {
  'magnet': '磁力',
  'ed2k': '电驴',
  'pan': '网盘',
  'music': '音乐',
  'audiobook': '有声播客',
  // novel = Legado 文本型源（网文小说）；book = 电子书文件（zlib/安娜）
  'novel': '小说',
  'book': '书籍',
  // Legado 图片型/视频型书源
  'comic': '漫画',
  'video': '影视',
  'game': '游戏',
};

/// 筛选 chips 固定顺序；暂无源的类别（书籍/电驴/游戏）显示 0 也保留。
/// game 必须在列内，否则 type=game 的源除「全部」外无法被筛到。
/// comic/video 同理：Legado 书源会产生这两类，不在列内就无法筛到。
const _chipTypes = [
  'music',
  'audiobook',
  'novel',
  'pan',
  'magnet',
  'book',
  'comic',
  'video',
  'ed2k',
  'game',
];

/// 与 main.dart 首启导入共用同一个标记
const _kBuiltinImported = 'builtin_imported';

const _typeIcons = {
  'magnet': Icons.link,
  'ed2k': Icons.alternate_email,
  'pan': Icons.cloud_outlined,
  'music': Icons.music_note,
  'audiobook': Icons.podcasts,
  'novel': Icons.auto_stories,
  'book': Icons.menu_book_outlined,
  'comic': Icons.collections_bookmark,
  'video': Icons.movie,
  'game': Icons.sports_esports_outlined,
};


class SourceManagePage extends ConsumerStatefulWidget {
  const SourceManagePage({super.key});
  @override
  ConsumerState<SourceManagePage> createState() => _SourceManagePageState();
}

class _SourceManagePageState extends ConsumerState<SourceManagePage> {
  List<StoredSource> _sources = [];
  bool _loading = true;
  String? _typeFilter;

  /// 已配置用户变量（Cookie）的源，用于高亮配置入口
  Set<String> _configuredIds = {};

  /// 仓库记录里 type 为空的源 → 从 raw 的 meta.type 解析出的真实类型。
  ///
  /// 老版本 App 写入的源文件不带 type 字段，导致这里按记录分类全部落空
  /// （磁力/网盘计数为 0，点筛选显示「该类型下没有源」），
  /// 而首页/搜索用的是 raw 解析出的 meta.type，两边对不上。
  final Map<String, String> _resolvedTypes = {};

  /// 源类型：优先仓库记录，其次 raw 解析结果，最后按格式推断
  String _typeOf(StoredSource s) {
    if (s.type.isNotEmpty) return s.type;
    final resolved = _resolvedTypes[s.id];
    if (resolved != null && resolved.isNotEmpty) return resolved;
    switch (s.format) {
      case 'musicfree' || 'lx':
        return 'music';
      case 'legado':
        return 'book';
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final path = await ref.read(sourceRepositoryPathProvider.future);
    final repo = SourceRepository(path);
    final prefs = await SharedPreferences.getInstance();
    final imported = prefs.getBool(_kBuiltinImported) ?? false;
    // 只在从未导入过时补一次。原实现只要列表为空就导入，
    // 导致用户手动删完源后每次进页面都被重新塞回，删除形同无效。
    if (!imported && (await repo.list()).isEmpty) {
      final n = await BuiltinSources.importAll(repo);
      if (n > 0) {
        await prefs.setBool(_kBuiltinImported, true);
        if (mounted) context.tip('已自动导入 $n 个内置源');
      }
    }
    await _reload();
  }

  Future<void> _reload() async {
    final path = await ref.read(sourceRepositoryPathProvider.future);
    final repo = SourceRepository(path);
    _sources = await repo.list();

    // 补齐老数据缺失的 type：own 与 legado 的 raw 都是 JSON，可直接解析；
    // JS 源（musicfree/lx）的 raw 不是 JSON，只能靠上面的格式推断。
    _resolvedTypes.clear();
    for (final s in _sources) {
      if (s.type.isNotEmpty) continue;
      if (s.format != 'own' && s.format != 'legado') continue;
      try {
        final raw = await repo.readRaw(s.id);
        final meta = s.format == 'own'
            ? parseSource(raw).meta
            : LegadoAdapter().translate(raw).meta;
        _resolvedTypes[s.id] = meta.type.name;
      } catch (_) {
        // 解析失败就维持原来的「未分类」，不影响其它源
      }
    }

    final store = await ref.read(pluginStoreProvider.future);
    _configuredIds = {
      for (final s in _sources)
        if (store.hasUserVars(s.id)) s.id,
    };
    if (mounted) {
      setState(() => _loading = false);
      // 源列表变化后刷新可搜索源装配
      ref.invalidate(searchableSourcesProvider);
    }
  }

  Future<void> _importFromClipboard() async {
    final raw = (await Clipboard.getData('text/plain'))?.text;
    if (raw == null || raw.isEmpty) {
      if (mounted) context.tip('剪贴板为空');
      return;
    }
    try {
      final format = detectSourceFormat(raw);
      String id;
      String name;
      String type;
      switch (format) {
        case SourceFormat.own:
          final meta = parseSource(raw).meta;
          id = meta.id;
          name = meta.name;
          type = meta.type.name;
        case SourceFormat.legado:
          final meta = LegadoAdapter().translate(raw).meta;
          id = meta.id;
          name = meta.name;
          type = meta.type.name;
        case SourceFormat.musicfree || SourceFormat.lx:
          id = '${format.name}-${raw.hashCode.abs()}';
          name = '剪贴板导入的 JS 源';
          type = 'music';
      }
      final path = await ref.read(sourceRepositoryPathProvider.future);
      await SourceRepository(path).save(id,
          format: format.name, raw: raw, name: name, type: type);
      await _reload();
      if (mounted) context.tip('导入成功：$name');
    } on SourceFormatException catch (e) {
      if (mounted) context.tip('无法识别：${e.message}');
    } on LegadoUnsupportedException catch (e) {
      if (mounted) context.tip('Legado 源不兼容：$e');
    } on SourceSchemaException catch (e) {
      if (mounted) context.tip('源校验失败：$e');
    } catch (e) {
      if (mounted) context.tip('导入失败：$e');
    }
  }

  Future<void> _importBuiltin() async {
    final path = await ref.read(sourceRepositoryPathProvider.future);
    final n = await BuiltinSources.importAll(SourceRepository(path));
    await _reload();
    if (mounted) context.tip(n > 0 ? '已导入 $n 个内置源' : '内置源均已存在');
  }

  Future<void> _confirmDelete(StoredSource s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除源'),
        content: Text('确定删除「${s.name.isEmpty ? s.id : s.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      final path = await ref.read(sourceRepositoryPathProvider.future);
      await SourceRepository(path).delete(s.id);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    int countOf(String t) => _sources.where((s) => _typeOf(s) == t).length;
    final visible = _typeFilter == null
        ? _sources
        : _sources.where((s) => _typeOf(s) == _typeFilter).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('源管理'),
        actions: [
          TextButton.icon(
            onPressed: _importBuiltin,
            icon: const Icon(Icons.inventory_2, size: 18),
            label: const Text('内置源'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importFromClipboard,
        icon: const Icon(Icons.content_paste),
        label: const Text('剪贴板导入'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.extension_off,
                          size: 60, color: scheme.outline),
                      const SizedBox(height: 12),
                      const Text('还没有搜索源'),
                      const SizedBox(height: 6),
                      Text('点右上角导入内置源，或用剪贴板粘贴源文件',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 类型筛选
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text('全部 ${_sources.length}'),
                              selected: _typeFilter == null,
                              onSelected: (_) =>
                                  setState(() => _typeFilter = null),
                              showCheckmark: false,
                            ),
                          ),
                          for (final t in _chipTypes)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                avatar: Icon(_typeIcons[t] ?? Icons.circle,
                                    size: 16),
                                label: Text('${_typeLabels[t] ?? t} ${countOf(t)}'),
                                selected: _typeFilter == t,
                                onSelected: (_) =>
                                    setState(() => _typeFilter = t),
                                showCheckmark: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Text('该类型下没有源',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant)))
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 80),
                              children: visible.map((s) {
                                final enabled = s.enabled;
                                final t = _typeOf(s);
                                return Card(
                                  clipBehavior: Clip.antiAlias,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: enabled
                                          ? scheme.primary
                                              .withValues(alpha: 0.12)
                                          : scheme.outlineVariant
                                              .withValues(alpha: 0.3),
                                      child: Icon(
                                        _typeIcons[t] ?? Icons.extension,
                                        size: 20,
                                        color: enabled
                                            ? scheme.primary
                                            : scheme.outline,
                                      ),
                                    ),
                                    title: Text(
                                      s.name.isEmpty ? s.id : s.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: enabled
                                            ? null
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Wrap(
                                        spacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          if (t.isNotEmpty)
                                            Text(
                                                '${_typeLabels[t] ?? t}源',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: scheme
                                                        .onSurfaceVariant)),
                                          // 格式徽标：小灰边框胶囊
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1.5),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                  color: scheme.outlineVariant),
                                            ),
                                            child: Text(
                                              s.format,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: scheme
                                                      .onSurfaceVariant),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 插件声明了用户变量（Cookie 等）才显示配置入口
                                        if (s.format == 'musicfree')
                                          IconButton(
                                            icon: Icon(
                                              Icons.tune,
                                              size: 20,
                                              color: _configuredIds.contains(s.id)
                                                  ? scheme.primary
                                                  : scheme.onSurfaceVariant,
                                            ),
                                            tooltip: '登录 / 配置',
                                            onPressed: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => SourceConfigPage(
                                                      sourceId: s.id,
                                                      sourceName: s.name),
                                                ),
                                              );
                                              await _reload();
                                            },
                                          ),
                                        Switch(
                                          value: s.enabled,
                                          onChanged: (v) async {
                                            final path = await ref.read(
                                                sourceRepositoryPathProvider
                                                    .future);
                                            await SourceRepository(path)
                                                .setEnabled(s.id, v);
                                            await _reload();
                                          },
                                        ),
                                        // 删除此前只能长按触发，属于不可见操作。
                                        // 保留长按作为快捷方式，同时给出可见入口。
                                        PopupMenuButton<String>(
                                          tooltip: '更多操作',
                                          onSelected: (v) {
                                            if (v == 'delete') {
                                              _confirmDelete(s);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                                value: 'delete',
                                                child: Text('删除源')),
                                          ],
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                SourceDebugPage(stored: s)),
                                      );
                                      await _reload();
                                    },
                                    onLongPress: () => _confirmDelete(s),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
    );
  }
}
