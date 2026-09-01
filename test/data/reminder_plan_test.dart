import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

/// نفس روتين اختبارات المحرك: صحيان ٧، فطار ٧:٣٠، غدا ٢:٣٠، عشا ٨، نوم ١١:٣٠ م
final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final aug31 = DateTime(2026, 8, 31);
final aug31at6 = DateTime(2026, 8, 31, 6);

DoseSchedule dose(
  String name,
  DayAnchor anchor, {
  int offset = 0,
  DoseRepeat repeat = DoseRepeat.daily,
  int? durationDays,
  String? amount,
  DateTime? start,
}) =>
    DoseSchedule(
      id: name,
      medicationName: name,
      timing: AnchorTiming(anchor, offset),
      repeat: repeat,
      durationDays: durationDays,
      amountLabel: amount,
      startDate: start ?? aug31,
    );

/// حوض تذكيرات في الذاكرة — بيمثّل جهاز، وبيفضح أي تكرار.
class FakeReminderSink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];
  int scheduleCalls = 0;

  @override
  Future<void> schedule(PlannedNotification notification) async {
    scheduleCalls++;
    // نفس سلوك الجهاز: نفس الرقم بيستبدل، ما بيزوّدش.
    scheduled[notification.id] = notification;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();

  @override
  Future<void> ensurePermissions() async {}
}

