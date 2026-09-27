import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/data/services/medication_save_service.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/routine_day.dart';

import '../../features/scan/scan_test_support.dart';
import '../../support/seeded_clock.dart';

/// شبكة الأمان عند الفتح والرجوع: إعادة الجدولة بتقارن المتوقَّع بالمعلّق،
/// بترجّع الناقص وبتلغي اليتيم — وبتعمل كده مرة واحدة في المرة.

/// sink بيقدر يوقّف أول `pendingIds()` لحد ما الاختبار يسيبه — عشان نحط
/// جولة في النص بالظبط زي ما بيحصل على الجهاز.
class _GateSink extends RecordingSink {
  Completer<void>? gate;
  Completer<void>? reached;
  @override
  Future<Set<int>> pendingIds() async {
    final g = gate;
    if (g != null) {
      gate = null;
      reached?.complete();
      await g.future;
    }
    return super.pendingIds();
  }
}

void main() {
  late AppDatabase db;
  late MedicationRepository meds;
  late DoseEventRepository events;
  late _GateSink sink;
  late ReminderScheduler scheduler;
  late int patientId;

  // الساعة ١٠ الصبح — الجرعة ٩ بالليل لسه قدام
  final now = DateTime(2026, 9, 27, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    meds = MedicationRepository(db, clock: seededLongAgo);
    events = DoseEventRepository(db);
    sink = _GateSink();
    patientId = await PatientRepository(db).ensurePatient();
    scheduler = ReminderScheduler(medications: meds, events: events, patientId: patientId, sink: sink);
  });
  tearDown(() => db.close());

  Future<int> addAt(int hour, {String name = 'Concor'}) => meds.addMedication(
        patientId: patientId,
        name: name,
        timing: FixedTiming(MinuteOfDay.hm(hour)),
        startDate: DateTime(2026, 9, 1),
      );

  Map<int, DateTime> snapshot() => {for (final e in sink.scheduled.entries) e.key: e.value.at};

  test('تذكير اتمسح من المعلّق — إعادة الجدولة بترجّعه وبتقول إنها صلّحت', () async {
    await addAt(21);
    await scheduler.rescheduleAll(now: now);
    final before = snapshot();
    final dose = before.keys.where(isDoseId).toList()..sort();
    // الجرعة التانية (بكرة) اختفت — فجوة جوّه المدى المتغطّي
    sink.scheduled.remove(dose[1]);

    await scheduler.rescheduleAll(now: now);
    final report = scheduler.lastRepair;

    expect(snapshot(), before);
    expect(report.missing, 1);
    expect(report.orphans, 0);
  });

  test('مرتين ورا بعض = نفس القايمة بالظبط، ومفيش إصلاح في التانية', () async {
    await addAt(9);
    await addAt(21, name: 'Telfast');
    await scheduler.rescheduleAll(now: now);
    final first = scheduler.lastRepair;
    final once = snapshot();
    await scheduler.rescheduleAll(now: now);
    final second = scheduler.lastRepair;

    expect(snapshot(), once);
    expect(first.missing, 0, reason: 'أول جدولة مش فجوة');
    expect(second, (missing: 0, orphans: 0));
  });

  test('يتيم في نطاق الجرعات بيتلغي — والتأجيل ما بيتلمسش', () async {
    await addAt(21);
    await scheduler.rescheduleAll(now: now);
    final orphanAt = DateTime(2026, 9, 28, 3, 17);
    final orphan = notificationIdFor(orphanAt);
    await sink.schedule(PlannedNotification(id: orphan, at: orphanAt, title: '', body: '', payload: ''));
    // «فكّرني بعدين» على جرعة الصبح
    final snoozeAt = DateTime(2026, 9, 27, 10, 15);
    await scheduler.snooze(originalAt: DateTime(2026, 9, 27, 9), body: 'Concor', payload: 'p', now: now);
    final snooze = snoozeIdFor(DateTime(2026, 9, 27, 9));

    await scheduler.rescheduleAll(now: now);
    final report = scheduler.lastRepair;

    expect(sink.scheduled.containsKey(orphan), isFalse);
    expect(report.orphans, 1);
    expect(sink.scheduled[snooze]?.at, snoozeAt, reason: 'إعادة الجدولة لمست التأجيل');
  });

  test('جرعة اتاخدت ما بترجعش — حتى لو ميعادها لسه قدام', () async {
    await addAt(21);
    final day = routineDayOf(now);
    await scheduler.rescheduleAll(now: now);
    final todayId = notificationIdFor(DateTime(2026, 9, 27, 21));
    expect(sink.scheduled, contains(todayId));

    final schedule = (await meds.activeSchedules(patientId)).single;
    await events.markTaken(int.parse(schedule.id), day);
    await scheduler.rescheduleAll(now: now);

    expect(sink.scheduled.containsKey(todayId), isFalse);
    expect(sink.scheduled, contains(notificationIdFor(DateTime(2026, 9, 28, 21))));
  });

  test('جولتين مع بعض ما بيلغوش تذكيرات دوا اتضاف في النص', () async {
    // الحفظ بيجدول بساعة الجهاز — فالاختبار ده كله على ساعة الجهاز
    final t = DateTime.now();
    final tomorrowNine = DateTime(t.year, t.month, t.day + 1, 21);
    await addAt(9);

    // جولة (أ) قرت الجداول قبل الدوا الجديد، ووقفت عند قراية المعلّق —
    // زي الرجوع للمقدمة بعد الكاميرا، أو إصلاح فحص السلامة
    final gate = Completer<void>();
    sink.gate = gate;
    sink.reached = Completer<void>();
    final a = scheduler.rescheduleAll();
    await sink.reached!.future;

    // في النص: «ضيف دوا» بيحفظ ويجدول
    final saves = MedicationSaveService(medications: meds, scheduler: scheduler);
    final saved = saves.add(
      patientId: patientId,
      name: 'Telfast',
      timings: [FixedTiming(MinuteOfDay.hm(21))],
      startDate: DateTime(2026, 9, 1),
    );
    await pumpEventQueue();
    gate.complete();
    await Future.wait([a, saved]);

    expect(sink.scheduled, contains(notificationIdFor(tomorrowNine)),
        reason: 'جولة قديمة لغت تذكير الدوا الجديد');
  });
}
