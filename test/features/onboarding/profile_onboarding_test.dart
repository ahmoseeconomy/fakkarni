import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/patient_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/features/onboarding/profile_page.dart';
import 'package:fakkarni/features/onboarding/profile_onboarding_screen.dart';
import 'package:fakkarni/core/widgets/f_wheels.dart';

import '../scan/scan_test_support.dart' show expectNoRedAndMinSize;
import '../../support/seeded_clock.dart';

/// «نتعرّف عليك» بعد ما الروتين وسؤال الجنس اتشالوا (٢٧ سبتمبر ٢٠٢٦): الاسم
/// ← السن (اختياري) ← «يومك». مفيش أسئلة عن الصحيان والأكل والنوم، ومفيش
/// «راجل ولا ست؟».
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

/// الخطوط الحقيقية — من غيرها flutter_test بيرسم كل حرف مربّع بعرض الخط
/// كله، وقياس iPhone SE تحت بيطلع أطول من الموبايل بكتير.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }

  await load('IBM Plex Sans Arabic', [
    'IBMPlexSansArabic-Regular.ttf',
    'IBMPlexSansArabic-Medium.ttf',
    'IBMPlexSansArabic-SemiBold.ttf',
    'IBMPlexSansArabic-Bold.ttf',
  ]);
  await load('Alexandria', ['Alexandria-Medium.ttf', 'Alexandria-Bold.ttf']);
}

/// كلمات الروتين والجنس اللي ما ينفعش تظهر على الشاشة دي تاني.
const bannedOnboardingWords = ['بتصحى', 'بتفطر', 'بتتغدى', 'بتتعشى', 'بتنام', 'راجل ولا ست', 'مواعيد يومك', 'مش دلوقتي'];

