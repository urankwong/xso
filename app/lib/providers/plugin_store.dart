import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 插件持久化仓库：
/// - env.storage：按命名空间（源 id）存一份 KV，供插件保存登录态/Cookie
/// - userVariables：按源 id 存用户变量（如 B站 Cookie），装配时注入插件
///
/// 通道是同步的（flutter_js sendMessage），因此启动时把全部数据载入内存，
/// 写入时同步更新内存 + 异步落盘。
class PluginStore {
  PluginStore(this._prefs);
  final SharedPreferences _prefs;

  static const _kStorage = 'plugin.storage.'; // + ns
  static const _kVars = 'plugin.vars.'; // + sourceId
  static const _kIndex = 'plugin.ns.index';

  final Map<String, Map<String, String>> _storage = {};
  final Map<String, Map<String, String>> _vars = {};

  /// 载入全部命名空间（须在首个 JS 运行时创建前完成）
  Future<void> load() async {
    final ns = (_prefs.getStringList(_kIndex) ?? const <String>[]).toSet();
    // 兼容历史键：扫描所有已存的 plugin.storage.*
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_kStorage)) ns.add(key.substring(_kStorage.length));
    }
    for (final name in ns) {
      final raw = _prefs.getString('$_kStorage$name');
      if (raw == null) continue;
      try {
        _storage[name] = (jsonDecode(raw) as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString()));
      } catch (_) {}
    }
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_kVars)) continue;
      final id = key.substring(_kVars.length);
      try {
        _vars[id] = (jsonDecode(_prefs.getString(key)!) as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString()));
      } catch (_) {}
    }
  }

  // ---------- env.storage ----------

  String? loadStorage(String ns) {
    final m = _storage[ns];
    return m == null ? null : jsonEncode(m);
  }

  void writeStorage(String ns, String? key, String? value) {
    final m = _storage.putIfAbsent(ns, () => <String, String>{});
    if (key == null) {
      m.clear();
    } else if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    final idx = (_prefs.getStringList(_kIndex) ?? const <String>[]).toSet()..add(ns);
    unawaited(_prefs.setStringList(_kIndex, idx.toList()));
    unawaited(_prefs.setString('$_kStorage$ns', jsonEncode(m)));
  }

  // ---------- 用户变量（Cookie 等） ----------

  Map<String, String> userVars(String sourceId) =>
      Map.unmodifiable(_vars[sourceId] ?? const {});

  Future<void> setUserVar(String sourceId, String key, String value) async {
    final m = _vars.putIfAbsent(sourceId, () => <String, String>{});
    if (value.isEmpty) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    await _prefs.setString('$_kVars$sourceId', jsonEncode(m));
  }

  Future<void> clearUserVars(String sourceId) async {
    _vars.remove(sourceId);
    await _prefs.remove('$_kVars$sourceId');
  }

  /// 该源是否已配置任一用户变量（用于列表显示"已登录/未登录"）
  bool hasUserVars(String sourceId) => (_vars[sourceId]?.isNotEmpty ?? false);
}

/// 启动时先 load 再暴露，避免同步通道读到空表
final pluginStoreProvider = FutureProvider<PluginStore>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final store = PluginStore(prefs);
  await store.load();
  return store;
});
