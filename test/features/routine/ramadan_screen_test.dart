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
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/ramadan.dart';
import 'package:fakkarni/features/routine/ramadan_screen.dart';

import '../scan/scan_test_support.dart' show expectNoRedAndMinSize;

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final aug31 = DateTime(2026, 8, 31);

class RecordingSink implements ReminderSink {
  final Map<int, PlannedNotification> scheduled = {};
  int reschedules = 0;

  @override
  Future<void> schedule(PlannedNotification notification) async {
    reschedules++;
    scheduled[notification.id] = notification;
  }

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();
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
  late RecordingSink sink;
  late AppServices services;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    meds = MedicationRepository(db);
    sink = RecordingSink();
    final patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, normalDay);
    await meds.addMedication(
      patientId: patientId,
      name: 'Antodine',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: aug31,
    );
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
        sink: sink,
      ),
      patientId: patientId,
    );
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: RamadanScreen(),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('مقفول في الأول: المفتاح مقفول والساعتين مستخبيين', (tester) async {
    await pumpScreen(tester);

    expect(find.text('وضع رمضان مقفول'), findsOneWidget);
    expect(find.text('بتفطر الساعة كام؟'), findsNothing);
    expectNoRedAndMinSize(tester);
  });

  screenTest('تشغيل → الساعتين بقيم القاهرة، وحفظ → الروتين اتحرك والتذكيرات اتبنت',
      (tester) async {
    await pumpScreen(tester);
    final emitted = <DayRoutine?>[];
    final sub = routines.watchRoutine(services.patientId).listen(emitted.add);
    addTearDown(sub.cancel);

    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect(find.text('وضع رمضان شغّال'), findsOneWidget);
    expect(find.text('بتفطر الساعة كام؟'), findsOneWidget);
    expect(find.text('بتتسحّر الساعة كام؟'), findsOneWidget);
    expect(find.text('٦:٠٠ م'), findsOneWidget);
    expect(find.text('٣:٣٠ ص'), findsOneWidget);
    expect(find.textContaining('الساعات الثابتة ما بتتحركش'), findsOneWidget);
    expectNoRedAndMinSize(tester);

    await tester.tap(find.text('احفظ'));
    await settle(tester);

    // «يومك» بيسمع للـstream ده — فهو بيتبني من جديد لوحده
    final saved = await routines.getRoutine(services.patientId);
    expect(saved, ramadanRoutine(normalDay, RamadanTimes.cairoDefaults));
    expect(emitted.last, saved);
    expect(sink.reschedules, greaterThan(0), reason: 'rescheduleAll اتنده');
    expect(sink.scheduled.values.any((n) => n.at.hour == 17 && n.at.minute == 30),
        isTrue, reason: '«قبل الفطار − ٣٠» بقت ٥:٣٠ م');
  });

  screenTest('مفتوح ثم قفل من الشاشة → الأصل رجع بالحرف', (tester) async {
    await routines.enterRamadan(services.patientId, RamadanTimes.cairoDefaults);
    await pumpScreen(tester);
    expect(find.text('وضع رمضان شغّال'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await settle(tester);
    await tester.tap(find.text('احفظ'));
    await settle(tester);

    expect(await routines.getRoutine(services.patientId), normalDay);
    expect(await routines.ramadanTimes(services.patientId), isNull);
  });

  screenTest('مقفول وحفظ من غير تغيير → ولا حاجة اتلمست', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('احفظ'));
    await settle(tester);
    expect(await routines.getRoutine(services.patientId), normalDay);
    expect(await routines.ramadanTimes(services.patientId), isNull);
  });
}
