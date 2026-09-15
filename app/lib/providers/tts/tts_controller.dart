import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:source_engine/source_engine.dart';

import '../reader_content.dart';
import 'edge_tts_engine.dart';
import 'system_tts_engine.dart';
import 'tts_engine.dart';

/// 听书状态
enum TtsStatus { idle, loading, playing, paused, error }

/// 听书控制器：断句 → 逐段朗读 → 自动跨章 → 进度持久化。
///
/// 状态机：
/// - `idle`：未开始或已停止
/// - `loading`：正在抓取章节内容或合成语音
/// - `playing`：正在朗读
/// - `paused`：已暂停
/// - `error`：出错（网络失败等）
///
/// 引擎切换：Edge（联网）↔ 系统（离线），切换时保持当前段位置。
class TtsController extends ChangeNotifier {
  static const _kPosPrefix = 'read_audio_pos_';
  static const _kEngine = 'tts.engine';
  static const _kVoiceEdge = 'tts.voice.edge';
  static const _kVoiceSystem = 'tts.voice.system';
  static const _kRate = 'tts.rate';

  TtsStatus _status = TtsStatus.idle;
  TtsEngineKind _engineKind = TtsEngineKind.edge;
  TtsVoice? _voice;
  double _rate = 1.0;
  int _chapterIndex = 0;
  int _segmentIndex = 0;
  List<String> _segments = const [];
  String? _error;

  EdgeTtsEngine? _edgeEngine;
  SystemTtsEngine? _systemEngine;

  /// 初始化失败过的引擎（不代表不能重试，仅用于给出更准确的提示）
  final Set<TtsEngineKind> _engineFailed = {};

  /// 取当前引擎。不可用时抛可读异常 —— 调用方（start）统一捕获并转成
  /// 用户能看懂的提示，而不是让 `!` 抛出 NPE 式的空断言崩溃。
  TtsEngine get _engine {
    final e = _engineKind == TtsEngineKind.edge ? _edgeEngine : _systemEngine;
    if (e == null) {
      throw StateError(_engineKind == TtsEngineKind.edge
          ? '联网语音引擎不可用'
          : '系统离线语音引擎不可用');
    }
    return e;
  }

  List<Chapter>? _chapters;
  ChapterContentRepository? _repo;
  String _progressKey = '';

  /// 防重入：段播放完成回调正在处理中
  bool _advancing = false;

  /// 是否已调用 dispose
  bool _disposed = false;

  // ── 公开状态 ──────────────────────────────────────────────

  TtsStatus get status => _status;
  TtsEngineKind get engineKind => _engineKind;
  TtsVoice? get voice => _voice;
  double get rate => _rate;
  int get chapterIndex => _chapterIndex;
  int get segmentIndex => _segmentIndex;
  int get segmentCount => _segments.length;
  String? get error => _error;
  bool get isActive => _status != TtsStatus.idle;
  String? get currentSegmentPreview =>
      _segmentIndex < _segments.length ? _segments[_segmentIndex] : null;

  // ── 初始化 ──────────────────────────────────────────────

  /// 从持久化恢复引擎/音色/语速偏好
  Future<void> loadPreferences() async {
    final p = await SharedPreferences.getInstance();
    final engineName = p.getString(_kEngine);
    if (engineName == 'system') {
      _engineKind = TtsEngineKind.system;
    }
    _rate = p.getDouble(_kRate) ?? 1.0;
    await _ensureEngines();
    final voiceKey = _engineKind == TtsEngineKind.edge ? _kVoiceEdge : _kVoiceSystem;
    final savedVoice = p.getString(voiceKey);
    if (savedVoice != null) {
      final voices = await _engine.listVoices();
      _voice = voices.where((v) => v.id == savedVoice).firstOrNull;
    }
    _voice ??= (await _engine.listVoices()).firstOrNull;
    _safeNotify();
  }

