import '../../core/format/arabic_time.dart';
import '../escalation/escalation_ladder.dart' show graceWindow;

/// **«إنت ماشي إزاي»** — الحساب كله هنا، دارت نقية: من غير قاعدة ولا
/// واجهة ولا جدولة. بياخد أحداث الجرعات زي ما اتسجّلت (موبايل المريض، أو
/// الصورة اللي وصلت للعيلة والممرض) ويطلّع العدّ والأسبوع والنسبة واللي
/// فات.
///
/// **قراية بس.** مفيش هنا ولا حاجة بتجدول أو بتلغي أو بتكتب — الأوقات
/// اللي بيقرا منها هي اللي محرّك المريض حسبها وقت ما نزّل اليوم، فرمضان
/// والروتين اللي اتغيّر والجرعة اللي بعد نص الليل كلهم داخلين في «يوم
/// الروتين» بتاع الصف نفسه، مش في الساعة.

/// حالة الجرعة زي ما الحساب محتاجها.
enum AdherenceState { pending, taken, skipped, missed }

/// جرعة واحدة في يوم روتين.
class AdherenceDose {
  const AdherenceDose({
    required this.id,
    required this.medicationName,
    required this.routineDay,
    required this.scheduledAt,
    required this.state,
  });

  /// مفتاح بيرجّع بيه اللي نده للصف بتاعه (عشان «أخدتها متأخر»).
  final String id;
  final String medicationName;

  /// يوم الروتين — **مش** تاريخ الساعة: جرعة ١ بالليل تبع امبارح.
  final DateTime routineDay;
  final DateTime scheduledAt;
  final AdherenceState state;
}

/// شكل اليوم في نقط الأسبوع.
enum DayMark {
  /// كل جرعة مستحقة اتاخدت أو المريض قرر ما ياخدهاش.
  complete,

  /// فيه جرعة عدّى وقتها ومهلتها من غير تأكيد.
  missed,

  /// مفيش جرعات مستحقة في اليوم ده — لا بيكسر العدّ ولا بيزوّده.
  neutral,

  /// لسه ما جاش، أو لسه فيه جرعة في وقتها.
  upcoming,
}

class WeekDay {
  const WeekDay(this.day, this.mark);
  final DateTime day;
  final DayMark mark;
}

class MissedDose {
  const MissedDose({
    required this.id,
    required this.medicationName,
    required this.routineDay,
    required this.scheduledAt,
  });
  final String id;
  final String medicationName;
  final DateTime routineDay;
  final DateTime scheduledAt;
}

class Adherence {
  const Adherence({
    required this.currentStreak,
    required this.bestStreak,
    required this.currentAtLeast,
    required this.bestAtLeast,
    required this.week,
    required this.takenPercent,
    required this.missed,
    required this.today,
  });

  /// أيام كاملة ورا بعض لحد النهارده (النهارده بيتحسب لما يكمل بس، وجرعة
  /// فاتت النهارده ما بتصفّرهوش طول ما اليوم مفتوح).
  final int currentStreak;
  final int bestStreak;

  /// العدّ وصل لأول الداتا اللي عندنا — الحقيقي ممكن يبقى أكتر
  /// (العيلة بتشوف آخر أسبوع بس).
  final bool currentAtLeast;
  final bool bestAtLeast;

  /// من السبت للجمعة — الأسبوع المصري.
  final List<WeekDay> week;

  /// من الجرعات اللي اتحسم أمرها في آخر ٧ أيام: كام في المية اتاخد.
  /// null = مفيش ولا جرعة اتحسمت.
  final int? takenPercent;

  /// اللي فات في آخر ٧ أيام — الأحدث الأول.
  final List<MissedDose> missed;

