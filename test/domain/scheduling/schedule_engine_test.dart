import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

/// روتين عادي: صحيان ٧، فطار ٧:٣٠، غدا ٢:٣٠، عشا ٨، نوم ١١:٣٠ م
final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final aug31 = DateTime(2026, 8, 31);

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

DoseSchedule dose(
  String name,
  DayAnchor anchor, {
  int offset = 0,
  DoseRepeat repeat = DoseRepeat.daily,
  int? durationDays,
  DateTime? start,
}) =>
    DoseSchedule(
      id: name,
      medicationName: name,
      timing: AnchorTiming(anchor, offset),
      repeat: repeat,
      durationDays: durationDays,
      startDate: start ?? aug31,
    );

void main() {
  group('حساب وقت الجرعة من المرساة', () {
    final engine = ScheduleEngine(normalDay);

    test('قبل الفطار بنص ساعة → ٧:٠٠', () {
      final t = engine.resolveTime(
          anchor: DayAnchor.breakfast, offsetMinutes: -30, onDay: aug31);
      expect(hhmm(t), '07:00');
    });

    test('بعد العشا بنص ساعة → ٢٠:٣٠', () {
      final t = engine.resolveTime(
          anchor: DayAnchor.dinner, offsetMinutes: 30, onDay: aug31);
      expect(hhmm(t), '20:30');
    });

    test('قبل النوم برُبع ساعة → ٢٣:١٥', () {
      final t = engine.resolveTime(
          anchor: DayAnchor.sleep, offsetMinutes: -15, onDay: aug31);
      expect(hhmm(t), '23:15');
    });

    test('من غير إزاحة بيرجّع المرساة نفسها', () {
      final t = engine.resolveTime(
          anchor: DayAnchor.lunch, offsetMinutes: 0, onDay: aug31);
      expect(hhmm(t), '14:30');
    });
  });

  group('النوم بعد منتصف الليل', () {
    // بينام ١ ص — لازم يتحسب على اليوم اللي بعده، مش يرجع لورا ٢٣ ساعة
    final nightOwl = normalDay.copyWith(sleep: MinuteOfDay.hm(1));
    final engine = ScheduleEngine(nightOwl);

    test('جرعة قبل النوم بتقع فجر اليوم اللي بعده', () {
      final t = engine.resolveTime(
          anchor: DayAnchor.sleep, offsetMinutes: -15, onDay: aug31);
      expect(t, DateTime(2026, 9, 1, 0, 45));
    });

    test('المسافة من الصحيان ١٨ ساعة مش ناقص ٦', () {
      expect(nightOwl.minutesFromDayStart(DayAnchor.sleep), 18 * 60);
    });
  });

  group('تحريك مرساة بيحرّك الجرعات المربوطة بيها', () {
    test('الفطار اتأخر ساعة ونص → الجرعة اتأخرت معاه', () {
      final before = ScheduleEngine(normalDay).resolveTime(
          anchor: DayAnchor.breakfast, offsetMinutes: -30, onDay: aug31);
      final lateBreakfast = normalDay.copyWith(breakfast: MinuteOfDay.hm(9));
      final after = ScheduleEngine(lateBreakfast).resolveTime(
          anchor: DayAnchor.breakfast, offsetMinutes: -30, onDay: aug31);

      expect(hhmm(before), '07:00');
      expect(hhmm(after), '08:30');
    });
  });

  group('وضع رمضان', () {
    // نفس الجرعات بالظبط — روتين مختلف. مفيش أي تغيير في الأدوية.
    final ramadan = DayRoutine(
      wake: MinuteOfDay.hm(4),
      breakfast: MinuteOfDay.hm(18, 15), // المغرب
      lunch: MinuteOfDay.hm(20),
      dinner: MinuteOfDay.hm(3), // السحور
      sleep: MinuteOfDay.hm(2),
    );

    test('«قبل الفطار» بقت قبل المغرب مش قبل الصبح', () {
      final t = ScheduleEngine(ramadan).resolveTime(
          anchor: DayAnchor.breakfast, offsetMinutes: -30, onDay: aug31);
      expect(hhmm(t), '17:45');
    });
  });

  group('التجميع', () {
    final engine = ScheduleEngine(normalDay);

    test('دواءين في نفس الدقيقة = تذكير واحد', () {
      final reminders = engine.remindersForDay([
        dose('Antodine', DayAnchor.breakfast, offset: -30),
        dose('Vitamin D', DayAnchor.breakfast, offset: -30),
        dose('LINEX', DayAnchor.breakfast, offset: 30),
      ], aug31);

      expect(reminders.length, 2);
      expect(reminders.first.doses.length, 2);
      expect(reminders.first.isGrouped, isTrue);
      expect(reminders.last.isGrouped, isFalse);
    });

    test('التذكيرات بترجع مرتّبة بالوقت', () {
      final reminders = engine.remindersForDay([
        dose('Telfast', DayAnchor.sleep, offset: -15),
        dose('Antodine', DayAnchor.breakfast, offset: -30),
        dose('LINEX', DayAnchor.dinner, offset: 30),
      ], aug31);

      expect(reminders.map((r) => hhmm(r.at)).toList(),
          ['07:00', '20:30', '23:15']);
    });
  });

  group('التكرار والمدة', () {
    final engine = ScheduleEngine(normalDay);

    test('«اليوم فقط» بترن مرة واحدة وبس', () {
      final amebazole =
          dose('Amebazole', DayAnchor.lunch, repeat: DoseRepeat.once);

      expect(engine.remindersForDay([amebazole], aug31).length, 1);
      expect(
        engine.remindersForDay([amebazole], aug31.add(const Duration(days: 1))),
        isEmpty,
      );
    });

    test('مدة ٣ أيام بتشتغل ٣ أيام وتقف', () {
      final d = dose('Antibiotic', DayAnchor.breakfast, durationDays: 3);

      for (var i = 0; i < 3; i++) {
        expect(d.isActiveOn(aug31.add(Duration(days: i))), isTrue,
            reason: 'اليوم رقم ${i + 1} لازم يكون شغال');
      }
      expect(d.isActiveOn(aug31.add(const Duration(days: 3))), isFalse);
    });

    test('مدة مفتوحة (null) ما بتقفش من نفسها أبداً', () {
      final d = dose('Concor', DayAnchor.breakfast);
      expect(d.durationDays, isNull);
      expect(d.isActiveOn(aug31.add(const Duration(days: 3650))), isTrue);
    });

    test('الجرعة مش شغالة قبل تاريخ البداية', () {
      final d = dose('Concor', DayAnchor.breakfast);
      expect(d.isActiveOn(aug31.subtract(const Duration(days: 1))), isFalse);
    });
  });

  group('التذكير الجاي', () {
    final engine = ScheduleEngine(normalDay);
    final schedules = [
      dose('Antodine', DayAnchor.breakfast, offset: -30), // ٠٧:٠٠
      dose('LINEX', DayAnchor.dinner, offset: 30), // ٢٠:٣٠
      dose('Telfast', DayAnchor.sleep, offset: -15), // ٢٣:١٥
    ];

    test('الساعة ٦ الصبح → الجاي هو ٧:٠٠', () {
      final r = engine.nextReminder(schedules, DateTime(2026, 8, 31, 6));
      expect(hhmm(r!.at), '07:00');
    });

    test('الساعة ٩ الصبح → الجاي هو ٢٠:٣٠', () {
      final r = engine.nextReminder(schedules, DateTime(2026, 8, 31, 9));
      expect(hhmm(r!.at), '20:30');
    });

    test('بعد آخر جرعة → بينتقل لجرعة بكرة', () {
      final r = engine.nextReminder(schedules, DateTime(2026, 8, 31, 23, 30));
      expect(r!.at, DateTime(2026, 9, 1, 7, 0));
    });

    test('لما كل الأدوية تخلص مدتها بيرجّع null', () {
      final finished = [
        dose('Antibiotic', DayAnchor.breakfast, durationDays: 1),
      ];
      final r = engine.nextReminder(
          finished, DateTime(2026, 9, 15), lookaheadDays: 14);
      expect(r, isNull);
    });
  });

  group('الساعة الثابتة — الاستثناء الموثّق', () {
    /// نفس الروتين بس الفطار اتأخر ساعة ونص — زي رمضان أو يوم أجازة.
    final lateBreakfast = normalDay.copyWith(breakfast: MinuteOfDay.hm(9));

    DoseSchedule fixed(String name, int hour, [int minute = 0]) => DoseSchedule(
          id: name,
          medicationName: name,
          timing: FixedTiming(MinuteOfDay.hm(hour, minute)),
          startDate: aug31,
        );

    test('الجرعة الثابتة ما بتتحركش لما الروتين يتغيّر', () {
      final concor = fixed('Concor', 8);

      expect(hhmm(ScheduleEngine(normalDay).resolve(concor, aug31)), '08:00');
      expect(hhmm(ScheduleEngine(lateBreakfast).resolve(concor, aug31)), '08:00');
    });

    test('جرعة المرساة بتتحرك مع نفس التغيير', () {
      final antodine = dose('Antodine', DayAnchor.breakfast, offset: -30);

      expect(hhmm(ScheduleEngine(normalDay).resolve(antodine, aug31)), '07:00');
      expect(
        hhmm(ScheduleEngine(lateBreakfast).resolve(antodine, aug31)),
        '08:30',
      );
    });

    test('ثابتة ومرساة في نفس الدقيقة = تذكير واحد', () {
      // قبل الغدا بنص ساعة = ٢:٠٠ م، والثابتة ٢:٠٠ م
      final reminders = ScheduleEngine(normalDay).remindersForDay(
        [dose('Antodine', DayAnchor.lunch, offset: -30), fixed('Concor', 14)],
        aug31,
      );

      expect(reminders.length, 1);
      expect(reminders.single.isGrouped, isTrue);
      expect(
        reminders.single.doses.map((d) => d.medicationName),
        containsAll(['Antodine', 'Concor']),
      );
    });

    test('ساعة ثابتة أبكر من الصحيان بتاعة آخر اليوم — بعد نص الليل', () {
      // واحد بيصحى ٧ ص، ودوا الساعة ١ ص: ده آخر يومه مش أوله
      final t = ScheduleEngine(normalDay).resolve(fixed('Melatonin', 1), aug31);
      expect(t, DateTime(2026, 9, 1, 1));
    });

    test('الترتيب بالوقت بيخلط النوعين عادي', () {
      final reminders = ScheduleEngine(normalDay).remindersForDay(
        [fixed('Concor', 8), dose('Antodine', DayAnchor.breakfast, offset: -30)],
        aug31,
      );
      expect(reminders.map((r) => hhmm(r.at)), ['07:00', '08:00']);
    });
  });
}
