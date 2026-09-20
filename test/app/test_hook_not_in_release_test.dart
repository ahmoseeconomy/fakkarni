import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// باب خلفي بيزرع دوا من برّه التطبيق **ماينفعش يوصل لحد**.
///
/// موجود لسبب واحد: سكّة أندرويد عمرها ما اشتغلت على جهاز، واختبار آلي
/// محتاج يزرع جرعة معادها بعد شوية. البوابة مكرّرة في اللغتين عن قصد —
/// نسيان واحدة ما بيفتحش الباب.
void main() {
  final dart = File('lib/data/testhook/test_hook.dart').readAsStringSync();
  final kotlin =
      File('android/app/src/main/kotlin/com/fakkarni/fakkarni/MainActivity.kt')
          .readAsStringSync();

  test('دارت: أول سطر في الزرع بيقف في نسخة الإصدار', () {
    final body = dart.substring(dart.indexOf('static Future<bool> seedIfAsked('));
    final gate = body.indexOf('if (kReleaseMode) return false;');
    expect(gate, isNot(-1), reason: 'مفيش بوابة أصلاً');
    // قبل أي كتابة في القاعدة
    for (final write in ['saveProfile', 'saveRoutine', 'addMedication']) {
      expect(gate, lessThan(body.indexOf(write)),
          reason: 'الكتابة دي قبل البوابة');
    }
  });

  test('كوتلن: القناة مش بتتسجّل أصلاً في نسخة الإصدار', () {
    final body = kotlin.substring(kotlin.indexOf('object TestHookChannel'));
    // العلم بيتقرا من الـmanifest بتاع الـAPK الشغّال — أقوى من ثابت
    // وقت ترجمة في ملف ممكن يتعدّل. نسخة الإصدار عمرها ما بتبقى
    // debuggable.
    expect(body, contains('ApplicationInfo.FLAG_DEBUGGABLE'));
    expect(body, contains('if (!debuggable) return'));
    expect(body.indexOf('if (!debuggable) return'),
        lessThan(body.indexOf('setMethodCallHandler')),
        reason: 'البوابة لازم تسبق التسجيل، مش تيجي بعده');
  });

  test('الباب مالوش غير مناد واحد، وهو main', () {
    final callers = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final text = file.readAsStringSync();
      if (text.contains('TestHook.seedIfAsked(')) callers.add(file.path);
    }
    expect(callers, ['lib/main.dart']);
  });

  test('ومش بيتنده من سكّة صحوة شاشة القفل', () {
    // الصحوة عمرها ثواني — أي قراية زيادة فيها بتتصرف من وقت الجرعة
    final boot = File('lib/app/bootstrap.dart').readAsStringSync();
    expect(boot, isNot(contains('TestHook')));
  });
}
