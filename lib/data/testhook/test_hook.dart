import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../core/diagnostics.dart';
import '../../domain/patient/sex.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/dose_schedule.dart';

/// باب خلفي للاختبار على جهاز — **وموجود في debug/profile بس**.
///
/// سكّة أندرويد (زرار الإشعار والتطبيق متقفول) عمرها ما اشتغلت على أي
/// جهاز. عشان اختبار آلي يجرّبها، لازم يزرع جرعة معادها بعد شوية من
/// برّه التطبيق — ومفيش طريقة تانية غير باب زي ده.
///
/// **بوابتين، واحدة في كل لغة**: `kReleaseMode` هنا، و`BuildConfig.DEBUG`
/// في `MainActivity.kt`. أي واحدة كفاية لوحدها، والاتنين مع بعض معناها
/// إن نسيان واحدة مش بيفتح الباب.
abstract final class TestHook {
  static const _channel = MethodChannel('fakkarni/testhook');

  /// بياخد عدد الثواني اللي الاختبار طلبها ويصفّيها — أو null.
  static Future<int?> _takeSeedSeconds() async {
    try {
      return await _channel.invokeMethod<int>('takeSeedSeconds');
    } catch (_) {
      return null;
    }
  }

  /// بيزرع مريض وروتين ودوا جرعته في أقرب دقيقة جاية. بيرجّع true لو حصل،
  /// واللي بينده بيعيد الجدولة بعدها زي أي فتحة عادية.
  ///
  /// **الدقة دقيقة مش ثانية**: التذكير بيتجدول على حدود الدقيقة
  /// (`MinuteOfDay`)، فطلب «بعد ٢٠ ثانية» معناه «أول دقيقة جاية» — أي
  /// وقت بين صفر و٦٠ ثانية. الاختبار مستني على الأساس ده.
  static Future<bool> seedIfAsked(AppServices services) async {
    if (kReleaseMode) return false;
    final seconds = await _takeSeedSeconds();
    if (seconds == null) return false;

    final fire = DateTime.now().add(Duration(seconds: seconds));
    final minute = MinuteOfDay(fire.hour * 60 + fire.minute);
    diag('TestHook: بنزرع جرعة الساعة ${minute.hour}:${minute.minute}');

    await services.routines.saveProfile(
      services.patientId,
      name: 'اختبار',
      sex: Sex.m,
    );
    await services.routines.saveRoutine(services.patientId, DayRoutine.fallback);
    await services.medications.addMedication(
      patientId: services.patientId,
      name: 'TestDose',
      timing: FixedTiming(minute),
      startDate: DateTime(fire.year, fire.month, fire.day),
      amountLabel: 'قرص',
    );
    return true;
  }
}
