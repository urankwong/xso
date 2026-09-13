import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:app/runtime/quickjs_runtime_impl.dart';
import 'package:source_engine/source_engine.dart';

/// QuickJS 动态库在 `flutter test` 宿主 VM 里不可加载（flutter_js 限制），
/// 依赖 JS 引擎的用例自动跳过，真机/模拟器上正常执行。
QuickJsRuntimeImpl? tryOpenRuntime() {
  try {
    return QuickJsRuntimeImpl();
  } catch (_) {
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RSA：PKCS#1 公钥加密 → 私钥可解（纯 Dart）', () {
    final rnd = pc.FortunaRandom()..seed(pc.KeyParameter(_seed32()));
    final keyGen = pc.RSAKeyGenerator()
      ..init(pc.ParametersWithRandom(
          pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), 1024, 64), rnd));
    final pair = keyGen.generateKeyPair();
    final pub = pair.publicKey as pc.RSAPublicKey;
    final prv = pair.privateKey as pc.RSAPrivateKey;

    final seq = ASN1Sequence()
      ..add(ASN1Integer(pub.modulus!))
      ..add(ASN1Integer(pub.exponent!));
    final pem =
        '-----BEGIN RSA PUBLIC KEY-----\n${base64.encode(seq.encodedBytes)}\n-----END RSA PUBLIC KEY-----';

    final cipherText = QuickJsRuntimeImpl.rsaEncryptPem(pem, 'rsa-bridge-ok');
    final decryptor = pc.PKCS1Encoding(pc.RSAEngine())
      ..init(false, pc.PrivateKeyParameter<pc.RSAPrivateKey>(prv));
    final plain = utf8.decode(decryptor.process(base64.decode(cipherText)));
    expect(plain, 'rsa-bridge-ok');
  });

  test('CryptoJS 注入：md5 / aes 回环（需 JS 引擎）', () async {
    final rt = tryOpenRuntime();
    if (rt == null) return; // 宿主 VM 无 QuickJS，跳过
    final md5 = await rt.evaluate("CryptoJS.MD5('abc').toString()");
    expect(md5, '900150983cd24fb0d6963f7d28e17f72');

    await rt.evaluate(r'''
      globalThis.__enc = CryptoJS.AES.encrypt(
        'hello-xso', CryptoJS.enc.Utf8.parse('0123456789abcdef'),
        { iv: CryptoJS.enc.Utf8.parse('0123456789abcdef'),
          mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7 }).toString();
      1
    ''');
    final dec = await rt.evaluate(r'''
      CryptoJS.AES.decrypt(__enc, CryptoJS.enc.Utf8.parse('0123456789abcdef'),
        { iv: CryptoJS.enc.Utf8.parse('0123456789abcdef'),
          mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7 }).toString(CryptoJS.enc.Utf8);
    ''');
    expect(dec, 'hello-xso');
    rt.dispose();
  });

  test('lx utils.crypto：md5 / aesEn/aesDe 回环（需 JS 引擎）', () async {
    final rt = tryOpenRuntime();
    if (rt == null) return;
    await LxAdapter(jsRuntime: rt).wrap('1;', name: '测试洛雪源');
    final md5 = await rt.evaluate("lx.utils.crypto.md5('abc')");
    expect(md5, '900150983cd24fb0d6963f7d28e17f72');
    await rt.evaluate(
        "globalThis.__e = lx.utils.crypto.aesEn('洛雪测试', 'aes-128-cbc', '0123456789abcdef', '0123456789abcdef'); 1");
    final dec = await rt.evaluate(
        "lx.utils.crypto.aesDe(__e, 'aes-128-cbc', '0123456789abcdef', '0123456789abcdef')");
    expect(dec, '洛雪测试');
    rt.dispose();
  });

  test('musicfree env：require CryptoJS / storage（需 JS 引擎）', () async {
    final rt = tryOpenRuntime();
    if (rt == null) return;
    await MusicFreeAdapter(jsRuntime: rt).wrap(
        'module.exports = { platform: "测试源", version: "0.0.1", search: function(){ return {isEnd:true, data:[]}; } };');
    final v = await rt.evaluate(
        'CryptoJS.MD5("abc").toString() + "|" + __mfEnv.CryptoJS.MD5("abc").toString()');
    expect(v, contains('900150983cd24fb0d6963f7d28e17f72'));
    await rt.evaluate('__mfEnv.storage.set("k", "v"); 1');
    final got = await rt.evaluate('__mfEnv.storage.get("k")');
    expect(got, contains('v'));
    rt.dispose();
  });
}

Uint8List _seed32() {
  final s = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    s[i] = i;
  }
  return s;
}
