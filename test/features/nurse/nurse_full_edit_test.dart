// الممرض بيعدّل كل حاجة (0035): التغيير بيتطبّق على موبايل المريض بسكّته —
// التذكيرات بتتجدول **هناك** بس؛ «تراجع» بيرجّع وبيلغي؛ الطابور الأوفلاين
// بيبعت مرة؛ وإشارة التأكيد بتلغي تذكير الممرض.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/data/care/caregiver_preferences.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/care/nurse_change_queue.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/push/confirm_signal_router.dart';
import 'package:fakkarni/data/push/confirm_signals.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/data/repositories/preferences_repository.dart';
import 'package:fakkarni/data/services/nurse_reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/sync/medication_change_pull.dart';
import 'package:fakkarni/domain/care/follower_profile.dart';
import 'package:fakkarni/domain/care/medication_change.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/nurse/nurse_reminders.dart';

import '../../features/scan/scan_test_support.dart' show RecordingSink;
import '../../support/fake_changes.dart';
import '../../support/seeded_clock.dart';
import '../care/caregiver_screen_test.dart' show event;

final _now = DateTime(2026, 9, 15, 6);

class _NurseDevice implements NurseReminderSink {
  final pending = <int, NurseNotification>{};
  final cancelled = <int>[];
  @override
  Future<void> schedule(NurseNotification n) async => pending[n.id] = n;
  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
  }

  @override
  Future<Set<int>> pendingIds() async => pending.keys.toSet();
}

class _Prefs implements CaregiverPreferencesService {
  final saved = <String, CaregiverPreferences>{};
  @override
  Future<CaregiverPreferences> load(String patientUuid) async => saved[patientUuid] ?? const CaregiverPreferences();
  @override
  Future<void> save(String patientUuid, CaregiverPreferences preferences) async => saved[patientUuid] = preferences;
  @override
  Future<List<FollowerProfile>> followers(String patientUuid) async => const [];
}

const _nursePerms = FollowerPermissions(role: FollowerRole.nurse, canConfirm: true, canEditMeds: true);

CaregiverSnapshot _snap(List<CaregiverDoseEvent> events) => CaregiverSnapshot(
      patient: const CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد', permissions: _nursePerms),
      medications: const [CaregiverMedication(uuid: 'm', name: 'Concor 5mg')],
      events: events,
    );

