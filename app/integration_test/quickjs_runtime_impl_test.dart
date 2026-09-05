import 'package:flutter_test/flutter_test.dart';
import 'package:app/runtime/quickjs_runtime_impl.dart';
import 'package:source_engine/source_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('evaluate 返回表达式结果', () async {
    final rt = QuickJsRuntimeImpl();
    expect(await rt.evaluate('1 + 1'), '2');
    rt.dispose();
  });

  test('JS 异常转 JsEvaluationException', () async {
    final rt = QuickJsRuntimeImpl();
    await expectLater(
      rt.evaluate('throw new Error("boom")'),
      throwsA(isA<JsEvaluationException>()),
    );
    rt.dispose();
  });
}
