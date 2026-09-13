import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:app/runtime/quickjs_runtime_impl.dart';
import 'package:source_engine/source_engine.dart';

/// 有声播客专辑两段式冒烟：懒人听书 搜索专辑 → 拉章节 → 解析播放地址
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('懒人听书 专辑流程冒烟', () async {
    final rt = QuickJsRuntimeImpl();
    try {
      final js = await rootBundle.loadString('assets/sources/mf_lrts.js');
      final src = await MusicFreeAdapter(jsRuntime: rt)
          .wrap(js, name: '懒人听书', type: SourceType.audiobook);
      expect(src.meta.type, SourceType.audiobook);

      final albums = await src
          .search(const SearchQuery(keyword: '三体', page: 1))
          .timeout(const Duration(seconds: 40));
      // ignore: avoid_print
      print('[SMOKE] 专辑数: ${albums.length} | 首张: ${albums.first.title}'
          ' | 主播: ${albums.first.extra?['artist']}'
          ' | needsDetail: ${albums.first.needsDetail}');
      expect(albums, isNotEmpty);
      expect(albums.first.needsDetail, isTrue);

      final tracks = await src
          .fetchAlbumTracks(albums.first)
          .timeout(const Duration(seconds: 40));
      // ignore: avoid_print
      print('[SMOKE] 章节数: ${tracks.length} | 首章: ${tracks.first.title}');
      expect(tracks, isNotEmpty);

      final url = await src
          .resolveMedia(tracks.first)
          .timeout(const Duration(seconds: 40));
      // ignore: avoid_print
      print('[SMOKE] 首章播放地址: ${url.substring(0, url.length.clamp(0, 90))}');
      expect(url.startsWith('http'), isTrue);
    } finally {
      rt.dispose();
    }
  });
}
