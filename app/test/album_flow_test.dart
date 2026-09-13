import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:app/runtime/quickjs_runtime_impl.dart';
import 'package:source_engine/source_engine.dart';

/// 专辑链路实测：搜专辑 → 取专辑条目 → 拉曲目列表。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  for (final path in [
    'assets/sources/mf_netease_cloud.js',
    'assets/sources/mf_qq_music.js',
  ]) {
    test('专辑流程实测 $path', () async {
      final rt = QuickJsRuntimeImpl();
      final js = await rootBundle.loadString(path);
      final src =
          await MusicFreeAdapter(jsRuntime: rt).wrap(js).timeout(const Duration(seconds: 30));

      // 先用普通搜索拿到一条带专辑名的曲目
      final songs = await src
          .search(const SearchQuery(keyword: '晴天', page: 1))
          .timeout(const Duration(seconds: 40));
      final albumName = songs
          .map((s) => s.extra?['album'] ?? '')
          .firstWhere((a) => a.isNotEmpty, orElse: () => '');
      // ignore: avoid_print
      print('[ALBUM] ${src.meta.name} 曲目 ${songs.length} 条，专辑名样本：$albumName');
      if (albumName.isEmpty) return;

      final albums = await src
          .searchAlbums(albumName)
          .timeout(const Duration(seconds: 40));
      // ignore: avoid_print
      print('[ALBUM] 搜到专辑 ${albums.length} 张：'
          '${albums.take(3).map((a) => '${a.title}(${a.extra?['itemId']})').join(' | ')}');
      if (albums.isEmpty) return;

      final tracks = await src
          .fetchAlbumTracks(albums.first)
          .timeout(const Duration(seconds: 40));
      // ignore: avoid_print
      print('[ALBUM] 《${albums.first.title}》曲目 ${tracks.length} 首：'
          '${tracks.take(3).map((t) => t.title).join(' | ')}');
      rt.dispose();
    });
  }
}
