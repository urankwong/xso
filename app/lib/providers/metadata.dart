import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lyric.dart';

final metadataProvider = Provider<MetadataService>(
    (ref) => MetadataService(Dio(), ref.watch(lyricProvider)));

/// 在线匹配到的元数据集合
class SongMatch {
  final String? coverUrl;
  final String? title;
  final String? artist;
  final String? album;
  final String? year;
  final String source; // 'iTunes' / 'lrclib' / '源透传'

  const SongMatch({
    this.coverUrl,
    this.title,
    this.artist,
    this.album,
    this.year,
    this.source = '',
  });

  static const empty = SongMatch();
}

/// 元数据服务：封面取图优先级链 + iTunes/lrclib 在线匹配，LRU 内存缓存。
class MetadataService {
  final Dio _dio;
  final LyricService _lyric;
  MetadataService(this._dio, this._lyric);

  static const _cacheMax = 200;
  static const _ua = 'AggregatorApp v0.1';

  /// key = "title|artist"，map 字面量默认就是 LinkedHashMap（插入/访问有序）
  final _coverCache = <String, Future<SongMatch>>{};

  /// 封面取图链，返回 URL：① 源透传 http 直用；② iTunes 600x600；③ lrclib cover；④ null
  Future<String?> resolveCover({
    required String? sourceCover,
    required String title,
    required String? artist,
    String? album,
  }) async {
    if (sourceCover != null && sourceCover.startsWith('http')) {
      return sourceCover;
    }
    final m = await match(title: title, artist: artist, album: album);
    return m.coverUrl;
  }

  /// 封面取图链的字节形态（UI/写标签共用）；取不到返回 null。
  ///
  /// 与 [match] 同理缓存 Future：播放页背景与封面每帧重建时若都拿到新 Future，
  /// FutureBuilder 会不断回到加载态，画面就在"渐变兜底/转圈/图片"之间闪烁。
  final _bytesCache = <String, Future<Uint8List?>>{};

  Future<Uint8List?> coverBytes({
    required String? sourceCover,
    required String title,
    required String? artist,
    String? album,
  }) {
    final key = '${sourceCover ?? ''}|$title|${artist ?? ''}|${album ?? ''}';
    final cached = _bytesCache.remove(key);
    if (cached != null) {
      _bytesCache[key] = cached; // 移到队尾（最近使用）
      return cached;
    }
    final future = _coverBytesUncached(
        sourceCover: sourceCover,
        title: title,
        artist: artist,
        album: album);
    _bytesCache[key] = future;
    if (_bytesCache.length > _cacheMax) {
      _bytesCache.remove(_bytesCache.keys.first);
    }
    // 空结果不长期缓存：可能只是当时网络失败，下次进入还能重试
    future.then<void>((bytes) {
      if (bytes == null && _bytesCache[key] == future) _bytesCache.remove(key);
    }).catchError((_) {
      if (_bytesCache[key] == future) _bytesCache.remove(key);
    });
    return future;
  }

  Future<Uint8List?> _coverBytesUncached({
    required String? sourceCover,
    required String title,
    required String? artist,
    String? album,
  }) async {
    final url = await resolveCover(
        sourceCover: sourceCover, title: title, artist: artist, album: album);
    if (url == null) return null;
    try {
      final bytes = await _lyric.fetchImage(url);
      if (bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 在线匹配（含 album/year 补充），LRU 缓存。失败静默返回空。
  Future<SongMatch> match({
    required String title,
    String? artist,
    String? album,
  }) {
    final t = title.trim();
    if (t.isEmpty) return Future.value(SongMatch.empty);
    final key = '$t|${(artist ?? '').trim()}';
    final cached = _coverCache.remove(key);
    if (cached != null) {
      final entry = cached;
      _coverCache[key] = entry; // 移到队尾（最近使用）
      return entry;
    }
    final future = _matchOnline(t, artist?.trim(), album?.trim());
    _coverCache[key] = future;
    if (_coverCache.length > _cacheMax) {
      _coverCache.remove(_coverCache.keys.first);
    }
    // 完全没匹配到时不长期缓存，允许下次网络恢复后重试
    future.then((m) {
      if (m.coverUrl == null && m.album == null && _coverCache[key] == future) {
        _coverCache.remove(key);
      }
    }).catchError((_) {
      _coverCache.remove(key);
    });
    return future;
  }

  Future<SongMatch> _matchOnline(String title, String? artist, String? album) async {
    SongMatch? it;
    try {
      it = await _iTunes(title, artist);
    } catch (_) {}
    if (it != null && it.coverUrl != null) {
      return it;
    }
    try {
      final cover = await _lyric.coverOf(title: title, artist: artist ?? '');
      if (cover != null) {
        return SongMatch(coverUrl: cover, album: album, source: 'lrclib');
      }
    } catch (_) {}
    return it ?? SongMatch(album: album, source: '');
  }

  /// iTunes Search API：term = "artist title"，取第一条的 600x600 封面与专辑/年份
  Future<SongMatch?> _iTunes(String title, String? artist) async {
    final term = (artist == null || artist.isEmpty) ? title : '$artist $title';
    final resp = await _dio.get<Map<String, dynamic>>(
      'https://itunes.apple.com/search',
      queryParameters: {'term': term, 'entity': 'song', 'limit': 5},
      options: Options(
          headers: {'User-Agent': _ua},
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (s) => s != null && s < 500),
    );
    final results = (resp.data?['results'] as List?) ?? const [];
    if (resp.statusCode != 200 || results.isEmpty) return null;
    // 优先取标题包含关系最接近的一条
    Map? best;
    for (final r in results.whereType<Map>()) {
      final name = (r['trackName'] ?? '').toString();
      if (best == null || name.toLowerCase().contains(title.toLowerCase())) {
        best = r;
        if (name.toLowerCase() == title.toLowerCase()) break;
      }
    }
    if (best == null) return null;
    final art = (best['artworkUrl100'] ?? '').toString();
    String? cover;
    if (art.isNotEmpty) {
      cover = art.replaceAll('100x100bb', '600x600bb');
    }
    final released = (best['releaseDate'] ?? '').toString();
    final year = released.length >= 4 ? released.substring(0, 4) : null;
    return SongMatch(
      coverUrl: cover,
      title: (best['trackName'] ?? '').toString().isEmpty
          ? null
          : best['trackName'].toString(),
      artist: (best['artistName'] ?? '').toString().isEmpty
          ? null
          : best['artistName'].toString(),
      album: (best['collectionName'] ?? '').toString().isEmpty
          ? null
          : best['collectionName'].toString(),
      year: year,
      source: 'iTunes',
    );
  }
}
