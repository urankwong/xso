/// JS 执行异常（脚本抛错、语法错误）
class JsEvaluationException implements Exception {
  final String message;
  JsEvaluationException(this.message);
  @override
  String toString() => 'JsEvaluationException: $message';
}

/// JS 执行超时（沙箱强制终止）
class JsTimeoutException implements Exception {
  final Duration limit;
  JsTimeoutException(this.limit);
  @override
  String toString() => 'JsTimeoutException: exceeded $limit';
}

/// JS 运行时抽象：source_engine 只依赖此接口，
/// flutter_js 的具体实现在 app 层注入（QuickJsRuntimeImpl）。
abstract class JsRuntime {
  /// 执行脚本，返回最后表达式/返回值的字符串形式。
  /// [timeout] 超时强制终止，防恶意/死循环源。
  Future<String> evaluate(String script, {Duration? timeout});

  /// 注册宿主函数（Dart 侧暴露给 JS 的 API，如 fetch）。
  void registerHostFunction(String name, HostFunction fn);

  /// 销毁运行时，释放资源。
  void dispose();
}

/// 宿主函数：JS 调用 → Dart 处理 → 返回值序列化回 JS
typedef HostFunction = Future<Object?> Function(List<Object?> args);
