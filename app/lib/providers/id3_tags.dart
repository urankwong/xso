import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 纯 Dart ID3v2.3 读写（mp3 标签用）。
/// 背景：pub.dev 上 flutter_id3v2 / audio_tags 已下架，为避免引入 C 构建链，
/// 这里手写最小实现：读 TIT2/TPE1/TALB/TYER/USLT/APIC，写同名字段。
class Mp3Tags {
  String? title;
  String? artist;
  String? album;
  String? year;
  String? lyrics;
  Uint8List? cover;
  String coverMime;

  Mp3Tags({this.coverMime = 'image/jpeg'});

  bool get isEmpty =>
      (title ?? '').isEmpty &&
      (artist ?? '').isEmpty &&
      (album ?? '').isEmpty &&
      (year ?? '').isEmpty &&
      (lyrics ?? '').isEmpty &&
      cover == null;
}

/// synchsafe 整数（ID3v2 尺寸编码：每字节 7 位有效）
Uint8List _synchsafe4(int value) => Uint8List.fromList([
      (value >> 21) & 0x7F,
      (value >> 14) & 0x7F,
      (value >> 7) & 0x7F,
      value & 0x7F,
    ]);

int _readSynchsafe4(List<int> b) =>
    ((b[0] & 0x7F) << 21) | ((b[1] & 0x7F) << 14) | ((b[2] & 0x7F) << 7) | (b[3] & 0x7F);

int _readBe32(List<int> b) => (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];

/// UTF-16LE + BOM（ID3v2 编码 1，中文兼容性最好）
Uint8List _utf16(String s) {
  final out = BytesBuilder();
  out.add([0xFF, 0xFE]);
  for (final cu in s.codeUnits) {
    out.addByte(cu & 0xFF);
    out.addByte((cu >> 8) & 0xFF);
  }
  out.add([0, 0]); // v2.3 文本帧以 null 终止
  return out.toBytes();
}

String _decodeText(int encoding, List<int> bytes) {
  bool stop(Uint8List u) => u.length >= 2 && u[u.length - 2] == 0 && u[u.length - 1] == 0;
  switch (encoding) {
    case 0:
      return String.fromCharCodes(bytes).replaceAll(RegExp(r'\u0000+$'), '');
    case 1:
      var u = Uint8List.fromList(bytes);
      if (u.length >= 2 && u[0] == 0xFF && u[1] == 0xFE) {
        u = Uint8List.sublistView(u, 2);
        if (stop(u)) u = Uint8List.sublistView(u, 0, u.length - 2);
        return String.fromCharCodes(_utf16Le(u));
      }
      if (u.length >= 2 && u[0] == 0xFE && u[1] == 0xFF) {
        u = Uint8List.sublistView(u, 2);
        final units = <int>[];
        for (var i = 0; i + 1 < u.length; i += 2) {
          units.add((u[i] << 8) | u[i + 1]);
        }
        return String.fromCharCodes(units).replaceAll(RegExp(r'\u0000+$'), '');
      }
      return '';
    case 2:
      final units = <int>[];
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        units.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units).replaceAll(RegExp(r'\u0000+$'), '');
    default:
      return utf8.decode(bytes, allowMalformed: true).replaceAll(RegExp(r'\u0000+$'), '');
  }
}

List<int> _utf16Le(Uint8List u) {
  final units = <int>[];
  for (var i = 0; i + 1 < u.length; i += 2) {
    units.add(u[i] | (u[i + 1] << 8));
  }
  return units;
}

Uint8List _frame(String id, List<int> data) {
  assert(id.length == 4);
  final out = BytesBuilder();
  out.add(latin1.encode(id));
  out.add([
    (data.length >> 24) & 0xFF,
    (data.length >> 16) & 0xFF,
    (data.length >> 8) & 0xFF,
    data.length & 0xFF,
  ]);
  out.add([0, 0]); // flags
  out.add(data);
  return out.toBytes();
}

