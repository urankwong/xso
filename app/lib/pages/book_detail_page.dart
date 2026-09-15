import 'package:core/core.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:source_engine/source_engine.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/data_providers.dart';
import '../providers/engine_providers.dart';
import '../providers/source_loader.dart';
import 'reader_page.dart';

/// 书籍/小说详情页。
///
/// 两种来源、两种形态：
/// - **小说**（Legado 文本型源）：拉 `ruleBookInfo` + `ruleToc`，
///   展示封面/分类/简介/章节数，并提供**内置阅读器**入口；
/// - **电子书文件**（zlib / 安娜档案馆等）：展示能拿到的元信息
///   （封面、文件大小、格式、出版社…）与下载/打开入口。
///
/// 拿不到的信息显示「—」而不是留空，避免用户以为界面坏了。
class BookDetailPage extends ConsumerStatefulWidget {
  final SearchResult result;
  const BookDetailPage({super.key, required this.result});

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  Source? _source;
  BookInfo? _info;
  List<Chapter> _chapters = const [];
  bool _loading = true;
  String? _error;
  bool _fav = false;

  /// 上次读到的章节索引（未读过/无记录为 null），用于「继续阅读」
  int? _resumeIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = widget.result;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final src = await ref.read(sourceByIdProvider(r.sourceId).future);
      if (!mounted) return;
      _source = src;
      if (src == null) {
        // 源反查失败：不再整页报错丢弃搜索结果已有信息，
        // 降级为「仅展示搜索结果已知字段 + 提示条」，至少可用。
        setState(() {
          _error = '源不存在或已被禁用，仅展示已知信息';
          _loading = false;
        });
        return;
      }
      final engine = ref.read(sourceEngineProvider);
      // 分离 try-catch：bookInfo 成功的结果即使 chapters 失败也保留
      try {
        _info = await engine.fetchBookInfo(src, r.url);
      } catch (e) {
        _info = null;
        _error = '详情抓取失败：${e.toString().split('\n').first}';
      }
      if (src.canRead) {
        try {
          _chapters = await engine.fetchChapters(src, r.url);
        } catch (e) {
          _chapters = const [];
          // chapters 失败不覆盖已有的 bookInfo 错误
          _error ??= '目录加载失败：${e.toString().split('\n').first}';
        }
      }
      if (!mounted) return;
      setState(() => _loading = false);
      _checkFav();
      _checkResume();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _checkFav() async {
    try {
      final dao = ref.read(appDbProvider).favoriteDao;
      final list = await dao.all();
      if (!mounted) return;
      setState(() => _fav = list.any((f) => f.url == widget.result.url));
    } catch (_) {}
  }

