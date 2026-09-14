import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'github_release_feed.dart';

/// 「从 GitHub 更新」的纯逻辑层：查版本、挑包、下载，不碰 UI。
///
/// 发布物由 CI（.github/workflows/build.yml）在推 v* tag 时产出：
/// app-debug.apk + app-arm64-v8a-release.apk + app-armeabi-v7a-release.apk，
/// 三者都是 debug 签名，可互相覆盖安装。因此本文件的更新流程是
/// 「下 APK → 拉起系统安装器」，不做增量/差分更新。
class UpdateService {
  static const owner = 'urankwong';
  static const repo = 'xso';

  /// 未认证的 GitHub API 限流是 60 次/小时/IP，所以启动静默检查必须节流
  /// （见 [shouldAutoCheck]），手动点「检查更新」不受节流限制。
  static const latestApi = 'https://api.github.com/repos/$owner/$repo/releases/latest';
  static const releasePage = 'https://github.com/$owner/$repo/releases/latest';

  /// 下载加速前缀（围场/国内直连失败时按顺序回退）。
  /// 前缀式代理：`https://<prefix>/https://github.com/...`
  static const mirrors = <String>[
    'https://gh-proxy.com/',
    'https://ghproxy.net/',
    'https://ghproxy.homeboyc.cn/',
  ];

  /// 两次静默检查的最小间隔。
  static const autoCheckInterval = Duration(hours: 24);

