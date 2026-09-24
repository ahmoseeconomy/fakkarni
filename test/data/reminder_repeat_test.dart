import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/escalation/repeat_alerts.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';

import '../support/seeded_clock.dart';

/// **إعادة التنبيه: نفس التذكير تاني كل ٥ دقايق لحد ٣ مرات — والسلّم
/// ما اتلمسش.**
///
/// الاختبارات هنا بتثبت تلات حاجات مع بعض: الإعادة بتتجدول وبتتلغي
/// بالقاعدة الخامسة، ونطاقاتها مش بتدوس على أي نطاق تاني، وسلّم التصعيد
/// (+١٥/+٣٠) ومهلة السيرفر (٦٠) بأرقامهم ومواعيدهم زي ما هم بالحرف.
class _Sink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];

  Map<int, PlannedNotification> get repeats => {
        for (final e in scheduled.entries)
          if (isRepeatId(e.key)) e.key: e.value,
      };

  Map<int, PlannedNotification> get escalations => {
        for (final e in scheduled.entries)
          if (isEscalationId(e.key)) e.key: e.value,
      };

  Map<int, PlannedNotification> get doses => {
        for (final e in scheduled.entries)
          if (isDoseId(e.key)) e.key: e.value,
      };

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
}

final _routine = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final _aug31 = DateTime(2026, 8, 31);
final _six = DateTime(2026, 8, 31, 6);
final _seven = DateTime(2026, 8, 31, 7);

