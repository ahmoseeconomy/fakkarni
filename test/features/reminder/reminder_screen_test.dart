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
import 'package:fakkarni/core/widgets/patient_voice.dart';
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/schedule_engine.dart';
import 'package:fakkarni/features/reminder/reminder_screen.dart';

import '../scan/scan_test_support.dart' show expectNoRedAndMinSize;
import '../../support/seeded_clock.dart';

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
    meds = MedicationRepository(db, clock: seededLongAgo);
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

    expect(find.text('تنبيه · المرحلة ٢'), findsOneWidget);
    expect(find.text('Antodine'), findsOneWidget);
    expect(find.textContaining('قرص واحد'), findsOneWidget);
    expect(find.textContaining('الغدا'), findsOneWidget);
    expect(find.textContaining('٢:٠٠ م'), findsOneWidget);
  });

  screenTest('اتأخر ربع ساعة → المرحلة ٢، «مرّت ١٥ دقيقة»، الدرجة التانية أمبر — من غير أحمر ولا لوم', (tester) async {
    final ids = await seed(['Antodine']);
    await pumpReminder(tester, ids);

    expect(find.text('مرّت ١٥ دقيقة على موعد الجرعة'), findsOneWidget);
    expect(find.text('تنبيه · المرحلة ٢'), findsOneWidget);
    expect(tester.widget<Text>(find.text('+١٥ د')).style?.color, F.amber);
    expect(tester.widget<Text>(find.text('في الموعد')).style?.color, isNot(F.amber));

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final colour = text.style?.color;
      if (colour == null) continue;
      final isRed = colour.r > 0.6 && colour.g < 0.35 && colour.b < 0.35;
      expect(isRed, isFalse, reason: 'مفيش أحمر: ${text.data}');
    }
  });

  screenTest('لسه في المعاد → «وقت الدوا» والمرحلة ١', (tester) async {
    final ids = await seed(['Antodine']);
    await pumpReminder(tester, ids, now: lunchDose);

    expect(find.text('وقت الدوا'), findsOneWidget);
    expect(find.text('تنبيه · المرحلة ١'), findsOneWidget);
    expect(tester.widget<Text>(find.text('في الموعد')).style?.color, F.amber);
  });

  screenTest('«أخدته» بتسجّل وبتلغي تذكير الخانة والتأجيل بتاعها', (tester) async {
    final ids = await seed(['Antodine', 'Vitamin D']);
    await pumpReminder(tester, ids);

    await tester.tap(find.text('تم التناول ✅'));
    await settle(tester);

    expect(await statesOf(ids), [DoseState.taken, DoseState.taken]);
    // الخانة كلها: التذكير، التأجيل، والدرجتين — القاعدة الخامسة
    expect(
      sink.cancelled,
      [
        notificationIdFor(lunchDose),
        snoozeIdFor(lunchDose),
        escalationIdFor(lunchDose, EscalationRung.first),
        escalationIdFor(lunchDose, EscalationRung.second),
      ],
    );
  });

  screenTest('«تخطّي» بتسجّل تخطّي وبتلغي التذكير — من غير ❌', (tester) async {
    final ids = await seed(['Antodine']);
    await pumpReminder(tester, ids);

    expect(find.textContaining('❌'), findsNothing);
    await tester.tap(find.text('تخطّي'));
    await settle(tester);

    expect(await statesOf(ids), [DoseState.skipped]);
    expect(sink.cancelled, contains(notificationIdFor(lunchDose)));
  });

  screenTest('«تأجيل ١٥ د ⏰» بتجدول تذكير واحد في نطاق التأجيل',
      (tester) async {
    final ids = await seed(['Antodine']);
    final now = DateTime(2026, 8, 31, 14, 15);
    await pumpReminder(tester, ids, now: now);

    await tester.tap(find.text('تأجيل ١٥ د ⏰'));
    await settle(tester);

    final snooze = sink.scheduled.single;
    expect(isSnoozeId(snooze.id), isTrue);
    expect(snooze.id, snoozeIdFor(lunchDose));
    expect(snooze.at, DateTime(2026, 8, 31, 14, 30));
    expect(snooze.body, 'Antodine — قرص واحد');
    expect(decodePayload(snooze.payload)!.scheduleIds, ids);
    // الجرعة لسه معلّقة — التأجيل مش تخطّي
    expect(await statesOf(ids), [DoseState.pending]);
    // التأجيل لـ٢:٣٠ بيسبق درجة ٢:١٥ وبيقع على درجة ٢:٣٠ → الاتنين بيتشالوا،
    // والتذكير الأصلي وتأجيله ما بيتلمسوش
    expect(sink.cancelled, [
      escalationIdFor(lunchDose, EscalationRung.first),
      escalationIdFor(lunchDose, EscalationRung.second),
    ]);
  });

  screenTest('بعد ٦٠ دقيقة → المرحلة ٤ «إشعار لابنك» أمبر، السلّم أربع درجات بس، ومفيش أحمر', (tester) async {
    final ids = await seed(['Antodine']);
    await pumpReminder(tester, ids, now: DateTime(2026, 8, 31, 15, 5));

    expect(find.text('تنبيه · المرحلة ٤'), findsOneWidget);
    expect(find.text('مرّت ٦٠ دقيقة على موعد الجرعة'), findsOneWidget);
    expect(tester.widget<Text>(find.text('+٦٠ د — إشعار لابنك')).style?.color, F.amber);
    expect(ladderSteps.length, 4, reason: 'الدرجة الخامسة مش مبنية');
    expect(find.textContaining('دائرة الرعاية'), findsNothing);
    expect(find.textContaining('+٩٠'), findsNothing);
    // أساسي واحد بس، والسلّم من ثوابت الدومين
    expect(find.byType(FilledButton), findsOneWidget);
    expect(ladderSteps[1].after, EscalationRung.first.delay);
    expect(ladderSteps[3].after, serverGraceWindow, reason: 'الابن بيتبلّغ من السيرفر بعد مهلته هو');
    expect(find.textContaining('قول'), findsNothing, reason: 'مفيش سطر صوت');
    expect(find.textContaining('لا أذكر'), findsNothing);
    expectNoRedAndMinSize(tester);
  });

  screenTest('دواءين في نفس الدقيقة → كارت واحد بالاتنين وأزرار واحدة', (tester) async {
    final ids = await seed(['Antodine', 'Vitamin D']);
    await pumpReminder(tester, ids);

    expect(find.text('Antodine'), findsOneWidget);
    expect(find.text('Vitamin D'), findsOneWidget);
    expect(find.text('تم التناول ✅'), findsOneWidget);

    await tester.tap(find.text('تم التناول ✅'));
    await settle(tester);
    expect(await statesOf(ids), [DoseState.taken, DoseState.taken]);
  });

  screenTest('جرعة اتاخدت خلاص من «يومك» → مفيش أزرار، بس «ارجع ليومك»',
      (tester) async {
    final ids = await seed(['Antodine']);
    await events.markTaken(int.parse(ids.single), aug31);
    await pumpReminder(tester, ids);

    expect(find.text('خدته خلاص'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('تم التناول ✅'), findsNothing);
    expect(find.text('سلّم التصعيد'), findsNothing);
    expect(find.text('ارجع ليومك'), findsOneWidget);
  });

  screenTest('صوت المريضة: «خدتيه خلاص» و«ارجعي ليومك» لما الجنس ست', (tester) async {
    final ids = await seed(['Antodine']);
    await events.markTaken(int.parse(ids.single), aug31);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PatientVoice(
              say: const Say(Sex.f),
              child: ReminderScreen(routineDay: aug31, scheduleIds: ids, now: DateTime(2026, 8, 31, 14, 15)),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('خدتيه خلاص'), findsOneWidget);
    expect(find.text('ارجعي ليومك'), findsOneWidget);
    expect(find.textContaining('أخدتيه'), findsOneWidget);
    expect(find.text('خدته خلاص'), findsNothing);
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

    // أساسي واحد ٦٤، وثانويين ٥٦ جنب بعض — مفيش TextButton باهت
    expect(tester.getSize(find.byType(FilledButton)).height, F.primaryButtonHeight);
    for (final button in find.byType(OutlinedButton).evaluate()) {
      expect(tester.getSize(find.byWidget(button.widget)).height, F.minTapTarget);
    }
    expect(find.byType(OutlinedButton), findsNWidgets(2));
    expect(find.byType(TextButton), findsNothing);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size != null) {
        expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
      }
    }
  });
}
