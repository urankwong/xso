import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:public_file_saver/public_file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'id3_tags.dart';
import 'lyric.dart';
import 'metadata.dart';

enum DownloadStatus { queued, running, done, failed, canceled }

/// 下载保存位置模式。
/// - app：应用私有目录（现状，Android 11+ 对用户不可见，无需权限）
/// - media：系统媒体库（MediaStore，写入「音乐/视频/下载」，对用户可见且被扫描）
/// - custom：用户经 SAF 选定的任意文件夹（含 Download），完全可控
enum SaveLocation { app, media, custom }

/// 下载资源类型（由 subDir 派生），用于下载页的类型标签与筛选
enum DownloadKind { music, audiobook, movie, book }

DownloadKind kindOfSubDir(String subDir) => switch (subDir) {
      'Movies' => DownloadKind.movie,
      'Books' => DownloadKind.book,
      'Audiobook' => DownloadKind.audiobook,
      _ => DownloadKind.music,
    };

/// 资源类型 → 保存子目录（Music / Audiobook / Movies / Books）
String subDirOfKind(DownloadKind kind) => switch (kind) {
      DownloadKind.movie => 'Movies',
      DownloadKind.book => 'Books',
      DownloadKind.audiobook => 'Audiobook',
      DownloadKind.music => 'Music',
    };

/// 是否在下载前弹确认面板（SharedPreferences 'downloadConfirm'，默认开）。
/// 每次下载现读，保证设置页改动能立即生效（无需重启）。
Future<bool> downloadConfirmEnabled() async {
  try {
    return (await SharedPreferences.getInstance())
            .getBool('downloadConfirm') ??
        true;
  } catch (_) {
    return true;
  }
}

/// 默认播放/下载音质（SharedPreferences 'defaultQuality'，默认 standard）。
/// 值为 lx 音质档位 id：standard/320k/flac/flac24bit。
Future<String> defaultQuality() async {
  try {
    return (await SharedPreferences.getInstance())
            .getString('defaultQuality') ??
        'standard';
  } catch (_) {
    return 'standard';
  }
}

@immutable
class DownloadTask {
  final String id; // url 去重
  final String title;
  final String? artist;
  final String? cover; // 源透传封面 URL（写标签取图链第①级）
  final String? album;
  final String qualityLabel;
  final String url;
  final DownloadStatus status;
  final double progress; // 0~1
  final String? savedPath;
  final String? error;
  final int retries; // 重试次数
  final String subDir; // 保存子目录：Music / Audiobook / Movies / Books
  final Map<String, String>? headers; // 部分 CDN 需要 Referer 等头
  final int fileSize; // 文件字节数：下载中若已知 total 则更新，完成后取实际大小

  const DownloadTask({
    required this.id,
    required this.title,
    this.artist,
    this.cover,
    this.album,
    required this.qualityLabel,
    required this.url,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.savedPath,
    this.error,
    this.retries = 0,
    this.subDir = 'Music',
    this.headers,
    this.fileSize = 0,
  });

  /// 资源类型（由 subDir 派生）
  DownloadKind get kind => kindOfSubDir(subDir);

  DownloadTask copyWith(
          {DownloadStatus? status,
          double? progress,
          String? savedPath,
          String? error,
          String? qualityLabel,
          int? retries,
          int? fileSize,
          bool clearSavedPath = false,
          bool clearError = false}) =>
      DownloadTask(
        id: id,
        title: title,
        artist: artist,
        cover: cover,
        album: album,
        qualityLabel: qualityLabel ?? this.qualityLabel,
        url: url,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        savedPath: clearSavedPath ? null : (savedPath ?? this.savedPath),
        error: clearError ? null : (error ?? this.error),
        retries: retries ?? this.retries,
        subDir: subDir,
        headers: headers,
        fileSize: fileSize ?? this.fileSize,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'cover': cover,
        'album': album,
        'qualityLabel': qualityLabel,
        'url': url,
        'status': status.name,
        'progress': progress,
        'savedPath': savedPath,
        'error': error,
        'retries': retries,
        'subDir': subDir,
        'headers': headers,
        'fileSize': fileSize,
      };

