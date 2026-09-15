import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 歌词来源：lrclib.net（免费无鉴权歌词库，支持带时间轴歌词）
final lyricProvider = Provider<LyricService>((ref) => LyricService(Dio()));

class LyricLine {
  final Duration? time;
  final String text;
  final String? translation;
  const LyricLine(this.time, this.text, {this.translation});
}

class LyricService {
  final Dio _dio;
  LyricService(this._dio);

  final _imgCache = <String, Future<List<int>>>{};

  /// lrclib 响应里的 cover 字段缓存（key = "title|artist"），
  /// 歌词请求命中时顺带记录，供元数据匹配链第三步复用。
  final _coverHints = <String, String?>{};

  /// 从 lrclib 拿封面 URL；已缓存则不再请求；查不到返回 null（不抛异常）。
  Future<String?> coverOf({required String title, required String artist}) async {
    final key = '$title|$artist';
    if (_coverHints.containsKey(key)) return _coverHints[key];
    String? cover;
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        'https://lrclib.net/api/get',
        queryParameters: {'track_name': title, 'artist_name': artist},
        options: Options(
            headers: {'User-Agent': 'AggregatorApp v0.1'},
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            validateStatus: (s) => s != null && s < 500),
      );
      if (resp.statusCode == 200) {
        final raw = (resp.data?['cover'] ?? resp.data?['coverPath']) as String?;
        if (raw != null && raw.isNotEmpty) cover = raw;
      }
    } catch (_) {
      // 网络失败不记录，允许下次重试
      return null;
    }
    _coverHints[key] = cover;
    return cover;
  }

  void _hintCover(String title, String? artist, Object? cover, Object? coverPath) {
    final url = ((cover ?? coverPath)?.toString() ?? '').trim();
    if (url.isNotEmpty) _coverHints['$title|${artist ?? ''}'] = url;
  }

  /// 歌词请求缓存（key = "title|artist"）。
  ///
  /// 缓存的是 Future 而不是结果：播放页原先每帧重建都调一次 fetch，
  /// 既重复打 lrclib，又让 FutureBuilder 一直停在加载态（表现为"歌词从来不显示"）。
  /// 同一 key 复用同一 Future 实例后，重建不再重置，请求也只发一次。
  final _lyricCache = <String, Future<List<LyricLine>>>{};
  static const _lyricCacheMax = 100;

  /// 返回逐行歌词；纯文本歌词 time 为 null；找不到抛 StateError。
  /// 结果按曲名+歌手缓存，失败不缓存（下次可重试）。
  Future<List<LyricLine>> fetch(
      {required String title, required String artist}) {
    final key = '$title|$artist';
    final cached = _lyricCache.remove(key);
    if (cached != null) {
      _lyricCache[key] = cached; // 移到队尾（最近使用）
      return cached;
    }
    final future = _fetchUncached(title: title, artist: artist);
    _lyricCache[key] = future;
    if (_lyricCache.length > _lyricCacheMax) {
      _lyricCache.remove(_lyricCache.keys.first);
    }
    // 派生监听吞掉错误避免 unhandled exception；调用方 await 原 future 仍会收到异常
    future.then<void>((_) {}).catchError((_) {
      if (_lyricCache[key] == future) _lyricCache.remove(key);
    });
    return future;
  }

  /// 精确匹配失败后用"去掉括号后缀的标题"重试（如 Love Story (Taylor's Version) → Love Story）
  Future<List<LyricLine>> _fetchUncached(
      {required String title, required String artist}) async {
    try {
      return await _get(title: title, artist: artist);
    } catch (_) {
      final bare = title.replaceAll(RegExp(r'\s*[(（][^)）]*[)）]\s*'), '').trim();
      if (bare.isNotEmpty && bare != title) {
        try {
          return await _get(title: bare, artist: artist);
        } catch (_) {}
      }
      // 第三级：search 接口按标题搜，取第一条（忽略艺人差异，翻唱也能命中原曲歌词）
      return _search(bare.isEmpty ? title : bare);
    }
  }

  Future<List<LyricLine>> _search(String query) async {
    final resp = await _dio.get<List<dynamic>>(
      'https://lrclib.net/api/search',
      queryParameters: {'track_name': query, 'limit': 1},
      options: Options(
          headers: {'User-Agent': 'AggregatorApp v0.1'},
          validateStatus: (s) => s != null && s < 500),
    );
    final list = resp.data ?? [];
    if (resp.statusCode != 200 || list.isEmpty) {
      throw StateError('未找到歌词');
    }
    final first = list.first as Map<String, dynamic>;
    _hintCover(query, null, first['cover'], first['coverPath']);
    final synced = first['syncedLyrics'] as String?;
    final plain = first['plainLyrics'] as String?;
    final translated = first['translatedLyrics'] as String?;
    final raw = (synced != null && synced.isNotEmpty) ? synced : plain;
    if (raw == null || raw.isEmpty) throw StateError('未找到歌词');
    return _parseWithTranslation(raw, translated);
  }

  Future<List<LyricLine>> _get(
      {required String title, required String artist}) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      'https://lrclib.net/api/get',
      queryParameters: {
        'track_name': title,
        'artist_name': artist,
      },
      options: Options(
          headers: {'User-Agent': 'AggregatorApp v0.1'},
          validateStatus: (s) => s != null && s < 500),
    );
    if (resp.statusCode != 200) {
      throw StateError('未找到歌词 (${resp.statusCode})');
    }
    _hintCover(title, artist, resp.data?['cover'], resp.data?['coverPath']);
    final synced = resp.data?['syncedLyrics'] as String?;
    final plain = resp.data?['plainLyrics'] as String?;
    final translated = resp.data?['translatedLyrics'] as String?;
    final raw = (synced != null && synced.isNotEmpty) ? synced : plain;
    if (raw == null || raw.isEmpty) throw StateError('未找到歌词');
    return _parseWithTranslation(raw, translated);
  }

  /// 对外暴露的 LRC 解析（歌曲信息页展示内嵌歌词用）
  List<LyricLine> parseLrc(String raw) => _parse(raw);

  /// 歌词 URL 文本缓存（部分源的歌词字段给的是链接而非内联文本）
  final _textCache = <String, Future<String>>{};

  /// 源自身给出的歌词（内联 LRC 文本或歌词 URL）；不可用时返回 null，
  /// 由调用方退回第三方歌词库。
  ///
  /// 此前完全没用上源自带歌词，只能拿歌名去撞第三方库，
  /// 撞不到就显示"暂无歌词"——播放条明明给了词。
  Future<List<LyricLine>?> fromSource(String? raw) async {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    var text = s;
    if (s.startsWith('http')) {
      try {
        text = await fetchText(s);
      } catch (_) {
        return null;
      }
      text = text.trim();
      // 歌词地址被重定向到网页时，整页 HTML 会被当成歌词逐行显示
      if (text.isEmpty || text.startsWith('<')) return null;
    }
    try {
      final lines = _parse(text);
      return lines.isEmpty ? null : lines;
    } catch (_) {
      return null;
    }
  }

  /// 下载歌词/文本资源，按 URL 缓存；空响应不入缓存以便重试
  Future<String> fetchText(String url) {
    return _textCache.putIfAbsent(url, () async {
      final resp = await _dio.get<String>(
        url,
        options: Options(
            responseType: ResponseType.plain,
            headers: const {'User-Agent': 'Mozilla/5.0 (Linux; Android 14)'},
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            validateStatus: (s) => s != null && s < 500),
      );
      final body = resp.data ?? '';
      if (body.trim().isEmpty) _textCache.remove(url);
      return body;
    });
  }

  List<LyricLine> _parse(String raw) {
    final lines = <LyricLine>[];
    final timeRe = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$');
    for (final line in raw.split('\n')) {
      final m = timeRe.firstMatch(line.trim());
      if (m != null) {
        lines.add(LyricLine(
          Duration(
              minutes: int.parse(m.group(1)!),
              milliseconds: ((double.parse(m.group(2)!)) * 1000).round()),
          m.group(3) ?? '',
        ));
      } else if (line.trim().isNotEmpty) {
        lines.add(LyricLine(null, line.trim()));
      }
    }
    if (lines.isEmpty) throw StateError('歌词为空');
    return lines;
  }

  /// 解析原文歌词并按时间轴对齐翻译歌词（如有）。
  /// 翻译歌词同为 LRC 格式，按时间戳精确匹配或取 1 秒内最近行对齐。
  List<LyricLine> _parseWithTranslation(String raw, String? translationRaw) {
    final original = _parse(raw);
    if (translationRaw == null || translationRaw.trim().isEmpty) {
      return original;
    }
    final translations = <Duration, String>{};
    final timeRe = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$');
    for (final line in translationRaw.split('\n')) {
      final m = timeRe.firstMatch(line.trim());
      if (m != null) {
        final t = Duration(
            minutes: int.parse(m.group(1)!),
            milliseconds: ((double.parse(m.group(2)!)) * 1000).round());
        final text = (m.group(3) ?? '').trim();
        if (text.isNotEmpty) translations[t] = text;
      }
    }
    if (translations.isEmpty) return original;
    return original.map((line) {
      if (line.time == null) return line;
      if (translations.containsKey(line.time)) {
        return LyricLine(line.time, line.text,
            translation: translations[line.time]);
      }
      Duration? closest;
      var minDiff = const Duration(seconds: 1);
      for (final t in translations.keys) {
        final diff = (t - line.time!).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closest = t;
        }
      }
      if (closest != null) {
        return LyricLine(line.time, line.text,
            translation: translations[closest]);
      }
      return line;
    }).toList();
  }

  /// 封面字节：走 dio（带 UA），结果按 url 缓存避免重复拉取
  Future<List<int>> fetchImage(String url) {
    return _imgCache.putIfAbsent(url, () async {
      final resp = await _dio.get<List<int>>(
        url,
        options: Options(
            responseType: ResponseType.bytes,
            headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14)'}),
      );
      return resp.data ?? [];
    });
  }
}

