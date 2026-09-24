import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/billing/subscription_service.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/billing/family_plan.dart';
import 'package:fakkarni/domain/care/follower_role.dart';
import 'package:fakkarni/features/billing/family_notice_cards.dart';
import 'package:fakkarni/features/billing/family_plan_screen.dart';

import '../../app/root_test.dart' show SilentSink;
import '../../data/billing/subscription_service_test.dart' show FakeRemote, FakeStore;
import '../care/caregiver_screen_test.dart' show FakeCaregiverRemote, event;
import '../scan/scan_test_support.dart' show screenTest, settle;

/// الدائرة بتتقال لها قبل ما تنبيهات المتابعين تقف وبعدها — عند المريض
/// سطر تحت الجدول، وعند المتابع/الممرض كارت دايم فوق الشاشة. «جدّد»
/// بتفتح «اشتراك العيلة». التذكير نفسه مش بيقرا حاجة من هنا
/// (`billing_mirror_test`).
void main() {
  final now = DateTime(2026, 8, 31, 14);
  late AppDatabase db;
  late FakeRemote remote;
  late SubscriptionService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    remote = FakeRemote();
    service = SubscriptionService(remote: remote, store: FakeStore(), clock: () => now)..patientUuid = 'p1';
    await service.load();
  });
  tearDown(() => db.close());

  Future<void> subscribe(FamilySubscription s) async {
    remote.next = s;
    await service.refresh();
  }

  final trialEndingIn3 = FamilySubscription(status: SubscriptionStatus.trial, trialEndsAt: DateTime(2026, 9, 3, 12));
  final expired = FamilySubscription(status: SubscriptionStatus.expired, trialEndsAt: DateTime(2026, 8, 1));
  final healthy = FamilySubscription(status: SubscriptionStatus.trial, trialEndsAt: DateTime(2026, 9, 20));

  Future<AppServices> services({CaregiverRemote? caregiver}) async {
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
    final events = DoseEventRepository(db);
    final patientId = await routines.ensurePatient();
    return AppServices(
      db: db,
      routines: routines,
      medications: meds,
      events: events,
      scheduler: ReminderScheduler(routines: routines, medications: meds, events: events, patientId: patientId, sink: SilentSink()),
      patientId: patientId,
      caregiver: caregiver,
      subscription: service,
    );
  }

  Future<void> pump(WidgetTester tester, AppServices s, Widget home) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppScope(
      services: s,
      child: MaterialApp(
        theme: F.light,
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      ),
    ));
    await settle(tester);
  }

  Widget patientCard({List<String> names = const ['محمد', 'سارة'], bool known = true}) => Scaffold(
        body: ListView(children: [PatientFamilyNotice(followerNames: names, followersKnown: known, now: now)]),
      );

  group('عند المريض', () {
    screenTest('٣ أيام قبل النهاية: أسامي المتابعين واليوم، و«جدّد» بتفتح اشتراك العيلة', (tester) async {
      await subscribe(trialEndingIn3);
      await pump(tester, await services(), patientCard());
      expect(find.textContaining('تنبيهات محمد وسارة هتقف يوم'), findsOneWidget);
      expect(find.textContaining('لو الاشتراك ما اتجددش'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('family-notice-renew')));
      await settle(tester);
      expect(find.byType(FamilyPlanScreen), findsOneWidget);
    });

    screenTest('بعد النهاية: سطر واحد بكلام البيت، ولا كلمة تقنية', (tester) async {
      await subscribe(expired);
      await pump(tester, await services(), patientCard());
      expect(find.text(familyEndedPatientLine), findsOneWidget);
      for (final w in ['اشتراك منتهي', 'expired', 'التحقق', 'السيرفر']) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
      expect(find.byKey(const ValueKey('family-notice-renew')), findsOneWidget);
    });

    screenTest('أكتر من ٧ أيام: مفيش حاجة', (tester) async {
      await subscribe(healthy);
      await pump(tester, await services(), patientCard());
      expect(find.byKey(const ValueKey('family-notice-endingSoon')), findsNothing);
    });

    screenTest('محدش بيتابعه (معروف): مفيش سطر — ومش معروف: السطر بيظهر', (tester) async {
      await subscribe(expired);
      await pump(tester, await services(), patientCard(names: const [], known: true));
      expect(find.text(familyEndedPatientLine), findsNothing);
      await pump(tester, await services(), patientCard(names: const [], known: false));
      expect(find.text(familyEndedPatientLine), findsOneWidget);
    });

    screenTest('المحاكاة «منتهي» من شاشة الاشتراك بتوري السطر على طول', (tester) async {
      await subscribe(healthy);
      await pump(tester, await services(), patientCard());
      expect(find.text(familyEndedPatientLine), findsNothing);
      await service.setDebugOverride(false);
      await settle(tester);
      expect(find.text(familyEndedPatientLine), findsOneWidget);
    });

    test('على «يومك» السطر تحت الجدول — عمره ما يزقّ «تأكيد الجرعة»', () {
      final src = File('lib/features/today/today_screen.dart').readAsStringSync();
      final rail = src.indexOf('DayRail(');
      final notice = src.indexOf('PatientFamilyNotice(');
      expect(rail, greaterThan(0));
      expect(notice, greaterThan(rail));
    });
  });

  group('عند المتابع والممرض', () {
    CaregiverSnapshot snap(FollowerPermissions p) => CaregiverSnapshot(
          patient: CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد', permissions: p),
          medications: const [],
          events: [event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending')],
          lastUpdated: DateTime(2026, 8, 31, 13),
        );
    const nurse = FollowerPermissions(role: FollowerRole.nurse, canConfirm: true, canEditMeds: false);

    for (final (label, perms, tab) in [
      ('المتابع على «متابعة»', FollowerPermissions.plainFollower, 'متابعة'),
      ('الممرض على «مرآة»', nurse, 'مرآة'),
    ]) {
      screenTest('$label: كارت دايم بعد النهاية باسم المريض، و«جدّد»', (tester) async {
        await subscribe(expired);
        final remote = FakeCaregiverRemote()..next = snap(perms);
        await pump(tester, await services(caregiver: remote), CaregiverShell(onNotLinked: () {}, now: now));
        expect(find.text(tab), findsWidgets);
        expect(find.text('التنبيهات واقفة — مش هتتبلّغ لو الحاج أحمد فوّت جرعة'), findsOneWidget);
        // دايم: مفيش «تمام» تشيله
        expect(find.descendant(of: find.byKey(const ValueKey('care-family-notice-ended')), matching: find.text('تمام')),
            findsNothing);
        await tester.tap(find.byKey(const ValueKey('care-family-notice-renew')));
        await settle(tester);
        expect(find.byType(FamilyPlanScreen), findsOneWidget);
      });

      screenTest('$label: قبلها بـ٣ أيام «تنبيهاتك عن الحاج أحمد هتقف يوم …»', (tester) async {
        await subscribe(trialEndingIn3);
        final remote = FakeCaregiverRemote()..next = snap(perms);
        await pump(tester, await services(caregiver: remote), CaregiverShell(onNotLinked: () {}, now: now));
        expect(find.textContaining('تنبيهاتك عن الحاج أحمد هتقف يوم'), findsOneWidget);
      });
    }

    screenTest('اشتراك سليم: مفيش كارت', (tester) async {
      await subscribe(healthy);
      final remote = FakeCaregiverRemote()..next = snap(FollowerPermissions.plainFollower);
      await pump(tester, await services(caregiver: remote), CaregiverShell(onNotLinked: () {}, now: now));
      expect(find.byKey(const ValueKey('care-family-notice-ended')), findsNothing);
      expect(find.byKey(const ValueKey('care-family-notice-endingSoon')), findsNothing);
    });
  });
}