  static const _kLastCheckAt = 'update_last_check_at';
  static const _kSkippedVersion = 'update_skipped_version';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      // GitHub API 没有 UA 会直接 403；Accept 决定返回结构化 JSON。
      'User-Agent': 'xso-android-app',
      'Accept': 'application/vnd.github+json',
    },
  ));

  /// 读取自身版本（0.1.0+6 → AppVersion(0.1.0, build 6)）。
  static Future<AppVersion?> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return AppVersion.parse('${info.version}+${info.buildNumber}');
    } catch (e) {
      debugPrint('[更新] 读取自身版本失败: $e');
      return null;
    }
  }

  /// 拉取最新 Release。
  ///
  /// 顺序刻意是「atom 优先、API 兜底」：未认证的 REST API 配额只有
  /// 60 次/小时/**出口 IP**，手机走运营商 NAT/校园网/代理池时整池设备共享，
  /// 用户随手一点就撞限流；`releases.atom` 是网页端点，不吃 core 配额。
  /// API 只在 atom 拿不到时兜底（它能给出精确的资产名与大小）。
  static Future<UpdateCheckResult> check({String? abiHint}) async {
    final current = await currentVersion();
    final feed = await ReleaseFeed.fetch(owner, repo, abiHint: abiHint);
    if (feed != null) return fromFeed(feed, current);
    try {
      final resp = await _dio.get<dynamic>(latestApi);
      final data = resp.data;
      final map = data is String ? jsonDecode(data) : data;
      if (map is! Map) {
        return UpdateCheckResult.error('返回数据格式异常');
      }
      return evaluate(Map<String, dynamic>.from(map),
          current: current, abiHint: abiHint);
    } on DioException catch (e) {
      return UpdateCheckResult.error(_describeDio(e));
    } catch (e) {
      return UpdateCheckResult.error('$e');
    }
  }

  /// 纯函数：atom 订阅结果 → 更新判定（与 [evaluate] 相同的比较规则）。
  static UpdateCheckResult fromFeed(FeedRelease feed, AppVersion? current) {
    final latest = AppVersion.parse(feed.tagName);
    if (feed.tagName.isEmpty || latest == null) {
      return UpdateCheckResult.error('无法解析版本号 ${feed.tagName}');
    }
    if (current == null) {
      return UpdateCheckResult.error('无法读取当前版本');
    }
    if (latest.compareTo(current) <= 0) {
      return UpdateCheckResult.upToDate(current: current, latest: latest);
    }
    final a = feed.asset;
    final asset = a == null ? null : ReleaseAsset(a.name, a.url, a.size);
    return UpdateCheckResult(
      status: UpdateStatus.available,
      current: current,
      latest: latest,
      release: ReleaseInfo(
        tagName: feed.tagName,
        name: feed.tagName,
        changelog: feed.changelog,
        assets: [if (asset != null) asset],
      ),
      asset: asset,
    );
  }

  /// 纯函数：Release JSON → 更新判定。抽出来是为了能离线单测版本比较与选包。
  static UpdateCheckResult evaluate(
    Map<String, dynamic> releaseJson, {
    AppVersion? current,
    String? abiHint,
  }) {
    final release = ReleaseInfo.fromJson(releaseJson);
    final latest = release.version;
    if (latest == null || release.tagName.isEmpty) {
      return UpdateCheckResult.error('无法解析版本号 ${release.tagName}');
    }
    if (current == null) {
      // 没有比较基准就判不了，宁可不提示，也别在启动时弹一个假的「有新版」
      return UpdateCheckResult.error('无法读取当前版本');
    }
    if (latest.compareTo(current) <= 0) {
      return UpdateCheckResult.upToDate(current: current, latest: latest);
    }
    return UpdateCheckResult(
      status: UpdateStatus.available,
      current: current,
      latest: latest,
      release: release,
      asset: pickAsset(release.assets, abiHint: abiHint),
    );
  }

  /// 按设备 ABI 选包：优先匹配本架构的 release 包，退到 arm64 → armv7，
  /// 再退到任意 APK（含 debug/universal）。找不到就返回 null，由 UI 引导去
  /// Release 页面手动下载。
  static ReleaseAsset? pickAsset(List<ReleaseAsset> assets, {String? abiHint}) {
    final candidates = <String>[
      if (abiHint != null && abiHint.isNotEmpty) abiHint,
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
    ];
    for (final abi in candidates) {
      for (final a in assets) {
        if (!a.name.toLowerCase().endsWith('.apk')) continue;
        if (a.name.contains(abi)) return a;
      }
    }
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith('.apk')) return a;
    }
    return null;
  }

  /// 设备主 ABI（供 [pickAsset] 用）。拿不到返回 null，走默认顺序。
  static Future<String?> deviceAbi() async {
    try {
      if (!Platform.isAndroid) return null;
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis;
      if (abis.isEmpty) return null;
      // 首个即系统优先选择的 ABI（通常 arm64-v8a），直接喂给 pickAsset 匹配
      return abis.first;
    } catch (_) {
      return null;
    }
  }

  /// 下载 APK：直连失败依次尝试加速前缀。返回落盘路径。
  ///
  /// 校验：文件大小与 Release 元数据一致才算成功（半截包直接删掉）。
  static Future<DownloadedApk> download(
    ReleaseAsset asset,
    void Function(int received, int total) onProgress, {
    CancelToken? cancelToken,
  }) async {
    final dir = await _downloadDir();
    final target = File('${dir.path}${Platform.pathSeparator}${asset.name}');
    if (await target.exists()) await target.delete();

    final urls = [asset.url, for (final m in mirrors) '$m${asset.url}'];
    Object? lastError;
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      try {
        await _dio.download(
          url,
          target.path,
          cancelToken: cancelToken,
          onReceiveProgress: onProgress,
          options: Options(
            // 前缀式代理会 302 回源，必须允许重定向
            followRedirects: true,
            receiveTimeout: const Duration(minutes: 10),
          ),
        );
        final size = await target.length();
        if (asset.size > 0 && size != asset.size) {
          await target.delete();
          lastError = '文件不完整($size/${asset.size})';
          continue;
        }
        return DownloadedApk(
          file: target,
          viaMirror: i > 0,
          sourceUrl: url,
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        lastError = _describeDio(e);
        await target.delete();
      } catch (e) {
        lastError = e;
        if (await target.exists()) await target.delete();
      }
    }
    return DownloadedApk.failed('$lastError', sourceUrl: asset.url);
  }

  static Future<Directory> _downloadDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}xso-update');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 清掉历史下载，避免缓存目录堆积几百 MB 安装包。
  static Future<void> cleanDownloads() async {
    try {
      final dir = await _downloadDir();
      if (!await dir.exists()) return;
      await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ---- 节流与「跳过此版本」 ----

  static Future<bool> shouldAutoCheck() async {
    final p = await SharedPreferences.getInstance();
    final last = p.getInt(_kLastCheckAt) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - last >
        autoCheckInterval.inMilliseconds;
  }

  static Future<void> markChecked() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastCheckAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> isSkipped(String tagName) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kSkippedVersion) == tagName;
  }

  static Future<void> skipVersion(String tagName) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSkippedVersion, tagName);
  }

  /// 启动期静默检查：只有「未跳过 + 距上次检查超过 24h + 确实有新版」才返回
  /// 结果；网络失败/解析失败一律返回 null（不打扰用户）。
  static Future<UpdateCheckResult?> startupCheck({String? abiHint}) async {
    if (!await shouldAutoCheck()) return null;
    await markChecked();
    final res = await check(abiHint: abiHint);
    if (res.status != UpdateStatus.available) return null;
    final tag = res.release?.tagName;
    if (tag != null && await isSkipped(tag)) return null;
    return res;
  }

  static String _describeDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 403 || code == 429) return '访问太频繁，稍后再试（未登录的频率上限）';
        if (code == 404) return '还没有发布过版本';
        return '服务返回 $code';
      case DioExceptionType.cancel:
        return '已取消';
      default:
        return '网络不可达(${e.type.name})';
    }
  }
}

