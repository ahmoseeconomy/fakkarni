import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/care/medication_changes.dart';
import 'package:fakkarni/data/care/proxy_confirmations.dart';
import 'package:fakkarni/domain/care/medication_change.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/features/care/caregiver_mirror_screen.dart';

import '../../app/root_test.dart' show SilentSink;
import '../scan/scan_test_support.dart' show settle, screenTest;
import 'caregiver_screen_test.dart' show FakeCaregiverRemote, event, now;

/// «مرآة» الممرض (٠٠٢٣): يوم المريض زي «يومك»، و«أكّد إنه أخدها» على
/// المستحق بس لو مسموح له — والتأكيد صف نيابةً، مش كتابة على صف الأب.
class _FakeProxy implements ProxyConfirmRemote {
  final confirmed = <(String patient, String event, String? actor)>[];
  CareCircleException? failure;

  @override
  Future<void> confirmOnBehalf({required String patientUuid, required String doseEventUuid, required String? actorName}) async {
    final f = failure;
    if (f != null) throw f;
    confirmed.add((patientUuid, doseEventUuid, actorName));
  }

  @override
  Future<List<ProxyConfirmation>> fetchForPatient(String patientUuid, {required DateTime since}) async => const [];
}

class _FakeChanges implements MedicationChangeRemote {
  final submitted = <(MedicationChangeKind, String?, String?)>[];
  final pending = <MedicationChange>[];

  @override
  Future<void> submit({required String patientUuid, required MedicationChangeKind kind, required MedicationChangePayload payload, String? medicationUuid, String? medicationName, String? actorName}) async {
    submitted.add((kind, medicationUuid, payload.amountLabel ?? payload.name));
    pending.add(MedicationChange(uuid: 'c${pending.length}', kind: kind, payload: payload, createdAt: DateTime(2026, 8, 31, 13), medicationName: medicationName));
  }

  @override
  Future<List<MedicationChange>> fetchPending(String patientUuid) async => List.of(pending);
  @override
  Future<List<MedicationChange>> pendingFor(String patientUuid) async => List.of(pending);
  @override
  Future<void> markApplied(String changeUuid, ChangeOutcome outcome) async {}
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  CaregiverSnapshot snapshot({
    required FollowerPermissions permissions,
    Map<String, String?> proxied = const {},
  }) =>
      CaregiverSnapshot(
        patient: CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد', permissions: permissions),
        medications: const [CaregiverMedication(uuid: 'm1', name: 'Concor 5mg', amountLabel: 'قرص واحد')],
        events: [
          event('Concor 5mg', DateTime(2026, 8, 31, 7), 'taken', actedAt: DateTime(2026, 8, 31, 7, 5)),
          event('Glucophage', DateTime(2026, 8, 31, 9), 'missed'),
          event('Glucophage', DateTime(2026, 8, 31, 12), 'pending'),
          event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending'),
        ],
        lastUpdated: DateTime(2026, 8, 31, 13),
        proxied: proxied,
      );

  late _FakeChanges changes;
  setUp(() => changes = _FakeChanges());

