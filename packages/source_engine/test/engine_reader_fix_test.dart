import 'dart:convert';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

/// 阅读链路两个真实故障的回归测试。
///
/// 1. **正文残留 HTML 标签**：Legado 正文规则写成 `xxx@html` 时取到的是
///    innerHtml，而 JS 钩子那条路径 stripTags 过、静态规则这条没有 ——
///    阅读页是纯文本渲染，于是满屏可见 `<p>`/`<a href=...>`
///    （部分小说站实测）。
///
/// 2. **跨章串页**：章节末页的"下一页"指向下一章时，引擎无条件跟随会一路
///    串下去。实测某小说站第一章串了 50 页（打满上限）、正文 7 万字、耗时
///    17 秒，内容里混进后面好几章。
void main() {
  final responses = <String, String>{};

  SourceEngine buildEngine() => SourceEngine(
        jsRuntime: FakeJsRuntime(),
        fetcher: (url,
                {method = 'GET',
                headers = const {},
                charset = 'utf-8', String? body}) async =>
            responses[url] ?? (throw Exception('network down: $url')),
      );

  setUp(() => responses.clear());

  Source sourceWith(Map<String, dynamic> ruleContent) =>
      LegadoAdapter().translate(jsonEncode({
        'bookSourceUrl': 'https://book.example.com',
        'bookSourceName': '测试书源',
        'searchUrl': 'https://book.example.com/search?q={{key}}',
        'ruleSearch': {
          'bookList': '@css:div.book-item',
          'name': '@css:h3@text',
          'bookUrl': '@css:a.link@href',
        },
        'ruleContent': ruleContent,
      }));

  test('静态 @html 规则：正文里的标签必须被剥离', () async {
    // 站点正文区里混着举报链接与广告，全是 HTML 结构
    responses['https://book.example.com/read/1.html'] = '''
      <div id="chaptercontent">
        <p><a href="javascript:postError(1,2);" style="color:red;">『章节错误，点此举报』</a></p>
        <p>天才一秒记住本站地址：[某站]最快更新！</p>
        <p>正文第一段。</p><p>正文第二段。</p>
      </div>
    ''';
    final source = sourceWith({'content': '@css:div#chaptercontent@html'});

    final text = await buildEngine()
        .fetchContent(source, 'https://book.example.com/read/1.html');

    expect(text, isNot(contains('<p>')));
    expect(text, isNot(contains('</p>')));
    expect(text, isNot(contains('<a ')));
    expect(text, isNot(contains('javascript:')));
    // 文字本身要保留（剥标签 ≠ 丢内容）
    expect(text, contains('正文第一段。'));
    expect(text, contains('正文第二段。'));
  });

  test('静态 text 规则：本来就无标签，不受影响', () async {
    responses['https://book.example.com/read/2.html'] =
        '<div id="c"><p>纯文本段落</p></div>';
    final source = sourceWith({'content': '@css:div#c@p@text'});

    final text = await buildEngine()
        .fetchContent(source, 'https://book.example.com/read/2.html');
    expect(text, contains('纯文本段落'));
    expect(text, isNot(contains('<')));
  });

  test('跨章串页：下一页指向兄弟章节时立即停止', () async {
    // 第一章两页；第 2 页的"下一页"是**第二章**（站点的真实行为）
    responses['https://book.example.com/read/1.html'] =
        '<div id="c"><p>第一章第一页</p>'
        '<a id="pt_next" href="https://book.example.com/read/1_2.html">下一页</a></div>';
    responses['https://book.example.com/read/1_2.html'] =
        '<div id="c"><p>第一章第二页</p>'
        '<a id="pt_next" href="https://book.example.com/read/2.html">下一页</a></div>';
    responses['https://book.example.com/read/2.html'] =
        '<div id="c"><p>第二章不该被串进来</p></div>';

    final source = sourceWith({
      'content': '@css:div#c@html',
      'nextContentUrl': '@css:a#pt_next@href',
    });

    final text = await buildEngine().fetchContent(
      source,
      'https://book.example.com/read/1.html',
      siblingChapterUrls: {
        'https://book.example.com/read/1.html',
        'https://book.example.com/read/2.html',
        'https://book.example.com/read/3.html',
      },
    );

    expect(text, contains('第一章第一页'));
    expect(text, contains('第一章第二页'));
    expect(text, isNot(contains('第二章不该被串进来')),
        reason: '"下一页"命中兄弟章节时必须收尾，否则会把后面几章并进本章');
  });

  test('同章分页不受跨章保护影响（正常长章节仍要串页）', () async {
    responses['https://book.example.com/read/5.html'] =
        '<div id="c"><p>第一页</p>'
        '<a id="pt_next" href="https://book.example.com/read/5_2.html">下一页</a></div>';
    responses['https://book.example.com/read/5_2.html'] =
        '<div id="c"><p>第二页</p>'
        '<a id="pt_next" href="https://book.example.com/read/5_3.html">下一页</a></div>';
    responses['https://book.example.com/read/5_3.html'] =
        '<div id="c"><p>第三页</p></div>';

    final source = sourceWith({
      'content': '@css:div#c@html',
      'nextContentUrl': '@css:a#pt_next@href',
    });

    final text = await buildEngine().fetchContent(
      source,
      'https://book.example.com/read/5.html',
      siblingChapterUrls: {
        'https://book.example.com/read/5.html',
        'https://book.example.com/read/9.html',
      },
    );

    expect(text, contains('第一页'));
    expect(text, contains('第二页'));
    expect(text, contains('第三页'));
  });

  test('未传兄弟章节集合时保持旧行为（不误伤）', () async {
    responses['https://book.example.com/read/7.html'] =
        '<div id="c"><p>页面A</p>'
        '<a id="pt_next" href="https://book.example.com/read/8.html">下一页</a></div>';
    responses['https://book.example.com/read/8.html'] =
        '<div id="c"><p>页面B</p></div>';

    final source = sourceWith({
      'content': '@css:div#c@html',
      'nextContentUrl': '@css:a#pt_next@href',
    });

    final text = await buildEngine()
        .fetchContent(source, 'https://book.example.com/read/7.html');
    expect(text, contains('页面A'));
    expect(text, contains('页面B'));
  });
}