  static DownloadTask fromJson(Map<String, dynamic> j) => DownloadTask(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        artist: j['artist'] as String?,
        cover: j['cover'] as String?,
        album: j['album'] as String?,
        qualityLabel: (j['qualityLabel'] as String?) ?? '默认音质',
        url: (j['url'] as String?) ?? '',
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => DownloadStatus.failed,
        ),
        progress: ((j['progress'] as num?) ?? 0).toDouble(),
        savedPath: j['savedPath'] as String?,
        error: j['error'] as String?,
        retries: (j['retries'] as int?) ?? 0,
        subDir: (j['subDir'] as String?) ?? 'Music',
        headers: (j['headers'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString())),
        fileSize: (j['fileSize'] as int?) ?? 0,
      );
}

/// 下载队列：顺序执行，支持排队/取消/重试；任务列表持久化到应用支持目录
class DownloadsController extends ChangeNotifier {
  final Dio _dio;
  final List<DownloadTask> _tasks = [];
  final Set<String> _ids = {};
  // 复合去重 key：title|artist|quality
  // MusicFree 等插件每次解析生成的 CDN URL 签名不同，仅靠 URL 无法识别"同一首歌"。
  // 这个 set 让用户再次下载同名+同艺人+同音质时被友好拦截，而不是在列表里重复出现。
  final Set<String> _compositeKeys = {};
  bool _running = false;
  bool _loaded = false;
  Directory? _taskDir;
  final Map<String, Directory> _dirCache = {};

  /// 进行中任务的取消句柄：用户点「取消」时用其中止 dio 请求
  final Map<String, CancelToken> _tokens = {};

  DownloadsController(this._dio, {MetadataService? metadata, LyricService? lyric})
      : _metadata = metadata,
        _lyric = lyric {
    // 启动时恢复上次会话的任务记录
    unawaited(_load());
  }

  final MetadataService? _metadata;
  final LyricService? _lyric;

  /// 下载保存位置（持久化于 SharedPreferences 'saveLocation'）
  SaveLocation _saveLoc = SaveLocation.app;

  /// 系统保存插件（Android 10+ 走 MediaStore，无需权限；内部原生实现，宿主无需写 Kotlin）
  final PublicFileSaver _saver = PublicFileSaver();

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool get loaded => _loaded;
  int get activeCount =>
      _tasks.where((t) => t.status == DownloadStatus.queued || t.status == DownloadStatus.running).length;

  // ---------- 持久化 ----------

  Future<Directory> _ensureTaskDir() async {
    if (_taskDir != null) return _taskDir!;
    final base = await getApplicationSupportDirectory();
    _taskDir = Directory('${base.path}/downloads');
    await _taskDir!.create(recursive: true);
    return _taskDir!;
  }

  Future<void> _save() async {
    try {
      final dir = await _ensureTaskDir();
      final file = File('${dir.path}/tasks.json');
      final data = _tasks.map((t) => t.toJson()).toList();
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // 持久化失败不影响下载流程
    }
  }

