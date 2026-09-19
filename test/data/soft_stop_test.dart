import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/services/reminder_plan.dart' show isDoseId;
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/export/export_document.dart';
import 'package:fakkarni/features/records/record_kinds.dart' show RecordPeriod;

import '../features/scan/scan_test_support.dart';

/// الإيقاف الناعم (نسخة ١٦): الدوا بيتوقف أو بيتشال — **ومفيش مسح**.
///
/// المسح الحقيقي ممنوع لسببين متلازمين: المزامنة بترفع بس (دين ١)، و
/// `dose_events` بتتمسح بالـcascade. يعني الجهاز ينسى والسحابة تفضل تنبّه
/// الابن على جرعة مابقتش موجودة — وموبايل الأب مش قادر يصحّح صف مسحه.
void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  /// ٣١ أغسطس: الفطار ٧:٣٠ والعشا ٨ م.
  final today = aug31;
  final noon = DateTime(2026, 8, 31, 12);

  Future<int> seed({String name = 'Concor 5mg'}) => h.meds.addMedicationWithDoses(
        patientId: h.services.patientId,
        name: name,
        timings: const [AnchorTiming(DayAnchor.breakfast, 0), AnchorTiming(DayAnchor.dinner, 0)],
        startDate: today,
        amountLabel: 'قرص',
      );

  /// بينزّل أحداث اليوم ويجدول — زي ما `rescheduleAll` بتعمل.
  Future<void> materialiseAndSchedule() async {
    await h.services.scheduler.rescheduleAll(now: noon);
  }

  Future<List<DoseEventRow>> events() => h.db.select(h.db.doseEvents).get();

  group('الإيقاف', () {
    test('بيعلّم الجرعات الجاية «اتغيّرت القاعدة» وبيسيب اللي فات زي ما هو', () async {
      final id = await seed();
      await materialiseAndSchedule();

      // الفطار ٧:٣٠ عدّى، والعشا ٨ م لسه جاي
      final before = await events();
      expect(before.where((e) => e.state == DoseState.pending).length, greaterThanOrEqualTo(2));
      // نعلّم اللي فات «اتاخد» عشان نتأكد إنه ما بيتلمسش
      final past = before.firstWhere((e) => e.scheduledAt.isBefore(noon));
      await (h.db.update(h.db.doseEvents)..where((t) => t.id.equals(past.id)))
          .write(const DoseEventsCompanion(state: Value(DoseState.taken)));

      await h.meds.stopMedication(id, now: noon);

      final after = await events();
      expect(
        after.where((e) => e.scheduledAt.isAfter(noon) && e.state == DoseState.superseded),
        isNotEmpty,
        reason: 'الجاي بيتعلّم — فالسيرفر ما يصعّدش عليه',
      );
      expect(
        after.firstWhere((e) => e.id == past.id).state,
        DoseState.taken,
        reason: 'اللي فات تاريخ — ما بيتلمسش',
      );
      expect(after.length, before.length, reason: 'ولا صف اتمسح');
    });

    test('بيلغي تذكيرات الجرعات الموقوفة', () async {
      final id = await seed();
      await materialiseAndSchedule();
      expect(h.sink.scheduled.keys.where(isDoseId), isNotEmpty);

      await h.meds.stopMedication(id, now: noon);
      await materialiseAndSchedule();

      expect(h.sink.scheduled.keys.where(isDoseId), isEmpty, reason: 'مفيش تذكير لدوا موقوف');
    });

    test('«رجّعه تاني» بيرجّع الجدولة', () async {
      final id = await seed();
      await h.meds.stopMedication(id, now: noon);
      await materialiseAndSchedule();
      expect(h.sink.scheduled.keys.where(isDoseId), isEmpty);

      await h.meds.resumeMedication(id);
      await materialiseAndSchedule();

      expect(h.sink.scheduled.keys.where(isDoseId), isNotEmpty, reason: 'رجع للخدمة');
      expect((await h.db.select(h.db.medications).get()).single.stoppedAt, isNull);
    });
  });

  group('الشيل بيختفي من القرايات الستة', () {
    late int removed;

    setUp(() async {
      removed = await seed(name: 'Concor 5mg');
      await seed(name: 'Telfast 180 mg');
      await materialiseAndSchedule();
      await h.meds.removeMedication(removed, now: noon);
    });

    test('١ — قايمة الأدوية: مش في الشغّالة ولا في «موقوفة»', () async {
      final all = await h.meds.watchAllSummaries(h.services.patientId).first;
      expect(all.map((m) => m.medication.name), ['Telfast 180 mg']);
    });

    test('٢ — شاشة اليوم: مفيش أحداثه', () async {
      final day = await h.services.events.watchDay(today).first;
      expect(day.map((e) => e.medicationName).toSet(), {'Telfast 180 mg'});
    });

    test('٣ — شريط الأسبوع (التقويم): مفيش أحداثه', () async {
      final week = await h.services.events
          .watchBetween(today, DateTime(2026, 9, 7))
          .first;
      expect(week.map((e) => e.medicationName).toSet(), {'Telfast 180 mg'});
    });

    test('٤ — ملف التصدير: مش في «الأدوية والجرعات»', () async {
      final doc = await collectExport(
        h.db,
        patientId: h.services.patientId,
        options: const ExportOptions(period: RecordPeriod.all, visible: {ExportSection.medications}),
        now: noon,
      );
      final lines = doc.blocks.singleWhere((b) => b.section == ExportSection.medications).lines;
      expect(lines.join(' '), contains('Telfast 180 mg'));
      expect(lines.join(' '), isNot(contains('Concor 5mg')));
    });

    test('٥ — الجدولة: مفيش تذكير ليه', () async {
      h.sink.scheduled.clear();
      await materialiseAndSchedule();
      final names = await h.meds.activeSchedules(h.services.patientId);
      expect(names.map((s) => s.medicationName).toSet(), {'Telfast 180 mg'});
    });

    test('٦ — شاشة الابن: الاستعلام بيفلتر المتشال (حارس على نص الاستعلام)', () {
      // الاستعلام ده بيتنفّذ في السحابة، فما ينفعش يتجرّب هنا — الحارس على
      // شكله، زي حارس قناة الدفع وحارس مهلة السيرفر.
      final source = File('lib/data/care/supabase_caregiver_remote.dart').readAsStringSync();
      expect(source, contains(".isFilter('removed_at', null)"));
      expect(source, contains(".isFilter('dose_schedules.medications.removed_at', null)"));
      expect(source, contains("if ((s as Map)['stopped_at'] == null)"),
          reason: 'الجرعة الموقوفة مش قاعدة شغّالة عند الابن');
    });

    test('الأحداث القديمة بتفضل في القاعدة — تاريخ، مش مسح', () async {
      final rows = await events();
      final schedules = await (h.db.select(h.db.doseSchedules)
            ..where((t) => t.medicationId.equals(removed)))
          .get();
      expect(schedules, isNotEmpty, reason: 'صف الجرعة مكانه');
      final ids = schedules.map((s) => s.id).toSet();
      expect(rows.where((e) => ids.contains(e.doseScheduleId)), isNotEmpty, reason: 'أحداثه مكانها');
    });
  });
}
