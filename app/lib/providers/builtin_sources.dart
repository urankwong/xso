import 'package:flutter/services.dart' show rootBundle;
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';

/// 内置源包：随 App 出厂的真实磁力/网盘/音乐/书籍源，一键导入到源仓库。
class BuiltinSources {
  static const _manifest = [
    // ---- 磁力搜索源（国内站点）----
    'assets/sources/ciliduo.magnet.json',
    'assets/sources/wuji.magnet.json',
    'assets/sources/skrbt.magnet.json',
    'assets/sources/cilipa.magnet.json',
    'assets/sources/lemon.magnet.json',
    'assets/sources/eclyun.magnet.json',
    'assets/sources/xingqiu.magnet.json',
    'assets/sources/yuhUAGE.magnet.json',
    'assets/sources/bt1207.magnet.json',
    'assets/sources/laowang.magnet.json',
    'assets/sources/cilijia.magnet.json',
    'assets/sources/cilihezi.magnet.json',
    'assets/sources/ddcl.magnet.json',
    'assets/sources/cltt.magnet.json',
    'assets/sources/wujicili.magnet.json',
    'assets/sources/cilimao.magnet.json',
    'assets/sources/cilicao.magnet.json',
    'assets/sources/91bt.magnet.json',
    'assets/sources/52bt.magnet.json',
    'assets/sources/magnetdog.magnet.json',
    'assets/sources/cldi.magnet.json',
    'assets/sources/btlm.magnet.json',
    'assets/sources/sefan.magnet.json',
    'assets/sources/foxso.magnet.json',
    'assets/sources/rili6.magnet.json',
    'assets/sources/emoncili.magnet.json',
    'assets/sources/wuqianso.magnet.json',
    'assets/sources/xiongmao.magnet.json',
    'assets/sources/iyuhUAGE.magnet.json',
    'assets/sources/mazey.magnet.json',
    'assets/sources/migu.magnet.json',
    // ---- 磁力搜索源（国际站点）----
    'assets/sources/torrentgalaxy.magnet.json',
    'assets/sources/solidtorrents.magnet.json',
    'assets/sources/idope.magnet.json',
    'assets/sources/snowfl.magnet.json',
    'assets/sources/torrentseeker.magnet.json',
    'assets/sources/magnetdl.magnet.json',
    'assets/sources/bitsearch.magnet.json',
    // ---- 磁力搜索源（已有精确定义，保持不变）----
    'assets/sources/knaben_magnet.json',
    'assets/sources/tpb_magnet.json',
    'assets/sources/bt4g_magnet.json',
    'assets/sources/btgg_magnet.json',
    'assets/sources/btsow_magnet.json',
    'assets/sources/zhongzisou_magnet.json',
    'assets/sources/btdigg_magnet.json',
    'assets/sources/zooqle_magnet.json',
    // ---- 网盘聚合源（新增站点）----
    'assets/sources/ypansou.pan.json',
    'assets/sources/xuebapan.pan.json',
    'assets/sources/upyunso.pan.json',
    'assets/sources/xiaoso.pan.json',
    'assets/sources/h2ero.pan.json',
    'assets/sources/sobaidupan.pan.json',
    'assets/sources/xiongdipan.pan.json',
    'assets/sources/chaonengsou.pan.json',
    'assets/sources/qileso.pan.json',
    'assets/sources/panduo.pan.json',
    'assets/sources/wowenda.pan.json',
    'assets/sources/pansearch.pan.json',
    'assets/sources/lingfengyun.pan.json',
    'assets/sources/sosoyunpan.pan.json',
    'assets/sources/daysou.pan.json',
    'assets/sources/wanyipan.pan.json',
    'assets/sources/pikaso.pan.json',
    'assets/sources/jiwake.pan.json',
    'assets/sources/codelicence.pan.json',
    'assets/sources/fastsoso.pan.json',
    'assets/sources/wopansou.pan.json',
    'assets/sources/pan131.pan.json',
    'assets/sources/yunpanem.pan.json',
    'assets/sources/panc.pa.pan.json',
    'assets/sources/xiaobaipan.pan.json',
    'assets/sources/dalipan.pan.json',
    'assets/sources/xiaomapan.pan.json',
    'assets/sources/woqusou.pan.json',
    'assets/sources/wosouyun.pan.json',
    'assets/sources/yunpuzi.pan.json',
    'assets/sources/vpansou.pan.json',
    'assets/sources/wuyasou.pan.json',
    'assets/sources/sopandas.pan.json',
    'assets/sources/cuppaso.pan.json',
    'assets/sources/xiongbeng.pan.json',
    'assets/sources/lanzou.magnet.json',
    // ---- 网盘聚合源（已有精确定义，保持不变）----
    'assets/sources/panhub_pan.json',
    'assets/sources/repanso_pan.json',
    'assets/sources/alipansou_pan.json',
    'assets/sources/niceso_pan.json',
    'assets/sources/pansousou_pan.json',
    // ---- 书籍源（Libgen 双镜像，实测可搜可直链下载）----
    'assets/sources/book_libgen_gl.json',
    'assets/sources/book_libgen_bz.json',
    'assets/sources/book_legado_01.json',
    'assets/sources/book_legado_02.json',
    'assets/sources/book_legado_03.json',
    'assets/sources/book_legado_04.json',
    'assets/sources/book_legado_05.json',
    'assets/sources/book_legado_06.json',
    'assets/sources/book_legado_07.json',
    'assets/sources/book_legado_08.json',
    'assets/sources/book_legado_09.json',
    'assets/sources/book_legado_10.json',
    'assets/sources/book_legado_11.json',
    // ---- Legado 社区书源（来源 shuyuan.yiove.com，经兼容性实测可导入；
    //      已按完整 bookSourceUrl 去重，Legado 用它作为书源唯一标识） ----
    // ---- MusicFree 社区插件（来源 qwerwhr/musicfree-plugins，可删）----
    'assets/sources/mf_netease_cloud.js',
    'assets/sources/mf_yuanli_wy.js',
    'assets/sources/mf_qq_music.js',
    'assets/sources/mf_qq_zhuyue.js',
    'assets/sources/mf_yuanli_qq.js',
    'assets/sources/mf_kugou.js',
    'assets/sources/mf_yuanli_kg.js',
    'assets/sources/mf_kuwo.js',
    'assets/sources/mf_yuanli_kw.js',
    // mf_yuanli_migu 摘除：依赖的 scr_search_tag 接口已下线（2026-09 实测 301 到 v5 首页），
    // 由重写版 mf_migu.js 替代（search_all.do + listen-url 解密协议）。
    'assets/sources/mf_migu.js', // 重写版：search_all.do 免签名接口，替代已下线接口的元力咪咕
    // mf_qishui_vip 摘除：上游 api.vsaa.cn 的 /api/music.qishui.vip 已 404（2026-09 实测），
    // 官方最新版插件仍指向该地址，服务端不可修复。
    'assets/sources/mf_kuaile_qishui.js',
    'assets/sources/mf_qianqian.js',
    'assets/sources/mf_bilibili.js',
    'assets/sources/mf_bilibili_cookie.js',
    'assets/sources/mf_maoer_fm.js',
    'assets/sources/mf_ximalaya.js',
    'assets/sources/mf_gd_music.js',
    'assets/sources/mf_aiting.js',
    // ---- 有声播客（专辑两段式：search 返回专辑，详情拉章节连播）----
    'assets/sources/mf_lrts.js',
    // ---- 洛雪社区音源（来源 xzh767/lxmusic-source-all 等，可删）----
    // 注意：洛雪协议里「搜索」是宿主职责，源只做 musicUrl 取链（见 lx.dart 的宿主搜索回退）。
    // 因此判断一个洛雪源能否用，唯一看点是它依赖的**解析后端是否存活**。
    // 2026-09 实测（修复源初始化 bug 后重测）：6 个源的后端已全部停服，一并摘除：
    //   lx_nya      → 103.40.13.21:9866        ECONNREFUSED（服务器已关）
    //   lx_zhizun   → 110.42.36.53:1314        ETIMEDOUT（服务器死）
    //   lx_huibq    → lxmusicapi.onrender.com  unknow error（Render 已停服）
    //   lx_sixyin   → 同 lx_huibq（混淆源，加载即挂死）
    //   lx_ikun     → api.ikunshare.com        ENOTFOUND（域名已失效）
    //   lx_gzh_v3   → 88.lxmusic.中国          unknow error（/url 已 404）
    'assets/sources/lx_monster.js', // 直连平台官方接口，实测 KW 端到端闭环 HTTP 206
  ];

