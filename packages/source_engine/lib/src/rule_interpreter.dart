import 'dart:convert' show jsonDecode;
import 'package:html/dom.dart' as dom;
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
      row[name] = _extractField(item, rule);
    });
    return row;
  }).toList();
}

/// 按候选链依次尝试，取首个命中且非空的值，再做可选的 ## 正则替换。
/// 全部候选落空才返回 null（Legado `||` 语义）。
String? _extractField(dom.Element item, FieldRule rule) {
  for (final sel in rule.candidates) {
    dom.Element? el;
    if (sel.isEmpty) {
      // Legado 语义：`@href` / `@text` 这种没有选择器的写法表示
      // 对**条目自身**取属性（常见于 container 已经是 <a> 的情况）。
      // 此前直接跳过，导致这类源的 url 全为 null、被引擎当作无效条目丢弃。
      el = item;
    } else {
      try {
        el = item.querySelector(sel);
      } catch (_) {
        continue; // 非法选择器不连坐，继续试下一个候选
      }
    }
    if (el == null) continue;
    final v = _attrOf(el, rule.attr);
    if (v != null && v.trim().isNotEmpty) return _applyReplace(v, rule);
  }
  return null;
}

/// 取元素属性：text/html 为内置语义，其余按 HTML 属性名取（href/title/src…）
String? _attrOf(dom.Element el, String attr) {
  switch (attr) {
    case 'text':
      return el.text.trim();
    case 'html':
    // Legado 的 @html 取完整内部 HTML
      return el.innerHtml;
    default:
      return el.attributes[attr];
  }
}

/// Legado `##` 正则替换：命中部分替换为 replacement（缺省空串即删除）。
/// 正则非法时降级返回原值，不让一条坏规则炸掉整个源。
String _applyReplace(String v, FieldRule rule) {
  if (!rule.hasReplace) return v;
  try {
    return v.replaceAll(RegExp(rule.replaceRegex!), rule.replacement ?? '');
  } catch (_) {
    return v;
  }
}

/// 提取选择器命中的所有元素的纯文本（两段式详情正文用）
String extractHtmlText(String html, String selector) {
  final doc = html_parser.parse(html);
  return doc
      .querySelectorAll(selector)
      .map((e) => e.text.trim())
      .join('\n');
}

// ── 书籍详情 / 目录 / 正文 用的整页取值 API ──────────────────────────

/// 从整页 HTML 按单条规则取一个字段（书籍详情元信息用）。
/// 取到空值或未命中返回 null（不是空串，便于上层用 `?? '—'` 兜底）。
String? extractField(String html, FieldRule rule) {
  try {
    final root = html_parser.parse(html).documentElement;
    if (root == null) return null;
    final v = _extractField(root, rule);
    return (v == null || v.trim().isEmpty) ? null : v;
  } catch (_) {
    return null;
  }
}

/// 从整页 HTML 取出目录条目元素（按 container 选择器）。
/// 非法选择器返回空列表，不抛错。
List<dom.Element> selectAll(String html, String selector) {
  try {
    return html_parser.parse(html).querySelectorAll(selector);
  } catch (_) {
    return const [];
  }
}

/// 在给定元素内按规则取字段（目录条目里取章节名/链接用）
String? extractFieldIn(dom.Element item, FieldRule rule) {
  final v = _extractField(item, rule);
  return (v == null || v.trim().isEmpty) ? null : v;
}

/// JSON 规则解释：jsonPath 定位条目数组，条目须为对象，字段值转字符串。
List<Map<String, String?>> interpretJson(String json,
    {required String jsonPath, Map<String, FieldRule>? fields}) {
  final path = JsonPath(jsonPath);
  final matches = path.read(jsonDecode(json));
  return matches.map((m) {
    final value = m.value;
    if (value is! Map) {
      throw FormatException('jsonPath 命中的条目不是对象: $value');
    }
    // 字段级 jsonPath：Legado 的 @json 模式下
    // ruleSearch.name/bookUrl 本身就是字段路径（$.title / title）
    if (fields != null && fields.isNotEmpty) {
      final row = <String, String?>{};
      fields.forEach((name, rule) {
        row[name] = _readJsonPath(value, rule.selector);
      });
      return row;
    }
    return value.map((k, v) => MapEntry(k.toString(), v?.toString()));
  }).toList();
}

/// 按 jsonPath 从单个条目取值；缺 `$` 前缀时自动补（Legado 常写 data.list）
String? _readJsonPath(Object root, String expr) {
  final p = expr.trim();
  if (p.isEmpty) return null;
  try {
    final e = p.startsWith(r'$') ? p : r'$.' + p;
    final hits = JsonPath(e).read(root);
    return hits.isNotEmpty ? hits.first.value?.toString() : null;
  } catch (_) {
    return null;
  }
}
