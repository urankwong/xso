import 'dart:async';
import 'js_runtime.dart';

/// 测试用假运行时：不执行真 JS，
/// 只按"预置脚本表"返回结果，验证引擎对运行时的调用契约。
class FakeJsRuntime implements JsRuntime {
  final Map<String, String> _scriptResults;
  final List<String> callLog = [];
  final Map<String, HostFunction> _hostFns = {};

  FakeJsRuntime({Map<String, String> scriptResults = const {}})
      : _scriptResults = scriptResults;

  @override
  Future<String> evaluate(String script, {Duration? timeout}) async {
    final limit = timeout ?? const Duration(seconds: 5);
    callLog.add(script);
    if (script.contains('while(true)')) {
      await Future<void>.delayed(limit + const Duration(milliseconds: 10));
      throw JsTimeoutException(limit);
    }
    if (script.trimLeft().startsWith('throw new Error')) {
      throw JsEvaluationException('boom');
    }
    if (_scriptResults.containsKey(script)) {
      return _scriptResults[script]!;
    }
    // parse 钩子场景：脚本以 (function(body){ 开头，预置 key 匹配钩子体
    for (final key in _scriptResults.keys) {
      if (script.contains(key)) return _scriptResults[key]!;
    }
    return 'null';
  }

  @override
  void registerHostFunction(String name, HostFunction fn) {
    _hostFns[name] = fn;
  }

  /// 测试辅助：直接触发已注册的宿主函数
  Future<Object?> invokeHost(String name, List<Object?> args) =>
      _hostFns[name]!(args);

  @override
  void dispose() {}
}
