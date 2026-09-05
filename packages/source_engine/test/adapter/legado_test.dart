import 'dart:io';
import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  late String legadoJson;

  setUpAll(() {
    legadoJson = File('test/fixtures/legado_source.json').readAsStringSync();
  });

  test('翻译为内部自有格式 Source', () {
    final source = LegadoAdapter().translate(legadoJson);
    expect(source.meta.type, SourceType.book);
    expect(source.meta.origin, 'legado');
    expect(source.meta.name, '示例书源');
    expect(source.search!.request.url,
        'https://legado.example.com/search?q={{keyword}}');
    expect(source.search!.result!.container, 'div.book-item');
    expect(source.search!.result!.fields!['title']!.attr, 'text');
    expect(source.search!.result!.fields!['url']!.attr, 'href');
  });

  test('命中不支持语法报 LegadoUnsupportedException', () {
    final bad = legadoJson.replaceAll('@css:h3@text',
        '{{js> java.ajax("https://x") }}');
    expect(() => LegadoAdapter().translate(bad),
        throwsA(isA<LegadoUnsupportedException>()));
  });

  test('## 正则过滤语法不支持', () {
    final bad =
        legadoJson.replaceAll('@css:h3@text', '@css:h3@text##\\d+');
    expect(() => LegadoAdapter().translate(bad),
        throwsA(isA<LegadoUnsupportedException>()));
  });
}
