import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/notifications/notification_service.dart';
import 'package:fakkarni/data/billing/subscription_service.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/care/proxy_confirmations.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/nurse_reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/nurse/nurse_reminders.dart';

import '../../app/root_test.dart' show SilentSink;
import '../../data/billing/subscription_service_test.dart' show FakeRemote, FakeStore;
import '../../support/seeded_clock.dart';
import '../care/caregiver_screen_test.dart' show event;

/// جهاز واحد فيه الاتنين — عشان نثبت إن كل مجدول بيلغي من نطاقه بس.
class _Device implements ReminderSink, NurseReminderSink {
  final pending = <int, String>{};
  final cancelled = <int>[];

  @override
  Future<void> schedule(Object n) async {
    if (n is NurseNotification) {
      pending[n.id] = 'nurse';
    } else if (n is PlannedNotification) {
      pending[n.id] = 'patient';
    }
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
  }

  @override
  Future<Set<int>> pendingIds() async => pending.keys.toSet();

  @override
  Future<void> ensurePermissions() async {}
}

class _Proxy implements ProxyConfirmRemote {
  final confirmed = <(String, String, String?)>[];

  @override
  Future<void> confirmOnBehalf({required String patientUuid, required String doseEventUuid, required String? actorName}) async =>
      confirmed.add((patientUuid, doseEventUuid, actorName));

  @override
  Future<List<ProxyConfirmation>> fetchForPatient(String patientUuid, {required DateTime since}) async => const [];
}

