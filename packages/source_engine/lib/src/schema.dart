import 'dart:convert';
import 'package:core/core.dart';

class SourceSchemaException implements Exception {
  final String message;
  SourceSchemaException(this.message);
  @override
  String toString() => 'SourceSchemaException: $message';
}

/// 源文件完整模型（自有格式）
class Source {
  final SourceMeta meta;
  final SearchRule? search;
  final DetailRule? detail;
  final HooksRule? hooks;
  const Source({
    required this.meta,
    this.search,
    this.detail,
    this.hooks,
  });
}

class SearchRule {
  final RequestRule request;
  final ResultRule? result;
  const SearchRule({required this.request, this.result});
}

class DetailRule {
  final RequestRule request;
  final String content; // 正文 CSS 选择器
  final List<String> extractors; // 启用的网盘识别器
  const DetailRule({
    required this.request,
    required this.content,
    this.extractors = const ['baidu', 'quark', 'aliyun', '123pan'],
  });
}

class RequestRule {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String charset;
  const RequestRule({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.charset = 'utf-8',
  });
}

class ResultRule {
  final String? container;
  final Map<String, FieldRule>? fields;
  final String? jsonPath;
  const ResultRule({this.container, this.fields, this.jsonPath});
}

class FieldRule {
  final String selector;
  final String attr; // text | href | html
  const FieldRule({required this.selector, this.attr = 'text'});
}

class HooksRule {
  final String? buildRequest;
  final String? parse;
  const HooksRule({this.buildRequest, this.parse});
}

/// 解析并校验源 JSON。任何结构问题都抛 SourceSchemaException。
Source parseSource(String json) {
  Map<String, dynamic> root;
  try {
    root = jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    throw SourceSchemaException('源不是合法 JSON');
  }

  final meta = _parseMeta(root);
  final search = _parseSearch(root);
  final detail = _parseDetail(root);
  final hooks = _parseHooks(root);
  if (search == null) {
    throw SourceSchemaException('自有格式源必须包含 search 段');
  }
  return Source(meta: meta, search: search, detail: detail, hooks: hooks);
}

SourceMeta _parseMeta(Map<String, dynamic> root) {
  final meta = _asMap(root['meta'], 'meta');
  final id = _reqStr(meta, 'id', 'meta.id');
  final name = _reqStr(meta, 'name', 'meta.name');
  final typeStr = _reqStr(meta, 'type', 'meta.type');
  final type = SourceType.values.where((t) => t.name == typeStr).firstOrNull;
  if (type == null) {
    throw SourceSchemaException('meta.type "$typeStr" 不受支持');
  }
  return SourceMeta(
    id: id,
    name: name,
    type: type,
    version: (meta['version'] as num?)?.toInt() ?? 1,
    engine: meta['engine'] as String? ?? 'script',
    updateUrl: meta['updateUrl'] as String?,
  );
}

SearchRule? _parseSearch(Map<String, dynamic> root) {
  if (root['search'] == null) return null;
  final search = _asMap(root['search'], 'search');
  final req = _asMap(search['request'], 'search.request');
  final url = _reqStr(req, 'url', 'search.request.url');
  final headers = <String, String>{};
  (req['headers'] as Map<String, dynamic>?)
      ?.forEach((k, v) => headers[k] = v.toString());
  final result = _parseResult(search['result']);
  return SearchRule(
    request: RequestRule(
      url: url,
      method: req['method'] as String? ?? 'GET',
      headers: headers,
      charset: req['charset'] as String? ?? 'utf-8',
    ),
    result: result,
  );
}

ResultRule? _parseResult(dynamic raw) {
  if (raw == null) return null;
  final result = _asMap(raw, 'search.result');
  final container = result['container'] as String?;
  final jsonPath = result['jsonPath'] as String?;
  if (container != null && jsonPath != null) {
    throw SourceSchemaException('container 与 jsonPath 互斥，只能选一个');
  }
  Map<String, FieldRule>? fields;
  final rawFields = result['fields'] as Map<String, dynamic>?;
  if (rawFields != null) {
    fields = {};
    rawFields.forEach((name, rule) {
      final m = _asMap(rule, 'search.result.fields.$name');
      fields![name] = FieldRule(
        selector: _reqStr(m, 'selector', 'fields.$name.selector'),
        attr: m['attr'] as String? ?? 'text',
      );
    });
  }
  return ResultRule(container: container, fields: fields, jsonPath: jsonPath);
}

DetailRule? _parseDetail(Map<String, dynamic> root) {
  if (root['detail'] == null) return null;
  final detail = _asMap(root['detail'], 'detail');
  final req = _asMap(detail['request'], 'detail.request');
  final content = _reqStr(detail, 'content', 'detail.content');
  final extractors = (detail['extractors'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
      const ['baidu', 'quark', 'aliyun', '123pan'];
  return DetailRule(
    request: RequestRule(url: _reqStr(req, 'url', 'detail.request.url')),
    content: content,
    extractors: extractors,
  );
}

HooksRule? _parseHooks(Map<String, dynamic> root) {
  if (root['hooks'] == null) return null;
  final hooks = _asMap(root['hooks'], 'hooks');
  return HooksRule(
    buildRequest: hooks['buildRequest'] as String?,
    parse: hooks['parse'] as String?,
  );
}

Map<String, dynamic> _asMap(dynamic v, String path) {
  if (v is! Map<String, dynamic>) {
    throw SourceSchemaException('$path 必须是对象');
  }
  return v;
}

String _reqStr(Map<String, dynamic> m, String key, String path) {
  final v = m[key];
  if (v is! String || v.isEmpty) {
    throw SourceSchemaException('$path 必填且为非空字符串');
  }
  return v;
}
