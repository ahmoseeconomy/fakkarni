// ٢٦ سبتمبر ٢٠٢٦، من الجهاز: دوا اتضاف ١٢:٥٠ بالليل بساعة ثابتة ١٢:٥٢ وبداية
// «النهارده» اتعرض «بكرة ١٢:٥٢ ص» وما رنّش — يوم الروتين كان لسه امبارح.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/routine_day.dart';

import '../features/scan/scan_test_support.dart' show RecordingSink;

final _routine = DayRoutine(
  wake: MinuteOfDay.hm(7, 30),
  breakfast: MinuteOfDay.hm(8),
  lunch: MinuteOfDay.hm(14),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23),
);

void main() {
  group('startDayFor — نقية', () {
    test('١٢:٥٠ بالليل و«النهارده» → يوم الروتين (امبارح بالتقويم)', () {
      final now = DateTime(2026, 9, 26, 0, 50);
      expect(startDayFor(_routine, DateTime(2026, 9, 26), now), DateTime(2026, 9, 25));
    });
    test('١١:٥٠ بالليل → النهارده زي ما هو؛ ١٠ الصبح → زي ما هو', () {
      expect(startDayFor(_routine, DateTime(2026, 9, 25), DateTime(2026, 9, 25, 23, 50)), DateTime(2026, 9, 25));
      expect(startDayFor(_routine, DateTime(2026, 9, 25), DateTime(2026, 9, 25, 10)), DateTime(2026, 9, 25));
    });
    test('تاريخ تاني (بكرة أو بعده) ما بيتلمسش — حتى بعد نص الليل', () {
      final now = DateTime(2026, 9, 26, 0, 50);
      expect(startDayFor(_routine, DateTime(2026, 9, 27), now), DateTime(2026, 9, 27));
      expect(startDayFor(_routine, DateTime(2026, 9, 30), now), DateTime(2026, 9, 30));
    });
  });

  group('من الإضافة للخطة', () {
    late AppDatabase db;
    late RecordingSink sink;
    late int pid;
    late MedicationRepository meds;
    late DateTime clockNow;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final routines = RoutineRepository(db);
      pid = await routines.ensurePatient();
      await routines.saveRoutine(pid, _routine);
      sink = RecordingSink();
      meds = MedicationRepository(db, clock: () => clockNow);
    });
    tearDown(() => db.close());

    Future<Set<DateTime>> plan(DateTime now) async {
      await ReminderScheduler(
        routines: RoutineRepository(db),
        medications: meds,
        events: DoseEventRepository(db),
        patientId: pid,
        sink: sink,
      ).rescheduleAll(now: now);
      return {for (final n in sink.scheduled.values) if (n.kind.name == 'dose') n.at};
    }

    test('١٢:٥٠ بالليل + ساعة ثابتة ١٢:٥٢ + «النهارده» → بترن الليلة دي، مش بكرة', () async {
      clockNow = DateTime(2026, 9, 26, 0, 50);
      await meds.addMedication(
        patientId: pid,
        name: 'Nexium',
        timing: const FixedTiming(MinuteOfDay(52)),
        startDate: DateTime(2026, 9, 26), // «النهارده» بالتقويم
      );
      final at = await plan(clockNow);
      expect(at, contains(DateTime(2026, 9, 26, 0, 52)), reason: 'دقيقتين قدام — لازم تتجدول');
      expect(at.every((t) => t.isAfter(clockNow)), isTrue, reason: 'ولا حاجة في الماضي');
      // و«يومك» (يوم الروتين ٢٥) بتلاقي صفها
      final events = await DoseEventRepository(db).watchDay(DateTime(2026, 9, 25)).first;
      expect(events.map((e) => e.scheduledAt), contains(DateTime(2026, 9, 26, 0, 52)));
    });

    test('١١:٥٠ بالليل + ثابتة ١٢:١٠ → الليلة دي (١٢:١٠ بعد نص الليل)', () async {
      clockNow = DateTime(2026, 9, 25, 23, 50);
      await meds.addMedication(
        patientId: pid,
        name: 'X',
        timing: const FixedTiming(MinuteOfDay(10)),
        startDate: DateTime(2026, 9, 25),
      );
      final at = await plan(clockNow);
      expect(at, contains(DateTime(2026, 9, 26, 0, 10)));
    });

    test('١٠ الصبح + «بعد الفطار» → عادي: أول جرعة بكرة ٨ الصبح، وجرعة النهارده اللي فاتت مش في الماضي', () async {
      clockNow = DateTime(2026, 9, 25, 10);
      await meds.addMedication(
        patientId: pid,
        name: 'Y',
        timing: const AnchorTiming(DayAnchor.breakfast, 0),
        startDate: DateTime(2026, 9, 25),
      );
      final at = await plan(clockNow);
      expect(at.first, DateTime(2026, 9, 26, 8));
      final saved = await meds.activeSchedules(pid);
      expect(saved.single.startDate, DateTime(2026, 9, 25), reason: 'مفيش تحريك بالنهار');
    });

    test('١٢:٥٠ بالليل + «بعد الفطار» → مفيش جرعة في الماضي (فطار امبارح)، وأول جرعة النهارده ٨', () async {
      clockNow = DateTime(2026, 9, 26, 0, 50);
      await meds.addMedication(
        patientId: pid,
        name: 'Z',
        timing: const AnchorTiming(DayAnchor.breakfast, 0),
        startDate: DateTime(2026, 9, 26),
      );
      final at = await plan(clockNow);
      expect(at.first, DateTime(2026, 9, 26, 8));
      expect(at.every((t) => t.isAfter(clockNow)), isTrue);
      // ولا صف «نسيتها؟» لفطار امبارح — active_from بتمنعه
      final yesterday = await DoseEventRepository(db).watchDay(DateTime(2026, 9, 25)).first;
      expect(yesterday, isEmpty);
    });

    test('التعديل بعد نص الليل: ساعة اتغيّرت لـ١٢:٥٢ على دوا بادئ النهارده → الليلة دي', () async {
      clockNow = DateTime(2026, 9, 25, 22);
      final id = await meds.addMedication(
        patientId: pid,
        name: 'E',
        timing: const FixedTiming(MinuteOfDay(21 * 60)),
        startDate: DateTime(2026, 9, 25),
      );
      // ٢٦ الساعة ١٢:٥٠: يوم الروتين ٢٥، وبداية الدوا «النهارده» ٢٦؟ لأ — اتضاف
      // امبارح ببداية ٢٥. الحالة المهمة: دوا اتضاف بالنهار ٢٦ ببداية ٢٦ واتعدّل
      // بالليل.
      clockNow = DateTime(2026, 9, 26, 12);
      final id2 = await meds.addMedication(
        patientId: pid,
        name: 'F',
        timing: const FixedTiming(MinuteOfDay(21 * 60)),
        startDate: DateTime(2026, 9, 26),
      );
      clockNow = DateTime(2026, 9, 27, 0, 50);
      final sched = (await meds.schedulesFor(id2)).single;
      await meds.updateTiming(int.parse(sched.id), const FixedTiming(MinuteOfDay(52)));
      final at = await plan(clockNow);
      expect(at, contains(DateTime(2026, 9, 27, 0, 52)), reason: 'التعديل بالليل بيرن الليلة دي');
      expect(id, isNot(id2));
    });
  });
}
