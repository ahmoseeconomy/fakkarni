import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/proxy_confirmations.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/sync/proxy_pull.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/escalation/repeat_alerts.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../../features/scan/scan_test_support.dart' show RecordingSink;
import '../../support/seeded_clock.dart';

/// **تأكيد الممرض اللي اتسحب = «أخدته» بالظبط (القاعدة ٥).** الصف بيتكتب
/// `taken` باسمه، والإعادات ودرجات السلّم بتاعة اللحظة دي بتتلغي على
/// الموبايل — ومفيش كتابة فوق قرار المريض لو أكّد هو الأول.
class _FakeProxy implements ProxyConfirmRemote {
  final rows = <ProxyConfirmation>[];
  int fetches = 0;

  @override
  Future<void> confirmOnBehalf({required String patientUuid, required String doseEventUuid, required String? actorName}) async {}

  @override
  Future<List<ProxyConfirmation>> fetchForPatient(String patientUuid, {required DateTime since}) async {
    fetches++;
    return rows;
  }
}

final _routine = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

/// الصبح ٧:٠٠ واحدة عدّت من غير تأكيد (٧:٣٠ − ٣٠ = ٧:٠٠ فاتت)، والتانية جاية
final _now = DateTime(2026, 9, 15, 7, 2);

void main() {
  late AppDatabase db;
  late RecordingSink sink;
  late ReminderScheduler scheduler;
  late DoseEventRepository events;
  late RoutineRepository routines;
  late _FakeProxy remote;
  late int patientId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sink = RecordingSink();
    routines = RoutineRepository(db);
    final meds = MedicationRepository(db, clock: seededLongAgo);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, _routine);
    await meds.addMedicationWithDoses(
      patientId: patientId,
      name: 'Concor',
      timings: const [AnchorTiming(DayAnchor.breakfast, -30), AnchorTiming(DayAnchor.dinner, 0)],
      startDate: DateTime(2026, 9, 1),
    );
    events = DoseEventRepository(db);
    scheduler = ReminderScheduler(routines: routines, medications: meds, events: events, patientId: patientId, sink: sink);
    remote = _FakeProxy();
    await scheduler.rescheduleAll(now: _now);
  });

  tearDown(() => db.close());

  ProxyConfirmationPuller puller() => ProxyConfirmationPuller(
        remote: remote,
        routines: routines,
        events: events,
        scheduler: scheduler,
        patientId: patientId,
        clock: () => _now,
      );

  Future<DoseEventRow> morning() async => (await (db.select(db.doseEvents)..orderBy([(t) => OrderingTerm.asc(t.scheduledAt)])).get())
      .firstWhere((e) => e.scheduledAt == DateTime(2026, 9, 15, 7));

  test('تأكيد اتسحب → الصف taken باسم الممرض، والإعادات ودرجات السلّم بتاعة اللحظة اتلغت', () async {
    final event = await morning();
    expect(event.state, DoseState.pending);
    final at = event.scheduledAt;
    // قبل السحب: الإعادات والسلّم بتوع ٧:٠٠ معلّقين
    expect(sink.scheduled.keys, contains(escalationIdFor(at, EscalationRung.first)));
    expect(sink.scheduled.keys, contains(repeatIdFor(at, 0)));
    sink.cancelled.clear();

    remote.rows.add(ProxyConfirmation(doseEventUuid: event.uuid, actorName: 'سارة', confirmedAt: _now));
    expect(await puller().pull(), 1);

    final after = await morning();
    expect(after.state, DoseState.taken);
    expect(after.actedBy, 'سارة');
    expect(after.actedAt, _now);
    // نفس إلغاء «أخدته»: الجرعة والتأجيل والدرجتين والإعادات العشرة
    expect(sink.cancelled, contains(notificationIdFor(at)));
    expect(sink.cancelled, contains(snoozeIdFor(at)));
    for (final rung in EscalationRung.values) {
      expect(sink.cancelled, contains(escalationIdFor(at, rung)), reason: rung.name);
    }
    for (var i = 0; i < maxRepeatsAny; i++) {
      expect(sink.cancelled, contains(repeatIdFor(at, i)), reason: 'إعادة $i');
    }
    // وبعد إعادة الجدولة مفيش ولا واحد منهم معلّق
    expect(sink.scheduled.keys, isNot(contains(escalationIdFor(at, EscalationRung.first))));
    expect(sink.scheduled.keys, isNot(contains(repeatIdFor(at, 0))));
    // والجرعة الجاية (العشا) لسه معلّقة زي ما هي
    expect(sink.scheduled.keys, contains(notificationIdFor(DateTime(2026, 9, 15, 20))));
  });

  test('السحبة نفسها مرتين ما بتكتبش مرتين، والمريض اللي أكّد بنفسه ما بيتكتبش فوقه', () async {
    final event = await morning();
    remote.rows.add(ProxyConfirmation(doseEventUuid: event.uuid, actorName: 'سارة', confirmedAt: _now));
    expect(await puller().pull(), 1);
    expect(await puller().pull(), 0, reason: 'اتأكّدت خلاص');

    // جرعة العشا أكّدها المريض بنفسه قبل السحبة
    final evening = (await db.select(db.doseEvents).get()).firstWhere((e) => e.scheduledAt.hour == 20);
    await events.markTaken(evening.doseScheduleId, evening.routineDay);
    remote.rows.add(ProxyConfirmation(doseEventUuid: evening.uuid, actorName: 'سارة', confirmedAt: _now));
    expect(await puller().pull(), 0);
    final still = (await db.select(db.doseEvents).get()).firstWhere((e) => e.uuid == evening.uuid);
    expect(still.actedBy, isNull, reason: 'قرار المريض بنفسه ما بيتكتبش فوقه');
  });

  test('حدث مش موجود محلياً بيتعدّى، وفشل السحابة ما بيرميش', () async {
    remote.rows.add(ProxyConfirmation(doseEventUuid: 'not-here', actorName: 'سارة', confirmedAt: _now));
    expect(await puller().pull(), 0);
    final broken = _ThrowingProxy();
    final p = ProxyConfirmationPuller(remote: broken, routines: routines, events: events, scheduler: scheduler, patientId: patientId);
    expect(await p.pull(), 0);
  });
}

class _ThrowingProxy implements ProxyConfirmRemote {
  @override
  Future<void> confirmOnBehalf({required String patientUuid, required String doseEventUuid, required String? actorName}) async {}

  @override
  Future<List<ProxyConfirmation>> fetchForPatient(String patientUuid, {required DateTime since}) async =>
      throw StateError('net down');
}
