// **الحارس اللي كان هيمسك باج الجولة اللي فاتت.**
//
// `9a0a5a0` بنت شاشة الأسئلة الأربعة وبنت `SupabaseCaregiverPreferences`،
// وما وصّلتش ولا واحدة فيهم بالتطبيق: الشاشة كان بينده عليها ملف اختبارها
// **وبس**، والخدمة عمرها ما اتبنت في `lib/`. الهجرة اتطبّقت واتأكّدت،
// و`caregiver_preferences` فضل صفر صف — لأن الابن عمره ما شاف السؤال.
//
// الاختبار ده بيبدأ من **جذر التطبيق الحقيقي** (`AppRoot`) لابن مربوط
// مالوش صف تفضيلات، وبيقع لو الأسئلة ما ظهرتش. ملف اختبار للشاشة لوحدها
// كان أخضر طول الوقت وهي مش موصّلة بحاجة — وده الفرق بين «الشاشة شغّالة»
// و«الشاشة موجودة في التطبيق».
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/root.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/auth/auth_service.dart';
import 'package:fakkarni/data/care/caregiver_preferences.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/domain/care/follower_profile.dart';
import 'package:fakkarni/features/care/onboarding/caregiver_onboarding_screen.dart';
import 'package:fakkarni/features/care/onboarding/onboarding_gate.dart';

import 'root_test.dart' show SilentSink;

const _patient = CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد');

class _LinkedAuth implements AuthService {
  @override
  Stream<FakkarniUser?> get authState => const Stream.empty();
  @override
  FakkarniUser? get currentUser => const FakkarniUser(id: 'son', isAnonymous: true);
  @override
  Future<void> signInToLink() async {}
  @override
  Future<void> signOut() async {}
}

class _LinkedRemote implements CaregiverRemote {
  @override
  Future<CaregiverPatient?> linkedPatient() async => _patient;
  @override
  Future<CaregiverSnapshot?> snapshot() async => const CaregiverSnapshot(
        patient: _patient,
        medications: [],
        events: [],
      );
}

class _Prefs implements CaregiverPreferencesService {
  CaregiverPreferences stored = const CaregiverPreferences();
  bool loadThrows = false;
  bool saveThrows = false;
  int loads = 0;
  final List<CaregiverPreferences> saved = [];

  @override
  Future<CaregiverPreferences> load(String patientUuid) async {
    loads++;
    if (loadThrows) throw StateError('offline');
    return stored;
  }

  @override
  Future<void> save(String patientUuid, CaregiverPreferences preferences) async {
    if (saveThrows) throw StateError('offline');
    saved.add(preferences);
    stored = preferences;
  }

  @override
  Future<List<FollowerProfile>> followers(String patientUuid) async => [?stored.profile];
}

