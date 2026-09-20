import 'dart:io';

import 'package:flutter/services.dart';

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

  /// true = التطبيق مستثنى (أو مفيش تحسين بطارية أصلاً).
  ///
  /// على iOS وفي `flutter test` مفيش قناة — بترجّع true والفحص بيسكت.
  /// **الشك بيتحسب سليم** عن قصد: إنذار كذب على شاشة مريض أسوأ من فحص
  /// ساكت.
  static Future<bool> isUnrestricted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true;
    } catch (_) {
      return true;
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
