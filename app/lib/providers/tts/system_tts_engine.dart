import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'tts_engine.dart';

/// 系统 TTS 引擎：调用平台原生 TTS（Android TextToSpeech / iOS AVSpeechSynthesizer）。
///
/// 离线可用，音色取决于设备已安装的语音数据。
/// 暂停后继续需重读当前段（flutter_tts 无 resume API）。
class SystemTtsEngine implements TtsEngine {
  FlutterTts? _tts;
  Completer<void>? _completer;
  bool _initialized = false;

  /// 当前段文本（resume 时重读）
  String? _currentText;
  double _currentRate = 1.0;

  @override
  TtsEngineKind get kind => TtsEngineKind.system;

  @override
  String get label => '系统离线';

  @override
  bool get requiresNetwork => false;

  @override
  Future<List<TtsVoice>> listVoices() async {
    final tts = _tts;
    if (tts == null) return const [];
    final raw = await tts.getVoices;
    if (raw == null) return const [];
    final list = raw as List;
    final voices = <TtsVoice>[];
    for (final v in list) {
      final map = v as Map;
      final name = map['name']?.toString() ?? '';
      final locale = map['locale']?.toString() ?? '';
      if (locale.toLowerCase().startsWith('zh')) {
        voices.add(TtsVoice(
          id: '$name|$locale',
          label: name,
          locale: locale,
        ));
      }
    }
    if (voices.isEmpty) {
      for (final v in list) {
        final map = v as Map;
        final name = map['name']?.toString() ?? '';
        final locale = map['locale']?.toString() ?? '';
        voices.add(TtsVoice(
          id: '$name|$locale',
          label: name,
          locale: locale,
        ));
      }
    }
    return voices;
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    _tts = FlutterTts();
    await _tts!.awaitSpeakCompletion(true);
    _tts!.setCompletionHandler(() {
      final c = _completer;
      if (c != null && !c.isCompleted) c.complete();
    });
    _tts!.setErrorHandler((err) {
      final c = _completer;
      if (c != null && !c.isCompleted) c.complete();
    });
    _initialized = true;
  }

  @override
  Future<void> speak(String text, {required String voiceId, required double rate}) async {
    _currentText = text;
    _currentRate = rate;

    final tts = _tts;
    if (tts == null) throw StateError('SystemTtsEngine 未初始化');

    _completer = Completer<void>();

    await tts.setSpeechRate(_convertRate(rate));
    final parts = voiceId.split('|');
    if (parts.length >= 2) {
      try {
        await tts.setVoice({'name': parts[0], 'locale': parts[1]});
      } catch (_) {}
    }
    await tts.speak(text);

    return _completer!.future;
  }

  @override
  Future<void> pause() async {
    await _tts?.pause();
  }

  @override
  Future<void> resume() async {
    final text = _currentText;
    if (text == null) return;

    _completer = Completer<void>();
    await _tts!.setSpeechRate(_convertRate(_currentRate));
    await _tts!.speak(text);
    return _completer!.future;
  }

  @override
  Future<void> stop() async {

    await _tts?.stop();
    final c = _completer;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> dispose() async {
    await _tts?.stop();
    _tts = null;
    _initialized = false;
  }

  /// 0.5~2.0 → 0.0~1.0（flutter_tts 语义：0.0 最慢，1.0 最快，0.5 常速）
  static double _convertRate(double rate) {
    return ((rate - 0.5) / 1.5).clamp(0.0, 1.0);
  }
}