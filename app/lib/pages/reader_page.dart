import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:source_engine/source_engine.dart';

import '../providers/engine_providers.dart';
import '../providers/reader_content.dart';
import '../providers/tts/tts_controller.dart';
import 'reader/reader_audio_bar.dart';
import 'reader/reader_overlays.dart';
import 'reader/reader_paginator.dart';
import 'reader/reader_theme.dart';

/// 内置正文阅读器（对标主流阅读软件）。
///
/// - 沉浸式：正文区全屏（隐藏状态栏/导航栏），点中央呼出菜单，3 秒自动隐藏
/// - 排版：字号/行距/字重/主题色卡/亮度（设置持久化）
/// - 翻页：上下滚动 / 左右分页（TextPainter 排版分页）
/// - 进度：章节进度条拖动跳章 + 目录面板（支持倒序）+ 章内页码
/// - 性能：章节内存 LRU + 磁盘缓存 + 下一章后台预取
///
/// 数据来自 Legado 源的 `ruleContent`（引擎 `fetchContent` 已自动串页
/// 拼接分页章节，返回完整正文）。
class ReaderPage extends ConsumerStatefulWidget {
  /// 书名（用于菜单栏与进度键）
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
  static const _kPosPrefix = 'read_pos_';
  static const _hideAfter = Duration(seconds: 3);

  ReaderSettings _settings = const ReaderSettings();
  ChapterContentRepository? _repo;
  SharedPreferences? _prefs;

  int _index = 0;
  String? _content;
  String? _error;
  bool _loading = true;

  // 沉浸式菜单
  bool _menuVisible = false;
  Timer? _hideTimer;

  // 分页模式状态
  List<ReaderPageContent> _pages = const [];
  PageController? _pageCtrl;
  Size? _pageSize;
  int _pageIndex = 0;

  // 目录倒序
  bool _tocReversed = false;

  // 听书
  final TtsController _tts = TtsController();
  bool _audioBarVisible = false;

  @override
  void initState() {
    super.initState();
    _enterImmersive();
    _restore();
    _tts.loadPreferences();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _pageCtrl?.dispose();
    _tts.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
  }

