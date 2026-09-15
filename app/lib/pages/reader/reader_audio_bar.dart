import 'package:flutter/material.dart';

import '../../providers/tts/tts_controller.dart';
import '../../providers/tts/tts_engine.dart';

/// 听书控制条：内嵌阅读页底部，边看边听。
///
/// - 引擎切换 chip（Edge 联网 / 系统离线）
/// - 音色 PopupMenu
/// - 语速 Slider（0.5~2.0）
/// - 上一段 / 播放暂停 / 下一段
/// - 当前段文本预览（1 行省略）
/// - 关闭按钮
///
/// 半透明深色背景，沉浸式阅读下不刺眼。
class ReaderAudioBar extends StatefulWidget {
  final TtsController controller;
  final VoidCallback onClose;

  const ReaderAudioBar({
    super.key,
    required this.controller,
    required this.onClose,
  });

  @override
  State<ReaderAudioBar> createState() => _ReaderAudioBarState();
}

class _ReaderAudioBarState extends State<ReaderAudioBar> {
  List<TtsVoice> _voices = const [];
  bool _voiceLoading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _refreshVoices();
  }

  @override
  void didUpdateWidget(ReaderAudioBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _refreshVoices();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshVoices() async {
    setState(() => _voiceLoading = true);
    try {
      final v = await widget.controller.listVoices();
      if (mounted) {
        _voices = v;
        _voiceLoading = false;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        _voiceLoading = false;
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _previewRow(c),
              const SizedBox(height: 8),
              _controlRow(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewRow(TtsController c) => Row(
        children: [
          Expanded(
            child: Text(
              c.currentSegmentPreview ?? _statusText(c),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
          if (c.status == TtsStatus.error)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.error_outline, color: Colors.red.shade300, size: 16),
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: () async {
              await c.stop();
              widget.onClose();
            },
            visualDensity: VisualDensity.compact,
          ),
        ],
      );

  String _statusText(TtsController c) {
    switch (c.status) {
      case TtsStatus.idle:
        return '听书已停止';
      case TtsStatus.loading:
        return '加载中…';
      case TtsStatus.playing:
        return '正在朗读…';
      case TtsStatus.paused:
        return '已暂停';
      case TtsStatus.error:
        return c.error ?? '出错';
    }
  }

  Widget _controlRow(TtsController c) => Row(
        children: [
          _engineChip(c),
          const SizedBox(width: 8),
          _voiceButton(c),
          const SizedBox(width: 8),
          _rateControl(c),
          const Spacer(),
          _segmentButton(Icons.skip_previous_rounded, c.prevSegment),
          _playPauseButton(c),
          _segmentButton(Icons.skip_next_rounded, c.nextSegment),
        ],
      );

  Widget _engineChip(TtsController c) {
    return GestureDetector(
      onTap: () => c.setEngine(
        c.engineKind == TtsEngineKind.edge ? TtsEngineKind.system : TtsEngineKind.edge,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              c.engineKind == TtsEngineKind.edge ? Icons.cloud : Icons.phone_android,
              size: 13,
              color: Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              c.engineKind == TtsEngineKind.edge ? 'Edge' : '系统',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceButton(TtsController c) {
    final voice = c.voice;
    return PopupMenuButton<String>(
      tooltip: '选择音色',
      onSelected: (id) {
        final v = _voices.where((x) => x.id == id).firstOrNull;
        if (v != null) c.setVoice(v);
      },
      itemBuilder: (_) => [
        if (_voiceLoading)
          const PopupMenuItem(enabled: false, child: Text('加载中…'))
        else if (_voices.isEmpty)
          const PopupMenuItem(enabled: false, child: Text('无可用音色'))
        else
          for (final v in _voices)
            PopupMenuItem(
              value: v.id,
              child: Row(
                children: [
                  if (v.id == voice?.id)
                    const Icon(Icons.check, size: 16)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${v.label}${v.gender != null ? ' · ${v.gender == 'Female' ? '女' : '男'}' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.record_voice_over, size: 13, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              voice?.label ?? '默认',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _rateControl(TtsController c) {
    return SizedBox(
      width: 90,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${c.rate.toStringAsFixed(1)}x',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 2,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: c.rate,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                onChanged: c.setRate,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentButton(IconData icon, Future<void> Function() action) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 26),
      onPressed: () => action(),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _playPauseButton(TtsController c) {
    final isPlaying = c.status == TtsStatus.playing;
    final isLoading = c.status == TtsStatus.loading;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28,
              ),
        onPressed: () async {
          if (isLoading) return;
          if (isPlaying) {
            await c.pause();
          } else if (c.status == TtsStatus.paused) {
            await c.resume();
          } else {
            // idle（尚未开始）或 error（上次失败）：这两个状态原来是**静默
            // 什么都不做** —— 用户看到面板上有个播放键，按下去毫无反应，
            // 感受就是"听书不能用"。改为重建听书：控制器记住上次的
            // 章节/仓库/进度，失败时给出可执行的提示。
            await c.restart();
          }
        },
      ),
    );
  }
}