import 'package:flutter/material.dart';

import 'reader_theme.dart';

/// 阅读菜单覆盖层（对标主流阅读软件）：
/// - 顶部：返回 / 书名 / 章节名
/// - 底部：章节进度条（可拖动跳章）+ 上一章/目录/下一章 + 设置入口
/// - 设置面板：亮度、字号、行距、字重、翻页方式、主题色卡
/// 菜单本体带半透明遮罩，点击遮罩关闭；显隐由外层 [visible] 控制。
class ReaderMenuOverlay extends StatefulWidget {
  final bool visible;
  final String bookTitle;
  final String chapterTitle;
  final int chapterIndex;
  final int chapterCount;
  final ReaderSettings settings;
  final VoidCallback onClose;
  final ValueChanged<int> onJumpChapter;
  final VoidCallback onOpenToc;
  final VoidCallback? onToggleAudio;
  final ValueChanged<ReaderSettings> onSettingsChanged;

  const ReaderMenuOverlay({
    super.key,
    required this.visible,
    required this.bookTitle,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterCount,
    required this.settings,
    required this.onClose,
    required this.onJumpChapter,
    required this.onOpenToc,
    this.onToggleAudio,
    required this.onSettingsChanged,
  });

  @override
  State<ReaderMenuOverlay> createState() => _ReaderMenuOverlayState();
}

class _ReaderMenuOverlayState extends State<ReaderMenuOverlay> {
  bool _showSettings = false;

  void _update(ReaderSettings s) => widget.onSettingsChanged(s);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      onEnd: () => setState(() {}),
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Material(
          color: Colors.black54,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _topBar(scheme),
                const Spacer(),
                if (_showSettings)
                  _settingsPanel(scheme)
                else
                  _controlBar(scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(ColorScheme scheme) => Container(
        color: Colors.black38,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                Navigator.of(context).maybePop();
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.bookTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  Text(widget.chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _controlBar(ColorScheme scheme) => Container(
        color: Colors.black38,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(_chapterLabel,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: widget.chapterCount <= 1
                          ? 0
                          : widget.chapterIndex / (widget.chapterCount - 1),
                      onChanged: widget.chapterCount <= 1
                          ? null
                          : (v) => widget.onJumpChapter(
                              (v * (widget.chapterCount - 1)).round()),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _barButton(Icons.chevron_left_rounded, '上一章',
                    widget.chapterIndex > 0
                        ? () => widget.onJumpChapter(widget.chapterIndex - 1)
                        : null),
                _barButton(Icons.menu_rounded, '目录', widget.onOpenToc),
                _barButton(Icons.headphones_rounded, '听书', widget.onToggleAudio),
                _barButton(Icons.tune_rounded, '设置', () {
                  setState(() => _showSettings = true);
                }),
                _barButton(
                    Icons.chevron_right_rounded,
                    '下一章',
                    widget.chapterIndex < widget.chapterCount - 1
                        ? () => widget.onJumpChapter(widget.chapterIndex + 1)
                        : null),
              ],
            ),
          ],
        ),
      );

  String get _chapterLabel =>
      '${widget.chapterIndex + 1}/${widget.chapterCount}章';

  Widget _barButton(IconData icon, String label, VoidCallback? onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11)),
            ],
          ),
        ),
      );

  // ── 设置面板 ──────────────────────────────────────────────

  Widget _settingsPanel(ColorScheme scheme) => Container(
        color: Colors.black45,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('阅读设置',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Colors.white),
                  onPressed: () => setState(() => _showSettings = false),
                ),
              ],
            ),
            // 亮度
            _settingRow(
              '亮度',
              Expanded(
                child: Slider(
                  value: widget.settings.brightness,
                  min: 0.3,
                  max: 1.0,
                  onChanged: (v) =>
                      _update(widget.settings.copyWith(brightness: v)),
                ),
              ),
            ),
            // 字号
            _settingRow(
              '字号',
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _iconBtn(Icons.remove_rounded, () {
                    final v = (widget.settings.fontSize - 1)
                        .clamp(ReaderSettings.fontSizeMin,
                            ReaderSettings.fontSizeMax);
                    _update(widget.settings.copyWith(fontSize: v));
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('${widget.settings.fontSize.round()}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                  _iconBtn(Icons.add_rounded, () {
                    final v = (widget.settings.fontSize + 1)
                        .clamp(ReaderSettings.fontSizeMin,
                            ReaderSettings.fontSizeMax);
                    _update(widget.settings.copyWith(fontSize: v));
                  }),
                ],
              ),
            ),
            // 行距
            _settingRow(
              '行距',
              _choiceChips(['紧凑', '标准', '宽松'], [1.4, 1.7, 2.0],
                  widget.settings.lineHeight,
                  (v) => _update(widget.settings.copyWith(lineHeight: v))),
            ),
            // 翻页 + 字重
            _settingRow(
              '翻页',
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _choiceChips(['滚动', '翻页'], ReaderPageMode.values,
                      widget.settings.mode,
                      (v) => _update(widget.settings.copyWith(mode: v))),
                  const SizedBox(width: 16),
                  _choiceChips(
                      ['常规', '加粗'],
                      [false, true],
                      widget.settings.bold,
                      (v) => _update(widget.settings.copyWith(bold: v))),
                ],
              ),
            ),
            // 主题色卡
            _settingRow(
              '背景',
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < kReaderPalettes.length; i++)
                    _paletteDot(i),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _paletteDot(int index) {
    final p = kReaderPalettes[index];
    final selected = widget.settings.paletteIndex == index;
    return GestureDetector(
      onTap: () => _update(widget.settings.copyWith(paletteIndex: index)),
      child: Container(
        margin: const EdgeInsets.only(left: 10),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: p.background,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? p.accent : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 16, color: p.accent)
            : null,
      ),
    );
  }

  Widget _settingRow(String label, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
                width: 44,
                child: Text(label,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13))),
            Expanded(child: child),
          ],
        ),
      );

  Widget _choiceChips<T>(
          List<String> labels, List<T> values, T current, ValueChanged<T> on) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < values.length; i++)
            GestureDetector(
              onTap: () => on(values[i]),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: values[i] == current
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        color: values[i] == current
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.65),
                        fontSize: 12)),
              ),
            ),
        ],
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
}