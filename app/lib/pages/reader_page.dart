import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:source_engine/source_engine.dart';

import '../providers/content_filter_provider.dart';
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

  /// 向后预取的章节数。只预取 1 章会断供（见 _load 里的说明）
  static const _prefetchAhead = 3;

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

  /// 滚动模式的滚动控制器：九宫格点击需要按"一屏"滚动，必须自己持有
  final ScrollController _scrollCtrl = ScrollController();
  Size? _pageSize;
  int _pageIndex = 0;

  /// 目录倒序偏好。
  ///
  /// 按**源 id** 持久化而非按书：站点吐出的目录是不是反的，取决于站点，
  /// 与读的哪本书无关。
  static const _kTocReversedPrefix = 'tocReversed_';
  bool _tocReversed = false;

  // 听书
  final TtsController _tts = TtsController();
  bool _audioBarVisible = false;

  Future<void> _saveTocReversed(bool v) async {
    // _prefs 由 _restore() 异步赋值：恢复尚未完成就点了按钮时它会是 null，
    // 这里兜底取一次实例（SharedPreferences 内部有缓存），避免这次点按被丢弃。
    final p = _prefs ?? await SharedPreferences.getInstance();
    _prefs ??= p;
    await p.setBool('$_kTocReversedPrefix${widget.source.meta.id}', v);
  }

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
    _scrollCtrl.dispose();
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
    _tocReversed =
        _prefs?.getBool('$_kTocReversedPrefix${widget.source.meta.id}') ?? false;
    _repo = ChapterContentRepository(
      ref.read(sourceEngineProvider),
      widget.source,
      // 传全部章节 URL（含当前章，引擎侧会自行排除）供跨章串页防护使用
      siblingChapterUrls: widget.chapters.map((c) => c.url).toSet(),
      // 本书标识：让"仅本书"的净化规则只作用在这本书上
      bookKey: widget.progressKey,
    );
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
      // 向后预取若干章：翻章零等待的关键。
      //
      // 只预取 1 章时，连着往后翻两章就会断供 —— 第一章是缓存命中，第二章
      // 却要现抓（网络 + 串页分页），表现为"章节之间过渡卡一下"。
      // 3 章足以覆盖真实的阅读节奏，代价可忽略（单章正文 3~8KB）。
      for (var k = 1; k <= _prefetchAhead; k++) {
        final next = i + k;
        if (next >= widget.chapters.length) break;
        repo.prefetch(widget.chapters[next].url);
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
    // 临时诊断日志：定位"点听书却跳章"的调用来源
    debugPrint('[阅读诊断] _jump($i)，当前章节下标=$_index');
    _hideMenu();
    _load(i);
  }

  // ── 菜单交互 ──────────────────────────────────────────────

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

  /// 章节标题样式：居中 + 加粗 + 略大。
  ///
  /// 站点会把章节标题当正文铺在正文首行（实测某小说站"第一章 祂"与正文
  /// 完全同款），读起来分不出哪里是标题、哪里是内容。这里给它独立的
  /// 排版（居中、加粗、上下留白、字号略放大），与主流阅读器一致。
  TextStyle get _headingStyle => _bodyStyle.copyWith(
        fontSize: _settings.fontSize * 1.18,
        fontWeight: FontWeight.w700,
        height: 1.4,
      );

  /// 段首缩进前缀（分页器会给首段也加，标题居中时要摘掉）
  String _stripIndent(String s) => s.startsWith(ReaderPaginator.indent)
      ? s.substring(ReaderPaginator.indent.length)
      : s;

  String _normTitle(String s) => s
      .replaceAll(RegExp(r'[\s　]+'), '')
      .replaceAll(RegExp(r'[（(\[【][^）)\]】]*[）)\]】]'), '')
      .trim();

  /// 判断某个段落是不是"章节标题"。
  ///
  /// 两种依据，命中其一即可：
  /// 1. 与目录里当前章标题一致（去空白/去括号后比较）—— 最可靠；
  /// 2. 形如"第X章/节/回"开头的短行 —— 兜底（有些源的目录标题与
  ///    正文标题写法不同，但对不上时这条仍能认出来）。
  /// 长度上限用于排除"第一章的内容开头就写了第一章三个字"这类误判。
  bool _isChapterHeading(String paragraph) {
    final t = _stripIndent(paragraph).trim();
    if (t.isEmpty || t.length > 40) return false;
    if (_index >= 0 && _index < widget.chapters.length) {
      final ct = _normTitle(widget.chapters[_index].title);
      final pt = _normTitle(t);
      if (ct.isNotEmpty && pt.isNotEmpty) {
        if (pt == ct || pt.startsWith(ct) || ct.startsWith(pt)) return true;
      }
    }
    return RegExp(r'^第\s*[0-9一二三四五六七八九十百千零〇两]{1,12}\s*[章节回卷]')
        .hasMatch(t);
  }

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
      // 标题与正文样式不同，测量端必须同步，否则分页漂移（页尾溢出）
      headingStyle: _headingStyle,
      isHeading: _isChapterHeading,
      headingSpacing: _headingSpacing,
    );
    _pageIndex = _pageIndex.clamp(0, _pages.length - 1);
    _recreatePageCtrl(_pageOffset + _pageIndex);
  }

  void _onPageChanged(int page) {
    // 换章 / 重排（字号、行距、尺寸变化）期间 PageView 的 page 会短暂停在
    // 旧值，而此刻 itemCount 已经变短 —— 直接按"越界"处理就会 _jump 到
    // 相邻章，新章又会触发一次，**递归下去把第 1 章一路顶到第 480 章**
    // （实测点听书时观察到跳章，就是这个连锁反应）。
    if (_loading) return;
    if (_pageViewCount <= 0) return;

    // 越界只可能是两个占位页（首章前的"已是第一章" / 末页后的"下一章"），
    // 且必须确认目标章真实存在，否则把 controller 拉回合法页而不是跳章。
    if (page < _pageOffset || page >= _pageOffset + _pages.length) {
      final target = page < _pageOffset ? _index - 1 : _index + 1;
      if (target >= 0 && target < widget.chapters.length) {
        _jump(target);
      } else {
        _recreatePageCtrl(_pageOffset + _pageIndex);
      }
      return;
    }
    setState(() => _pageIndex = page - _pageOffset);
  }

  // ── 点击分区（九宫格）──────────────────────────────────────

  /// 上一次 pointer down 的位置与时刻，用于把「点击」与「滑动/长按」分开。
  /// 用 Listener（pointer 层）而不是 GestureDetector：正文是 SelectableText，
  /// 它自带的手势识别器会在竞技场里赢过外层 GestureDetector，导致自定义
  /// 分区逻辑收不到点击（这正是"点右侧也只会弹菜单/点哪都没反应"的由来）。
  Offset? _downPos;
  int _downMs = 0;

  void _onPointerDown(PointerDownEvent e) {
    _downPos = e.localPosition;
    _downMs = DateTime.now().millisecondsSinceEpoch;
  }

  void _onPointerUp(PointerUpEvent e) {
    final d = _downPos;
    final t = _downMs;
    _downPos = null;
    if (d == null) return;
    // 位移超过阈值 = 滑动（翻页/滚动）；按住超过 600ms = 长按选择文本
    if ((e.localPosition - d).distance > 12) return;
    if (DateTime.now().millisecondsSinceEpoch - t > 600) return;
    _onZoneTap(e.localPosition);
  }

  /// 九宫格分区：左 1/3 上一页、中 1/3 唤菜单、右 1/3 下一页。
  ///
  /// 这是主流阅读器的通用手势约定 —— 单击左右翻页、单击中间才出菜单。
  /// 菜单已显示时，点任意处只关闭菜单（不在关菜单的同时又翻一页）。
  void _onZoneTap(Offset p) {
    if (_menuVisible) {
      _hideMenu();
      return;
    }
    final w = MediaQuery.sizeOf(context).width;
    // 临时诊断日志：确认分区判定与实际坐标
    debugPrint('[阅读诊断] 分区点击 x=${p.dx.toStringAsFixed(0)} '
        'y=${p.dy.toStringAsFixed(0)} 屏宽=${w.toStringAsFixed(0)}');
    if (p.dx < w / 3) {
      _turnPage(-1);
    } else if (p.dx > w * 2 / 3) {
      _turnPage(1);
    } else {
      _showMenu();
    }
  }

  /// 翻一页（分页模式）或翻一屏（滚动模式）；到本章边界则翻章。
  void _turnPage(int dir) {
    if (_settings.mode == ReaderPageMode.page) {
      final ctrl = _pageCtrl;
      if (ctrl == null || !ctrl.hasClients) return;
      final cur = (ctrl.page ?? (_pageOffset + _pageIndex).toDouble()).round();
      final target = cur + dir;
      // 越界：PageView 的占位页（"已是第一章"/"下一章"）也算越界，
      // 这里直接翻章，交给 _jump 处理，避免停在占位页上。
      if (target < 0) {
        if (_hasPrev) _jump(_index - 1);
        return;
      }
      if (target > _pageViewCount - 1) {
        if (_hasNext) _jump(_index + 1);
        return;
      }
      ctrl.animateToPage(target,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      return;
    }

    // 滚动模式：翻一屏（留 60px 重叠，读起来不会丢行）
    final ctrl = _scrollCtrl;
    if (!ctrl.hasClients) return;
    final viewport = ctrl.position.viewportDimension;
    final max = ctrl.position.maxScrollExtent;
    final target = (ctrl.offset + dir * (viewport - 60)).clamp(0.0, max);
    if ((target - ctrl.offset).abs() < 1) {
      // 已经到底/到顶：继续同向点击就翻章（与主流阅读器一致）
      if (dir > 0 && _hasNext) _jump(_index + 1);
      if (dir < 0 && _hasPrev) _jump(_index - 1);
      return;
    }
    ctrl.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  // ── 选中即净化 ────────────────────────────────────────────

  /// 正文选中菜单：保留系统的复制/全选，追加「净化…」与「替换为…」。
  ///
  /// **只放两个入口**。"仅这段/整行"与"本书/本源/全局"两个维度全部收进
  /// 弹窗 —— 第一版把"净化选中""净化整行"平铺在菜单里，看着就是两个
  /// 意思差不多的项，分不清区别（用户直接问"为啥会有个净化本行"）。
  Widget _selectionMenuBuilder(
      BuildContext context, EditableTextState editableTextState) {
    final items = editableTextState.contextMenuButtonItems;
    final value = editableTextState.textEditingValue;
    final selected = value.selection.textInside(value.text);
    if (selected.trim().isEmpty) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: items,
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: [
        ...items,
        ContextMenuButtonItem(
          label: '净化…',
          onPressed: () {
            ContextMenuController.removeAny();
            _openFilterSheet(selected);
          },
        ),
        ContextMenuButtonItem(
          label: '替换为…',
          onPressed: () {
            ContextMenuController.removeAny();
            _openFilterSheet(selected, askReplacement: true);
          },
        ),
      ],
    );
  }

  /// 净化/替换设置：一次把"去掉什么"和"影响哪些书"选清楚。
  ///
  /// 关键在于**让语义自己说话**：用户选中的文字就是"要去掉的内容"，
  /// 而不是"框定一个范围"。所以这里给实时预览 —— 直接告诉他正文里
  /// 会少掉哪几个字/哪一整行，不用他去猜"净化"是什么意思。
  Future<void> _openFilterSheet(String raw,
      {bool askReplacement = false}) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    var wholeLine = false;
    // 默认只影响本书 —— 最不容易误伤别的书；要广而告之再手动选本源/全局
    var scope = FilterScope.book;
    final replaceCtrl = TextEditingController();
    final scheme = Theme.of(context).colorScheme;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('要去掉的内容',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 6),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('就这几个字'),
                        icon: Icon(Icons.crop_free, size: 16)),
                    ButtonSegment(
                        value: true,
                        label: Text('整行'),
                        icon: Icon(Icons.format_align_left, size: 16)),
                  ],
                  selected: {wholeLine},
                  onSelectionChanged: (s) =>
                      setSheet(() => wholeLine = s.first),
                ),
                const SizedBox(height: 10),
                // 实时预览：直接显示正文里会少掉什么
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    wholeLine
                        ? '会删掉这一整行：\n${_lineContaining(text)}'
                        : '只会删掉这几个字：\n$text',
                    style: TextStyle(
                        fontSize: 12, height: 1.5, color: scheme.onSurface),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('影响范围',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 6),
                SegmentedButton<FilterScope>(
                  segments: const [
                    ButtonSegment(
                        value: FilterScope.book, label: Text('本书')),
                    ButtonSegment(
                        value: FilterScope.source, label: Text('本源')),
                    ButtonSegment(
                        value: FilterScope.global, label: Text('全局')),
                  ],
                  selected: {scope},
                  onSelectionChanged: (s) => setSheet(() => scope = s.first),
                ),
                if (askReplacement) ...[
                  const SizedBox(height: 18),
                  TextField(
                    controller: replaceCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '替换为（留空 = 直接删除）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    const SizedBox(width: 8),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('应用')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final replacement = replaceCtrl.text;
    replaceCtrl.dispose();
    if (ok != true) return;
    await _applyFilter(text,
        wholeLine: wholeLine, scope: scope, replacement: replacement);
  }

  /// 正文里包含 [text] 的那一行（"整行"预览用）。
  /// 找不到就退回文本本身 —— 预览至少要能显示点什么。
  String _lineContaining(String text) {
    for (final line in (_content ?? '').split('\n')) {
      if (line.contains(text)) return line.trim();
    }
    return text;
  }

  /// 把选中的正文变成一条净化规则。
  ///
  /// 站点广告千奇百怪，让用户"看到什么就净化什么"比让他去设置页手写正则
  /// 现实得多。[wholeLine] 为真时连整行一起删 —— 站点广告绝大多数独立成行。
  Future<void> _applyFilter(
    String raw, {
    required bool wholeLine,
    required FilterScope scope,
    String replacement = '',
  }) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    // 选中文字里的正则元字符必须转义，否则规则生成得出来却匹配不到
    final escaped = RegExp.escape(text);
    final pattern = wholeLine ? '^.*$escaped.*\$' : escaped;
    final label = text.length > 14 ? '${text.substring(0, 14)}…' : text;
    final rule = ContentFilterRule(
      pattern: pattern,
      replacement: replacement,
      label: label,
      scope: scope,
      scopeKey: switch (scope) {
        FilterScope.book => widget.progressKey,
        FilterScope.source => widget.source.meta.id,
        FilterScope.global => null,
      },
    );
    if (!rule.isValidRegExp) {
      _toast('这段内容生成不了规则，请到「正文净化」页手动填写');
      return;
    }
    final rules = [...await ContentFilterStore.load(), rule];
    await ContentFilterStore.save(rules);
    ref.invalidate(contentFilterProvider);
    await _refreshAfterFilterChange();
    _toast('已加入净化规则（${rule.scopeLabel}）：$label');
  }

  /// 规则变了要重取本章：缓存里存的是**规则生效前**的正文，
  /// 不作废就完全看不出区别（用户会以为功能没生效）。
  Future<void> _refreshAfterFilterChange() async {
    final repo = _repo;
    if (repo == null || _index >= widget.chapters.length) return;
    await repo.invalidateUrl(widget.chapters[_index].url);
    await _load(_index);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  /// 强制重抓本章（跳过内存与磁盘缓存）。
  ///
  /// 三种场合用得上：正文残缺/被广告污染、站点临时故障后想再试一次、
  /// 刚改完净化规则要立刻看效果。和"往后预取"是互补的 ——
  /// 预取让正常的翻章不必等待，重载则给异常情况一条不用退出重进的退路。
  Future<void> _reloadChapter() async {
    final repo = _repo;
    if (repo == null || _index >= widget.chapters.length) return;
    _hideMenu();
    _toast('正在重新加载本章…');
    await repo.invalidateUrl(widget.chapters[_index].url);
    await _load(_index);
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
        // 倒序与否是**站点属性**（有些站的目录天然是最新章节在前），
        // 不是某一本书的属性 —— 所以按源 id 记住，同一站点后续所有书都继承，
        // 免得用户每换一本书就得再点一次。
        onToggleReversed: () {
          final next = !_tocReversed;
          setState(() => _tocReversed = next);
          _saveTocReversed(next);
        },
        onSelect: (i) {
          Navigator.pop(ctx);
          _jump(i);
        },
      ),
    );
  }

  // ── 听书 ──────────────────────────────────────────────────

  void _toggleAudio() {
    // 临时诊断日志：定位"点听书却跳章"的调用来源
    debugPrint('[阅读诊断] _toggleAudio 被调用，'
        'audioBarVisible=$_audioBarVisible，当前章节=$_index');
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
            // Listener 在 pointer 层，不与正文的 SelectableText 抢手势竞技场；
            // 分区判定见 _onZoneTap（左/中/右三段）。
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUp,
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
    // 沉浸式阅读：正文区不带任何常驻信息条。
    // 章节名 / 书名 / 进度统一由"点中间唤出的菜单"承载
    // （ReaderMenuOverlay 顶部是书名+章节、底部是进度与操作），
    // 与主流阅读器一致 —— 平时满屏只有正文。
    return _settings.mode == ReaderPageMode.page
        ? _buildPagedBody(palette)
        : _buildScrollBody(palette);
  }

  // ── 滚动模式 ──────────────────────────────────────────────

  Widget _buildScrollBody(ReaderPalette palette) {
    final paragraphs = ReaderPaginator.splitParagraphs(_content ?? '');
    return ListView.builder(
      // key 随章节变化 → 换章时重建，滚动位置自然归零
      // （没有它，换章后会停在上一章的滚动偏移处）
      key: ValueKey<int>(_index),
      controller: _scrollCtrl,
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.paddingOf(context).bottom + 32),
      itemCount: paragraphs.length + 1,
      itemBuilder: (ctx, i) {
        if (i == paragraphs.length) {
          return _chapterEndBlock(palette);
        }
        return Padding(
          padding: EdgeInsets.only(bottom: i == 0 ? 6 : 14),
          child: i == 0 && _isChapterHeading(paragraphs[i])
              ? SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.only(
                        top: _headingPadTop, bottom: _headingPadBottom),
                    child: Text(
                      _stripIndent(paragraphs[i]),
                      style: _headingStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : SelectableText(
                  '${ReaderPaginator.indent}${paragraphs[i]}',
                  style: _bodyStyle,
                  // 选中后可直接"净化/替换"（见 _selectionMenuBuilder）
                  contextMenuBuilder: _selectionMenuBuilder,
                  // 不在这里绑 onTap：点击统一由外层 Listener 按九宫格分区处理
                  // （左翻页/中菜单/右翻页）。绑在这里等于"点正文任何位置都只
                  // 唤菜单"，右侧翻页就永远触发不了。
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
                  const SizedBox(width: 4),
                  // 重抓本章（跳过缓存）：内容残缺、被广告污染、
                  // 或刚改完净化规则想立刻看效果时用。
                  // 章末是它最自然的落点 —— 用户"读完了发现不对劲"就在这儿。
                  TextButton.icon(
                    onPressed: _reloadChapter,
                    icon: Icon(Icons.refresh, size: 16,
                        color: palette.secondary),
                    label: Text('重载',
                        style: TextStyle(color: palette.secondary)),
                  ),
                  const SizedBox(width: 4),
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

  /// 标题块上下留白（滚动/分页两种模式共用同一数值）。
  ///
  /// 分页模式的测量端必须把总高计入预算：这段高度由 Padding 产生，
  /// 不在 TextPainter 的测量结果里，漏算就一定溢出（实测 18px 的留白
  /// 直接把首页顶出 39px）。上下分开定义是为了让渲染端直接取用，
  /// 保证"渲染的留白"与"测量的留白"永远是同一个数。
  static const _headingPadTop = 2.0;
  static const _headingPadBottom = 16.0;
  static const _headingSpacing = _headingPadTop + _headingPadBottom;

  Widget _buildPagedBody(ReaderPalette palette) {
    return LayoutBuilder(builder: (ctx, constraints) {
      // 上下信息条由 _buildBody 统一布置，这里的 constraints 已经是正文区，
      // 只需再留**1.5 行**安全余量。
      //
      // 为什么按"行"而不是按比例留：TextPainter 的测量高度与 RenderParagraph
      // 实际占用存在每行 1~2px 的差（行高为小数时逐行累积，一页能差出
      // 1 行以上）。按 8% 留虽然绝对安全，但底部会空出一大块，一眼就看得出来；
      // 留 1.5 行是最小的安全量，视觉上也就是段落末尾多一口气。
      final pageH = constraints.maxHeight;
      final lineH = _settings.fontSize * _settings.lineHeight;
      final size = Size(
        constraints.maxWidth - 40, // 左右 20 边距
        // 留 2 行余量：正文用 SelectableText（分页模式也得能选中净化），
        // 它的实际渲染高度比 Text 每行多约 0.7px，一页累积十几像素 ——
        // 原来留 1.5 行时实测底部溢出 14px。
        (pageH - lineH * 2).clamp(0.0, pageH),
      );
      _ensurePaginated(size);
      final ctrl = _pageCtrl;
      if (ctrl == null || _pages.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return PageView.builder(
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
      );
    });
  }

  Widget _pageContent(ReaderPageContent page) => ClipRect(
        // 兜底：分页测量的行高与实际渲染存在亚像素差，极端情况下仍可能
        // 差出几个像素 —— 这里裁掉而不是让 RenderFlex 弹黄条。
        // 正常情况内容本来就在预算内（见 _buildPagedBody 的余量），
        // 这条只是保证"永不出现调试条纹"。
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in page)
                // index==0 即章节首段：是标题就单独排版（居中/加粗/留白），
                // 否则按正文渲染。分页器保留了下标，这里才能认出来。
                if (f.paragraphIndex == 0 && _isChapterHeading(f.text))
                  SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.only(
                          top: _headingPadTop, bottom: _headingPadBottom),
                      child: Text(
                        _stripIndent(f.text),
                        style: _headingStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  // 分页模式的正文也要能选中：选中即净化/替换全靠它。
                  // 之前这里用 Text（选不中），"替换功能用不起来"就是这个原因。
                  // 排版上它与 Text 同源（都走 RichText），高度一致，不影响分页。
                  SelectableText(
                    f.text,
                    style: _bodyStyle,
                    textAlign: TextAlign.start,
                    contextMenuBuilder: _selectionMenuBuilder,
                  ),
            ],
          ),
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