/// 从随机访问文件指定偏移读取至多 count 字节
Uint8List _readAt(RandomAccessFile raf, int offset, int count) {
  raf.setPositionSync(offset);
  final buf = Uint8List(count);
  var read = 0;
  while (read < count) {
    final n = raf.readIntoSync(buf, read, count);
    if (n <= 0) break;
    read += n;
  }
  return read == count ? buf : Uint8List.sublistView(buf, 0, read);
}

/// 读取文件头部 ID3v2 标签；无标签返回 null。
Mp3Tags? readMp3Tags(String path) {
  final raf = File(path).openSync(mode: FileMode.read);
  try {
    final head = _readAt(raf, 0, 10);
    if (head.length < 10 ||
        head[0] != 0x49 ||
        head[1] != 0x44 ||
        head[2] != 0x33) {
      return null;
    }
    final tagSize = _readSynchsafe4(head.sublist(6, 10));
    if (tagSize <= 0 || tagSize > 10 * 1024 * 1024) return null;
    final tag = _readAt(raf, 10, tagSize);
    return _parseTag(tag);
  } catch (_) {
    return null;
  } finally {
    raf.closeSync();
  }
}

Mp3Tags? _parseTag(Uint8List tag) {
  if (tag.length < 10) return null;
  final version = tag[3];
  if (version < 3) return null; // 只支持 v2.3/v2.4
  final tags = Mp3Tags();
  var pos = 0;
  while (pos + 10 <= tag.length) {
    final id = String.fromCharCodes(tag.sublist(pos, pos + 4));
    if (!RegExp(r'^[A-Z][A-Z0-9]{3}$').hasMatch(id)) break;
    final raw = tag.sublist(pos + 4, pos + 8);
    final size = version == 4 ? _readSynchsafe4(raw) : _readBe32(raw);
    if (size <= 0 || pos + 10 + size > tag.length) break;
    final data = tag.sublist(pos + 10, pos + 10 + size);
    try {
      switch (id) {
        case 'TIT2':
          tags.title = _decodeText(data[0], data.sublist(1));
          break;
        case 'TPE1':
          tags.artist = _decodeText(data[0], data.sublist(1));
          break;
        case 'TALB':
          tags.album = _decodeText(data[0], data.sublist(1));
          break;
        case 'TYER':
          tags.year = _decodeText(data[0], data.sublist(1));
          break;
        case 'TDRC':
          tags.year = _decodeText(data[0], data.sublist(1)).split('T').first;
          break;
        case 'USLT':
          // encoding(1) + lang(3) + desc(terminator) + text
          var i = 4; // 跳过 encoding + 'xxx'
          final enc = data[0];
          i = _skipTerminated(data, i, enc);
          tags.lyrics = _decodeText(enc, data.sublist(i));
          break;
        case 'APIC':
          final enc = data[0];
          var i = 1;
          final mimeEnd = data.indexOf(0, i);
          if (mimeEnd < 0) break;
          tags.coverMime = latin1.decode(data.sublist(i, mimeEnd));
          i = mimeEnd + 1;
          i += 1; // picture type
          i = _skipTerminated(data, i, enc);
          tags.cover = Uint8List.fromList(data.sublist(i));
          break;
      }
    } catch (_) {
      // 单帧解析失败不影响其余
    }
    pos += 10 + size;
  }
  return tags;
}

/// 跳过一个按编码规则终止的字符串（返回终止符后的位置）
int _skipTerminated(Uint8List data, int from, int encoding) {
  if (encoding == 1 || encoding == 2) {
    for (var i = from; i + 1 < data.length; i += 2) {
      if (data[i] == 0 && data[i + 1] == 0) return i + 2;
    }
    return data.length;
  }
  final end = data.indexOf(0, from);
  return end < 0 ? data.length : end + 1;
}

/// 待写入的标签（仅非空字段会写）
class Mp3TagPatch {
  final String? title;
  final String? artist;
  final String? album;
  final String? year;
  final String? lyrics;
  final Uint8List? cover;
  const Mp3TagPatch({
    this.title,
    this.artist,
    this.album,
    this.year,
    this.lyrics,
    this.cover,
  });
}

