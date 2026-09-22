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
import 'package:fakkarni/domain/scheduling/day_routine.dart';

/// **إشعارات المواعيد: هادي امبارحه، وواحد بيرن في يومه.**
///
/// المنصّتين مختلفين عن قصد وده متختبر هنا: iOS نافذة متدحرجة بخانتين
/// (سقف الـ٦٤ بيرمي الزيادة في صمت، وممكن يرمي جرعة)، وأندرويد بيجدول
/// الكل من ساعة الحجز (مفيش سقف، والنافذة بتعتمد على فتح التطبيق — وده
/// أقل حاجة مضمونة هناك بسبب قتلة البطارية).
class _Sink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];
  int peak = 0;

  Set<int> get live => scheduled.keys.toSet();

  @override
  Future<void> schedule(PlannedNotification n) async {
    scheduled[n.id] = n;
    final now = live.where(isAppointmentId).length;
    if (now > peak) peak = now;
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

  /// بيحجز ميعاد معمل في اليوم ده ويرجّع رقم الصف.
  Future<int> book(DateTime day, {String title = 'صورة دم'}) async {
    final id = await checkups.start(patientId: patientId, title: title, today: _now);
    await checkups.advance(id, now: _now); // → حجز المعمل
    await checkups.setStageDate(id, CheckupStage.labBooking, day: day, now: _now);
    return id;
  }

  Future<void> refresh({required bool rolling, DateTime? now}) =>
      AppointmentScheduler(db: db, patientId: patientId, sink: sink, rolling: rolling)
          .refresh(now: now ?? _now);

  group('الإشعارين', () {
    test('الهادي امبارحه على العشا، واللي بيرن في يومه على الصحيان', () async {
      final day = DateTime(2026, 9, 20);
      await book(day);
      await refresh(rolling: false);

      // **الرقم مشتق من اليوم** — كل مواعيد اليوم الواحد إشعارهم واحد.
      final before = sink.scheduled[appointmentIdFor(day, AppointmentNotice.dayBefore)]!;
      final dayOf = sink.scheduled[appointmentIdFor(day, AppointmentNotice.dayOf)]!;

      expect(before.at, DateTime(2026, 9, 19, 20));
      expect(before.kind, NotificationKind.appointmentQuiet);
      expect(before.title, 'بكرة ميعادك في المعمل');
      expect(before.body, 'صورة دم');

      expect(dayOf.at, DateTime(2026, 9, 20, 7));
      expect(dayOf.kind, NotificationKind.appointmentAlert);
      expect(dayOf.title, 'النهارده ميعادك في المعمل');
    });

    test('الاتنين بيتلغوا لما المرحلة تعدّي', () async {
      final day = DateTime(2026, 9, 20);
      final id = await book(day);
      await refresh(rolling: false);
      expect(sink.live.where(isAppointmentId), hasLength(2));

      // «التحضير» ← «سحب العينة» ← «انتظار النتيجة»: الميعاد بقى بلا معنى
      for (var i = 0; i < 3; i++) {
        await checkups.advance(id, now: _now);
      }
      await refresh(rolling: false);

      expect(sink.live.where(isAppointmentId), isEmpty);
      expect(sink.cancelled, contains(appointmentIdFor(day, AppointmentNotice.dayBefore)));
      expect(sink.cancelled, contains(appointmentIdFor(day, AppointmentNotice.dayOf)));
    });

    test('ميعاد بكرة: الهادي عدّى خلاص، فاللي بيرن بس هو اللي بيتجدول', () async {
      // دلوقتي ١٥ سبتمبر ١٠ صباحاً؛ ميعاد بكرة ١٦ → الهادي كان ١٥ الساعة ٨ مساءً
      await book(DateTime(2026, 9, 16));
      await refresh(rolling: false, now: DateTime(2026, 9, 15, 22));
      final kinds = sink.scheduled.values.where((n) => isAppointmentId(n.id)).map((n) => n.kind);
      expect(kinds, [NotificationKind.appointmentAlert],
          reason: 'إشعار وقته عدّى ما بياخدش خانة');
    });
  });

  group('iOS — نافذة متدحرجة بخانتين', () {
    test('بتمسك أقرب اتنين، والباقي بيستنى دوره', () async {
      await book(DateTime(2026, 9, 18), title: 'الأقرب');
      await book(DateTime(2026, 9, 25), title: 'الأبعد');
      await refresh(rolling: true);

      final live = sink.scheduled.values.where((n) => isAppointmentId(n.id)).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      expect(live, hasLength(checkupPendingSlack));
      // أقرب اتنين = هادي وبيرن بتوع الميعاد الأقرب
      expect(live.map((n) => n.body).toSet(), {'الأقرب'});
    });

    test('وبتتدحرج بعد ما الأول يرن', () async {
      await book(DateTime(2026, 9, 18), title: 'الأقرب');
      await book(DateTime(2026, 9, 25), title: 'الأبعد');
      await refresh(rolling: true);
      expect(sink.scheduled.values.map((n) => n.body).toSet(), {'الأقرب'});

      // عدّى ميعاد الأقرب — النافذة بتتحسب من جديد عند أول فتحة بعده
      await refresh(rolling: true, now: DateTime(2026, 9, 21, 10));
      final live = sink.scheduled.values.where((n) => isAppointmentId(n.id));
      expect(live.map((n) => n.body).toSet(), {'الأبعد'});
      expect(live, hasLength(2));
    });

    test('**ولا لحظة فيها أكتر من خانتين** — الإلغاء قبل الجدولة', () async {
      await book(DateTime(2026, 9, 18), title: 'أ');
      await refresh(rolling: true);
      await book(DateTime(2026, 9, 16), title: 'ب'); // أقرب، بيزقّ اللي قبله
      await refresh(rolling: true);
      await book(DateTime(2026, 9, 17), title: 'ج');
      await refresh(rolling: true);

      expect(sink.peak, lessThanOrEqualTo(checkupPendingSlack),
          reason: 'لو iOS ماسك ٦٤، الزيادة بتترمي في صمت — وممكن تبقى جرعة');
    });

    test('الحجز البعيد بيتقبل حتى وهو برّه النافذة', () async {
      await book(DateTime(2026, 9, 16), title: 'أ');
      await book(DateTime(2026, 9, 17), title: 'ب');
      final far = await book(DateTime(2026, 10, 20), title: 'البعيد');
      await refresh(rolling: true);

      // مفيش إشعار له لسه…
      expect(
          sink.live.contains(appointmentIdFor(DateTime(2026, 10, 20), AppointmentNotice.dayOf)),
          isFalse);
      // …بس الميعاد نفسه **متكتوب**، والكارت بيقراه من هنا
      final rows = await RecordsRepository(db).all(patientId);
      final row = rows.firstWhere((r) => r.id == far);
      expect(CheckupService.stageDateOf(row, CheckupStage.labBooking), isNotNull);
    });
  });

  group('أندرويد — كل الإشعارات من ساعة الحجز', () {
    test('تلات مواعيد = ستة إشعارات، من غير نافذة', () async {
      await book(DateTime(2026, 9, 18), title: 'أ');
      await book(DateTime(2026, 9, 25), title: 'ب');
      await book(DateTime(2026, 10, 2), title: 'ج');
      await refresh(rolling: false);

      expect(sink.live.where(isAppointmentId), hasLength(6));
      expect(sink.peak, 6);
    });
  });
}
