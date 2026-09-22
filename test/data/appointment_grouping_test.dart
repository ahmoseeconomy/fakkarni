// **إشعار واحد لكل لحظة، مش واحد لكل ميعاد — والعطل اللي عمله.**
//
// آيفون حقيقي، صبح ٢٢ سبتمبر ٢٠٢٦: **أربع إشعارات** عن نفس الصبح.
//   «النهارده ميعادك في المعمل» / «تقرير تحليل — 6 نتايج»    ← الجديد
//   «النهارده عندك زيارة» / «من غير اسم دكتور»                 ← الجديد
//   «متابعة تقرير تحليل — 6 نتايج» / «النهارده ميعادك…»      ← القديم
//   «متابعة من غير اسم دكتور» / «النهارده معاد زيارتك.»       ← القديم
//
// تلات أعطال في الأربعة دول، وكل واحد له مجموعته هنا:
//   ١. صفوف اتحطّ ميعادها **قبل** الترقية فضلت ماسكة إشعارها القديم.
//   ٢. ميعادين في يوم واحد = رنّتين، كل واحدة بنصّ الخبر.
//   ٣. المتن بيعرض عنوان الورقة الخام — وفيه رقم لاتيني.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/appointment_scheduler.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/health/follow_up.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';

class _Sink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];

  Set<int> get live => scheduled.keys.toSet();

  @override
  Future<void> schedule(PlannedNotification n) async => scheduled[n.id] = n;

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
final _day = DateTime(2026, 9, 20);

