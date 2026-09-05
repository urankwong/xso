import 'dart:io';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  late String html;

  setUpAll(() {
    html = File('test/fixtures/search_page.html').readAsStringSync();
  });

  test('CSS 选择器解析出所有条目与字段', () {
    final rows = interpretHtml(
      html,
      container: 'div.result-item',
      fields: {
        'title': const FieldRule(selector: 'h3'),
        'url': const FieldRule(selector: 'a.mag-link', attr: 'href'),
        'size': const FieldRule(selector: 'span.size'),
      },
    );
    expect(rows, hasLength(2));
    expect(rows[0]['title'], '资源A');
    expect(rows[0]['url'], 'magnet:?xt=urn:btih:aaa');
    expect(rows[0]['size'], '1.2GB');
    expect(rows[1]['size'], '800MB');
  });

  test('缺字段的条目该字段为 null（容错）', () {
    final rows = interpretHtml(
      html,
      container: 'div.result-item',
      fields: {
        'date': const FieldRule(selector: 'span.date'),
        'title': const FieldRule(selector: 'h3'),
      },
    );
    expect(rows[0]['date'], '2026-01-01');
    expect(rows[1]['date'], isNull); // 第二条没有 date
  });

  test('JSONPath 解析 JSON 响应', () {
    const json =
        '{"data":{"list":[{"title":"A","url":"u1"},{"title":"B","url":"u2"}]}}';
    final rows = interpretJson(json, jsonPath: r'$.data.list[*]');
    expect(rows, hasLength(2));
    expect(rows[0]['title'], 'A');
  });

  test('container 无匹配返回空列表（交由上层标记"无结果"）', () {
    final rows = interpretHtml(
      html,
      container: 'div.not-exist',
      fields: {'title': const FieldRule(selector: 'h3')},
    );
    expect(rows, isEmpty);
  });
}
