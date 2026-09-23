import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **الاختبار بيشغّل السكربت الحقيقي**، مش بيقرا نصّه.
///
/// حارس على فحص تسريب لازم يكون شافه بيوقع فعلاً — قراية مصدر كانت هتعدّي
/// على `grep` بيطابق فراغ أو على `exit` ناقص. كل حالة هنا بتبني مجلد بناء
/// مزيّف وملف أسرار مزيّف وبتشوف السكربت بيعمل إيه.
///
/// القيم المزروعة هنا **مخترعة** — مفيش سر حقيقي في أي اختبار.
void main() {
  late Directory tmp;
  late Directory build;
  late File secrets;

  const geminiValue = 'AIzaTOTALLYfakeVALUEforTESTS0000';
  const anonValue = 'sbp_publishable_fake_for_tests';
  const urlValue = 'https://fake-project.supabase.co';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('leakcheck');
    build = Directory('${tmp.path}/web')..createSync(recursive: true);
    secrets = File('${tmp.path}/secrets.json')
      ..writeAsStringSync(jsonEncode({
        'GEMINI_API_KEY': geminiValue,
        'SUPABASE_ANON_KEY': anonValue,
        'SUPABASE_URL': urlValue,
      }));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  ProcessResult run() => Process.runSync(
        'bash',
        ['tool/leak_check.sh', build.path, secrets.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  String output(ProcessResult r) => '${r.stdout}${r.stderr}';

  void bundle(String contents) =>
      File('${build.path}/main.dart.js').writeAsStringSync(contents);

  test('حزمة فيها المسموح بس بتعدّي', () {
    bundle('var u="$urlValue";var k="$anonValue";');
    final result = run();
    expect(result.exitCode, 0, reason: output(result));
  });

  test('قيمة مفتاح جيميني بتوقّف الرفع', () {
    bundle('var u="$urlValue";var g="$geminiValue";');
    final result = run();
    expect(result.exitCode, isNonZero);
    expect(output(result), contains('GEMINI_API_KEY'));
  });

  test('**ولا مرة بتطبع القيمة نفسها** — تقرير بيسرّب السر أسوأ من مفيش', () {
    bundle('var g="$geminiValue";');
    final result = run();
    expect(result.exitCode, isNonZero);
    expect(output(result), isNot(contains(geminiValue)),
        reason: 'الفحص طبع السر اللي بيبلّغ عنه');
  });

  test('اسم المفتاح لوحده كفاية يوقّف — يعني التعريف اتمرّر للبناء', () {
    bundle('const GEMINI_API_KEY = fromEnvironment();');
    final result = run();
    expect(result.exitCode, isNonZero);
    expect(output(result), contains('GEMINI_API_KEY'));
  });

  test('مفتاح الخدمة ممنوع حتى لو مش في secrets.json', () {
    // مقسوم زي `no_privileged_key_test` بالظبط — الحارس بيوقع على الكلمة
    // كاملة في أي ملف في الحزمة، والملف ده منها.
    const roleToken = 'service' '_role';
    bundle('var role = "$roleToken";');
    final result = run();
    expect(result.exitCode, isNonZero);
    expect(output(result), contains(roleToken));
  });

  test('بادئة AIza ممنوعة حتى لو المفتاح مش بتاعنا', () {
    bundle('var other = "AIzaSomeOtherProjectsKey1234";');
    final result = run();
    expect(result.exitCode, isNonZero);
    expect(output(result), contains('AIza'));
  });

  test('بيدوّر في الملفات الثنائية كمان — سر في .wasm سر برضه', () {
    File('${build.path}/app.wasm')
        .writeAsBytesSync([0, 1, 2, ...utf8.encode(geminiValue), 0, 3]);
    bundle('var u="$urlValue";');
    final result = run();
    expect(result.exitCode, isNonZero, reason: output(result));
    expect(output(result), contains('GEMINI_API_KEY'));
  });

  test('مجلد بناء مش موجود = غلط استعمال، مش «نضيف»', () {
    final result = Process.runSync(
      'bash',
      ['tool/leak_check.sh', '${tmp.path}/nope', secrets.path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, isNot(0));
  });

  test('قايمة السماح مفتاحين بالظبط — أي زيادة قرار، مش سهو', () {
    final source = File('tool/leak_check.sh').readAsStringSync();
    expect(
      source,
      contains('ALLOWED=("SUPABASE_URL" "SUPABASE_ANON_KEY")'),
      reason: 'قايمة السماح اتغيّرت — ده قرار نشر، لازم يتراجع بالعين',
    );
  });
}
