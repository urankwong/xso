import 'package:core/src/pan_detector.dart';

typedef PageFetcher = Future<String> Function(String url);

/// 网盘链接活性检测：HEAD/GET 探测 + 内置失效特征判定。
/// fetcher 由 app 层（dio）提供。
class LivenessChecker {
  final PageFetcher fetcher;
  LivenessChecker({required this.fetcher});

  /// 返回是否已失效
  Future<bool> check(String url) async {
    try {
      final page = await fetcher(url);
      final provider = providerOfUrl(url) ?? PanProvider.baidu;
      return isPanLinkDead(provider, page);
    } catch (_) {
      return true; // 网络失败保守视为失效，UI 提示可手动重检
    }
  }
}