  Future<void> _checkResume() async {
    try {
      final p = await SharedPreferences.getInstance();
      // 与 reader_page.dart 的 read_pos_ 前缀一致，读取上次读到的章节
      final i = p.getInt('read_pos_${widget.result.url}');
      if (!mounted) return;
      final valid = i != null && i > 0 && i < _chapters.length;
      if (valid) setState(() => _resumeIndex = i);
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    final dao = ref.read(appDbProvider).favoriteDao;
    try {
      if (_fav) {
        final list = await dao.all();
        final hit = list.where((f) => f.url == widget.result.url).firstOrNull;
        if (hit != null) await dao.remove(hit.id);
        if (mounted) setState(() => _fav = false);
      } else {
        await dao.add(widget.result, code: widget.result.extractCode);
        if (mounted) setState(() => _fav = true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_fav ? '已加入收藏' : '已取消收藏')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('收藏失败：$e')));
      }
    }
  }

  Future<void> _openUrl() async {
    final uri = Uri.tryParse(widget.result.url);
    if (uri == null) return;
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开该链接')));
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _startReading({int index = -1}) {
    final src = _source;
    if (src == null || _chapters.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderPage(
        bookTitle: widget.result.title,
        source: src,
        chapters: _chapters,
        progressKey: widget.result.url,
        startIndex: index,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _header(scheme),
                const SizedBox(height: 16),
                _actions(scheme),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _errorBanner(scheme),
                ],
                const SizedBox(height: 20),
                _metaSection(scheme),
                const SizedBox(height: 20),
                _introSection(scheme),
                if (_chapters.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _tocSection(scheme),
                ],
                const SizedBox(height: 24),
                _linkRow(scheme),
              ],
            ),
    );
  }

  /// 非致命错误条：出现在内容上方，附「重试」。相比整页错误页更柔和，
  /// 源反查失败 / 单字段抓取失败时仍能展示搜索结果已有信息。
  Widget _errorBanner(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_error!,
                style: TextStyle(color: scheme.error, fontSize: 12)),
          ),
          TextButton(
            onPressed: _load,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 封面 + 标题 + 作者/来源
  Widget _header(ColorScheme scheme) {
    final r = widget.result;
    // extra 可空：源不返回任何附加字段时就是 null
    final e = r.extra ?? const <String, String>{};
    final cover = _info?.cover ?? e['cover'] ?? e['coverUrl'];
    final author = e['author'] ?? e['artist'];
    final kind = _info?.kind ?? e['kind'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 92,
            height: 128,
            child: (cover != null && cover.isNotEmpty)
                ? Image.network(
                    cover,
                    fit: BoxFit.cover,
                    cacheWidth: 184,
                    cacheHeight: 256,
                    errorBuilder: (_, __, ___) => _coverPlaceholder(scheme),
                  )
                : _coverPlaceholder(scheme),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (author != null && author.isNotEmpty)
                Text(author,
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('来源：${r.sourceName}',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, children: [
                _tag(scheme, _typeLabel(r.type), scheme.primary),
                if (kind != null && kind.isNotEmpty)
                  _tag(scheme, kind, scheme.tertiary),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coverPlaceholder(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.menu_book, color: scheme.onSurfaceVariant, size: 36),
      );

  Widget _tag(ColorScheme scheme, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color)),
      );

  Widget _actions(ColorScheme scheme) {
    final canRead = _source?.canRead == true;
    final hasToc = _chapters.isNotEmpty;
    final loading = _loading;
    // 有历史阅读记录 → 主按钮变「继续阅读」（从上次章节起）
    final resume = _resumeIndex != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canRead && hasToc)
          // 主操作：醒目大按钮，对标主流阅读软件；有进度时改为「继续阅读」
          FilledButton.icon(
            onPressed: () => _startReading(index: resume ? _resumeIndex! : -1),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600),
            ),
            icon: Icon(resume ? Icons.play_arrow : Icons.menu_book, size: 24),
            label: Text(resume ? '继续阅读' : '开始阅读'),
          )
        else if (canRead && !loading)
          // 目录没拉到：给出明确原因 + 重试，不制造"没入口"的空白
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('暂时无法获取章节目录，无法开始阅读',
                      style: TextStyle(fontSize: 13)),
                ),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleFav,
                icon: Icon(_fav ? Icons.star : Icons.star_border,
                    size: 18),
                label: Text(_fav ? '已收藏' : '收藏'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openUrl,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('打开原网页'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 元信息：小说看字数/最新章节；电子书看大小/格式等（取自源返回的字段）
  Widget _metaSection(ColorScheme scheme) {
    final rows = <(String, String)>[];
    void add(String k, String? v) {
      if (v != null && v.trim().isNotEmpty) rows.add((k, v.trim()));
    }

    add('字数', _info?.wordCount);
    add('最新章节', _info?.lastChapter);
    // 电子书类信息：源在搜索结果里返回的字段（extra 可能为 null）
    final e = widget.result.extra ?? const <String, String>{};
    add('文件大小', e['size'] ?? e['filesize'] ?? e['fileSize']);
    add('格式', e['format'] ?? e['ext'] ?? e['extension']);
    add('出版社', e['publisher']);
    add('出版年', e['year'] ?? e['publishYear']);
    add('语言', e['language'] ?? e['lang']);
    add('ISBN', e['isbn']);
    if (_chapters.isNotEmpty) add('章节数', '${_chapters.length} 章');

    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('书籍信息',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(k,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                      Expanded(
                        child: Text(v,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _introSection(ColorScheme scheme) {
    final intro = _info?.intro;
    if (intro == null || intro.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('简介',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Text(intro.trim(),
            style: const TextStyle(fontSize: 14, height: 1.6)),
      ],
    );
  }

  Widget _tocSection(ColorScheme scheme) {
    const preview = 12;
    final shown = _chapters.take(preview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('目录',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
            const Spacer(),
            Text('共 ${_chapters.length} 章',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < shown.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(shown[i].title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _startReading(index: i),
          ),
        if (_chapters.length > preview)
          TextButton(
            onPressed: _showFullToc,
            child: Text('查看全部 ${_chapters.length} 章'),
          ),
      ],
    );
  }

  /// 完整目录弹窗：可滚动选择任意章节
  void _showFullToc() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('目录（共 ${_chapters.length} 章）',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _chapters.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  title: Text(_chapters[i].title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _startReading(index: i);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkRow(ColorScheme scheme) => SelectableText(
        widget.result.url,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      );

  String _typeLabel(SourceType t) => switch (t) {
        SourceType.novel => '小说',
        SourceType.book => '书籍',
        SourceType.comic => '漫画',
        SourceType.video => '影视',
        SourceType.audiobook => '有声',
        SourceType.music => '音乐',
        SourceType.pan => '网盘',
        SourceType.magnet => '磁力',
        SourceType.ed2k => '电驴',
        SourceType.game => '游戏',
      };
}