/// 语义化版本 + 构建号（`0.1.0+6`）。缺段按 0 补齐，非数字段截断。
@immutable
class AppVersion implements Comparable<AppVersion> {
  final List<int> parts;
  final int build;
  final String raw;

  const AppVersion(this.parts, this.build, this.raw);

  /// 解析 `v0.1.0+6` / `0.1.0` 等写法；版本段必须是 `数字(.数字)*`，
  /// 否则返回 null（避免把 nightly/滚动标签误判成 0.0.0 而静默不更新）。
  static AppVersion? parse(String input) {
    var s = input.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    if (s.isEmpty) return null;
    // 构建号支持 `+7`（pubspec 写法，也是本项目 tag 约定）与 `-7` 两种分隔
    final m = RegExp(r'^(.+)[+-](\d+)$').firstMatch(s);
    final verPart = m?.group(1) ?? s;
    final build = int.tryParse(m?.group(2) ?? '') ?? 0;
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(verPart)) return null;
    final nums = verPart.split('.').map(int.parse).toList();
    return AppVersion(nums, build, input.trim());
  }

  /// 展示用：优先原样，否则拼回。
  String get display {
    final v = parts.join('.');
    return build > 0 ? '$v+$build' : v;
  }

  @override
  int compareTo(AppVersion other) {
    final n = parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var i = 0; i < n; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return build.compareTo(other.build);
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      ListEqualityInt.equals(other.parts, parts) &&
      other.build == build;

  @override
  int get hashCode => Object.hash(ListEqualityInt.hashOf(parts), build);

  @override
  String toString() => raw;
}

/// 极小的 `List<int>` 相等工具，避免为一次比较再拉 collection 依赖。
class ListEqualityInt {
  static bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int hashOf(List<int> l) {
    var h = 0;
    for (final e in l) {
      h = h * 31 + e;
    }
    return h;
  }
}

enum UpdateStatus { available, upToDate, failed }

class ReleaseAsset {
  final String name;
  final String url;
  final int size;
  const ReleaseAsset(this.name, this.url, this.size);

  static ReleaseAsset fromJson(Map<String, dynamic> j) => ReleaseAsset(
        j['name'] as String? ?? '',
        j['browser_download_url'] as String? ?? '',
        (j['size'] as num?)?.toInt() ?? 0,
      );
}

class ReleaseInfo {
  final String tagName;
  final String name;
  final String changelog;
  final List<ReleaseAsset> assets;
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.changelog,
    required this.assets,
  });

  AppVersion? get version => AppVersion.parse(tagName);

  String get pageUrl =>
      'https://github.com/${UpdateService.owner}/${UpdateService.repo}/releases/tag/'
      '${Uri.encodeComponent(tagName)}';

  static ReleaseInfo fromJson(Map<String, dynamic> j) {
    final list = (j['assets'] as List?) ?? const [];
    return ReleaseInfo(
      tagName: j['tag_name'] as String? ?? '',
      name: j['name'] as String? ?? (j['tag_name'] as String? ?? ''),
      changelog: j['body'] as String? ?? '',
      assets: [
        for (final a in list)
          if (a is Map) ReleaseAsset.fromJson(Map<String, dynamic>.from(a)),
      ],
    );
  }
}

class DownloadedApk {
  final File? file;
  final bool viaMirror;
  final String? error;

  /// 本次实际使用的下载地址：成功时可能是镜像地址，失败时是 GitHub 直链，
  /// 供「复制地址」按钮交给浏览器/下载工具。
  final String sourceUrl;

  DownloadedApk({
    required File this.file,
    required this.viaMirror,
    required this.sourceUrl,
  }) : error = null;

  DownloadedApk.failed(this.error, {required this.sourceUrl})
      : file = null,
        viaMirror = false;

  bool get ok => file != null;
}

class UpdateCheckResult {
  final UpdateStatus status;
  final AppVersion? current;
  final AppVersion? latest;
  final ReleaseInfo? release;
  final ReleaseAsset? asset;
  final String? error;

  const UpdateCheckResult({
    required this.status,
    this.current,
    this.latest,
    this.release,
    this.asset,
    this.error,
  });

  UpdateCheckResult.upToDate({required AppVersion this.current, required AppVersion this.latest})
      : status = UpdateStatus.upToDate,
        release = null,
        asset = null,
        error = null;

  UpdateCheckResult.error(this.error)
      : status = UpdateStatus.failed,
        current = null,
        latest = null,
        release = null,
        asset = null;

  bool get hasUpdate => status == UpdateStatus.available;
}
