import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/src/schema.dart';

class LegadoUnsupportedException implements Exception {
  final String feature;
  LegadoUnsupportedException(this.feature);
  @override
  String toString() => 'LegadoUnsupportedException: 不支持 $feature';
}

/// Legado 书源子集适配器：把简单书源翻译为内部自有格式 Source。
/// 支持：{{key}} 模板、@css:/@json: 规则、@text/@href 提取。
/// 不支持：java.* 宿主、##/||/&& 规则链 → 导入时明确报错。
class LegadoAdapter {
  static const _unsupportedMarkers = ['java.', '##', '||', '&&', '<js>', '{{js'];

  Source translate(String legadoJson) {
    final Map<String, dynamic> raw;
    try {
      raw = jsonDecode(legadoJson) as Map<String, dynamic>;
    } catch (_) {
      throw LegadoUnsupportedException('非法 JSON');
    }

    // 全量扫描不支持语法
    for (final marker in _unsupportedMarkers) {
      if (legadoJson.contains(marker)) {
        throw LegadoUnsupportedException('语法 "$marker"');
      }
    }

    final searchUrl = raw['searchUrl'] as String?;
    final ruleSearch = raw['ruleSearch'] as Map<String, dynamic>?;
    if (searchUrl == null || ruleSearch == null) {
      throw LegadoUnsupportedException('缺少 searchUrl 或 ruleSearch');
    }

    // {{key}} → {{keyword}}
    final url = searchUrl.replaceAll('{{key}}', '{{keyword}}');

    final bookList = ruleSearch['bookList'] as String? ?? '';
    final container = _parseSelector(bookList);
    final nameRule = ruleSearch['name'] as String? ?? '';
    final bookUrlRule = ruleSearch['bookUrl'] as String? ?? '';

    return Source(
      meta: SourceMeta(
        id: 'legado://${raw['bookSourceUrl'] ?? ''}',
        name: raw['bookSourceName'] as String? ?? 'Legado书源',
        type: SourceType.book,
        version: 1,
        origin: 'legado',
      ),
      search: SearchRule(
        request: RequestRule(url: url),
        result: ResultRule(
          container: container,
          fields: {
            'title': FieldRule(
              selector: _parseSelector(nameRule),
              attr: _extractAttr(nameRule),
            ),
            'url': FieldRule(
              selector: _parseSelector(bookUrlRule),
              attr: _extractAttr(bookUrlRule),
            ),
          },
        ),
      ),
    );
  }

  /// 解析 Legado 规则为本引擎 CSS 选择器。
  /// 支持 "@css:sel" / "sel"（默认 CSS 子集）
  String _parseSelector(String rule) {
    if (rule.startsWith('@css:')) {
      return rule.substring(5).split('@').first.trim();
    }
    if (rule.startsWith('@json:')) {
      return rule.substring(6).split('@').first.trim();
    }
    // 裸选择器（Legado 默认 JSoup 语法，简单类名/tag 选择器与 CSS 兼容）
    return rule.split('@').first.trim();
  }

  /// 提取属性：@text → text（默认）、@href → href
  String _extractAttr(String rule) {
    if (rule.contains('@href')) return 'href';
    if (rule.contains('@html')) return 'html';
    return 'text';
  }
}
