import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/routine_day.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

/// المحرّك بعد ما الروتين اتشال (٢٧ سبتمبر ٢٠٢٦): كل جرعة ساعة ثابتة،
/// واليوم بيبدأ ٤ الفجر لكل الناس.
void main() {
  const engine = ScheduleEngine();
  final day = DateTime(2026, 9, 1);

  DoseSchedule at(String id, int h, [int m = 0, DoseRepeat repeat = DoseRepeat.daily, int? days]) => DoseSchedule(
        id: id,
        medicationName: id,
        timing: FixedTiming(MinuteOfDay.hm(h, m)),
        startDate: DateTime(2026, 8, 31),
        repeat: repeat,
        durationDays: days,
      );

  group('الساعة الثابتة', () {
    test('٩ الصبح على يوم = ٩ الصبح في نفس التاريخ', () {
      expect(engine.resolveFixed(minuteOfDay: MinuteOfDay.hm(9), onDay: day), DateTime(2026, 9, 1, 9));
    });

    test('١ بالليل تبع آخر اليوم — التاريخ اللي بعده', () {
      expect(engine.resolveFixed(minuteOfDay: MinuteOfDay.hm(1), onDay: day), DateTime(2026, 9, 2, 1));
    });

    test('٤ الفجر بالظبط أول اليوم — نفس التاريخ', () {
      expect(engine.resolveFixed(minuteOfDay: dayStart, onDay: day), DateTime(2026, 9, 1, 4));
      expect(engine.resolveFixed(minuteOfDay: MinuteOfDay.hm(3, 59), onDay: day), DateTime(2026, 9, 2, 3, 59));
    });

    test('resolve = resolveFixed على ساعة الجدول', () {
      expect(engine.resolve(at('a', 21, 15), day), DateTime(2026, 9, 1, 21, 15));
    });
  });

  group('تذكيرات اليوم', () {
    test('مرتّبة بالوقت، ونفس الدقيقة = تذكير واحد بدوايين', () {
      final reminders = engine.remindersForDay([at('b', 21), at('a', 9), at('c', 9)], day);
      expect(reminders.map((r) => r.at), [DateTime(2026, 9, 1, 9), DateTime(2026, 9, 1, 21)]);
      expect(reminders.first.doses.map((d) => d.id), ['a', 'c']);
      expect(reminders.first.isGrouped, isTrue);
    });

    test('جرعة بالليل بعد نص الليل بتيجي آخر اليوم بتاريخ بكرة', () {
      final reminders = engine.remindersForDay([at('night', 1), at('morning', 8)], day);
      expect(reminders.map((r) => r.at), [DateTime(2026, 9, 1, 8), DateTime(2026, 9, 2, 1)]);
    });

    test('اللي ما بدأش أو خلّص مدته ما بيرنش', () {
      final notYet = at('x', 9).copyWith(startDate: DateTime(2026, 9, 5));
      final over = at('y', 9, 0, DoseRepeat.daily, 1);
      expect(engine.remindersForDay([notYet, over], day), isEmpty);
      expect(engine.remindersForDay([over], DateTime(2026, 8, 31)), hasLength(1));
    });

    test('«مرة واحدة» يوم البداية بس', () {
      final once = at('o', 12, 0, DoseRepeat.once);
      expect(engine.remindersForDay([once], DateTime(2026, 8, 31)), hasLength(1));
      expect(engine.remindersForDay([once], day), isEmpty);
    });
  });

  group('التذكير الجاي', () {
    test('أقرب تذكير بعد «دلوقتي» — حتى لو بتاع يوم امبارح بعد نص الليل', () {
      final next = engine.nextReminder([at('night', 1), at('morning', 8)], DateTime(2026, 9, 1, 23, 30));
      expect(next!.at, DateTime(2026, 9, 2, 1));
    });

    test('مفيش حاجة = null', () {
      expect(engine.nextReminder([at('y', 9, 0, DoseRepeat.daily, 1)], DateTime(2026, 9, 10)), isNull);
    });
  });

  group('يوم الروتين — ٤ الفجر', () {
    test('قبل ٤ الفجر لسه امبارح', () {
      expect(routineDayOf(DateTime(2026, 9, 2, 3, 59)), DateTime(2026, 9, 1));
      expect(routineDayOf(DateTime(2026, 9, 2, 4)), DateTime(2026, 9, 2));
      expect(routineDayOf(DateTime(2026, 9, 2, 12)), DateTime(2026, 9, 2));
    });

    test('«النهارده» بعد نص الليل = يوم الروتين اللي لسه ماشي', () {
      final now = DateTime(2026, 9, 2, 0, 50);
      expect(startDayFor(DateTime(2026, 9, 2), now), DateTime(2026, 9, 1));
      expect(startDayFor(DateTime(2026, 9, 3), now), DateTime(2026, 9, 3));
      expect(startDayFor(DateTime(2026, 9, 2), DateTime(2026, 9, 2, 10)), DateTime(2026, 9, 2));
    });
  });
}
