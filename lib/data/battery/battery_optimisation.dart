import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/health/health_snapshot.dart' show BatteryState;

/// حالة «تحسين البطارية» على أندرويد — **قراية من النظام، مش افتراض**.
///
/// الفحص ده رجع بعد ما اتشال: أول نسخة كانت بتحط `true` ثابتة عشان مفيش
/// API في دارت، وده حارس شرطه عمره ما بيتحقّق — بالظبط اللي الأعراف
/// بتحذّر منه. الحل إننا نقرا الشرط، مش إننا نشيل الحارس. قاتل البطارية
/// بتاع الشركة المصنّعة هو أشهر سبب إن تذكير دوا ما يرنش على أندرويد،
/// وأندرويد هو المنصة اللي مش بنقدر نجربها هنا.
///
/// **بنفتح قايمة الإعدادات، مش الحوار المباشر.** الحوار
/// (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) بيطلب إذن مقيّد على
/// Google Play؛ قايمة الإعدادات بتوصل لنفس النتيجة بدوسة زيادة ومن غير
/// أي إذن ومن غير أي تعرّض لسياسة المتجر.
abstract final class BatteryOptimisation {
  static const _channel = MethodChannel('fakkarni/battery');

  /// الحالة بتلات قيم — **و«ما قدرناش نبص» مش نفس «تمام»**.
  ///
  /// على iOS مفيش تحسين بطارية أصلاً، فالرد `unrestricted` حقيقة مش
  /// تهرّب. لكن قناة ما ردّتش على أندرويد (نسخة قديمة، صلاحية، أي حاجة)
  /// بترجّع `unknown`: على الشاشة بيتعامل زي السليم، وفي النبضة بيتسجّل
  /// لوحده عشان نعرف لو القناة نفسها بايظة على ألف جهاز.
  static Future<BatteryState> state() async {
    if (!Platform.isAndroid) return BatteryState.unrestricted;
    try {
      final ignoring =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      if (ignoring == null) return BatteryState.unknown;
      return ignoring ? BatteryState.unrestricted : BatteryState.restricted;
    } catch (_) {
      return BatteryState.unknown;
    }
  }

  /// بيفتح قايمة «تحسين البطارية» عشان المستخدم يشيل القيد بنفسه.
  static Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('openBatterySettings');
    } catch (_) {}
  }
}