  Future<void> _restore() async {
    _settings = await ReaderSettings.load();
    _prefs = await SharedPreferences.getInstance();
    _repo =
        ChapterContentRepository(ref.read(sourceEngineProvider), widget.source);
    var start = widget.startIndex;
    if (start < 0) {
      start = _prefs?.getInt('$_kPosPrefix${widget.progressKey}') ?? 0;
    }
    if (start < 0 || start >= widget.chapters.length) start = 0;
    if (!mounted) return;
    setState(() {});
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
    _hideTimer?.cancel();
    setState(() {
      _index = i;
      _loading = true;
      _error = null;
      _pageIndex = 0;
    });
    try {
      final repo = _repo!;
      final text = await repo.fetch(widget.chapters[i].url);
      if (!mounted) return;
      setState(() {
        _content = text.trim().isEmpty ? '(本章内容为空)' : text;
        _loading = false;
        _pages = const [];
        _pageSize = null;
        _recreatePageCtrl(0);
      });
      final p = _prefs;
      if (p != null) await p.setInt('$_kPosPrefix${widget.progressKey}', i);
      // 下一章预取：翻章零等待的关键
      if (i + 1 < widget.chapters.length) {
        repo.prefetch(widget.chapters[i + 1].url);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            e.toString().replaceFirst('SourceExecutionException', '抓取失败');
        _loading = false;
      });
    }
  }

  void _jump(int i) {
    if (i < 0 || i >= widget.chapters.length) return;
    _hideMenu();
    _load(i);
  }

  // ── 菜单交互 ──────────────────────────────────────────────

  void _toggleMenu() {
    _menuVisible ? _hideMenu() : _showMenu();
  }

  void _showMenu() {
    _hideTimer?.cancel();
    setState(() => _menuVisible = true);
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _menuVisible = false);
    });
  }

  void _hideMenu() {
    _hideTimer?.cancel();
    if (mounted) setState(() => _menuVisible = false);
  }

  void _resetHideTimer() {
    if (!_menuVisible) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _menuVisible = false);
    });
  }

  Future<void> _applySettings(ReaderSettings s) async {
    setState(() {
      _settings = s;
      _pages = const []; // 样式变化 → 重排
      _pageSize = null;
      _pageIndex = 0;
      _recreatePageCtrl(0);
    });
    await s.save();
  }

  // ── 分页 ──────────────────────────────────────────────────

  bool get _hasPrev => _index > 0;
  bool get _hasNext => _index < widget.chapters.length - 1;
  int get _pageOffset => _hasPrev ? 1 : 0;
  int get _pageViewCount =>
      (_hasPrev ? 1 : 0) + _pages.length + (_hasNext ? 1 : 0);

  TextStyle get _bodyStyle => TextStyle(
        fontSize: _settings.fontSize,
        height: _settings.lineHeight,
        fontWeight: _settings.bold ? FontWeight.w600 : FontWeight.w400,
        color: _settings.palette.text,
      );

  /// 重建 PageController 时旧实例延迟到帧末释放
  /// （build 期间 dispose 仍 attach 的 controller 会断言失败）
  void _recreatePageCtrl(int initialPage) {
    final old = _pageCtrl;
    _pageCtrl = PageController(initialPage: initialPage);
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  /// 排版分页（build 内同步计算并缓存：尺寸或内容/样式变化时重算）
  void _ensurePaginated(Size size) {
    if (_content == null || _loading) return;
    if (_pageSize == size && _pages.isNotEmpty) return;
    _pageSize = size;
    _pages = ReaderPaginator.paginate(
      content: _content!,
      maxWidth: size.width,
      maxHeight: size.height,
      style: _bodyStyle,
    );
    _pageIndex = _pageIndex.clamp(0, _pages.length - 1);
    _recreatePageCtrl(_pageOffset + _pageIndex);
  }

  void _onPageChanged(int page) {
    if (page < _pageOffset) {
      _jump(_index - 1);
      return;
    }
    if (page >= _pageOffset + _pages.length) {
      _jump(_index + 1);
      return;
    }
    setState(() => _pageIndex = page - _pageOffset);
  }

  // ── 目录 ──────────────────────────────────────────────────

  void _openToc() {
    _hideMenu();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TocSheet(
        chapters: widget.chapters,
        currentIndex: _index,
        reversed: _tocReversed,
        onToggleReversed: () => setState(() => _tocReversed = !_tocReversed),
        onSelect: (i) {
          Navigator.pop(ctx);
          _jump(i);
        },
      ),
    );
  }

  // ── 听书 ──────────────────────────────────────────────────

  void _toggleAudio() {
    _hideMenu();
    if (_audioBarVisible) {
      _tts.stop();
      setState(() => _audioBarVisible = false);
      return;
    }
    setState(() => _audioBarVisible = true);
    final repo = _repo;
    if (repo == null) return;
    _tts.start(
      chapters: widget.chapters,
      repo: repo,
      progressKey: widget.progressKey,
      startIndex: _index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _settings.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMenu,
              child: _buildBody(palette),
            ),
          ),
          // 亮度减光蒙层（近似系统亮度调节，零插件依赖）
          if (_settings.dimAmount > 0.001)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                    color:
                        Colors.black.withValues(alpha: _settings.dimAmount)),
              ),
            ),
          ReaderMenuOverlay(
            visible: _menuVisible,
            bookTitle: widget.bookTitle,
            chapterTitle:
                widget.chapters.isEmpty ? '' : widget.chapters[_index].title,
            chapterIndex: _index,
            chapterCount: widget.chapters.length,
            settings: _settings,
            onClose: _hideMenu,
            onJumpChapter: _jump,
            onOpenToc: _openToc,
            onToggleAudio: _toggleAudio,
            onSettingsChanged: (s) {
              _applySettings(s);
              _resetHideTimer();
            },
          ),
          if (_audioBarVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ReaderAudioBar(
                controller: _tts,
                onClose: () => setState(() => _audioBarVisible = false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(ReaderPalette palette) {
    if (_loading && _content == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: palette.accent, size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.text)),
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
    return _settings.mode == ReaderPageMode.page
        ? _buildPagedBody(palette)
        : _buildScrollBody(palette);
  }

  // ── 滚动模式 ──────────────────────────────────────────────

  Widget _buildScrollBody(ReaderPalette palette) {
    final paragraphs = ReaderPaginator.splitParagraphs(_content ?? '');
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.paddingOf(context).bottom + 32),
      itemCount: paragraphs.length + 1,
      itemBuilder: (ctx, i) {
        if (i == paragraphs.length) {
          return _chapterEndBlock(palette);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SelectableText(
            '${ReaderPaginator.indent}${paragraphs[i]}',
            style: _bodyStyle,
          ),
        );
      },
    );
  }

  /// 章末衔接块：进度提示 + 上一章/下一章（主流阅读软件样式）
  Widget _chapterEndBlock(ReaderPalette palette) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          children: [
            Center(
              child: Text(
                _hasNext ? '— 本章完 · 点击下方继续 —' : '— 全书完 —',
                style: TextStyle(fontSize: 12, color: palette.secondary),
              ),
            ),
            if (_loading && _content != null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (!_loading && _content != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _hasPrev ? () => _jump(_index - 1) : null,
                    child: Text('上一章',
                        style: TextStyle(color: palette.secondary)),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: _hasNext ? () => _jump(_index + 1) : null,
                    child:
                        Text('下一章', style: TextStyle(color: palette.accent)),
                  ),
                ],
              ),
          ],
        ),
      );

  // ── 分页模式 ──────────────────────────────────────────────

  Widget _buildPagedBody(ReaderPalette palette) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final size = Size(
        constraints.maxWidth - 40, // 左右 20 边距
        constraints.maxHeight - 34, // 底部页码区
      );
      _ensurePaginated(size);
      final ctrl = _pageCtrl;
      if (ctrl == null || _pages.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: ctrl,
              itemCount: _pageViewCount,
              onPageChanged: _onPageChanged,
              itemBuilder: (ctx, page) {
                final idx = page - _pageOffset;
                if (idx < 0) return _edgePlaceholder('已是第一章', palette);
                if (idx >= _pages.length) {
                  return _nextChapterPlaceholder(palette);
                }
                return _pageContent(_pages[idx]);
              },
            ),
          ),
          SizedBox(
            height: 34,
            child: Center(
              child: Text(
                widget.chapters.isEmpty
                    ? ''
                    : '${widget.chapters[_index].title}  ·  ${_pageIndex + 1}/${_pages.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: palette.secondary),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _pageContent(ReaderPageContent page) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in page)
              Text(f.text, style: _bodyStyle, textAlign: TextAlign.start),
          ],
        ),
      );

  Widget _edgePlaceholder(String label, ReaderPalette palette) =>
      Center(child: Text(label, style: TextStyle(color: palette.secondary)));

  Widget _nextChapterPlaceholder(ReaderPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Center(
      child: TextButton.icon(
        onPressed: _hasNext ? () => _jump(_index + 1) : null,
        icon: const Icon(Icons.auto_stories_rounded),
        label: Text(_hasNext ? '进入下一章' : '已是最后一章',
            style: TextStyle(color: palette.secondary)),
      ),
    );
  }
}

/// 目录面板：支持正/倒序切换与当前章高亮
class _TocSheet extends StatelessWidget {
  final List<Chapter> chapters;
  final int currentIndex;
  final bool reversed;
  final VoidCallback onToggleReversed;
  final ValueChanged<int> onSelect;

  const _TocSheet({
    required this.chapters,
    required this.currentIndex,
    required this.reversed,
    required this.onToggleReversed,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (ctx, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text('目录 · 共 ${chapters.length} 章',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: onToggleReversed,
                  icon: Icon(
                      reversed
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 18),
                  label: Text(reversed ? '倒序' : '正序'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: chapters.length,
              itemExtent: 44,
              itemBuilder: (ctx, i) {
                final index = reversed ? chapters.length - 1 - i : i;
                final cur = index == currentIndex;
                return ListTile(
                  dense: true,
                  selected: cur,
                  title: Text(
                    '$index. ${chapters[index].title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: cur ? FontWeight.w600 : null,
                      color: cur ? scheme.primary : null,
                    ),
                  ),
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
