import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/features/onboarding/routine_onboarding_screen.dart';
import 'package:fakkarni/features/onboarding/time_wheel.dart';

import '../scan/scan_test_support.dart' show expectNoRedAndMinSize;
import '../../support/seeded_clock.dart';

/// النص المطلوب بالظبط وبالترتيب.
const expectedQuestions = [
  'بتصحى الساعة كام؟',
  'بتفطر الساعة كام؟',
  'بتتغدى الساعة كام؟',
  'بتتعشى الساعة كام؟',
  'بتنام الساعة كام؟',
];

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

void main() {
  late AppDatabase db;
  late RoutineRepository routines;
  late AppServices services;
  var finished = false;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    final medications = MedicationRepository(db, clock: seededLongAgo);
    final patientId = await routines.ensurePatient();
    finished = false;
    services = AppServices(
      db: db,
      routines: routines,
      medications: medications,
      events: DoseEventRepository(db),
      scheduler: ReminderScheduler(
        routines: routines,
        medications: medications,
        events: DoseEventRepository(db),
        patientId: patientId,
        sink: SilentSink(),
      ),
      patientId: patientId,
    );
  });

  tearDown(() => db.close());

  Future<void> pumpOnboarding(WidgetTester tester, {bool askProfile = false}) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: RoutineOnboardingScreen(
              onDone: () => finished = true,
              askProfile: askProfile,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('الخمس أسئلة بتظهر بالترتيب وبالنص المكتوب بالظبط',
      (tester) async {
    await pumpOnboarding(tester);

    for (final question in expectedQuestions) {
      expect(find.text(question), findsOneWidget, reason: question);
      await tapAndSettle(tester, 'تمام');
    }

    expect(finished, isTrue);
  });

  testWidgets('كل شاشة فيها «مش متأكد»', (tester) async {
    await pumpOnboarding(tester);

    for (var i = 0; i < expectedQuestions.length; i++) {
      expect(find.text('مش متأكد'), findsOneWidget);
      await tapAndSettle(tester, 'مش متأكد');
    }
  });

  testWidgets('«مش متأكد» في كل سؤال بيدي الروتين الافتراضي', (tester) async {
    await pumpOnboarding(tester);

    for (var i = 0; i < expectedQuestions.length; i++) {
      await tapAndSettle(tester, 'مش متأكد');
    }

    final saved = await routines.getRoutine(services.patientId);
    expect(saved!.wake, DayRoutine.fallback.wake);
    expect(saved.breakfast, DayRoutine.fallback.breakfast);
    expect(saved.lunch, DayRoutine.fallback.lunch);
    expect(saved.dinner, DayRoutine.fallback.dinner);
    expect(saved.sleep, DayRoutine.fallback.sleep);
  });

  testWidgets('الشيب بيغيّر الوقت المعروض وبيتحفظ', (tester) async {
    await pumpOnboarding(tester);

    // أول سؤال: الاقتراحات ٦:٠٠ / ٦:٣٠ / ٧:٠٠ والافتراضي المختار ٦:٣٠
    expect(find.text('٦:٠٠ ص'), findsOneWidget);
    await tapAndSettle(tester, '٦:٠٠ ص');
    // الوقت الكبير فوق العجلة بقى ٦:٠٠ كمان → بقى ظاهر مرتين
    expect(find.text('٦:٠٠ ص'), findsNWidgets(2));

    for (var i = 0; i < expectedQuestions.length; i++) {
      await tapAndSettle(tester, i == 0 ? 'تمام' : 'مش متأكد');
    }

    final saved = await routines.getRoutine(services.patientId);
    expect(saved!.wake, MinuteOfDay.hm(6));
  });

  testWidgets('الاقتراحات فوق العجلة، مش تحتها', (tester) async {
    await pumpOnboarding(tester);

    final chip = tester.getCenter(find.text('٦:٠٠ ص'));
    final wheel = tester.getCenter(find.byType(TimeWheel));
    expect(chip.dy, lessThan(wheel.dy), reason: 'أغلب الناس بتاخد اقتراح');
  });

  testWidgets('كل زرار أساسي ٦٤ وكل نص مش أقل من ١٧', (tester) async {
    await pumpOnboarding(tester);

    final button = tester.getSize(find.byType(FilledButton));
    expect(button.height, greaterThanOrEqualTo(F.primaryButtonHeight));

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size != null) {
        expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
      }
    }
  });

  testWidgets('مفيش سحب بالإيد بين الأسئلة', (tester) async {
    await pumpOnboarding(tester);

    await tester.drag(find.text('بتصحى الساعة كام؟'), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('بتصحى الساعة كام؟'), findsOneWidget);
  });

  testWidgets('خمس نقط تقدّم: الحالية ذهبية والباقي line، وبتتحرك مع الأسئلة', (tester) async {
    await pumpOnboarding(tester);

    Color dot(int i) =>
        (tester.widget<Container>(find.byKey(ValueKey('dot-$i'))).decoration! as BoxDecoration).color!;
    expect(dot(1), F.gold);
    for (var i = 2; i <= 5; i++) {
      expect(dot(i), F.line, reason: 'نقطة $i');
    }
    // مفيش عدّاد نصّي ولا شريط تقدّم قديم
    expect(find.textContaining('سؤال ١ من'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tapAndSettle(tester, 'تمام');
    expect(dot(1), F.line);
    expect(dot(2), F.gold);
  });

  testWidgets('«مش متأكد» بتدي افتراضيات README: ٦:٣٠ — ٧:٣٠ — ٢:٠٠ — ٨:٠٠ — ١١:٣٠', (tester) async {
    await pumpOnboarding(tester);
    for (var i = 0; i < expectedQuestions.length; i++) {
      await tapAndSettle(tester, 'مش متأكد');
    }
    final saved = (await routines.getRoutine(services.patientId))!;
    expect(saved.wake, MinuteOfDay.hm(6, 30));
    expect(saved.breakfast, MinuteOfDay.hm(7, 30));
    expect(saved.lunch, MinuteOfDay.hm(14));
    expect(saved.dinner, MinuteOfDay.hm(20));
    expect(saved.sleep, MinuteOfDay.hm(23, 30));
  });

  testWidgets('الاقتراح النصّاني هو الافتراضي، وبيبان ذهبي من غير ما يدوس', (tester) async {
    await pumpOnboarding(tester);
    final mid = find.text('٦:٣٠ ص').first;
    final material = tester.widget<Material>(
      find.ancestor(of: mid, matching: find.byType(Material)).first,
    );
    expect(material.color, F.gold);
  });

  group('«نتعرّف عليك» قبل الأسئلة (المخطط 21)', () {
    Future<void> pumpTall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpOnboarding(tester, askProfile: true);
    }

    testWidgets('أول مرة: الاسم والجنس والسن الأول، و«كمّل» مقفولة لحد اسم وجنس', (tester) async {
      await pumpTall(tester);

      expect(find.text('نتعرّف عليك'), findsOneWidget);
      expect(find.text('اسمك إيه؟'), findsOneWidget);
      expect(find.text('راجل ولا ست؟'), findsOneWidget);
      expect(find.text(expectedQuestions.first), findsNothing, reason: 'الأسئلة بعدين');

      FilledButton next() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'كمّل'));
      expect(next().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'الحاج أحمد');
      await tester.pumpAndSettle();
      expect(next().onPressed, isNull, reason: 'لسه الجنس');
      await tapAndSettle(tester, 'راجل');
      expect(next().onPressed, isNotNull);
      expectNoRedAndMinSize(tester);
    });

    testWidgets('ست → الأسئلة بالمؤنث، والجنس والاسم اتحفظوا، والسن null لو ما اختارتش', (tester) async {
      await pumpTall(tester);

      await tester.enterText(find.byType(TextField), 'الحاجة فاطمة');
      await tapAndSettle(tester, 'ست');
      // الكلام على الشاشة نفسها بيتبع الجنس فوراً
      expect(find.textContaining('بتفطري الساعة كام؟'), findsOneWidget);
      await tapAndSettle(tester, 'كمّل');

      expect(find.text('بتصحي الساعة كام؟'), findsOneWidget);
      expect(find.text('مش متأكدة'), findsOneWidget);
      expect(find.text('بتصحى الساعة كام؟'), findsNothing);

      final row = (await services.routines.getPatient(services.patientId))!;
      expect(row.name, 'الحاجة فاطمة');
      expect(row.sex, Sex.f);
      expect(row.age, isNull, reason: 'مش بنكتب سن ما اتقالش');
    });

    testWidgets('راجل وسن من الشريحة → الأسئلة بالمذكر والسن اتحفظ', (tester) async {
      await pumpTall(tester);

      await tester.enterText(find.byType(TextField), 'الحاج أحمد');
      await tapAndSettle(tester, 'راجل');
      await tapAndSettle(tester, '٦٥–٧٤');
      await tapAndSettle(tester, 'أكتر');
      await tapAndSettle(tester, 'كمّل');

      expect(find.text('بتصحى الساعة كام؟'), findsOneWidget);
      expect(find.text('مش متأكد'), findsOneWidget);
      final row = (await services.routines.getPatient(services.patientId))!;
      expect(row.sex, Sex.m);
      expect(row.age, 71);
    });

    testWidgets('الجنس متسجّل قبل كده → الأسئلة على طول من غير «نتعرّف عليك»', (tester) async {
      await services.routines.saveProfile(services.patientId, name: 'الحاج أحمد', sex: Sex.m);
      await pumpTall(tester);
      expect(find.text('نتعرّف عليك'), findsNothing);
      expect(find.text(expectedQuestions.first), findsOneWidget);
    });
  });
}
