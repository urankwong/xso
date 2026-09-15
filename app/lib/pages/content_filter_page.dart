import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:source_engine/source_engine.dart' show applyContentFilters;

import '../providers/content_filter_provider.dart';

/// 内置推荐规则：从实测站点归纳的**文字级**广告特征。
///
/// 网上流传的净化规则大量是 HTML 标签级（`<img src="…ad…">`、
/// `<div class="float-ad">`）—— 那些在 xso 里由引擎的 stripTags 统一清掉了，
/// 用户再加一遍毫无意义。这里只收"文字广告"：它们没法靠标签剥离，
/// 才是真正需要规则的地方。
///
/// 选取标准是**跨站点共性**（记住本站、举报入口、分页标记、求票……）；
/// 站点特有的那些交给"阅读页选中即净化"随手加，不进这里。
const kRecommendedFilters = <ContentFilterRule>[
  ContentFilterRule(
      pattern: r'天才一秒记住本[书站]地址[^\n]*', label: '记住本站地址'),
  ContentFilterRule(
      pattern: r'(记住本站|一秒记住|收藏本站|记住本书)[^\n]{0,20}',
      label: '收藏本站类'),
  ContentFilterRule(
      pattern: r'[全最]新[章节网址域名]*[^。\n]{0,10}(最快|无弹窗|无广告)',
      label: '更新最快/无广告'),
  ContentFilterRule(
      pattern: r'[（(【]?\s*章节[错误内容]{1,2}\s*[，,]?\s*点此举报\s*[）)】]?',
      label: '章节错误举报'),
  ContentFilterRule(
      pattern: r'[（(【]?\s*内容[错误有误]{1,2}\s*[，,]?\s*(点此|请)举报\s*[）)】]?',
      label: '内容纠错举报'),
  ContentFilterRule(
      pattern: r'[（(【]\s*第\s*\d+\s*/\s*\d+\s*页\s*[）)】]', label: '分页标记'),
  ContentFilterRule(
      pattern: r'^第\s*\d+\s*节\s*[（(]第?\s*\d+\s*[-–~]\s*\d+\s*行[）)]$',
      label: '分节标记'),
  ContentFilterRule(
      pattern:
          r'[（(【][^）)】]{0,12}(求|投)[^）)】]{0,12}(月票|推荐票|收藏|打赏)[^）)】]{0,12}[）)】]',
      label: '求票提示'),
  ContentFilterRule(
      pattern: r'手机用户请(浏览|访问|阅读|下载)[^\n]*', label: '手机端推广'),
  ContentFilterRule(
      pattern: r'(扫码|关注公众号|下载APP|下载客户端)[^\n]{0,20}',
      label: '扫码/关注类'),
  ContentFilterRule(
      pattern: r'(本章完|未完待续)[。！!]?\s*$', label: '章节结束语'),
];

/// 正文净化规则的编辑与预览。
///
/// 两个诉求合并成一个页面：**净化**（把站点广告整段删掉）与**替换**
/// （把某些词换成别的）。两者本质都是"正则 → 替换串"，只是替换串
/// 留空就是删除，所以用同一套规则表达，不额外区分类型。
class ContentFilterPage extends ConsumerStatefulWidget {
  const ContentFilterPage({super.key});

  @override
  ConsumerState<ContentFilterPage> createState() => _ContentFilterPageState();
}

class _ContentFilterPageState extends ConsumerState<ContentFilterPage> {
  List<ContentFilterRule> _rules = const [];
  bool _loading = true;