void main() {
  late AppDatabase db;
  late _Sink sink;
  late CheckupService checkups;
  late int patientId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sink = _Sink();
    final routines = RoutineRepository(db);
    patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, _routine);
    checkups = CheckupService(db, sink);
  });

  tearDown(() => db.close());

  /// متابعة تحليل بميعاد معمل في اليوم ده.
  Future<int> lab(DateTime day, {String title = 'صورة دم'}) async {
    final id = await checkups.start(patientId: patientId, title: title, today: _now);
    await checkups.advance(id, now: _now); // → حجز المعمل
    await checkups.setStageDate(id, CheckupStage.labBooking, day: day, now: _now);
    return id;
  }

  /// متابعة زيارة بميعاد في اليوم ده.
  Future<int> visit(DateTime day, {String title = 'د. حسام'}) async {
    final id = await checkups.start(
        patientId: patientId, kind: FollowKind.visit, title: title, today: _now);
    await checkups.setStageDate(id, VisitStage.booked, day: day, now: _now);
    return id;
  }

  Future<void> refresh({bool rolling = false, DateTime? now}) =>
      AppointmentScheduler(db: db, patientId: patientId, sink: sink, rolling: rolling)
          .refresh(now: now ?? _now);

  PlannedNotification notice(DateTime day, AppointmentNotice which) =>
      sink.scheduled[appointmentIdFor(day, which)]!;

  group('١ — بقايا النسخة القديمة بتتشال في التوفيق', () {
    /// إشعار زي اللي النسخة القديمة كانت بتسيبه: رقم من نطاق المتابعات.
    void plantLegacy(int recordId, int slot) {
      final id = checkupIdFor(recordId, slot);
      sink.scheduled[id] = PlannedNotification(
        id: id,
        at: _day,
        title: 'متابعة تقرير تحليل — 6 نتايج',
        body: 'النهارده ميعادك في المعمل.',
        payload: '',
        kind: NotificationKind.appointmentAlert,
      );
    }

    test('إشعار قديم معلّق بيتلغي من أول تشغيلة، والجديدين بيفضلوا', () async {
      final id = await lab(_day);
      plantLegacy(id, 0);
      expect(sink.live.where(isCheckupId), hasLength(1));

      await refresh();

      expect(sink.live.where(isCheckupId), isEmpty,
          reason: 'الصف اتحطّ ميعاده قبل الترقية — إشعاره القديم كان بيفضل للأبد');
      expect(sink.cancelled, contains(checkupIdFor(id, 0)));
      expect(sink.live.where(isAppointmentId), hasLength(2), reason: 'والجديدين مكانهم');
    });

    test('وبتتشال حتى لو الصف اتمسح — القراية من المعلّق مش من الصفوف', () async {
      // رقم صف مش موجود خالص: الصف اتمسح والإشعار فضل.
      plantLegacy(9999, 2);
      await refresh();
      expect(sink.live.where(isCheckupId), isEmpty);
    });

    test('وبتتعاد من غير أثر — مفيش حاجة تتلغي في التشغيلة التانية', () async {
      await lab(_day);
      await refresh();
      sink.cancelled.clear();
      await refresh();
      expect(sink.cancelled, isEmpty);
      expect(sink.live.where(isAppointmentId), hasLength(2));
    });

    test('**وما بتقربش من نطاق الجرعات ولا الصيام**', () async {
      final dose = PlannedNotification(
        id: doseIdBase + 7,
        at: _day,
        title: 'جرعة',
        body: '',
        payload: '',
        kind: NotificationKind.dose,
      );
      final fasting = PlannedNotification(
        id: fastingIdFor(3),
        at: _day,
        title: 'صيام',
        body: '',
        payload: '',
        kind: NotificationKind.fasting,
      );
      sink.scheduled[dose.id] = dose;
      sink.scheduled[fasting.id] = fasting;

      await lab(_day);
      await refresh();

      expect(sink.cancelled, isNot(contains(dose.id)));
      expect(sink.cancelled, isNot(contains(fasting.id)));
      expect(sink.live, containsAll([dose.id, fasting.id]));
    });
  });

  group('٢ — إشعار واحد لكل لحظة', () {
    test('ميعادين في يوم واحد = إشعارين لليوم كله، مش أربعة', () async {
      await visit(_day);
      await lab(_day);
      await refresh();

      expect(sink.live.where(isAppointmentId), hasLength(2),
          reason: 'واحد امبارحه وواحد في يومه — مش واحد لكل ميعاد');
      expect(sink.live, {
        appointmentIdFor(_day, AppointmentNotice.dayBefore),
        appointmentIdFor(_day, AppointmentNotice.dayOf),
      });
    });

    test('والعنوان بيسمّي الاتنين', () async {
      await visit(_day);
      await lab(_day);
      await refresh();

      expect(notice(_day, AppointmentNotice.dayOf).title,
          'النهارده عندك: زيارة الدكتور، وميعاد المعمل');
      expect(notice(_day, AppointmentNotice.dayBefore).title,
          'بكرة عندك: زيارة الدكتور، وميعاد المعمل');
    });

    test('ومن تلاتة وفوق: الأولين بالاسم، والباقي «وحاجة كمان»', () async {
      await visit(_day);
      await lab(_day, title: 'صورة دم');
      // متابعة تانية عندها ميعاد دكتور في نفس اليوم
      final third = await checkups.start(patientId: patientId, title: 'وظايف كبد', today: _now);
      for (var i = 0; i < 5; i++) {
        await checkups.advance(third, now: _now); // → النتيجة وصلت
      }
      await checkups.setStageDate(third, CheckupStage.resultArrived, day: _day, now: _now);
      await refresh();

      expect(notice(_day, AppointmentNotice.dayOf).title, endsWith('، وحاجة كمان'));
      expect(sink.live.where(isAppointmentId), hasLength(2));
    });

    test('وميعاد واحد بيفضل بكلامه القديم — مفيش «عندك:» على واحد', () async {
      await lab(_day);
      await refresh();
      expect(notice(_day, AppointmentNotice.dayOf).title, 'النهارده ميعادك في المعمل');
      expect(notice(_day, AppointmentNotice.dayBefore).title, 'بكرة ميعادك في المعمل');
    });

    test('ويومين مختلفين بيفضلوا إشعارين لكل يوم', () async {
      await lab(_day);
      await visit(DateTime(2026, 9, 22));
      await refresh();
      expect(sink.live.where(isAppointmentId), hasLength(4));
    });

    test('**ونافذة iOS بقت تغطّي يوم كامل بخانتين**', () async {
      // نفس الخانتين، بس بقوا بيشيلوا كل مواعيد أقرب يوم بدل ميعاد واحد.
      await visit(_day);
      await lab(_day);
      await lab(DateTime(2026, 9, 25), title: 'الأبعد');
      await refresh(rolling: true);

      expect(sink.live.where(isAppointmentId), hasLength(checkupPendingSlack));
      expect(notice(_day, AppointmentNotice.dayOf).title, contains('زيارة الدكتور'));
      expect(notice(_day, AppointmentNotice.dayOf).title, contains('ميعاد المعمل'));
    });
  });

  group('٣ — أرقام عربية واسم المتابعة في الإشعار', () {
    /// العنوان اللي جه من الجهاز الحقيقي، برقمه اللاتيني.
    const rawLab = 'تقرير تحليل — 6 نتايج';

    test('المتن بيعرض اسم المتابعة، مش عنوان الورقة الخام', () async {
      await lab(_day, title: rawLab);
      await refresh();
      expect(notice(_day, AppointmentNotice.dayOf).body, 'متابعة تحليل');
    });

    test('وزيارة من غير اسم دكتور بتتقال «متابعة زيارة»', () async {
      await visit(_day, title: 'من غير اسم دكتور');
      await refresh();
      expect(notice(_day, AppointmentNotice.dayOf).body, 'متابعة زيارة');
    });

    test('**ولا رقم لاتيني في أي عنوان إشعار ميعاد** — العناوين كلها بتاعتنا',
        () async {
      // كل شكل ممكن: ميعاد واحد، ميعادين، تلاتة، والمرحلتين التانيتين.
      await lab(_day, title: rawLab);
      await visit(_day, title: 'من غير اسم دكتور');
      await lab(DateTime(2026, 9, 23), title: 'وظايف كبد');
      await refresh();

      final latin = RegExp(r'[0-9]');
      final notices = sink.scheduled.values.where((n) => isAppointmentId(n.id));
      expect(notices, isNotEmpty, reason: 'الحارس عدّى فاضي');
      for (final n in notices) {
        expect(latin.hasMatch(n.title), isFalse, reason: 'عنوان: «${n.title}»');
        expect(latin.hasMatch(n.body), isFalse, reason: 'متن: «${n.body}»');
      }
    });

    test('**واللي كتبه إنسان بيعدّي زي ما هو — ده قرار مش ثغرة**', () async {
      // نفس قاعدة `lab_title_digits_test`: الأرقام اللي في عنوان كتبه
      // إنسان بتاعته هو، وفيه أسامي تحاليل فيها أرقام لاتينية (`HbA1c`)
      // تحويلها بيبوّظها. اللي إحنا مسؤولين عنه هو اللي **إحنا** بنولّده.
      await lab(_day, title: 'CBC 2026');
      await refresh();
      expect(notice(_day, AppointmentNotice.dayOf).body, 'CBC 2026');
      expect(notice(_day, AppointmentNotice.dayOf).title,
          isNot(matches(RegExp(r'[0-9]'))));
    });
  });

  group('التوفيق هو صاحب النطاق', () {
    test('شيل ميعاد واحد من يوم فيه اتنين ما بيطفّيش إشعار التاني', () async {
      final v = await visit(_day);
      await lab(_day);
      await refresh();
      expect(sink.live.where(isAppointmentId), hasLength(2));

      await checkups.clearStageDate(v, VisitStage.booked);
      await refresh();

      // الإشعار لسه موجود — بس بقى عن الميعاد الفاضل لوحده
      expect(sink.live.where(isAppointmentId), hasLength(2));
      expect(notice(_day, AppointmentNotice.dayOf).title, 'النهارده ميعادك في المعمل');
    });

    test('ولما اليوم يفضى خالص الإشعارين بيتلغوا', () async {
      final v = await visit(_day);
      await refresh();
      await checkups.clearStageDate(v, VisitStage.booked);
      await refresh();

      expect(sink.live.where(isAppointmentId), isEmpty);
      final rows = await RecordsRepository(db).all(patientId);
      expect(CheckupService.stageDateOf(rows.single, VisitStage.booked), isNull);
    });
  });
}