  /// يوم الروتين اللي الحساب اتعمل عليه.
  final DateTime today;
}

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime _plus(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// الجرعة دي عدّت مهلتها من غير تأكيد؟ نفس مهلة الجهاز (٤٥ دقيقة) اللي
/// «يومك» بتقول عندها «نسيتها؟» — مش تعريف تاني.
bool doseIsMissed(AdherenceDose d, DateTime now) => switch (d.state) {
      AdherenceState.missed => true,
      AdherenceState.pending => !d.scheduledAt.add(graceWindow).isAfter(now),
      AdherenceState.taken || AdherenceState.skipped => false,
    };

/// أول يوم في الأسبوع المصري (السبت) اللي فيه [day].
DateTime weekStart(DateTime day) {
  final d = _date(day);
  return _plus(d, -((d.weekday - DateTime.saturday) % 7));
}

/// **قواعد اليوم:**
/// * يوم فيه جرعة واحدة فايتة (مهلتها خلصت من غير تأكيد) = [DayMark.missed].
/// * يوم مفيهوش فايت وفيه جرعة لسه في وقتها = [DayMark.upcoming] — لسه
///   بيتحسم، فلا بيكسر ولا بيزوّد.
/// * يوم كل جرعاته اتاخدت (بإيده أو بإيد الممرض) أو اتخطّت بقراره =
///   [DayMark.complete].
/// * يوم مالوش جرعات = [DayMark.neutral].
/// * يوم لسه ما جاش = [DayMark.upcoming].
DayMark markDay(List<AdherenceDose> doses, DateTime day, {required DateTime today, required DateTime now}) {
  if (_date(day).isAfter(today)) return DayMark.upcoming;
  if (doses.isEmpty) return DayMark.neutral;
  if (doses.any((d) => doseIsMissed(d, now))) return DayMark.missed;
  if (doses.any((d) => d.state == AdherenceState.pending)) return DayMark.upcoming;
  return DayMark.complete;
}

/// الحساب كله.
///
/// [today] يوم الروتين الحالي (عند المريض من صحيانه؛ عند العيلة التاريخ).
/// [dataFrom] أول يوم الداتا فيه كاملة — العيلة بتسحب ٧ أيام بالساعة، فأول
/// يوم فيها ممكن يبقى ناقص؛ بيتشال من الحساب، والعدّ اللي يوصله بيتقال
/// «أو أكتر». null = الداتا من أول يوم (موبايل المريض).
Adherence computeAdherence(
  List<AdherenceDose> doses, {
  required DateTime today,
  required DateTime now,
  DateTime? dataFrom,
}) {
  final t = _date(today);
  final from = dataFrom == null ? null : _date(dataFrom);
  final byDay = <DateTime, List<AdherenceDose>>{};
  for (final d in doses) {
    final day = _date(d.routineDay);
    if (from != null && day.isBefore(from)) continue;
    (byDay[day] ??= []).add(d);
  }

  DayMark mark(DateTime day) => markDay(byDay[day] ?? const [], day, today: t, now: now);

  /// شكل اليوم **للعدّ**: النهارده لسه مفتوح، فجرعة فاتت الصبح ما بتصفّرش
  /// الرقم — النقطة بتبقى رمادي، والرقم بيفضل. أول ما يوم الروتين يقفل
  /// وفيه فايت (بقى «امبارح»)، العدّ بيبدأ من جديد من اليوم اللي بعده.
  DayMark streakMark(DateTime day) {
    final m = mark(day);
    return day == t && m == DayMark.missed ? DayMark.upcoming : m;
  }

  // الأيام اللي عندنا، من أولها لحد النهارده.
  final known = byDay.keys.where((d) => !d.isAfter(t)).toList()..sort();
  final start = from ?? (known.isEmpty ? t : known.first);

  // --- العدّ الحالي: من النهارده لورا.
  var current = 0;
  var currentAtLeast = false;
  for (var day = t; !day.isBefore(start); day = _plus(day, -1)) {
    final m = streakMark(day);
    if (m == DayMark.missed) break;
    if (m == DayMark.complete) current++;
    if (from != null && day == from && current > 0) currentAtLeast = true;
  }

  // --- أحسن عدّ: على كل الأيام اللي عندنا.
  var best = 0, run = 0;
  var bestAtLeast = false, runAtLeast = false;
  for (var day = start; !day.isAfter(t); day = _plus(day, 1)) {
    final m = streakMark(day);
    if (m == DayMark.missed) {
      run = 0;
      runAtLeast = false;
      continue;
    }
    if (m == DayMark.complete) {
      if (run == 0 && from != null && day == from) runAtLeast = true;
      run++;
    } else if (run == 0 && from != null && day == from) {
      // يوم محايد في أول الداتا — اللي قبله مش معروف
      runAtLeast = true;
    }
    if (run > best || (run == best && runAtLeast && !bestAtLeast)) {
      best = run;
      bestAtLeast = runAtLeast;
    }
  }
  if (current > best) {
    best = current;
    bestAtLeast = currentAtLeast;
  }

  // --- الأسبوع (سبت ← جمعة).
  final ws = weekStart(t);
  final week = [for (var i = 0; i < 7; i++) WeekDay(_plus(ws, i), mark(_plus(ws, i)))];

  // --- آخر ٧ أيام: النسبة واللي فات.
  final last7From = _plus(t, -6);
  var taken = 0, decided = 0;
  final missed = <MissedDose>[];
  for (final entry in byDay.entries) {
    if (entry.key.isBefore(last7From) || entry.key.isAfter(t)) continue;
    for (final d in entry.value) {
      if (d.state == AdherenceState.taken) {
        taken++;
        decided++;
      } else if (doseIsMissed(d, now)) {
        decided++;
        missed.add(MissedDose(
          id: d.id,
          medicationName: d.medicationName,
          routineDay: entry.key,
          scheduledAt: d.scheduledAt,
        ));
      }
      // المتخطّية بقراره: مش «فاتت» ومش «اتاخدت» — برّه النسبة.
    }
  }
  missed.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  return Adherence(
    currentStreak: current,
    bestStreak: best,
    currentAtLeast: currentAtLeast,
    bestAtLeast: bestAtLeast,
    week: week,
    takenPercent: decided == 0 ? null : (taken * 100 / decided).round(),
    missed: missed,
    today: t,
  );
}

/// الكارت بيستخبّى أول يومين بعد أول دوا — لسه مفيش حاجة تتقال.
/// [firstDay] أول يوم روتين عليه جرعة؛ null = مفيش جرعات خالص.
bool adherenceWorthShowing(DateTime? firstDay, DateTime today) =>
    firstDay != null && _date(today).difference(_date(firstDay)).inDays >= 2;

// ===========================================================================
// الكلام — مصري، مشجّع، ومن غير لوم. مفيش «فشلت» ولا «فاتتك» بنبرة حكم.
// ===========================================================================

/// «٥ أيام ورا بعض» / «النهارده بداية جديدة».
String streakLine(int days, {bool atLeast = false}) {
  if (days <= 0) return 'النهارده بداية جديدة';
  final more = atLeast ? ' أو أكتر' : '';
  return switch (days) {
    1 => 'يوم كامل$more',
    2 => 'يومين$more ورا بعض',
    <= 10 => '${arabicNumber(days)} أيام$more ورا بعض',
    _ => '${arabicNumber(days)} يوم$more ورا بعض',
  };
}

/// السطر اللي تحت الرقم — تشجيع وبس.
String streakCheer(int days) => days <= 0
    ? 'كل يوم أدويته كاملة بيبدأ العدّ من أوله.'
    : 'كمّل كده — كل يوم أدويته كاملة بيتحسب.';

String takenPercentLine(int? percent) => percent == null
    ? 'لسه مفيش جرعات اتحسبت في آخر ٧ أيام.'
    : 'اتاخد ${arabicNumber(percent)}٪ من الجرعات في آخر ٧ أيام';

String bestStreakLine(int days, {bool atLeast = false}) =>
    days <= 0 ? 'لسه أول عدّ هيتسجّل هنا.' : 'أحسن مرة: ${streakLine(days, atLeast: atLeast)}';

/// حرف اليوم تحت النقطة — السبت الأول.
const weekDayLetters = {
  DateTime.saturday: 'سبت',
  DateTime.sunday: 'حد',
  DateTime.monday: 'اتنين',
  DateTime.tuesday: 'تلات',
  DateTime.wednesday: 'أربع',
  DateTime.thursday: 'خميس',
  DateTime.friday: 'جمعة',
};

const _dayNames = {
  DateTime.saturday: 'السبت',
  DateTime.sunday: 'الحد',
  DateTime.monday: 'الاتنين',
  DateTime.tuesday: 'التلات',
  DateTime.wednesday: 'الأربع',
  DateTime.thursday: 'الخميس',
  DateTime.friday: 'الجمعة',
};

/// «النهارده ٨:٠٠ ص» / «امبارح ...» / «الاتنين ...».
String missedWhen(MissedDose m, DateTime today) {
  final diff = _date(today).difference(_date(m.routineDay)).inDays;
  final day = switch (diff) {
    0 => 'النهارده',
    1 => 'امبارح',
    _ => _dayNames[m.routineDay.weekday]!,
  };
  return '$day ${arabicTime(m.scheduledAt)}';
}

/// وصف النقطة للقارئ الصوتي — نفس المعنى من غير لون.
String dayMarkWord(DayMark m) => switch (m) {
      DayMark.complete => 'كامل',
      DayMark.missed => 'فيه جرعة ما اتأكدتش',
      DayMark.neutral => 'مفيش جرعات',
      DayMark.upcoming => 'لسه',
    };

/// كل الجمل الثابتة — الحارس بيقراها.
List<String> adherenceSampleTexts() => [
      for (final n in [0, 1, 2, 5, 12]) streakLine(n),
      streakLine(7, atLeast: true),
      streakCheer(0),
      streakCheer(4),
      takenPercentLine(null),
      takenPercentLine(86),
      bestStreakLine(0),
      bestStreakLine(9),
      for (final m in DayMark.values) dayMarkWord(m),
      ...weekDayLetters.values,
      ..._dayNames.values,
    ];