  /// JS 源文件名 → 展示名
  static const _jsPrettyNames = {
    'musicfree_itunes.js': 'iTunes 音乐（试听30s·MusicFree）',
    'lx_itunes.js': 'iTunes 音乐（试听30s·洛雪）',
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
    // 其余洛雪源已摘除（后端停服，理由见 _manifest 注释）：
    // lx_sixyin / lx_nya / lx_zhizun / lx_huibq / lx_ikun / lx_gzh_v3
    'lx_monster.js': 'Monster音源（洛雪）',
  };

  /// JS 源文件名 → 内容类型（缺省 music）
  static const _jsTypes = {
    'mf_lrts.js': 'audiobook',
  };

  /// 读取全部内置源原文
  static Future<List<String>> loadAll() async {
    return [for (final p in _manifest) await rootBundle.loadString(p)];
  }

  /// 内置源清单指纹。
  ///
  /// 用来替代"首启只导入一次"的布尔标记：清单没变时跳过（不拖慢启动、
  /// 也不会把用户删过的源塞回来），清单变了才重新导入 ——
  /// 否则每次发版新增内置源，老用户升级后永远拿不到。
  static String manifestSignature() {
    var h = 17;
    for (final p in _manifest) {
      for (final c in p.codeUnits) {
        h = (h * 31 + c) & 0x3fffffff;
      }
      h = (h * 7 + 1) & 0x3fffffff;
    }
    return '${_manifest.length}-$h';
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
    var imported = 0;
    final ids = <String>[];
    final existing = await repo.list();
    final existingIds = existing.map((e) => e.id).toSet();
    for (final path in _manifest) {
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
        if (existingIds.contains(id)) continue;
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
