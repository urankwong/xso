import 'package:flutter_test/flutter_test.dart';
import 'package:app/providers/github_release_feed.dart';
import 'package:app/providers/update_service.dart';

/// atom 订阅解析测试。夹具是从 https://github.com/urankwong/xso/releases.atom
/// 抓下来的真实结构（两个坑都体现在里面）：
/// ① `<id>` 不含 /releases/tag/，tag 只在 `<link href>` 且被 URL 编码（+ → %2B）；
/// ② 正文 HTML 被 GitHub 套了两层实体转义（&amp; 写成 &amp;amp;）。
void main() {
  group('parse', () {
    test('从 link href 取 tag 并解码 %2B', () {
      final r = ReleaseFeed.parse(_atom);
      expect(r, isNotNull);
      expect(r!.tagName, 'v0.1.0+7');
    });

    test('正文还原为可读文本（去标签 + 双层转义）', () {
      final r = ReleaseFeed.parse(_atom)!;
      expect(r.changelog, contains('发现新版按本机架构选包下载'));
      expect(r.changelog, contains('&&'), reason: '双层转义要还原成 &&');
      expect(r.changelog, contains('• '));
      expect(r.changelog, isNot(contains('<li>')));
      expect(r.changelog, isNot(contains('&lt;')));
    });

    test('没有 entry / 没有 tag 时返回 null 而不是崩', () {
      expect(ReleaseFeed.parse('<feed></feed>'), isNull);
      expect(ReleaseFeed.parse('<entry><id>x</id></entry>'), isNull);
    });

    test('<id> 兜底：没有 link 时取末段', () {
      final r = ReleaseFeed.parse(
          '<entry><id>tag:github.com,2008:Repository/1368/v0.2.0+9</id></entry>');
      expect(r?.tagName, 'v0.2.0+9');
    });
  });

  group('包名与下载地址', () {
    test('按本机架构优先，且去重', () {
      expect(ReleaseFeed.apkNames(abiHint: 'armeabi-v7a'), [
        'app-armeabi-v7a-release.apk',
        'app-arm64-v8a-release.apk',
        'app-x86_64-release.apk',
      ]);
      expect(ReleaseFeed.apkNames(abiHint: 'arm64-v8a').first,
          'app-arm64-v8a-release.apk');
      expect(ReleaseFeed.apkNames().length, 3);
    });

    test('tag 里的 + 必须编码成 %2B，否则下载 404', () {
      final url = ReleaseFeed.apkUrl(
          owner: 'urankwong',
          repo: 'xso',
          tag: 'v0.1.0+7',
          name: 'app-arm64-v8a-release.apk');
      expect(url,
          'https://github.com/urankwong/xso/releases/download/v0.1.0%2B7/app-arm64-v8a-release.apk');
    });
  });

  group('fromFeed 判定', () {
    FeedRelease feed(String tag) =>
        FeedRelease(tagName: tag, changelog: 'x', publishedAt: '', asset: const FeedAsset(
            'app-arm64-v8a-release.apk',
            'https://github.com/urankwong/xso/releases/download/v0.1.0%2B8/app-arm64-v8a-release.apk',
            28000000));

    test('atom 路径同样能识别更新并带上推导出的包', () {
      final res = UpdateService.fromFeed(feed('v0.1.0+8'), AppVersion.parse('0.1.0+7'));
      expect(res.status, UpdateStatus.available);
      expect(res.asset?.name, 'app-arm64-v8a-release.apk');
      expect(res.asset!.url, contains('%2B8'));
    });

    test('版本相同不提示', () {
      final res = UpdateService.fromFeed(feed('v0.1.0+7'), AppVersion.parse('0.1.0+7'));
      expect(res.status, UpdateStatus.upToDate);
    });

    test('atom 没探测到包时仍提示更新，但不给下载地址', () {
      final f = FeedRelease(tagName: 'v0.2.0+1', changelog: '', publishedAt: '');
      final res = UpdateService.fromFeed(f, AppVersion.parse('0.1.0+7'));
      expect(res.hasUpdate, isTrue);
      expect(res.asset, isNull);
    });
  });

  test('htmlToText 处理列表/换行/脚本噪音（反转义由 parse 先行完成）', () {
    final t = ReleaseFeed.htmlToText(
        '<p>A & B</p><ul><li>一</li><li>二<br>c</li></ul><script>x=1</script>');
    expect(t, 'A & B\n• 一\n• 二\nc');
  });
}

const _atom = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>tag:github.com,2008:https://github.com/urankwong/xso/releases</id>
  <entry>
    <id>tag:github.com,2008:Repository/1368974296/v0.1.0+7</id>
    <updated>2026-09-14T01:05:13Z</updated>
    <link rel="alternate" type="text/html" href="https://github.com/urankwong/xso/releases/tag/v0.1.0%2B7"/>
    <title>v0.1.0+7: - 新增应用内「检查更新」</title>
    <content type="html">&lt;ul&gt;
&lt;li&gt;发现新版按本机架构选包下载（带进度、可取消），下载完成自动唤起系统安装器&lt;/li&gt;
&lt;li&gt;修复 Legado 书源：规则含 &lt;a class="user-mention" href="https://github.com/js"&gt;@js&lt;/a&gt;:、&amp;amp;&amp;amp; 等动态写法时改走 JS 钩子求值，&lt;br&gt;
解决这类书源「能搜到却打不开目录与正文」&lt;/li&gt;
&lt;/ul&gt;</content>
    <author><name>urankwong</name></author>
  </entry>
</feed>''';
