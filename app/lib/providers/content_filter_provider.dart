import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 正文净化规则（用户自定义的"查找替换"）。
///
/// 站点广告五花八门且不断翻新，内置规则永远追不上；让用户自己加一条
/// 正则替换，才是这类问题的终局解法（对标 Legado 的「替换净化」）。
///
/// 规则对**所有源**生效，且在正文清洗之后应用 —— 用户写规则时面对的
/// 是"已经去过广告"的文本，不必考虑原始 HTML 结构。
class ContentFilterStore {
  static const _key = 'contentFilters';

  /// 读取规则列表。坏数据一律跳过，不让一条坏规则让设置页打不开。
  static Future<List<ContentFilterRule>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (ContentFilterRule.tryParse(e) case final r?) r,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<ContentFilterRule> rules) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode([for (final r in rules) r.toJson()]));
  }
}

/// 当前规则列表。设置页保存后 `ref.invalidate(contentFilterProvider)`
/// 即触发重建，引擎侧通过 listen 收到新值并立即生效（无需重启）。
final contentFilterProvider = FutureProvider<List<ContentFilterRule>>(
  (ref) => ContentFilterStore.load(),
);
