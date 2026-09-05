import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  test('替换 keyword 与 page', () {
    final out = renderUrlTemplate(
      'https://example.com/search?q={{keyword}}&p={{page}}',
      keyword: '哈利波特',
      page: 2,
    );
    expect(out,
        'https://example.com/search?q=%E5%93%88%E5%88%A9%E6%B3%A2%E7%89%B9&p=2');
  });

  test('detailUrl 变量用于两段式详情请求', () {
    final out = renderUrlTemplate(
      'https://example.com{{detailUrl}}',
      detailUrl: '/book/123',
    );
    expect(out, 'https://example.com/book/123');
  });

  test('未知变量抛错（防止拼出错误请求）', () {
    expect(
      () => renderUrlTemplate('https://a.com/?x={{unknown}}', keyword: 'k'),
      throwsArgumentError,
    );
  });
}
