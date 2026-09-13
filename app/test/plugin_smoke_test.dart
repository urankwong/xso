import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:app/runtime/quickjs_runtime_impl.dart';
import 'package:source_engine/source_engine.dart';

/// 真实社区插件冒烟：逐个 wrap + 搜索，输出结果数与首条标题。
/// 纯观测（print），断言只保证"不炸测试框架"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 会用 mock HttpClient 劫持全部请求（统一 400 空体），
  // 冒烟需要真实网络，这里还原为系统默认。
  HttpOverrides.global = null;

  const candidates = [
    'assets/sources/mf_gd_music.js',
    'assets/sources/mf_kugou.js',
    'assets/sources/mf_kuwo.js',
    'assets/sources/mf_qianqian.js',
    'assets/sources/mf_netease_cloud.js',
    'assets/sources/mf_qq_music.js',
    'assets/sources/mf_qq_zhuyue.js',
    'assets/sources/mf_qishui_vip.js',
    'assets/sources/mf_kuaile_qishui.js',
    'assets/sources/mf_yuanli_wy.js',
    'assets/sources/mf_yuanli_qq.js',
    'assets/sources/mf_yuanli_kg.js',
    'assets/sources/mf_yuanli_kw.js',
    'assets/sources/mf_yuanli_migu.js',
    'assets/sources/mf_migu.js',
    'assets/sources/mf_bilibili.js',
    'assets/sources/mf_bilibili_cookie.js',
    'assets/sources/mf_ximalaya.js',
    'assets/sources/mf_maoer_fm.js',
    'assets/sources/mf_aiting.js',
  ];

  test('社区插件逐源搜索冒烟', () async {
    for (final path in candidates) {
      final rt = QuickJsRuntimeImpl();
      try {
        final js = await rootBundle.loadString(path);
        final src = await MusicFreeAdapter(jsRuntime: rt)
            .wrap(js)
            .timeout(const Duration(seconds: 30));
        final results = await src
            .search(const SearchQuery(keyword: '晴天', page: 1))
            .timeout(const Duration(seconds: 40));
        // ignore: avoid_print
        print('[SMOKE] ${src.meta.name} ($path): ${results.length} 条'
            ' ${results.isNotEmpty ? '| 首条: ${results.first.title}' : ''}');
      } catch (e) {
        // ignore: avoid_print
        print('[SMOKE] $path 失败: ${e.toString().substring(0, e.toString().length.clamp(0, 160))}');
        try {
          final logs = await rt.evaluate('JSON.stringify(__mfLogs || [])');
          // ignore: avoid_print
          print('[SMOKE]   插件日志: ${logs.length > 400 ? logs.substring(0, 400) : logs}');
        } catch (_) {}
      } finally {
        rt.dispose();
      }
    }
    expect(true, isTrue);
  });
}
