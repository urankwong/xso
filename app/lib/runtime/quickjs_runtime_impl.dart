import 'dart:async';
import 'package:flutter_js/flutter_js.dart';
import 'package:source_engine/source_engine.dart';

/// flutter_js → JsRuntime 适配实现（app 层注入引擎）。
class QuickJsRuntimeImpl implements JsRuntime {
  final JavascriptRuntime _rt = getJavascriptRuntime();
  final Map<String, HostFunction> _hostFns = {};
  bool _hostBridgeInstalled = false;

  QuickJsRuntimeImpl() {
    _rt.onMessage('hostCall', (dynamic args) {
      // JS 侧: __hostCall('name', [args...]) → 通道消息
      final list = args as List;
      final name = list[0] as String;
      final fnArgs = (list[1] as List).cast<Object?>();
      return _hostFns[name]!(fnArgs);
    });
  }

  void _installHostBridge() {
    if (_hostBridgeInstalled) return;
    _hostBridgeInstalled = true;
    _rt.evaluate('''
      globalThis.__hostFetch = function(opts) {
        var url = typeof opts === 'string' ? opts : opts.url;
        var method = (typeof opts === 'object' && opts.method) || 'GET';
        return __hostCall('fetch', [url, method]);
      };
    ''');
  }

  @override
  Future<String> evaluate(String script, {Duration? timeout}) async {
    _installHostBridge();
    final result = _rt.evaluate(script);
    if (result.isError) {
      throw JsEvaluationException(result.stringResult);
    }
    return result.stringResult;
  }

  @override
  void registerHostFunction(String name, HostFunction fn) {
    _hostFns[name] = fn;
  }

  @override
  void dispose() => _rt.dispose();
}
