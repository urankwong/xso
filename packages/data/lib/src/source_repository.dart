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