  Future<void> _load() async {
    try {
      final dir = await _ensureTaskDir();
      final file = File('${dir.path}/tasks.json');
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final list = (jsonDecode(raw) as List)
              .whereType<Map<String, dynamic>>()
              .map(DownloadTask.fromJson);
          for (final t in list) {
            if (_ids.contains(t.id)) continue;
            _ids.add(t.id);
            // 上次中断的任务（queued/running）恢复为失败状态
            _tasks.add(switch (t.status) {
              DownloadStatus.queued ||
              DownloadStatus.running =>
                t.copyWith(
                    status: DownloadStatus.failed,
                    error: '上次中断',
                    clearSavedPath: true),
              _ => t,
            });
          }
        }
      }
    } catch (_) {
      // 损坏的记录文件直接忽略
    }
    // 读取下载保存位置偏好（默认应用目录）
    try {
      final sp = await SharedPreferences.getInstance();
      _saveLoc = switch (sp.getString('saveLocation')) {
        'media' => SaveLocation.media,
        'custom' => SaveLocation.custom,
        _ => SaveLocation.app,
      };
    } catch (_) {
      // 偏好读不到就用默认
    }
    _loaded = true;
    notifyListeners();
  }

  Future<Directory> _ensureDir([String sub = 'Music']) async {
    final base = _dirCache[sub] ?? await _baseDir(sub);
    return base;
  }

  Future<Directory> _baseDir(String sub) async {
    final root = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/$sub');
    await dir.create(recursive: true);
    _dirCache[sub] = dir;
    return dir;
  }

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  /// 从 URL 安全提取文件后缀：只走 path 部分（不带 query），移除所有非字母数字字符；
  /// 解析失败或取不到则回退 'mp3'。纯 URL 字符串让 Uri.parse 抛异常时不会拖垮下载任务。
  static String _extractSuffix(String url) {
    try {
      final path = Uri.parse(url).path;
      final dot = path.lastIndexOf('.');
      if (dot < 0 || dot == path.length - 1) return 'mp3';
      final raw = path.substring(dot + 1);
      final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      return cleaned.isEmpty ? 'mp3' : cleaned.toLowerCase();
    } catch (_) {
      return 'mp3';
    }
  }

  /// 入队一首/一个文件；已存在同 url 的任务则忽略
  Future<bool> enqueue({
    required String url,
    required String title,
    String? artist,
    String? cover,
    String? album,
    String qualityLabel = '默认音质',
    String subDir = 'Music',
    Map<String, String>? headers,
  }) async {
    if (url.isEmpty) return false;
    final cleanedTitle = title.trim();
    final cleanedArtist = (artist ?? '').trim();
    final compositeKey =
        '$cleanedTitle|$cleanedArtist|$qualityLabel'.toLowerCase();
    if (_ids.contains(url) || _compositeKeys.contains(compositeKey)) {
      return false;
    }
    _ids.add(url);
    _compositeKeys.add(compositeKey);
    _tasks.add(DownloadTask(
      id: url,
      title: title,
      artist: artist,
      cover: cover,
      album: album,
      qualityLabel: qualityLabel,
      url: url,
      subDir: subDir,
      headers: headers,
    ));
    notifyListeners();
    unawaited(_save());
    await _pump();
    return true;
  }

  /// 批量入队（音乐结果）
  Future<int> enqueueAll(List<({String url, String title, String? artist})> items,
      {String qualityLabel = '默认音质', String subDir = 'Music'}) async {
    var added = 0;
    for (final it in items) {
      if (it.url.isEmpty) continue;
      final compositeKey =
          '${it.title.trim()}|${(it.artist ?? '').trim()}|$qualityLabel'
              .toLowerCase();
      if (_ids.contains(it.url) || _compositeKeys.contains(compositeKey)) continue;
      _ids.add(it.url);
      _compositeKeys.add(compositeKey);
      _tasks.add(DownloadTask(
        id: it.url,
        title: it.title,
        artist: it.artist,
        qualityLabel: qualityLabel,
        url: it.url,
        subDir: subDir,
      ));
      added++;
    }
    if (added > 0) {
      notifyListeners();
      unawaited(_save());
    }
    await _pump();
    return added;
  }

  /// 失败任务重试：重新排队下载同一 url
  bool retry(String taskId) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return false;
    final t = _tasks[i];
    if (t.status != DownloadStatus.failed && t.status != DownloadStatus.canceled) {
      return false;
    }
    _tasks[i] = t.copyWith(
      status: DownloadStatus.queued,
      progress: 0,
      retries: t.retries + 1,
      clearError: true,
      clearSavedPath: true,
    );
    notifyListeners();
    unawaited(_save());
    unawaited(_pump());
    return true;
  }

  /// 移除任务记录（不限于已结束任务）
  void remove(String taskId) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final removed = _tasks[i];
    _tasks.removeAt(i);
    _ids.remove(taskId);
    _compositeKeys.remove(
        '${removed.title.trim()}|${(removed.artist ?? '').trim()}|${removed.qualityLabel}'
            .toLowerCase());
    notifyListeners();
    unawaited(_save());
  }

  /// 取消任务。
  /// 排队中直接置为 canceled；进行中则中止 dio 请求，由 _runTask 的 catch
  /// 统一落状态 —— 原实现只处理 queued，导致「进行中」任务的取消按钮毫无反应。
  void cancel(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final status = _tasks[i].status;
    if (status == DownloadStatus.queued) {
      _tasks[i] = _tasks[i].copyWith(status: DownloadStatus.canceled);
      notifyListeners();
      unawaited(_save());
      return;
    }
    if (status == DownloadStatus.running) {
      _tokens[id]?.cancel('user cancel');
    }
  }

  /// 取消全部未完成任务（排队 + 进行中）。对已结束的任务是空操作。
  void cancelAll() {
    for (final t in List<DownloadTask>.of(_tasks)) {
      cancel(t.id);
    }
  }

  // ---------- 保存位置 ----------

  SaveLocation get saveLocation => _saveLoc;

  Future<void> setSaveLocation(SaveLocation loc) async {
    _saveLoc = loc;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('saveLocation', switch (loc) {
        SaveLocation.media => 'media',
        SaveLocation.custom => 'custom',
        SaveLocation.app => 'app',
      });
    } catch (_) {}
    notifyListeners();
  }

  /// 已完成数量（用于页面统计）
  int get finishedCount =>
      _tasks.where((t) => t.status == DownloadStatus.done).length;

  void clearFinished() {
    final before = _tasks.length;
    _tasks.removeWhere((t) =>
        t.status == DownloadStatus.done || t.status == DownloadStatus.failed || t.status == DownloadStatus.canceled);
    _ids
      ..clear()
      ..addAll(_tasks.map((t) => t.id));
    _compositeKeys
      ..clear()
      ..addAll(_tasks.map((t) =>
          '${t.title.trim()}|${(t.artist ?? '').trim()}|${t.qualityLabel}'.toLowerCase()));
    if (_tasks.length != before) {
      notifyListeners();
      unawaited(_save());
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = _tasks.indexWhere((t) => t.status == DownloadStatus.queued);
        if (next < 0) break;
        await _runTask(_tasks[next]);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runTask(DownloadTask task) async {
    _update(task.id, status: DownloadStatus.running);
    try {
      // 先落临时文件（应用私有缓存），再做落盘校验与跨目录导出，
      // 避免直接在目标目录写出半截/0 字节文件。
      final cacheDir = await _ensureCacheDir();
      final suffix = _extractSuffix(task.url);
      final tmpName =
          '${_safeName(task.title)}${task.artist != null && task.artist!.isNotEmpty ? ' - ${_safeName(task.artist!)}' : ''} [${_safeName(task.qualityLabel)}].$suffix';
      final tmp = File('${cacheDir.path}/$tmpName');
      final token = CancelToken();
      _tokens[task.id] = token;
      try {
        await _dio.download(
          task.url,
          tmp.path,
          cancelToken: token,
          options: Options(headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
            ...?task.headers, // B 站等 CDN 需要 Referer
          }),
          onReceiveProgress: (received, total) {
            if (total > 0) {
              _update(task.id,
                  progress: (received / total).clamp(0.0, 1.0),
                  fileSize: total);
            }
          },
        );
      } finally {
        _tokens.remove(task.id);
      }
      // 落盘校验：文件必须存在且体积 > 0，否则视为失败，杜绝「显示完成但无文件」。
      // 某些源解析出的 url 实为错误页/空响应，Dio 仍按 200 保存，这里拦截下来。
      if (!await tmp.exists()) {
        _update(task.id,
            status: DownloadStatus.failed,
            error: '下载完成但未生成有效文件（源可能返回了错误页或空内容）');
        return;
      }
      final size = await tmp.length();
      if (size == 0) {
        try {
          await tmp.delete();
        } catch (_) {}
        _update(task.id,
            status: DownloadStatus.failed,
            error: '下载完成但未生成有效文件（源可能返回了错误页或空内容）');
        return;
      }
      // 仅音频（音乐/有声，mp3）写标签：在临时文件上操作，导出时一并带走
      if ((task.subDir == 'Music' || task.subDir == 'Audiobook') &&
          tmp.path.toLowerCase().endsWith('.mp3')) {
        await _writeTags(task, tmp.path);
      }
      final savedPath = await _export(tmp, task);
      if (savedPath == null) {
        _update(task.id, status: DownloadStatus.failed, error: '保存文件失败');
        return;
      }
      _update(task.id,
          status: DownloadStatus.done, progress: 1, savedPath: savedPath, fileSize: size);
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _update(task.id, status: DownloadStatus.canceled);
      } else {
        _update(task.id, status: DownloadStatus.failed, error: e.toString());
      }
    }
  }

  /// 把临时文件导出到最终保存位置（纯 Dart，经 public_file_saver 插件，
  /// 宿主无需编写任何 Kotlin/Java）：
  /// - app：移动到应用私有目录（兼容旧行为，Android 11+ 对用户不可见）
  /// - media：写入系统公开目录 Download/Xso（MediaStore，无需权限、可见、可被扫描）
  /// - custom：弹系统保存框（SAF）由用户指定目录与文件名
  /// 任一步骤异常都回退到应用目录并保留文件，确保「不丢文件、不崩溃」。
  Future<String?> _export(File tmp, DownloadTask task) async {
    final name =
        '${_safeName(task.title)}${task.artist != null && task.artist!.isNotEmpty ? ' - ${_safeName(task.artist!)}' : ''} [${_safeName(task.qualityLabel)}].${_extractSuffix(task.url)}';
    if (_saveLoc == SaveLocation.app) {
      final dir = await _ensureDir(task.subDir);
      final dest = File('${dir.path}/$name');
      await tmp.copy(dest.path);
      try {
        await tmp.delete();
      } catch (_) {}
      return dest.path;
    }
    try {
      final res = await _saver.saveFile(
        // 分析器误报：public_file_saver 内部是条件导入
        // （`io_compat_web.dart` if (dart.library.io) `io_compat.dart`），
        // analyze 按 web 分支解析出 io_compat_web.File，而实际构建走
        // io_compat.dart（= `export 'dart:io' show File`），类型一致。
        // 已由 release APK 实际构建验证通过，故此处不阻断、仅标注。
        // ignore: argument_type_not_assignable
        file: tmp,
        fileName: name,
        subDir: 'Xso',
        useDialog: _saveLoc == SaveLocation.custom,
      );
      try {
        await tmp.delete();
      } catch (_) {}
      if (res == null || !res.isSuccess) return null;
      return res.path ?? res.uri ?? name;
    } catch (e) {
      debugPrint('[downloads] 系统保存失败，回退到应用目录：$e');
      final dir = await _ensureDir(task.subDir);
      final dest = File('${dir.path}/$name');
      await tmp.copy(dest.path);
      try {
        await tmp.delete();
      } catch (_) {}
      return dest.path;
    }
  }

  Future<Directory> _ensureCacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/download_tmp');
    await dir.create(recursive: true);
    return dir;
  }

  /// 下载完成后写音频标签：writeTags 开关（默认开）→ 封面取图链 → LRC 歌词
  /// → ID3v2.3 写入（已有非空字段不覆盖）。失败静默降级，只记一行日志。
  Future<void> _writeTags(DownloadTask t, String path) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('writeTags') ?? true)) return;
      if (!path.toLowerCase().endsWith('.mp3')) {
        debugPrint('[downloads] flac 标签写入待支持：$path');
        return;
      }
      final meta = _metadata;
      if (meta == null) return;
      final cover = await meta.coverBytes(
        sourceCover: t.cover,
        title: t.title,
        artist: t.artist,
        album: t.album,
      );
      String? lrc;
      final lyric = _lyric;
      if (lyric != null) {
        try {
          lrc = lyricsToLrc(
              await lyric.fetch(title: t.title, artist: t.artist ?? ''));
        } catch (_) {
          // 没歌词不阻塞写标签
        }
      }
      await writeMp3Tags(
        path,
        Mp3TagPatch(
          title: t.title,
          artist: t.artist,
          album: t.album,
          cover: cover,
          lyrics: lrc,
        ),
      );
      debugPrint('[downloads] 已写入音频标签：$path');
    } catch (e) {
      debugPrint('[downloads] 标签写入失败（忽略）：$e');
    }
  }

  void _update(String id,
      {DownloadStatus? status,
      double? progress,
      String? savedPath,
      String? error,
      int? fileSize}) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    _tasks[i] = _tasks[i].copyWith(
        status: status,
        progress: progress,
        savedPath: savedPath,
        error: error,
        fileSize: fileSize);
    notifyListeners();
    // 状态/进度变更落盘；进度高频更新时也异步保存，失败时记录最后一次进度
    if (status != null) {
      unawaited(_save());
    }
  }
}

final downloadsProvider = ChangeNotifierProvider<DownloadsController>((ref) {
  return DownloadsController(
    Dio(),
    metadata: ref.watch(metadataProvider),
    lyric: ref.watch(lyricProvider),
  );
});
