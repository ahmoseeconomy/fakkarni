import '../wording/rule_wording.dart' show dayPatternWording;

/// **أنهي أيام الجرعة شغّالة — دالة واحدة نقية** (أنماط الجدولة، الجولة ٢).
///
/// «كل يوم» / «أيام معيّنة» / «كل كام يوم» / «فترة وراحة»، **كلها محسوبة من
/// يوم البداية** («هتبدأ الدوا من إمتى؟»). النمط بيختار **الأيام** بس؛
/// الدقيقة لسه من المرساة أو الساعة الثابتة — فرمضان والمراسي زي ما هم.
/// اليوم المقفول ما بيطلعش منه ولا حدث ولا إشعار: المحرّك بيسأل
/// `DoseSchedule.isActiveOn` قبل أي حاجة، وكل اللي بعده بيشوف اللي طلع.
///
/// الفرق بين يومين بيتحسب بالتاريخ (UTC) مش بالساعات: مصر بتغيّر التوقيت،
/// ويوم بـ٢٣ ساعة كان هيطلع صفر أيام ويبوّظ اللفّة.
sealed class DayPattern {
  const DayPattern();

  /// كل يوم — الافتراضي، وكل الجداول اللي قبل الجولة دي.
  static const everyDay = EveryDay();
}

final class EveryDay extends DayPattern {
  const EveryDay();
  @override
  bool operator ==(Object other) => other is EveryDay;
  @override
  int get hashCode => 0;
}

/// أيام معيّنة من الأسبوع — `DateTime.saturday` … إلخ.
final class OnWeekdays extends DayPattern {
  OnWeekdays(Iterable<int> weekdays) : weekdays = Set.unmodifiable(weekdays) {
    if (this.weekdays.isEmpty || this.weekdays.any((d) => d < 1 || d > 7)) {
      throw ArgumentError.value(weekdays, 'weekdays');
    }
  }
  final Set<int> weekdays;

  /// التخزين: بت لكل يوم (الاتنين = البت ٠ … الحد = البت ٦).
  int get mask => weekdays.fold(0, (m, d) => m | (1 << (d - 1)));
  static OnWeekdays fromMask(int mask) => OnWeekdays([for (var d = 1; d <= 7; d++) if (mask & (1 << (d - 1)) != 0) d]);

  @override
  bool operator ==(Object other) => other is OnWeekdays && other.mask == mask;
  @override
  int get hashCode => mask;
}

/// كل [days] يوم من يوم البداية (٢ = «يوم ويوم»).
final class EveryNDays extends DayPattern {
  EveryNDays(this.days) {
    if (days < 2 || days > everyNDaysMax) throw ArgumentError.value(days, 'days');
  }
  final int days;
  @override
  bool operator ==(Object other) => other is EveryNDays && other.days == days;
  @override
  int get hashCode => days;
}

/// [on] يوم شغّال وبعدهم [off] يوم راحة، ويعيد — من يوم البداية.
final class OnOffCycle extends DayPattern {
  OnOffCycle(this.on, this.off) {
    if (on < 1 || on > cycleMaxDays || off < 1 || off > cycleMaxDays) {
      throw ArgumentError('on=$on off=$off');
    }
  }
  final int on;
  final int off;
  @override
  bool operator ==(Object other) => other is OnOffCycle && other.on == on && other.off == off;
  @override
  int get hashCode => on * 1000 + off;
}

const int everyNDaysMax = 30;
const int cycleMaxDays = 90;

int _epochDay(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1970)).inDays;

/// **القرار كله هنا.** يوم قبل البداية = لأ (المدة والـ«مرة واحدة» بيتحكموا
/// فيهم برّه في `DoseSchedule.isActiveOn`).
bool dayPatternActive(DayPattern pattern, {required DateTime start, required DateTime day}) {
  final gap = _epochDay(day) - _epochDay(start);
  if (gap < 0) return false;
  return switch (pattern) {
    EveryDay() => true,
    OnWeekdays(:final weekdays) => weekdays.contains(day.weekday),
    EveryNDays(:final days) => gap % days == 0,
    OnOffCycle(:final on, :final off) => gap % (on + off) < on,
  };
}

/// متوسط الأيام الشغّالة في اليوم — للمخزون: أيام معيّنة ن/٧، كل ن يوم ١/ن،
/// فترة وراحة شغّال/(شغّال+راحة).
double dayPatternShare(DayPattern pattern) => switch (pattern) {
      EveryDay() => 1,
      OnWeekdays(:final weekdays) => weekdays.length / 7,
      EveryNDays(:final days) => 1 / days,
      OnOffCycle(:final on, :final off) => on / (on + off),
    };

/// الأيام الجاية الشغّالة من [from] (أو من البداية لو لسه ما جاتش) — للمعاينة.
List<DateTime> nextActiveDays(DayPattern pattern, {required DateTime start, required DateTime from, int count = 5}) {
  final begin = from.isBefore(start) ? start : from;
  final out = <DateTime>[];
  for (var i = 0; out.length < count && i < 400; i++) {
    final d = DateTime(begin.year, begin.month, begin.day + i);
    if (dayPatternActive(pattern, start: start, day: d)) out.add(d);
  }
  return out;
}

/// «السبت والتلات» / «يوم ويوم» / «٢١ يوم وراحة ٧» — null = كل يوم.
String? dayPatternLabel(DayPattern p) => switch (p) {
      EveryDay() => null,
      OnWeekdays() => dayPatternWording(weekdaysMask: p.mask),
      EveryNDays(:final days) => dayPatternWording(everyDays: days),
      OnOffCycle(:final on, :final off) => dayPatternWording(cycleOn: on, cycleOff: off),
    };
