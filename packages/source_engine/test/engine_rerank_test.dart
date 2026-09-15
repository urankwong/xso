import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

/// 相关性重排的测试。
///
/// 背景：站点返回的顺序是它自己的口径（更新时间/热度/推广位），与用户
/// 输入的关键词无关 —— 搜"诡秘之主"时正主被挤到第 4 位（前三条是同人），
/// 或首条干脆是无关的模糊匹配结果。这套用例锁定重排后的相对顺序，
/// 防止后续改动把它悄悄改回"站点原样透传"。
void main() {
  final responses = <String, String>{};

  SourceEngine buildEngine({bool rerankSearch = true}) => SourceEngine(
        jsRuntime: FakeJsRuntime(),
        rerankSearch: rerankSearch,
        fetcher: (url, {method = 'GET', headers = const {}, charset = 'utf-8', String? body}) async =>
            responses[url] ?? (throw Exception('network down')),
      );

  setUp(() => responses.clear());

  test('完全命中优先于前缀命中，前缀优先于包含，包含优先于无关', () async {
    responses['https://x.com/s?q=%E8%AF%A1%E7%A7%98%E4%B9%8B%E4%B8%BB&p=1'] =
        '<div class="it"><h3>拯救世界？抱歉，我妈是深渊之主</h3>'
        '<a class="l" href="https://x.com/a">d</a></div>'
        '<div class="it"><h3>诡秘之主：番外</h3>'
        '<a class="l" href="https://x.com/b">d</a></div>'
        '<div class="it"><h3>【诡秘之主】同人</h3>'
        '<a class="l" href="https://x.com/c">d</a></div>'
        '<div class="it"><h3>诡秘之主</h3>'
        '<a class="l" href="https://x.com/d">d</a></div>';

    final source = parseSource(
      '{"meta":{"id":"t","name":"测试","type":"novel","version":1},'
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{"container":"div.it","fields":{"title":{"selector":"h3"},'
      '"url":{"selector":"a.l","attr":"href"}}}}}',
    );

    final results =
        await buildEngine().search(source, SearchQuery(keyword: '诡秘之主'));
    expect(results.map((r) => r.title).toList(), [
      '诡秘之主', // 完全命中
      '诡秘之主：番外', // 前缀命中
      '【诡秘之主】同人', // 包含
      '拯救世界？抱歉，我妈是深渊之主', // 无关，保留原位
    ]);
  });

  test('同分组内保留站点原本的先后顺序', () async {
    responses['https://x.com/s?q=%E8%AF%A1%E7%A7%98%E4%B9%8B%E4%B8%BB&p=1'] =
        '<div class="it"><h3>诡秘之主：祂</h3>'
        '<a class="l" href="https://x.com/1">d</a></div>'
        '<div class="it"><h3>诡秘之主：番外</h3>'
        '<a class="l" href="https://x.com/2">d</a></div>'
        '<div class="it"><h3>诡秘之主：刺客歧途</h3>'
        '<a class="l" href="https://x.com/3">d</a></div>';

    final source = parseSource(
      '{"meta":{"id":"t","name":"测试","type":"novel","version":1},'
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{"container":"div.it","fields":{"title":{"selector":"h3"},'
      '"url":{"selector":"a.l","attr":"href"}}}}}',
    );

    final results =
        await buildEngine().search(source, SearchQuery(keyword: '诡秘之主'));
    // 三条都是前缀命中（同分），顺序必须与站点返回的一致
    expect(results.map((r) => r.title).toList(), [
      '诡秘之主：祂',
      '诡秘之主：番外',
      '诡秘之主：刺客歧途',
    ]);
  });

  test('标题解析失败的占位条目被压到最后', () async {
    responses['https://x.com/s?q=%E8%AF%A1%E7%A7%98%E4%B9%8B%E4%B8%BB&p=1'] =
        '<div class="it"><h3>诡秘之主</h3>'
        '<a class="l" href="https://x.com/1">d</a></div>'
        '<div class="it"><a class="l" href="https://x.com/2">d</a></div>'
        '<div class="it"><a class="l" href="https://x.com/3">d</a></div>';

    final source = parseSource(
      '{"meta":{"id":"t","name":"测试","type":"novel","version":1},'
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{"container":"div.it","fields":{"title":{"selector":"h3"},'
      '"url":{"selector":"a.l","attr":"href"}}}}}',
    );

    final results =
        await buildEngine().search(source, SearchQuery(keyword: '诡秘之主'));
    expect(results.map((r) => r.title).toList(), [
      '诡秘之主',
      SourceEngine.untitled,
      SourceEngine.untitled,
    ]);
  });

  test('归一化比对：忽略《》标点、空白与大小写差异', () async {
    responses['https://x.com/s?q=%E8%AF%A1%E7%A7%98%E4%B9%8B%E4%B8%BB&p=1'] =
        '<div class="it"><h3>诡秘之主之 xyz</h3>'
        '<a class="l" href="https://x.com/1">d</a></div>'
        '<div class="it"><h3>《诡秘 之主》</h3>'
        '<a class="l" href="https://x.com/2">d</a></div>';

    final source = parseSource(
      '{"meta":{"id":"t","name":"测试","type":"novel","version":1},'
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{"container":"div.it","fields":{"title":{"selector":"h3"},'
      '"url":{"selector":"a.l","attr":"href"}}}}}',
    );

    final results =
        await buildEngine().search(source, SearchQuery(keyword: '诡秘之主'));
    // 去掉《》和空格后与关键词完全相等 → 命中完全命中组，排到最前
    expect(results.first.title, '《诡秘 之主》');
  });

  test('rerankSearch=false 时原样保留站点顺序', () async {
    responses['https://x.com/s?q=%E8%AF%A1%E7%A7%98%E4%B9%8B%E4%B8%BB&p=1'] =
        '<div class="it"><h3>诡秘之主：番外</h3>'
        '<a class="l" href="https://x.com/1">d</a></div>'
        '<div class="it"><h3>诡秘之主</h3>'
        '<a class="l" href="https://x.com/2">d</a></div>';

    final source = parseSource(
      '{"meta":{"id":"t","name":"测试","type":"novel","version":1},'
      '"search":{"request":{"url":"https://x.com/s?q={{keyword}}&p={{page}}"},'
      '"result":{"container":"div.it","fields":{"title":{"selector":"h3"},'
      '"url":{"selector":"a.l","attr":"href"}}}}}',
    );

    final results = await buildEngine(rerankSearch: false)
        .search(source, SearchQuery(keyword: '诡秘之主'));
    expect(results.map((r) => r.title).toList(), ['诡秘之主：番外', '诡秘之主']);
  });
}