/// 把歌词行序列化回 LRC 文本（下载写标签用）；带时间的行加时间戳，
/// 纯文本歌词原样按行输出。结果为空返回 null。
String? lyricsToLrc(List<LyricLine> lines) {
  final sb = StringBuffer();
  for (final l in lines) {
    final t = l.time;
    if (t != null) {
      final total = t.inMilliseconds;
      final mm = (total ~/ 60000).toString().padLeft(2, '0');
      final rest = total % 60000;
      final ss = (rest ~/ 1000).toString().padLeft(2, '0');
      final cs = ((rest % 1000) ~/ 10).toString().padLeft(2, '0');
      sb.write('[$mm:$ss.$cs]');
    }
    sb.writeln(l.text);
  }
  final out = sb.toString().trim();
  return out.isEmpty ? null : out;
}

/// 音质 id → 中文显示名
const qualityDisplayNames = {
  '128k': '标准 128k',
  '320k': '高品 320k',
  'flac': '无损 FLAC',
  'flac24bit': 'Hi-Res',
  'standard': '标准音质',
  'exhigh': '超高音质',
  'lossless': '无损音质',
  'hires': 'Hi-Res',
};

/// 结果附带的音质列表（来自源声明的 qualities 字段）。
/// 兼容两种格式：
/// - 洛雪源：[{type:'128k', size, hash}, ...]（type 是音质档位）
/// - 通用：[{id, name}, ...]
List<({String id, String name})> parseQualities(Map<String, String>? extra) {
  final raw = extra?['qualities'];
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((q) {
          final id = (q['id'] ?? q['type'] ?? q['name'] ?? '').toString();
          return (
            id: id,
            name: qualityDisplayNames[id] ??
                (q['name'] ?? q['type'] ?? id).toString(),
          );
        })
        .where((q) => q.id.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}
