import 'package:core/src/models.dart';

/// 结果动作抽象：UI 据此动态渲染按钮。
/// 第一期实现 CopyLinkAction / OpenLinkAction；
/// download/push 为日后扩展。
abstract class ResultAction {
  String get id;
  String get label;
  bool appliesTo(SearchResult result);
}

class CopyLinkAction implements ResultAction {
  @override
  String get id => 'copy';
  @override
  String get label => '复制链接';

  @override
  bool appliesTo(SearchResult r) => r.url.isNotEmpty;

  String clipboardContent(SearchResult r) {
    if (r.extractCode != null) return '${r.url} 提取码: ${r.extractCode}';
    return r.url;
  }
}

class OpenLinkAction implements ResultAction {
  @override
  String get id => 'open';
  @override
  String get label => '打开';

  @override
  bool appliesTo(SearchResult r) =>
      r.url.startsWith('http') ||
      r.url.startsWith('magnet:') ||
      r.url.startsWith('ed2k:');

  /// 网盘链接 → 平台 URL；磁力/ed2k → 原链接（由系统分发）
  String target(SearchResult r) => r.url;
}

class ActionRegistry {
  final _actions = <ResultAction>[];

  void register(ResultAction action) => _actions.add(action);

  List<ResultAction> actionsFor(SearchResult result) =>
      _actions.where((a) => a.appliesTo(result)).toList();
}
