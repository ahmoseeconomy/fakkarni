import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/notifications/notification_service.dart'
    show NotificationActions;
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/notification_actions.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final aug31 = DateTime(2026, 8, 31);
final aug31at6 = DateTime(2026, 8, 31, 6);

/// جهاز وهمي بيفتكر اللي متجدول عليه — زي iOS بالظبط.
class DeviceSink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];

  @override
  Future<void> schedule(PlannedNotification n) async => scheduled[n.id] = n;
  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();
  @override
  Future<void> ensurePermissions() async {}

  /// تذكيرات الجرعات بس — السلّم بيتعدّ لوحده.
  Map<int, PlannedNotification> get doses => {
        for (final e in scheduled.entries)
          if (isDoseId(e.key)) e.key: e.value,
      };

  DateTime get coverageEnd => scheduled.values
      .where((p) => isDoseId(p.id))
      .map((p) => p.at)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

void main() {
  late AppDatabase db;
  late DeviceSink device;
  late int patientId;

  /// «التطبيق مقفول»: كل صحوة بتبني خدماتها من الصفر فوق نفس القاعدة،
  /// من غير أي widget — زي الـisolate اللي النظام بيصحّيه.
  NotificationActionHandler wake() {
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
    final events = DoseEventRepository(db);
    return NotificationActionHandler(
      routines: routines,
      medications: meds,
      events: events,
      scheduler: ReminderScheduler(
        routines: routines,
        medications: meds,
        events: events,
        patientId: patientId,
        sink: device,
      ),
      patientId: patientId,
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    device = DeviceSink();
    final routines = RoutineRepository(db);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, normalDay);

    // مريض تقيل: ٤ أدوية × ٣ جرعات = ١٢ في اليوم → السقف بيتملا في ٤ أيام
    final meds = MedicationRepository(db);
    for (var i = 0; i < 4; i++) {
      final id = await meds.addMedication(
        patientId: patientId,
        name: 'Med$i',
        timing: AnchorTiming(DayAnchor.breakfast, -30 + i * 5),
        startDate: aug31,
        amountLabel: 'قرص',
      );
      await meds.addDoseSchedule(id,
          timing: AnchorTiming(DayAnchor.lunch, -30 + i * 5), startDate: aug31);
      await meds.addDoseSchedule(id,
          timing: AnchorTiming(DayAnchor.dinner, 30 + i * 5), startDate: aug31);
    }

    // آخر مرة التطبيق اتفتح: النافذة اتجدولت وبعدها المريض ما فتحوش تاني
    await wake().scheduler.rescheduleAll(now: aug31at6);
  });

  tearDown(() => db.close());

  /// الإشعار اللي هيرن ٧:٠٠ ص — حمولته زي ما اتجدولت.
  PlannedNotification firstReminder() => device.doses.values
      .reduce((a, b) => a.at.isBefore(b.at) ? a : b);

  test('«أخدته» من الإشعار والتطبيق مقفول: الجرعة اتسجّلت والنافذة اتمدّت',
      () async {
    final first = firstReminder();
    expect(first.at, DateTime(2026, 8, 31, 7));
    expect(device.doses.length, maxPendingReminders);
    final endBefore = device.coverageEnd;
    expect(await db.select(db.doseEvents).get(), isEmpty,
        reason: '«يومك» ما اتفتحتش — مفيش صف حدث لسه');

    // المريض داس «أخدته» على شاشة القفل الساعة ٦:٥٥
    await wake().handle(
      NotificationActions.taken,
      first.payload,
      now: DateTime(2026, 8, 31, 6, 55),
    );

    // اليوم كله اتنزّل كأحداث (زي ما «يومك» بتعمل)، والجرعة دي بس «اتاخدت»
    final events = await db.select(db.doseEvents).get();
    final taken = events.where((e) => e.state == DoseState.taken).toList();
    expect(taken.length, 1);
    expect(taken.single.routineDay, aug31);
    expect(taken.single.scheduledAt, first.at);

    expect(device.cancelled, contains(first.id));
    expect(device.cancelled, contains(snoozeIdFor(first.at)));
    expect(device.doses.containsKey(first.id), isFalse,
        reason: 'اتأكدت بدري وما رجعتش');
    expect(device.doses.length, maxPendingReminders);
    expect(device.coverageEnd.isAfter(endBefore), isTrue,
        reason: 'التغطية اتمدّت من غير ما التطبيق يتفتح');
  });

  test('كل تأكيد بيجدد التغطية — يوم ٥ ما بيبقاش صامت', () async {
    var now = DateTime(2026, 8, 31, 6, 55);
    final endAtStart = device.coverageEnd;

    // أسبوع كامل من التأكيدات من شاشة القفل، من غير ولا فتحة للتطبيق
    for (var i = 0; i < 7 * 12; i++) {
      final next = firstReminder();
      now = next.at.subtract(const Duration(minutes: 2));
      await wake().handle(NotificationActions.taken, next.payload, now: now);
      expect(device.doses.length, maxPendingReminders);
      expect(
        device.scheduled.length + snoozePendingSlack,
        lessThanOrEqualTo(iosPendingLimit),
      );
    }

    expect(device.coverageEnd.isAfter(endAtStart.add(const Duration(days: 6))),
        isTrue);
    expect(firstReminder().at.isAfter(now), isTrue, reason: 'دايماً فيه تذكير جاي');
  });

  test('«فكّرني بعدين» من الإشعار: تأجيل في نطاقه، والجرعة لسه معلّقة',
      () async {
    final first = firstReminder();

    await wake().handle(
      NotificationActions.snooze,
      first.payload,
      now: DateTime(2026, 8, 31, 7, 1),
    );

    final snooze = device.scheduled[snoozeIdFor(first.at)];
    expect(snooze, isNotNull);
    expect(snooze!.at, DateTime(2026, 8, 31, 7, 16));
    expect(snooze.body, first.body);
    expect(snooze.payload, first.payload);
    expect(
      (await db.select(db.doseEvents).get())
          .where((e) => e.state == DoseState.taken),
      isEmpty,
    );
  });

  test('زرار مش معروف أو حمولة بايظة → ولا حاجة بتتغيّر ومفيش رمي', () async {
    final before = Map.of(device.scheduled);

    await wake().handle('dismiss', firstReminder().payload);
    await wake().handle(NotificationActions.taken, 'مش json');
    await wake().handle(NotificationActions.taken, null);

    expect(device.scheduled, before);
    expect(device.cancelled, isEmpty);
    expect(await db.select(db.doseEvents).get(), isEmpty);
  });

  test('إشعار لدوا اتوقف بعد الجدولة → بيتجاهل بهدوء', () async {
    final first = firstReminder();
    final meds = MedicationRepository(db);
    for (final m in await meds.watchMedications(patientId).first) {
      await meds.stopMedication(m.id);
    }

    await wake().handle(NotificationActions.taken, first.payload);

    expect(await db.select(db.doseEvents).get(), isEmpty);
  });
  test('«أخدته» من درجة التصعيد على شاشة القفل: بتسجّل وبتلغي السلّم كله',
      () async {
    final first = firstReminder();
    final rung = device.scheduled[escalationIdFor(first.at, EscalationRung.first)]!;
    expect(rung.at, DateTime(2026, 8, 31, 7, 15));
    expect(rung.payload, first.payload, reason: 'نفس الحمولة → نفس المعالجة');

    // الجرعة رنّت ٧:٠٠ وعدّت، ودرجة ٧:١٥ رنّت، وهو داس «أخدته» عليها ٧:٢٠
    await wake().handle(NotificationActions.taken, rung.payload,
        now: DateTime(2026, 8, 31, 7, 20));

    final events = await db.select(db.doseEvents).get();
    expect(events.where((e) => e.state == DoseState.taken).length, 1);
    expect(device.cancelled, contains(escalationIdFor(first.at, EscalationRung.first)));
    expect(device.cancelled, contains(escalationIdFor(first.at, EscalationRung.second)));
    expect(device.scheduled.containsKey(escalationIdFor(first.at, EscalationRung.second)), isFalse,
        reason: 'القاعدة الخامسة: درجة ٧:٣٠ ما ترنّش على حاجة اتعملت');
  });

  test('صحوة بعد المهلة من غير أي زرار: الجرعة اللي فاتت «اتنست» — لا لوم ولا مسح',
      () async {
    final first = firstReminder();
    final second = device.doses.values
        .where((p) => p.at.isAfter(first.at))
        .reduce((a, b) => a.at.isBefore(b.at) ? a : b);

    // أكّد الجرعة التانية (٧:٠٥) الساعة ٧:٥٠ بس، من غير ما يلمس الأولى
    // (٧:٠٠) — صحوة الخلفية. ٧:٠٠ عدّت المهلة؛ ٧:١٠ و٧:١٥ لسه جوّاها.
    await wake().handle(NotificationActions.taken, second.payload,
        now: DateTime(2026, 8, 31, 7, 50));

    final events = await db.select(db.doseEvents).get();
    final missed = events.where((e) => e.state == DoseState.missed).toList();
    expect(missed.length, 1);
    expect(missed.single.scheduledAt, first.at);
    expect(missed.single.actedAt, isNull);
  });

}