  /// 预览用样例文本：改规则时立即看到效果，避免"写完不知道对不对"
  final _sampleController = TextEditingController(
      text: '天才一秒记住本站地址：[某站]最快更新！无广告！\n'
          '正文第一段，正常内容。\n'
          '请收藏本站，方便下次阅读。');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sampleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rules = await ContentFilterStore.load();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    await ContentFilterStore.save(_rules);
    // 让引擎侧通过 listen 收到新规则（立即生效，无需重进阅读页）
    ref.invalidate(contentFilterProvider);
  }

  Future<void> _edit({ContentFilterRule? existing, int? index}) async {
    final result = await showDialog<ContentFilterRule>(
      context: context,
      builder: (_) => _RuleDialog(existing: existing),
    );
    if (result == null) return;
    setState(() {
      final list = List<ContentFilterRule>.of(_rules);
      if (index == null) {
        list.add(result);
      } else {
        list[index] = result;
      }
      _rules = list;
    });
    await _persist();
  }

  Future<void> _remove(int index) async {
    setState(() {
      final list = List<ContentFilterRule>.of(_rules)..removeAt(index);
      _rules = list;
    });
    await _persist();
  }

  /// 导入内置推荐规则（按 pattern 去重，重复导入是安全的）
  Future<void> _importRecommended() async {
    final existing = {for (final r in _rules) r.pattern};
    final add =
        kRecommendedFilters.where((r) => !existing.contains(r.pattern)).toList();
    if (add.isEmpty) {
      _snack('推荐规则都已经有了');
      return;
    }
    setState(() => _rules = [..._rules, ...add]);
    await _persist();
    _snack('已导入 ${add.length} 条推荐规则（可在「效果预览」里看命中效果）');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _toggle(int index, bool enabled) async {
    setState(() {
      final list = List<ContentFilterRule>.of(_rules);
      list[index] = list[index].copyWith(enabled: enabled);
      _rules = list;
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('正文净化'),
        actions: [
          IconButton(
            tooltip: '导入推荐规则',
            icon: const Icon(Icons.download_done_outlined),
            onPressed: _importRecommended,
          ),
          IconButton(
            tooltip: '新增规则',
            icon: const Icon(Icons.add),
            onPressed: () => _edit(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '按正则匹配正文并替换。替换内容留空即为「删除」，'
                      '所以去广告和改词用的是同一套规则。\n'
                      '规则在内置清洗之后应用。\n\n'
                      '这里新建的规则默认「全局」（所有书生效）。'
                      '「本书/本源」的规则请在阅读页里选中文字后创建 —— '
                      '只有那时才知道你指的是哪本书、哪个源。',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.auto_fix_high_outlined,
                              size: 40, color: scheme.outline),
                          const SizedBox(height: 12),
                          const Text('还没有自定义规则'),
                          const SizedBox(height: 6),
                          Text(
                            '内置清洗已覆盖常见广告；\n遇到漏网的，点右上角 + 加一条',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _rules.length; i++) ...[
                    _RuleTile(
                      rule: _rules[i],
                      onToggle: (v) => _toggle(i, v),
                      onEdit: () => _edit(existing: _rules[i], index: i),
                      onDelete: () => _remove(i),
                    ),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 20),
                Text('效果预览',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _sampleController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    labelText: '样例文本（可自行改动）',
                  ),
                ),
                const SizedBox(height: 8),
                _PreviewBox(
                  rules: _rules,
                  sample: _sampleController.text,
                ),
              ],
            ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  final ContentFilterRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleTile({
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 8, right: 4),
        leading: Switch(value: rule.enabled, onChanged: onToggle),
        title: Text(
          rule.label?.trim().isNotEmpty == true ? rule.label! : rule.pattern,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rule.label?.trim().isNotEmpty == true)
              Text(rule.pattern,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            Text(
              '${rule.scopeLabel} · '
              '${rule.replacement.isEmpty ? '删除命中内容' : '替换为「${rule.replacement}」'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '编辑',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// 规则效果预览：在用户给的样例文本上直接跑一遍规则
class _PreviewBox extends StatefulWidget {
  final List<ContentFilterRule> rules;
  final String sample;
  const _PreviewBox({required this.rules, required this.sample});

  @override
  State<_PreviewBox> createState() => _PreviewBoxState();
}

class _PreviewBoxState extends State<_PreviewBox> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final out = applyContentFilters(widget.sample, widget.rules);
    final pagingDemo = _stripPagingForPreview(out);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        pagingDemo.trim().isEmpty ? '（全部内容都被规则删掉了）' : pagingDemo,
        style: const TextStyle(fontSize: 13, height: 1.5),
      ),
    );
  }

  /// 预览里也顺带展示分页标记会被清掉（与引擎行为一致）
  static String _stripPagingForPreview(String s) => s
      .replaceAll(RegExp(r'[（(\[【]\s*(?:第\s*)?\d+\s*/\s*\d+\s*(?:页)?\s*[）)\]】]'), '');
}

/// 新增/编辑规则的弹窗
class _RuleDialog extends StatefulWidget {
  final ContentFilterRule? existing;
  const _RuleDialog({this.existing});

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final TextEditingController _pattern;
  late final TextEditingController _replacement;
  late final TextEditingController _label;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pattern = TextEditingController(text: widget.existing?.pattern ?? '');
    _replacement =
        TextEditingController(text: widget.existing?.replacement ?? '');
    _label = TextEditingController(text: widget.existing?.label ?? '');
  }

  @override
  void dispose() {
    _pattern.dispose();
    _replacement.dispose();
    _label.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _pattern.text.trim();
    if (p.isEmpty) {
      setState(() => _error = '正则不能为空');
      return;
    }
    final rule = ContentFilterRule(
      pattern: p,
      replacement: _replacement.text,
      label: _label.text.trim().isEmpty ? null : _label.text.trim(),
      // 保留原作用范围与范围键：设置页并不知道"是哪本书/哪个源"，
      // 在这里改范围只会把规则变成一条永不生效的废规则。
      scope: widget.existing?.scope ?? FilterScope.global,
      scopeKey: widget.existing?.scopeKey,
    );
    if (!rule.isValidRegExp) {
      setState(() => _error = '正则语法有误，请检查括号/转义');
      return;
    }
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '新增规则' : '编辑规则'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: '名称（可选，便于辨认）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pattern,
              decoration: InputDecoration(
                labelText: '正则表达式',
                hintText: r'例如：记住本站|请收藏本站',
                isDense: true,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _replacement,
              decoration: const InputDecoration(
                labelText: '替换为（留空 = 删除）',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