  Future<(FakeCaregiverRemote, _FakeProxy)> pumpShell(WidgetTester tester, CaregiverSnapshot snap) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
    final events = DoseEventRepository(db);
    final patientId = await routines.ensurePatient();
    final remote = FakeCaregiverRemote()..next = snap;
    final proxy = _FakeProxy();
    await tester.pumpWidget(
      AppScope(
        services: AppServices(
          db: db,
          routines: routines,
          medications: meds,
          events: events,
          scheduler: ReminderScheduler(routines: routines, medications: meds, events: events, patientId: patientId, sink: SilentSink()),
          patientId: patientId,
          caregiver: remote,
          proxy: proxy,
          medChanges: changes,
        ),
        child: MaterialApp(
          theme: F.light,
          builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          home: CaregiverShell(onNotLinked: () {}, now: now),
        ),
      ),
    );
    await settle(tester);
    return (remote, proxy);
  }

  const nurse = FollowerPermissions(role: FollowerRole.nurse, canConfirm: true, canEditMeds: false);
  const quietNurse = FollowerPermissions(role: FollowerRole.nurse, canConfirm: false, canEditMeds: false);

  screenTest('الممرض بيلاقي «مرآة» مكان «متابعة»، والمتابع لأ', (tester) async {
    await pumpShell(tester, snapshot(permissions: nurse));
    expect(find.text('مرآة'), findsWidgets);
    expect(find.text('متابعة'), findsNothing);
    expect(find.byType(CaregiverMirrorScreen), findsOneWidget);
    expect(find.text('الآن'), findsOneWidget);
    expect(find.text('جدول النهارده'), findsOneWidget);
  });

  screenTest('المتابع العادي: نفس شاشته القديمة، ولا زرار تأكيد', (tester) async {
    await pumpShell(tester, snapshot(permissions: FollowerPermissions.plainFollower));
    expect(find.text('مرآة'), findsNothing);
    expect(find.text('متابعة'), findsWidgets);
    expect(find.text(CaregiverMirrorScreen.confirmLabel), findsNothing);
  });

  screenTest('«أكّد إنه أخدها» على المستحق والفايت بس — ومش على الجاي ولا اللي اتاخد', (tester) async {
    await pumpShell(tester, snapshot(permissions: nurse));
    // ٩:٠٠ فايتة (missed) و١٢:٠٠ مستحقة (now = ١٣:٠٠) — ٢٠:٠٠ جاية، ٧:٠٠ اتاخدت
    // «الآن» بيعرض أقدم فايتة (٩:٠٠) وبيكرّرها في الجدول → زرارين ليها
    final buttons = find.text(CaregiverMirrorScreen.confirmLabel);
    expect(buttons, findsNWidgets(3));
    expect(find.byKey(ValueKey('mirror-confirm-${event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending').uuid}')), findsNothing);
  });

  screenTest('الدوسة بتكتب صف نيابةً باسم الممرض للمريض ده، وبعدها الصف بيقول «أكّدتها ✓»', (tester) async {
    final (remote, proxy) = await pumpShell(tester, snapshot(permissions: nurse));
    final missed = event('Glucophage', DateTime(2026, 8, 31, 9), 'missed');
    remote.next = snapshot(permissions: nurse, proxied: {missed.uuid: null});
    await tester.tap(find.byKey(ValueKey('mirror-confirm-${missed.uuid}')).first);
    await settle(tester);

    expect(proxy.confirmed, hasLength(1));
    expect(proxy.confirmed.single.$1, 'p1');
    expect(proxy.confirmed.single.$2, missed.uuid);
    expect(find.text('أكّدتها ✓'), findsWidgets);
    expect(find.textContaining('مستنية موبايله'), findsWidgets);
    // مش بيتأكّد مرتين
    expect(find.byKey(ValueKey('mirror-confirm-${missed.uuid}')), findsNothing);
  });

  screenTest('السيرفر رفض → جملة واحدة، والزرار فاضل', (tester) async {
    final (_, proxy) = await pumpShell(tester, snapshot(permissions: nurse));
    proxy.failure = const CareCircleException(CareCircleFailure.offline);
    final missed = event('Glucophage', DateTime(2026, 8, 31, 9), 'missed');
    await tester.tap(find.byKey(ValueKey('mirror-confirm-${missed.uuid}')).first);
    await settle(tester);
    expect(find.byKey(const ValueKey('mirror-error')), findsOneWidget);
    expect(find.textContaining('مفيش نت'), findsOneWidget);
    expect(find.byKey(ValueKey('mirror-confirm-${missed.uuid}')), findsWidgets);
  });

  screenTest('ممرض من غير صلاحية التأكيد: بيشوف وبس، وجملة بتقول ليه', (tester) async {
    await pumpShell(tester, snapshot(permissions: quietNurse));
    expect(find.byType(CaregiverMirrorScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('mirror-read-only')), findsOneWidget);
    expect(find.text(CaregiverMirrorScreen.confirmLabel), findsNothing);
  });

  const editor = FollowerPermissions(role: FollowerRole.nurse, canConfirm: true, canEditMeds: true);

  screenTest('من غير «يعدّل الأدوية»: مفيش ضيف ولا وقّف ولا عدّل الجرعة', (tester) async {
    await pumpShell(tester, snapshot(permissions: nurse));
    expect(find.byKey(const ValueKey('mirror-add-medication')), findsNothing);
    expect(find.text('وقّفه'), findsNothing);
    expect(find.text('أدويته'), findsNothing);
  });

  screenTest('بصلاحية التعديل: «وقّفه» بتسأل وبتبعت تغيير معلّق باسم الدوا، والشاشة بتقول اتبعت', (tester) async {
    await pumpShell(tester, snapshot(permissions: editor));
    expect(find.byKey(const ValueKey('mirror-add-medication')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mirror-stop-m1')));
    await settle(tester);
    expect(find.text('توقّف Concor 5mg؟'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mirror-stop-confirm')));
    await settle(tester);
    expect(changes.submitted, [(MedicationChangeKind.stop, 'm1', null)]);
    expect(find.byKey(const ValueKey('mirror-pending-c0')), findsOneWidget);
    expect(find.textContaining('اتبعت لموبايله'), findsOneWidget);
  });

  screenTest('«عدّل الجرعة» بتبعت الجرعة الجديدة للدوا ده', (tester) async {
    await pumpShell(tester, snapshot(permissions: editor));
    await tester.tap(find.byKey(const ValueKey('mirror-amount-m1')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('mirror-amount-field')), 'قرصين');
    await tester.tap(find.byKey(const ValueKey('mirror-amount-save')));
    await settle(tester);
    expect(changes.submitted, [(MedicationChangeKind.amount, 'm1', 'قرصين')]);
  });
}
