import 'dart:convert';
import 'dart:io';

class StoredSource {
  final String id;
  final String format; // own | musicfree | lx | legado
  final String name; // 展示名（导入时记录）
  final String type; // 内容类型：magnet/pan/music/book…（导入时记录）
  final bool enabled;
  final String file;
  const StoredSource({
    required this.id,
    required this.format,
    this.name = '',
    this.type = '',
    required this.enabled,
    required this.file,
  });
}

/// 源仓库：目录式文件存储，每个源一个 JSON 包裹文件
class SourceRepository {
  final String rootDir;
  SourceRepository(this.rootDir) {
    Directory(rootDir).createSync(recursive: true);
  }

  String _safeId(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  Future<void> save(String id,
      {required String format, required String raw, String? name, String? type}) async {
    final file = File('$rootDir/${_safeId(id)}.json');
    await file.writeAsString(jsonEncode({
      'id': id,
      'format': format,
      'name': name ?? '',
      'type': type ?? '',
      'enabled': true,
      'raw': raw,
    }));
  }

  Future<List<StoredSource>> list() async {
    final dir = Directory(rootDir);
    final result = <StoredSource>[];
    await for (final f in dir.list()) {
      if (!f.path.endsWith('.json')) continue;
      final m =
          jsonDecode(File(f.path).readAsStringSync()) as Map<String, dynamic>;
      result.add(StoredSource(
        id: m['id'] as String,
        format: m['format'] as String,
        name: m['name'] as String? ?? '',
        type: m['type'] as String? ?? '',
        enabled: m['enabled'] as bool? ?? true,
        file: f.path,
      ));
    }
    return result;
  }

  Future<String> readRaw(String id) async {
    final file = File('$rootDir/${_safeId(id)}.json');
    final m = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return m['raw'] as String;
  }

  Future<void> setEnabled(String id, bool enabled) async =>
      _mutate(id, (m) => m['enabled'] = enabled);

  /// 只更新展示名/类型，保留 raw 内容与用户的启用状态。
  ///
  /// 用途：内置源的**类型映射**可能随版本变化（例如 Legado 文本型源
  /// 从 book 改成 novel），已导入的源需要刷新 type；但整体覆盖会连带
  /// 抹掉用户对内置源的改动与禁用状态，所以单独开一个轻量接口。
  Future<void> updateMeta(String id, {String? name, String? type}) =>
      _mutate(id, (m) {
        if (name != null && name.isNotEmpty) m['name'] = name;
        if (type != null && type.isNotEmpty) m['type'] = type;
      });

  /// 重新下发源内容，但保留用户的启用状态。
  ///
  /// 用途：内置源的**内容**可能需要修复下发（例如某个 Legado 源的书名
  /// 选择器取错了元素，导致标题全部为空）。这类修复 id 不变，
  /// 走 [save] 会把 enabled 重置为 true（用户禁用的内置源被重新打开），
  /// 走 [updateMeta] 又碰不到 raw —— 两头不讨好，因此单独开这个接口：
  /// 只覆盖 raw/name/type，其余字段原样保留。
  Future<void> updateRaw(String id,
      {required String raw, String? name, String? type}) =>
      _mutate(id, (m) {
        m['raw'] = raw;
        if (name != null && name.isNotEmpty) m['name'] = name;
        if (type != null && type.isNotEmpty) m['type'] = type;
      });

  Future<void> delete(String id) async {
    final file = File('$rootDir/${_safeId(id)}.json');
    if (await file.exists()) await file.delete();
  }

  Future<void> _mutate(
      String id, void Function(Map<String, dynamic>) fn) async {
    final file = File('$rootDir/${_safeId(id)}.json');
    final m = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    fn(m);
    await file.writeAsString(jsonEncode(m));
  }
}
