import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:pointycastle/export.dart' as pc;
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
  final Map<String, String> _assetCache = {};
  Dio? _dio;
  bool _bridgeInstalled = false;
  Completer<void>? _cryptoReady;
  StorageLoad? _storageLoad;
  StorageWrite? _storageWrite;

  /// 内置 JS 库：name → asset 路径（懒注入给插件 require）
  static const _jsLibAssets = {
    'cryptojs': 'assets/js/cryptojs.min.js',
    'dayjs': 'assets/js/dayjs.min.js',
    'qs': 'assets/js/qs.js',
    'he': 'assets/js/he.js',
    'cheerio': 'assets/js/cheerio.min.js',
    'big-integer': 'assets/js/biginteger.min.js',
  };

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

    // 同步 crypto 通道：RSA 等纯 Dart 运算，sendMessage 返回值直接回 JS
    _rt.onMessage('hostCrypto', (dynamic args) {
      try {
        final list = args as List;
        final op = list[0]?.toString() ?? '';
        switch (op) {
          case 'rsaEncrypt':
            return {
              'ok': true,
              'data': rsaEncryptPem(list[1].toString(), list[2].toString()),
            };
          default:
            return {'ok': false, 'error': '未知 crypto 操作: $op'};
        }
      } catch (e) {
        return {'ok': false, 'error': e.toString()};
      }
    });

    // 同步资产通道：插件 require 内置库时取库源码（预载于 _ensureCrypto）
    _rt.onMessage('hostAsset', (dynamic args) {
      final name = (args is List ? args.first : args)?.toString() ?? '';
      return _assetCache[name];
    });

    // 同步存储通道：插件 env.storage 持久化（登录态需跨重启保留）
    _rt.onMessage('hostStorage', (dynamic args) {
      try {
        final list = args is List ? args : <Object?>[args];
        final op = list[0]?.toString() ?? '';
        final ns = (list.length > 1 ? list[1]?.toString() : null) ?? 'default';
        switch (op) {
          case 'load':
            return _storageLoad?.call(ns);
          case 'set':
            _storageWrite
                ?.call(ns, list[2]?.toString(), list.length > 3 ? list[3]?.toString() : null);
            return true;
          case 'del':
            _storageWrite?.call(ns, list[2]?.toString(), null);
            return true;
          case 'clear':
            _storageWrite?.call(ns, null, null);
            return true;
        }
        return null;
      } catch (e) {
        _log('hostStorage error: $e');
        return null;
      }
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
        },
        rsaEncrypt: function(pubkey, data) {
          var r = sendMessage('hostCrypto', JSON.stringify(['rsaEncrypt', String(pubkey), String(data)]));
          var o = JSON.parse(r);
          if (!o || !o.ok) throw new Error((o && o.error) || 'rsa 失败');
          return o.data;
        }
      };
      1
    ''');
  }

  /// 预载内置 JS 库源码 + 注入 CryptoJS 全局。evaluate() 前必须完成。
  Future<void> _ensureCrypto() {
    return (_cryptoReady ??= Completer<void>()..complete(_injectCrypto()))
        .future;
  }

  Future<void> _injectCrypto() async {
    try {
      for (final entry in _jsLibAssets.entries) {
        _assetCache[entry.key] = await rootBundle.loadString(entry.value);
      }
      final src = _assetCache['cryptojs'];
      if (src == null) return;
      _rt.evaluate('''
        globalThis.CryptoJS = (function(){
          var module = { exports: {} };
          var exports = module.exports;
          var define = undefined;
          $src
          return module.exports && Object.keys(module.exports).length
              ? module.exports : globalThis.CryptoJS;
        })();
        1
      ''');
    } catch (e) {
      _log('内置 JS 库注入失败: $e');
    }
  }

  /// RSA PKCS#1 v1.5 加密，pubkey 支持 PKCS#1/PKCS#8 PEM 或裸 base64。
  static String rsaEncryptPem(String pubkey, String plain) {
    var b64 = pubkey.trim().replaceAll(RegExp(r'-----[^\-]+-----'), '');
    b64 = b64.replaceAll(RegExp(r'\s'), '');
    final bytes = base64.decode(b64);
    final top = ASN1Parser(bytes).nextObject();
    if (top is! ASN1Sequence) {
      throw const FormatException('RSA 公钥格式无法解析');
    }
    ASN1Sequence seq;
    final first = top.elements.first;
    if (first is ASN1Sequence) {
      // PKCS#8: SEQ( INT 0, SEQ(OID,NULL), OCTET STRING(pkcs1) )
      final octet = top.elements[2] as ASN1OctetString;
      seq = ASN1Parser(octet.valueBytes()).nextObject() as ASN1Sequence;
    } else {
      seq = top; // PKCS#1: SEQ( INT modulus, INT exponent )
    }
    final modulus = _asn1ToBigInt(seq.elements[0] as ASN1Integer);
    final exponent = _asn1ToBigInt(seq.elements[1] as ASN1Integer);
    final cipher = pc.PKCS1Encoding(pc.RSAEngine())
      ..init(
          true,
          pc.PublicKeyParameter<pc.RSAPublicKey>(
              pc.RSAPublicKey(modulus, exponent)));
    final out = cipher.process(Uint8List.fromList(utf8.encode(plain)));
    return base64.encode(out);
  }

  /// ASN1 INTEGER → BigInt（容忍前导 0x00）
  static BigInt _asn1ToBigInt(ASN1Integer e) {
    final b = e.valueBytes();
    if (b.isEmpty) return BigInt.zero;
    final hexStr = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return BigInt.parse(hexStr, radix: 16);
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
    final binary = opts['binary'] == true;
    _log('[HTTP] --> $method $url');
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
      if (binary) {
        // 二进制响应（加密协议等）：按 latin1 还原为字节串，JS 侧 charCodeAt 无损取字节
        final resp = await dio.request<List<int>>(
          url,
          options: Options(
              method: method,
              headers: headers,
              responseType: ResponseType.bytes),
          data: opts['body'] ?? opts['data'],
        );
        final body = latin1.decode(resp.data ?? const []);
        _log('[HTTP] <-- ${resp.statusCode} $url len=${body.length} (binary)');
        return {'status': resp.statusCode ?? 0, 'data': body};
      }
      final resp = await dio.request<String>(
        url,
        options: Options(method: method, headers: headers),
        data: opts['body'] ?? opts['data'],
      );
      final body = resp.data ?? '';
      _log('[HTTP] <-- ${resp.statusCode} $url len=${body.length}');
      return {'status': resp.statusCode ?? 0, 'data': body};
    } catch (e) {
      _log('[HTTP] <-- ERR $url $e');
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
    await _ensureCrypto();
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
  void registerStorage(StorageLoad load, StorageWrite save) {
    _storageLoad = load;
    _storageWrite = save;
  }

  @override
  void dispose() => _rt.dispose();
}
