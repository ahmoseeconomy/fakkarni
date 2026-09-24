import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/ramadan.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

/// **الروتين اختياري، والمحرّك عمره ما يوقّت دوا من مرساة المستخدم ما
/// حدّدهاش.** الرقم اللي في الروتين لمرساة مش متحددة مكان راحة، مش إجابة.
void main() {
  final full = DayRoutine(
    wake: MinuteOfDay.hm(7),
    breakfast: MinuteOfDay.hm(7, 30),
    lunch: MinuteOfDay.hm(14, 30),
    dinner: MinuteOfDay.hm(20),
    sleep: MinuteOfDay.hm(23, 30),
  );
  final day = DateTime(2026, 8, 31);

  DoseSchedule dose(String id, DoseTiming timing) => DoseSchedule(
        id: id,
        medicationName: id,
        timing: timing,
        repeat: DoseRepeat.daily,
        durationDays: null,
        amountLabel: null,
        startDate: day,
      );

  group('النموذج', () {
    test('الافتراضي متحدد بالكامل، و`none` مفيش فيه ولا مرساة متحددة', () {
      expect(DayRoutine.fallback.isComplete, isTrue);
      expect(DayRoutine.none.isComplete, isFalse);
      expect(DayRoutine.none.unset, DayAnchor.values.toSet());
      for (final a in DayAnchor.values) {
        expect(DayRoutine.none.at(a), DayRoutine.fallback.at(a), reason: 'مكان راحة');
      }
    });

    test('withAnchor بيحدد المرساة دي وبس، وبيشيلها من «مش متحدد»', () {
      final r = DayRoutine.none.withAnchor(DayAnchor.breakfast, MinuteOfDay.hm(8));
      expect(r.isSet(DayAnchor.breakfast), isTrue);
      expect(r.breakfast, MinuteOfDay.hm(8));
      expect(r.unset, DayAnchor.values.toSet().difference({DayAnchor.breakfast}));
      expect(r.lunch, DayRoutine.fallback.lunch, reason: 'الباقي ما اتلمسش');
    });

    test('التساوي بيحسب اللي مش متحدد — روتين كامل ≠ نفس الأرقام مش متحددة', () {
      expect(DayRoutine.fallback == DayRoutine.none, isFalse);
      expect(DayRoutine.none.copyWith(unset: const {}), DayRoutine.fallback);
      expect(DayRoutine.none.withAnchor(DayAnchor.wake, MinuteOfDay.hm(6, 30)),
          DayRoutine.none.copyWith(unset: DayAnchor.values.toSet().difference({DayAnchor.wake})));
    });
  });

  group('المحرّك', () {
    test('روتين كامل: نفس التذكيرات بالحرف زي قبل — الحسابات ما اتغيّرتش', () {
      final engine = ScheduleEngine(full);
      final rems = engine.remindersForDay([
        dose('a', const AnchorTiming(DayAnchor.breakfast, -30)),
        dose('b', FixedTiming(MinuteOfDay.hm(21))),
      ], day);
      expect(rems.map((r) => r.at), [DateTime(2026, 8, 31, 7), DateTime(2026, 8, 31, 21)]);
    });

    test('**جرعة على مرساة مش متحددة ما بتترنّش** — والثابتة جنبها بترنّ', () {
      final partial = full.copyWith(unset: {DayAnchor.breakfast});
      final engine = ScheduleEngine(partial);
      final rems = engine.remindersForDay([
        dose('a', const AnchorTiming(DayAnchor.breakfast, -30)),
        dose('b', const AnchorTiming(DayAnchor.dinner, 30)),
        dose('c', FixedTiming(MinuteOfDay.hm(21))),
      ], day);
      expect(rems.map((r) => r.at), [DateTime(2026, 8, 31, 20, 30), DateTime(2026, 8, 31, 21)]);
      expect(rems.expand((r) => r.doses).map((d) => d.id), ['b', 'c']);
      expect(engine.nextReminder([dose('a', const AnchorTiming(DayAnchor.breakfast, -30))], day),
          isNull, reason: 'مفيش تذكير يتحسب من رقم ما اتقالش');
    });

    test('لما المرساة تتحدد بعدين، الجرعة المربوطة بيها بتتبعها — والثابتة مكانها', () {
      final before = full.copyWith(unset: {DayAnchor.breakfast});
      final after = before.withAnchor(DayAnchor.breakfast, MinuteOfDay.hm(9));
      final doses = [
        dose('a', const AnchorTiming(DayAnchor.breakfast, -30)),
        dose('c', FixedTiming(MinuteOfDay.hm(21))),
      ];
      expect(ScheduleEngine(before).remindersForDay(doses, day).map((r) => r.at),
          [DateTime(2026, 8, 31, 21)]);
      expect(ScheduleEngine(after).remindersForDay(doses, day).map((r) => r.at),
          [DateTime(2026, 8, 31, 8, 30), DateTime(2026, 8, 31, 21)]);
    });

    test('صحيان مش متحدد بيحدد حدود اليوم بس — الثابتة بعد نص الليل بنفس اللحظة', () {
      final noWake = full.copyWith(unset: {DayAnchor.wake});
      final one = dose('n', FixedTiming(MinuteOfDay.hm(1)));
      expect(ScheduleEngine(noWake).resolve(one, day), ScheduleEngine(full).resolve(one, day));
    });
  });

  group('رمضان', () {
    test('الفطار والسحور اللي المستخدم كتبهم بيحددوا الوجبات والنوم، والصحيان زي ما كان', () {
      final times = RamadanTimes(iftar: MinuteOfDay.hm(18), suhoor: MinuteOfDay.hm(3, 30));
      final r = ramadanRoutine(DayRoutine.none, times);
      expect(r.unset, {DayAnchor.wake});
      expect(r.isSet(DayAnchor.breakfast), isTrue);
      expect(ramadanRoutine(full, times).isComplete, isTrue);
    });
  });
}
