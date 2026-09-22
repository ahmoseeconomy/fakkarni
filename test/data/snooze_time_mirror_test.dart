// **«هيفكّرك ١٠:٣٠ ص» لازم تبقى اللحظة اللي الإشعار اتجدول عليها فعلاً.**
//
// الشاشة بتقرا [snoozeTimeFrom]، والجدولة بتحصل جوّه
// `ReminderScheduler.snooze`. لو الاتنين اتفرّقوا، الشاشة بتقول ميعاد
// والموبايل بيرن في ميعاد تاني — وده عطل ما بيظهرش في أي اختبار واجهة.
//
// الاختبار ده بيشغّل **الجدولة الحقيقية** ويقارن وقت الإشعار اللي طلع
// باللي الشاشة بتعرضه.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';

class _Sink implements ReminderSink {
  final List<PlannedNotification> scheduled = [];
  @override
  Future<void> schedule(PlannedNotification n) async => scheduled.add(n);
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<Set<int>> pendingIds() async => {};
  @override
  Future<void> ensurePermissions() async {}
}

void main() {
  test('وقت التأجيل اللي بيتعرض هو اللي بيتجدول', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final routines = RoutineRepository(db);
    final patientId = await routines.ensurePatient();
    final sink = _Sink();
    final scheduler = ReminderScheduler(
      routines: routines,
      medications: MedicationRepository(db),
      events: DoseEventRepository(db),
      patientId: patientId,
      sink: sink,
    );

    final now = DateTime(2026, 8, 31, 10, 15);
    final originalAt = DateTime(2026, 8, 31, 7);
    await scheduler.snooze(
      originalAt: originalAt,
      body: 'Concor',
      payload: '',
      now: now,
    );

    final snoozeNotification =
        sink.scheduled.singleWhere((n) => isSnoozeId(n.id));
    expect(snoozeNotification.at, snoozeTimeFrom(now),
        reason: 'الشاشة بتقول حاجة والإشعار بيرن في حاجة تانية');
  });

  test('والمهلة نفسها — ربع ساعة، مكان واحد', () {
    expect(snoozeDelay, const Duration(minutes: 15));
    expect(
      snoozeTimeFrom(DateTime(2026, 8, 31, 10, 15)),
      DateTime(2026, 8, 31, 10, 30),
    );
  });
}
