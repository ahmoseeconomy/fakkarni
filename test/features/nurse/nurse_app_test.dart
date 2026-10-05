import 'package:drift/native.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/features/today/widgets/day_rail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/billing/subscription_service.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import '../../support/fake_changes.dart';
import 'package:fakkarni/data/care/proxy_confirmations.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/care/medication_change.dart';
import 'package:fakkarni/domain/health/vitals.dart';
import 'package:fakkarni/data/services/nurse_reminder_plan.dart';
import 'package:fakkarni/features/nurse/nurse_records_screen.dart';
import 'package:fakkarni/features/nurse/nurse_reminders.dart';
import 'package:fakkarni/features/nurse/nurse_widgets.dart';

import '../../app/root_test.dart' show SilentSink;
import '../../data/billing/subscription_service_test.dart' show FakeRemote, FakeStore;
import '../care/caregiver_screen_test.dart' show event;
import '../scan/scan_test_support.dart' show settle, screenTest, pickWheel, expectNoRedAndMinSize;

final now = DateTime(2026, 8, 31, 14);

/// سحابة الممرض الوهمية: أكتر من مريض، وصور الورق.
class _NurseCloud implements CaregiverRemote, MultiPatientRemote, PaperPhotos {
  final snapshots = <String, CaregiverSnapshot>{};
  final downloads = <String>[];

  @override
  Future<List<CaregiverPatient>> linkedPatients() async => [for (final s in snapshots.values) s.patient];

  @override
  Future<CaregiverSnapshot?> snapshotFor(String patientUuid) async => snapshots[patientUuid];

  @override
  Future<CaregiverPatient?> linkedPatient() async => snapshots.values.firstOrNull?.patient;

  @override
  Future<CaregiverSnapshot?> snapshot() async => snapshots.values.firstOrNull;

  @override
  Future<List<int>?> download(String patientUuid, String recordUuid) async {
    downloads.add('$patientUuid/$recordUuid');
    return null; // الصورة ما نزلتش — الشاشة بتقول كده
  }
}

class _Proxy implements ProxyConfirmRemote {
  final confirmed = <(String, String)>[];
  CareCircleException? failure;

  @override
  Future<void> confirmOnBehalf({required String patientUuid, required String doseEventUuid, required String? actorName}) async {
    if (failure != null) throw failure!;
    confirmed.add((patientUuid, doseEventUuid));
  }

  @override
  Future<List<ProxyConfirmation>> fetchForPatient(String patientUuid, {required DateTime since}) async => const [];
}


class _NoDevice implements NurseReminderSink {
  final scheduled = <NurseNotification>[];
  @override
  Future<void> schedule(NurseNotification n) async => scheduled.add(n);
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<Set<int>> pendingIds() async => {};
}

