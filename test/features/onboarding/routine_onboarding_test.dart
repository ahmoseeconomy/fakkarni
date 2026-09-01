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
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/features/onboarding/routine_onboarding_screen.dart';
import 'package:fakkarni/features/onboarding/time_wheel.dart';

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
    final medications = MedicationRepository(db);
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

  Future<void> pumpOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: RoutineOnboardingScreen(onDone: () => finished = true),
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

    // أول سؤال: الاقتراحات ٦:٠٠ / ٧:٠٠ / ٨:٠٠ والافتراضي المختار ٧:٠٠
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
}
