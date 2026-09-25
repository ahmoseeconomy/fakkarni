import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/scheduling/day_pattern.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

/// الدالة الواحدة اللي بتقول الجرعة شغّالة في اليوم ده ولا لأ.
void main() {
  DateTime d(int y, int m, int day) => DateTime(y, m, day);
  bool on(DayPattern p, DateTime start, DateTime day) => dayPatternActive(p, start: start, day: day);
  List<int> activeDaysOfMonth(DayPattern p, DateTime start, int y, int m) => [
        for (var i = 1; i <= DateTime(y, m + 1, 0).day; i++)
          if (on(p, start, d(y, m, i))) i,
      ];

  test('كل يوم: من البداية وبعدها بس', () {
    expect(on(DayPattern.everyDay, d(2026, 9, 10), d(2026, 9, 9)), isFalse);
    expect(on(DayPattern.everyDay, d(2026, 9, 10), d(2026, 9, 10)), isTrue);
    expect(on(DayPattern.everyDay, d(2026, 9, 10), d(2027, 3, 1)), isTrue);
  });

  test('أيام معيّنة: السبت والتلات والخميس — والتخزين بيرجع زي ما هو', () {
    final p = OnWeekdays({DateTime.saturday, DateTime.tuesday, DateTime.thursday});
    // سبتمبر ٢٠٢٦: السبت ٥/١٢/١٩/٢٦، التلات ١/٨/١٥/٢٢/٢٩، الخميس ٣/١٠/١٧/٢٤
    expect(activeDaysOfMonth(p, d(2026, 9, 1), 2026, 9), [1, 3, 5, 8, 10, 12, 15, 17, 19, 22, 24, 26, 29]);
    expect(OnWeekdays.fromMask(p.mask), p);
    expect(p.mask, 42);
    expect(() => OnWeekdays(const <int>{}), throwsArgumentError);
  });

  test('كل كام يوم: «يوم ويوم» من البداية، وعبر آخر الشهر وآخر السنة', () {
    final p = EveryNDays(2);
    expect(activeDaysOfMonth(p, d(2026, 9, 1), 2026, 9).take(4), [1, 3, 5, 7]);
    // ٣٠ سبتمبر شغّال (فرق ٢٩؟ لأ — ٢٩ فردي) → ٢٩ سبتمبر، ١ أكتوبر
    expect(on(p, d(2026, 9, 1), d(2026, 9, 29)), isTrue);
    expect(on(p, d(2026, 9, 1), d(2026, 9, 30)), isFalse);
    expect(on(p, d(2026, 9, 1), d(2026, 10, 1)), isTrue);
    // آخر السنة: من ٣٠ ديسمبر كل ٣ أيام → ٢ يناير، ٥ يناير
    final three = EveryNDays(3);
    expect(on(three, d(2026, 12, 30), d(2027, 1, 2)), isTrue);
    expect(on(three, d(2026, 12, 30), d(2027, 1, 1)), isFalse);
    expect(on(three, d(2026, 12, 30), d(2027, 1, 5)), isTrue);
    expect(() => EveryNDays(1), throwsArgumentError);
  });

  test('فترة وراحة ٢١/٧: الأسبوع التالت راحة، واللفّة بترجع', () {
    final p = OnOffCycle(21, 7);
    final start = d(2026, 9, 1);
    expect(on(p, start, d(2026, 9, 21)), isTrue, reason: 'اليوم ٢١');
    for (var day = 22; day <= 28; day++) {
      expect(on(p, start, d(2026, 9, day)), isFalse, reason: 'راحة $day');
    }
    expect(on(p, start, d(2026, 9, 29)), isTrue, reason: 'اللفّة التانية');
    // عبر السنة: اللفّة رقم ١٣ (٣٦٤ يوم) بتبدأ ٣١ أغسطس ٢٠٢٧
    expect(on(p, start, d(2027, 8, 31)), isTrue);
    expect(on(p, start, d(2027, 8, 30)), isFalse);
  });

  test('بداية في المستقبل: ولا يوم قبلها، مهما كان النمط', () {
    final start = d(2026, 10, 3); // سبت
    for (final p in [DayPattern.everyDay, OnWeekdays({DateTime.saturday}), EveryNDays(2), OnOffCycle(3, 2)]) {
      expect(on(p, start, d(2026, 10, 2)), isFalse, reason: '$p');
      expect(on(p, start, d(2026, 10, 3)), isTrue, reason: '$p');
    }
  });

  test('التوقيت الصيفي في مصر (٢٤ أبريل / ٢٩ أكتوبر ٢٠٢٦) ما بيحرّكش اللفّة', () {
    final p = EveryNDays(2);
    // حوالين التغييرين، والساعة في اليوم مالهاش دعوة
    final start = d(2026, 4, 22);
    expect([for (var i = 22; i <= 28; i++) on(p, start, DateTime(2026, 4, i, 23, 30))],
        [true, false, true, false, true, false, true]);
    final autumn = d(2026, 10, 27);
    expect([for (var i = 27; i <= 31; i++) on(p, autumn, DateTime(2026, 10, i, 0, 30))],
        [true, false, true, false, true]);
  });

  test('الجدول بيسأل الدالة، والمدة و«مرة واحدة» فوقها', () {
    final s = DoseSchedule(
      id: '1',
      medicationName: 'X',
      timing: const AnchorTiming(DayAnchor.breakfast, 0),
      startDate: d(2026, 9, 1),
      durationDays: 10,
      days: EveryNDays(3),
    );
    expect([for (var i = 1; i <= 14; i++) if (s.isActiveOn(d(2026, 9, i))) i], [1, 4, 7, 10]);
    expect(s.copyWith(amountLabel: 'قرص').days, EveryNDays(3), reason: 'copyWith ما بيضيّعش النمط');
  });

  test('المعاينة ونصيب الأيام', () {
    expect(nextActiveDays(EveryNDays(2), start: d(2026, 9, 1), from: d(2026, 9, 2), count: 3),
        [d(2026, 9, 3), d(2026, 9, 5), d(2026, 9, 7)]);
    expect(dayPatternShare(OnWeekdays({1, 3, 5})), 3 / 7);
    expect(dayPatternShare(EveryNDays(4)), 0.25);
    expect(dayPatternShare(OnOffCycle(21, 7)), 0.75);
    expect(dayPatternLabel(OnWeekdays({DateTime.saturday, DateTime.tuesday})), 'السبت والتلات');
    expect(dayPatternLabel(EveryNDays(2)), 'يوم ويوم');
    expect(dayPatternLabel(OnOffCycle(21, 7)), '٢١ يوم وراحة ٧');
    expect(dayPatternLabel(DayPattern.everyDay), isNull);
  });
}