/// 把标签写入 mp3（ID3v2.3）：读取现有标签合并（已有非空字段不被覆盖），
/// 替换文件头部旧标签，其余字节流式保留。
Future<void> writeMp3Tags(String path, Mp3TagPatch patch) async {
  final existing = readMp3Tags(path) ?? Mp3Tags();
  final title = _pick(patch.title, existing.title);
  final artist = _pick(patch.artist, existing.artist);
  final album = _pick(patch.album, existing.album);
  final year = _pick(patch.year, existing.year);
  final lyrics = _pick(patch.lyrics, existing.lyrics);
  final cover = patch.cover != null && patch.cover!.isNotEmpty
      ? patch.cover
      : (existing.cover != null && existing.cover!.isNotEmpty ? existing.cover : null);

  if (title == null &&
      artist == null &&
      album == null &&
      year == null &&
      lyrics == null &&
      cover == null) {
    return; // 没有任何可写内容，不动文件
  }

  final frames = BytesBuilder();
  void text(String id, String? v) {
    if (v == null || v.isEmpty) return;
    frames.add(_frame(id, [1, ..._utf16(v)]));
  }

  text('TIT2', title);
  text('TPE1', artist);
  text('TALB', album);
  text('TYER', year);
  if (lyrics != null && lyrics.isNotEmpty) {
    final data = BytesBuilder();
    data.add([3, ...latin1.encode('chi')]); // UTF-8 + 语言
    data.add([0]); // 空描述符终止
    data.add(const Utf8Encoder().convert(lyrics));
    frames.add(_frame('USLT', data.toBytes()));
  }
  if (cover != null) {
    final mime = _sniffMime(cover);
    final data = BytesBuilder();
    data.add([0, ...latin1.encode(mime)]); // encoding=latin1 + mime
    data.add([0, 3, 0]); // mime 终止 + 封面类型(3=Front cover) + 空描述
    data.add(cover);
    frames.add(_frame('APIC', data.toBytes()));
  }
  final body = frames.toBytes();
  final header = BytesBuilder();
  header.add([0x49, 0x44, 0x33, 3, 0, 0]); // "ID3" v2.3 无标志
  header.add(_synchsafe4(body.length));
  final tag = header.toBytes();

  // 计算旧标签长度（有则替换，无则前插）
  int oldTagLen = 0;
  final src = File(path).openSync(mode: FileMode.read);
  try {
    final head = _readAt(src, 0, 10);
    if (head.length >= 10 &&
        head[0] == 0x49 &&
        head[1] == 0x44 &&
        head[2] == 0x33) {
      final s = _readSynchsafe4(head.sublist(6, 10));
      if (s > 0 && s <= 10 * 1024 * 1024) oldTagLen = 10 + s;
    }
  } finally {
    src.closeSync();
  }

  final tmpPath = '$path.tagtmp';
  final tmp = File(tmpPath).openWrite();
  try {
    tmp.add(tag);
    tmp.add(body);
    await tmp.flush();
    await tmp.close();
    final raf = File(tmpPath).openSync(mode: FileMode.append);
    final rest = File(path).openRead(oldTagLen);
    await for (final chunk in rest) {
      raf.writeFromSync(chunk);
    }
    raf.closeSync();
    await File(path).delete();
    await File(tmpPath).rename(path);
  } catch (e) {
    try {
      await File(tmpPath).delete();
    } catch (_) {}
    rethrow;
  }
}

String? _pick(String? want, String? have) {
  if (want != null && want.trim().isNotEmpty) return want.trim();
  if (have != null && have.trim().isNotEmpty) return have.trim();
  return null;
}

/// 从图片魔数判断 MIME（写入 APIC 用）
String _sniffMime(Uint8List b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length > 2 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  if (b.length > 3 && String.fromCharCodes(b.sublist(0, 3)) == 'GIF') return 'image/gif';
  return 'image/jpeg';
}