  /// 初始化两个引擎。
  ///
  /// **任一引擎初始化失败都不能连坐另一个**：系统 TTS 在没装语音数据的
  /// 设备上会抛异常，而它挂在 start() 的必经路径上 —— 原来没有 try/catch，
  /// 结果就是联网引擎明明可用、整个听书却直接卡住（状态停在 loading，
  /// 面板上点任何按钮都无响应）。
  Future<void> _ensureEngines() async {
    if (_edgeEngine == null && !_engineFailed.contains(TtsEngineKind.edge)) {
      try {
        final e = EdgeTtsEngine();
        await e.init();
        _edgeEngine = e;
      } catch (err) {
        _edgeEngine = null;
        _engineFailed.add(TtsEngineKind.edge);
        debugPrint('[TTS] Edge 引擎初始化失败: $err');
      }
    }
    if (_systemEngine == null && !_engineFailed.contains(TtsEngineKind.system)) {
      try {
        final e = SystemTtsEngine();
        await e.init();
        _systemEngine = e;
      } catch (err) {
        _systemEngine = null;
        _engineFailed.add(TtsEngineKind.system);
        debugPrint('[TTS] 系统语音引擎初始化失败: $err');
      }
    }
  }

  /// 列出当前引擎可用音色
  Future<List<TtsVoice>> listVoices() async {
    await _ensureEngines();
    return _engine.listVoices();
  }

  // ── 播放控制 ──────────────────────────────────────────────

  /// 开始听书：从 [startIndex] 章节开始
  Future<void> start({
    required List<Chapter> chapters,
    required ChapterContentRepository repo,
    required String progressKey,
    int startIndex = 0,
  }) async {
    _chapters = chapters;
    _repo = repo;
    _progressKey = progressKey;
    _error = null;
    // 整体兜底：start 里的每一步（引擎初始化、抓正文、首段合成）都可能抛。
    // 不捕获的话异常会逃到 UI 层，而状态停留在 loading/idle —— 用户看到
    // 面板却按什么都没反应（实测模拟器上正是这个表现）。
    try {
      await _ensureEngines();
      await _engine.stop();

      final p = await SharedPreferences.getInstance();
      var idx = startIndex;
      if (startIndex < 0) {
        idx = p.getInt('$_kPosPrefix$progressKey') ?? 0;
      }
      if (chapters.isEmpty) {
        _status = TtsStatus.error;
        _error = '该源没有可用目录，无法听书';
        _safeNotify();
        return;
      }
      idx = idx.clamp(0, chapters.length - 1);

      _status = TtsStatus.loading;
      _safeNotify();

      await _loadChapter(idx);
      if (_status == TtsStatus.error) return;
      _segmentIndex = 0;
      _status = TtsStatus.playing;
      _safeNotify();
      _playCurrent();
    } catch (e) {
      _status = TtsStatus.error;
      _error = _friendlyError(e);
      _safeNotify();
      debugPrint('[TTS] start 失败: $e');
    }
  }

  /// 面板已打开但处于 idle（未开始）或 error（失败）时，用户再点播放。
  ///
  /// 复用上次的章节/仓库/进度键重启 —— 音频条自身没有这些参数，
  /// 只能由控制器自己记住。
  Future<void> restart() async {
    final chapters = _chapters;
    final repo = _repo;
    if (chapters == null || repo == null) return;
    await start(
      chapters: chapters,
      repo: repo,
      progressKey: _progressKey,
      startIndex: _chapterIndex,
    );
  }

