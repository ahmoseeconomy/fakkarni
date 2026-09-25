import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/repositories/stock_repository.dart';
import 'package:fakkarni/data/services/refill_alerts.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../../support/seeded_clock.dart';

class _Shown implements RefillNotifier {
  final shown = <(int, String)>[];
  @override
  Future<void> show(int id, String title, String body) async => shown.add((id, title));
}

void main() {
  late AppDatabase db;
  late DoseEventRepository events;
  late StockRepository stock;
  late int patientId;
  late int medId;
  late int scheduleId;
  final day = DateTime(2026, 9, 25);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, DayRoutine.fallback);
    final meds = MedicationRepository(db, clock: seededLongAgo);
    medId = await meds.addMedicationWithDoses(
      patientId: patientId,
      name: 'Concor 5mg',
      amountLabel: 'قرص واحد',
      timings: const [AnchorTiming(DayAnchor.breakfast, -30), AnchorTiming(DayAnchor.dinner, 0)],
      startDate: DateTime(2026, 9, 1),
    );
    scheduleId = (await db.select(db.doseSchedules).get()).first.id;
    events = DoseEventRepository(db);
    stock = StockRepository(db);
    // صف «لسه» لكل جرعة في اليوم — نفس اللي «يومك» بتنزّله
    for (final (i, s) in (await db.select(db.doseSchedules).get()).indexed) {
      await db.into(db.doseEvents).insert(DoseEventsCompanion.insert(
            doseScheduleId: s.id,
            routineDay: day,
            scheduledAt: DateTime(2026, 9, 25, 7 + i * 12),
            state: DoseState.pending,
          ));
    }
  });
  tearDown(() => db.close());

  Future<double> quantity() async => (await stock.rowFor(medId))!.quantity;

  test('من غير مخزون متكتب: التأكيد ما بيعملش حاجة، ومفيش صف بيتخترع', () async {
    await events.markTaken(scheduleId, day);
    expect(await stock.rowFor(medId), isNull);
  });

  test('«اتاخدت» بينقّص بالجرعة، والإلغاء بيرجّعها', () async {
    await stock.setQuantity(medId, 10);
    await events.markTaken(scheduleId, day);
    expect(await quantity(), 9);
    await events.markTaken(scheduleId, day);
    expect(await quantity(), 9, reason: 'نفس الجرعة مرتين = مرة');
    await events.undoTaken(scheduleId, day);
    expect(await quantity(), 10);
    final row = (await db.select(db.doseEvents).get()).firstWhere((e) => e.doseScheduleId == scheduleId);
    expect(row.state, DoseState.pending);
  });

  test('«اتاخدت» وبعدين «مش هاخده» = إلغاء — المخزون بيرجع', () async {
    await stock.setQuantity(medId, 10);
    await events.markTaken(scheduleId, day);
    await events.markSkipped(scheduleId, day);
    expect(await quantity(), 10);
  });

  test('الفايتة والمتخطّية ما بتنقّصش', () async {
    await stock.setQuantity(medId, 10);
    await events.sweepMissed(now: DateTime(2026, 9, 26, 12));
    expect(await quantity(), 10);
    await events.markSkipped(scheduleId, day);
    expect(await quantity(), 10);
  });

  test('عمره ما بينزل تحت الصفر، ونص قرص بينقّص نص', () async {
    await (db.update(db.medications)..where((t) => t.id.equals(medId)))
        .write(const MedicationsCompanion(amountLabel: Value('نص قرص')));
    await stock.setQuantity(medId, 0.25);
    await events.markTaken(scheduleId, day);
    expect(await quantity(), 0);
    await stock.setQuantity(medId, 3);
    final second = (await db.select(db.doseSchedules).get()).last.id;
    await events.markTaken(second, day);
    expect(await quantity(), 2.5);
  });

  test('تأكيد الممرض بينقّص زي تأكيد المريض', () async {
    await stock.setQuantity(medId, 10);
    final row = (await db.select(db.doseEvents).get()).firstWhere((e) => e.doseScheduleId == scheduleId);
    await events.confirmByProxy(doseEventUuid: row.uuid, actorName: 'سارة', confirmedAt: DateTime(2026, 9, 25, 7));
    expect(await quantity(), 9);
  });

  test('شاشة القفل: الصف الأول، والمخزون مجاملة بعد flushStock', () async {
    await stock.setQuantity(medId, 10);
    await events.confirmDose(
      doseScheduleId: scheduleId,
      routineDay: day,
      scheduledAt: DateTime(2026, 9, 25, 7),
      state: DoseState.taken,
    );
    expect(await quantity(), 10, reason: 'المخزون مش جوّه وعد الصف');
    await events.flushStock();
    expect(await quantity(), 9);
  });

  test('فاضله كام يوم من الجدول (جرعتين في اليوم × قرص)', () async {
    await stock.setQuantity(medId, 9);
    final view = (await stock.all(patientId)).single;
    expect((view.dosesPerDay, view.amount, view.daysLeft, view.isLow), (2, 1.0, 4, true));
    await stock.setQuantity(medId, 20);
    expect((await stock.all(patientId)).single.isLow, isFalse);
  });

  group('تنبيه «قرب يخلص»', () {
    test('أول ما يعدّي الحد مرة، وبعدها كل ٣ أيام، ومش بالليل، والشراء بيرجّع الدورة', () async {
      final shown = _Shown();
      final alerts = RefillAlerts(stock: stock, patientId: patientId, notifier: shown);
      await stock.setQuantity(medId, 20);
      expect(await alerts.sync(now: DateTime(2026, 9, 25, 10)), 0, reason: 'مش قرب يخلص');

      await stock.setQuantity(medId, 8); // ٤ أيام
      expect(await alerts.sync(now: DateTime(2026, 9, 25, 10)), 1);
      expect(shown.shown.single, (refillIdFor(medId), 'Concor 5mg فاضله ٤ أيام'));
      expect(await alerts.sync(now: DateTime(2026, 9, 26, 10)), 0, reason: 'مش قبل ٣ أيام');
      expect(await alerts.sync(now: DateTime(2026, 9, 28, 23)), 0, reason: 'مش بالليل');
      expect(await alerts.sync(now: DateTime(2026, 9, 28, 10)), 1, reason: 'بعد ٣ أيام وهو لسه قرب يخلص');

      await stock.restock(medId, 30); // اشترى
      expect(await alerts.sync(now: DateTime(2026, 9, 29, 10)), 0);
      expect((await stock.rowFor(medId))!.notifiedAt, isNull, reason: 'الدورة بتبدأ من الأول');
      await stock.setQuantity(medId, 4);
      expect(await alerts.sync(now: DateTime(2026, 9, 29, 11)), 1, reason: 'عدّى الحد تاني = تنبيه على طول');
    });

    test('الرقم في نطاقه وبرّه نطاقات الجرعات وإعادة الجدولة', () {
      final id = refillIdFor(medId);
      expect(isRefillId(id), isTrue);
      expect(isDoseId(id) || isRescheduledId(id) || isNurseId(id), isFalse);
    });
  });
}