void main() {
  late AppDatabase db;
  late _NurseCloud cloud;
  late _Proxy proxy;
  late FakeChanges changes;
  late SubscriptionService sub;

  const nurse = FollowerPermissions(role: FollowerRole.nurse, canConfirm: true, canEditMeds: false);
  const editor = FollowerPermissions(role: FollowerRole.nurse, canConfirm: true, canEditMeds: true);

  final missed = event('Glucophage', DateTime(2026, 8, 31, 9), 'missed');
  final due = event('Glucophage', DateTime(2026, 8, 31, 12), 'pending');
  final later = event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending');

  CaregiverSnapshot snap({
    String uuid = 'p1',
    String name = 'الحاج أحمد',
    FollowerPermissions permissions = nurse,
    Map<String, String?> proxied = const {},
    List<CaregiverRecord> records = const [],
    Set<String> shared = const {},
    List<Vital> vitals = const [],
    DateTime? notBoughtAt,
  }) =>
      CaregiverSnapshot(
        patient: CaregiverPatient(uuid: uuid, name: name, permissions: permissions),
        medications: [
          CaregiverMedication(
            uuid: 'm1',
            name: 'Concor 5mg',
            amountLabel: 'قرص واحد',
            rules: ['الفطار − ٣٠ د'],
            purpose: 'pressure',
            form: 'tablet',
            instructions: 'بعد الأكل',
            alertMode: 'continuous',
            stockQuantity: 6,
            dosesPerDay: 2,
            notBoughtAt: notBoughtAt,
          ),
        ],
        events: [
          event('Concor 5mg', DateTime(2026, 8, 31, 7), 'taken', actedAt: DateTime(2026, 8, 31, 7, 5)),
          missed,
          due,
          later,
        ],
        lastUpdated: DateTime(2026, 8, 31, 13),
        proxied: proxied,
        records: records,
        sharedPapers: shared,
        vitals: vitals,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    cloud = _NurseCloud();
    proxy = _Proxy();
    changes = FakeChanges();
    sub = SubscriptionService(remote: FakeRemote(), store: FakeStore(), clock: () => now);
    await sub.load();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final patients = PatientRepository(db);
    final meds = MedicationRepository(db);
    final events = DoseEventRepository(db);
    final patientId = await patients.ensurePatient();
    await tester.pumpWidget(AppScope(
      services: AppServices(
        db: db,
        patients: patients,
        medications: meds,
        events: events,
        scheduler: ReminderScheduler(medications: meds, events: events, patientId: patientId, sink: SilentSink()),
        patientId: patientId,
        caregiver: cloud,
        proxy: proxy,
        medChanges: changes,
        subscription: sub,
      ),
      child: MaterialApp(
        theme: F.light,
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: CaregiverShell(onNotLinked: () {}, now: now, nurseSink: _NoDevice()),
      ),
    ));
    await settle(tester);
  }

  group('تطبيق الممرض', () {
    screenTest('علاقة ممرض = تطبيق المريض: «يومك» و«أدويته» و«الملف الطبي» و«بتتابع: الاسم» فوق', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      for (final tab in ['يومك', 'الأدوية', 'ملفّي', 'الإعدادات']) {
        expect(find.text(tab), findsWidgets, reason: tab);
      }
      // «ضيف» جوّه الدوك زي المريض — بصلاحية التعديل بس (اللقطة دي من غيرها)
      expect(find.text('ضيف'), findsNothing);
      expect(find.text('متابعة'), findsNothing);
      expect(find.text('بتتابع: الحاج أحمد'), findsOneWidget);
      // الشكل الجديد (المرحلة ٤): التحية بالشمس والدايرة وكارت «الجرعة
      // الجاية» و«باقي اليوم» — زي «يومك» عند المريض
      expect(find.byKey(const ValueKey('nurse-greeting')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-progress-ring')), findsOneWidget);
      expect(find.text('الجرعة الجاية'), findsOneWidget);
      expect(find.text('باقي اليوم'), findsOneWidget);
      expect(find.text('معلومة تهمك'), findsOneWidget, reason: 'كارت المعلومة زي «يومك»');
    });

    screenTest('ملخص الأسبوع فوق «الآن» عند الممرض (طلب المدير، ٤ أكتوبر ٢٠٢٦)', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      expect(find.byKey(const ValueKey('weekly-summary')), findsOneWidget);
      expect(find.text('ملخص الأسبوع — ٢٤ أغسطس لـ٣٠ أغسطس'), findsOneWidget);
      final summaryY = tester.getTopLeft(find.byKey(const ValueKey('weekly-summary'))).dy;
      expect(summaryY, lessThan(tester.getTopLeft(find.byKey(const ValueKey('nurse-now-card'))).dy),
          reason: 'الملخص فوق كارت «الجرعة الجاية»');
    });

    screenTest('المتابع العادي: شاشته القديمة زي ما هي', (tester) async {
      cloud.snapshots['p1'] = snap(permissions: FollowerPermissions.plainFollower);
      await pump(tester);
      expect(find.text('متابعة'), findsWidgets);
      expect(find.text('بتتابع: الحاج أحمد'), findsNothing);
    });

    screenTest('«أكّد إنه أخدها» على الفايت والمستحق بس، والدوسة تأكيد نيابةً للمريض ده', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      expect(find.byKey(ValueKey('nurse-confirm-${missed.uuid}')), findsWidgets);
      expect(find.byKey(ValueKey('nurse-confirm-${due.uuid}')), findsOneWidget);
      expect(find.byKey(ValueKey('nurse-confirm-${later.uuid}')), findsNothing, reason: 'الجاية لسه');

      cloud.snapshots['p1'] = snap(proxied: {missed.uuid: null});
      await tester.tap(find.byKey(ValueKey('nurse-confirm-${missed.uuid}')).first);
      await settle(tester);
      expect(proxy.confirmed, [('p1', missed.uuid)]);
      expect(find.textContaining('أكّدتها ✓'), findsWidgets);
      expect(find.byKey(ValueKey('nurse-confirm-${missed.uuid}')), findsNothing);
    });

    screenTest('السيرفر رفض → جملة واحدة، والزرار فاضل', (tester) async {
      cloud.snapshots['p1'] = snap();
      proxy.failure = const CareCircleException(CareCircleFailure.offline);
      await pump(tester);
      await tester.tap(find.byKey(ValueKey('nurse-confirm-${due.uuid}')));
      await settle(tester);
      expect(find.byKey(const ValueKey('nurse-error')), findsOneWidget);
      expect(find.byKey(ValueKey('nurse-confirm-${due.uuid}')), findsOneWidget);
    });

    screenTest('الاشتراك خلص: الكارت الذهبي و«جدّد»، ومفيش تأكيد — القراية شغّالة', (tester) async {
      cloud.snapshots['p1'] = snap();
      await sub.setDebugOverride(false);
      await pump(tester);
      expect(find.byKey(const ValueKey('nurse-family-notice-ended')), findsOneWidget);
      expect(find.byKey(const ValueKey('nurse-family-renew')), findsOneWidget);
      expect(find.text(nurseConfirmLabel), findsNothing);
      expect(find.textContaining('Glucophage'), findsWidgets);
    });

    screenTest('أكتر من مريض: «غيّر» بيبدّل، والشاشة كلها بتبقى عن التاني', (tester) async {
      cloud.snapshots['p1'] = snap();
      cloud.snapshots['p2'] = snap(uuid: 'p2', name: 'الحاجة فاطمة');
      await pump(tester);
      expect(find.text('بتتابع: الحاج أحمد'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nurse-switch')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('nurse-patient-p2')));
      await settle(tester);
      expect(find.text('بتتابع: الحاجة فاطمة'), findsOneWidget);
    });

    screenTest('مدة الملخص لكل مريض لوحده: «غيّر» لمريض تاني بيرجّعها لافتراضيها', (tester) async {
      cloud.snapshots['p1'] = snap();
      cloud.snapshots['p2'] = snap(uuid: 'p2', name: 'الحاجة فاطمة');
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('summary-range')));
      await settle(tester);
      await pickWheel(tester, const ValueKey('range-to-wheel'), 3);
      await pickWheel(tester, const ValueKey('range-from-wheel'), 1);
      await tester.tap(find.byKey(const ValueKey('range-save')));
      await settle(tester);
      expect(find.textContaining('الملخص —'), findsOneWidget, reason: 'مدة مختارة لمريض الأول');

      await tester.tap(find.byKey(const ValueKey('nurse-switch')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('nurse-patient-p2')));
      await settle(tester);
      // المفتاح بالمريض: مدة الأول ما اتشالتش للتانية
      expect(find.textContaining('ملخص الأسبوع'), findsOneWidget);
      expect(find.textContaining('الملخص —'), findsNothing);
    });

    screenTest('مريض واحد: مفيش «غيّر»', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      expect(find.byKey(const ValueKey('nurse-switch')), findsNothing);
    });
  });

  group('المرحلة ٤ — شكل «يومك» الجديد عند الممرض', () {
    screenTest('الدايرة بتعدّ من صفوف الصورة، وكارت «الجرعة الجاية» بزراره الواحد — ومفيش تأجيل', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      // ٤ جرعات النهارده، واحدة متاخدة
      expect(find.text('١ من ٤'), findsOneWidget);
      // الكارت: الفايتة (٩) واللي معادها دلوقتي (١٢) — سطرين بزرار محدّد لكل واحد
      expect(find.text('الجرعة الجاية'), findsOneWidget);
      expect(find.text('أكّد إنه أخدها'), findsNWidgets(2));
      // **قرار 3A**: ولا تأجيل ولا «أخدتهم كلهم» — الممرض ما بيأجّلش جدول المريض
      expect(find.textContaining('فكّرني'), findsNothing);
      expect(find.textContaining('لاحق'), findsNothing);
      expect(find.text('أخدتهم كلهم'), findsNothing);
      expectNoRedAndMinSize(tester);
    });

    screenTest('«باقي اليوم»: المتاخدة والجاية بالسكة ورسمة النوع — والصف مش بيتداس', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      expect(find.text('باقي اليوم'), findsOneWidget);
      final rail = find.byType(DayRail);
      // المتاخدة ٧:٠٠ والجاية ٨:٠٠ م (Concor) على السكة — الكارت مفيهوش Concor
      expect(find.descendant(of: rail, matching: find.byKey(const ValueKey('med-type-art-tablet'))), findsNWidgets(2));
      expect(find.byKey(const ValueKey('rail-mark-done')), findsOneWidget);
      // ومفيش InkWell بيفتح حاجة — onOpen null (مفيش شاشة تذكير عنده)
      final rows = tester.widgetList<InkWell>(
        find.descendant(of: rail, matching: find.byType(InkWell)),
      );
      for (final r in rows) {
        expect(r.onTap, isNull, reason: 'صف السكة عند الممرض مش بيتداس');
      }
    });

    screenTest('مفيش أدوية النهارده: مفيش دايرة ولا كارت — والسطر الهادي نفسه بتاع المريض', (tester) async {
      final empty = snap();
      cloud.snapshots['p1'] = CaregiverSnapshot(
        patient: empty.patient,
        medications: const [],
        events: const [],
        lastUpdated: DateTime(2026, 8, 31, 13),
      );
      await pump(tester);
      expect(find.byKey(const ValueKey('today-progress-ring')), findsNothing);
      expect(find.byKey(const ValueKey('nurse-now-card')), findsNothing);
      expect(find.text('مفيش أدوية النهارده'), findsOneWidget);
    });

    screenTest('التحية بالشمس الحقيقية — الضهر صباح', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester); // now = ٢ الضهر
      expect(find.text('صباح الخير'), findsOneWidget);
      expect(find.byKey(const ValueKey('nurse-greeting-sun')), findsOneWidget);
    });
  });

  group('«أدويته»', () {
    screenTest('مجموعات بالغرض بألوانها — رأس «للقلب والضغط» ورسمة النوع بديل الصورة (قرار 2A)', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      await tester.tap(find.text('الأدوية'));
      await settle(tester);
      expect(find.byKey(const ValueKey('med-group-heartPressure')), findsOneWidget);
      expect(find.text('للقلب والضغط'), findsOneWidget);
      // الصورة مش موجودة (التنزيل بيرجّع null) → رسمة النوع مش أيقونة عامة
      expect(find.byKey(const ValueKey('med-type-art-tablet')), findsWidgets);
      expectNoRedAndMinSize(tester);
    });

    screenTest('التفاصيل كاملة: الجرعة والميعاد والغرض والتعليمات والتنبيه', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      await tester.tap(find.text('الأدوية').last);
      await settle(tester);
      expect(find.textContaining('الفطار − ٣٠ د'), findsOneWidget);
      expect(find.textContaining('ضغط'), findsNWidgets(2) /* سطر الغرض + رأس المجموعة الجديد */);
      expect(find.textContaining('بعد الأكل'), findsOneWidget);
      expect(find.textContaining('مستمر'), findsOneWidget);
      expect(find.byKey(const ValueKey('nurse-add-medication')), findsNothing, reason: 'من غير صلاحية التعديل');
    });

    screenTest('بصلاحية التعديل: «وقّفه» بتسأل وبتبعت طلب، والشاشة بتقول اتبعت', (tester) async {
      cloud.snapshots['p1'] = snap(permissions: editor);
      await pump(tester);
      await tester.tap(find.text('الأدوية').last);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('nurse-stop-m1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('nurse-stop-confirm')));
      await settle(tester);
      expect(changes.kinds, [MedicationChangeKind.stop]);
      expect(find.textContaining('اتبعت لموبايله'), findsOneWidget);
    });
  });

  group('المخزون', () {
    screenTest('سطر المخزون قراية، وبصلاحية التعديل «اشتريت علبة جديدة» طلب مستني موبايل المريض', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      await tester.tap(find.text('الأدوية').last);
      await settle(tester);
      expect(find.text('Concor 5mg فاضله ٣ أيام'), findsOneWidget);
      expect(find.byKey(const ValueKey('nurse-restock-m1')), findsNothing, reason: 'من غير صلاحية التعديل');
    });

    screenTest('بصلاحية التعديل: العلبة الجديدة بتتبعت كتغيير «restock» بالكمية', (tester) async {
      cloud.snapshots['p1'] = snap(permissions: editor);
      await pump(tester);
      await tester.tap(find.text('الأدوية').last);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('nurse-restock-m1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('restock-save')));
      await settle(tester);
      expect(changes.kinds, [MedicationChangeKind.restock]);
      expect(changes.submitted.single.quantity, 30);
      expect(find.textContaining('اتبعت لموبايله'), findsOneWidget);
    });
  });

  group('«الملف الطبي»', () {
    final paper = CaregiverRecord(
      uuid: 'r1',
      kind: 'prescription',
      title: 'روشتة د. حسام',
      happenedAt: DateTime(2026, 8, 20),
      updatedAt: DateTime(2026, 8, 20),
    );

    screenTest('٠٠٣١: «أدوية لسه ماتشترتش» — من غير «يعدّل الأدوية» قراية بس', (tester) async {
      cloud.snapshots['p1'] = snap(notBoughtAt: DateTime(2026, 8, 30));
      await pump(tester);
      await tester.tap(find.text('ملفّي').last);
      await settle(tester);
      expect(find.text('أدوية لسه ماتشترتش (١)'), findsOneWidget);
      expect(find.byKey(const ValueKey('nurse-not-bought-m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('nurse-bought-m1')), findsNothing);
    });

    screenTest('٠٠٣١: بـ«يعدّل الأدوية» «اشتريته» بيبعت تغيير bought — ومن غير المخزون', (tester) async {
      cloud.snapshots['p1'] = snap(permissions: editor, notBoughtAt: DateTime(2026, 8, 30));
      await pump(tester);
      await tester.tap(find.text('ملفّي').last);
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('nurse-bought-m1')));
      await tester.tap(find.byKey(const ValueKey('nurse-bought-m1')));
      await settle(tester);
      expect(changes.kinds, [MedicationChangeKind.bought]);
      expect(changes.submitted.single.quantity, isNull, reason: 'مفيش كمية بتتخمّن');
    });

    screenTest('مفيش حاجة لسه ماتشترتش → القسم مش موجود', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      await tester.tap(find.text('ملفّي').last);
      await settle(tester);
      expect(find.textContaining('لسه ماتشترتش'), findsNothing);
    });

    screenTest('التلات أقسام، والورقة من غير صورة مشاركة بتقول «الصورة على موبايل المريض»', (tester) async {
      cloud.snapshots['p1'] = snap(records: [paper]);
      await pump(tester);
      await tester.tap(find.text('ملفّي').last);
      await settle(tester);
      expect(find.text('مواعيدك الجاية'), findsOneWidget);
      expect(find.text('أوراقك'), findsOneWidget);
      expect(find.text('للدكتور'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nurse-paper-r1')));
      await settle(tester);
      expect(find.byType(NurseRecordScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('nurse-photo-on-phone')), findsOneWidget);
      expect(cloud.downloads, isEmpty);
      expect(find.text('بتتابع: الحاج أحمد'), findsOneWidget, reason: 'الترويسة ثابتة على الشاشات المفتوحة كمان');
    });

    screenTest('الصورة مشاركة: بيحاول ينزّلها بدل السطر', (tester) async {
      cloud.snapshots['p1'] = snap(records: [paper], shared: {'r1'});
      await pump(tester);
      await tester.tap(find.text('ملفّي').last);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('nurse-paper-r1')));
      await settle(tester);
      expect(cloud.downloads, ['p1/r1']);
      expect(find.byKey(const ValueKey('nurse-photo-on-phone')), findsNothing);
    });

    screenTest('بصلاحية التعديل: «ميعاد جديد» بيبعت طلب ميعاد للمريض', (tester) async {
      cloud.snapshots['p1'] = snap(permissions: editor);
      await pump(tester);
      await tester.tap(find.text('ملفّي').last);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('nurse-new-appointment')));
      await settle(tester);
      expect(find.byKey(const ValueKey('start-follow-visit')), findsNothing, reason: 'مفيش «عندي روشتة» للممرض');
      await tester.tap(find.byKey(const ValueKey('new-appt-save')));
      await settle(tester);
      expect(changes.kinds, [MedicationChangeKind.appointment]);
      expect(changes.submitted.single.followKind, 'visit');
      expect(changes.submitted.single.day, DateTime(2026, 9, 1), reason: 'بكرة افتراضياً');
    });

    screenTest('بصلاحية التعديل: «ورقة جديدة» بعنوان بتتبعت كطلب ورقة', (tester) async {
      cloud.snapshots['p1'] = snap(permissions: editor);
      await pump(tester);
      await tester.tap(find.text('ملفّي').last);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('nurse-new-record')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('nurse-record-title')), 'كشف القلب');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('nurse-record-save')));
      await settle(tester);
      expect(changes.kinds, [MedicationChangeKind.record]);
      expect(changes.submitted.single.name, 'كشف القلب');
      expect(changes.submitted.single.recordKind, 'visit');
    });

    screenTest('من غير صلاحية التعديل: مفيش «ميعاد جديد» ولا «ورقة جديدة»', (tester) async {
      cloud.snapshots['p1'] = snap();
      await pump(tester);
      await tester.tap(find.text('ملفّي').last);
      await settle(tester);
      expect(find.byKey(const ValueKey('nurse-new-appointment')), findsNothing);
      expect(find.byKey(const ValueKey('nurse-new-record')), findsNothing);
    });
  });

  group('آيفون SE بخط ×١٫٣', () {
    for (final tab in ['يومك', 'الأدوية', 'ملفّي']) {
      screenTest('«$tab»: مفيش فيض، و«بتتابع» ظاهرة', (tester) async {
        cloud.snapshots['p1'] = snap(permissions: editor, name: 'الحاج أحمد عبد الرحمن');
        cloud.snapshots['p2'] = snap(uuid: 'p2', name: 'الحاجة فاطمة');
        await pump(tester);
        tester.view.physicalSize = const Size(375, 667);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await settle(tester);
        await tester.tap(find.text(tab).last);
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('nurse-following')), findsOneWidget);
        expect(find.byKey(const ValueKey('nurse-switch')), findsOneWidget);
      });
    }
  });

  // كل تبويب عند الممرض والمتابع على مقاسات حقيقية بخط ×١٫٣ — أصغر موبايل
  // لحد الآيباد. أي فيضان بيوقّع (takeException).
  group('كل المقاسات بخط ×١٫٣', () {
    const sizes = <String, Size>{
      '٣٢٠×٥٦٨': Size(320, 568),
      // ضيق وطويل: القوايم بتبني الصفوف اللي تحت الطية على أضيق عرض
      '٣٢٠×٢٤٠٠': Size(320, 2400),
      '٣٦٠×٦٤٠': Size(360, 640),
      '٤٣٠×٩٣٢': Size(430, 932),
      '٧٦٨×١٠٢٤': Size(768, 1024),
      '١٠٢٤×٧٦٨': Size(1024, 768),
    };
    final roles = <String, (FollowerPermissions, List<String>)>{
      'ممرض': (editor, ['يومك', 'الأدوية', 'ملفّي', 'الإعدادات']),
      'متابع': (FollowerPermissions.plainFollower, ['متابعة', 'الأدوية', 'الملف الطبي', 'الإعدادات']),
    };
    for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
      for (final MapEntry(key: role, value: (perms, tabs)) in roles.entries) {
        for (final tab in tabs) {
          screenTest('$role — $sizeName — «$tab»: مفيش فيض', (tester) async {
            cloud.snapshots['p1'] = snap(permissions: perms, name: 'الحاج أحمد عبد الرحمن');
            cloud.snapshots['p2'] = snap(uuid: 'p2', name: 'الحاجة فاطمة');
            await pump(tester);
            tester.view.physicalSize = size;
            tester.platformDispatcher.textScaleFactorTestValue = 1.3;
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
            await settle(tester);
            await tester.tap(find.text(tab).last);
            await settle(tester);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('القياسات عند العيلة والممرض — قراية بس', () {
    final vitals = [Vital(kind: VitalKind.weight, value: 72.5, measuredAt: DateTime(2026, 8, 31, 9))];

    screenTest('الممرض: «قياساته» في «الملف الطبي»، والتاريخ من غير «سجّل قياس»', (tester) async {
      cloud.snapshots['p1'] = snap(vitals: vitals);
      await pump(tester);
      await tester.tap(find.text('ملفّي').last);
      await settle(tester);
      expect(find.text('قياساته'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vital-summary-weight')));
      await settle(tester);
      expect(find.text('٧٢٫٥ كيلو'), findsWidgets);
      expect(find.byKey(const ValueKey('vital-add')), findsNothing);
      expect(find.text('بتتابع: الحاج أحمد'), findsOneWidget);
    });

    screenTest('المتابع: مدخل «القياسات» في «الملف الطبي» بيفتح قراية بس', (tester) async {
      cloud.snapshots['p1'] = snap(permissions: FollowerPermissions.plainFollower, vitals: vitals);
      await pump(tester);
      await tester.tap(find.text('الملف الطبي').last);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('care-entry-vitals')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('vital-summary-weight')));
      await settle(tester);
      expect(find.text('٧٢٫٥ كيلو'), findsWidgets);
      expect(find.byKey(const ValueKey('vital-add')), findsNothing);
      expect(find.byKey(const ValueKey('vital-ask-doctor')), findsNothing);
    });
  });

  group('لقطات المرحلة ٤ — PNG حقيقية من نفس الحزام (المحاكي محتاج حساب مربوط)', () {
    setUpAll(() async {
      final loader = FontLoader('Cairo');
      for (final f in [
        'Cairo-Regular.ttf',
        'Cairo-Medium.ttf',
        'Cairo-SemiBold.ttf',
        'Cairo-Bold.ttf',
        'Cairo-ExtraBold.ttf',
      ]) {
        loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
      }
      await loader.load();
    });

    tearDown(() => F.setDark(on: false));

    Future<void> capture(WidgetTester tester, String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture-root')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        final file = File('build/capture/nurse/$name.png')..createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    Future<void> shoot(WidgetTester tester, {required bool dark, required bool withMeds}) async {
      F.setDark(on: dark);
      final empty = snap();
      cloud.snapshots['p1'] = withMeds
          ? snap()
          : CaregiverSnapshot(
              patient: empty.patient,
              medications: const [],
              events: const [],
              lastUpdated: DateTime(2026, 8, 31, 13),
            );
      tester.view.physicalSize = const Size(780, 1688); // 390×844 @2x
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final patients = PatientRepository(db);
      final meds = MedicationRepository(db);
      final events = DoseEventRepository(db);
      final patientId = await patients.ensurePatient();
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('capture-root'),
        child: AppScope(
          services: AppServices(
            db: db,
            patients: patients,
            medications: meds,
            events: events,
            scheduler: ReminderScheduler(medications: meds, events: events, patientId: patientId, sink: SilentSink()),
            patientId: patientId,
            caregiver: cloud,
            proxy: proxy,
            medChanges: changes,
            subscription: sub,
          ),
          child: MaterialApp(
            theme: F.light,
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: CaregiverShell(onNotLinked: () {}, now: now, nurseSink: _NoDevice()),
            ),
          ),
        ),
      ));
      await settle(tester);
      final mode = dark ? 'night' : 'day';
      final who = withMeds ? 'meds' : 'empty';
      await capture(tester, 'today-$mode-$who');
      await tester.tap(find.text('الأدوية').last);
      await settle(tester);
      await capture(tester, 'medications-$mode-$who');
    }

    for (final dark in [false, true]) {
      for (final withMeds in [true, false]) {
        screenTest('لقطة ${dark ? 'ليلي' : 'نهاري'} — ${withMeds ? 'بأدوية' : 'من غير'}', (tester) async {
          await shoot(tester, dark: dark, withMeds: withMeds);
        });
      }
    }
  });
}
