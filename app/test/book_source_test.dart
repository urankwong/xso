import 'dart:io';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:app/runtime/quickjs_runtime_impl.dart';
import 'package:source_engine/source_engine.dart';

/// 书籍源端到端实测：真实抓取 + JS 钩子解析 + 归一化结果。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  Future<SourceEngine> engine() async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      validateStatus: (s) => s != null && s < 500,
      headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/125'},
    ));
    return SourceEngine(
      jsRuntime: QuickJsRuntimeImpl(),
      fetcher: (url, {method = 'GET', headers = const {}, charset = 'utf-8'}) async {
        final r = await dio.request<String>(url,
            options: Options(method: method, headers: headers));
        return r.data ?? '';
      },
    );
  }

  for (final path in [
    'assets/sources/book_libgen_gl.json',
    'assets/sources/book_libgen_bz.json',
  ]) {
    test('书籍源实测 $path', () async {
      final src = parseSource(await rootBundle.loadString(path));
      final eng = await engine();
      final results = await eng
          .search(src, const SearchQuery(keyword: '1984'))
          .timeout(const Duration(seconds: 60));
      // ignore: avoid_print
      print('[BOOK] ${src.meta.name}: ${results.length} 条');
      for (final r in results.take(3)) {
        // ignore: avoid_print
        print('[BOOK]   ${r.title} | ${r.extra?['author']} | '
            '${r.extra?['publisher']} ${r.extra?['year']} | '
            '${r.extra?['format']} ${r.extra?['size']} | ${r.url.substring(0, 42)}…');
      }
      expect(results, isNotEmpty);
      expect(results.first.url, startsWith('https://libgen'));
      expect(results.first.extra?['format'], isNotEmpty);
    });
  }
}