void main() {
  final now = DateTime(2026, 8, 31, 14);

  CaregiverSnapshot snap(String uuid, String name, List<CaregiverDoseEvent> events, {Map<String, String?> proxied = const {}}) =>
      CaregiverSnapshot(
        patient: CaregiverPatient(
          uuid: uuid,
          name: name,
          permissions: const FollowerPermissions(role: FollowerRole.nurse, canConfirm: true, canEditMeds: false),
        ),
        medications: const [CaregiverMedication(uuid: 'm', name: 'Concor 5mg', alertMode: 'once')],
        events: events,
        proxied: proxied,
      );

  group('الخطة (دارت نقية)', () {
    final dose = event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending');
    final same = event('Glucophage', DateTime(2026, 8, 31, 20), 'pending');
    final past = event('Concor 5mg', DateTime(2026, 8, 31, 9), 'pending');
    final taken = event('Concor 5mg', DateTime(2026, 8, 31, 22), 'taken');
    final far = event('Concor 5mg', DateTime(2026, 9, 2, 9), 'pending');

    List<NurseNotification> plan(List<NurseDose> doses) => planNurseReminders(
          [NursePatientDoses(index: 0, uuid: 'p1', name: 'الحاج أحمد', doses: doses)],
          now: now,
        );
    NurseDose d(CaregiverDoseEvent e, {bool here = false}) => NurseDose(
        eventUuid: e.uuid, medicationName: e.medicationName, scheduledAt: e.scheduledAt, state: e.state, confirmedHere: here);

    test('الجاي المفتوح بس، ودواءين في نفس الدقيقة إشعار واحد باسم المريض', () {
      final out = plan([d(dose), d(same), d(past), d(taken), d(far)]);
      expect(out, hasLength(1));
      expect(out.single.title, 'ميعاد دوا الحاج أحمد: Concor 5mg، Glucophage');
      expect(out.single.at, DateTime(2026, 8, 31, 20));
      expect(parseNursePayload(out.single.payload)!.events, [dose.uuid, same.uuid]);
      expect(parseNursePayload(out.single.payload)!.patient, 'p1');
    });

    test('اللي اتأكّد من هنا ما يرنّش', () {
      expect(plan([d(dose, here: true)]), isEmpty);
    });

    test('الرقم في نطاق الممرض، ومش في نطاقات المريض ولا في إعادة جدولته', () {
      final id = plan([d(dose)]).single.id;
      expect(isNurseId(id), isTrue);
      expect(isDoseId(id), isFalse);
      expect(isRescheduledId(id), isFalse, reason: 'rescheduleAll بتاع المريض عمره ما يلغيه');
      expect(isEscalationId(id) || isRepeatId(id) || isSnoozeId(id), isFalse);
      // مريضين في نفس الدقيقة → رقمين
      final two = planNurseReminders([
        NursePatientDoses(index: 0, uuid: 'p1', name: 'أ', doses: [d(dose)]),
        NursePatientDoses(index: 1, uuid: 'p2', name: 'ب', doses: [d(dose)]),
      ], now: now);
      expect(two.map((n) => n.id).toSet(), hasLength(2));
    });

    test('سقف ٤٠، الأقرب الأول', () {
      final many = [
        for (var i = 0; i < 60; i++)
          NurseDose(eventUuid: 'e$i', medicationName: 'x', scheduledAt: now.add(Duration(minutes: 10 + i * 20)), state: 'pending'),
      ];
      final out = plan(many);
      expect(out, hasLength(maxPendingNurseReminders));
      expect(out.first.at, now.add(const Duration(minutes: 10)));
    });

    test('الحمولة ما بتتلخبطش مع حمولة المريض', () {
      expect(parseNursePayload('{"v":1,"day":"2026-08-31","ids":[1]}'), isNull);
      expect(parseNursePayload('مش json'), isNull);
    });
  });

  group('المجدول على جهاز مشترك', () {
    late AppDatabase db;
    late _Device device;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      device = _Device();
    });
    tearDown(() => db.close());

    test('تذكيرات الممرض ما بتلمسش تذكيرات المريض — ولا العكس', () async {
      // جرعات مريض على نفس الجهاز (مش حالة حقيقية — عشان نثبت الفصل)
      final routines = RoutineRepository(db);
      final meds = MedicationRepository(db, clock: seededLongAgo);
      final patientId = await routines.ensurePatient();
      await routines.saveRoutine(patientId, DayRoutine.fallback);
      await meds.addMedication(
        patientId: patientId,
        name: 'Concor',
        timing: const AnchorTiming(DayAnchor.dinner, 0),
        startDate: DateTime(2026, 8, 1),
      );
      final patient = ReminderScheduler(
          routines: routines, medications: meds, events: DoseEventRepository(db), patientId: patientId, sink: device);
      await patient.rescheduleAll(now: now);
      final patientIds = {for (final e in device.pending.entries) if (e.value == 'patient') e.key};
      expect(patientIds, isNotEmpty);

      final reminders = NurseReminders(sink: device, clock: () => now);
      final s = snap('p1', 'الحاج أحمد', [event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending')]);
      await reminders.sync(patients: [s.patient], current: s, allowed: true);
      final nurseIds = {for (final e in device.pending.entries) if (e.value == 'nurse') e.key};
      expect(nurseIds, hasLength(1));

      // المريض بيعيد الجدولة → تذكير الممرض فاضل
      await patient.rescheduleAll(now: now);
      expect(device.pending.keys, containsAll(nurseIds));

      // الممرض بيقفل → بيلغي بتوعه بس
      await NurseReminders.setEnabled(false);
      await reminders.sync(patients: [s.patient], current: s, allowed: true);
      expect(device.pending.keys.where(isNurseId), isEmpty);
      expect(device.pending.keys, containsAll(patientIds));
      expect(device.cancelled.where((id) => !isNurseId(id)), isEmpty);
    });

    test('مفتوح افتراضياً، والاشتراك لو خلص بيلغي كله', () async {
      expect(await NurseReminders.isEnabled(), isTrue);
      final reminders = NurseReminders(sink: device, clock: () => now);
      final s = snap('p1', 'الحاج أحمد', [event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending')]);
      await reminders.sync(patients: [s.patient], current: s, allowed: true);
      expect(device.pending.keys.where(isNurseId), hasLength(1));
      await reminders.sync(patients: [s.patient], current: s, allowed: false);
      expect(device.pending.keys.where(isNurseId), isEmpty);
    });

    test('المتابع العادي مالوش تذكيرات', () async {
      final reminders = NurseReminders(sink: device, clock: () => now);
      final s = CaregiverSnapshot(
        patient: const CaregiverPatient(uuid: 'p1', name: 'x'),
        medications: const [],
        events: [event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending')],
      );
      await reminders.sync(patients: [s.patient], current: s, allowed: true);
      expect(device.pending, isEmpty);
    });
  });

  group('الزرار', () {
    setUp(NotificationService.resetForTest);

    test('«أكّد إنه أخدها» بيروح لباب الممرض بس — عمره ما يوصل معالج «أخدته»', () {
      final patientCalls = <String>[];
      final nurseCalls = <String?>[];
      NotificationService.onAction = (a, p) => patientCalls.add(a);
      NotificationService.onNurseAction = (id, p) => nurseCalls.add(p);
      addTearDown(() {
        NotificationService.onAction = null;
        NotificationService.onNurseAction = null;
      });
      NotificationService.tapForTest(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        id: 180000001,
        actionId: NotificationActions.nurseConfirm,
        payload: '{"v":1,"nurse":{"p":"p1","e":["e1"]}}',
      ));
      expect(patientCalls, isEmpty);
      expect(nurseCalls, hasLength(1));
      expect(NotificationActions.isAction(NotificationActions.nurseConfirm), isFalse);
    });

    test('إطلاق من زرار الممرض بيرجع كزرار، مش دوسة عادية', () {
      final r = NotificationService.applyLaunchResponse(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: NotificationActions.nurseConfirm,
        payload: '{"v":1,"nurse":{"p":"p1","e":["e1"]}}',
      ));
      expect(r?.actionId, NotificationActions.nurseConfirm);
      expect(NotificationService.lastPayload.value, isNull);
    });

    test('التأكيد من الإشعار = تأكيد نيابةً لكل الأحداث — ومع اشتراك منتهي ولا حاجة', () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final routines = RoutineRepository(db);
      final meds = MedicationRepository(db);
      final events = DoseEventRepository(db);
      final patientId = await routines.ensurePatient();
      final proxy = _Proxy();
      final sub = SubscriptionService(remote: FakeRemote(), store: FakeStore(), clock: () => now);
      await sub.load();
      final services = AppServices(
        db: db,
        routines: routines,
        medications: meds,
        events: events,
        scheduler: ReminderScheduler(routines: routines, medications: meds, events: events, patientId: patientId, sink: SilentSink()),
        patientId: patientId,
        proxy: proxy,
        subscription: sub,
      );
      final payload = nursePayload('p1', ['e1', 'e2']);
      expect(await confirmFromNurseNotification(services, null, payload), 2);
      expect(proxy.confirmed.map((c) => c.$2), ['e1', 'e2']);

      await sub.setDebugOverride(false);
      expect(await confirmFromNurseNotification(services, null, payload), 0);
      expect(proxy.confirmed, hasLength(2));
      expect(await confirmFromNurseNotification(services, null, '{"v":1,"day":"x"}'), 0, reason: 'حمولة مريض');
    });
  });
}