DoseSchedule _dose(String name, DayAnchor anchor, {int offset = 0}) => DoseSchedule(
      id: name,
      medicationName: name,
      timing: AnchorTiming(anchor, offset),
      repeat: DoseRepeat.daily,
      durationDays: null,
      amountLabel: null,
      startDate: _aug31,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('١ — الدومين نقي: +٥ و+١٠ و+١٥ من الأصل', () {
    test('تلات إعادات كل خمس دقايق، محسوبة من معاد الجرعة مش من اللي قبلها', () {
      expect(repeatEvery, const Duration(minutes: 5));
      expect(maxRepeats, 3);
      final steps = repeatsFor(_seven);
      expect(steps.map((s) => s.at), [
        DateTime(2026, 8, 31, 7, 5),
        DateTime(2026, 8, 31, 7, 10),
        DateTime(2026, 8, 31, 7, 15),
      ]);
      for (final s in steps) {
        expect(s.at.difference(_seven), s.delay);
      }
    });

    test('بتعدّي نص الليل بتاريخ صح', () {
      final steps = repeatsFor(DateTime(2026, 8, 31, 23, 55));
      expect(steps.last.at, DateTime(2026, 9, 1, 0, 10));
    });

    test('آخر إعادة على نفس دقيقة أول درجة — وده اللي المخطّط بيحلّه', () {
      expect(repeatsFor(_seven).last.at, ladderFor(_seven).first.at);
    });
  });

  group('٢ — الأرقام: عشر نطاقات على ٨٠ لحد ١٧٠ مليون', () {
    test('كل إعادة في نطاقها، والنطاق بيبدأ على حد ١٠ مليون', () {
      expect(repeatIdBase, 80000000);
      expect(maxRepeatsAny, 10, reason: '«مستمر» بعشرة');
      expect(repeatIdFor(_seven, 0), greaterThanOrEqualTo(80000000));
      expect(repeatIdFor(_seven, 1), greaterThanOrEqualTo(90000000));
      expect(repeatIdFor(_seven, 2), greaterThanOrEqualTo(100000000));
      expect(repeatIdFor(_seven, 9), greaterThanOrEqualTo(170000000));
      for (var i = 0; i < maxRepeatsAny; i++) {
        final id = repeatIdFor(_seven, i);
        expect(repeatIndexOf(id), i);
        expect(isRepeatId(id), isTrue);
        expect(isRescheduledId(id), isTrue, reason: 'الإعادة بتتبني من الخطة زي السلّم');
        expect(isDoseId(id), isFalse);
        expect(isEscalationId(id), isFalse);
        expect(isSnoozeId(id), isFalse);
        expect(isFastingId(id), isFalse);
        expect(isCheckupId(id), isFalse);
        expect(isAppointmentId(id), isFalse);
        expect(isCaregiverAppointmentId(id), isFalse);
      }
      expect(repeatIndexOf(notificationIdFor(_seven)), isNull);
      expect(() => repeatIdFor(_seven, 10), throwsRangeError);
      expect(() => repeatIdFor(_seven, -1), throwsRangeError);
    });

    test('مشتق من الخانة الأصلية: نفس المريض ونفس الخانة = نفس الرقم', () {
      expect(repeatIdFor(_seven, 1), repeatIdFor(DateTime(2026, 8, 31, 7), 1));
      expect(repeatIdFor(_seven, 1, patientIndex: 3), isNot(repeatIdFor(_seven, 1)));
    });

    test('ولا تقاطع مع أي نطاق تاني — عند الأقصى، وتحت سقف أندرويد', () {
      final ranges = <String, (int, int)>{
        'الجرعات': (doseIdBase, doseIdLimit),
        'السلّم ١': (escalationFirstIdBase, escalationFirstIdBase + maxPatients * patientIdSpan),
        'التأجيل': (snoozeIdBase, snoozeIdBase + maxPatients * patientIdSpan),
        'السلّم ٢': (escalationSecondIdBase, escalationSecondIdBase + maxPatients * patientIdSpan),
        'الصيام': (fastingIdBase, fastingIdLimit),
        'المتابعات': (checkupIdBase, checkupIdLimit),
        'المواعيد': (appointmentIdBase, appointmentIdLimit),
        'مواعيد الابن': (caregiverAppointmentIdBase, caregiverAppointmentIdLimit),
        for (var i = 0; i < maxRepeatsAny; i++)
          'إعادة $i': (
            repeatIdFor(DateTime.utc(1970), i),
            repeatIdFor(DateTime.utc(1970), i, patientIndex: maxPatients - 1) + patientIdSpan,
          ),
      };
      final names = ranges.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final (aLo, aHi) = ranges[names[i]]!;
          final (bLo, bHi) = ranges[names[j]]!;
          expect(aLo < bHi && bLo < aHi, isFalse,
              reason: '«${names[i]}» و«${names[j]}» متداخلين');
        }
      }
      expect(repeatIdLimit, lessThan(2147483647));
      expect(repeatIdFor(DateTime.utc(1970, 2, 1, 23, 59), 9, patientIndex: maxPatients - 1),
          lessThan(repeatIdLimit));
    });
  });

  group('٣ — الميزانية: الجرعات دفعت، السلّم لأ', () {
    test('٢٤ + ١٤ + ٢ + ٢ + ٢ + ٢٠ = ٦٤', () {
      expect(maxPendingRepeats, 20, reason: '«مستمر» لتذكيرين، أو «يتكرر» لستة');
      expect(maxPendingReminders, 24);
      expect(maxPendingEscalations, 14, reason: 'السلّم ما اتقصّش');
      expect(
        maxPendingReminders +
            maxPendingEscalations +
            snoozePendingSlack +
            fastingPendingSlack +
            checkupPendingSlack +
            maxPendingRepeats,
        iosPendingLimit,
      );
    });
  });

  group('٤ — التخطيط نقي', () {
    final schedules = [_dose('Concor', DayAnchor.breakfast, offset: -30)];
    List<PlannedNotification> reminders({DateTime? from}) =>
        planWindow(routine: _routine, schedules: schedules, from: from ?? _six);

    test('كل درجات السلّم شغّالة → إعادتين (+٥، +١٠): الـ+١٥ بتاعة الدرجة', () {
      final planned = planRepeats(reminders(), from: _six);
      final forSeven = planned.where((p) => p.payload == reminders().first.payload).toList();
      expect(forSeven.map((p) => p.at), [
        DateTime(2026, 8, 31, 7, 5),
        DateTime(2026, 8, 31, 7, 10),
      ]);
      expect(forSeven.every((p) => p.kind == NotificationKind.repeat), isTrue);
      expect(forSeven.map((p) => p.id), [repeatIdFor(_seven, 0), repeatIdFor(_seven, 1)]);
    });

    test('درجة +١٥ مقفولة → التالتة بتملا مكانها', () {
      final planned = planRepeats(reminders(), from: _six, enabledRungs: {EscalationRung.second});
      expect(planned.where((p) => p.id == repeatIdFor(_seven, 2)), hasLength(1));
      final none = planRepeats(reminders(), from: _six, enabledRungs: const {});
      expect(none.where((p) => p.doses.first.medicationName == 'Concor' && p.at.day == 31),
          hasLength(3));
    });

    test('اللي معادها فات ما بتتجدولش، واللي جاية بتتجدول', () {
      final seven07 = DateTime(2026, 8, 31, 7, 7);
      final planned = planRepeats(reminders(from: DateTime(2026, 8, 31, 6, 22)), from: seven07);
      expect(planned.map((p) => p.id), isNot(contains(repeatIdFor(_seven, 0))));
      expect(planned.map((p) => p.id), contains(repeatIdFor(_seven, 1)));
    });

    test('الميزانية خانات: «يتكرر» بإعادتين بيغطّي ١٠ تذكيرات، والأقرب الأول، واللي فاتت ما بتاخدش خانة', () {
      final many = [
        for (var i = 0; i < 12; i++) _dose('M$i', DayAnchor.breakfast, offset: -30 + i * 20),
      ];
      final rems = planWindow(routine: _routine, schedules: many, from: _six);
      final planned = planRepeats(rems, from: _six);
      final covered = {for (final p in planned) p.payload};
      // +١٥ بتاعة الدرجة، فكل تذكير بياخد إعادتين: ٢٠ ÷ ٢ = ١٠ تذكيرات
      expect(covered.length, 10);
      expect(planned.length, maxPendingRepeats);
      expect(covered, {for (final r in rems.take(10)) r.payload}, reason: 'الأقرب الأول');

      // ٧:٠٠ رنّت من نص ساعة — إعاداتها كلها فاتت، وما بتاخدش خانة
      final later = DateTime(2026, 8, 31, 7, 30);
      final shifted = planWindow(routine: _routine, schedules: many,
          from: DateTime(2026, 8, 31, 6, 45));
      final planned2 = planRepeats(shifted, from: later);
      final covered2 = {for (final p in planned2) p.payload};
      expect(covered2, isNot(contains(rems.first.payload)));
      expect(covered2.length, 10);
    });

    test('«مرة واحدة»: ولا إعادة — والسلّم ما بيتلمسش', () {
      final planned = planRepeats(reminders(), from: _six, modeOf: (_) => AlertMode.once);
      expect(planned, isEmpty);
      expect(planEscalations(reminders(), from: _six), isNotEmpty);
    });

    test('«مستمر»: كل ٣ دقايق لحد نص ساعة — عشرة، ناقص اللي على دقيقة درجة شغّالة', () {
      final rems = reminders();
      final planned = planRepeats(rems, from: _six, modeOf: (_) => AlertMode.continuous);
      final mine = planned.where((p) => p.payload == rems.first.payload).toList();
      expect(mine.map((p) => p.at.difference(_seven).inMinutes), [3, 6, 9, 12, 18, 21, 24, 27],
          reason: '+١٥ و+٣٠ بتوع السلّم');
      final none = planRepeats(rems, from: _six, modeOf: (_) => AlertMode.continuous, enabledRungs: const {});
      expect(none.where((p) => p.payload == rems.first.payload).length, AlertMode.continuous.count);
      expect(mine.map((p) => p.body).first, endsWith('فات ٣ دقايق'));
      expect(mine.map((p) => p.body).last, endsWith('فات ٢٧ دقيقة'));
    });

    test('«مستمر» بياخد الميزانية كلها لأقرب تذكيرين — والتالت بياخد اللي فاضل', () {
      final many = [
        for (var i = 0; i < 4; i++) _dose('M$i', DayAnchor.breakfast, offset: -30 + i * 60),
      ];
      final rems = planWindow(routine: _routine, schedules: many, from: _six);
      final planned = planRepeats(rems, from: _six, modeOf: (_) => AlertMode.continuous, enabledRungs: const {});
      expect(planned.length, maxPendingRepeats);
      final byReminder = <String, int>{};
      for (final p in planned) {
        byReminder[p.payload] = (byReminder[p.payload] ?? 0) + 1;
      }
      expect(byReminder[rems[0].payload], 10);
      expect(byReminder[rems[1].payload], 10);
      expect(byReminder[rems[2].payload], isNull, reason: 'الميزانية خلصت — الأقرب الأول');
    });

    test('تذكير مجمّع بياخد الأقوى بين أدويته، ودوا من غير نوع بياخد إعداد الجهاز', () {
      expect(AlertMode.strongest([AlertMode.once, AlertMode.continuous, AlertMode.repeating]),
          AlertMode.continuous);
      expect(AlertMode.strongest(const []), AlertMode.once);
      final quiet = _dose('q', DayAnchor.breakfast, offset: -30);
      final loud = DoseSchedule(
        id: 'l', medicationName: 'l', timing: const AnchorTiming(DayAnchor.breakfast, -30),
        repeat: DoseRepeat.daily, startDate: _aug31, alertMode: AlertMode.continuous,
      );
      final rems = planWindow(routine: _routine, schedules: [quiet, loud], from: _six);
      expect(rems.first.doses, hasLength(2), reason: 'نفس الدقيقة → تذكير واحد');
      expect(alertModeOf(rems.first, fallback: AlertMode.once), AlertMode.continuous);
      expect(alertModeOf(planWindow(routine: _routine, schedules: [quiet], from: _six).first,
          fallback: AlertMode.once), AlertMode.once);
    });

    test('النص نفس سطر الجرعة وقدامه قد إيه فات، ونفس الحمولة ونفس العنوان', () {
      final rems = reminders();
      final planned = planRepeats(rems, from: _six, enabledRungs: const {});
      final r = rems.first;
      final mine = planned.where((p) => p.payload == r.payload).toList();
      expect(mine.map((p) => p.body), [
        '${r.body} — فات ٥ دقايق',
        '${r.body} — فات ١٠ دقايق',
        '${r.body} — فات ربع ساعة',
      ]);
      expect(mine.every((p) => p.title == r.title), isTrue);
      expect(mine.every((p) => p.doses == r.doses), isTrue);
    });
  });

  group('٥ — على الجهاز', () {
    late AppDatabase db;
    late MedicationRepository meds;
    late PreferencesRepository prefs;
    late _Sink sink;
    late ReminderScheduler scheduler;
    late int patientId;
    late int medId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final routines = RoutineRepository(db);
      meds = MedicationRepository(db, clock: seededLongAgo);
      prefs = PreferencesRepository(db);
      sink = _Sink();
      patientId = await routines.ensurePatient();
      await routines.saveRoutine(patientId, _routine);
      scheduler = ReminderScheduler(
        routines: routines,
        medications: meds,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: sink,
        preferences: prefs,
      );
      medId = await meds.addMedication(
        patientId: patientId,
        name: 'Concor',
        timing: AnchorTiming(DayAnchor.breakfast, -30),
        startDate: _aug31,
      );
    });

    tearDown(() => db.close());

    test('الإعادات بتتجدول مع الجرعات والسلّم، وكله تحت الـ٦٤', () async {
      await scheduler.rescheduleAll(now: _six);
      expect(sink.repeats.length, 14, reason: '٧ تذكيرات في النافذة المزاحة × إعادتين (+١٥ بتاعة الدرجة)');
      expect(sink.repeats.containsKey(repeatIdFor(_seven, 0)), isTrue);
      expect(sink.repeats.containsKey(repeatIdFor(_seven, 1)), isTrue);
      expect(sink.repeats.containsKey(repeatIdFor(_seven, 2)), isFalse);
      expect(
        sink.scheduled.length + snoozePendingSlack + fastingPendingSlack + checkupPendingSlack,
        lessThanOrEqualTo(iosPendingLimit),
      );
    });

    test('«أخدته» بتلغي الإعادات العشرة مع التذكير في نفس اللحظة — القاعدة الخامسة', () async {
      await scheduler.rescheduleAll(now: _six);
      await scheduler.cancelReminderAt(_seven);
      for (var i = 0; i < maxRepeatsAny; i++) {
        expect(sink.cancelled, contains(repeatIdFor(_seven, i)));
        expect(sink.scheduled.containsKey(repeatIdFor(_seven, i)), isFalse);
      }
      // والتأكيد بيلغي خانته هو بس — إعادات بكرة لسه واقفة
      final tomorrow = DateTime(2026, 9, 1, 7);
      expect(sink.scheduled.containsKey(repeatIdFor(tomorrow, 0)), isTrue);
    });

    test('«فكّرني بعدين» بتلغي الإعادات كلها وبتسيب درجة +٣٠', () async {
      await scheduler.rescheduleAll(now: _six);
      await scheduler.snooze(
        originalAt: _seven,
        body: 'Concor',
        payload: '{}',
        now: DateTime(2026, 8, 31, 7, 2),
      );
      for (var i = 0; i < maxRepeatsAny; i++) {
        expect(sink.cancelled, contains(repeatIdFor(_seven, i)));
      }
      expect(sink.scheduled.containsKey(escalationIdFor(_seven, EscalationRung.second)), isTrue);
    });

    test('فتح التطبيق بعد ما الجرعة رنّت ما بيسكّتش الإعادة الجاية', () async {
      await scheduler.rescheduleAll(now: _six);
      await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 7, 7));
      expect(sink.cancelled, isNot(contains(repeatIdFor(_seven, 1))));
      expect(sink.scheduled.containsKey(repeatIdFor(_seven, 1)), isTrue);
    });

    test('جرعة اتأكدت من مكان تاني قبل إعادة الجدولة → إعاداتها المعلّقة بتتلغي', () async {
      await scheduler.rescheduleAll(now: _six);
      expect(sink.scheduled.containsKey(repeatIdFor(_seven, 0)), isTrue);

      // التأكيد وصل الصف من غير ما يعدّي على cancelReminderAt — «يومك»
      // بتنده afterConfirmation عادي؛ ده الطريق اللي ما بيندهش عليها
      final events = DoseEventRepository(db);
      final schedules = await meds.activeSchedules(patientId);
      await events.markTaken(int.parse(schedules.single.id), _aug31);

      await scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 6, 50));
      expect(sink.cancelled, containsAll([repeatIdFor(_seven, 0), repeatIdFor(_seven, 1)]));
      expect(sink.repeats.keys.where((id) => id == repeatIdFor(_seven, 0)), isEmpty);
    });

    test('درجة +١٥ مقفولة من «التنبيهات» → الإعادة التالتة بتتجدول مكانها', () async {
      await prefs.setRung(EscalationRung.first, false);
      await scheduler.rescheduleAll(now: _six);
      expect(sink.scheduled.containsKey(repeatIdFor(_seven, 2)), isTrue);
      expect(sink.scheduled.containsKey(escalationIdFor(_seven, EscalationRung.first)), isFalse);
      expect(sink.scheduled.containsKey(escalationIdFor(_seven, EscalationRung.second)), isTrue);
    });

    test('إعداد الجهاز «مستمر» → كل ٣ دقايق على الجهاز، والسلّم ١٤ زي ما هو', () async {
      await prefs.setAlertMode(AlertMode.continuous);
      await scheduler.rescheduleAll(now: _six);
      expect(sink.repeats.containsKey(repeatIdFor(_seven, 0)), isTrue);
      expect(sink.repeats[repeatIdFor(_seven, 0)]!.at, DateTime(2026, 8, 31, 7, 3));
      expect(sink.repeats.length, maxPendingRepeats);
      expect(sink.escalations.length, 14);
      expect(sink.scheduled.length + snoozePendingSlack + fastingPendingSlack + checkupPendingSlack,
          lessThanOrEqualTo(iosPendingLimit));
    });

    test('نوع الدوا بيغلب إعداد الجهاز: «مرة واحدة» على الدوا → ولا إعادة، والدرجتين موجودين', () async {
      await meds.setAlertMode(medId, AlertMode.once);
      await scheduler.rescheduleAll(now: _six);
      expect(sink.repeats, isEmpty);
      expect(sink.escalations.length, 14);
    });

    test('**السلّم ما اتلمسش**: نفس الأرقام ونفس المواعيد بالحرف، من السلّم النقي', () async {
      await scheduler.rescheduleAll(now: _six);

      // الحكم: كل تذكير من أقرب ٧ ليه درجتين بالظبط عند +١٥ و+٣٠
      final doseReminders = sink.doses.values.toList()..sort((a, b) => a.at.compareTo(b.at));
      final expected = <int, DateTime>{
        for (final r in doseReminders.take(maxPendingEscalations ~/ EscalationRung.values.length))
          for (final step in ladderFor(r.at))
            escalationIdFor(r.at, step.rung): step.at,
      };
      expect({for (final e in sink.escalations.entries) e.key: e.value.at}, expected);
      expect(sink.escalations.length, 14);

      // والأرقام الحاكمة زي ما هي
      expect(EscalationRung.first.delay, const Duration(minutes: 15));
      expect(EscalationRung.second.delay, const Duration(minutes: 30));
      expect(graceWindow, const Duration(minutes: 45));
      expect(serverGraceWindow, const Duration(minutes: 60));
      expect(serverGraceWindow, graceWindow + syncSlack);

      // ومفيش إعادة ولا درجة على نفس الدقيقة
      final minutes = <DateTime>{};
      for (final p in [...sink.escalations.values, ...sink.repeats.values]) {
        expect(minutes.add(p.at), isTrue, reason: 'إشعارين على ${p.at}');
      }
    });

    test('والإعادة بتعدّي على نفس أزرار الجرعة: نفس الحمولة اللي «أخدته» بتفكّها', () async {
      await scheduler.rescheduleAll(now: _six);
      final repeat = sink.repeats[repeatIdFor(_seven, 0)]!;
      final decoded = decodePayload(repeat.payload)!;
      expect(decoded.routineDay, _aug31);
      final engine = ScheduleEngine(_routine);
      final schedules = await meds.activeSchedules(patientId);
      expect(decoded.scheduleIds, [schedules.single.id]);
      expect(engine.resolve(schedules.single, _aug31), _seven);
    });
  });
}
