/// **نهار ولا ليل؟ — مكان واحد للإجابة** (مراجعة المالك، ٥ أكتوبر ٢٠٢٦).
///
/// التحية وأيقونتها («صباح الخير» وشمسها من الشروق للغروب، «مساء الخير»
/// وهلالها من الغروب للشروق) والوضع «تلقائي» بتاع الشاشة الاتنين بيقروا
/// من هنا — نسختين كانوا هيختلفوا في صمت.
///
/// المكان: القاهرة افتراضياً؛ لو إذن المكان موجود خلاص (من «القريب مني»)
/// بناخد آخر مكان معروف **من غير أي حوار** ([quietPosition]) —
/// `main` بينده [refreshLocation] كمجاملة بعد الإقلاع، وفشلها بيسيب
/// القاهرة. **التحية بتمشي مع الوقت الحقيقي دايماً**، مهما كان وضع
/// الشاشة المختار.
library;

import '../core/diagnostics.dart';
import '../data/location/quiet_position.dart';
import '../domain/time/sun_times.dart' as sun;

abstract final class DayNight {
  static double _lat = sun.cairoLat;
  static double _lon = sun.cairoLon;

  /// كاش نافذة اليوم — بتتحسب مرة لكل (يوم، مكان).
  static ({int sunriseMinutes, int sunsetMinutes})? _window;
  static DateTime? _windowDay;

  static ({int sunriseMinutes, int sunsetMinutes}) windowFor(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    if (_window == null || _windowDay != day) {
      _window = sun.sunWindowFor(now, lat: _lat, lon: _lon);
      _windowDay = day;
    }
    return _window!;
  }

  /// نهار؟ — للتحية وللوضع «تلقائي». **باللحظات** (٥ أكتوبر ٢٠٢٦): نافذة
  /// الحيطة بتتلف لما المكان بعيد عن منطقة الجهاز، واللفّ كان بيطلّع
  /// «ليل على طول» — عطل المحاكي المتقاس.
  static bool isDaytime(DateTime now) => sun.isDaytimeAtInstant(now, lat: _lat, lon: _lon);

  /// مجاملة بعد الإقلاع: مكان من غير سؤال — نجح بيظبط النافذة، فشل بيسيب
  /// القاهرة. **عمره ما يطلب إذن** ([quietPosition]).
  static Future<bool> refreshLocation({
    Future<({double lat, double lon})?> Function() position = quietPosition,
    Duration? tzOffset,
  }) async {
    final p = await position();
    if (p == null) return false;
    // **المكان لازم يطابق منطقة الجهاز**: آخر مكان متخزّن ممكن يبقى قديم
    // (سفر)، والمحاكي بيدّي سان فرانسيسكو وساعته قاهرة — الشمس هناك
    // والساعة هنا بيطلّعوا تحية غلط طول اليوم (العطل المتقاس، ٥ أكتوبر).
    final offset = tzOffset ?? DateTime.now().timeZoneOffset;
    if (!sun.plausibleForTimezone(p.lon, offset)) {
      diag('DayNight: المكان المتخزّن (${p.lat}, ${p.lon}) بعيد عن منطقة الجهاز '
          '(${offset.inHours} س) — القاهرة أصدق منه');
      return false;
    }
    _lat = p.lat;
    _lon = p.lon;
    _window = null; // النافذة بتتحسب تاني بالمكان الجديد
    return true;
  }

  /// للاختبار — ترجيع القاهرة والكاش.
  static void resetForTest() {
    _lat = sun.cairoLat;
    _lon = sun.cairoLon;
    _window = null;
    _windowDay = null;
  }
}
