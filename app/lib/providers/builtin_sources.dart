import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';

/// 内置源包：随 App 出厂的真实磁力/网盘/音乐/书籍源，一键导入到源仓库。
///
/// 出厂**清单不硬编码在本文件里**——否则公开仓库的源码会直接暴露「内置了
/// 哪些站点」及来源出处。改为运行时从 `assets/sources/_index.json` 枚举：
/// 该索引由 CI 在构建时依据私有源仓实际拉取到的文件动态生成（`app/assets/`
/// 已被 gitignore，索引随之不进公开仓）。未接入私有源仓的构建（如公开仓自行
/// clone）读不到该索引时，内置导入得到空集合，等价于「空壳」默认，不报错。
class BuiltinSources {
  /// 内置源清单版本号。
  ///
  /// **每次修改内置源「内容」（不只是增删文件）都要 +1**。清单指纹基于文件
  /// 路径，改内容不改文件名时指纹不变，老用户升级后就不会重新导入。
  static const manifestVersion = 7;

  /// JS 源文件名 → 展示名（MusicFree/洛雪插件，上游本就公开，故仍列于此）。
  static const _jsPrettyNames = {
    'mf_netease_cloud.js': '网易云音乐',
    'mf_yuanli_wy.js': '网易云·元力音源',
    'mf_qq_music.js': 'QQ音乐',
    'mf_qq_zhuyue.js': 'QQ音乐·竹玥源',
    'mf_yuanli_qq.js': 'QQ音乐·元力音源',
    'mf_kugou.js': '酷狗音乐',
    'mf_yuanli_kg.js': '酷狗·元力音源',
    'mf_kuwo.js': '酷我音乐',
    'mf_yuanli_kw.js': '酷我·元力音源',
    'mf_migu.js': '咪咕音乐',
    'mf_kuaile_qishui.js': '开心汽水',
    'mf_qianqian.js': '千千音乐',
    'mf_bilibili.js': '哔哩哔哩',
    'mf_bilibili_cookie.js': '哔哩哔哩·Cookie版',
    'mf_maoer_fm.js': '猫耳FM',
    'mf_ximalaya.js': '喜马拉雅',
    'mf_gd_music.js': 'GD音乐台',
    'mf_aiting.js': '爱听',
    'mf_lrts.js': '懒人听书',
    'lx_qingmusic.js': 'QingMusic音源（洛雪）',
  };

  /// JS 源文件名 → 内容类型（缺省 music）。
  static const _jsTypes = {
    'mf_lrts.js': 'audiobook',
  };

  /// 运行时从 CI 生成的索引枚举内置源文件（返回 assets 逻辑路径列表）。
  /// 缺失索引 → 返回空（「空壳」默认，不抛错）。
  static Future<List<String>> _files() async {
    try {
      final raw = await rootBundle.loadString('assets/sources/_index.json');
      final decoded = jsonDecode(raw);
      final names = decoded is Map
          ? (decoded['files'] as List? ?? const [])
          : (decoded as List);
      return [for (final n in names) 'assets/sources/$n'];
    } catch (_) {
      return const [];
    }
  }

  /// 读取全部内置源原文。
  static Future<List<String>> loadAll() async =>
      [for (final p in await _files()) await rootBundle.loadString(p)];

  /// 内置源清单指纹：用于判断「是否需要重新导入」。
  static Future<String> manifestSignature() async {
    final files = await _files();
    var h = 17;
    for (final p in files) {
      for (final c in p.codeUnits) {
        h = (h * 31 + c) & 0x3fffffff;
      }
      h = (h * 7 + 1) & 0x3fffffff;
    }
    return 'v$manifestVersion-${files.length}-$h';
  }

  /// 导入内置源到仓库；已存在同 id 的源跳过。返回新导入数量。
  static Future<int> importAll(SourceRepository repo) async =>
      (await importDetailed(repo)).imported;

  /// 导入内置源，并返回本次清单里的**全部** id。
  ///
  /// 调用方拿这份 id 列表可以与"上次内置过的 id"做差集，
  /// 只清理**曾经内置、现已从清单移除**的源 —— 不会误删用户自行导入的源。
  static Future<BuiltinImportResult> importDetailed(
      SourceRepository repo) async {
    final manifest = await _files();
    var imported = 0;
    final ids = <String>[];
    final existing = await repo.list();
    final existingIds = existing.map((e) => e.id).toSet();
    for (final path in manifest) {
      try {
        final raw = await rootBundle.loadString(path);
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
            // JS 源脚本没有稳定 id 字段，按文件名生成
            final base = path.split('/').last;
            id = 'builtin.${base.replaceAll('.', '_')}';
            name = _jsPrettyNames[base] ?? base;
            type = _jsTypes[base] ?? 'music';
        }
        ids.add(id);
        if (existingIds.contains(id)) {
          // 已存在：刷新元信息**并重新下发 raw**。内置源的内容修复在 id 不变
          // 的前提下靠这里下发；只刷 name/type 不够。走 updateRaw，enabled 不重置。
          try {
            await repo.updateRaw(id, raw: raw, name: name, type: type);
          } catch (_) {}
          continue;
        }
        await repo.save(id,
            format: format.name, raw: raw, name: name, type: type);
        imported++;
      } catch (_) {
        // 单个内置源损坏不影响其余导入
      }
    }
    return BuiltinImportResult(imported, ids);
  }
}

/// 内置源导入结果
class BuiltinImportResult {
  /// 本次新导入的数量
  final int imported;

  /// 本次清单里的全部源 id（含早已存在的）
  final List<String> manifestIds;

  const BuiltinImportResult(this.imported, this.manifestIds);
}
