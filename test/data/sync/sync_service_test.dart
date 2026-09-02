import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/data/sync/sync_service.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final aug31 = DateTime(2026, 8, 31);

/// جهاز ما بيعملش حاجة — الاختبار ده عن السحابة، مش عن الإشعارات.
class SilentSink implements ReminderSink {
  @override
  Future<void> schedule(PlannedNotification n) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<Set<int>> pendingIds() async => {};
  @override
  Future<void> ensurePermissions() async {}
}

/// سحابة وهمية بتحترم upsert-on-uuid — اختبار العدّ فيها هو برهان 3.2a.
class FakeSyncRemote implements SyncRemote {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  int calls = 0;

  /// جدول بيرمي — لمحاكاة فشل في نص الدفعة.
  String? failOnTable;

  /// بيتندَه قبل ما upsert يرجع — لمحاكاة تعديل أثناء الدفع.
  Future<void> Function(String table)? onUpsert;

  /// سحابة بتعلّق — لمحاكاة شبكة بايظة في صحوة خلفية.
  Duration? hangFor;

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    calls++;
    if (hangFor != null) await Future<void>.delayed(hangFor!);
    if (table == failOnTable) throw Exception('السحابة وقعت');
    await onUpsert?.call(table);
    final t = tables.putIfAbsent(table, () => {});
    for (final row in rows) {
      t[row['uuid'] as String] = row; // on conflict (uuid) do update
    }
  }

  int rowCount(String table) => tables[table]?.length ?? 0;
}