void main() {
  // ---------------------------------------------------------- موبايل المريض
  late AppDatabase db;
  late RecordingSink patientSink;
  late PatientRepository patients;
  late MedicationRepository meds;
  late ReminderScheduler scheduler;
  late FakeChanges cloud;
  late int patientId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MedicationChangePuller.notices.value = const [];
    db = AppDatabase(NativeDatabase.memory());
    patientSink = RecordingSink();
    patients = PatientRepository(db);
    meds = MedicationRepository(db, clock: seededLongAgo);
    patientId = await patients.ensurePatient();
    scheduler = ReminderScheduler(medications: meds, events: DoseEventRepository(db), patientId: patientId, sink: patientSink);
    cloud = FakeChanges();
  });
  tearDown(() => db.close());

  MedicationChangePuller puller() => MedicationChangePuller(
        remote: cloud,
        db: db,
        patients: patients,
        medications: meds,
        scheduler: scheduler,
        patientId: patientId,
        clock: () => _now,
      );

  /// الممرض بيبعت «ضيف دوا» — بنفس اللي الشاشة بتبعته.
  Future<({SubmitOutcome outcome, String? error})> nurseAdds(NurseChangeQueue q, {String uuid = 'c-add'}) => q.submit(QueuedChange(
        uuid: uuid,
        patientUuid: 'p1',
        patientName: 'الحاج أحمد',
        kind: MedicationChangeKind.add,
        payload: MedicationChangePayload(
          name: 'Concor 5mg',
          timings: [FixedTiming(MinuteOfDay.hm(8)), FixedTiming(MinuteOfDay.hm(20))],
          amountLabel: 'قرص',
        ),
        actorName: 'سارة',
      ));

  test('الممرض بيضيف دوا → بيتطبّق على موبايل المريض بسكّته — التذكير هناك بس، ولا واحد على موبايل الممرض', () async {
    final q = NurseChangeQueue(cloud);
    final nurseDevice = _NurseDevice();
    final r = await nurseAdds(q);
    expect(r.outcome, SubmitOutcome.sent);

    // موبايل الممرض: المقارنة على صورته (لسه مفيش أحداث للدوا الجديد) —
    // ولا رقم في نطاق الجرعات ولا السلّم
    final reminders = NurseReminders(sink: nurseDevice, clock: () => _now);
    await reminders.sync(patients: [_snap(const []).patient], current: _snap(const []), allowed: true);
    expect(nurseDevice.pending.keys.where(isDoseId), isEmpty);
    expect(nurseDevice.pending.keys.where(isEscalationId), isEmpty);

    // موبايل المريض: السحبة بتطبّق وبتجدول
    expect(await puller().pull(), 1);
    final saved = await meds.activeSchedules(patientId);
    expect(saved.map((s) => s.timing.minuteOfDay.minutes).toSet(), {8 * 60, 20 * 60});
    expect(patientSink.scheduled.keys, contains(notificationIdFor(DateTime(2026, 9, 15, 8))));
    expect(patientSink.scheduled.keys, contains(notificationIdFor(DateTime(2026, 9, 15, 20))));
    expect(patientSink.scheduled.keys.where(isEscalationId), isNotEmpty, reason: 'السلّم زي أي دوا المريض ضافه');
    expect(cloud.marked, [('c-add', ChangeOutcome.applied)]);
    // الجملة بالساعات و«تراجع» متاح
    final n = MedicationChangePuller.notices.value.single;
    expect(n.line, 'سارة ضاف دوا Concor 5mg — ٨:٠٠ ص و٨:٠٠ م');
    expect(n.canUndoAt(_now.add(const Duration(hours: 23))), isTrue);
    expect(n.canUndoAt(_now.add(const Duration(hours: 25))), isFalse);
    // ولا حاجة اتجدولت على موبايل الممرض بسبب ده
    expect(nurseDevice.pending, isEmpty);
  });

  test('«تراجع» بيرجّع بنفس السكّة وبيلغي التذكيرات، وبيعلّم الصف «اترجع»', () async {
    final q = NurseChangeQueue(cloud);
    await nurseAdds(q);
    final p = puller();
    await p.pull();
    final ids = patientSink.scheduled.keys.where((id) => isDoseId(id) || isEscalationId(id)).toSet();
    expect(ids, isNotEmpty);

    expect(await p.undo(MedicationChangePuller.notices.value.single), isTrue);
    expect(await meds.activeSchedules(patientId), isEmpty, reason: 'الدوا اتشال (ناعم)');
    for (final id in ids) {
      expect(patientSink.scheduled.containsKey(id), isFalse, reason: 'التذكير $id اتلغى بالجدولة');
    }
    expect(cloud.reverted, ['c-add']);
    expect(MedicationChangePuller.notices.value, isEmpty);
  });

  test('«تراجع» على إيقاف = رجوع، وعلى الجرعة = الجرعة القديمة، وبرّه الـ٢٤ ساعة ولا حاجة', () async {
    final id = await meds.addMedication(patientId: patientId, name: 'Concor', timing: FixedTiming(MinuteOfDay.hm(20)), startDate: DateTime(2026, 9, 1), amountLabel: 'قرص');
    final row = await (db.select(db.medications)..where((t) => t.id.equals(id))).getSingle();
    // بعد تعديل المريض المحلي (ساعة الجهاز الحقيقية على updated_at_ms) — وإلا «تعديل الأب بيكسب»
    final after0 = DateTime.now().add(const Duration(minutes: 1));
    cloud.pending.add(MedicationChange(uuid: 'c-stop', kind: MedicationChangeKind.stop, medicationUuid: row.uuid, payload: const MedicationChangePayload(), createdAt: after0, actorName: 'سارة'));
    cloud.pending.add(MedicationChange(uuid: 'c-amt', kind: MedicationChangeKind.amount, medicationUuid: row.uuid, payload: const MedicationChangePayload(amountLabel: 'قرصين'), createdAt: after0, actorName: 'سارة'));
    final p = puller();
    expect(await p.pull(), 2);
    var after = await (db.select(db.medications)..where((t) => t.id.equals(id))).getSingle();
    expect(after.stoppedAt, isNotNull);
    expect(after.amountLabel, 'قرصين');

    final notices = MedicationChangePuller.notices.value;
    expect(await p.undo(notices.firstWhere((n) => n.kind == MedicationChangeKind.amount)), isTrue);
    expect(await p.undo(notices.firstWhere((n) => n.kind == MedicationChangeKind.stop)), isTrue);
    after = await (db.select(db.medications)..where((t) => t.id.equals(id))).getSingle();
    expect(after.stoppedAt, isNull);
    expect(after.amountLabel, 'قرص');

    // برّه النافذة
    final late = MedicationChangePuller(remote: cloud, db: db, patients: patients, medications: meds, scheduler: scheduler, patientId: patientId, clock: () => _now.add(const Duration(days: 2)));
    cloud.pending.add(MedicationChange(uuid: 'c-stop2', kind: MedicationChangeKind.stop, medicationUuid: row.uuid, payload: const MedicationChangePayload(), createdAt: DateTime.now().add(const Duration(minutes: 2)), actorName: 'سارة'));
    await p.pull();
    expect(await late.undo(MedicationChangePuller.notices.value.first), isFalse);
  });

  test('طابور أوفلاين: النت واقع → محفوظ بجملته، رجع → اتبعت مرة، والمريض بيطبّقه مرة — مفيش دوا مكرر', () async {
    final q = NurseChangeQueue(cloud);
    cloud.submitFailure = const CareCircleException(CareCircleFailure.offline, 'no net');
    final r = await nurseAdds(q);
    expect(r.outcome, SubmitOutcome.queued);
    expect(NurseChangeQueue.queuedLine('الحاج أحمد'), 'هيوصل لموبايل الحاج أحمد أول ما يفتح النت');
    expect(await q.pendingFor('p1'), hasLength(1));
    expect(cloud.submitted, isEmpty);

    // لسه واقع: الطابور بيفضل
    expect(await q.flush(), 0);
    expect(await q.pendingFor('p1'), hasLength(1));

    // رجع: مرة واحدة — والفلاش التاني ما بيبعتش تاني
    cloud.submitFailure = null;
    expect(await q.flush(), 1);
    expect(await q.flush(), 0);
    expect(cloud.submitted, hasLength(1));
    expect(cloud.submittedUuids, ['c-add']);

    // إعادة إرسال نفس الصف (النت وقع بعد ما وصل) = نجاح من غير صف تاني
    await nurseAdds(q);
    expect(cloud.submitted, hasLength(1));

    // المريض: نفس التغيير بيوصله مرتين (التعليم وقع) → دوا واحد
    final p = puller();
    expect(await p.pull(), 1);
    cloud.pending.add(MedicationChange(uuid: 'c-add', kind: MedicationChangeKind.add, payload: cloud.submitted.single, createdAt: _now));
    expect(await p.pull(), 0, reason: 'اتطبّق قبل كده');
    expect((await meds.activeSchedules(patientId)).map((s) => s.medicationName).toSet(), {'Concor 5mg'});
    expect(await (db.select(db.medications).get()), hasLength(1));
  });

  test('الرفض من السيرفر مش طابور — جملة، والصف ما بيتحفظش', () async {
    final q = NurseChangeQueue(cloud);
    cloud.submitFailure = const CareCircleException(CareCircleFailure.other, 'rls');
    final r = await nurseAdds(q);
    expect(r.outcome, SubmitOutcome.failed);
    expect(r.error, isNotNull);
    expect(await q.pendingFor('p1'), isEmpty);
  });

  test('«صيدليتي» من الممرض بتتكتب على تفضيلات المريض، و«تراجع» بيرجّع القديمة', () async {
    final prefs = PreferencesRepository(db);
    await prefs.setPharmacy(name: 'الشفا', whatsapp: '01000000000', call: '0223456789');
    cloud.pending.add(MedicationChange(
      uuid: 'c-ph',
      kind: MedicationChangeKind.pharmacy,
      payload: const MedicationChangePayload(pharmacyName: 'العزبي', pharmacyCall: '01012345678', pharmacyWhatsapp: '01012345678'),
      createdAt: _now,
      actorName: 'سارة',
    ));
    final p = puller();
    expect(await p.pull(), 1);
    expect(await prefs.pharmacy(), (name: 'العزبي', whatsapp: '01012345678', call: '01012345678'));
    expect(MedicationChangePuller.notices.value.single.line, 'سارة غيّر صيدليتك لـالعزبي');
    expect(await p.undo(MedicationChangePuller.notices.value.single), isTrue);
    expect(await prefs.pharmacy(), (name: 'الشفا', whatsapp: '01000000000', call: '0223456789'));
  });

  test('القياس من الممرض صف في vitals — ومفيش «تراجع» عليه', () async {
    cloud.pending.add(MedicationChange(
      uuid: 'c-v',
      kind: MedicationChangeKind.vital,
      payload: MedicationChangePayload(vitalKind: 'bloodPressure', value: 130, value2: 85, pulse: 70, measuredAt: _now),
      createdAt: _now,
      actorName: 'سارة',
    ));
    expect(await puller().pull(), 1);
    expect(await db.select(db.vitals).get(), hasLength(1));
    expect(MedicationChangePuller.notices.value.single.canUndoAt(_now), isFalse);
  });

  // ---------------------------------------------------------- تذكيرات الممرض
  group('تذكيرات الممرض', () {
    late _NurseDevice device;
    setUp(() => device = _NurseDevice());

    final e20 = event('Concor 5mg', DateTime(2026, 9, 15, 20), 'pending');
    final e21 = event('Concor 5mg', DateTime(2026, 9, 15, 21), 'pending');

    test('النص والأزرار: «ميعاد دوا [الاسم]: [الدوا] — [الساعة]»، والحمولة فيها الخانة', () async {
      final r = NurseReminders(sink: device, clock: () => _now);
      await r.sync(patients: [_snap([e20]).patient], current: _snap([e20]), allowed: true);
      final n = device.pending.values.single;
      expect(n.title, 'ميعاد دوا الحاج أحمد: Concor 5mg — ٨:٠٠ م');
      expect(n.body, contains('أخدها'));
      expect(parseNursePayload(n.payload)!.at, DateTime(2026, 9, 15, 20));
      expect(isNurseId(n.id), isTrue);
    });

    test('تعديل الجدول (من أي ناحية) → الصورة الجاية بتعيد جدولة الممرض: القديم بيتلغي والجديد بيتجدول', () async {
      final r = NurseReminders(sink: device, clock: () => _now);
      await r.sync(patients: [_snap([e20]).patient], current: _snap([e20]), allowed: true);
      final oldId = device.pending.keys.single;
      await r.sync(patients: [_snap([e21]).patient], current: _snap([e21]), allowed: true);
      expect(device.cancelled, contains(oldId));
      expect(device.pending.keys.single, nurseIdFor(DateTime(2026, 9, 15, 21), patientIndex: 0));
    });

    test('المريض أكّد على موبايله → إشارة الدفع بتلغي تذكير الممرض (وتأجيله) حالاً', () async {
      final r = NurseReminders(sink: device, clock: () => _now);
      await r.sync(patients: [_snap([e20]).patient], current: _snap([e20]), allowed: true);
      final id = device.pending.keys.single;
      var patientPulls = 0;
      final router = ConfirmSignalRouter(
        onPatientSide: () async => patientPulls++,
        onNurseSide: (s) => r.onConfirmed(patientUuid: s.patientUuid, doseEventUuid: s.doseEventUuid),
      );
      await router.handle(ConfirmSignal(patientUuid: 'p1', doseEventUuid: e20.uuid, source: ConfirmSource.patient).toData());
      expect(device.pending, isEmpty);
      expect(device.cancelled, containsAll([id, nurseSnoozeIdBase + (id - nurseIdBase)]));
      expect(patientPulls, 0, reason: 'تأكيد المريض نفسه — مفيش سحبة');
      // نفس الإشارة تاني = ولا حاجة
      await router.handle(ConfirmSignal(patientUuid: 'p1', doseEventUuid: e20.uuid, source: ConfirmSource.patient).toData());
      expect(device.cancelled, hasLength(2));
      // وإشارة تانية مش تأكيد بتتعدّى
      await router.handle({'type': 'escalation'});
      expect(patientPulls, 0);
    });

    test('ممرض أكّد نيابةً → موبايل المريض بيسحب (وده اللي بيلغي سلّمه)، والممرضين التانيين بيلغوا', () async {
      final r = NurseReminders(sink: device, clock: () => _now);
      await r.sync(patients: [_snap([e20]).patient], current: _snap([e20]), allowed: true);
      var patientPulls = 0;
      final router = ConfirmSignalRouter(
        onPatientSide: () async => patientPulls++,
        onNurseSide: (s) => r.onConfirmed(patientUuid: s.patientUuid, doseEventUuid: s.doseEventUuid),
      );
      await router.handle(ConfirmSignal(patientUuid: 'p1', doseEventUuid: e20.uuid, source: ConfirmSource.proxy).toData());
      expect(patientPulls, 1);
      expect(device.pending, isEmpty);
    });

    test('«لاحقاً» على جهاز الممرض يلغي التنبيه المحلي القديم فقط', () async {
      final r = NurseReminders(sink: device, clock: () => _now);
      final snapshot = _snap([e20]);
      final legacy = NurseNotification(
        id: nurseIdFor(DateTime(2026, 9, 15, 20), patientIndex: 0),
        at: DateTime(2026, 9, 15, 20),
        title: 'ميعاد جرعة قديم',
        body: nurseReminderBody,
        payload: nursePayload(
          'p1',
          [e20.uuid],
          at: DateTime(2026, 9, 15, 20),
          patientIndex: 0,
        ),
        insistent: true,
      );
      device.pending[legacy.id] = legacy;

      expect(await r.later(id: legacy.id, payload: legacy.payload), isTrue);

      // لا إشعار محلي جديد ولا تأجيل؛ إجراء الممرض لا يغيّر حالة الجرعة
      // القادمة من المريض، فتظل ظاهرة كجرعة مفتوحة في واجهة المتابعة.
      expect(device.pending, isEmpty);
      expect(device.cancelled, [legacy.id]);
      expect(snapshot.events.single.uuid, e20.uuid);
      expect(snapshot.events.single.state, 'pending');
    });

    test('«نبهني بمواعيد الدوا» مقفول للمريض ده → ولا تذكير، وفتحه بيرجّعها', () async {
      final prefs = _Prefs()..saved['p1'] = const CaregiverPreferences(nurseDoseReminders: false);
      final r = NurseReminders(sink: device, preferences: prefs, clock: () => _now);
      await r.sync(patients: [_snap([e20]).patient], current: _snap([e20]), allowed: true);
      expect(device.pending, isEmpty);
      r.setDoseRemindersOn('p1', true);
      await r.sync(patients: [_snap([e20]).patient], current: _snap([e20]), allowed: true);
      expect(device.pending, hasLength(1));
      r.setDoseRemindersOn('p1', false);
      await r.sync(patients: [_snap([e20]).patient], current: _snap([e20]), allowed: true);
      expect(device.pending, isEmpty);
    });

    test('تذكيرات المريض على موبايله ما اتلمستش — الخطة الذهبية', () async {
      await meds.addMedication(patientId: patientId, name: 'Concor', timing: FixedTiming(MinuteOfDay.hm(20)), startDate: DateTime(2026, 9, 1));
      await scheduler.rescheduleAll(now: _now);
      final before = Map.of(patientSink.scheduled);
      // كل اللي الممرض بيعمله على جهازه هو
      final r = NurseReminders(sink: device, clock: () => _now);
      await r.sync(patients: [_snap([e20]).patient], current: _snap([e20]), allowed: true);
      await r.onConfirmed(patientUuid: 'p1', doseEventUuid: e20.uuid);
      await scheduler.rescheduleAll(now: _now);
      expect(patientSink.scheduled.keys.toSet(), before.keys.toSet());
    });
  });
}
