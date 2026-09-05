import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';
import '../providers/engine_providers.dart';
import '../providers/builtin_sources.dart';
import 'source_debug_page.dart';

/// 导入状态反馈 SnackBar 的辅助扩展
extension _SnackBar on BuildContext {
  void tip(String msg) =>
      ScaffoldMessenger.of(this).showSnackBar(SnackBar(content: Text(msg)));
}

class SourceManagePage extends ConsumerStatefulWidget {
  const SourceManagePage({super.key});
  @override
  ConsumerState<SourceManagePage> createState() => _SourceManagePageState();
}

class _SourceManagePageState extends ConsumerState<SourceManagePage> {
  List<StoredSource> _sources = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 首次启动自动导入内置源（已导入的跳过）
    final path = await ref.read(sourceRepositoryPathProvider.future);
    final repo = SourceRepository(path);
    if ((await repo.list()).isEmpty) {
      final n = await BuiltinSources.importAll(repo);
      if (mounted && n > 0) {
        context.tip('已导入 $n 个内置源，可直接搜索');
      }
    }
    await _reload();
  }

  Future<void> _importBuiltin() async {
    final path = await ref.read(sourceRepositoryPathProvider.future);
    final n = await BuiltinSources.importAll(SourceRepository(path));
    await _reload();
    if (mounted) context.tip(n > 0 ? '已导入 $n 个内置源' : '内置源均已存在');
  }

  Future<void> _reload() async {
    final path = await ref.read(sourceRepositoryPathProvider.future);
    _sources = await SourceRepository(path).list();
    if (mounted) setState(() {});
  }

  Future<void> _importFromClipboard() async {
    final raw = (await Clipboard.getData('text/plain'))?.text;
    if (raw == null || raw.isEmpty) {
      if (mounted) context.tip('剪贴板为空');
      return;
    }
    try {
      final format = detectSourceFormat(raw);
      final id = switch (format) {
        SourceFormat.own => parseSource(raw).meta.id,
        SourceFormat.legado =>
          LegadoAdapter().translate(raw).meta.id, // 不支持语法在此抛错
        SourceFormat.musicfree => 'musicfree-${raw.hashCode.abs()}',
        SourceFormat.lx => 'lx-${raw.hashCode.abs()}',
      };
      final path = await ref.read(sourceRepositoryPathProvider.future);
      await SourceRepository(path).save(id, format: format.name, raw: raw);
      await _reload();
      if (mounted) context.tip('导入成功（$format）');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('源管理'),
        actions: [
          TextButton.icon(
            onPressed: _importBuiltin,
            icon: const Icon(Icons.inventory_2, size: 18),
            label: const Text('导入内置源'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importFromClipboard,
        icon: const Icon(Icons.content_paste),
        label: const Text('剪贴板导入'),
      ),
      body: _sources.isEmpty
          ? const Center(child: Text('还没有源：点右上角导入内置源，或用剪贴板导入'))
          : ListView(
              children: _sources
                  .map((s) => ListTile(
                        title: Text(s.id),
                        subtitle: Text('格式: ${s.format}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final path = await ref
                                    .read(sourceRepositoryPathProvider.future);
                                await SourceRepository(path).delete(s.id);
                                await _reload();
                              },
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
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => SourceDebugPage(stored: s)),
                        ),
                      ))
                  .toList(),
            ),
    );
  }
}
