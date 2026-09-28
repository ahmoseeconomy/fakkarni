// **الجمل المتغيّرة بصوت ممدوح** — حتت مسجّلة بتتركّب ورا بعض، بدل صوت
// الموبايل اللي كان آلي. دارت نقية.
//
// القواعد (المالك، ٢٨ سبتمبر ٢٠٢٦):
// * **ولا اسم دوا ولا اسم دكتور بيتقال** — مالهمش حتة مسجّلة. الجملة
//   بتتقال من غيرهم («والدوا الجاي الساعة ٥ العصر»)، والشاشة بتكتب الأسامي.
// * جملة محتاجة حتة مش في الكتالوج (١١ دوا، ٩ و٧ دقايق) = **ما بتتقالش
//   خالص** — ولا نص جملة. وكذلك لو ملف الحتة مش موجود (الخدمة بتتأكد).
// * الكتالوج هنا هو المرجع؛ `docs/voice/segments_to_record.md` فيه نفس
//   النصوص وأسامي الملفات، واختبار بيمسك الاتنين.

import '../../core/format/arabic_time.dart' show arabicNumber;

/// رقم الحتة ← نصها بالحرف (زي ما هيتسجّل).
final Map<String, String> segmentTexts = {
  'seg_greet_morning': 'صباح الخير.',
  'seg_greet_evening': 'مساء الخير.',
  'seg_today_you_have': 'النهارده عندك',
  for (var n = 1; n <= 10; n++) 'seg_count_$n': _countText(n),
  'seg_its_time': '، معادها',
  'seg_their_time': '، معادهم',
  'seg_next_dose': '، والدوا الجاي',
  'seg_next_dose_start': 'الدوا الجاي',
  for (var h = 1; h <= 12; h++) 'seg_hour_$h': 'الساعة ${arabicNumber(h)}',
  'seg_min_half': 'ونص',
  'seg_min_quarter': 'وربع',
  'seg_min_less_quarter': 'إلا ربع',
  'seg_part_morning': 'الصبح.',
  'seg_part_noon': 'الضهر.',
  'seg_part_asr': 'العصر.',
  'seg_part_maghrib': 'المغرب.',
  'seg_part_night': 'بالليل.',
  'seg_all_done': 'خلصت أدوية النهارده كلها.',
  'seg_visit_tomorrow': 'وعندك زيارة دكتور بكرة.',
  'seg_visit_after_tomorrow': 'وعندك زيارة دكتور بعد بكرة.',
  'seg_visit_after': 'وعندك زيارة دكتور بعد',
  for (var d = 3; d <= 10; d++) 'seg_days_$d': '${arabicNumber(d)} أيام.',
};

String _countText(int n) => switch (n) {
      1 => 'دوا واحد',
      2 => 'دوايين',
      _ => '${arabicNumber(n)} أدوية',
    };

/// مسار ملف الحتة.
String segmentAssetPath(String id) => 'assets/voices/segments/$id.mp3';

/// جملة متركّبة: الحتت بالترتيب، ونصها المقروء.
class SpokenPhrase {
  const SpokenPhrase(this.segments);
  final List<String> segments;

  String get text => segments.map((s) => segmentTexts[s]!).join(' ').replaceAll(' ،', '،').replaceAll(' .', '.');

  @override
  String toString() => 'SpokenPhrase($segments)';
}

/// «الساعة ٥ العصر» / «الساعة ٩ ونص الصبح» / «الساعة ٦ إلا ربع المغرب» —
/// null لو الدقايق مش صفر أو ربع أو نص أو إلا ربع (مالهاش حتة).
List<String>? timeSegments(DateTime t) {
  var hour = t.hour;
  final minute = t.minute;
  final String? min;
  switch (minute) {
    case 0:
      min = null;
    case 15:
      min = 'seg_min_quarter';
    case 30:
      min = 'seg_min_half';
    case 45:
      min = 'seg_min_less_quarter';
      hour = (hour + 1) % 24;
    default:
      return null;
  }
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  // نفس أجزاء اليوم بتاعة `voiceTime`
  final part = switch (hour) {
    >= 4 && <= 11 => 'seg_part_morning',
    >= 12 && <= 14 => 'seg_part_noon',
    >= 15 && <= 17 => 'seg_part_asr',
    >= 18 && <= 19 => 'seg_part_maghrib',
    _ => 'seg_part_night',
  };
  return ['seg_hour_$h12', ?min, part];
}

/// «دوا واحد» … «١٠ أدوية» — null برّه ١..١٠.
String? countSegment(int n) => n >= 1 && n <= 10 ? 'seg_count_$n' : null;

/// ملخص اليوم بالحتت: التحية ← «النهارده عندك N أدوية، معادها / والدوا
/// الجاي الساعة …» (أو «خلصت أدوية النهارده كلها») ← أقرب زيارة دكتور.
///
/// - [dosesToday] لحظات التذكير النهارده.
/// - [nextDoseAt] أول جرعة لسه ما اتأكدتش النهارده — null = خلصوا.
/// - [visitInDays] أقرب زيارة دكتور بعد كام يوم (١ = بكرة) — null = مفيش.
///
/// null = مفيش جملة تنفع تتقال كاملة بالحتت.
SpokenPhrase? briefingPhrase({
  required DateTime now,
  required int dosesToday,
  DateTime? nextDoseAt,
  int? visitInDays,
}) {
  final segs = <String>[now.hour >= 4 && now.hour < 12 ? 'seg_greet_morning' : 'seg_greet_evening'];
  var said = false;
  if (dosesToday > 0) {
    if (nextDoseAt == null) {
      segs.add('seg_all_done');
    } else {
      final count = countSegment(dosesToday);
      final time = timeSegments(nextDoseAt);
      if (count == null || time == null) return null;
      segs
        ..add('seg_today_you_have')
        ..add(count)
        ..add(dosesToday == 1 ? 'seg_its_time' : 'seg_next_dose')
        ..addAll(time);
    }
    said = true;
  }
  if (visitInDays != null && visitInDays >= 1) {
    if (visitInDays == 1) {
      segs.add('seg_visit_tomorrow');
    } else if (visitInDays == 2) {
      segs.add('seg_visit_after_tomorrow');
    } else if (visitInDays <= 10) {
      segs
        ..add('seg_visit_after')
        ..add('seg_days_$visitInDays');
    } else if (!said) {
      return null;
    }
    said = true;
  }
  return said ? SpokenPhrase(segs) : null;
}

/// «الدوا الجاي الساعة ٥ العصر» — رد «كلّمني» من غير اسم الدوا.
SpokenPhrase? nextDosePhrase(DateTime at) {
  final time = timeSegments(at);
  return time == null ? null : SpokenPhrase(['seg_next_dose_start', ...time]);
}

/// «النهارده عندك ٣ أدوية.» — رد «باخد إيه النهارده؟» من غير أسامي.
SpokenPhrase? todayCountPhrase(int moments) {
  final count = countSegment(moments);
  return count == null ? null : SpokenPhrase(['seg_today_you_have', count]);
}
