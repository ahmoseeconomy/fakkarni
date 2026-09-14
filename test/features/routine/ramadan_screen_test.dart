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
import 'package:fakkarni/features/onboarding/time_wheel.dart';
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
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: RamadanScreen(today: aug31),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('مقفول: الحالة واضحة، والمعاينة قلب الشاشة — قبل → بعد لكل دوا والعدّاد صادق',
      (tester) async {
    await meds.addMedication(
      patientId: services.patientId,
      name: 'Eltroxin',
      timing: FixedTiming(MinuteOfDay.hm(6)),
      startDate: aug31,
    );
    await pumpScreen(tester);

    expect(find.text('يومك في رمضان'), findsOneWidget);
    expect(find.textContaining('وضع رمضان مقفول'), findsOneWidget);
    expect(find.text('السحور'), findsOneWidget);
    expect(find.text('الفطار (المغرب)'), findsOneWidget);
    expect(find.text('النوم'), findsOneWidget);
    // قيم القاهرة: سحور ٣:٣٠ · مغرب ٦:٠٠ · نوم ٤:٣٠ (بعد السحور بساعة)
    expect(find.text('٣:٣٠ ص'), findsOneWidget);
    expect(find.text('٦:٠٠ م'), findsOneWidget);
    expect(find.text('٤:٣٠ ص'), findsOneWidget);
    // الثابتة ما بتتعدّش — دوا واحد بس هيتحرك
    expect(find.text('دوا واحد هيتحرك'), findsOneWidget);
    expect(find.textContaining('Eltroxin'), findsOneWidget);
    expect(find.textContaining('ساعة ثابتة، ما بتتحركش'), findsOneWidget);
    // Antodine: قبل الفطار (٧:٣٠) − ٣٠ = ٧:٠٠ ص → قبل المغرب (٦:٠٠) − ٣٠ = ٥:٣٠ م
    expect(find.text('Antodine'), findsOneWidget);
    expect(find.text('٧:٠٠ ص'), findsOneWidget);
    expect(find.text('٥:٣٠ م'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'فعّل وضع رمضان'), findsOneWidget);
    expect(find.byType(Switch), findsNothing, reason: 'الزرار هو الفعل — مفيش مفتاح');
    expectNoRedAndMinSize(tester);
  });

  // ⚠️ القاعدة: ولا حاجة بتتغيّر قبل «فعّل وضع رمضان».
  screenTest('فتح الشاشة وتغيير المغرب وقفلها من غير ضغطة → الجدول زي ما هو بالحرف',
      (tester) async {
    await services.scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 6));
    final before = Map.of(sink.scheduled);
    final routineBefore = await routines.getRoutine(services.patientId);

    await pumpScreen(tester);
    // غيّر الفطار بالعجلة
    await tester.tap(find.text('غيّر').last);
    await settle(tester);
    expect(find.byType(TimeWheel), findsOneWidget);
    await tester.drag(find.byType(TimeWheel), const Offset(0, -60));
    await settle(tester);

    // اقفل الشاشة من غير ما تدوس
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);

    expect(await routines.getRoutine(services.patientId), routineBefore);
    expect(await routines.ramadanTimes(services.patientId), isNull);
    expect(sink.scheduled, before, reason: 'ولا تذكير اتحرك');
  });

  screenTest('«فعّل وضع رمضان» → الروتين اتحرك، البث بعت، والتذكيرات اتبنت على المغرب',
      (tester) async {
    await pumpScreen(tester);
    final emitted = <DayRoutine?>[];
    final sub = routines.watchRoutine(services.patientId).listen(emitted.add);
    addTearDown(sub.cancel);

    await tester.tap(find.text('فعّل وضع رمضان'));
    await settle(tester);

    // «يومك» بيسمع للـstream ده — فهو بيتبني من جديد لوحده
    final saved = await routines.getRoutine(services.patientId);
    expect(saved, ramadanRoutine(normalDay, RamadanTimes.cairoDefaults));
    expect(emitted.last, saved);
    expect(sink.reschedules, greaterThan(0), reason: 'rescheduleAll اتنده');
    expect(sink.scheduled.values.any((n) => n.at.hour == 17 && n.at.minute == 30),
        isTrue, reason: '«قبل الفطار − ٣٠» بقت ٥:٣٠ م');
  });

  screenTest('شغّال: الحالة مكتوبة والزرار «اقفل» — والقفل بيرجّع الأصل بالحرف',
      (tester) async {
    await routines.enterRamadan(services.patientId, RamadanTimes.cairoDefaults);
    await pumpScreen(tester);

    expect(find.textContaining('وضع رمضان شغّال دلوقتي'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'اقفل وضع رمضان'), findsOneWidget);
    expect(find.text('فعّل وضع رمضان'), findsNothing);
    // المعاينة وهو شغّال: الأصل → الساري، مش الساري → نفسه
    expect(find.text('دوا واحد اتحرك'), findsOneWidget);
    expect(find.text('٧:٠٠ ص'), findsOneWidget, reason: 'قبل: من النسخة الأصلية');
    expect(find.text('٥:٣٠ م'), findsOneWidget, reason: 'بعد: الساري');

    await tester.tap(find.text('اقفل وضع رمضان'));
    await settle(tester);

    expect(await routines.getRoutine(services.patientId), normalDay);
    expect(await routines.ramadanTimes(services.patientId), isNull);
  });

  screenTest('تعديل المغرب قبل التفعيل بيتحفظ مع التفعيل — مش قبله', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('غيّر').last); // الفطار (المغرب)
    await settle(tester);
    // خمس دقايق لفوق على العجلة (خطوة ٥)
    await tester.drag(find.byType(TimeWheel), const Offset(0, -56));
    await settle(tester);
    expect(await routines.ramadanTimes(services.patientId), isNull, reason: 'لسه ما اتفعّلش');

    await tester.tap(find.text('فعّل وضع رمضان'));
    await settle(tester);
    final times = await routines.ramadanTimes(services.patientId);
    expect(times, isNotNull);
    expect(times!.iftar, isNot(RamadanTimes.cairoDefaults.iftar), reason: 'الوقت اللي اتغيّر هو اللي اتحفظ');
  });
}
