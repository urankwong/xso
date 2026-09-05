import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';
import '../providers/engine_providers.dart';
import '../providers/data_providers.dart';
import '../providers/builtin_sources.dart';
import 'source_debug_page.dart';

extension _SnackBar on BuildContext {
  void tip(String msg) =>
      ScaffoldMessenger.of(this).showSnackBar(SnackBar(content: Text(msg)));
}

const _formatLabels = {
  'own': '自有规则',
  'musicfree': 'MusicFree',
  'lx': '洛雪',
  'legado': 'Legado',
};

class SourceManagePage extends ConsumerStatefulWidget {
  const SourceManagePage({super.key});
  @override
  ConsumerState<SourceManagePage> createState() => _SourceManagePageState();
}

class _SourceManagePageState extends ConsumerState<SourceManagePage> {
  List<StoredSource> _sources = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final path = await ref.read(sourceRepositoryPathProvider.future);
    final repo = SourceRepository(path);
    if ((await repo.list()).isEmpty) {
      final n = await BuiltinSources.importAll(repo);
      if (mounted && n > 0) context.tip('已自动导入 $n 个内置源');
    }
    await _reload();
  }

  Future<void> _reload() async {
    final path = await ref.read(sourceRepositoryPathProvider.future);
    _sources = await SourceRepository(path).list();
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
      switch (format) {
        case SourceFormat.own:
          final meta = parseSource(raw).meta;
          id = meta.id;
          name = meta.name;
        case SourceFormat.legado:
          final meta = LegadoAdapter().translate(raw).meta;
          id = meta.id;
          name = meta.name;
        case SourceFormat.musicfree || SourceFormat.lx:
          id = '${format.name}-${raw.hashCode.abs()}';
          name = '剪贴板导入的 JS 源';
      }
      final path = await ref.read(sourceRepositoryPathProvider.future);
      await SourceRepository(path).save(id,
          format: format.name, raw: raw, name: name);
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
              : ListView(
                  padding: const EdgeInsets.only(bottom: 80),
                  children: _sources.map((s) {
                    final enabled = s.enabled;
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: enabled
                              ? scheme.primary.withValues(alpha: 0.12)
                              : scheme.outlineVariant.withValues(alpha: 0.3),
                          child: Icon(
                            Icons.extension,
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
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _formatLabels[s.format] ?? s.format,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onPrimaryContainer),
                                ),
                              ),
                              Text(s.id,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _confirmDelete(s),
                            ),
                            Switch(
                              value: s.enabled,
                              onChanged: (v) async {
                                final path = await ref
                                    .read(sourceRepositoryPathProvider.future);
                                await SourceRepository(path)
                                    .setEnabled(s.id, v);
                                await _reload();
                              },
                            ),
                          ],
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => SourceDebugPage(stored: s)),
                          );
                          await _reload();
                        },
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}
