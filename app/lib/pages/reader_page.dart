import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:source_engine/source_engine.dart';

import '../providers/engine_providers.dart';

/// 内置正文阅读器。
///
/// 数据来自 Legado 源的 `ruleContent`（经引擎 `fetchContent` 抓取并转纯文本），
/// 目录来自 `ruleToc`。支持：目录跳转、上/下一章、字号调节、夜间模式、
/// 阅读进度记忆（按书籍 URL 持久化）。
class ReaderPage extends ConsumerStatefulWidget {
  /// 书名（用于标题栏与进度键）
  final String bookTitle;

  /// 书源（阅读规则由它提供）
  final Source source;

  /// 目录
  final List<Chapter> chapters;

  /// 起始章节（外部恢复进度时传入；-1 表示按持久化进度自动恢复）
  final int startIndex;

  /// 进度持久化键，一般传书籍 URL
  final String progressKey;

  const ReaderPage({
    super.key,
    required this.bookTitle,
    required this.source,
    required this.chapters,
    required this.progressKey,
    this.startIndex = -1,
  });

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  static const _kFontSize = 'reader_font_size';
  static const _kNight = 'reader_night';

  int _index = 0;
  String? _content;
  String? _error;
  bool _loading = true;

  double _fontSize = 17;
  bool _night = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    _fontSize = p.getDouble(_kFontSize) ?? 17;
    _night = p.getBool(_kNight) ?? false;
    var start = widget.startIndex;
    if (start < 0) {
      start = p.getInt('read_pos_${widget.progressKey}') ?? 0;
    }
    if (start < 0 || start >= widget.chapters.length) start = 0;
    if (!mounted) return;
    setState(() {}); // 先把字号/夜间态落到 UI，避免读正文时再跳一次
    await _load(start);
  }

  Future<void> _load(int i) async {
    if (widget.chapters.isEmpty) {
      setState(() {
        _loading = false;
        _error = '该源没有可用目录';
      });
      return;
    }
    setState(() {
      _index = i;
      _loading = true;
      _error = null;
    });
    try {
      final engine = ref.read(sourceEngineProvider);
      final text =
          await engine.fetchContent(widget.source, widget.chapters[i].url);
      if (!mounted) return;
      setState(() {
        _content = text.trim().isEmpty ? '(本章内容为空)' : text;
        _loading = false;
      });
      final p = await SharedPreferences.getInstance();
      await p.setInt('read_pos_${widget.progressKey}', i);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('SourceExecutionException', '抓取失败');
        _loading = false;
      });
    }
  }

  void _jump(int i) {
    if (i < 0 || i >= widget.chapters.length) return;
    _load(i);
  }

  Future<void> _bumpFont(double d) async {
    final v = (_fontSize + d).clamp(13.0, 26.0);
    setState(() => _fontSize = v);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kFontSize, v);
  }

  Future<void> _toggleNight() async {
    setState(() => _night = !_night);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kNight, _night);
  }

  void _openToc() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('目录 · 共 ${widget.chapters.length} 章',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: widget.chapters.length,
                itemBuilder: (ctx, i) {
                  final cur = i == _index;
                  return ListTile(
                    dense: true,
                    selected: cur,
                    title: Text(
                      widget.chapters[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: cur ? FontWeight.w600 : null,
                        color: cur
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _jump(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 夜间模式：独立于 App 主题，只影响阅读页
    final bg = _night ? const Color(0xFF15171A) : scheme.surface;
    final fg = _night ? const Color(0xFFB9BEC6) : scheme.onSurface;
    final title = widget.chapters.isEmpty
        ? widget.bookTitle
        : widget.chapters[_index].title;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: bg,
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
        ),
      ),
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.bookTitle,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(title,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.normal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '目录',
              icon: const Icon(Icons.list),
              onPressed: widget.chapters.isEmpty ? null : _openToc,
            ),
            PopupMenuButton<String>(
              tooltip: '阅读设置',
              icon: const Icon(Icons.text_fields),
              onSelected: (v) {
                if (v == 'a+') _bumpFont(1);
                if (v == 'a-') _bumpFont(-1);
                if (v == 'night') _toggleNight();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'a-', child: Text('字号 -')),
                const PopupMenuItem(value: 'a+', child: Text('字号 +')),
                PopupMenuItem(
                    value: 'night', child: Text(_night ? '日间模式' : '夜间模式')),
              ],
            ),
          ],
        ),
        body: _buildBody(fg),
        bottomNavigationBar: widget.chapters.isEmpty
            ? null
            : SafeArea(
                child: Container(
                  color: bg,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed:
                            _index > 0 ? () => _jump(_index - 1) : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('上一章'),
                      ),
                      Expanded(
                        child: Text(
                          '${_index + 1} / ${widget.chapters.length}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: fg),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _index < widget.chapters.length - 1
                            ? () => _jump(_index + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('下一章'),
                        iconAlignment: IconAlignment.end,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBody(Color fg) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.error, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: fg)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _load(_index),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final paragraphs = (_content ?? '')
        .split(RegExp(r'\n+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      itemCount: paragraphs.length + 1,
      itemBuilder: (ctx, i) {
        if (i == paragraphs.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                _index < widget.chapters.length - 1 ? '— 本章完 —' : '— 全书完 —',
                style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.6)),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SelectableText(
            paragraphs[i],
            style: TextStyle(fontSize: _fontSize, height: 1.8, color: fg),
          ),
        );
      },
    );
  }
}