void main() {
  late AppDatabase db;
  late AppServices services;
  late _Prefs prefs;

  Future<void> build({Map<String, Object> seen = const {}}) async {
    SharedPreferences.setMockInitialValues(seen);
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
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
      auth: _LinkedAuth(),
      caregiver: _LinkedRemote(),
      caregiverPreferences: prefs,
    );
  }

  setUp(() => prefs = _Prefs());
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  /// **من الجذر الحقيقي** — مش من الشاشة على طول.
  Future<void> pumpRoot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

  void screenTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    });
  }

  group('الوصول من جذر التطبيق', () {
    screenTest('**ابن مربوط مالوش صف → الأسئلة بتظهر**', (tester) async {
      await build();
      await pumpRoot(tester);

      expect(find.byType(CaregiverOnboardingScreen), findsOneWidget,
          reason: 'الشاشة مش موصّلة بالتطبيق — نفس باج 9a0a5a0');
      expect(find.text('اسمك وصلتك بيه'), findsOneWidget);
      // **وقبل ما يشوف البيت**: التبويبات مش مرسومة تحتها.
      expect(find.text('متابعة'), findsNothing);
    });

    screenTest('وابن عنده صف باسمه → على طول على المتابعة', (tester) async {
      prefs.stored = const CaregiverPreferences(
          name: 'محمد', relation: FollowerRelation.son);
      await build();
      await pumpRoot(tester);

      expect(find.byType(CaregiverOnboardingScreen), findsNothing);
      expect(find.text('متابعة'), findsWidgets);
    });
  });

  group('مرة واحدة — والتخطّي مش نقّ', () {
    screenTest('تخطّى للآخر → مش بتظهر تاني', (tester) async {
      await build();
      await pumpRoot(tester);
      expect(find.byType(CaregiverOnboardingScreen), findsOneWidget);

      // بيعدّي الأربعة بالتخطّي/كمّل لحد ما تخلص
      for (var i = 0; i < CaregiverOnboardingScreen.steps; i++) {
        final skip = find.byKey(const ValueKey('onboarding-skip'));
        await tester.tap(skip.evaluate().isEmpty
            ? find.byKey(const ValueKey('onboarding-next'))
            : skip);
        await settle(tester);
      }
      expect(find.byType(CaregiverOnboardingScreen), findsNothing);

      // **العلامة المحلية اتسجّلت** — فتحة تانية ما بتسألش
      final seen = await SharedPreferences.getInstance();
      expect(seen.getBool(onboardingSeenKey('p1')), isTrue);
    });

    screenTest('والعلامة المحلية بتمنع السؤال من أول فتحة', (tester) async {
      await build(seen: {onboardingSeenKey('p1'): true});
      await pumpRoot(tester);
      expect(find.byType(CaregiverOnboardingScreen), findsNothing);
      expect(find.text('متابعة'), findsWidgets);
    });
  });

  group('**القراءة لو فشلت: ما نسألش وما نسجّلش**', () {
    screenTest('أوفلاين → مفيش أسئلة، ومفيش علامة اتكتبت', (tester) async {
      prefs.loadThrows = true;
      await build();
      await pumpRoot(tester);

      expect(find.byType(CaregiverOnboardingScreen), findsNothing,
          reason: 'فشل قراية مش إجابة');
      final seen = await SharedPreferences.getInstance();
      expect(seen.getBool(onboardingSeenKey('p1')), isNull,
          reason: 'عطل شبكة لحظي كان هيسكّت السؤال للأبد');
    });
  });

  group('حساب المتابع بيرحّب باسمه', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.text('الإعدادات'));
      await settle(tester);
    }

    screenTest('الاسم والصلة في كارت حسابه', (tester) async {
      prefs.stored = const CaregiverPreferences(
          name: 'محمد', relation: FollowerRelation.son);
      await build();
      await pumpRoot(tester);
      await openSettings(tester);

      expect(find.text('أهلاً يا محمد — ابن الحاج أحمد'), findsOneWidget);
    });

    screenTest('ولسه ما كتبش اسمه → ترحيب من غير اسم مخترع', (tester) async {
      await build(seen: {onboardingSeenKey('p1'): true});
      await pumpRoot(tester);
      await openSettings(tester);

      expect(find.text('أهلاً بيك'), findsOneWidget);
    });

    screenTest('ومدخل «بياناتك وتنبيهاتك» بيفتح نفس الشاشة متعبّية', (tester) async {
      prefs.stored = const CaregiverPreferences(
          name: 'محمد', relation: FollowerRelation.son);
      await build();
      await pumpRoot(tester);
      await openSettings(tester);

      await tester.tap(find.byKey(const ValueKey('care-settings-onboarding')));
      await settle(tester);
      expect(find.byType(CaregiverOnboardingScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'محمد'), findsOneWidget,
          reason: 'شاشة فاضية بتخلّيه يفتكر إن اللي كتبه راح');
    });
  });

  group('الحفظ لو فشل: بيفضل مكانه والعطل باين', () {
    screenTest('مفيش «تمام» والصف ما اتكتبش', (tester) async {
      prefs.saveThrows = true;
      await build();
      await pumpRoot(tester);

      await tester.enterText(find.byKey(const ValueKey('follower-name')), 'محمد');
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await settle(tester);

      expect(find.byKey(const ValueKey('onboarding-error')), findsOneWidget);
      expect(find.text(saveFailedMessage), findsOneWidget);
      // لسه على نفس السؤال — ما عدّاش
      expect(find.text('سؤال ١ من ٤'), findsOneWidget);
      expect(prefs.saved, isEmpty);

      // و«حاول تاني» بتنجح لما الشبكة ترجع
      prefs.saveThrows = false;
      await tester.tap(find.text('حاول تاني'));
      await settle(tester);
      expect(find.text('سؤال ٢ من ٤'), findsOneWidget);
      expect(prefs.saved.single.name, 'محمد');
    });
  });
}
