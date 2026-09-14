import 'dart:async';

/// TTS 引擎类型
enum TtsEngineKind { edge, system }

/// TTS 音色
class TtsVoice {
  /// 引擎内音色标识（Edge: shortName 如 `zh-CN-XiaoxiaoNeural`；
  /// 系统: `name|locale` 编码）
  final String id;

  /// 显示名
  final String label;

  /// 性别（`Male`/`Female`/`null`）
  final String? gender;

  /// 语言区域（如 `zh-CN`）
  final String? locale;

  const TtsVoice({
    required this.id,
    required this.label,
    this.gender,
    this.locale,
  });

  @override
  String toString() => '$label${gender != null ? ' ($gender)' : ''}';
}

/// TTS 引擎抽象。
///
/// 统一语速为 0.5~2.0 倍速（1.0 = 常速），各引擎内部自行转换。
/// `speak` 返回的 Future 在播放结束时完成；若中途 `stop` 则立即完成。
abstract class TtsEngine {
  TtsEngineKind get kind;
  String get label;
  bool get requiresNetwork;

  /// 列出可用音色。Edge 需联网（或用内置精选列表）；系统从平台读取。
  Future<List<TtsVoice>> listVoices();

  /// 初始化（注册回调等）。幂等。
  Future<void> init();

  /// 朗读 [text]，播放结束时 Future 完成。
  Future<void> speak(String text, {required String voiceId, required double rate});

  /// 暂停（Edge 真暂停；系统尽力而为）
  Future<void> pause();

  /// 继续播放（Edge 真继续；系统重读当前段）
  Future<void> resume();

  /// 停止并释放当前播放资源
  Future<void> stop();

  /// 释放引擎所有资源
  Future<void> dispose();
}