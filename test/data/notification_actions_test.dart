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
import 'package:fakkarni/data/sync/sync_service.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/escalation/repeat_alerts.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import '../support/seeded_clock.dart';

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
    trace.add('cancel');
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

/// سجل مرتّب لكل حاجة بتحصل — الترتيب هو اللي بنختبره، مش بس النتيجة.
final trace = <String>[];

/// سحابة وهمية بتقدر تقع أو تعلّق — زي شبكة مصرية في صحوة خلفية.
class FakeRemote implements SyncRemote {
  final List<String> tables = [];
  bool fail = false;
  Duration? hangFor;

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    trace.add('upsert:$table');
    tables.add(table);
    if (hangFor != null) await Future<void>.delayed(hangFor!);
    if (fail) throw Exception('السحابة وقعت');
  }

  @override
  Future<void> deleteByUuid(String table, List<String> uuids) async {
    trace.add('delete:$table');
    if (fail) throw Exception('السحابة وقعت');
  }
}

void main() {
  late AppDatabase db;
  late DeviceSink device;
  late FakeRemote remote;
  late bool signedIn;
  late int patientId;

  /// «التطبيق مقفول»: كل صحوة بتبني خدماتها من الصفر فوق نفس القاعدة،
  /// من غير أي widget — زي الـisolate اللي النظام بيصحّيه.
  NotificationActionHandler wake({Duration? pushTimeout}) {
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db, clock: seededLongAgo);
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
      // زي الـisolate بالظبط: من غير start() — مفيش مستمعين ولا مؤقّتات.
      // ودالة، مش خدمة جاهزة: التهيئة نفسها وراء الوعد.
      cloud: () async => SyncService(
        db: db,
        remote: remote,
        hasSession: () => signedIn,
        localWrites: const Stream.empty(),
        backgroundTimeout: pushTimeout ?? backgroundPushTimeout,
      ),
    );
  }

  /// الجهاز اتربط: صف المريض اترفع من شاشة الربط وconfirmLinked علّمته.
  Future<void> link() => SyncService(
        db: db,
        remote: remote,
        hasSession: () => signedIn,
        localWrites: const Stream.empty(),
      ).confirmLinked();

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    device = DeviceSink();
    remote = FakeRemote();
    signedIn = true;
    trace.clear();
    final routines = RoutineRepository(db);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, normalDay);

    // مريض تقيل: ٤ أدوية × ٣ جرعات = ١٢ في اليوم → السقف بيتملا في ٤ أيام
    final meds = MedicationRepository(db, clock: seededLongAgo);
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

  group('الوعد قبل أي حاجة سحابية أو قناة — ترتيب صحوة شاشة القفل', () {
    // على iOS الصحوة دي مالهاش مهلة مضمونة: الإضافة بترجّع
    // completionHandler قبل ما أول سطر دارت يشتغل، وما بتاخدش
    // beginBackgroundTask. فأي حاجة بتتعمل قبل الوعد بتتصرف من وقته.
    //
    // ده كان الترتيب الحقيقي في bootstrap: تهيئة إشعارات ← تهيئة سحابة
    // (لحد ثانيتين) ← بناء الخدمات ← **وبعدين** تسجيل الجرعة. على آيفون
    // مقفول، ده تأكيد من شاشة القفل ما بيتسجّلش ودرجات السلّم بتفضل
    // مسلّحة — راجل خد دواه وابنه بيتصحّى عليه.

    NotificationActionHandler ordered({
      Future<SyncService?> Function()? cloud,
    }) {
      final routines = RoutineRepository(db);
      final meds = MedicationRepository(db, clock: seededLongAgo);
      return NotificationActionHandler(
        routines: routines,
        medications: meds,
        events: _TracingEvents(DoseEventRepository(db)),
        scheduler: ReminderScheduler(
          routines: routines,
          medications: meds,
          events: DoseEventRepository(db),
          patientId: patientId,
          sink: device,
        ),
        patientId: patientId,
        prepareNotifications: () async => trace.add('prepareNotifications'),
        cloud: cloud ??
            () async {
              trace.add('cloudInit');
              return SyncService(
                db: db,
                remote: remote,
                hasSession: () => signedIn,
                localWrites: const Stream.empty(),
              );
            },
      );
    }

    test('الجرعة بتتكتب قبل تهيئة الإشعارات وقبل أول إلغاء', () async {
      final first = firstReminder();
      trace.clear();

      await ordered().handle(NotificationActions.taken, first.payload);

      expect(trace.first, 'confirmDose',
          reason: 'أي نداء قناة قبل الصف بياكل من وقت الصف نفسه');
      expect(trace.indexOf('prepareNotifications'),
          greaterThan(trace.indexOf('confirmDose')));
      expect(trace.indexOf('cancel'),
          greaterThan(trace.indexOf('prepareNotifications')),
          reason: 'الإلغاء بيمرّ على الإضافة، فالتهيئة لازم تسبقه');
    });

    test('تهيئة السحابة ما بتحصلش غير بعد آخر إلغاء', () async {
      final first = firstReminder();
      await link();
      trace.clear();

      await ordered().handle(NotificationActions.taken, first.payload);

      final cloudAt = trace.indexOf('cloudInit');
      expect(cloudAt, isNot(-1));
      expect(cloudAt, greaterThan(trace.lastIndexOf('cancel')),
          reason: 'القاعدة الخامسة: مفيش شبكة قدام إلغاء درجة لسه ما رنّتش');
      expect(trace.indexWhere((t) => t.startsWith('upsert:')),
          greaterThan(cloudAt),
          reason: 'والرفع بعد التهيئة طبعاً');
    });

    test('تهيئة السحابة وقعت → التأكيد مسجّل والإلغاء اتعمل', () async {
      final first = firstReminder();
      trace.clear();

      // بيكمّل عادي: التهيئة مجاملة زيها زي الرفع
      await ordered(cloud: () async => throw Exception('الشبكة ماتت'))
          .handle(NotificationActions.taken, first.payload);

      expect(trace, contains('confirmDose'));
      expect(trace, contains('cancel'));
      final taken = (await db.select(db.doseEvents).get())
          .where((e) => e.state == DoseState.taken);
      expect(taken, isNotEmpty);
      expect(remote.tables, isEmpty, reason: 'مفيش خدمة، يبقى مفيش رفع');
    });

    test('«فكّرني بعدين» بيجهّز الإشعارات قبل ما يجدول التأجيل', () async {
      final first = firstReminder();
      trace.clear();

      await ordered().handle(NotificationActions.snooze, first.payload);

      expect(trace.first, 'prepareNotifications',
          reason: 'التأجيل نفسه إشعار — هو ده الوعد كله هنا');
    });
  });

  group('تأكيد فشل عمره ما يشبه تأكيد نجح', () {
    // الإشعار بيختفي من شاشة القفل سواء الكتابة نجحت أو وقعت — النظام
    // بيشيله ساعة ما المستخدم يدوس، مش لما إحنا نخلص. فلو بلعنا الخطأ،
    // المريض بيمشي وهو فاكر إنه أكّد والجرعة مش مسجّلة عند حد.
    //
    // ده اللي حصل بالظبط مع `database is locked`: `materializeDay` رمت،
    // الـcatch اللي بره سجّلت، والمستخدم ما شافش أي فرق.

    test('الكتابة وقعت → المعالج بيرمي، ما بيرجعش عادي', () async {
      final first = firstReminder();
      final handler = wake();
      final broken = NotificationActionHandler(
        routines: handler.routines,
        medications: handler.medications,
        // القاعدة اتقفلت في وشنا
        events: _ThrowingEvents(handler.events),
        scheduler: handler.scheduler,
        patientId: patientId,
      );

      await expectLater(
        broken.handle(NotificationActions.taken, first.payload),
        throwsA(isA<Exception>()),
        reason: 'لو رجع عادي، الفشل مش هيبان في أي لوج ولا لأي حد',
      );
    });

    test('مدّ النافذة وقع → التأكيد بيفضل مسجّل والمعالج بيكمّل', () async {
      final first = firstReminder();
      final handler = wake();
      final flaky = NotificationActionHandler(
        routines: handler.routines,
        medications: handler.medications,
        events: handler.events,
        scheduler: _ThrowingScheduler(
          routines: RoutineRepository(db),
          medications: MedicationRepository(db, clock: seededLongAgo),
          events: DoseEventRepository(db),
          patientId: patientId,
          sink: device,
        ),
        patientId: patientId,
      );

      // بيكمّل: المجاملة مسموح لها تفشل
      await flaky.handle(NotificationActions.taken, first.payload);

      // والوعد اتنفّذ: الجرعة مسجّلة
      final taken = (await db.select(db.doseEvents).get())
          .where((e) => e.state == DoseState.taken);
      expect(taken, isNotEmpty,
          reason: 'فشل مدّ النافذة مش المفروض يوقّع التأكيد');
    });

    test('صف اليوم لسه ما اتنزّلش → التأكيد بيزرعه بنفسه', () async {
      // «يومك» ما اتفتحتش النهاردة، فمفيش صفوف. الوعد لازم يشتغل برضه.
      await db.delete(db.doseEvents).go();
      final first = firstReminder();

      await wake().handle(NotificationActions.taken, first.payload);

      final taken = (await db.select(db.doseEvents).get())
          .where((e) => e.state == DoseState.taken);
      expect(taken, isNotEmpty);
    });
  });

  test('«أخدته» من الإشعار والتطبيق مقفول: الجرعة اتسجّلت والنافذة اتمدّت',
      () async {
    final first = firstReminder();
    expect(first.at, DateTime(2026, 8, 31, 7));
    expect(device.doses.length, maxPendingReminders);
    final endBefore = device.coverageEnd;
    // الصفوف موجودة من قبل — الجدولة بتنزّلها عشان السحابة تعرف الجرعة
    // قبل معادها (٤.٢ب جزء ١) — بس ولا واحدة اتأكدت لسه.
    expect(
      (await db.select(db.doseEvents).get())
          .where((e) => e.state != DoseState.pending),
      isEmpty,
      reason: '«يومك» ما اتفتحتش — محدش أكّد حاجة',
    );

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
    expect(
      (await db.select(db.doseEvents).get())
          .where((e) => e.state != DoseState.pending),
      isEmpty,
      reason: 'ولا صف غيّر حالته',
    );
  });

  test('إشعار لدوا اتوقف بعد الجدولة → بيتجاهل بهدوء', () async {
    final first = firstReminder();
    final meds = MedicationRepository(db, clock: seededLongAgo);
    for (final m in await meds.watchMedications(patientId).first) {
      await meds.stopMedication(m.id);
    }

    await wake().handle(NotificationActions.taken, first.payload);

    expect(
      (await db.select(db.doseEvents).get())
          .where((e) => e.state == DoseState.taken),
      isEmpty,
      reason: 'الدوا اتوقف — مفيش حاجة تتسجّل',
    );
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
  test('«أخدته» من إعادة التنبيه على شاشة القفل: بتسجّل وبتلغي باقي الإعادات والسلّم',
      () async {
    final first = firstReminder();
    final repeat = device.scheduled[repeatIdFor(first.at, 0)]!;
    expect(repeat.at, DateTime(2026, 8, 31, 7, 5));
    expect(repeat.payload, first.payload, reason: 'نفس الحمولة → نفس المعالجة');

    // الجرعة رنّت ٧:٠٠، الإعادة الأولى رنّت ٧:٠٥، وهو داس «أخدته» عليها ٧:٠٦
    await wake().handle(NotificationActions.taken, repeat.payload,
        now: DateTime(2026, 8, 31, 7, 6));

    final events = await db.select(db.doseEvents).get();
    expect(events.where((e) => e.state == DoseState.taken).length, 1);
    for (var i = 0; i < maxRepeats; i++) {
      expect(device.cancelled, contains(repeatIdFor(first.at, i)));
      expect(device.scheduled.containsKey(repeatIdFor(first.at, i)), isFalse,
          reason: 'القاعدة الخامسة: إعادة ٧:١٠ ما ترنّش على حاجة اتعملت');
    }
    expect(device.cancelled, contains(escalationIdFor(first.at, EscalationRung.second)));
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

  group('٤.٢أ — اللي الـisolate بيكتبه لازم يوصل السحابة', () {
    Future<List<DoseEventRow>> dirtyEvents() async => (await db
            .select(db.doseEvents)
            .get())
        .where((e) => e.syncedAtMs == null || e.syncedAtMs! < e.updatedAtMs)
        .toList();

    test('«أخدته» من شاشة القفل → الجرعة بتوصل السحابة من غير ما التطبيق يتفتح',
        () async {
      await link();
      final first = firstReminder();

      await wake().handle(NotificationActions.taken, first.payload,
          now: DateTime(2026, 8, 31, 6, 55));

      expect(remote.tables, contains('dose_events'),
          reason: 'ده الصف اللي السيرفر هيقرا منه في ٤.٢ب');
      expect(await dirtyEvents(), isEmpty, reason: 'اتعلّم بعد ما وصل');
      final taken = (await db.select(db.doseEvents).get())
          .where((e) => e.state == DoseState.taken);
      expect(taken.length, 1);
    });

    test('الرفع بيحصل بعد الكتابة المحلية وبعد إلغاء الإشعارات — مش قبلهم',
        () async {
      await link();
      final first = firstReminder();

      await wake().handle(NotificationActions.taken, first.payload,
          now: DateTime(2026, 8, 31, 6, 55));

      final firstUpsert = trace.indexWhere((e) => e.startsWith('upsert:'));
      final lastCancel = trace.lastIndexOf('cancel');
      expect(firstUpsert, greaterThan(-1));
      expect(lastCancel, greaterThan(-1));
      expect(lastCancel, lessThan(firstUpsert),
          reason: 'القاعدة الخامسة: التصعيد بيتسكّت قبل ما نستنى أي شبكة');
    });

    test('من غير ربط → صفر نداءات شبكة، والتسجيل المحلي بيتم عادي', () async {
      final first = firstReminder();

      await wake().handle(NotificationActions.taken, first.payload,
          now: DateTime(2026, 8, 31, 6, 55));

      expect(remote.tables, isEmpty, reason: 'غير المربوط أوفلاين ١٠٠٪');
      expect(device.cancelled, contains(first.id));
      expect(
        (await db.select(db.doseEvents).get())
            .where((e) => e.state == DoseState.taken)
            .length,
        1,
      );
    });

    test('السحابة وقعت → مفيش رمي، الجرعة اتسجّلت والإشعارات اتلغت، والصف متوسّخ',
        () async {
      await link();
      remote.fail = true;
      final first = firstReminder();

      await expectLater(
        wake().handle(NotificationActions.taken, first.payload,
            now: DateTime(2026, 8, 31, 6, 55)),
        completes,
      );

      expect(
        (await db.select(db.doseEvents).get())
            .where((e) => e.state == DoseState.taken)
            .length,
        1,
      );
      expect(device.cancelled, contains(first.id));
      expect(await dirtyEvents(), isNotEmpty, reason: 'هيتشال في دفعة المقدمة');
    });

    test('الشبكة علّقت → المهلة بتحرّرنا، والوعد للمريض اتنفّذ قبلها', () async {
      await link();
      remote.hangFor = const Duration(seconds: 30);
      final first = firstReminder();

      final watch = Stopwatch()..start();
      await expectLater(
        wake(pushTimeout: const Duration(milliseconds: 50)).handle(
            NotificationActions.taken, first.payload,
            now: DateTime(2026, 8, 31, 6, 55)),
        completes,
      );
      watch.stop();

      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(device.cancelled, contains(first.id));
      expect(await dirtyEvents(), isNotEmpty);
    });

    test('«اتنست» اللي الصحوة كتبتها بتوصل السحابة هي كمان', () async {
      await link();
      final first = firstReminder();
      final second = device.doses.values
          .where((p) => p.at.isAfter(first.at))
          .reduce((a, b) => a.at.isBefore(b.at) ? a : b);

      // أكّد التانية ٧:٥٠ — الأولى (٧:٠٠) عدّت المهلة والصحوة كتبتها «اتنست»
      await wake().handle(NotificationActions.taken, second.payload,
          now: DateTime(2026, 8, 31, 7, 50));

      expect(remote.tables, contains('dose_events'));
      expect(await dirtyEvents(), isEmpty);
      final missed = (await db.select(db.doseEvents).get())
          .where((e) => e.state == DoseState.missed);
      expect(missed.length, 1);
    });

    test('«فكّرني بعدين» مش بيكتب محلي → مفيش نداء شبكة من ورا التأجيل',
        () async {
      await link();
      // ندفع كل المتوسّخ الأول عشان اللي بعده يبقى من التأجيل لوحده
      await wake().handle(NotificationActions.taken, firstReminder().payload,
          now: DateTime(2026, 8, 31, 6, 55));
      remote.tables.clear();

      final next = firstReminder();
      await wake().handle(NotificationActions.snooze, next.payload,
          now: DateTime(2026, 8, 31, 7, 5));

      expect(remote.tables, isEmpty, reason: 'مفيش صف اتوسّخ، يبقى مفيش رفع');
    });
  });

}


/// قاعدة بيانات بترفض تكتب — زي `database is locked` بالظبط.
class _ThrowingEvents implements DoseEventRepository {
  _ThrowingEvents(this._real);

  final DoseEventRepository _real;

  @override
  Future<void> confirmDose({
    required int doseScheduleId,
    required DateTime routineDay,
    required DateTime scheduledAt,
    required DoseState state,
  }) async =>
      throw Exception('SqliteException(5): database is locked');

  @override
  noSuchMethod(Invocation invocation) =>
      // الباقي بيعدّي للحقيقي عشان الاختبار يوصل لنقطة الكتابة أصلاً
      (_real as dynamic).noSuchMethod(invocation);
}

/// بتسجّل لحظة كتابة صف الجرعة — عشان نقيس اللي قبلها واللي بعدها.
class _TracingEvents implements DoseEventRepository {
  _TracingEvents(this._real);

  final DoseEventRepository _real;

  @override
  Future<void> confirmDose({
    required int doseScheduleId,
    required DateTime routineDay,
    required DateTime scheduledAt,
    required DoseState state,
  }) async {
    await _real.confirmDose(
      doseScheduleId: doseScheduleId,
      routineDay: routineDay,
      scheduledAt: scheduledAt,
      state: state,
    );
    trace.add('confirmDose');
  }

  @override
  noSuchMethod(Invocation invocation) =>
      (_real as dynamic).noSuchMethod(invocation);
}

/// مدّ النافذة بيقع — مجاملة، مش وعد.
class _ThrowingScheduler extends ReminderScheduler {
  _ThrowingScheduler({
    required super.routines,
    required super.medications,
    required super.events,
    required super.patientId,
    required super.sink,
  });

  @override
  Future<void> rescheduleAll({DateTime? now}) async =>
      throw Exception('SqliteException(5): database is locked');
}
