import 'package:flutter/services.dart' show rootBundle;
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';

/// 内置源包：随 App 出厂的示例/站点源，一键导入到源仓库。
class BuiltinSources {
  static const _manifest = [
    'assets/sources/knaben_magnet.json',
    'assets/sources/tpb_magnet.json',
    'assets/sources/pan_cms_example.json',
    'assets/sources/magnet_json_example.json',
  ];

  /// 读取全部内置源原文
  static Future<List<String>> loadAll() async {
    return [for (final p in _manifest) await rootBundle.loadString(p)];
  }

  /// 导入内置源到仓库；已存在同 id 的源跳过。返回新导入数量。
  static Future<int> importAll(SourceRepository repo) async {
    var imported = 0;
    for (final raw in await loadAll()) {
      try {
        final meta = parseSource(raw).meta;
        final existing = await repo.list();
        if (existing.any((e) => e.id == meta.id)) continue;
        await repo.save(meta.id, format: 'own', raw: raw);
        imported++;
      } catch (_) {
        // 单个内置源损坏不影响其余导入
      }
    }
    return imported;
  }
}
