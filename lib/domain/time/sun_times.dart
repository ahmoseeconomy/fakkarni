/// **شروق وغروب حقيقيين — حساب نقي** (مراجعة المالك، ٥ أكتوبر ٢٠٢٦).
///
/// خوارزمية NOAA المعروفة (تقريب الزوال الشمسي + زاوية الساعة عند −٠٫٨٣٣°)،
/// دقتها دقايق معدودة — كفاية لتحية وقلبة ثيم، ومش ملاحة. دارت نقية:
/// مفيش مكان ولا إذن هنا — الإحداثيات بتيجي من برّه، والقاهرة هي
/// الافتراضي لما مفيش مكان متاح ([cairoLat]/[cairoLon]).
///
/// **كل النواتج UTC**، والتحويل لحيطان الساعة المحلية بيحصل عند القارئ
/// بـ`timeZoneOffset` بتاع اللحظة نفسها — عشان الاختبار ما يعتمدش على
/// منطقة ماكينة التشغيل، وعشان صيفي مصر يتحسب من النظام مش مننا.
library;

import 'dart:math' as math;

/// القاهرة — الافتراضي لما المكان مش متاح (قرار المالك: عمرنا ما نطلب
/// إذن مكان جديد عشان التحية).
const double cairoLat = 30.0444;
const double cairoLon = 31.2357;

/// شروق وغروب يوم واحد، UTC.
class SunTimes {
  const SunTimes({required this.sunriseUtc, required this.sunsetUtc});

  final DateTime sunriseUtc;
  final DateTime sunsetUtc;
}

double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

/// شروق وغروب التاريخ [year]/[month]/[day] (تاريخ ميلادي، بيوم UTC) عند
/// [lat]/[lon]. جوّه الدايرة القطبية ممكن اليوم يبقى كله نهار أو كله ليل —
/// ساعتها بنرجّع null (مش حالتنا، بس الحساب ما يكدبش).
SunTimes? sunTimesUtc({
  required int year,
  required int month,
  required int day,
  double lat = cairoLat,
  double lon = cairoLon,
}) {
  // يوم جولياني للظهر UTC
  final a = (14 - month) ~/ 12;
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  final jdn = day + ((153 * m + 2) ~/ 5) + 365 * y + y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
  final n = jdn - 2451545 + 0.0008; // أيام من J2000

  final meanSolarTime = n - lon / 360;
  final meanAnomaly = (357.5291 + 0.98560028 * meanSolarTime) % 360;
  final center = 1.9148 * math.sin(_rad(meanAnomaly)) +
      0.02 * math.sin(_rad(2 * meanAnomaly)) +
      0.0003 * math.sin(_rad(3 * meanAnomaly));
  final eclipticLon = (meanAnomaly + center + 180 + 102.9372) % 360;
  final solarTransit = 2451545 +
      meanSolarTime +
      0.0053 * math.sin(_rad(meanAnomaly)) -
      0.0069 * math.sin(_rad(2 * eclipticLon));
  final declination = _deg(math.asin(math.sin(_rad(eclipticLon)) * math.sin(_rad(23.4397))));

  // −٠٫٨٣٣° = نص قرص الشمس + انكسار الأفق
  final cosHourAngle = (math.sin(_rad(-0.833)) - math.sin(_rad(lat)) * math.sin(_rad(declination))) /
      (math.cos(_rad(lat)) * math.cos(_rad(declination)));
  if (cosHourAngle < -1 || cosHourAngle > 1) return null;
  final hourAngle = _deg(math.acos(cosHourAngle));

  DateTime fromJulian(double jd) {
    final ms = ((jd - 2440587.5) * 24 * 60 * 60 * 1000).round();
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  return SunTimes(
    sunriseUtc: fromJulian(solarTransit - hourAngle / 360),
    sunsetUtc: fromJulian(solarTransit + hourAngle / 360),
  );
}

/// نافذة النهار **بحيطان الساعة المحلية** للحظة [now] — دقيقة الشروق
/// ودقيقة الغروب في يوم [now] نفسه. التحويل بإزاحة [now] نفسها
/// (`timeZoneOffset`)، فصيفي مصر محسوب من النظام.
({int sunriseMinutes, int sunsetMinutes}) sunWindowFor(
  DateTime now, {
  double lat = cairoLat,
  double lon = cairoLon,
}) {
  final utcDay = now.toUtc();
  final times = sunTimesUtc(year: utcDay.year, month: utcDay.month, day: utcDay.day, lat: lat, lon: lon);
  if (times == null) {
    // قطبي — مش حالتنا: نهار افتراضي من ٦ لـ٦ بدل ما التحية تقع
    return (sunriseMinutes: 6 * 60, sunsetMinutes: 18 * 60);
  }
  int wall(DateTime utc) {
    final local = utc.add(now.timeZoneOffset);
    return local.hour * 60 + local.minute;
  }

  return (sunriseMinutes: wall(times.sunriseUtc), sunsetMinutes: wall(times.sunsetUtc));
}

/// نهار؟ — من الشروق **لحد** الغروب (قرار المالك: «صباح الخير» وشمسها
/// من الشروق للغروب، و«مساء الخير» وهلالها من الغروب للشروق).
bool isDaytime(DateTime now, {required int sunriseMinutes, required int sunsetMinutes}) {
  final minutes = now.hour * 60 + now.minute;
  return minutes >= sunriseMinutes && minutes < sunsetMinutes;
}
