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
  TtsEngine get _engine =>
      _engineKind == TtsEngineKind.edge ? _edgeEngine! : _systemEngine!;

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

  Future<void> _ensureEngines() async {
    if (_edgeEngine == null) {
      _edgeEngine = EdgeTtsEngine();
      await _edgeEngine!.init();
    }
    if (_systemEngine == null) {
      _systemEngine = SystemTtsEngine();
      await _systemEngine!.init();
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
    await _ensureEngines();
    await _engine.stop();

    final p = await SharedPreferences.getInstance();
    var idx = startIndex;
    if (startIndex < 0) {
      idx = p.getInt('$_kPosPrefix$progressKey') ?? 0;
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