  /// 把底层异常翻译成用户能看懂的话，并给出可执行的下一步。
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('HandshakeException') ||
        s.contains('Connection') ||
        s.contains('TimeoutException') ||
        s.contains('网络')) {
      return '联网语音合成失败（网络不可达），可在上方切换到「系统离线」再试';
    }
    if (s.contains('引擎不可用')) {
      return '当前语音引擎不可用，请切换到另一个引擎';
    }
    return s.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
  }

  Future<void> pause() async {
    if (_status != TtsStatus.playing) return;
    await _engine.pause();
    _status = TtsStatus.paused;
    _safeNotify();
  }

  Future<void> resume() async {
    if (_status != TtsStatus.paused) return;
    _status = TtsStatus.playing;
    _safeNotify();
    await _engine.resume();
  }

  Future<void> stop() async {
    _advancing = false;
    await _engine.stop();
    _status = TtsStatus.idle;
    _safeNotify();
  }

  /// 下一段（自动跨章）
  Future<void> nextSegment() async {
    if (_chapters == null) return;
    _advancing = false;
    await _engine.stop();

    if (_segmentIndex + 1 < _segments.length) {
      _segmentIndex++;
      _status = TtsStatus.playing;
      _safeNotify();
      _playCurrent();
      return;
    }
    if (_chapterIndex + 1 < _chapters!.length) {
      _status = TtsStatus.loading;
      _safeNotify();
      await _loadChapter(_chapterIndex + 1);
      if (_status == TtsStatus.error) return;
      _segmentIndex = 0;
      _status = TtsStatus.playing;
      _safeNotify();
      _playCurrent();
      return;
    }
    _status = TtsStatus.idle;
    _safeNotify();
  }

  /// 上一段（自动跨章）
  Future<void> prevSegment() async {
    if (_chapters == null) return;
    _advancing = false;
    await _engine.stop();

    if (_segmentIndex > 0) {
      _segmentIndex--;
      _status = TtsStatus.playing;
      _safeNotify();
      _playCurrent();
      return;
    }
    if (_chapterIndex > 0) {
      _status = TtsStatus.loading;
      _safeNotify();
      await _loadChapter(_chapterIndex - 1);
      if (_status == TtsStatus.error) return;
      _segmentIndex = _segments.isEmpty ? 0 : _segments.length - 1;
      _status = TtsStatus.playing;
      _safeNotify();
      _playCurrent();
      return;
    }
    _status = TtsStatus.idle;
    _safeNotify();
  }

  // ── 引擎/音色/语速 ──────────────────────────────────────────

  Future<void> setEngine(TtsEngineKind kind) async {
    if (kind == _engineKind) return;
    final wasPlaying = _status == TtsStatus.playing || _status == TtsStatus.paused;
    final segIdx = _segmentIndex;
    final chIdx = _chapterIndex;
    final segs = _segments;
    final chapters = _chapters;
    final repo = _repo;
    final key = _progressKey;

    await _engine.stop();
    _engineKind = kind;
    await _ensureEngines();

    final p = await SharedPreferences.getInstance();
    await p.setString(_kEngine, kind.name);
    final voiceKey = kind == TtsEngineKind.edge ? _kVoiceEdge : _kVoiceSystem;
    final savedVoice = p.getString(voiceKey);
    if (savedVoice != null) {
      final voices = await _engine.listVoices();
      _voice = voices.where((v) => v.id == savedVoice).firstOrNull;
    }
    _voice ??= (await _engine.listVoices()).firstOrNull;
    _safeNotify();

    if (wasPlaying && chapters != null && repo != null) {
      _chapters = chapters;
      _repo = repo;
      _progressKey = key;
      _segments = segs;
      _chapterIndex = chIdx;
      _segmentIndex = segIdx;
      _status = TtsStatus.playing;
      _safeNotify();
      _playCurrent();
    }
  }

  Future<void> setVoice(TtsVoice v) async {
    _voice = v;
    final p = await SharedPreferences.getInstance();
    final key = _engineKind == TtsEngineKind.edge ? _kVoiceEdge : _kVoiceSystem;
    await p.setString(key, v.id);
    _safeNotify();
  }

  Future<void> setRate(double r) async {
    _rate = r.clamp(0.5, 2.0);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kRate, _rate);
    _safeNotify();
  }

  // ── 内部 ──────────────────────────────────────────────────

  Future<void> _loadChapter(int idx) async {
    final repo = _repo;
    final chapters = _chapters;
    if (repo == null || chapters == null || idx < 0 || idx >= chapters.length) {
      _status = TtsStatus.error;
      _error = '章节不可用';
      _safeNotify();
      return;
    }
    _chapterIndex = idx;
    try {
      final text = await repo.fetch(chapters[idx].url);
      _segments = splitSentences(text);
      if (_segments.isEmpty) {
        _segments = ['(本章内容为空)'];
      }
      final p = await SharedPreferences.getInstance();
      await p.setInt('$_kPosPrefix$_progressKey', idx);
    } catch (e) {
      _status = TtsStatus.error;
      _error = e.toString().replaceFirst('SourceExecutionException', '抓取失败');
      _safeNotify();
    }
  }

  void _playCurrent() {
    if (_disposed || _status != TtsStatus.playing) return;
    if (_segmentIndex >= _segments.length) {
      _onSegmentComplete();
      return;
    }
    final text = _segments[_segmentIndex];
    final voiceId = _voice?.id;
    if (voiceId == null) {
      _status = TtsStatus.error;
      _error = '未选择音色';
      _safeNotify();
      return;
    }

    _advancing = true;
    _engine.speak(text, voiceId: voiceId, rate: _rate).then((_) {
      if (!_advancing) return;
      _onSegmentComplete();
    }).catchError((e) {
      if (!_advancing) return;
      _advancing = false;
      _status = TtsStatus.error;
      _error = e.toString();
      _safeNotify();
    });
  }

  void _onSegmentComplete() {
    _advancing = false;
    if (_disposed || _status != TtsStatus.playing) return;

    if (_segmentIndex + 1 < _segments.length) {
      _segmentIndex++;
      _safeNotify();
      _playCurrent();
      return;
    }
    if (_chapterIndex + 1 < (_chapters?.length ?? 0)) {
      _status = TtsStatus.loading;
      _safeNotify();
      _loadChapter(_chapterIndex + 1).then((_) {
        if (_disposed || _status == TtsStatus.error) return;
        _segmentIndex = 0;
        _status = TtsStatus.playing;
        _safeNotify();
        _playCurrent();
      });
      return;
    }
    _status = TtsStatus.idle;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _advancing = false;
    await _edgeEngine?.dispose();
    await _systemEngine?.dispose();
    _edgeEngine = null;
    _systemEngine = null;
    super.dispose();
  }

  // ── 断句 ──────────────────────────────────────────────────

  /// 将正文拆分为朗读段落。
  ///
  /// 规则：
  /// - 按 。！？；…\n 切句，保留句末标点
  /// - 合并过短片段（<4 字）到前句
  /// - 超长片段（>200 字）按 ，、 切分
  static List<String> splitSentences(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), ' ')
        .trim();
    if (cleaned.isEmpty) return const [];

    final parts = <String>[];
    final buf = StringBuffer();
    for (final ch in cleaned.runes) {
      buf.writeCharCode(ch);
      final s = String.fromCharCode(ch);
      if (s == '。' ||
          s == '！' ||
          s == '？' ||
          s == '；' ||
          s == '…' ||
          s == '\n' ||
          s == '.' ||
          s == '!' ||
          s == '?') {
        final t = buf.toString().trim();
        if (t.isNotEmpty) parts.add(t);
        buf.clear();
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) parts.add(tail);

    final merged = <String>[];
    for (final p in parts) {
      if (p.length < 4 && merged.isNotEmpty) {
        merged[merged.length - 1] += p;
      } else {
        merged.add(p);
      }
    }

    final result = <String>[];
    for (final p in merged) {
      if (p.length <= 200) {
        result.add(p);
        continue;
      }
      final sub = <String>[];
      final sb = StringBuffer();
      for (final ch in p.runes) {
        sb.writeCharCode(ch);
        final s = String.fromCharCode(ch);
        if (s == '，' || s == '、' || s == ',' || s == ' ') {
          final t = sb.toString().trim();
          if (t.isNotEmpty) sub.add(t);
          sb.clear();
        }
      }
      final t = sb.toString().trim();
      if (t.isNotEmpty) sub.add(t);
      for (final s in sub) {
        if (s.length < 4 && result.isNotEmpty) {
          result[result.length - 1] += s;
        } else {
          result.add(s);
        }
      }
    }
    return result;
  }
}