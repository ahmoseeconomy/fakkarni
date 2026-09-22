import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/features/care/caregiver_appointment_notices.dart';

import 'caregiver_screen_test.dart' show now;

/// **مواعيد الأب على موبايل الابن** — إشعارات محلية من السحبة، لأن مفيش
/// دفع من السيرفر لسه.
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

CaregiverRecord _follow({
  required String uuid,
  required String title,
  String? kind,
  int stage = 2,
  DateTime? labBookingAt,
  DateTime? doctorVisitAt,
}) =>
    CaregiverRecord(
      uuid: uuid,
      kind: kind == 'visit' ? 'visit' : 'lab',
      title: title,
      happenedAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      checkupStage: stage,
      followKind: kind,
      labBookingAt: labBookingAt,
      doctorVisitAt: doctorVisitAt,
    );

CaregiverSnapshot _snapshot(List<CaregiverRecord> records) => CaregiverSnapshot(
      patient: const CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد'),
      medications: const [],
      events: const [],
      alerts: const [],
      records: records,
    );

void main() {
  test('ميعاد واحد → إشعارين: هادي بالليل امبارحه، وواحد بيرن الصبح', () {
    final notices = caregiverAppointmentNotices(
      _snapshot([
        _follow(uuid: 'r1', title: 'صورة دم', labBookingAt: DateTime(2026, 9, 20, 7)),
      ]),
      now: now,
    );

    expect(notices, hasLength(2));
    // **الرقم مشتق من اليوم** — زي موبايل الأب بالظبط.
    final day = DateTime(2026, 9, 20);
    final before = notices[caregiverAppointmentIdFor(day, AppointmentNotice.dayBefore)]!;
    final dayOf = notices[caregiverAppointmentIdFor(day, AppointmentNotice.dayOf)]!;

    expect(before.at, DateTime(2026, 9, 19, 20));
    expect(before.kind, NotificationKind.appointmentQuiet);
    expect(before.title, 'بكرة عند والدك تحليل');
    expect(before.body, 'صورة دم');

    expect(dayOf.at, DateTime(2026, 9, 20, 8));
    expect(dayOf.kind, NotificationKind.appointmentAlert);
  });

  test('زيارة بتتقال زيارة — نفس كلام الأب، مش نسخة تانية', () {
    final notices = caregiverAppointmentNotices(
      _snapshot([
        _follow(
          uuid: 'v1',
          title: 'متابعة الضغط',
          kind: 'visit',
          stage: 1,
          doctorVisitAt: DateTime(2026, 9, 20, 10),
        ),
      ]),
      now: now,
    );
    expect(notices.values.first.title, contains('زيارة'));
  });

  test('الأقرب الأول، والسقف بيقص الباقي', () {
    final notices = caregiverAppointmentNotices(
      _snapshot([
        for (var i = 0; i < caregiverAppointmentCap + 3; i++)
          _follow(
            uuid: 'r$i',
            title: 'متابعة $i',
            labBookingAt: DateTime(2026, 10, 20 - i, 7),
          ),
      ]),
      now: now,
    );
    expect(notices, hasLength(caregiverAppointmentCap * 2));
    // السقف بقى **عدّ أيام**: أقرب يوم هو ١٤ أكتوبر (i = cap + 2).
    final nearest = DateTime(2026, 10, 20 - (caregiverAppointmentCap + 2));
    final first = notices[caregiverAppointmentIdFor(nearest, AppointmentNotice.dayOf)]!;
    expect(first.body, 'متابعة ${caregiverAppointmentCap + 2}');
  });

  test('ميعاد عدّى مش بيتجدول', () {
    final notices = caregiverAppointmentNotices(
      _snapshot([_follow(uuid: 'old', title: 'قديم', labBookingAt: DateTime(2026, 8, 1, 7))]),
      now: now,
    );
    expect(notices, isEmpty);
  });

  group('إشعار واحد لكل لحظة — زي موبايل الأب', () {
    final day = DateTime(2026, 9, 20);

    test('ميعادين في يوم واحد = إشعارين لليوم، مش أربعة', () {
      final notices = caregiverAppointmentNotices(
        _snapshot([
          _follow(uuid: 'r1', title: 'صورة دم', labBookingAt: DateTime(2026, 9, 20, 7)),
          _follow(
            uuid: 'v1',
            title: 'متابعة الضغط',
            kind: 'visit',
            stage: 1,
            doctorVisitAt: DateTime(2026, 9, 20, 10),
          ),
        ]),
        now: now,
      );

      expect(notices, hasLength(2));
      expect(notices.keys.toSet(), {
        caregiverAppointmentIdFor(day, AppointmentNotice.dayBefore),
        caregiverAppointmentIdFor(day, AppointmentNotice.dayOf),
      });
      expect(notices[caregiverAppointmentIdFor(day, AppointmentNotice.dayOf)]!.title,
          'النهارده عند والدك تحليل وزيارة');
    });

    test('ومن تلاتة وفوق «وحاجة كمان»', () {
      final notices = caregiverAppointmentNotices(
        _snapshot([
          for (var i = 0; i < 3; i++)
            _follow(uuid: 'r\$i', title: 'متابعة \$i', labBookingAt: DateTime(2026, 9, 20, 7 + i)),
        ]),
        now: now,
      );
      expect(notices[caregiverAppointmentIdFor(day, AppointmentNotice.dayOf)]!.title,
          endsWith(' وحاجة كمان'));
    });

    test('**والمتن بيقول اسم المتابعة، مش عنوان الورقة الخام**', () {
      // نفس العنوان اللي جه من الجهاز الحقيقي، برقمه اللاتيني.
      final notices = caregiverAppointmentNotices(
        _snapshot([
          _follow(
            uuid: 'r1',
            title: 'تقرير تحليل — 6 نتايج',
            labBookingAt: DateTime(2026, 9, 20, 7),
          ),
        ]),
        now: now,
      );
      final latin = RegExp(r'[0-9]');
      expect(notices, isNotEmpty, reason: 'الحارس عدّى فاضي');
      for (final n in notices.values) {
        expect(n.body, 'متابعة تحليل');
        expect(latin.hasMatch(n.title), isFalse, reason: 'عنوان: «\${n.title}»');
        expect(latin.hasMatch(n.body), isFalse, reason: 'متن: «\${n.body}»');
      }
    });
  });

  group('المزامنة مع الجهاز', () {
    test('بتتعاد من غير أي أثر — نفس الصورة، نفس الأرقام', () async {
      final sink = _Sink();
      final snapshot = _snapshot([
        _follow(uuid: 'r1', title: 'صورة دم', labBookingAt: DateTime(2026, 9, 20, 7)),
      ]);
      await syncCaregiverAppointments(snapshot, sink: sink, now: now);
      final first = sink.live;
      sink.cancelled.clear();

      await syncCaregiverAppointments(snapshot, sink: sink, now: now);
      expect(sink.live, first);
      expect(sink.cancelled, isEmpty, reason: 'سحبة تانية على نفس الصورة ألغت حاجة');
    });

    test('الميعاد لما يخرج من الصورة بيتلغي', () async {
      final sink = _Sink();
      await syncCaregiverAppointments(
        _snapshot([_follow(uuid: 'r1', title: 'صورة دم', labBookingAt: DateTime(2026, 9, 20, 7))]),
        sink: sink,
        now: now,
      );
      expect(sink.live, isNotEmpty);

      await syncCaregiverAppointments(_snapshot(const []), sink: sink, now: now);
      expect(sink.live.where(isCaregiverAppointmentId), isEmpty);
    });

    test('**ما بتلمسش تنبيهات التصعيد** — نطاقها مالوش علاقة', () async {
      final sink = _Sink()
        ..scheduled[escalationFirstIdBase + 5] = PlannedNotification(
          id: escalationFirstIdBase + 5,
          at: DateTime(2026, 9, 16, 8),
          title: 'تنبيه',
          body: '',
          payload: '',
          kind: NotificationKind.escalation,
        );

      await syncCaregiverAppointments(_snapshot(const []), sink: sink, now: now);
      expect(sink.cancelled, isEmpty);
      expect(sink.live, contains(escalationFirstIdBase + 5));
    });
  });
}
