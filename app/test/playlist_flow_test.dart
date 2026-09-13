import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:app/runtime/quickjs_runtime_impl.dart';
import 'package:source_engine/source_engine.dart';

/// 歌单链路实测：用插件推荐歌单接口取一个真实歌单 id，再解析整单曲目。
Future<Map<String, dynamic>> _call(
    QuickJsRuntimeImpl rt, String fn, List args) async {
  await rt.evaluate(
      '__mfCall(${jsonEncode(fn)}, ${jsonEncode(jsonEncode(args))})',
      timeout: const Duration(seconds: 20));
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final raw = await rt.evaluate('__mfCallTake()');
    if (raw != '__pending__') {
      final d = jsonDecode(raw);
      if (d is Map && d['__error'] != null) {
        throw Exception('$fn 失败: ${d['__error']}');
      }
      return (d as Map?)?.cast<String, dynamic>() ?? {};
    }
  }
  throw TimeoutException('$fn 超时');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('歌单解析实测（网易云）', () async {
    final rt = QuickJsRuntimeImpl();
    final js = await rootBundle.loadString('assets/sources/mf_netease_cloud.js');
    final src = await MusicFreeAdapter(jsRuntime: rt)
        .wrap(js)
        .timeout(const Duration(seconds: 30));

    final tags = await _call(rt, 'getRecommendSheetTags', []);
    final tagList = (tags['data'] ?? tags['tags'] ?? []) as List;
    // ignore: avoid_print
    print('[SHEET] 推荐标签 ${tagList.length} 个：'
        '${tagList.take(4).map((t) => t is Map ? t['title'] : t).join(' | ')}');
    final tag = tagList.isEmpty
        ? {'title': '推荐'}
        : (tagList.first is Map ? tagList.first : {'title': tagList.first});

    final sheets = await _call(rt, 'getRecommendSheetsByTag', [tag, 1]);
    final sheetList = (sheets['data'] ?? sheets['list'] ?? []) as List;
    // ignore: avoid_print
    print('[SHEET] 标签下歌单 ${sheetList.length} 个：'
        '${sheetList.take(3).map((s) => s is Map ? '${s['title']}#${s['id']}' : s).join(' | ')}');
    if (sheetList.isEmpty) return;
    final sheetId = (sheetList.first as Map)['id'].toString();

    final tracks = await src
        .fetchSheetTracks(sheetId)
        .timeout(const Duration(seconds: 60));
    // ignore: avoid_print
    print('[SHEET] 歌单 $sheetId 解析出曲目 ${tracks.length} 首：'
        '${tracks.take(3).map((t) => '${t.title}-${t.extra?['artist']}').join(' | ')}');
    expect(tracks, isNotEmpty);
    rt.dispose();
  });
}
