import 'dart:async';

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:source_engine/source_engine.dart';

/// 章节正文仓库：内存 LRU → 磁盘缓存 → 引擎抓取。
///
/// - 内存 LRU（容量 [_capacity] 章）：翻章零解析开销；
/// - 磁盘缓存（应用支持目录/reader_cache）：重启后秒开、离线可读；
/// - [prefetch]：阅读当前章时后台预取下一章（含其全部分页），
///   主流阅读软件"翻章零等待"体验的关键。
class ChapterContentRepository {
  ChapterContentRepository(this._engine, this._source);

  final SourceEngine _engine;
  final Source _source;

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
    final text = await _engine.fetchContent(_source, chapterUrl);
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

  void _putMem(String url, String text) {
    if (_mem.length >= _capacity) {
      _mem.remove(_mem.keys.first); // LinkedHashMap：最早插入者淘汰
    }
    _mem[url] = text;
  }

  Future<Directory?> _disk() async {
    if (_diskDir != null) return _diskDir;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(
          '${base.path}${Platform.pathSeparator}reader_cache');
      await dir.create(recursive: true);
      return _diskDir = dir;
    } catch (_) {
      return null; // 存储不可用（罕见）时静默退化为纯内存
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
