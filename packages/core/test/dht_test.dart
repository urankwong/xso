import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('bencode', () {
    test('整数编解码', () {
      expect(Bencode.decode(Bencode.encode(42)), 42);
      expect(Bencode.decode(Bencode.encode(-7)), -7);
      expect(Bencode.decode(Bencode.encode(0)), 0);
    });

    test('字符串编解码', () {
      expect(Bencode.decode(Bencode.encode('hello')),
          Uint8List.fromList('hello'.codeUnits));
    });

    test('字节串二进制安全（0x00 不被截断）', () {
      final raw = Uint8List.fromList([0, 1, 255, 0, 128]);
      final decoded = Bencode.decode(Bencode.encode(raw));
      expect(decoded, raw);
    });

    test('list 与 dict 往返', () {
      final v = {
        't': Uint8List.fromList([0xaa, 0xbb]),
        'y': 'q',
        'q': 'ping',
        'a': {'id': Uint8List(20)},
      };
      final decoded = Bencode.decode(Bencode.encode(v));
      expect(decoded, isA<Map<String, Object?>>());
      final m = decoded as Map<String, Object?>;
      expect(m['y'], Uint8List.fromList('q'.codeUnits));
      expect(m['q'], Uint8List.fromList('ping'.codeUnits));
      expect(m['a'], isA<Map>());
    });

    test('dict key 按字节序升序排列', () {
      final enc = Bencode.encode({'b': 1, 'a': 2});
      expect(String.fromCharCodes(enc), startsWith('d1:a'));
    });
  });

  group('磁力链 infohash 解析', () {
    test('40 字符十六进制', () {
      final h = infoHashFromMagnet(
          'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c');
      expect(h, isNotNull);
      expect(h!.length, 20);
      expect(h[0], 0xdd);
      expect(h[19], 0x1c);
    });

    test('32 字符 base32', () {
      // 全 A 在 base32 里表示 0，应解出 20 个 0 字节
      final h = infoHashFromMagnet(
          'magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
      expect(h, isNotNull);
      expect(h!.length, 20);
      expect(h.every((b) => b == 0), isTrue);
    });

    test('带其它参数的完整磁力链', () {
      final h = infoHashFromMagnet(
          'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c'
          '&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Ftracker');
      expect(h, isNotNull);
      expect(h!.length, 20);
    });

    test('非磁力链返回 null', () {
      expect(infoHashFromMagnet('https://example.com/a.torrent'), isNull);
      expect(infoHashFromMagnet('ed2k://|file|x|1|2|/|'), isNull);
      expect(infoHashFromMagnet(''), isNull);
    });
  });

  group('PeerLookup 判定', () {
    test('无节点响应 = 结论未知', () {
      const r = PeerLookup(peerCount: 0, respondedNodes: 0);
      expect(r.unknown, isTrue);
      expect(r.isDead, isFalse); // 不能因为查不到就判死
    });

    test('有响应但无 peer = 判定失效', () {
      const r = PeerLookup(peerCount: 0, respondedNodes: 3);
      expect(r.unknown, isFalse);
      expect(r.isDead, isTrue);
    });

    test('有 peer', () {
      const r = PeerLookup(peerCount: 12, respondedNodes: 4);
      expect(r.unknown, isFalse);
      expect(r.isDead, isFalse);
    });
  });
}
