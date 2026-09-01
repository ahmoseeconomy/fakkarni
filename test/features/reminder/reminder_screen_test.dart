import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/dose_state.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';
import 'package:fakkarni/features/reminder/reminder_screen.dart';

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final aug31 = DateTime(2026, 8, 31);

/// قبل الغدا بنص ساعة = ٢:٠٠ م
final lunchDose = DateTime(2026, 8, 31, 14);

class RecordingSink implements ReminderSink {
  final List<int> cancelled = [];
  final List<PlannedNotification> scheduled = [];

  @override
  Future<void> schedule(PlannedNotification notification) async =>
      scheduled.add(notification);
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
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
  late MedicationRepository meds;
  late DoseEventRepository events;
  late AppServices services;
  late RecordingSink sink;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    meds = MedicationRepository(db);
    events = DoseEventRepository(db);
    sink = RecordingSink();
    final patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, normalDay);
    services = AppServices(
      db: db,
      routines: routines,
      medications: meds,
      events: events,
      scheduler: ReminderScheduler(
        routines: routines,
        medications: meds,
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

  /// بيضيف الأدوية، وبينزّل أحداث اليوم زي ما «يومك» بتعمل، وبيرجّع أرقام
  /// الجداول اللي في خانة الغدا — نفس اللي بيبقى في الـpayload.
  Future<List<String>> seed(List<String> names) async {
    for (final name in names) {
      await meds.addMedication(
        patientId: services.patientId,
        name: name,
        timing: AnchorTiming(DayAnchor.lunch, -30),
        startDate: aug31,
        amountLabel: 'قرص واحد',
      );
    }
    final schedules = await meds.activeSchedules(services.patientId);
    final reminders = ScheduleEngine(normalDay).remindersForDay(schedules, aug31);
    await events.materializeDay(aug31, reminders);
    return [for (final s in schedules) s.id];
  }

  Future<void> pumpReminder(
    WidgetTester tester,
    List<String> ids, {
    DateTime? now,
  }) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ReminderScreen(
              routineDay: aug31,
              scheduleIds: ids,
              now: now ?? DateTime(2026, 8, 31, 14, 15),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<List<DoseState>> statesOf(List<String> ids) async {
    final rows = await db.select(db.doseEvents).get();
    return [
      for (final id in ids)
        rows.firstWhere((r) => r.doseScheduleId.toString() == id).state,
    ];
  }

  screenTest('الدوا والجرعة والقاعدة والساعة على الكارت', (tester) async {
    final ids = await seed(['Antodine']);
    await pumpReminder(tester, ids);

    expect(find.text('تذكير'), findsOneWidget);
    expect(find.text('Antodine'), findsOneWidget);
    expect(find.textContaining('قرص واحد'), findsOneWidget);
    expect(find.textContaining('الغدا'), findsOneWidget);
    expect(find.textContaining('٢:٠٠ م'), findsOneWidget);
  });

  screenTest('اتأخر ربع ساعة → «فات معاده» من غير أحمر ولا لوم', (tester) async {
    final ids = await seed(['Antodine']);
    await pumpReminder(tester, ids);

    expect(find.text('فات معاده بـ١٥ دقيقة'), findsOneWidget);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final colour = text.style?.color;
      if (colour == null) continue;
      final isRed = colour.r > 0.6 && colour.g < 0.35 && colour.b < 0.35;
      expect(isRed, isFalse, reason: 'مفيش أحمر: ${text.data}');
    }
  });

  screenTest('لسه في المعاد → «وقت الدوا»', (tester) async {
    final ids = await seed(['Antodine']);
    await pumpReminder(tester, ids, now: lunchDose);

    expect(find.text('وقت الدوا'), findsOneWidget);
  });

  screenTest('«أخدته» بتسجّل وبتلغي تذكير الخانة والتأجيل بتاعها', (tester) async {
    final ids = await seed(['Antodine', 'Vitamin D']);
    await pumpReminder(tester, ids);

    await tester.tap(find.text('أخدته'));
    await settle(tester);

    expect(await statesOf(ids), [DoseState.taken, DoseState.taken]);
    expect(
      sink.cancelled,
      [notificationIdFor(lunchDose), snoozeIdFor(lunchDose)],
    );
  });

  screenTest('«مش هاخده دلوقتي» بتسجّل تخطّي وبتلغي التذكير', (tester) async {
    final ids = await seed(['Antodine']);
    await pumpReminder(tester, ids);

    await tester.tap(find.text('مش هاخده دلوقتي'));
    await settle(tester);

    expect(await statesOf(ids), [DoseState.skipped]);
    expect(sink.cancelled, contains(notificationIdFor(lunchDose)));
  });

  screenTest('«فكّرني بعد ربع ساعة» بتجدول تذكير واحد في نطاق التأجيل',
      (tester) async {
    final ids = await seed(['Antodine']);
    final now = DateTime(2026, 8, 31, 14, 15);
    await pumpReminder(tester, ids, now: now);

    await tester.tap(find.text('فكّرني بعد ربع ساعة'));
    await settle(tester);

    final snooze = sink.scheduled.single;
    expect(isSnoozeId(snooze.id), isTrue);
    expect(snooze.id, snoozeIdFor(lunchDose));
    expect(snooze.at, DateTime(2026, 8, 31, 14, 30));
    expect(snooze.body, 'Antodine — قرص واحد');
    expect(decodePayload(snooze.payload)!.scheduleIds, ids);
    // الجرعة لسه معلّقة — التأجيل مش تخطّي
    expect(await statesOf(ids), [DoseState.pending]);
    expect(sink.cancelled, isEmpty);
  });

  screenTest('جرعة اتاخدت خلاص من «يومك» → مفيش أزرار، بس «ارجع ليومك»',
      (tester) async {
    final ids = await seed(['Antodine']);
    await events.markTaken(int.parse(ids.single), aug31);
    await pumpReminder(tester, ids);

    expect(find.text('خدته خلاص'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('أخدته'), findsNothing);
    expect(find.text('ارجع ليومك'), findsOneWidget);
  });

  screenTest('إشعار لجرعة اتشالت من اليوم → رسالة هادية بدل شاشة فاضية',
      (tester) async {
    await pumpReminder(tester, ['999']);

    expect(find.textContaining('مبقتش في يومك'), findsOneWidget);
    expect(find.text('ارجع ليومك'), findsOneWidget);
  });

  screenTest('كل زرار ٦٤ أو ٥٦ وكل نص مش أقل من ١٧', (tester) async {
    final ids = await seed(['Antodine']);
    await pumpReminder(tester, ids);

    expect(tester.getSize(find.byType(FilledButton)).height, F.primaryButtonHeight);
    expect(tester.getSize(find.byType(OutlinedButton)).height, F.primaryButtonHeight);
    expect(tester.getSize(find.byType(TextButton)).height, F.minTapTarget);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size != null) {
        expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
      }
    }
  });
}
