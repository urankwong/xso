import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题持久化 key
const _kThemeMode = 'themeMode';

/// 主题模式状态：默认跟随系统，用户选择后持久化到 SharedPreferences
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  bool _pending = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // 加载期间用户已手动设置过则以用户设置为准
    if (_pending) return;
    state = _fromKey(prefs.getString(_kThemeMode));
  }

  /// 切换主题模式并落盘
  Future<void> set(ThemeMode mode) async {
    _pending = true;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, _keyOf(mode));
  }

  static ThemeMode _fromKey(String? key) => switch (key) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _keyOf(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      };

  /// 当前模式的中文名（"我的"页副标题用）
  static String label(ThemeMode mode) => switch (mode) {
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
        _ => '跟随系统',
      };
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
        (ref) => ThemeModeNotifier());

/// 双主题设计系统：浅色 seed teal 0xFF00897B，深色 seed 0xFF2BD4B4
class AppTheme {
  AppTheme._();

  static ThemeData light() =>
      _build(Brightness.light, const Color(0xFF00897B));

  static ThemeData dark() => _build(Brightness.dark, const Color(0xFF2BD4B4));

  static ThemeData _build(Brightness brightness, Color seed) {
    var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    if (brightness == Brightness.dark) {
      // 深色统一走深灰 #141518 系
      scheme = scheme.copyWith(
        surface: const Color(0xFF141518),
        surfaceContainerLowest: const Color(0xFF101114),
        surfaceContainerLow: const Color(0xFF191A1E),
        surfaceContainer: const Color(0xFF1E1F23),
        surfaceContainerHigh: const Color(0xFF24262A),
        surfaceContainerHighest: const Color(0xFF2E3033),
      );
    }
    final dark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF141518) : scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
      ),
      // 统一形状语言：卡片圆角 16
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      ),
      // 输入框胶囊圆角 22
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      // Chip 圆角 16
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        showCheckmark: false,
      ),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: DividerThemeData(
          color: scheme.outlineVariant.withValues(alpha: 0.5)),
    );
  }
}
