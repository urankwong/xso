import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  late FakeJsRuntime js;
  // 假网络层：预置 URL→响应 映射
  final responses = <String, String>{};

  setUp(() {
    js = FakeJsRuntime();
    responses.clear();
  });

  SourceEngine buildEngine() => SourceEngine(
        jsRuntime: js,
        fetcher: (url, {method = 'GET', headers = const {}, charset = 'utf-8', String? body}) async =>
            responses[url] ?? (throw Exception('network down')),
      );

  Source testSource(String searchJson) =>
      parseSource('{"meta":{"id":"t","name":"测试","type":"magnet","version":1},'
          '$searchJson}');

  test('单段式源：请求→CSS 解析→归一化 SearchResult', () async {
    const html =
        '<div class="it"><h3>标题A</h3><a class="l" href="magnet:?xt=1">m</a></div>';
    responses['https://x.com/s?q=%E5%85%B3%E9%94%AE%E8%AF%8D&p=1'] = html;
    final source = testSource(
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{"container":"div.it","fields":{'
      '"title":{"selector":"h3"},"url":{"selector":"a.l","attr":"href"}}}}',
    );
    final results = await buildEngine().search(source, SearchQuery(keyword: '关键词'));
    expect(results, hasLength(1));
    expect(results[0].title, '标题A');
    expect(results[0].url, 'magnet:?xt=1');
    expect(results[0].type, SourceType.magnet);
    expect(results[0].needsDetail, isFalse);
  });

  test('两段式源：列表 needsDetail=true，detail() 二次请求+网盘识别', () async {
    const listHtml =
        '<div class="it"><h3>游戏X</h3><a class="l" href="/g/123">d</a></div>';
    responses['https://x.com/s?q=g&p=1'] = listHtml;
    const detailHtml =
        '<div class="content">夸克: https://pan.quark.cn/s/xyz 提取码：ab12</div>';
    responses['https://x.com/g/123'] = detailHtml;

    final source = testSource(
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{"container":"div.it","fields":{'
      '"title":{"selector":"h3"},"url":{"selector":"a.l","attr":"href"}}}},'
      '"detail":{"request":{"url":"https://x.com{{detailUrl}}"},'
      '"content":"div.content","extractors":["quark"]}',
    );
    final results = await buildEngine().search(source, SearchQuery(keyword: 'g'));
    expect(results[0].needsDetail, isTrue);

    final detail = await buildEngine().fetchDetail(source, results[0]);
    expect(detail, hasLength(1));
    expect(detail[0].url, 'https://pan.quark.cn/s/xyz');
    expect(detail[0].extractCode, 'ab12');
  });

  test('jsonPath 源解析 JSON API 响应', () async {
    responses['https://x.com/api?q=k&p=1'] =
        '{"list":[{"title":"JsonA","url":"https://x.com/1","size":"2GB"}]}';
    final source = testSource(
      '"search":{"request":{"url":"https://x.com/api?q={{keyword}}&p={{page}}"},'
      '"result":{"jsonPath":"\$.list[*]"}}',
    );
    final results = await buildEngine().search(source, SearchQuery(keyword: 'k'));
    expect(results, hasLength(1));
    expect(results[0].title, 'JsonA');
    expect(results[0].extra!['size'], '2GB');
  });

  test('parse 钩子兜底解析（JS 返回 JSON 数组）', () async {
    responses['https://x.com/s?q=k&p=1'] = '<html>raw</html>';
    final source = testSource(
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{}},'
      '"hooks":{"parse":"return [{\\"title\\":\\"JS结果\\",\\"url\\":\\"magnet:?xt=9\\"}]"}',
    );
    final jsWithParse = FakeJsRuntime(scriptResults: {
      'return [{"title":"JS结果","url":"magnet:?xt=9"}]':
          '[{"title":"JS结果","url":"magnet:?xt=9"}]',
    });
    final engine2 = SourceEngine(
      jsRuntime: jsWithParse,
      fetcher: (url,
              {method = 'GET', headers = const {}, charset = 'utf-8', String? body}) async =>
          '<html>raw</html>',
    );
    final results = await engine2.search(source, SearchQuery(keyword: 'k'));
    expect(results, hasLength(1));
    expect(results[0].title, 'JS结果');
  });

  test('无 url 的行（如表头）被过滤', () async {
    const html = '<table id="s"><tr><th>标题</th></tr>'
        '<tr><td><a href="magnet:?xt=1">A</a></td></tr></table>';
    responses['https://x.com/s?q=k&p=1'] = html;
    final source = testSource(
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{"container":"#s tr","fields":{'
      '"title":{"selector":"a"},"url":{"selector":"a","attr":"href"}}}}',
    );
    final results = await buildEngine().search(source, SearchQuery(keyword: 'k'));
    expect(results, hasLength(1));
    expect(results[0].title, 'A');
  });

  test('网络异常抛 SourceExecutionException，含源 id', () async {
    final source = testSource(
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{"container":"div.it","fields":{"title":{"selector":"h3"}}}}',
    );
    await expectLater(
      buildEngine().search(source, SearchQuery(keyword: 'k')),
      throwsA(isA<SourceExecutionException>()),
    );
  });
}
