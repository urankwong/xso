import 'dart:async';
import 'dart:io';

import 'package:edge_tts/edge_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'tts_engine.dart';

/// Edge TTS 引擎：联网调用微软神经网络语音合成（免费无 key），
/// 生成 MP3 → 写临时文件 → just_audio 播放。
///
/// 暂停/继续由 just_audio 原生支持（不重新合成）。
class EdgeTtsEngine implements TtsEngine {
  AudioPlayer? _player;
  String? _tempPath;
  bool _stopped = false;
  bool _initialized = false;

  /// 精选中文音色（免联网即列）。覆盖主流男声/女声。
  static const _curatedVoices = <TtsVoice>[
    TtsVoice(id: 'zh-CN-XiaoxiaoNeural', label: '晓晓', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaoyiNeural', label: '晓伊', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaochenNeural', label: '晓辰', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaohanNeural', label: '晓涵', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaomengNeural', label: '晓梦', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaomoNeural', label: '晓墨', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaoruiNeural', label: '晓瑞', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaoshuangNeural', label: '晓双', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaoxuanNeural', label: '晓萱', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaoyanNeural', label: '晓颜', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaozhenNeural', label: '晓甄', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaoxiaoMultilingualNeural', label: '晓晓(多语)', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaqiuNeural', label: '晓秋', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaoyuNeural', label: '晓雨', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaoyouNeural', label: '晓悠', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-XiaoyuMultilingualNeural', label: '晓雨(多语)', gender: 'Female', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-YunxiNeural', label: '云希', gender: 'Male', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-YunjianNeural', label: '云健', gender: 'Male', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-YunyangNeural', label: '云扬', gender: 'Male', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-YunfengNeural', label: '云枫', gender: 'Male', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-YunhaoNeural', label: '云皓', gender: 'Male', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-YunxiaNeural', label: '云夏', gender: 'Male', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-YunyeNeural', label: '云野', gender: 'Male', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-YunzeNeural', label: '云泽', gender: 'Male', locale: 'zh-CN'),
    TtsVoice(id: 'zh-CN-YunyiNeural', label: '云逸', gender: 'Male', locale: 'zh-CN'),
    TtsVoice(id: 'zh-TW-HsiaoChenNeural', label: '曉臻(台)', gender: 'Female', locale: 'zh-TW'),
    TtsVoice(id: 'zh-TW-YunJheNeural', label: '雲哲(台)', gender: 'Male', locale: 'zh-TW'),
  ];

  @override
  TtsEngineKind get kind => TtsEngineKind.edge;

  @override
  String get label => 'Edge 联网';

  @override
  bool get requiresNetwork => true;

  @override
  Future<List<TtsVoice>> listVoices() async => _curatedVoices;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _player = AudioPlayer();
    _initialized = true;
  }

  @override
  Future<void> speak(String text, {required String voiceId, required double rate}) async {
    _stopped = false;
    final player = _player;
    if (player == null) throw StateError('EdgeTtsEngine 未初始化');

    final rateStr = _formatRate(rate);
    final comm = Communicate(text: text, voice: voiceId, rate: rateStr);
    final bytes = await comm.toBytes();

    if (_stopped) return;

    final dir = await getTemporaryDirectory();
    _tempPath = '${dir.path}${Platform.pathSeparator}edge_tts_segment.mp3';
    await File(_tempPath!).writeAsBytes(bytes);

    if (_stopped) {
      _cleanupTemp();
      return;
    }

    await player.setFilePath(_tempPath!);
    if (_stopped) {
      _cleanupTemp();
      return;
    }

    await player.play();
    _cleanupTemp();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    await _player?.play();
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await _player?.stop();
    _cleanupTemp();
  }

  @override
  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
    _initialized = false;
    _cleanupTemp();
  }

  void _cleanupTemp() {
    if (_tempPath != null) {
      try {
        final f = File(_tempPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      _tempPath = null;
    }
  }

  /// 0.5~2.0 → '+0%'/'+50%'/'-50%'（Edge 格式）
  static String _formatRate(double rate) {
    final pct = ((rate - 1.0) * 100).round().clamp(-50, 100);
    final sign = pct >= 0 ? '+' : '-';
    return '$sign${pct.abs()}%';
  }
}