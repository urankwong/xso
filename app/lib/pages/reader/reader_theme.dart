import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读主题色卡（对标主流阅读软件：纸白/羊皮/护眼绿/浅灰蓝/暗夜/纯黑）
class ReaderPalette {
  final String id;
  final String label;
  final Color background;
  final Color text;
  final Color secondary;
  final Color accent;

  /// 深色卡：沉浸模式下状态栏图标用浅色
  final bool isDark;

  const ReaderPalette({
    required this.id,
    required this.label,
    required this.background,
    required this.text,
    required this.secondary,
    required this.accent,
    required this.isDark,
  });
}

const kReaderPalettes = <ReaderPalette>[
  ReaderPalette(
    id: 'paper',
    label: '纸白',
    background: Color(0xFFFAF6F0),
    text: Color(0xFF2C2A26),
    secondary: Color(0xFF8A857C),
    accent: Color(0xFFB07B4F),
    isDark: false,
  ),
  ReaderPalette(
    id: 'parchment',
    label: '羊皮',
    background: Color(0xFFF2E8D5),
    text: Color(0xFF4A3B28),
    secondary: Color(0xFF96866B),
    accent: Color(0xFF9C6B3F),
    isDark: false,
  ),
  ReaderPalette(
    id: 'green',
    label: '护眼',
    background: Color(0xFFE3EDE0),
    text: Color(0xFF2B3A2E),
    secondary: Color(0xFF7C8B7E),
    accent: Color(0xFF4F7A55),
    isDark: false,
  ),
  ReaderPalette(
    id: 'gray',
    label: '浅灰',
    background: Color(0xFFEAECEF),
    text: Color(0xFF33373C),
    secondary: Color(0xFF878D94),
    accent: Color(0xFF4C6E91),
    isDark: false,
  ),
  ReaderPalette(
    id: 'night',
    label: '暗夜',
    background: Color(0xFF1E2226),
    text: Color(0xFFB4BAC2),
    secondary: Color(0xFF6B727B),
    accent: Color(0xFF6E93B8),
    isDark: true,
  ),
  ReaderPalette(
    id: 'oled',
    label: '纯黑',
    background: Color(0xFF000000),
    text: Color(0xFF9AA0A8),
    secondary: Color(0xFF565B62),
    accent: Color(0xFF5B7E9E),
    isDark: true,
  ),
];

/// 翻页方式
enum ReaderPageMode { scroll, page }

/// 阅读设置（持久化到 SharedPreferences）。
///
/// 兼容旧版键：`reader_font_size`/`reader_night` 有值时做一次性迁移，
/// 避免升级后用户已调好的字号/夜间态丢失。
class ReaderSettings {
  static const _kFontSize = 'reader.fontSize';
  static const _kLineHeight = 'reader.lineHeight';
  static const _kBold = 'reader.bold';
  static const _kMode = 'reader.mode';
  static const _kPalette = 'reader.palette';
  static const _kBrightness = 'reader.brightness';
  static const _kLegacyFontSize = 'reader_font_size';
  static const _kLegacyNight = 'reader_night';

  /// 字号范围（主流阅读软件普遍 14~28）
  static const fontSizeMin = 14.0;
  static const fontSizeMax = 28.0;

  final double fontSize;

  /// 行距倍数：1.4 紧凑 / 1.7 标准 / 2.0 宽松
  final double lineHeight;
  final bool bold;
  final ReaderPageMode mode;
  final int paletteIndex;

  /// 内容层亮度 0.3~1.0：以减光蒙层近似系统亮度调节（零插件依赖）
  final double brightness;

  const ReaderSettings({
    this.fontSize = 18,
    this.lineHeight = 1.7,
    this.bold = false,
    this.mode = ReaderPageMode.scroll,
    this.paletteIndex = 0,
    this.brightness = 1.0,
  });

  ReaderPalette get palette =>
      kReaderPalettes[paletteIndex.clamp(0, kReaderPalettes.length - 1)];

  /// 减光蒙层透明度（brightness=1 时不加蒙层）
  double get dimAmount => (1 - brightness) * 0.6;

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    bool? bold,
    ReaderPageMode? mode,
    int? paletteIndex,
    double? brightness,
  }) =>
      ReaderSettings(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        bold: bold ?? this.bold,
        mode: mode ?? this.mode,
        paletteIndex: paletteIndex ?? this.paletteIndex,
        brightness: brightness ?? this.brightness,
      );

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kFontSize, fontSize);
    await p.setDouble(_kLineHeight, lineHeight);
    await p.setBool(_kBold, bold);
    await p.setString(_kMode, mode.name);
    await p.setInt(_kPalette, paletteIndex);
    await p.setDouble(_kBrightness, brightness);
  }

  static Future<ReaderSettings> load() async {
    final p = await SharedPreferences.getInstance();
    var fontSize = p.getDouble(_kFontSize);
    if (fontSize == null) {
      // 旧版迁移：reader_font_size（字号）/ reader_night（夜间→暗夜卡）
      final legacy = p.getDouble(_kLegacyFontSize);
      fontSize = legacy ?? 18;
      final wasNight = p.getBool(_kLegacyNight) ?? false;
      return ReaderSettings(
        fontSize: fontSize.clamp(fontSizeMin, fontSizeMax),
        paletteIndex: wasNight ? 4 : 0,
      );
    }
    final modeName = p.getString(_kMode);
    return ReaderSettings(
      fontSize: (p.getDouble(_kFontSize) ?? 18)
          .clamp(fontSizeMin, fontSizeMax),
      lineHeight: p.getDouble(_kLineHeight) ?? 1.7,
      bold: p.getBool(_kBold) ?? false,
      mode: modeName == 'page' ? ReaderPageMode.page : ReaderPageMode.scroll,
      paletteIndex: p.getInt(_kPalette) ?? 0,
      brightness: p.getDouble(_kBrightness) ?? 1.0,
    );
  }
}