void main() {
  // الاختبارات دي بتفتح أكتر من قاعدة في الذاكرة، وكل واحدة منفصلة تماماً.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('أرقام الإشعارات', () {
    test('نفس الخانة الزمنية = نفس الرقم دايماً', () {
      final a = notificationIdFor(DateTime(2026, 8, 31, 7));
      final b = notificationIdFor(DateTime(2026, 8, 31, 7));
      expect(a, b);
    });

    test('كل دقيقة في اليوم ليها رقم لوحدها', () {
      final ids = <int>{};
      for (var minute = 0; minute < 1440; minute++) {
        ids.add(notificationIdFor(DateTime(2026, 8, 31, 0, minute)));
      }
      expect(ids.length, 1440);
    });

    test('أيام مختلفة = أرقام مختلفة جوّه الدورة', () {
      // الأرقام بتلف كل ٣٢ يوم لكل مريض. ده مقصود: النافذة ٧ أيام والسقف
      // ٤٨ إشعار، يعني عمر رقم اليوم الـ٣٢ ما هيبقى متجدول وقت ما رقم
      // اليوم الأول يترد.
      final ids = <int>{};
      for (var day = 0; day < 32; day++) {
        ids.add(notificationIdFor(DateTime(2026, 8, 1).add(Duration(days: day))));
      }
      expect(ids.length, 32);

      // اليوم الـ٣٣ بيرجع لأول رقم — والنافذة عمرها ما بتوصله
      expect(
        notificationIdFor(DateTime(2026, 8, 1).add(const Duration(days: 32))),
        notificationIdFor(DateTime(2026, 8, 1)),
      );
      expect(reminderWindowDays, lessThan(32));
    });

    test('النطاقات هي اللي مكتوبة في CLAUDE.md', () {
      // الجدول في CLAUDE.md بيقول: الجرعات ١٠٠٠٠٠٠ – ٦٨٩٨٢٣٩.
      // لو الأرقام دي اتغيّرت، الوثيقة بتبقى كذب — فالاختبار ده بيوقّع.
      expect(doseIdBase, 1000000);
      expect(doseIdLimit, 6898240);
      expect(isDoseId(6898239), isTrue);
      expect(isDoseId(6898240), isFalse);

      // مساحة المريض الواحد × أقصى عدد مرضى = عرض النطاق بالظبط
      expect(patientIdSpan, 46080);
      expect(maxPatients, 128);
      expect(doseIdBase + maxPatients * patientIdSpan, doseIdLimit);

      // نطاق تصعيد المرحلة الرابعة محجوز من ١٠ مليون — لازم يفضل برّه
      // نطاق الجرعات عشان إعادة جدولة الجرعات ما تلغيش مكالمة.
      const escalationBase = 10000000;
      const escalationLimit = escalationBase + 4096 * 1440;
      expect(isDoseId(escalationBase), isFalse);
      expect(isDoseId(escalationLimit - 1), isFalse);
      expect(escalationBase, greaterThanOrEqualTo(doseIdLimit));
      expect(escalationLimit, lessThan(1 << 31));
    });

    test('كل الأرقام جوّه نطاق الجرعات وجوّه حدود أندرويد', () {
      final id = notificationIdFor(DateTime(2030, 12, 31, 23, 59));
      expect(isDoseId(id), isTrue);
      expect(id, lessThan(1 << 31));
      expect(isDoseId(doseIdBase - 1), isFalse);
      expect(isDoseId(doseIdLimit), isFalse);
    });
  });

  group('بُعد المريض في الرقم', () {
    final sameMinute = DateTime(2026, 8, 31, 8);

    test('مريضين في نفس الدقيقة في نفس اليوم بياخدوا رقمين مختلفين', () {
      final first = notificationIdFor(sameMinute, patientIndex: 0);
      final second = notificationIdFor(sameMinute, patientIndex: 1);

      expect(first, isNot(second), reason: 'واحد كان بيمسح تذكير التاني');
      expect(second - first, patientIdSpan);
      expect(isDoseId(first), isTrue);
      expect(isDoseId(second), isTrue);
    });

    test('كل المرضى في نفس الدقيقة بأرقام مختلفة، وكلهم جوّه النطاق', () {
      final ids = {
        for (var patient = 0; patient < maxPatients; patient++)
          notificationIdFor(sameMinute, patientIndex: patient),
      };

      expect(ids.length, maxPatients);
      expect(ids.every(isDoseId), isTrue);
      expect(ids.reduce((a, b) => a > b ? a : b), lessThan(doseIdLimit));
    });

    test('مساحة المريض ما بتزحفش على اللي بعده', () {
      // آخر دقيقة في آخر يوم عند مريض، وأول دقيقة عند اللي بعده
      final lastOfFirst = notificationIdFor(
        DateTime(1970, 1, 32, 23, 59),
        patientIndex: 0,
      );
      final firstOfSecond = notificationIdFor(
        DateTime(1970, 1, 1),
        patientIndex: 1,
      );
      expect(lastOfFirst, lessThan(firstOfSecond));
    });

    test('خانة برّه الحد بترمي خطأ بدل ما تلف وتصطدم', () {
      expect(
        () => notificationIdFor(sameMinute, patientIndex: maxPatients),
        throwsArgumentError,
      );
      expect(
        () => notificationIdFor(sameMinute, patientIndex: -1),
        throwsArgumentError,
      );
    });

    test('نفس المريض ونفس الخانة = نفس الرقم، مهما اتكرر', () {
      expect(
        notificationIdFor(sameMinute, patientIndex: 3),
        notificationIdFor(sameMinute, patientIndex: 3),
      );
    });
  });

  group('يوم الروتين', () {
    test('بعد الصحيان = نفس اليوم', () {
      expect(
        currentRoutineDay(normalDay, DateTime(2026, 8, 31, 9)),
        aug31,
      );
    });

    test('قبل الصحيان لسه في يوم امبارح', () {
      // بيصحى ٧، والساعة ٦:٣٠ — فهو لسه في يوم ٣٠ أغسطس
      expect(
        currentRoutineDay(normalDay, DateTime(2026, 8, 31, 6, 30)),
        DateTime(2026, 8, 30),
      );
    });

    test('بعد نص الليل لواحد بينام متأخر لسه في يوم امبارح', () {
      expect(
        currentRoutineDay(normalDay, DateTime(2026, 9, 1, 0, 45)),
        aug31,
      );
    });

    test('بالظبط عند الصحيان بيبدأ اليوم الجديد', () {
      expect(
        currentRoutineDay(normalDay, DateTime(2026, 8, 31, 7)),
        aug31,
      );
    });
  });

  group('نافذة الجدولة', () {
    test('جرعة يومية = ٧ تذكيرات في ٧ أيام', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: [dose('Concor', DayAnchor.breakfast, offset: -30)],
        from: aug31at6,
      );

      expect(planned.length, 7);
      expect(planned.first.at, DateTime(2026, 8, 31, 7));
      expect(planned.last.at, DateTime(2026, 9, 6, 7));
    });

    test('التذكيرات مرتّبة بالوقت', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: [
          dose('Telfast', DayAnchor.sleep, offset: -15),
          dose('Antodine', DayAnchor.breakfast, offset: -30),
          dose('LINEX', DayAnchor.dinner, offset: 30),
        ],
        from: aug31at6,
        days: 1,
      );

      expect(
        planned.map((p) => p.at).toList(),
        [
          DateTime(2026, 8, 31, 7),
          DateTime(2026, 8, 31, 20, 30),
          DateTime(2026, 8, 31, 23, 15),
        ],
      );
    });

    test('اللي فات ما بيتجدولش', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: [dose('Concor', DayAnchor.breakfast, offset: -30)],
        from: DateTime(2026, 8, 31, 9),
        days: 1,
      );

      expect(planned, isEmpty, reason: 'جرعة ٧:٠٠ عدّت خلاص');
    });

    test('جرعتين في نفس الدقيقة = تذكير واحد برقم واحد', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: [
          dose('Antodine', DayAnchor.breakfast, offset: -30),
          dose('Vitamin D', DayAnchor.breakfast, offset: -30),
        ],
        from: aug31at6,
        days: 1,
      );

      expect(planned.length, 1);
      expect(planned.single.doses.length, 2);
      expect(planned.single.body, contains('٢ أدوية دلوقتي'));
    });

    test('جرعة «قبل النوم» بعد منتصف الليل بتتجدول لليوم الصح', () {
      final nightOwl = normalDay.copyWith(sleep: MinuteOfDay.hm(1));
      final planned = planWindow(
        routine: nightOwl,
        schedules: [
          dose(
            'Telfast',
            DayAnchor.sleep,
            offset: -15,
            start: DateTime(2026, 8, 30),
          ),
        ],
        from: DateTime(2026, 8, 31, 0, 10),
        days: 1,
      );

      // يوم الروتين بتاع ٣٠ أغسطس بينتهي بجرعة الساعة ٠٠:٤٥ من ٣١ — لسه جاية
      expect(planned.first.at, DateTime(2026, 8, 31, 0, 45));
    });

    test('«اليوم فقط» بتتجدول مرة واحدة بس', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: [
          dose('Amebazole', DayAnchor.lunch, repeat: DoseRepeat.once),
        ],
        from: aug31at6,
      );

      expect(planned.length, 1);
    });

    test('مدة مفتوحة بتملا النافذة كلها وما بتقفش', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: [dose('Concor', DayAnchor.breakfast, offset: -30)],
        from: aug31at6,
        days: 30,
      );

      expect(planned.length, 30);
    });

    test('نص التذكير بيقول اسم الدوا والجرعة', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: [
          dose('Concor', DayAnchor.breakfast, offset: -30, amount: 'قرص واحد'),
        ],
        from: aug31at6,
        days: 1,
      );

      expect(planned.single.title, 'وقت الدوا');
      expect(planned.single.body, 'Concor — قرص واحد');
    });

    test('الحمولة فيها اليوم وأرقام الجرعات', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: [dose('Concor', DayAnchor.breakfast, offset: -30)],
        from: aug31at6,
        days: 1,
      );

      final payload = jsonDecode(planned.single.payload) as Map<String, dynamic>;
      expect(payload['v'], 1);
      expect(payload['day'], '2026-08-31');
      expect(payload['scheduleIds'], ['Concor']);
    });
  });

  group('سقف الإشعارات المعلّقة', () {
    /// ٦ أدوية × ٣ جرعات في اليوم = ١٨ جرعة يومياً في مواعيد مختلفة.
    ///
    /// الإزاحة بتتغيّر مع كل دوا عشان الجرعات ما تتجمّعش في نفس الدقيقة —
    /// ده أسوأ حالة واقعية، وهي اللي بتكسر حد الـ٦٤ بتاع iOS.
    List<DoseSchedule> sixMedicationsThriceDaily() => [
          for (var med = 0; med < 6; med++)
            for (final anchor in [
              DayAnchor.breakfast,
              DayAnchor.lunch,
              DayAnchor.dinner,
            ])
              dose(
                'دوا $med ${anchor.name}',
                anchor,
                offset: -30 + med * 7,
              ),
        ];

    test('١٨ جرعة في اليوم بتدي ١٨ تذكير مختلف', () {
      final oneDay = planWindow(
        routine: normalDay,
        schedules: sixMedicationsThriceDaily(),
        from: aug31at6,
        days: 1,
        maxPending: 1000,
      );
      expect(oneDay.length, 18, reason: 'مفيش تجميع — ١٨ معاد مختلف');
    });

    test('٦ أدوية × ٣ جرعات عمرها ما بتعدي السقف', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: sixMedicationsThriceDaily(),
        from: aug31at6,
      );

      expect(planned.length, maxPendingReminders);
      expect(planned.length, lessThan(iosPendingLimit));
      // مع خانات المرحلة الرابعة المحجوزة لسه تحت حد iOS
      expect(maxPendingReminders + 16, lessThanOrEqualTo(iosPendingLimit));
    });

    test('اللي بيتساب هو الأبعد — الأقرب بيتجدول دايماً', () {
      final schedules = sixMedicationsThriceDaily();

      final capped = planWindow(
        routine: normalDay,
        schedules: schedules,
        from: aug31at6,
      );
      final everything = planWindow(
        routine: normalDay,
        schedules: schedules,
        from: aug31at6,
        maxPending: 1000,
      );

      expect(everything.length, greaterThan(capped.length));
      expect(
        capped.map((p) => p.at).toList(),
        everything.take(capped.length).map((p) => p.at).toList(),
      );

      // مفيش تذكير متسيّب أقرب من أبعد تذكير اتجدول
      final lastKept = capped.last.at;
      final dropped = everything.skip(capped.length);
      expect(dropped.every((p) => p.at.isAfter(lastKept)), isTrue);
    });

    test('التذكيرات مرتّبة، وأقربها هو أول واحد', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: sixMedicationsThriceDaily(),
        from: aug31at6,
      );

      for (var i = 1; i < planned.length; i++) {
        expect(planned[i].at.isAfter(planned[i - 1].at), isTrue);
      }
      expect(planned.first.at.isAfter(aug31at6), isTrue);
    });

    test('النافذة بتقصر لما الأدوية تكتر', () {
      final busy = planWindow(
        routine: normalDay,
        schedules: sixMedicationsThriceDaily(),
        from: aug31at6,
      );
      final light = planWindow(
        routine: normalDay,
        schedules: [dose('Concor', DayAnchor.breakfast, offset: -30)],
        from: aug31at6,
      );

      // دواء واحد بياخد السبع أيام كاملة
      expect(light.length, 7);
      expect(coverageEnd(light), DateTime(2026, 9, 6, 7));

      // ٦ أدوية بتملا السقف في أقل من ٣ أيام
      expect(coverageEnd(busy)!.isBefore(coverageEnd(light)!), isTrue);
      expect(coverageEnd(busy)!.difference(aug31at6).inDays, lessThan(3));
    });

    test('كل مرة التطبيق يتفتح النافذة بتتمدّ قدام', () {
      final schedules = sixMedicationsThriceDaily();

      final onOpen = planWindow(
        routine: normalDay,
        schedules: schedules,
        from: aug31at6,
      );
      final twoDaysLater = planWindow(
        routine: normalDay,
        schedules: schedules,
        from: aug31at6.add(const Duration(days: 2)),
      );

      expect(twoDaysLater.length, maxPendingReminders);
      expect(
        coverageEnd(twoDaysLater)!.isAfter(coverageEnd(onOpen)!),
        isTrue,
        reason: 'التغطية بتزحف قدام مع كل فتحة',
      );
    });

    test('السقف بيتحسب لكل مريض لوحده', () {
      final schedules = sixMedicationsThriceDaily();

      final first = planWindow(
        routine: normalDay,
        schedules: schedules,
        from: aug31at6,
      );
      final second = planWindow(
        routine: normalDay,
        schedules: schedules,
        from: aug31at6,
        patientIndex: 1,
      );

      expect(first.length, maxPendingReminders);
      expect(second.length, maxPendingReminders);
      // نفس المواعيد بالظبط، أرقام مختلفة تماماً
      expect(first.map((p) => p.at).toList(), second.map((p) => p.at).toList());
      expect(
        first.map((p) => p.id).toSet().intersection(
              second.map((p) => p.id).toSet(),
            ),
        isEmpty,
      );
    });
  });

  group('المطابقة مع الجهاز', () {
    test('اللي مش مطلوب بيتلغي، والباقي بيتجدول', () {
      final planned = planWindow(
        routine: normalDay,
        schedules: [dose('Concor', DayAnchor.breakfast, offset: -30)],
        from: aug31at6,
        days: 1,
      );

      final stale = notificationIdFor(DateTime(2026, 8, 31, 12));
      final plan = reconcile(planned, {stale, planned.single.id});

      expect(plan.toCancel, {stale});
      expect(plan.toSchedule.single.id, planned.single.id);
    });

    test('إشعارات برّه نطاق الجرعات ما بتتلغيش أبداً', () {
      // نطاق التصعيد بتاع المرحلة الرابعة لازم يعدّي سليم
      final escalation = doseIdLimit + 7;
      final plan = reconcile(const [], {escalation, doseIdBase + 5});

      expect(plan.toCancel, {doseIdBase + 5});
      expect(plan.toCancel.contains(escalation), isFalse);
    });
  });

  group('إعادة الجدولة على جهاز', () {
    late AppDatabase db;
    late RoutineRepository routines;
    late MedicationRepository meds;
    late FakeReminderSink sink;
    late ReminderScheduler scheduler;
    late int patientId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      routines = RoutineRepository(db);
      meds = MedicationRepository(db);
      sink = FakeReminderSink();
      patientId = await routines.ensurePatient();
      await routines.saveRoutine(patientId, normalDay);
      scheduler = ReminderScheduler(
        routines: routines,
        medications: meds,
        patientId: patientId,
        sink: sink,
      );
    });

    tearDown(() => db.close());

    Future<void> addConcor() => meds.addMedication(
          patientId: patientId,
          name: 'Concor',
          timing: AnchorTiming(DayAnchor.breakfast, -30),
          startDate: aug31,
        );

    test('إعادة الجدولة مرتين ما بتزوّدش ولا إشعار', () async {
      await addConcor();

      await scheduler.rescheduleAll(now: aug31at6);
      final firstPass = sink.scheduled.keys.toSet();

      await scheduler.rescheduleAll(now: aug31at6);

      expect(sink.scheduled.keys.toSet(), firstPass);
      expect(sink.scheduled.length, 7);
      expect(sink.cancelled, isEmpty);
    });

    test('الروتين اتغيّر → القديم اتلغى والجديد اتجدول', () async {
      await addConcor();
      await scheduler.rescheduleAll(now: aug31at6);
      final oldIds = sink.scheduled.keys.toSet();

      await routines.saveRoutine(
        patientId,
        normalDay.copyWith(breakfast: MinuteOfDay.hm(9)),
      );
      await scheduler.rescheduleAll(now: aug31at6);

      final newIds = sink.scheduled.keys.toSet();
      expect(newIds.intersection(oldIds), isEmpty, reason: 'كل المواعيد اتحركت');
      expect(sink.cancelled.toSet(), oldIds);
      expect(newIds.length, 7);
      expect(sink.scheduled[newIds.first]!.at.hour, 8);
    });

    test('الروتين اتغيّر → المرساة اتحركت والساعة الثابتة فضلت بنفس أرقامها',
        () async {
      await addConcor(); // قبل الفطار بنص ساعة
      await meds.addMedication(
        patientId: patientId,
        name: 'Eltroxin',
        timing: FixedTiming(MinuteOfDay.hm(6, 30)),
        startDate: aug31,
      );
      await scheduler.rescheduleAll(now: aug31at6);

      final fixedBefore = sink.scheduled.keys.where(
        (id) => sink.scheduled[id]!.body.contains('Eltroxin'),
      ).toSet();
      final anchoredBefore = sink.scheduled.keys.toSet().difference(fixedBefore);
      expect(fixedBefore.length, 7);
      expect(anchoredBefore.length, 7);

      await routines.saveRoutine(
        patientId,
        normalDay.copyWith(breakfast: MinuteOfDay.hm(9)),
      );
      await scheduler.rescheduleAll(now: aug31at6);

      final fixedAfter = sink.scheduled.keys.where(
        (id) => sink.scheduled[id]!.body.contains('Eltroxin'),
      ).toSet();
      expect(fixedAfter, fixedBefore, reason: 'الثابتة ما اتحركتش');
      expect(sink.cancelled.toSet(), anchoredBefore, reason: 'المرساة بس اتلغت');
      expect(
        sink.scheduled.keys.toSet().difference(fixedAfter).intersection(anchoredBefore),
        isEmpty,
        reason: 'كل مواعيد المرساة اتحركت',
      );
    });

    test('دوا جديد بيزوّد تذكيراته من غير ما يلمس اللي قبله', () async {
      await addConcor();
      await scheduler.rescheduleAll(now: aug31at6);

      await meds.addMedication(
        patientId: patientId,
        name: 'LINEX',
        timing: AnchorTiming(DayAnchor.dinner, 30),
        startDate: aug31,
      );
      await scheduler.rescheduleAll(now: aug31at6);

      expect(sink.scheduled.length, 14);
      expect(sink.cancelled, isEmpty);
    });

    test('إيقاف دوا بيلغي تذكيراته كلها', () async {
      final id = await meds.addMedication(
        patientId: patientId,
        name: 'Concor',
        timing: AnchorTiming(DayAnchor.breakfast, -30),
        startDate: aug31,
      );
      await scheduler.rescheduleAll(now: aug31at6);
      expect(sink.scheduled.length, 7);

      await meds.stopMedication(id);
      await scheduler.rescheduleAll(now: aug31at6);

      expect(sink.scheduled, isEmpty);
      expect(sink.cancelled.length, 7);
    });

    test('«أخدته» بيلغي التذكير ده وبس', () async {
      await addConcor();
      await scheduler.rescheduleAll(now: aug31at6);

      await scheduler.cancelReminderAt(DateTime(2026, 8, 31, 7));

      expect(sink.scheduled.length, 6);
      // الخانة دي بس: تذكيرها وتأجيلها، ومفيش حاجة تانية
      expect(sink.cancelled, [
        notificationIdFor(DateTime(2026, 8, 31, 7)),
        snoozeIdFor(DateTime(2026, 8, 31, 7)),
      ]);
    });

    /// ٦ أدوية حقيقية، كل واحد بـ٣ جرعات في اليوم.
    Future<void> addSixThriceDaily() async {
      for (var med = 0; med < 6; med++) {
        final id = await meds.addMedication(
          patientId: patientId,
          name: 'دوا $med',
          timing: AnchorTiming(DayAnchor.breakfast, -30 + med * 7),
          startDate: aug31,
        );
        for (final anchor in [DayAnchor.lunch, DayAnchor.dinner]) {
          await meds.addDoseSchedule(
            id,
            timing: AnchorTiming(anchor, -30 + med * 7),
            startDate: aug31,
          );
        }
      }
    }

    test('٦ أدوية × ٣ جرعات عمرها ما بتعدي سقف iOS على الجهاز', () async {
      await addSixThriceDaily();
      expect((await meds.activeSchedules(patientId)).length, 18);

      await scheduler.rescheduleAll(now: aug31at6);

      expect(sink.scheduled.length, maxPendingReminders);
      expect(sink.scheduled.length, lessThan(iosPendingLimit));
      expect(sink.scheduled.keys.every(isDoseId), isTrue);
    });

    test('اللي اتجدول على الجهاز هو الأقرب', () async {
      await addSixThriceDaily();
      await scheduler.rescheduleAll(now: aug31at6);

      final scheduled = sink.scheduled.values.map((p) => p.at).toList()..sort();
      // أقرب جرعة: دوا ٠ قبل الفطار بنص ساعة = ٧:٠٠ ص
      expect(scheduled.first, DateTime(2026, 8, 31, 7));

      // كل اللي اتجدول قبل أي حاجة اتسابت
      final everything = planWindow(
        routine: normalDay,
        schedules: await meds.activeSchedules(patientId),
        from: aug31at6,
        maxPending: 1000,
      );
      final dropped = everything.skip(maxPendingReminders);
      expect(dropped.isNotEmpty, isTrue);
      expect(dropped.every((p) => p.at.isAfter(scheduled.last)), isTrue);
    });

    test('فتح التطبيق تاني بيمدّ التغطية قدام من غير ما يعدي السقف', () async {
      await addSixThriceDaily();

      await scheduler.rescheduleAll(now: aug31at6);
      final firstEnd = sink.scheduled.values
          .map((p) => p.at)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      await scheduler.rescheduleAll(
        now: aug31at6.add(const Duration(days: 2)),
      );
      final secondEnd = sink.scheduled.values
          .map((p) => p.at)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      expect(sink.scheduled.length, maxPendingReminders);
      expect(secondEnd.isAfter(firstEnd), isTrue);
      expect(sink.cancelled, isNotEmpty, reason: 'اللي فات اتلغى');
    });

    test('من غير روتين محفوظ بيستخدم الافتراضي بدل ما يسيبه من غير تذكير',
        () async {
      final fresh = AppDatabase(NativeDatabase.memory());
      final freshRoutines = RoutineRepository(fresh);
      final freshMeds = MedicationRepository(fresh);
      final freshPatient = await freshRoutines.ensurePatient();
      await freshMeds.addMedication(
        patientId: freshPatient,
        name: 'Concor',
        timing: AnchorTiming(DayAnchor.breakfast, -30),
        startDate: aug31,
      );
      final freshSink = FakeReminderSink();

      await ReminderScheduler(
        routines: freshRoutines,
        medications: freshMeds,
        patientId: freshPatient,
        sink: freshSink,
      ).rescheduleAll(now: aug31at6);

      // الافتراضي فطاره ٨:٠٠ → الجرعة ٧:٣٠
      expect(freshSink.scheduled.length, 7);
      expect(freshSink.scheduled.values.first.at, DateTime(2026, 8, 31, 7, 30));
      await fresh.close();
    });
  });

  group('التأجيل والـpayload', () {
    test('رقم التأجيل في نطاق تاني غير نطاق الجرعات', () {
      final at = DateTime(2026, 8, 31, 8);
      final dose = notificationIdFor(at, patientIndex: 3);
      final snooze = snoozeIdFor(at, patientIndex: 3);

      expect(isDoseId(dose), isTrue);
      expect(isSnoozeId(dose), isFalse);
      expect(isSnoozeId(snooze), isTrue);
      expect(isDoseId(snooze), isFalse);
      // نفس الإزاحة جوّه النطاقين — الخانة هي هي
      expect(snooze - snoozeIdBase, dose - doseIdBase);
    });

    test('نطاق التأجيل ما بيلمسش نطاق الجرعات ولا سقف أندرويد', () {
      expect(snoozeIdBase, greaterThanOrEqualTo(doseIdLimit));
      expect(snoozeIdLimit, lessThan(2147483647));
    });

    test('الـpayload بيتفك لنفس اليوم ونفس الجداول', () {
      final encoded = encodePayloadFor(DateTime(2026, 8, 31, 8), ['4', '9']);
      final decoded = decodePayload(encoded)!;

      expect(decoded.routineDay, DateTime(2026, 8, 31));
      expect(decoded.scheduleIds, ['4', '9']);
    });

    test('payload غريب أو فاضي بيرجّع null بدل ما يرمي', () {
      expect(decodePayload(null), isNull);
      expect(decodePayload('مش json'), isNull);
      expect(decodePayload('{"v":2,"day":"2026-08-31","scheduleIds":["1"]}'),
          isNull);
      expect(decodePayload('{"v":1,"day":"2026-08-31","scheduleIds":[]}'),
          isNull);
    });

    test('نص التذكير من أسماء جاهزة زي نص المحرك', () {
      expect(reminderBodyFor([(name: 'Concor', amount: 'قرص')]), 'Concor — قرص');
      expect(
        reminderBodyFor([(name: 'A', amount: null), (name: 'B', amount: null)]),
        '٢ أدوية دلوقتي: A + B',
      );
    });
  });
}
