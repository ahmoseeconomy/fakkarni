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
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/features/onboarding/routine_onboarding_screen.dart';
import 'package:fakkarni/features/reminder/reminder_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

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
    meds = MedicationRepository(db);
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

  screenTest('من غير روتين → الأسئلة الأول', (tester) async {
    await pumpRoot(tester);
    expect(find.byType(RoutineOnboardingScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
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
