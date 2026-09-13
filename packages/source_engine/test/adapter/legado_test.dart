import 'dart:convert' show jsonEncode;
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
    // Legado 文本型书源（bookSourceType=0，缺省即 0）是**网文小说**，
    // 映射为 novel；book 保留给"电子书文件"型资源（zlib/安娜的 epub/pdf）。
    expect(source.meta.type, SourceType.novel);
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

  test('## 正则替换语法已支持', () {
    // P1 起 ## 不再是不支持语法：##[0-9]+ 表示把标题里的数字删掉。
    // 这里刻意不用 \d —— JSON 字符串里 \d 是非法转义，直接替换会让
    // jsonDecode 失败（真实书源会写成 \\d，是合法转义）。
    final withReplace =
        legadoJson.replaceAll('@css:h3@text', r'@css:h3@text##[0-9]+');
    final source = LegadoAdapter().translate(withReplace);
    final title = source.search!.result!.fields!['title']!;
    expect(title.hasReplace, isTrue);
    expect(title.replaceRegex, '[0-9]+');
    expect(title.replacement, '');
  });

  test('|| 兜底链解析为候选选择器', () {
    final chained = legadoJson.replaceAll(
        '@css:h3@text', r'@css:h3@text||@css:a.title@text||h4');
    final title =
        LegadoAdapter().translate(chained).search!.result!.fields!['title']!;
    expect(title.selector, 'h3');
    expect(title.fallbackSelectors, ['a.title', 'h4']);
  });

  test('&& 规则链仍不支持', () {
    final bad = legadoJson.replaceAll('@css:h3@text', '@css:h3@text&&x');
    expect(() => LegadoAdapter().translate(bad),
        throwsA(isA<LegadoUnsupportedException>()));
  });

  test('搜索无关字段含不支持语法时不连坐整源', () {
    // 真实书源普遍在正文/目录/发现页/登录脚本里用 <js>/java./##，
    // 但搜索路径是纯 CSS —— 整段扫描的实现会把这类可用源误杀。
    // 这里锁定"只校验搜索必需字段"的行为。
    final src = {
      'bookSourceUrl': 'https://book.example.com',
      'bookSourceName': '带JS正文的书源',
      'searchUrl': 'https://book.example.com/search?q={{key}}',
      'ruleSearch': {
        'bookList': '@css:div.book-item',
        'name': '@css:h3@text',
        'bookUrl': '@css:a.link@href',
      },
      'ruleContent': {
        'content': r'<js>var a = java.ajax("http://x"); a</js>##\d+',
      },
      'ruleToc': {'chapterList': '@css:dd a||a'},
      'exploreUrl': r'<js>java.toast("hi")</js>',
      'loginUrl': r'<js>java.reLoginView();</js>',
    };
    final source = LegadoAdapter().translate(jsonEncode(src));
    expect(source.search!.result!.container, 'div.book-item');
    expect(source.search!.result!.fields!['title']!.selector, 'h3');
  });

  test('bookUrl 缺失降级兜底 a@href；含 JS 规则交给 JS 运行时', () {
    final noBookUrl = {
      'bookSourceUrl': 'https://book.example.com',
      'bookSourceName': '无 bookUrl',
      'searchUrl': 'https://book.example.com/search?q={{key}}',
      'ruleSearch': {
        'bookList': '@css:div.book-item',
        'name': '@css:h3@text',
      },
    };
    expect(LegadoAdapter().translate(jsonEncode(noBookUrl))
        .search!.result!.fields!['url']!.selector, 'a');

    // bookUrl 含 <js>：不再降级成 CSS，而是整段解析交给 JS 运行时
    final jsBookUrl = {
      'bookSourceUrl': 'https://book.example.com',
      'bookSourceName': 'JS bookUrl',
      'searchUrl': 'https://book.example.com/search?q={{key}}',
      'ruleSearch': {
        'bookList': '@css:div.book-item',
        'name': '@css:h3@text',
        'bookUrl': r'<js>java.base64Encode(result)</js>',
      },
    };
    final jsSrc = LegadoAdapter().translate(jsonEncode(jsBookUrl));
    expect(jsSrc.hooks?.parse, isNotNull);
    expect(jsSrc.hooks!.parse, contains('evalRule'));
  });

  test('{{java.xxx()}} 动态模板编译为 buildRequest 钩子', () {
    final tpl = {
      'bookSourceUrl': 'https://book.example.com',
      'bookSourceName': '动态模板源',
      'searchUrl': r'https://book.example.com/s?w={{java.encodeURI(key)}}',
      'ruleSearch': {
        'bookList': '@css:div.book-item',
        'name': '@css:h3@text',
        'bookUrl': '@css:a.link@href',
      },
    };
    final src = LegadoAdapter().translate(jsonEncode(tpl));
    expect(src.hooks?.buildRequest, isNotNull);
    expect(src.hooks!.buildRequest, contains('renderTpl'));
  });

  // ── 在线阅读：详情 / 目录 / 正文 规则翻译 ──────────────────────────

  test('ruleBookInfo / ruleToc / ruleContent 翻译为阅读规则', () {
    final withRead = {
      'bookSourceUrl': 'https://book.example.com',
      'bookSourceName': '可读源',
      'searchUrl': 'https://book.example.com/s?q={{key}}',
      'ruleSearch': {
        'bookList': '@css:div.book-item',
        'name': '@css:h3@text',
        'bookUrl': '@css:a.link@href',
      },
      'ruleBookInfo': {
        'coverUrl': '.cover img@src',
        'intro': '#intro@text',
        'kind': '.kind@text',
      },
      'ruleToc': {
        'chapterList': 'ul.chapter-list li',
        'chapterName': 'a@text',
        'chapterUrl': 'a@href',
      },
      'ruleContent': {'content': '#content@html'},
    };
    final src = LegadoAdapter().translate(jsonEncode(withRead));
    expect(src.canRead, isTrue);
    expect(src.bookMeta!.cover!.selector, '.cover img');
    expect(src.bookMeta!.cover!.attr, 'src');
    expect(src.bookMeta!.intro!.selector, '#intro');
    expect(src.toc!.list, 'ul.chapter-list li');
    expect(src.toc!.name.selector, 'a');
    expect(src.toc!.url.attr, 'href');
    expect(src.content!.content.selector, '#content');
    expect(src.content!.content.attr, 'html');
  });

  test('缺少目录或正文时不具备在线阅读能力', () {
    final onlyToc = {
      'bookSourceUrl': 'https://book.example.com',
      'bookSourceName': '仅目录',
      'searchUrl': 'https://book.example.com/s?q={{key}}',
      'ruleSearch': {
        'bookList': '@css:div',
        'name': '@css:h3@text',
        'bookUrl': 'a@href',
      },
      'ruleToc': {
        'chapterList': 'ul li',
        'chapterName': 'a@text',
        'chapterUrl': 'a@href',
      },
    };
    final src = LegadoAdapter().translate(jsonEncode(onlyToc));
    expect(src.toc, isNotNull);
    expect(src.content, isNull);
    expect(src.canRead, isFalse);
  });

  test('阅读规则含 JS 时该字段降级为 null（不给错误内容）', () {
    final jsIntro = {
      'bookSourceUrl': 'https://book.example.com',
      'bookSourceName': 'JS 简介',
      'searchUrl': 'https://book.example.com/s?q={{key}}',
      'ruleSearch': {
        'bookList': '@css:div',
        'name': '@css:h3@text',
        'bookUrl': 'a@href',
      },
      'ruleBookInfo': {
        'intro': r'@js:java.ajax(baseUrl)',
        'kind': '.kind@text',
      },
    };
    final src = LegadoAdapter().translate(jsonEncode(jsIntro));
    expect(src.bookMeta!.intro, isNull); // JS 规则不采纳
    expect(src.bookMeta!.kind, isNotNull); // 静态规则照常
  });

  test('~= 正则属性匹配展开为 CSS 候选选择器', () {
    // legado 的 `~=` 是"属性值匹配正则"，CSS 无对应语法；
    // 简单的 a|b|c 展开成多个 *= 选择器（CSS 逗号即"或"）。
    final src = LegadoAdapter().translate(jsonEncode({
      'bookSourceUrl': 'https://book.example.com',
      'bookSourceName': '正则属性源',
      'searchUrl': 'https://book.example.com/s?q={{key}}',
      'ruleSearch': {
        'bookList': '@css:div',
        'name': '@css:h3@text',
        'bookUrl': 'a@href',
      },
      'ruleBookInfo': {
        'kind': '[property~=category|status|tags]@content',
        'lastChapter': r'[property~=las?test_chapter_name]@content',
      },
    }));
    expect(src.bookMeta!.kind!.selector, contains('[property*="category"]'));
    expect(src.bookMeta!.kind!.selector, contains('[property*="tags"]'));
    expect(src.bookMeta!.kind!.attr, 'content');
    // 含 `?` 的复杂正则不做转换 → 该字段降级为 null（不显示）
    expect(src.bookMeta!.lastChapter, isNull);
  });

  test('属性名简写（text/href）作用于元素自身', () {
    // 目录容器已定位到 <a> 时，legado 规则直接写 text/href
    final src = LegadoAdapter().translate(jsonEncode({
      'bookSourceUrl': 'https://book.example.com',
      'bookSourceName': '简写源',
      'searchUrl': 'https://book.example.com/s?q={{key}}',
      'ruleSearch': {
        'bookList': '@css:div',
        'name': '@css:h3@text',
        'bookUrl': 'a@href',
      },
      'ruleToc': {
        'chapterList': '#chapterList.-1@a',
        'chapterName': 'text',
        'chapterUrl': 'href',
      },
    }));
    expect(src.toc, isNotNull);
    // `@a` 是取子元素（转后代选择器），不是属性
    expect(src.toc!.list, '#chapterList a');
    // 简写 → 空选择器（作用于元素自身）
    expect(src.toc!.name.selector, isEmpty);
    expect(src.toc!.name.attr, 'text');
    expect(src.toc!.url.selector, isEmpty);
    expect(src.toc!.url.attr, 'href');
  });

  test('stripTags 把正文 HTML 转成可读纯文本', () {
    final html = '<div><p>第一段</p><p>第二段</p>'
        '<br>换行&amp;实体&nbsp;结束</div>';
    final t = stripTags(html);
    expect(t, contains('第一段'));
    expect(t, contains('第二段'));
    expect(t, contains('\n')); // 段落之间保留了换行
    expect(t, contains('换行&实体'));
    expect(t, isNot(contains('<p>')));
  });
}
