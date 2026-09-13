import 'dart:convert';
import 'dart:typed_data';

// bencode 分隔符
const int _tInt = 0x69; // i
const int _tList = 0x6C; // l
const int _tDict = 0x64; // d
const int _tEnd = 0x65; // e
const int _tSep = 0x3A; // :

/// KRPC（BitTorrent DHT）用到最小 bencode 编解码。
///
/// 只支持 dict / list / int / bytestring 四种类型。自己实现而不引第三方包，
/// 一是依赖更少，二是避免 pub 拉取在国内网络下的不确定性。
///
/// 字节串统一用 [Uint8List] 表示；列表用 [List]。
/// 注意 [Uint8List] 本身也是 [List<int>]，所有分支判断里必须**先判 Uint8List**。
class Bencode {
  Bencode._();

  static Uint8List encode(Object? value) {
    final out = <int>[];
    _write(value, out);
    return Uint8List.fromList(out);
  }

  static void _write(Object? value, List<int> out) {
    if (value == null) return;
    if (value is Uint8List) {
      // 字节串：长度:内容（二进制安全，node id / peer 紧凑格式都走这里）
      out.addAll(value.length.toString().codeUnits);
      out.add(_tSep);
      out.addAll(value);
    } else if (value is int) {
      out.add(_tInt);
      out.addAll(value.toString().codeUnits);
      out.add(_tEnd);
    } else if (value is String) {
      final bytes = utf8.encode(value);
      out.addAll(bytes.length.toString().codeUnits);
      out.add(_tSep);
      out.addAll(bytes);
    } else if (value is List) {
      out.add(_tList);
      for (final e in value) {
        _write(e, out);
      }
      out.add(_tEnd);
    } else if (value is Map) {
      out.add(_tDict);
      // bencode 要求 dict 的 key 按原始字节序升序排列
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      for (final k in keys) {
        _write(k, out);
        _write(value[k], out);
      }
      out.add(_tEnd);
    } else {
      throw ArgumentError('bencode 不支持的类型: ${value.runtimeType}');
    }
  }

  /// 解码。返回 Map / List / int / Uint8List。
  /// dict 的 key 按 utf8 解码（DHT 协议的 key 都是 ASCII 文本）。
  static Object? decode(Uint8List data) => _Reader(data).read();

  /// 便捷：把可能是字节串的值转成十六进制字符串
  static String? hexOf(Object? v) {
    if (v is Uint8List) {
      return v.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }
    if (v is String) return v;
    return null;
  }
}

class _Reader {
  final Uint8List _d;
  int _p = 0;

  _Reader(this._d);

  Object? read() {
    if (_p >= _d.length) return null;
    final c = _d[_p];
    if (c == _tInt) return _readInt();
    if (c == _tList) return _readList();
    if (c == _tDict) return _readDict();
    return _readBytes();
  }

  int _readInt() {
    _p++; // i
    final start = _p;
    while (_p < _d.length && _d[_p] != _tEnd) {
      _p++;
    }
    final s = String.fromCharCodes(_d.sublist(start, _p));
    _p++; // e
    return int.tryParse(s) ?? 0;
  }

  Uint8List _readBytes() {
    final start = _p;
    while (_p < _d.length && _d[_p] != _tSep) {
      _p++;
    }
    final len = int.tryParse(String.fromCharCodes(_d.sublist(start, _p))) ?? 0;
    _p++; // :
    final end = (_p + len).clamp(0, _d.length);
    final out = Uint8List.fromList(_d.sublist(_p, end));
    _p = end;
    return out;
  }

  List<Object?> _readList() {
    _p++; // l
    final out = <Object?>[];
    while (_p < _d.length && _d[_p] != _tEnd) {
      out.add(read());
    }
    _p++; // e
    return out;
  }

  Map<String, Object?> _readDict() {
    _p++; // d
    final out = <String, Object?>{};
    while (_p < _d.length && _d[_p] != _tEnd) {
      final k = _readBytes();
      out[utf8.decode(k, allowMalformed: true)] = read();
    }
    _p++; // e
    return out;
  }
}
