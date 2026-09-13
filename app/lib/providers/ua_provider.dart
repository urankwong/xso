import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 预置 User-Agent。
///
/// 设计原则：**默认即可用，小白无需知道 UA 是什么。**
/// 反爬站点大多只校验 UA 是否像真实浏览器，内置两个常见取值即可覆盖
/// 绝大多数场景；"自定义"只作为高级选项，不暴露在默认路径上。
class UaPresets {
  /// 桌面 Chrome：小说站/影视站最通用（站点通常不会因移动端做重定向）
  static const desktop = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// 移动 Chrome：部分站点只服务移动端，或移动端页面结构更易解析
  static const mobile = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 '
      'Mobile Safari/537.36';

  static const defaultMode = UaMode.desktop;

  static String of(UaMode mode, String custom) {
    switch (mode) {
      case UaMode.mobile:
        return mobile;
      case UaMode.custom:
        return custom.trim().isEmpty ? desktop : custom.trim();
      case UaMode.desktop:
        return desktop;
    }
  }
}

enum UaMode { desktop, mobile, custom }

extension UaModeX on UaMode {
  String get label => switch (this) {
        UaMode.desktop => '桌面浏览器（推荐）',
        UaMode.mobile => '手机浏览器',
        UaMode.custom => '自定义',
      };
  String get key => name;
  static UaMode fromKey(String? k) => UaMode.values.firstWhere(
        (m) => m.name == k,
        orElse: () => UaPresets.defaultMode,
      );
}

/// 当前生效的 UA。设置页保存后 invalidate 即可立即生效（无需重启）。
final userAgentProvider = FutureProvider<String>((ref) async {
  final p = await SharedPreferences.getInstance();
  final modeKey = p.getString('uaMode');
  final custom = p.getString('ua') ?? '';
  // 兼容老数据：以前只有 ua、没有 uaMode，直接沿用旧值
  if (modeKey == null || modeKey.isEmpty) {
    return custom.trim().isEmpty
        ? UaPresets.of(UaPresets.defaultMode, '')
        : custom.trim();
  }
  return UaPresets.of(UaModeX.fromKey(modeKey), custom);
});

/// UA 模式（供设置页回显）
final uaModeProvider = FutureProvider<UaMode>((ref) async {
  final p = await SharedPreferences.getInstance();
  final k = p.getString('uaMode');
  if (k == null || k.isEmpty) {
    // 老数据：填过自定义值就按自定义回显
    final custom = p.getString('ua') ?? '';
    return custom.trim().isEmpty ? UaPresets.defaultMode : UaMode.custom;
  }
  return UaModeX.fromKey(k);
});
