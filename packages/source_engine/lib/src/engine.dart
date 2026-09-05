import 'dart:async';
import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/src/js_runtime.dart';
import 'package:source_engine/src/rule_interpreter.dart';
import 'package:source_engine/src/schema.dart';
import 'package:source_engine/src/url_template.dart';

class SourceExecutionException implements Exception {
  final String sourceId;
  final String message;
  SourceExecutionException(this.sourceId, this.message);
  @override
  String toString() => 'SourceExecutionException($sourceId): $message';
}

/// 网络层抽象：由 app 层提供 dio 实现；引擎测试用假实现。
/// charset 处理 GBK 站点（app 层 dio + gbk 解码器负责）。
typedef Fetcher = Future<String> Function(
  String url, {
  String method,
  Map<String, String> headers,
  String charset,
});

/// 源引擎：编排"钩子→请求→解析→归一化"完整流程。
class SourceEngine {
  final JsRuntime jsRuntime;
  final Fetcher fetcher;
  static const hookTimeout = Duration(seconds: 5);
  static const searchTimeout = Duration(seconds: 10);

  SourceEngine({required this.jsRuntime, required this.fetcher}) {
    // 沙箱 API 白名单注册：JS 只能通过这些与外界交互
    jsRuntime.registerHostFunction('log', (args) async => null);
  }

  /// 单段/两段式列表搜索，返回归一化结果
  Future<List<SearchResult>> search(Source source, SearchQuery query) async {
    try {
      final rule = source.search!;
      final url = renderUrlTemplate(
        rule.request.url,
        keyword: query.keyword,
        page: query.page,
      );
      final body = await fetcher(
        url,
        method: rule.request.method,
        headers: rule.request.headers,
        charset: rule.request.charset,
      ).timeout(searchTimeout);
      final rows = await _parseRows(source, body);
      // 表头/占位行等没有 url 的条目直接丢弃（url 是结果的最低要求）
      final usable =
          rows.where((row) => (row['url'] ?? '').isNotEmpty).toList();
      final twoPhase = source.detail != null;
      return usable
          .map((row) => _toResult(source, row, needsDetail: twoPhase))
          .toList();
    } on SourceExecutionException {
      rethrow;
    } catch (e) {
      throw SourceExecutionException(source.meta.id, e.toString());
    }
  }

  /// 两段式：详情页二次请求 + 正文网盘识别
  Future<List<SearchResult>> fetchDetail(
      Source source, SearchResult item) async {
    try {
      final detail = source.detail!;
      final detailUrl = item.url; // 列表 fields.url 即 detailUrl
      final url = renderUrlTemplate(detail.request.url, detailUrl: detailUrl);
      final body = await fetcher(url).timeout(searchTimeout);

      // 正文选择器切出正文文本
      final contentText = extractHtmlText(body, detail.content);

      // 内置网盘识别器提取（App 级能力，core 提供）
      final links = detectPanLinks(contentText);
      return links
          .map((l) => SearchResult(
                sourceId: source.meta.id,
                sourceName: source.meta.name,
                type: source.meta.type,
                title: item.title,
                url: l.url,
                extractCode: l.extractCode,
                extra: {'provider': l.provider.name},
              ))
          .toList();
    } catch (e) {
      throw SourceExecutionException(source.meta.id, e.toString());
    }
  }

  /// 规则解释：parse 钩子兜底 / jsonPath / container+fields
  Future<List<Map<String, String?>>> _parseRows(
      Source source, String body) async {
    final result = source.search!.result;
    // 1) parse 钩子兜底优先级最高（作者显式声明用 JS）
    final parseHook = source.hooks?.parse;
    if (parseHook != null && parseHook.isNotEmpty) {
      return _runParseHook(parseHook, body);
    }
    // 2) JSON API
    if (result?.jsonPath != null) {
      return interpretJson(body, jsonPath: result!.jsonPath!);
    }
    // 3) HTML 规则
    if (result?.container != null) {
      return interpretHtml(body,
          container: result!.container!, fields: result.fields ?? {});
    }
    throw SourceExecutionException(source.meta.id, '源缺少可用的结果解析规则');
  }

  Future<List<Map<String, String?>>> _runParseHook(
      String hook, String body) async {
    final script = '(function(body){ $hook })(${jsonEncode(body)})';
    final raw = await jsRuntime.evaluate(script, timeout: hookTimeout);
    return (jsonDecode(raw) as List)
        .map((e) =>
            (e as Map).map((k, v) => MapEntry(k.toString(), v?.toString())))
        .toList();
  }

  SearchResult _toResult(Source source, Map<String, String?> row,
      {required bool needsDetail}) {
    final extra = Map<String, String?>.from(row)
      ..remove('title')
      ..remove('url')
      ..remove('code');
    return SearchResult(
      sourceId: source.meta.id,
      sourceName: source.meta.name,
      type: source.meta.type,
      title: row['title'] ?? '(无标题)',
      url: row['url'] ?? '',
      extractCode: row['code'],
      extra: extra.map((k, v) => MapEntry(k, v ?? '')),
      needsDetail: needsDetail,
    );
  }
}