void main() {
  late AppDatabase db;
  late RoutineRepository routines;
  late MedicationRepository meds;
  late FakeSyncRemote remote;
  late bool signedIn;
  late SyncService sync;
  late int patientId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    meds = MedicationRepository(db);
    remote = FakeSyncRemote();
    signedIn = true;
    sync = SyncService(
      db: db,
      remote: remote,
      hasSession: () => signedIn,
      localWrites: const Stream.empty(),
    );
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, normalDay);
  });

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  Future<int> addConcor() => meds.addMedication(
        patientId: patientId,
        name: 'Concor 5mg',
        timing: const AnchorTiming(DayAnchor.breakfast, -30),
        startDate: aug31,
        amountLabel: 'قرص واحد',
      );

  Future<List<({String table, String uuid, int? synced, int updated})>>
      localState() async {
    final meds_ = await db.select(db.medications).get();
    return [
      for (final m in meds_)
        (table: 'medications', uuid: m.uuid, synced: m.syncedAtMs, updated: m.updatedAtMs),
    ];
  }

  test('من غير جلسة أو من غير ربط → صفر نداءات — المستخدم غير المربوط أوفلاين ١٠٠٪',
      () async {
    await addConcor();

    signedIn = false;
    await sync.push();
    expect(remote.calls, 0);

    signedIn = true; // جلسة موجودة بس عمره ما ربط (confirmLinked ما اتندهتش)
    await sync.push();
    expect(remote.calls, 0, reason: 'اربط ابني هو اللي بيفتح المزامنة');
  });

  test('بعد الربط: المتوسّخ بيتدفع أب-قبل-ابن، والعلامة بتتحط، والنضيف مش بيتبعت تاني',
      () async {
    await addConcor();
    await sync.confirmLinked();

    await sync.push();

    // صف المريض رفعته شاشة الربط نفسها (care.upsertPatient) — المزامنة
    // بتبعته بس لو اتعدّل بعدها، وconfirmLinked علّمته نضيف.
    expect(remote.rowCount('patients'), 0);
    expect(remote.rowCount('day_routines'), 1);
    expect(remote.rowCount('medications'), 1);
    expect(remote.rowCount('dose_schedules'), 1);
    // الأرقام المحلية ما سابتش الجهاز، والعلاقات بالـuuid
    final med = remote.tables['medications']!.values.single;
    expect(med.containsKey('id'), isFalse);
    expect(med.containsKey('patient_id'), isFalse);
    expect(med['patient_uuid'],
        (await db.select(db.patients).get()).single.uuid);

    for (final row in await localState()) {
      expect(row.synced, row.updated, reason: 'العلامة = اللي اتدفع');
    }

    final callsAfterFirst = remote.calls;
    await sync.push();
    expect(remote.calls, callsAfterFirst, reason: 'النضيف مش بيتبعت تاني');
  });

  test('الدفع مرتين → عدد الصفوف في السحابة زي ما هو — برهان uuid بتاع 3.2a',
      () async {
    await addConcor();
    await sync.confirmLinked();

    await sync.push();
    final counts = {
      for (final t in remote.tables.keys) t: remote.rowCount(t),
    };

    // نوسّخ كل حاجة تاني وندفع تاني
    await meds.updateAmount((await db.select(db.medications).get()).single.id, 'قرصين');
    await sync.push();

    for (final t in counts.keys) {
      expect(remote.rowCount(t), counts[t], reason: 'upsert مش insert: $t');
    }
    expect(remote.tables['medications']!.values.single['amount_label'], 'قرصين');
  });

  test('فشل في أول جدول → ولا صف اتعلّم، وكله بيتعاد في المحاولة الجاية', () async {
    await addConcor();
    await sync.confirmLinked();
    // نوسّخ المريض نفسه عشان أول جدول في الدفعة يكون هو اللي بيقع
    await (db.update(db.patients)..where((t) => t.id.equals(patientId)))
        .write(const PatientsCompanion(name: Value('الحاج أحمد محمود')));

    remote.failOnTable = 'patients';
    await sync.push(); // بتسجّل وتسكت — عمرها ما بترمي في الواجهة

    final patient = (await db.select(db.patients).get()).single;
    expect(patient.syncedAtMs, lessThan(patient.updatedAtMs),
        reason: 'لسه متوسّخ');
    expect(remote.rowCount('medications'), 0, reason: 'وقفنا عند أول فشل');

    remote.failOnTable = null;
    await sync.push();
    expect(remote.rowCount('patients'), 1);
    expect(remote.rowCount('medications'), 1);
  });

  test('تعديل أثناء الدفع → الصف بيفضل متوسّخاً بعد ما الدفعة تخلص', () async {
    final medId = await addConcor();
    await sync.confirmLinked();

    remote.onUpsert = (table) async {
      if (table == 'medications') {
        // بين القراءة والتعليم — المريض بيعدّل الجرعة
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await meds.updateAmount(medId, 'تلات أقراص');
      }
    };
    await sync.push();

    final med = (await db.select(db.medications).get()).single;
    expect(med.syncedAtMs, lessThan(med.updatedAtMs),
        reason: 'العلامة هي اللي اتدفعت مش now() — التعديل الجديد لسه واصلش');

    remote.onUpsert = null;
    await sync.push();
    expect(remote.tables['medications']!.values.single['amount_label'], 'تلات أقراص');
  });

  test('حدث جرعة الساعة ٩ مساءً بتوقيت القاهرة بيوصل بلحظته الكونية — مش بحائط الساعة',
      () async {
    await addConcor();
    await sync.confirmLinked();
    final schedules = await meds.activeSchedules(patientId);
    final events = DoseEventRepository(db);
    // «٩ مساءً بالقاهرة» = لحظة كونية معروفة (١٨:٠٠Z صيفاً EEST+3).
    // بنبنيها كلحظة وبنحوّلها لحائط الجهاز أياً كان — فالاختبار بيثبت إن
    // التحويل بيحافظ على اللحظة مهما كانت منطقة الجهاز أو توقيته الصيفي.
    final cairoNinePm = DateTime.utc(2026, 8, 31, 18).toLocal();
    await events.materializeDay(aug31, [
      Reminder(at: cairoNinePm, doses: schedules),
    ]);
    await events.markTaken(int.parse(schedules.single.id), aug31);

    await sync.push();

    final event = remote.tables['dose_events']!.values.single;
    expect(event['scheduled_at'], '2026-08-31T18:00:00.000Z');
    expect(DateTime.parse(event['scheduled_at'] as String).isUtc, isTrue);
    final acted = DateTime.parse(event['acted_at'] as String);
    expect(acted.isUtc, isTrue);
  });

  test('التريجر: أي تعديل بيوسّخ الصف من غير ما حد يفتكر، وتعليم المزامنة مش بيوسّخ',
      () async {
    final medId = await addConcor();
    await sync.confirmLinked();
    await sync.push();

    final before = (await db.select(db.medications).get()).single;
    expect(before.syncedAtMs, before.updatedAtMs);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    // تعديل من مسار ما يعرفش حاجة عن المزامنة
    await meds.stopMedication(medId);

    final after = (await db.select(db.medications).get()).single;
    expect(after.updatedAtMs, greaterThan(before.updatedAtMs),
        reason: 'قاعدة البيانات نفسها وسّخت الصف');
    expect(after.syncedAtMs, lessThan(after.updatedAtMs));

    await sync.push();
    final marked = (await db.select(db.medications).get()).single;
    expect(marked.syncedAtMs, marked.updatedAtMs,
        reason: 'التعليم نفسه ما وسّخش الصف');
  });

  test('كتابة محلية → دفعة بعد سكوت الدबounce، من غير مؤقّت دوري', () async {
    final writes = StreamController<Object?>.broadcast();
    final debounced = SyncService(
      db: db,
      remote: remote,
      hasSession: () => true,
      localWrites: writes.stream,
      debounce: const Duration(milliseconds: 40),
    )..start();
    addTearDown(debounced.dispose);
    addTearDown(writes.close);

    await addConcor();
    await debounced.confirmLinked();

    writes.add(null);
    writes.add(null); // اتنين ورا بعض = دفعة واحدة
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(remote.rowCount('medications'), 1);
  });
  group('دفعة الخلفية المحدودة (pushOnce)', () {
    /// نفس ما تعمله شاشة الربط: أول رفع لصف المريض هو علامة «مربوط».
    Future<void> link() => sync.confirmLinked();

    test('بتدفع زي push العادية بالظبط — نفس الترتيب ونفس التعليم', () async {
      await addConcor();
      await link();

      await sync.pushOnce();

      // صف المريض رفعته شاشة الربط، فconfirmLinked علّمته نضيف — الباقي
      // بيتدفع أب-قبل-ابن زي push بالظبط
      expect(remote.tables.keys.toList(),
          ['day_routines', 'medications', 'dose_schedules']);
      for (final row in await localState()) {
        expect(row.synced, row.updated, reason: 'العلامة = اللي اتدفع');
      }
    });

    test('غير مربوط → صفر نداءات', () async {
      await addConcor();
      await sync.pushOnce();
      expect(remote.calls, 0);
    });

    test('السحابة وقعت → مفيش رمي، والصفوف بتفضل متوسّخة', () async {
      await link();
      await addConcor();
      remote.failOnTable = 'medications';

      // لو دي رمت، الـisolate كان هيقع وهو بيسجّل جرعة
      await expectLater(sync.pushOnce(), completes);

      expect((await localState()).single.synced, isNull);
    });

    test('الشبكة علّقت → المهلة بتحرّرنا، من غير رمي، والصف لسه متوسّخ',
        () async {
      await link();
      await addConcor();
      remote.hangFor = const Duration(seconds: 30);

      final watch = Stopwatch()..start();
      await expectLater(
        sync.pushOnce(timeout: const Duration(milliseconds: 50)),
        completes,
      );
      watch.stop();

      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect((await localState()).single.synced, isNull,
          reason: 'اللي ما لحقش بيستنى دفعة المقدمة الجاية');
    });

    test('المهلة الافتراضية ثواني معدودة — مش محاولة عنيدة', () {
      expect(backgroundPushTimeout, lessThanOrEqualTo(const Duration(seconds: 10)));
      expect(backgroundPushTimeout, greaterThanOrEqualTo(const Duration(seconds: 2)));
    });
  });

  /// ٤.٢ب — جزء ١: السحابة لازم تعرف الجرعة **قبل معادها**.
  ///
  /// الأساس اللي الجولة كلها واقفة عليه. السيرفر بيصعّد لابنه من صفوف
  /// موجودة في السحابة؛ أب بيهمل كل الإشعارات مش بيصحّي حاجة، فلو الصف
  /// ما اترفعش وهو لسه جاي، المسح بيلاقي ولا حاجة والتصعيد بيسكت في صمت —
  /// للراجل اللي التصعيد اتعمل عشانه بالظبط.
  group('الأب فتح التطبيق الصبح وساب الموبايل', () {
    late ReminderScheduler scheduler;

    setUp(() {
      scheduler = ReminderScheduler(
        routines: routines,
        medications: meds,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: SilentSink(),
      );
    });

    /// ٣ جرعات في اليوم: ٧:٠٠ ص، ٢:٠٠ م، ٨:٣٠ م
    Future<void> addThreeADay() async {
      final id = await addConcor(); // قبل الفطار بنص ساعة = ٧:٠٠
      await meds.addDoseSchedule(id,
          timing: const AnchorTiming(DayAnchor.lunch, -30), startDate: aug31);
      await meds.addDoseSchedule(id,
          timing: const AnchorTiming(DayAnchor.dinner, 30), startDate: aug31);
    }

    List<Map<String, dynamic>> cloudEvents() =>
        remote.tables['dose_events']?.values.toList() ?? [];

    test('كل جرعات اليوم موجودة في السحابة كـpending قبل معادها', () async {
      await addThreeADay();
      await sync.confirmLinked();

      // فتحة واحدة الساعة ٧:٠٠ ص، وبعدها الموبايل مالوش أي لمسة
      final morning = DateTime(2026, 8, 31, 7);
      await scheduler.rescheduleAll(now: morning);
      await sync.push();

      final today = cloudEvents()
          .where((e) => e['routine_day'] == '2026-08-31')
          .toList();
      expect(today.length, 3, reason: 'التلات جرعات، مش اللي عدّت بس');
      for (final event in today) {
        expect(event['state'], 'pending');
        // **قبل معادها**: اللحظة اللي جهاز الأب حسبها لسه ما جاتش
        final at = DateTime.parse(event['scheduled_at'] as String);
        expect(at.isBefore(morning.toUtc()), isFalse,
            reason: 'الصف وصل السحابة والجرعة لسه جاية');
      }
    });

    test('بكرة كمان موجود — التغطية يومين من غير أي لمسة تانية', () async {
      await addThreeADay();
      await sync.confirmLinked();

      await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 7));
      await sync.push();

      final tomorrow = cloudEvents()
          .where((e) => e['routine_day'] == '2026-09-01')
          .toList();
      expect(tomorrow.length, 3);
      expect(tomorrow.every((e) => e['state'] == 'pending'), isTrue);
    });

    test('إعادة الفتح ما بتكرّرش ولا صف — المفتاح (جرعة، يوم)', () async {
      await addThreeADay();
      await sync.confirmLinked();

      await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 7));
      await sync.push();
      final countAfterFirst = cloudEvents().length;
      final localAfterFirst = (await db.select(db.doseEvents).get()).length;

      // فتح تاني وتالت في نفس اليوم
      await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 9));
      await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 11));
      await sync.push();

      expect((await db.select(db.doseEvents).get()).length, localAfterFirst,
          reason: 'materializeDay بتضيف الناقص بس');
      expect(cloudEvents().length, countAfterFirst);
    });

    test('الجرعة اللي اتاخدت بتوصل السحابة بحالتها — مش بتفضل pending',
        () async {
      await addThreeADay();
      await sync.confirmLinked();
      await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 7));
      await sync.push();

      final events = DoseEventRepository(db);
      final schedules = await meds.activeSchedules(patientId);
      await events.markTaken(int.parse(schedules.first.id), aug31);
      await sync.push();

      final taken = cloudEvents().where((e) => e['state'] == 'taken');
      expect(taken.length, 1);
    });
  });

}
