import 'dart:convert' show jsonDecode;

enum SourceFormat { own, musicfree, lx, legado }

class SourceFormatException implements Exception {
  final String message;
  SourceFormatException(this.message);
  @override
  String toString() => 'SourceFormatException: $message';
}

/// 格式检测顺序：先试 JSON（自有/Legado），再试 JS（MusicFree/洛雪）
SourceFormat detectSourceFormat(String raw) {
  final trimmed = raw.trim();

  // JSON 类
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {}
    if (json != null) {
      if (json.containsKey('bookSourceUrl') || json.containsKey('ruleSearch')) {
        return SourceFormat.legado;
      }
      if (json.containsKey('meta') && json.containsKey('search')) {
        return SourceFormat.own;
      }
    }
    throw SourceFormatException('JSON 格式但既非自有源也非 Legado 源');
  }

  // JS 类
  if (trimmed.contains('module.exports') &&
      (trimmed.contains('search') || trimmed.contains('platform'))) {
    return SourceFormat.musicfree;
  }
  if (trimmed.contains('ENVIRONMENT') ||
      trimmed.contains('lx.') ||
      trimmed.contains('globalThis.lx')) {
    return SourceFormat.lx;
  }

  throw SourceFormatException('无法识别的源格式');
}
