import 'dart:io';
import 'package:source_engine/source_engine.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  late String validJson;

  setUpAll(() {
    validJson = File('test/fixtures/valid_source.json').readAsStringSync();
  });

  test('合法源解析成功并转 SourceMeta', () {
    final source = parseSource(validJson);
    expect(source.meta.id, 'com.example.mag');
    expect(source.meta.type, SourceType.magnet);
    expect(source.search!.result!.container, 'div.result-item');
    expect(source.search!.result!.fields!['title']!.selector, 'h3');
  });

  test('坏 JSON 报 SourceSchemaException', () {
    expect(() => parseSource('{ not json'),
        throwsA(isA<SourceSchemaException>()));
  });

  test('缺 meta.id 报错', () {
    final noId = validJson.replaceAll('"id": "com.example.mag",', '');
    expect(() => parseSource(noId), throwsA(isA<SourceSchemaException>()));
  });

  test('缺 search 段报错', () {
    final noSearch = '{"meta":{"id":"x","name":"n","type":"magnet","version":1}}';
    expect(() => parseSource(noSearch), throwsA(isA<SourceSchemaException>()));
  });

  test('container 与 jsonPath 互斥，同时给出报错', () {
    final withBoth = validJson.replaceFirst(
      '"container": "div.result-item",',
      '"container": "div.result-item", "jsonPath": "\$.list[*]",',
    );
    expect(() => parseSource(withBoth), throwsA(isA<SourceSchemaException>()));
  });

  test('两段式 detail 段解析', () {
    const src = '{"meta":{"id":"t","name":"n","type":"game","version":1},'
        '"search":{"request":{"url":"https://a.com?q={{keyword}}"}},'
        '"detail":{"request":{"url":"https://a.com{{detailUrl}}"},'
        '"content":"div.content","extractors":["quark"]}}';
    final s = parseSource(src);
    expect(s.detail!.content, 'div.content');
    expect(s.detail!.extractors, ['quark']);
  });
}
