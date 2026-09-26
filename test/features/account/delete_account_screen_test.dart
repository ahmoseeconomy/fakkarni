// «امسح حسابي» — الخطوتين، والموبايل ما بيتلمسش غير بعد «اتمسح» من السيرفر.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/account/account_deletion.dart';
import 'package:fakkarni/features/account/delete_account_screen.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/features/care/caregiver_settings_screen.dart';
import 'package:fakkarni/features/settings/settings_screen.dart';
import '../../data/auth/auth_service_test.dart' show FakeAuthService;

import '../scan/scan_test_support.dart';

class FakeDeletion implements AccountDeletionRemote {
  FakeDeletion(this.outcome);
  DeletionOutcome outcome;
  int calls = 0;
  @override
  Future<DeletionOutcome> deleteAccount() async {
    calls++;
    return outcome;
  }
}

AppServices _with(AppServices s, AccountDeletionRemote? remote, {FakeAuthService? auth}) => AppServices(
      auth: auth,
      db: s.db,
      routines: s.routines,
      medications: s.medications,
      events: s.events,
      scheduler: s.scheduler,
      patientId: s.patientId,
      accountDeletion: remote,
    );

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  Future<({FakeDeletion remote, List<int> wipes})> open(
    WidgetTester tester,
    DeletionOutcome outcome, {
    DeletingAs who = DeletingAs.patient,
    String patientName = '',
    bool linked = true,
  }) async {
    final remote = FakeDeletion(outcome);
    final wipes = <int>[];
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppScope(
      services: _with(h.services, remote),
      child: MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('home-open'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => DeleteAccountScreen(
                    who: who,
                    linked: linked,
                    patientName: patientName,
                    wipe: (_) async => wipes.add(1),
                  ),
                )),
                child: const Text('البيت'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('home-open')));
    await settle(tester);
    return (remote: remote, wipes: wipes);
  }

  screenTest('مش مربوط: نفس الخطوتين، ولا نداء سيرفر — الموبايل بيتمسح وبنرجع لأول شاشة', (tester) async {
    final r = await open(tester, DeletionOutcome.failed, linked: false);
    expect(find.byKey(const ValueKey('delete-local-only')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-continue')));
    await settle(tester);
    expect(r.wipes, isEmpty, reason: '«كمّل للمسح» لسه ما بتمسحش');
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await settle(tester);
    expect(r.remote.calls, 0, reason: 'مفيش سيرفر يتسأل');
    expect(r.wipes, [1]);
    expect(find.byType(DeleteAccountScreen), findsNothing);
    expect(find.text('البيت'), findsOneWidget);
  });

  screenTest('خطوتين: «كمّل للمسح» ما بتمسحش — «امسح حسابي نهائي» بس اللي بتنده السيرفر', (tester) async {
    final r = await open(tester, DeletionOutcome.deleted);
    expect(find.byKey(const ValueKey('delete-confirm')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('delete-continue')));
    await settle(tester);
    expect(r.remote.calls, 0, reason: 'الخطوة الأولى بتعرض بس');
    expect(find.text(finalWarningLine), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await settle(tester);
    expect(r.remote.calls, 1);
    expect(r.wipes, [1], reason: 'بعد «اتمسح» الموبايل بيتمسح');
    expect(find.byKey(const ValueKey('home-open')), findsOneWidget, reason: 'رجع لأول شاشة');
    expect(find.byType(DeleteAccountScreen), findsNothing);
  });

  for (final outcome in [DeletionOutcome.offline, DeletionOutcome.failed]) {
    screenTest('${outcome.name}: ولا حاجة على الموبايل اتلمست، والجملة بتقول كده', (tester) async {
      final r = await open(tester, outcome);
      await tester.tap(find.byKey(const ValueKey('delete-continue')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await settle(tester);
      expect(r.remote.calls, 1);
      expect(r.wipes, isEmpty, reason: 'السيرفر ما مسحش — الموبايل ما يتمسحش (مفيش نص حساب)');
      expect(find.text(deletionOutcomeLine(outcome)), findsOneWidget);
      expect(find.byType(DeleteAccountScreen), findsOneWidget, reason: 'فاضل على الشاشة يجرّب تاني');
      // وتاني محاولة ممكنة
      r.remote.outcome = DeletionOutcome.deleted;
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await settle(tester);
      expect(r.wipes, [1]);
    });
  }

  screenTest('المريض: القايمة بتقول الموبايل ده كمان، وسطر الاشتراك موجود، ومفيش أحمر', (tester) async {
    await open(tester, DeletionOutcome.deleted);
    for (final line in deletedLines(DeletingAs.patient)) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.text(storeSubscriptionLine), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-kept')), findsNothing);
    expectNoRedAndMinSize(tester);
    await tester.tap(find.byKey(const ValueKey('delete-continue')));
    await settle(tester);
    expectNoRedAndMinSize(tester);
  });

  screenTest('الممرض: بيانات المريض مش هتتمسح — بالاسم — والتأكيدات فاضلة من غير اسمه', (tester) async {
    await open(tester, DeletionOutcome.deleted, who: DeletingAs.nurse, patientName: 'الحاج عاشور');
    expect(find.textContaining('بيانات الحاج عاشور نفسها مش هتتمسح'), findsOneWidget);
    expect(find.textContaining('من غير اسمك'), findsOneWidget);
    expect(find.text('ربطك بـالحاج عاشور، واسمك وتفضيلاتك'), findsOneWidget);
  });

  test('المتابع من غير اسم مريض: «المريض» مش فراغ', () {
    expect(keptLine(DeletingAs.follower), startsWith('بيانات المريض نفسها'));
    expect(keptLine(DeletingAs.patient), isNull);
  });

  group('المداخل', () {
    Future<void> pumpScreen(WidgetTester tester, Widget screen, AppServices services) async {
      tester.view.physicalSize = const Size(1000, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: screen)),
        ),
      ));
      await settle(tester);
    }

    screenTest('المريض المربوط: الزرار آخر الإعدادات وبيفتح كلام المريض المربوط (السيرفر الأول)', (tester) async {
      final auth = FakeAuthService();
      await auth.signInToLink();
      await pumpScreen(tester, const SettingsScreen(), _with(h.services, FakeDeletion(DeletionOutcome.failed), auth: auth));
      await tester.ensureVisible(find.byKey(const ValueKey('settings-delete-account')));
      await tester.tap(find.byKey(const ValueKey('settings-delete-account')));
      await settle(tester);
      expect(find.text(deletedLines(DeletingAs.patient).last), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-local-only')), findsNothing);
      expect(find.byKey(const ValueKey('delete-store-note')), findsOneWidget);
    });

    screenTest('المريض مش مربوط: الزرار موجود برضه — وبيفتح «الموبايل ده بس»', (tester) async {
      await pumpScreen(tester, const SettingsScreen(), _with(h.services, null, auth: FakeAuthService()));
      await tester.ensureVisible(find.byKey(const ValueKey('settings-delete-account')));
      await tester.tap(find.byKey(const ValueKey('settings-delete-account')));
      await settle(tester);
      expect(find.byKey(const ValueKey('delete-local-only')), findsOneWidget);
      expect(find.text(localOnlyLine), findsOneWidget);
      expect(find.text('حسابك'), findsNothing, reason: 'مفيش حساب يتمسح');
      expect(find.byKey(const ValueKey('delete-store-note')), findsNothing);
    });

    screenTest('المريض بجلسة بس من غير خدمة مسح: بيتعامل كمش مربوط — الموبايل ده بس', (tester) async {
      final auth = FakeAuthService();
      await auth.signInToLink();
      await pumpScreen(tester, const SettingsScreen(), _with(h.services, null, auth: auth));
      await tester.ensureVisible(find.byKey(const ValueKey('settings-delete-account')));
      await tester.tap(find.byKey(const ValueKey('settings-delete-account')));
      await settle(tester);
      expect(find.byKey(const ValueKey('delete-local-only')), findsOneWidget);
    });

    screenTest('الممرض: الصف في إعداداته وبيفتح كلام الممرض باسم المريض', (tester) async {
      await pumpScreen(
        tester,
        const CaregiverSettingsScreen(
          patient: CaregiverPatient(
            uuid: 'p',
            name: 'الحاج عاشور',
            permissions: FollowerPermissions(role: FollowerRole.nurse, canConfirm: true, canEditMeds: false),
          ),
        ),
        _with(h.services, FakeDeletion(DeletionOutcome.failed)),
      );
      await tester.tap(find.byKey(const ValueKey('care-delete-account')));
      await settle(tester);
      expect(find.text('تذكيرات مواعيده على الموبايل ده'), findsOneWidget);
      expect(find.textContaining('بيانات الحاج عاشور نفسها'), findsOneWidget);
    });
  });
}
