import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

/// 章节正文分页与多元素提取回归测试。
///
/// 背景：Legado 书源的分页字段是 `nextContentUrl`（旧实现只认 `nextUrl`），
/// 且正文选择器命中多个元素（如 `#readerContent@p@text`）时只取首个，
/// 导致"章节只显示第一页/第一段"。
void main() {
  late FakeJsRuntime js;
  final responses = <String, String>{};

  setUp(() {
    js = FakeJsRuntime();
    responses.clear();
  });

  SourceEngine buildEngine() => SourceEngine(
        jsRuntime: js,
        fetcher: (url,
                {method = 'GET',
                headers = const {},
                charset = 'utf-8'}) async =>
            responses[url] ?? (throw Exception('network down: $url')),
      );

  Source legadoSource(
    Map<String, dynamic> ruleContent, {
    Map<String, dynamic>? ruleToc,
  }) =>
      LegadoAdapter().translate(jsonEncode({
        'bookSourceUrl': 'https://book.example.com',
        'bookSourceName': '分页书源',
        'searchUrl': 'https://book.example.com/search?q={{key}}',
        'ruleSearch': {
          'bookList': '@css:div.book-item',
          'name': '@css:h3@text',
          'bookUrl': '@css:a.link@href',
        },
        'ruleContent': ruleContent,
        if (ruleToc != null) 'ruleToc': ruleToc,
      }));

  group('正文分页拼接', () {
    test('nextContentUrl 静态分页自动拼接后续页', () async {
      responses['https://book.example.com/c/1.html'] =
          '<div id="content"><p>第一页内容</p></div>'
          '<a class="next" href="/c/2.html">下一页</a>';
      responses['https://book.example.com/c/2.html'] =
          '<div id="content"><p>第二页内容</p></div>'
          '<a class="next" href="/c/3.html">下一页</a>';
      responses['https://book.example.com/c/3.html'] =
          '<div id="content"><p>第三页内容</p></div>';
      final source = legadoSource({
        'content': '@css:#content@text',
        'nextContentUrl': '@css:a.next@href',
      });
      final text =
          await buildEngine().fetchContent(source, 'https://book.example.com/c/1.html');
      expect(text, contains('第一页内容'));
      expect(text, contains('第二页内容'));
      expect(text, contains('第三页内容'));
    });

    test('nextUrl（自有格式字段名）同样生效', () async {
      responses['https://book.example.com/c/1.html'] =
          '<div id="content">前半</div><a class="n" href="/c/2.html">下页</a>';
      responses['https://book.example.com/c/2.html'] = '<div id="content">后半</div>';
      final source = legadoSource({
        'content': '@css:#content@text',
        'nextUrl': '@css:a.n@href',
      });
      final text =
          await buildEngine().fetchContent(source, 'https://book.example.com/c/1.html');
      expect(text, contains('前半'));
      expect(text, contains('后半'));
    });

    test('页与页之间用换行分隔，不粘连', () async {
      responses['https://book.example.com/c/1.html'] =
          '<div id="content">尾字</div><a class="n" href="/c/2.html">下页</a>';
      responses['https://book.example.com/c/2.html'] = '<div id="content">首字</div>';
      final source = legadoSource({
        'content': '@css:#content@text',
        'nextContentUrl': '@css:a.n@href',
      });
      final text =
          await buildEngine().fetchContent(source, 'https://book.example.com/c/1.html');
      expect(text, matches(RegExp(r'尾字\n+首字')));
    });

    test('分页环路（A→B→A）自动终止不死循环', () async {
      responses['https://book.example.com/c/1.html'] =
          '<div id="content">甲</div><a class="n" href="/c/2.html">下页</a>';
      responses['https://book.example.com/c/2.html'] =
          '<div id="content">乙</div><a class="n" href="/c/1.html">下页</a>';
      final source = legadoSource({
        'content': '@css:#content@text',
        'nextContentUrl': '@css:a.n@href',
      });
      final text =
          await buildEngine().fetchContent(source, 'https://book.example.com/c/1.html');
      expect(text, contains('甲'));
      expect(text, contains('乙'));
      // 甲只出现一次（回到已访问页即停）
      expect('甲'.allMatches(text).length, 1);
    });
  });

  group('正文多元素提取', () {
    test('选择器命中多个 <p> 时全部拼接', () async {
      responses['https://book.example.com/c/1.html'] =
          '<div id="readerContent"><p>段落一</p><p>段落二</p><p>段落三</p></div>';
      final source = legadoSource({
        'content': '@css:#readerContent@p@text',
      });
      final text =
          await buildEngine().fetchContent(source, 'https://book.example.com/c/1.html');
      expect(text, contains('段落一'));
      expect(text, contains('段落二'));
      expect(text, contains('段落三'));
    });

    test('多元素 + 分页组合场景完整', () async {
      responses['https://book.example.com/c/1.html'] =
          '<div id="readerContent"><p>一段</p><p>二段</p></div>'
          '<a class="n" href="/c/2.html">下页</a>';
      responses['https://book.example.com/c/2.html'] =
          '<div id="readerContent"><p>三段</p><p>四段</p></div>';
      final source = legadoSource({
        'content': '@css:#readerContent@p@text',
        'nextContentUrl': '@css:a.n@href',
      });
      final text =
          await buildEngine().fetchContent(source, 'https://book.example.com/c/1.html');
      for (final p in ['一段', '二段', '三段', '四段']) {
        expect(text, contains(p));
      }
    });
  });

  group('目录分页（nextTocUrl）', () {
    test('目录跨多页自动拼接章节', () async {
      responses['https://book.example.com/book/1.html'] =
          '<ul id="list"><li><a href="/c/1.html">第一章</a></li></ul>'
          '<a class="gr" href="/book/1_2.html">下一页</a>';
      responses['https://book.example.com/book/1_2.html'] =
          '<ul id="list"><li><a href="/c/2.html">第二章</a></li></ul>';
      final source = legadoSource({
        'content': '@css:#content@text',
      }, ruleToc: {
        'chapterList': '@css:#list li',
        'chapterName': '@css:a@text',
        'chapterUrl': '@css:a@href',
        'nextTocUrl': '@css:a.gr@href',
      });
      final chapters =
          await buildEngine().fetchChapters(source, 'https://book.example.com/book/1.html');
      expect(chapters, hasLength(2));
      expect(chapters[0].title, '第一章');
      expect(chapters[1].title, '第二章');
    });
  });

  group('JS 动态分页（黄金屋型）', () {
    // 真实 JS 求值在 app 层 QuickJS 中验证；此处分两层验证：
    // 1) 适配器把含 <js> 的 nextContentUrl 编译为 nextPage 钩子（而非丢弃）；
    // 2) 引擎按钩子返回的 URL 数组抓取全部后续页。
    test('nextContentUrl 含 <js> 生成 URL 数组时全部抓取', () async {
      // 页面上的 <small>(1/3)</small> 表示共 3 页
      responses['https://book.example.com/c/1.html'] =
          '<div id="readerContent"><p>首页内容</p></div><small>(1/3)</small>';
      responses['https://book.example.com/c/1_2.html'] =
          '<div id="readerContent"><p>第二页内容</p></div>';
      responses['https://book.example.com/c/1_3.html'] =
          '<div id="readerContent"><p>第三页内容</p></div>';
      final source = legadoSource({
        'content': '@css:#readerContent@p@text',
        'nextContentUrl': 'small@text##(\\d+)\\)\$##\$1###\n<js>\n'
            'Array.from({ length: Number(result[0]) - 1 }, '
            '(_, i) => baseUrl.replace(/1\\.html\$/, "_" + (i + 2) + ".html"))\n'
            '</js>',
      });
      // 1) 适配器层面：JS 型分页规则不再被静默丢弃
      expect(source.bookHooks?.nextPage, isNotNull);
      // 2) 引擎层面：钩子返回 URL 数组 → 逐页抓取拼接
      js = FakeJsRuntime(scriptResults: {
        'Array.from':
            '["https://book.example.com/c/1_2.html","https://book.example.com/c/1_3.html"]',
      });
      final text = await buildEngine().fetchContent(
          source, 'https://book.example.com/c/1.html');
      expect(text, contains('首页内容'));
      expect(text, contains('第二页内容'));
      expect(text, contains('第三页内容'));
    });
  });
  group('java.ajax 重放协议（ixdzs8 型 token 挑战）', () {
    // QuickJS 是同步引擎、Dart 无法同步网络。引擎用「重放」协议支持
    // 同步语义的 java.ajax：第 1 轮登记缺失 URL → 引擎抓取写缓存 →
    // 第 2 轮重放命中。
    test('content 钩子内 java.ajax 触发抓取并重放成功', () async {
      responses['https://book.example.com/read/1'] = '<html>初始页(带token)</html>';
      responses['https://book.example.com/read/1?challenge=tok'] = '挑战后正文';
      final source = Source(
        meta: const SourceMeta(
            id: 'ajax-test', name: 'ajax测试', type: SourceType.novel, version: 1),
        bookHooks: const BookHooks(
          content: 'var h = java.ajax("https://book.example.com/read/1?challenge=tok");\n'
              'return h;',
        ),
      );
      // 自定义假运行时：第 1 轮报 __need，缓存写入后第 2 轮给结果
      final replayJs = _AjaxReplayJs();
      final engine = SourceEngine(
        jsRuntime: replayJs,
        fetcher: (url,
                {method = 'GET',
                headers = const {},
                charset = 'utf-8'}) async =>
            responses[url] ?? (throw Exception('network down: $url')),
      );
      final text = await engine.fetchContent(
          source, 'https://book.example.com/read/1');
      expect(text, '挑战后正文');
      expect(replayJs.rounds, 2); // 恰好两轮：登记 + 重放
    });
  });
}

/// 模拟「重放协议」的假运行时：
/// 每轮 evaluate 若脚本是缓存写入则吞掉；主钩子脚本第 1 轮返回 __need，
/// 之后返回 __result。
class _AjaxReplayJs extends FakeJsRuntime {
  int rounds = 0;
  bool _cached = false;

  @override
  Future<String> evaluate(String script, {Duration? timeout}) async {
    if (script.contains('__ajaxCache')) {
      _cached = true;
      return '1';
    }
    rounds++;
    if (rounds == 1) {
      return '{"__need":["https://book.example.com/read/1?challenge=tok"]}';
    }
    assert(_cached);
    return '{"__result":"挑战后正文"}';
  }
}