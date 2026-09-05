import 'dart:convert' show jsonDecode;
import 'package:html/parser.dart' as html_parser;
import 'package:json_path/json_path.dart';
import 'package:source_engine/src/schema.dart';

/// HTML 规则解释：container 定位条目，fields 提取字段。
/// 条目内字段选择器匹配不到时该字段为 null（容错，不抛错）。
List<Map<String, String?>> interpretHtml(
  String html, {
  required String container,
  required Map<String, FieldRule> fields,
}) {
  final doc = html_parser.parse(html);
  final items = doc.querySelectorAll(container);
  return items.map((item) {
    final row = <String, String?>{};
    fields.forEach((name, rule) {
      final el = item.querySelector(rule.selector);
      if (el == null) {
        row[name] = null;
        return;
      }
      switch (rule.attr) {
        case 'href':
          row[name] = el.attributes['href'];
        case 'html':
          row[name] = el.innerHtml;
        default:
          row[name] = el.text.trim();
      }
    });
    return row;
  }).toList();
}

/// 提取选择器命中的所有元素的纯文本（两段式详情正文用）
String extractHtmlText(String html, String selector) {
  final doc = html_parser.parse(html);
  return doc
      .querySelectorAll(selector)
      .map((e) => e.text.trim())
      .join('\n');
}

/// JSON 规则解释：jsonPath 定位条目数组，条目须为对象，字段值转字符串。
List<Map<String, String?>> interpretJson(String json,
    {required String jsonPath}) {
  final path = JsonPath(jsonPath);
  final matches = path.read(jsonDecode(json));
  return matches.map((m) {
    final value = m.value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v?.toString()));
    }
    throw FormatException('jsonPath 命中的条目不是对象: $value');
  }).toList();
}
