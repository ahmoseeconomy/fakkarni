import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **الفحص بيقرا الشرط، ومش بياخد إذن مقيّد عشان يصلّحه.**
///
/// أول نسخة من الفحص ده كانت بتحط `true` ثابتة — حارس شرطه عمره ما
/// بيتحقّق. والحل إننا نقراه، مش إننا نشيله. بس القراية حاجة والإصلاح
/// حاجة تانية: `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (الحوار
/// المباشر) بيطلب إذن `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`، وهو إذن
/// **مقيّد** على Google Play بقايمة استخدامات مقبولة.
/// `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` بيوصل لنفس النتيجة
/// بدوسة زيادة ومن غير أي إذن.
void main() {
  /// التعليقات بتتشال الأول: الشرح نفسه بيسمّي الـintent المرفوض، ومقارنة
  /// على نص فيه شرح بتقيس التعليق مش الكود.
  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') &&
            !t.startsWith('*') &&
            !t.startsWith('/*');
      })
      .join('\n');

  final kotlin =
      code('android/app/src/main/kotlin/com/fakkarni/fakkarni/MainActivity.kt');
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final dartSource =
      File('lib/data/battery/battery_optimisation.dart').readAsStringSync();
  final dart = code('lib/data/battery/battery_optimisation.dart');

  test('الحالة بتتقرا من النظام، مش مفترضة', () {
    expect(kotlin, contains('isIgnoringBatteryOptimizations'));
    expect(dart, contains("invokeMethod<bool>('isIgnoringBatteryOptimizations')"));
  });

  test('الزرار بيفتح قايمة الإعدادات — مش الحوار المباشر', () {
    expect(kotlin, contains('ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS'));
    expect(kotlin, isNot(contains('ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')),
        reason: 'ده بيجرّنا لإذن مقيّد على Play من غير داعي');
  });

  test('الإذن المقيّد مش مطلوب في الـmanifest', () {
    expect(manifest, isNot(contains('REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')));
    // والقاعدة القديمة لسه واقفة: USE_EXACT_ALARM مرفوض في مراجعة Play
    // لتطبيق مش منبّه/اتصال، وإحنا بنطلب SCHEDULE_EXACT_ALARM وقت التشغيل
    expect(manifest, isNot(contains('USE_EXACT_ALARM')));
  });

  test('القناة بتتسجّل على المحرّك — مفيش فحص من غير قناة', () {
    expect(kotlin, contains('BatteryChannel.register('));
    expect(kotlin, contains('fakkarni/battery'));
    expect(dart, contains("MethodChannel('fakkarni/battery')"));
  });

  test('غياب القناة بيتحسب سليم — مفيش إنذار كذب', () {
    // على iOS وفي الاختبارات مفيش قناة؛ فحص بيقول «مكسور» ساعتها بيبقى
    // أسوأ من فحص ساكت.
    expect(dartSource, contains('if (!Platform.isAndroid) return true;'));
    expect(dartSource, contains('} catch (_) {\n      return true;\n    }'));
  });
}
