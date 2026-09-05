import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('Action 注册表按类型注册/查询', () {
    final registry = ActionRegistry();
    registry.register(CopyLinkAction());
    final r = SearchResult(
        sourceId: 's',
        sourceName: 'n',
        type: SourceType.magnet,
        title: 't',
        url: 'magnet:?xt=1');

    final actions = registry.actionsFor(r);
    expect(actions.map((a) => a.id), contains('copy'));
  });

  test('copy 动作产出剪贴板内容（含提取码）', () {
    final r = SearchResult(
        sourceId: 's',
        sourceName: 'n',
        type: SourceType.pan,
        title: 't',
        url: 'https://pan.baidu.com/s/1a',
        extractCode: 'ab12');
    expect(CopyLinkAction().clipboardContent(r),
        'https://pan.baidu.com/s/1a 提取码: ab12');
  });

  test('open 动作只作用于链接型结果', () {
    final registry = ActionRegistry();
    registry.register(OpenLinkAction());
    final link = SearchResult(
        sourceId: 's',
        sourceName: 'n',
        type: SourceType.pan,
        title: 't',
        url: 'https://pan.quark.cn/s/x');
    final detail = SearchResult(
        sourceId: 's',
        sourceName: 'n',
        type: SourceType.book,
        title: 't',
        url: '/relative/detail');
    expect(registry.actionsFor(link).map((a) => a.id), contains('open'));
    expect(registry.actionsFor(detail), isEmpty);
  });
}
