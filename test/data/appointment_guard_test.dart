import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/appointment_scheduler.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';

import '../support/seeded_clock.dart';

/// **القيد الأول في مواصفة المواعيد: ما نلمسش تذكير الدوا.**
///
/// النية مش ضمانة. الملف ده هو الضمانة — وأهم اختبار فيه هو الأول:
/// نفس خطة الجرعات بالظبط، **من غير مواعيد وبخمس مواعيد**.
class _Sink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];

  /// اللي معلّق **دلوقتي** — الجدولة بتزوّد والإلغاء بيشيل، زي الجهاز.
  Set<int> get live => scheduled.keys.toSet();

  /// أقصى عدد إشعارات مواعيد كانت معلّقة في **أي لحظة** خلال التشغيل.
  int peakAppointments = 0;

  @override
  Future<void> schedule(PlannedNotification n) async {
    scheduled[n.id] = n;
    final now = live.where(isAppointmentId).length;
    if (now > peakAppointments) peakAppointments = now;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<Set<int>> pendingIds() async => live;

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

final _now = DateTime(2026, 9, 15, 10);

void main() {
  late AppDatabase db;
  late _Sink sink;
  late ReminderScheduler scheduler;
  late CheckupService checkups;
  late int patientId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sink = _Sink();
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db, clock: seededLongAgo);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, _routine);
    // **تركيبة واقعية**: ٨ أدوية × ٣ جرعات، والسلّم شغّال.
    for (var i = 0; i < 8; i++) {
      await meds.addMedicationWithDoses(
        patientId: patientId,
        name: 'Med$i',
        amountLabel: 'قرص',
        timings: [
          AnchorTiming(DayAnchor.breakfast, -30 - i),
          AnchorTiming(DayAnchor.lunch, -30 - i),
          AnchorTiming(DayAnchor.dinner, -30 - i),
        ],
        startDate: DateTime(2026, 9, 1),
      );
    }
    scheduler = ReminderScheduler(
      routines: routines,
      medications: meds,
      events: DoseEventRepository(db),
      patientId: patientId,
      sink: sink,
    );
    checkups = CheckupService(db, sink);
  });

  tearDown(() => db.close());

  String code(String path) => File(path)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');


  /// بيحجز [n] ميعاد في متابعات مختلفة.
  Future<void> book(int n) async {
    for (var i = 0; i < n; i++) {
      final id = await checkups.start(patientId: patientId, title: 'متابعة $i', today: _now);
      await checkups.advance(id, now: _now); // → حجز المعمل
      await checkups.setStageDate(id, CheckupStage.labBooking,
          day: DateTime(2026, 9, 18 + i), now: _now);
    }
  }

  /// بصمة خطة الجرعات: الرقم والوقت والنوع — مفيش حاجة تانية بتفرق.
  Future<List<String>> dosePlan() async {
    sink.scheduled.clear();
    sink.cancelled.clear();
    await scheduler.rescheduleAll(now: _now);
    final out = [
      for (final n in sink.scheduled.values)
        if (!isAppointmentId(n.id)) '${n.id}|${n.at.toIso8601String()}|${n.kind.name}',
    ]..sort();
    return out;
  }

  group('١ — خطة الجرعات هي هي، بمواعيد ومن غيرها', () {
    test('صفر ميعاد vs خمس مواعيد → نفس المجموعة بالحرف', () async {
      final without = await dosePlan();
      expect(without, isNotEmpty, reason: 'الاختبار نفسه لازم يشوف خطة');

      await book(5);
      await AppointmentScheduler(
        db: db,
        patientId: patientId,
        sink: sink,
        rolling: true,
      ).refresh(now: _now);

      final with5 = await dosePlan();
      expect(with5, without, reason: 'المواعيد غيّرت خطة الجرعات');
    });

    test('والأسقف زي ما هي — بالرقم، مش بقراية نفسها', () {
      // ٤٤ ← ٣٢ مع إعادة التنبيه، ← ٢٤ مع نوع «مستمر» (٢٠ خانة) — الجرعات دفعت، السلّم لأ
      expect(maxPendingReminders, 24);
      expect(maxPendingRepeats, 20);
      expect(maxPendingEscalations, 14);
      expect(snoozePendingSlack, 2);
      expect(fastingPendingSlack, 2);
      expect(checkupPendingSlack, 2);
      expect(iosPendingLimit, 64);
    });
  });

  group('٢ — سكّة لوحدها', () {
    test('`rescheduleAll` ما بتعرفش حاجة عن المواعيد', () {
      final source = code('lib/data/services/reminder_scheduler.dart');
      for (final word in ['appointment', 'Appointment', 'refreshAppointments']) {
        expect(source.contains(word), isFalse,
            reason: 'سكّة الجرعات بتعرف عن المواعيد — «$word»');
      }
    });

    test('ونداء المواعيد بيجي **بعد** الجرعات في كل مكان بينده الاتنين', () {
      for (final path in ['lib/main.dart', 'lib/app/root.dart']) {
        final source = code(path);
        final dose = source.indexOf('rescheduleAll');
        final appointment = source.indexOf('refreshAppointments');
        expect(dose, greaterThanOrEqualTo(0), reason: path);
        expect(appointment, greaterThan(dose),
            reason: '$path: المواعيد قبل الجرعات — استثناء فيها بيمنع جرعة');
      }
    });

    test('المواعيد في try/catch بتاعها — استثناء فيها ما بيوقّعش حاجة', () {
      final source = code('lib/app/app_scope.dart');
      expect(source, contains('Future<void> refreshAppointments'));
      expect(source, contains('} catch (error, stack) {'));
    });
  });

  group('٣ — أرقام منفصلة تماماً', () {
    test('نطاق المواعيد مالوش أي تقاطع مع أي نطاق تاني — عند الأقصى', () {
      final ranges = <String, (int, int)>{
        'الجرعات': (doseIdBase, doseIdLimit),
        'السلّم ١': (escalationFirstIdBase, escalationFirstIdBase + maxPatients * patientIdSpan),
        'التأجيل': (snoozeIdBase, snoozeIdBase + maxPatients * patientIdSpan),
        'السلّم ٢': (escalationSecondIdBase, escalationSecondIdBase + maxPatients * patientIdSpan),
        'الصيام': (fastingIdBase, fastingIdBase + maxPatients * patientIdSpan),
        'المتابعات': (checkupIdBase, checkupIdLimit),
        'المواعيد': (appointmentIdBase, appointmentIdLimit),
        'مواعيد الابن': (caregiverAppointmentIdBase, caregiverAppointmentIdLimit),
        'الإعادات': (repeatIdBase, repeatIdLimit),
      };
      final names = ranges.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final (aLo, aHi) = ranges[names[i]]!;
          final (bLo, bHi) = ranges[names[j]]!;
          expect(aLo < bHi && bLo < aHi, isFalse,
              reason: '«${names[i]}» و«${names[j]}» متداخلين — '
                  'جدولة برقم موجود بتستبدله في صمت');
        }
      }
    });

    test('وأقصى يوم لسه جوّه نطاقه، واللي بعده بيرمي', () {
      // الرقم بقى مشتق من **اليوم**: النطاق سايع `appointmentDaySpan` يوم
      // من ١٩٧٠ — أكتر من ثمن آلاف سنة، فمفيش يوم حقيقي بيوصل حدّه.
      final lastDay = DateTime.fromMillisecondsSinceEpoch(
          (appointmentDaySpan - 1) * Duration.millisecondsPerDay,
          isUtc: true);
      final top = appointmentIdFor(lastDay, AppointmentNotice.dayOf);
      expect(isAppointmentId(top), isTrue);
      expect(top, lessThan(appointmentIdLimit));

      final past = DateTime.fromMillisecondsSinceEpoch(
          appointmentDaySpan * Duration.millisecondsPerDay,
          isUtc: true);
      expect(() => appointmentIdFor(past, AppointmentNotice.dayOf), throwsRangeError);
      // ويوم قبل ١٩٧٠ بيرمي كمان — مفيش ميعاد هناك، والسالب بيلفّ لبرّه
      expect(() => appointmentIdFor(DateTime(1969, 12, 31), AppointmentNotice.dayOf),
          throwsRangeError);
    });

    test('ونطاق الابن بيرمي عند نفس الحد', () {
      final past = DateTime.fromMillisecondsSinceEpoch(
          appointmentDaySpan * Duration.millisecondsPerDay,
          isUtc: true);
      expect(() => caregiverAppointmentIdFor(past, AppointmentNotice.dayOf), throwsRangeError);
    });

    test('ومش في نطاق إعادة الجدولة — إعادة بناء الجرعات ما بتلغيهاش', () {
      final day = DateTime(2026, 9, 20);
      expect(isRescheduledId(appointmentIdFor(day, AppointmentNotice.dayBefore)), isFalse);
      expect(isRescheduledId(caregiverAppointmentIdFor(day, AppointmentNotice.dayOf)), isFalse);
    });
  });

  group('٤ و٥ — إلغاء بالرقم، ومنبّه غير دقيق', () {
    // **التعليقات بتتشال الأول.** الشرح نفسه بيسمّي اللي إحنا مانعينه
    // («مفيش cancelAll»، «المنبّه الدقيق للجرعات»)، ومقارنة على نص فيه
    // شرح بتقيس التعليق مش الكود — نفس درس `battery_policy_test`.
    test('ولا `cancelAll` في أي ملف مواعيد', () {
      for (final path in [
        'lib/data/services/appointment_scheduler.dart',
        'lib/data/services/appointment_plan.dart',
      ]) {
        expect(code(path).contains('cancelAll'), isFalse, reason: path);
      }
    });

    test('سكّة المواعيد ما بتستعملش المنبّه الدقيق', () {
      final service = code('lib/core/notifications/notification_service.dart');
      final start = service.indexOf('scheduleAppointment');
      final end = service.indexOf('static Future<void> cancel(', start);
      final body = service.substring(start, end);
      expect(body, contains('AndroidScheduleMode.inexactAllowWhileIdle'));
      // **بالبادئة `AndroidScheduleMode.`**: `inexactAllowWhileIdle`
      // بيحتوي `exactAllowWhileIdle` كنص فرعي، فالمقارنة من غير البادئة
      // كانت بتوقّع على الحاجة الصح.
      expect(body.contains('AndroidScheduleMode.exactAllowWhileIdle'), isFalse,
          reason: 'المنبّه الدقيق مورد مقنّن ومحجوز للجرعات');
    });

    test('والمواعيد بتلغي أرقامها هي بس', () async {
      await book(1);
      sink.cancelled.clear();
      await AppointmentScheduler(db: db, patientId: patientId, sink: sink, rolling: true)
          .refresh(now: _now);
      expect(sink.cancelled.where((id) => !isAppointmentId(id)), isEmpty);
    });
  });
}
