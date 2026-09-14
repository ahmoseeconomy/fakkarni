import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/ramadan.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

/// صحيان ٧، فطار ٧:٣٠، غدا ٢:٣٠، عشا ٨، نوم ١١:٣٠ م
final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final times = RamadanTimes(
  iftar: MinuteOfDay.hm(18),
  suhoor: MinuteOfDay.hm(3, 30),
);

final aug31 = DateTime(2026, 8, 31);

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

void main() {
  final ramadan = ramadanRoutine(normalDay, times);

  test('الأصل ما اتلمسش — الدالة بترجّع روتين جديد', () {
    expect(normalDay.breakfast, MinuteOfDay.hm(7, 30));
    expect(ramadan, isNot(normalDay));
  });

  test('«قبل الفطار − ٣٠» بقت ٥:٣٠ م — من غير أي تعديل في الدوا', () {
    final before = ScheduleEngine(normalDay).resolveTime(
        anchor: DayAnchor.breakfast, offsetMinutes: -30, onDay: aug31);
    final after = ScheduleEngine(ramadan).resolveTime(
        anchor: DayAnchor.breakfast, offsetMinutes: -30, onDay: aug31);
    expect(hhmm(before), '07:00');
    expect(hhmm(after), '17:30');
  });

  test('جرعة الغدا بتندمج مع الفطار في تذكير واحد — ما بتختفيش', () {
    final reminders = ScheduleEngine(ramadan).remindersForDay([
      DoseSchedule(
        id: '1',
        medicationName: 'A',
        timing: const AnchorTiming(DayAnchor.breakfast, -30),
        repeat: DoseRepeat.daily,
        startDate: aug31,
      ),
      DoseSchedule(
        id: '2',
        medicationName: 'B',
        timing: const AnchorTiming(DayAnchor.lunch, -30),
        repeat: DoseRepeat.daily,
        startDate: aug31,
      ),
    ], aug31);
    expect(reminders.length, 1);
    expect(reminders.single.doses.length, 2);
    expect(hhmm(reminders.single.at), '17:30');
  });

  test('العشا → السحور، وبيقع في التاريخ اللي بعده (آخر يوم الروتين)', () {
    final t = ScheduleEngine(ramadan).resolveTime(
        anchor: DayAnchor.dinner, offsetMinutes: 0, onDay: aug31);
    expect(t.day, 1, reason: 'السحور ٣:٣٠ بعد نص الليل — أول سبتمبر');
    expect(hhmm(t), '03:30');
  });

  test('الصحيان زي ما هو، والنوم بعد السحور بساعة', () {
    expect(ramadan.wake, normalDay.wake);
    expect(ramadan.sleep, MinuteOfDay.hm(4, 30));
    expect(sleepAfterSuhoorMinutes, 60);
  });

  test('الساعة الثابتة ما بتتحركش في الاتجاهين', () {
    final fixed = DoseSchedule(
      id: '9',
      medicationName: 'F',
      timing: FixedTiming(MinuteOfDay.hm(14)),
      repeat: DoseRepeat.daily,
      startDate: aug31,
    );
    final before = ScheduleEngine(normalDay).remindersForDay([fixed], aug31);
    final during = ScheduleEngine(ramadan).remindersForDay([fixed], aug31);
    // الرجوع للأصل — نفس الروتين اللي بدأنا بيه
    final after = ScheduleEngine(normalDay).remindersForDay([fixed], aug31);
    expect(before.single.at, during.single.at);
    expect(during.single.at, after.single.at);
    expect(hhmm(during.single.at), '14:00');
  });

  test('قيم القاهرة الافتراضية: ٦ م و ٣:٣٠ ص', () {
    expect(RamadanTimes.cairoDefaults.iftar, MinuteOfDay.hm(18));
    expect(RamadanTimes.cairoDefaults.suhoor, MinuteOfDay.hm(3, 30));
  });

  test('نوم بعد سحور متأخر بيلف حوالين نص الليل من غير ما يرمي', () {
    final late = ramadanRoutine(
      normalDay,
      RamadanTimes(iftar: MinuteOfDay.hm(18), suhoor: MinuteOfDay.hm(23, 30)),
    );
    expect(late.sleep, MinuteOfDay.hm(0, 30));
  });
}
