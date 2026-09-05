import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  test('FakeJsRuntime 能执行预置脚本并取回结果', () async {
    final rt = FakeJsRuntime(scriptResults: {'a': '2'});
    final result = await rt.evaluate('a');
    expect(result, '2');
  });

  test('JsRuntime 超时强制终止', () async {
    final rt = FakeJsRuntime();
    expect(
      () => rt.evaluate('while(true){}', timeout: Duration(milliseconds: 50)),
      throwsA(isA<JsTimeoutException>()),
    );
  });

  test('JS 异常转为 JsEvaluationException 而非穿透', () async {
    final rt = FakeJsRuntime();
    expect(
      () => rt.evaluate('throw new Error("boom")'),
      throwsA(isA<JsEvaluationException>()),
    );
  });

  test('宿主函数可注册并触发', () async {
    final rt = FakeJsRuntime();
    rt.registerHostFunction('log', (args) async => args.join());
    expect(await rt.invokeHost('log', ['a', 'b']), 'ab');
  });
}
