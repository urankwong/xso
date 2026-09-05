import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:source_engine/source_engine.dart';

/// flutter_js → JsRuntime 适配实现（app 层注入引擎）。
///
/// flutter_js 的 QuickJS 是同步引擎：JS→Dart 的 sendMessage 通道是同步的，
/// Dart→JS 的回调靠重新 evaluate。异步网络协议（与 source_engine 适配器的
/// __jsHost 约定配套）：
/// 1. JS 调 __jsHost.request(opts)：登记 pending[id]，经同步通道 'hostRequest'
///    把 [id, opts] 交给 Dart；
/// 2. Dart 用 dio 异步请求，完成后 evaluate('__jsHost.httpDone(id, payload)')
///    写回结果并 drain promise job 队列；
/// 3. JS 侧 axios 的 promise 由 setTimeout 轮询 pending 表恢复。
class QuickJsRuntimeImpl implements JsRuntime {
  final JavascriptRuntime _rt = getJavascriptRuntime();
  final Map<String, HostFunction> _hostFns = {};
  Dio? _dio;
  bool _bridgeInstalled = false;

  QuickJsRuntimeImpl({Dio? dio}) : _dio = dio;

  void _installBridge() {
    if (_bridgeInstalled) return;
    _bridgeInstalled = true;

    // 异步请求通道：args = [id, opts]
    _rt.onMessage('hostRequest', (dynamic args) {
      try {
        final list = args as List;
        final id = list[0];
        final opts = (list[1] as Map?) ?? {};
        _doHttp(id, opts);
      } catch (e) {
        _log('hostRequest handler error: $e');
      }
      return null; // 异步结果稍后经 httpDone 写回
    });

    // JS 侧异步桥：pending 表 + promise 轮询恢复
    _rt.evaluate(r'''
      globalThis.__jsHost = {
        seq: 0,
        pending: {},
        request: function(opts) {
          var id = ++this.seq;
          this.pending[id] = { done: false, payload: null };
          sendMessage('hostRequest', JSON.stringify([id, opts || {}]));
          var self = this;
          return new Promise(function(resolve, reject) {
            var tries = 0;
            function poll() {
              var p = self.pending[id];
              if (p && p.done) {
                delete self.pending[id];
                if (p.payload && p.payload.error) reject(new Error(p.payload.error));
                else resolve(p.payload);
                return;
              }
              if (++tries > 1200) { reject(new Error('host request timeout')); return; }
              setTimeout(poll, 25);
            }
            setTimeout(poll, 25);
          });
        },
        httpDone: function(id, payload) {
          var p = this.pending[id];
          if (p) { p.done = true; p.payload = payload; }
        }
      };
      1
    ''');
  }

  Future<void> _doHttp(dynamic id, Map opts) async {
    final payload = await _executeHttp(opts);
    // 写回 JS：httpDone 设置 pending 表，drain 后 promise 轮询恢复
    _rt.evaluate('__jsHost.httpDone($id, ${jsonEncode(payload)}); 1');
    try {
      _rt.executePendingJob();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _executeHttp(Map opts) async {
    final url = opts['url']?.toString() ?? '';
    final method = (opts['method'] ?? 'GET').toString().toUpperCase();
    final headers = <String, String>{};
    ((opts['headers'] ?? opts['header']) as Map?)
        ?.forEach((k, v) => headers[k.toString()] = v.toString());
    try {
      final dio = _dio ??= Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        },
      ));
      final resp = await dio.request<String>(
        url,
        options: Options(method: method, headers: headers),
        data: opts['body'] ?? opts['data'],
      );
      return {'status': resp.statusCode ?? 0, 'data': resp.data ?? ''};
    } catch (e) {
      return {'status': 0, 'data': '', 'error': e.toString()};
    }
  }

  void _log(String msg) {
    assert(() {
      // ignore: avoid_print
      print('[QuickJsRuntime] $msg');
      return true;
    }());
  }

  @override
  Future<String> evaluate(String script, {Duration? timeout}) async {
    _installBridge();
    final result = _rt.evaluate(script);
    // drain promise 微任务（setTimeout 回调链等）
    try {
      _rt.executePendingJob();
    } catch (_) {}
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