void main() {
  setUpAll(_loadFonts);
  late AppDatabase db;
  late PatientRepository patients;
  late AppServices services;
  var finished = false;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    patients = PatientRepository(db);
    final medications = MedicationRepository(db, clock: seededLongAgo);
    final patientId = await patients.ensurePatient();
    finished = false;
    services = AppServices(
      db: db,
      patients: patients,
      medications: medications,
      events: DoseEventRepository(db),
      scheduler: ReminderScheduler(
        medications: medications,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: SilentSink(),
      ),
      patientId: patientId,
    );
  });

  tearDown(() => db.close());

  Future<void> pumpOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ProfileOnboardingScreen(onDone: () => finished = true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpTall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOnboarding(tester);
  }

  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  FilledButton next(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'كمّل'));

  /// صفحة الاسم ← السن، بـ«كمّل» بينهم.
  Future<void> toAge(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, 'كمّل');
  }

  /// بيحرّك البكرة [items] خانة: بالسالب لفوق (سن أكبر)، بالموجب لتحت.
  Future<void> spin(WidgetTester tester, int items) async {
    await tester.drag(find.byType(CupertinoPicker), Offset(0, -AgeWheel.itemExtent * items));
    await tester.pumpAndSettle();
  }

  String hint(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('age-hint'))).data!;

  testWidgets('صفحتين بس: الاسم ← السن، و«كمّل» مقفولة لحد ما يكتب اسمه', (tester) async {
    await pumpTall(tester);

    expect(find.text('نتعرّف عليك'), findsOneWidget);
    expect(find.text('اسمك إيه؟'), findsOneWidget);
    expect(find.byKey(const ValueKey('age-wheel')), findsNothing, reason: 'السن صفحة لوحده');
    expect(next(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'الحاج أحمد');
    await tester.pumpAndSettle();
    expect(next(tester).onPressed, isNotNull);
    await tapAndSettle(tester, 'كمّل');

    expect(find.byKey(const ValueKey('age-wheel')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(next(tester).onPressed, isNotNull, reason: 'السن اختياري');
    expect((await services.patients.getPatient(services.patientId))!.profileDoneAt, isNull,
        reason: 'ولا حاجة بتتحفظ قبل آخر صفحة');
    expect(finished, isFalse);
    expectNoRedAndMinSize(tester);
  });

  testWidgets('مفيش سؤال جنس ولا أسئلة روتين — ولا كلمة منهم على الشاشتين', (tester) async {
    await pumpTall(tester);
    for (final page in ['الاسم', 'السن']) {
      for (final w in bannedOnboardingWords) {
        expect(find.textContaining(w), findsNothing, reason: '$w على صفحة $page');
      }
      expect(find.byKey(const ValueKey('sex-m')), findsNothing);
      expect(find.byKey(const ValueKey('sex-f')), findsNothing);
      expect(find.byType(FTimeWheel), findsNothing, reason: 'مفيش بكرة ساعة في البداية');
      if (page == 'الاسم') await toAge(tester, 'الحاج أحمد');
    }
    expect(ProfilePage.steps, 2);
  });

  testWidgets('«كمّل» على السن بيحفظ الاسم وبيعلّم إن فيه مريض وبيخلّص — السن null لو ما اختارش', (tester) async {
    await pumpTall(tester);
    await toAge(tester, 'الحاجة فاطمة');
    await tapAndSettle(tester, 'كمّل');

    final row = (await services.patients.getPatient(services.patientId))!;
    expect(row.name, 'الحاجة فاطمة');
    expect(row.profileDoneAt, isNotNull, reason: '«فيه مريض على الموبايل ده»');
    expect(row.age, isNull, reason: 'مش بنكتب سن ما اتقالش');
    expect(finished, isTrue);
    // (البث `watchHasPatient` بيتقرا من الصف ده — `profileDoneAt` — ومتختبر في اختبار المستودع)
  });

  testWidgets('«رجوع» بيرجع صفحة، والمكتوب بيفضل زي ما هو', (tester) async {
    await pumpTall(tester);
    expect(find.byKey(const ValueKey('onboarding-back')), findsNothing, reason: 'أول صفحة ومفيش شاشة قبلها هنا');
    await toAge(tester, 'الحاج أحمد');

    await tester.tap(find.byKey(const ValueKey('onboarding-back')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'الحاج أحمد'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-back')), findsNothing);
  });

  testWidgets('حرّك البكرة → السن اللي وقف عنده اتحفظ', (tester) async {
    await pumpTall(tester);
    await toAge(tester, 'الحاج أحمد');
    await spin(tester, 5); // ٦٠ → ٦٥
    expect(hint(tester), 'سنّك ٦٥ سنة');
    await tapAndSettle(tester, 'كمّل');

    final row = (await services.patients.getPatient(services.patientId))!;
    expect(row.age, 65);
    expect(finished, isTrue);
  });

  testWidgets('البكرة واقفة على ٦٠ ومفيش حاجة بتتكتب لحد ما تتحرّك', (tester) async {
    await pumpTall(tester);
    await toAge(tester, 'الحاج أحمد');
    expect(find.byKey(const ValueKey('age-wheel')), findsOneWidget);
    expect(hint(tester), AgeWheel.hint);
    expect(find.textContaining('سنّك ٦٠'), findsNothing);
    expect(AgeWheel.minAge, 18, reason: 'مريض بأدوية مزمنة ممكن يكون عنده ٢٠');
    expect(AgeWheel.maxAge, 110);

    await tapAndSettle(tester, 'كمّل');
    final row = (await services.patients.getPatient(services.patientId))!;
    expect(row.age, isNull, reason: 'البكرة واقفة على ٦٠ مش معناه إنه قال ٦٠');
  });

  testWidgets('سن صغير بيتحفظ زي ما هو — مفيش أرضية ٦٠', (tester) async {
    await pumpTall(tester);
    await toAge(tester, 'محمد');
    await spin(tester, -30); // ٦٠ → ٣٠
    expect(hint(tester), 'سنّك ٣٠ سنة');
    await tapAndSettle(tester, 'كمّل');
    final row = (await services.patients.getPatient(services.patientId))!;
    expect(row.age, 30);
  });

  testWidgets('«مش عايز أقول» حتى بعد ما لفّ البكرة: السن null وبيخلّص على طول — من غير «كمّل»', (tester) async {
    await pumpTall(tester);
    await toAge(tester, 'الحاج أحمد');
    await spin(tester, 5);
    expect(hint(tester), 'سنّك ٦٥ سنة');

    await tapAndSettle(tester, 'مش عايز أقول');
    expect(finished, isTrue, reason: 'آخر سؤال — التخطّي هو الحفظ');
    final row = (await services.patients.getPatient(services.patientId))!;
    expect(row.age, isNull);
    expect(row.profileDoneAt, isNotNull);
  });

  testWidgets('نقطتين تقدّم: الحالية ذهبية والتانية line، وبتتحرك مع الصفحة', (tester) async {
    await pumpTall(tester);
    Color dot(int i) =>
        (tester.widget<Container>(find.byKey(ValueKey('dot-$i'))).decoration! as BoxDecoration).color!;
    expect(dot(1), F.gold);
    expect(dot(2), F.line);
    expect(find.byKey(const ValueKey('dot-3')), findsNothing);
    await toAge(tester, 'الحاج أحمد');
    expect(dot(1), F.line);
    expect(dot(2), F.gold);
  });

  testWidgets('على iPhone SE: كل صفحة و«كمّل» بتاعتها ظاهرين من غير لفّ ومن غير فيض', (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOnboarding(tester);

    void fits(String page) {
      expect(tester.takeException(), isNull, reason: 'فيض — $page');
      final button = tester.getRect(find.widgetWithText(FilledButton, 'كمّل'));
      expect(button.bottom, lessThanOrEqualTo(667), reason: page);
      expect(button.top, greaterThanOrEqualTo(0), reason: page);
      expectNoRedAndMinSize(tester);
    }

    fits('الاسم');
    await tester.enterText(find.byType(TextField), 'الحاج أحمد');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapAndSettle(tester, 'كمّل');
    fits('السن');
    final button = tester.getRect(find.widgetWithText(FilledButton, 'كمّل'));
    final wheel = tester.getRect(find.byKey(const ValueKey('age-wheel')));
    expect(wheel.height, AgeWheel.wheelHeight);
    final clear = tester.getRect(find.text('مش عايز أقول'));
    expect(clear.bottom, lessThanOrEqualTo(button.top),
        reason: 'كتلة السن كلها فوق «كمّل» من غير لفّ: ${wheel.bottom} / ${clear.bottom} / ${button.top}');
  });

  testWidgets('كل زرار أساسي ٦٤ وكل نص مش أقل من ١٧', (tester) async {
    await pumpTall(tester);
    final button = tester.getSize(find.byType(FilledButton));
    expect(button.height, greaterThanOrEqualTo(F.primaryButtonHeight));
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size != null) {
        expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
      }
    }
  });
}
