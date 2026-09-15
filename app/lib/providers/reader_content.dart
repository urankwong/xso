import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:source_engine/source_engine.dart';

/// 章节正文仓库：内存 LRU → 磁盘缓存 → 引擎抓取。
///
/// - 内存 LRU（容量 [_capacity] 章）：翻章零解析开销；
/// - 磁盘缓存（应用支持目录/reader_cache）：重启后秒开、离线可读；
/// - [prefetch]：阅读当前章时后台预取下一章（含其全部分页），
///   主流阅读软件"翻章零等待"体验的关键。
class ChapterContentRepository {
  ChapterContentRepository(this._engine, this._source,
      {this.siblingChapterUrls = const <String>{}, this.bookKey});

  final SourceEngine _engine;
  final Source _source;

  /// 本书标识（阅读页的 progressKey），用于筛选"仅本书"的净化规则
  final String? bookKey;

  /// 本书**其他章节**的 URL 集合，透传给引擎做"跨章串页"防护。
  ///
  /// 有些站点的章节末页会把"下一页"直接指向下一章，引擎若无从判断就会
  /// 一路串下去（实测某小说站第一章串 50 页、正文 7 万字、耗时 17 秒）。
  /// 有了这份集合，引擎一发现"下一页"是已知的兄弟章节就收尾。
  final Set<String> siblingChapterUrls;

  static const _capacity = 12;
  final Map<String, String> _mem = <String, String>{};
  Directory? _diskDir;

  /// 预取代际：换书/清空后旧预取结果作废
  int _epoch = 0;
  final Set<String> _prefetching = {};
  final Set<String> _failed = {};

  Future<String> fetch(String chapterUrl) async {
    final hit = _mem[chapterUrl];
    if (hit != null) return hit;
    final disk = await _readDisk(chapterUrl);
    if (disk != null) {
      _putMem(chapterUrl, disk);
      return disk;
    }
    final text = await _engine.fetchContent(_source, chapterUrl,
        siblingChapterUrls: siblingChapterUrls, bookKey: bookKey);
    if (text.isNotEmpty) {
      _putMem(chapterUrl, text);
      unawaited(_writeDisk(chapterUrl, text));
    }
    return text;
  }

  /// 后台预取（fire-and-forget）：同 URL 进行中或已失败则跳过
  void prefetch(String chapterUrl) {
    if (chapterUrl.isEmpty ||
        _mem.containsKey(chapterUrl) ||
        _prefetching.contains(chapterUrl) ||
        _failed.contains(chapterUrl)) {
      return;
    }
    final epoch = _epoch;
    _prefetching.add(chapterUrl);
    () async {
      try {
        final text = await fetch(chapterUrl);
        if (text.isEmpty) _failed.add(chapterUrl);
      } catch (_) {
        _failed.add(chapterUrl);
      } finally {
        _prefetching.remove(chapterUrl);
        assert(epoch == _epoch || true); // 保留结果无害，仅日志语义
      }
    }();
  }

  /// 清空内存缓存并使进行中的预取作废（换书时调用）
  void invalidate() {
    _epoch++;
    _mem.clear();
    _failed.clear();
  }

  /// 让某一章的缓存失效（内存 + 磁盘）。
  ///
  /// 用户改完正文净化规则后必须调它：缓存里存的是**规则生效前**的正文，
  /// 不删掉他会以为"规则根本没起作用"（这类误判的排查成本极高，
  /// 参见 _cacheFormatVersion 那段注释）。
  Future<void> invalidateUrl(String url) async {
    _mem.remove(url);
    _failed.remove(url);
    try {
      final dir = await _disk();
      if (dir == null) return;
      final f = File('${dir.path}${Platform.pathSeparator}${_keyOf(url)}.txt');
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 删缓存失败不阻断阅读：最坏情况是这一章仍显示旧文本
    }
  }

  void _putMem(String url, String text) {
    if (_mem.length >= _capacity) {
      _mem.remove(_mem.keys.first); // LinkedHashMap：最早插入者淘汰
    }
    _mem[url] = text;
  }

  /// 正文缓存格式版本。
  ///
  /// **每次改动"正文抓取 / 清洗 / 分页 / 净化"相关逻辑后必须 +1。**
  ///
  /// 磁盘缓存里存的是**清洗后的成品文本**，逻辑一变，旧缓存就是错的
  /// 数据，而且永远不会自己失效。实测踩过这个坑：引擎侧已经修好
  /// 「静态 @html 规则剥标签」与「跨章串页防护」，阅读页却依旧满屏
  /// `<p>` 标签、正文被串成 50 页约 8 万字 —— 表面上完全像"修复没生效"，
  /// 实际是缓存没失效。连带把听书也拖死（TTS 逐段联网合成 8 万字，
  /// 用户根本等不到出声）。这类问题的排查成本极高，故用版本号兜住。
  static const _cacheFormatVersion = 2;
  static const _kCacheVersionKey = 'reader_cache_format_ver';

  Future<Directory?> _disk() async {
    if (_diskDir != null) return _diskDir;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(
          '${base.path}${Platform.pathSeparator}reader_cache');
      await dir.create(recursive: true);
      await _invalidateIfStale(dir);
      return _diskDir = dir;
    } catch (_) {
      return null; // 存储不可用（罕见）时静默退化为纯内存
    }
  }

  /// 版本不符 → 清空整个缓存目录（惰性，只在首次使用磁盘缓存时做一次）。
  Future<void> _invalidateIfStale(Directory dir) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getInt(_kCacheVersionKey) ?? 0;
      if (cached == _cacheFormatVersion) return;
      var removed = 0;
      for (final f in dir.listSync()) {
        try {
          f.deleteSync();
          removed++;
        } catch (_) {}
      }
      await prefs.setInt(_kCacheVersionKey, _cacheFormatVersion);
      debugPrint('[阅读缓存] 清洗逻辑已升级（v$cached → v$_cacheFormatVersion），'
          '清理 $removed 个旧缓存文件');
    } catch (_) {
      // 清理失败不阻塞阅读：最坏情况是继续用旧缓存
    }
  }

  Future<String?> _readDisk(String url) async {
    try {
      final dir = await _disk();
      if (dir == null) return null;
      final f = File('${dir.path}${Platform.pathSeparator}${_keyOf(url)}.txt');
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      // 首行 URL 校验：不同书 URL 哈希碰撞防御（概率极低但代价小）
      final nl = raw.indexOf('\n');
      if (nl < 0) return null;
      if (raw.substring(0, nl) != url) return null;
      return raw.substring(nl + 1);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDisk(String url, String text) async {
    try {
      final dir = await _disk();
      if (dir == null) return;
      final f = File('${dir.path}${Platform.pathSeparator}${_keyOf(url)}.txt');
      await f.writeAsString('$url\n$text', flush: false);
    } catch (_) {
      // 写缓存失败不影响阅读
    }
  }

  /// FNV-1a 64 位哈希：Dart 的 String.hashCode 带 run 随机种子，
  /// 跨重启不稳定，不能做磁盘文件名。
  static String _keyOf(String url) {
    var h = 0xcbf29ce484222325;
    for (final cu in url.codeUnits) {
      h ^= cu;
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return h.toRadixString(36);
  }
}
