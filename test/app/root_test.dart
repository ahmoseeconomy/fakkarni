import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/root.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/auth/auth_service.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/data/care/care_circle_service.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/features/entry/entry_screen.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/features/onboarding/routine_onboarding_screen.dart';
import 'package:fakkarni/features/link/sign_in_screen.dart';
import 'package:fakkarni/features/reminder/reminder_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';
import '../support/seeded_clock.dart';

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

class SilentSink implements ReminderSink {
  @override
  Future<void> schedule(PlannedNotification notification) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<Set<int>> pendingIds() async => {};
  @override
  Future<void> ensurePermissions() async {}
}

void screenTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}

void main() {
  late AppDatabase db;
  late RoutineRepository routines;
  late MedicationRepository meds;
  late ValueNotifier<String?> tap;
  late AppServices services;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    meds = MedicationRepository(db, clock: seededLongAgo);
    tap = ValueNotifier<String?>(null);
    final patientId = await routines.ensurePatient();
    services = AppServices(
      db: db,
      routines: routines,
      medications: meds,
      events: DoseEventRepository(db),
      scheduler: ReminderScheduler(
        routines: routines,
        medications: meds,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: SilentSink(),
      ),
      patientId: patientId,
      tapPayload: tap,
    );
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpRoot(WidgetTester tester) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const AppRoot(),
        ),
      ),
    );
    await settle(tester);
  }

  String payloadFor(List<String> ids) =>
      encodePayloadFor(DateTime(2026, 8, 31), ids);

  // ⚠️ حارس «الهوية مش بوابة». لو الاختبار ده وقع فحد حط دخول في وش
  // المستخدم عند الفتح — وده ممنوع بنص CLAUDE.md: التطبيق كامل من غير
  // حساب، وباب الدخول الوحيد «اربط ابني». صحّح التصميم، متصحّحش الاختبار.
  screenTest('حارس: الفتح من غير أي جلسة بيدخل على التطبيق نفسه، مش على شاشة دخول',
      (tester) async {
    // الهوية **متظبطة وموجودة** — وبرضه ولا جلسة ولا نداء دخول عند الفتح.
    // لو الحارس ده بقى صحيح-تلقائياً لأن جلسة بتتعمل دايماً، يبقى اتشال.
    final fakeAuth = _CountingAuth();
    services = AppServices(
      db: services.db,
      routines: services.routines,
      medications: services.medications,
      events: services.events,
      scheduler: services.scheduler,
      patientId: services.patientId,
      tapPayload: tap,
      auth: fakeAuth,
    );
    await routines.saveRoutine(services.patientId, normalDay);
    await pumpRoot(tester);

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
    expect(fakeAuth.signInCalls, 0, reason: 'signInToLink من الزرار وبس');
    expect(fakeAuth.currentUser, isNull, reason: 'تنزيلة جديدة = صفر جلسات');
    // وكل حاجة أساسية موجودة وشغّالة — «ضيف» في الهيكل بيفتح الروشتة والإدخال
    expect(find.text('جدول النهاردة'), findsOneWidget);
    expect(find.text('ضيف'), findsOneWidget);
  });

  screenTest('حارس: «اربط ابني» → «مش دلوقتي» بترجّع لـ«يومك» كاملة', (tester) async {
    await routines.saveRoutine(services.patientId, normalDay);
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpRoot(tester);

    // «اربط ابني» بقى في تبويب «العائلة» — والباب لسه بالدوسة وبس
    await tester.tap(find.text('العائلة'));
    await settle(tester);
    await tester.tap(find.text('اربط ابني'));
    await settle(tester);
    expect(find.byType(SignInScreen), findsOneWidget);

    await tester.tap(find.text('مش دلوقتي'));
    await settle(tester);
    expect(find.byType(SignInScreen), findsNothing);

    await tester.tap(find.text('اليوم'));
    await settle(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('جدول النهاردة'), findsOneWidget);
    expect(find.text('ضيف'), findsOneWidget);
  });

  screenTest('جنس اتسأل ومن غير روتين → الأسئلة الأول (مش شاشة البداية تاني)', (tester) async {
    await routines.saveProfile(services.patientId, name: 'أحمد', sex: Sex.m);
    await pumpRoot(tester);
    expect(find.byType(RoutineOnboardingScreen), findsOneWidget);
    expect(find.byType(EntryScreen), findsNothing);
    expect(find.byType(TodayScreen), findsNothing);
  });

  group('D4 — «مين ماسك التليفون؟»', () {
    late _SessionAuth auth;
    late _FakeCare care;
    late _FakeRemote remote;
    late _CountingSink sink;

    void useCloud() {
      auth = _SessionAuth();
      care = _FakeCare();
      remote = _FakeRemote();
      sink = _CountingSink();
      services = AppServices(
        db: db,
        routines: routines,
        medications: meds,
        events: services.events,
        scheduler: ReminderScheduler(
          routines: routines,
          medications: meds,
          events: services.events,
          patientId: services.patientId,
          sink: sink,
        ),
        patientId: services.patientId,
        tapPayload: tap,
        auth: auth,
        care: care,
        caregiver: remote,
      );
    }

    Future<void> tallView(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    // ⚠️ نفس روح الحارس فوق: الشاشة دي سؤال، مش تسجيل دخول
    screenTest('تنزيلة نضيفة (والهوية متظبطة) → شاشة البداية، وصفر جلسات وصفر نداءات دخول',
        (tester) async {
      useCloud();
      await tallView(tester);
      await pumpRoot(tester);

      expect(find.byType(EntryScreen), findsOneWidget);
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.byType(RoutineOnboardingScreen), findsNothing);
      expect(auth.signInCalls, 0);
      expect(auth.currentUser, isNull);
    });

    screenTest('«التليفون ده ليا» → «نتعرّف عليك» بالمخاطب، زي ما كانت', (tester) async {
      await tallView(tester);
      await pumpRoot(tester);
      await tester.tap(find.byKey(const ValueKey('entry-self')));
      await settle(tester);

      expect(find.byType(RoutineOnboardingScreen), findsOneWidget);
      expect(find.text('نتعرّف عليك'), findsOneWidget);
      expect(find.text('اسمك إيه؟'), findsOneWidget);
    });

    screenTest('«بظبّط لحد تاني» → الأسئلة عن المريض: أول سؤال محايد، والباقي بالغايب', (tester) async {
      await tallView(tester);
      await pumpRoot(tester);
      await tester.tap(find.byKey(const ValueKey('entry-other')));
      await settle(tester);

      expect(find.text('اسم والدك أو والدتك إيه؟'), findsOneWidget);
      expect(find.text('اسمك إيه؟'), findsNothing);

      await tester.enterText(find.byType(TextField), 'الحاجة فاطمة');
      await tester.tap(find.text('ست'));
      await settle(tester);
      expect(find.text('سنّها كام؟ (لو تعرف)'), findsOneWidget);
      await tester.tap(find.text('كمّل'));
      await settle(tester);

      expect(find.text('بتصحى الساعة كام؟'), findsOneWidget, reason: 'هي بتصحى — مش «بتصحي» (إنتي)');
      expect(find.text('يومها بيبدأ من هنا — كل المواعيد بتترتب عليه.'), findsOneWidget);
      expect(find.text('خلينا نعرف يومها'), findsOneWidget);
    });

    screenTest('«رجوع» من «نتعرّف عليك» بترجّع لشاشة البداية — اختيار غلط ما يحبسش حد', (tester) async {
      await tallView(tester);
      await pumpRoot(tester);
      await tester.tap(find.byKey(const ValueKey('entry-self')));
      await settle(tester);
      await tester.tap(find.text('رجوع'));
      await settle(tester);
      expect(find.byType(EntryScreen), findsOneWidget);
    });

    screenTest('«بعتلي كود» → دخول → كود → المتابعة: ولا سؤال مريض، ولا روتين، ولا مريض اتعرّف',
        (tester) async {
      useCloud();
      await tallView(tester);
      await pumpRoot(tester);

      await tester.tap(find.byKey(const ValueKey('entry-code')));
      await settle(tester);
      expect(find.text('حساب عشان تتابع'), findsOneWidget);
      expect(find.text('اعرض كود الربط'), findsNothing, reason: 'ده طريق المريض');
      expect(auth.signInCalls, 0, reason: 'الدخول بعد الدوسة بس');

      await tester.tap(find.text('كمّل بحساب تجريبي'));
      await settle(tester);
      expect(auth.signInCalls, 1);
      expect(find.text('عندي كود'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('اربط'));
      await settle(tester);
      expect(care.redeemed, ['123456']);
      expect(sink.permissionRequests, 1, reason: 'من غير الإذن تنبيه ابنه ما بيظهرش');

      await tester.tap(find.text('افتح المتابعة'));
      await settle(tester);

      expect(find.byType(CaregiverShell), findsOneWidget);
      expect(find.text('متابعة الحاج أحمد'), findsOneWidget);
      expect(find.byType(EntryScreen), findsNothing);
      expect(find.byType(RoutineOnboardingScreen), findsNothing);
      expect(find.byType(TodayScreen), findsNothing);

      expect(await db.select(db.dayRoutines).get(), isEmpty, reason: 'ولا روتين');
      final patients = await db.select(db.patients).get();
      expect(patients.every((p) => p.sex == null && p.age == null), isTrue,
          reason: 'صف «أنا» الفاضي بتاع الإقلاع بس — ولا مريض اتعرّفنا عليه');
      expect(await db.select(db.medications).get(), isEmpty);
    });

    screenTest('بعد الربط، أي فتحة جاية → المتابعة على طول، وشاشة البداية ما بتظهرش تاني',
        (tester) async {
      useCloud();
      auth.user = const FakkarniUser(id: 'son', isAnonymous: true);
      await tallView(tester);
      await pumpRoot(tester);

      expect(find.byType(CaregiverShell), findsOneWidget);
      expect(find.byType(EntryScreen), findsNothing);
      expect(auth.signInCalls, 0, reason: 'الجلسة اتقرت محفوظة — مش دخول');
    });

    screenTest('جلسة من غير مريض مربوط (ربط فشل وقفل) → شاشة البداية تاني، مش متابعة فاضية',
        (tester) async {
      useCloud();
      auth.user = const FakkarniUser(id: 'son', isAnonymous: true);
      remote.linked = false;
      await tallView(tester);
      await pumpRoot(tester);

      expect(find.byType(EntryScreen), findsOneWidget);
      expect(find.byType(CaregiverShell), findsNothing);
    });

    screenTest('أوفلاين مع جلسة → المتابعة بجملة الأوفلاين، مش شاشة البداية', (tester) async {
      useCloud();
      auth.user = const FakkarniUser(id: 'son', isAnonymous: true);
      remote.offline = true;
      await tallView(tester);
      await pumpRoot(tester);

      expect(find.byType(CaregiverShell), findsOneWidget);
      expect(find.textContaining('مفيش نت'), findsOneWidget);
    });

    screenTest('الجهاز فيه مريض → مسار المريض حتى لو فيه جلسة (الأب اللي ربط ابنه)', (tester) async {
      useCloud();
      auth.user = const FakkarniUser(id: 'father', isAnonymous: true);
      await routines.saveRoutine(services.patientId, normalDay);
      await pumpRoot(tester);

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.byType(CaregiverShell), findsNothing);
    });
  });

  screenTest('بروتين → «يومك»', (tester) async {
    await routines.saveRoutine(services.patientId, normalDay);
    await pumpRoot(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  screenTest('دوسة على الإشعار والتطبيق مفتوح → شاشة التذكير فوق «يومك»',
      (tester) async {
    await routines.saveRoutine(services.patientId, normalDay);
    await pumpRoot(tester);

    tap.value = payloadFor(['1']);
    await settle(tester);

    expect(find.byType(ReminderScreen), findsOneWidget);
    // اتقرت واتصفّرت — ما تتفتحش تاني لو الشجرة اتبنت من جديد
    expect(tap.value, isNull);
  });

  screenTest('التطبيق اتفتح من الإشعار قبل ما الروتين يوصل → بتستنى وبتفتح',
      (tester) async {
    await routines.saveRoutine(services.patientId, normalDay);
    // الـpayload موجود من قبل أول build — زي getNotificationAppLaunchDetails
    tap.value = payloadFor(['1']);
    await pumpRoot(tester);

    expect(find.byType(ReminderScreen), findsOneWidget);
    expect(tap.value, isNull);
  });

  screenTest('payload مش بتاعنا → بيتصفّر ومفيش شاشة بتتفتح', (tester) async {
    await routines.saveRoutine(services.patientId, normalDay);
    await pumpRoot(tester);

    tap.value = 'حاجة قديمة';
    await settle(tester);

    expect(find.byType(ReminderScreen), findsNothing);
    expect(tap.value, isNull);
  });
}

/// جلسة بتتعمل من الزرار بس — [user] بيتحط في الاختبار كجلسة محفوظة.
class _SessionAuth implements AuthService {
  int signInCalls = 0;
  FakkarniUser? user;
  final _states = StreamController<FakkarniUser?>.broadcast();

  @override
  Stream<FakkarniUser?> get authState => _states.stream;
  @override
  FakkarniUser? get currentUser => user;
  @override
  Future<void> signInToLink() async {
    signInCalls++;
    user = const FakkarniUser(id: 'son', isAnonymous: true);
    _states.add(user);
  }

  @override
  Future<void> signOut() async {
    user = null;
    _states.add(null);
  }
}

class _FakeCare implements CareCircleService {
  final redeemed = <String>[];

  @override
  Future<String> redeemInvite(String code) async {
    redeemed.add(code);
    return 'الحاج أحمد';
  }

  @override
  Future<InviteCode> createInvite(String patientUuid) => throw UnimplementedError();
  @override
  Future<void> upsertPatient({required String uuid, required String name}) async {}
}

class _FakeRemote implements CaregiverRemote {
  bool linked = true;
  bool offline = false;
  static const _patient = CaregiverPatient(uuid: 'p-1', name: 'الحاج أحمد');

  @override
  Future<CaregiverPatient?> linkedPatient() async => linked ? _patient : null;

  @override
  Future<CaregiverSnapshot?> snapshot() async {
    if (offline) throw const CareCircleException(CareCircleFailure.offline);
    if (!linked) return null;
    return const CaregiverSnapshot(patient: _patient, medications: [], events: []);
  }
}

class _CountingSink extends SilentSink {
  int permissionRequests = 0;
  @override
  Future<void> ensurePermissions() async => permissionRequests++;
}

/// بيعدّ نداءات الدخول — الحارس بيثبت إنها صفر عند الفتح.
class _CountingAuth implements AuthService {
  int signInCalls = 0;

  @override
  Stream<FakkarniUser?> get authState => Stream.value(null);
  @override
  FakkarniUser? get currentUser => null;
  @override
  Future<void> signInToLink() async => signInCalls++;
  @override
  Future<void> signOut() async {}
}
