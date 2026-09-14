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
import 'package:fakkarni/features/routine/edit_routine_screen.dart';

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
  final List<int> cancelled = [];

  @override
  Future<void> schedule(PlannedNotification notification) async =>
      scheduled[notification.id] = notification;
  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

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

  Future<void> pumpEdit(WidgetTester tester) async {
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
            child: EditRoutineScreen(routine: normalDay),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('الخمس أسئلة بنفس نصها، والمعاد الحالي معروض', (tester) async {
    await pumpEdit(tester);

    for (final text in [
      'بتصحى الساعة كام؟',
      'بتفطر الساعة كام؟',
      'بتتغدى الساعة كام؟',
      'بتتعشى الساعة كام؟',
      'بتنام الساعة كام؟',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('٧:٣٠ ص'), findsWidgets); // الفطار الحالي
    expect(find.textContaining('الساعات الثابتة بتفضل زي ما هي'), findsOneWidget);
  });

  screenTest('تغيير الفطار بيتحفظ وبيحرّك جرعة المرساة ويسيب الثابتة', (tester) async {
    await meds.addMedication(
      patientId: services.patientId,
      name: 'Antodine',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: aug31,
    );
    await meds.addMedication(
      patientId: services.patientId,
      name: 'Eltroxin',
      timing: FixedTiming(MinuteOfDay.hm(6, 30)),
      startDate: aug31,
    );
    // الشاشة بتعيد الجدولة بساعة الجهاز الحقيقية، فالنافذة الأولى لازم
    // تتبني بنفس الساعة وإلا الفرق يبقى يوم اتزحلق، مش جرعة اتحركت.
    await services.scheduler.rescheduleAll();
    final fixedBefore = sink.scheduled.entries
        .where((e) => e.value.body.contains('Eltroxin'))
        .map((e) => e.key)
        .toSet();
    final anchoredBefore = sink.scheduled.keys.toSet().difference(fixedBefore);

    await pumpEdit(tester);
    await tester.tap(find.text('٨:٣٠ ص')); // اقتراح الفطار التاني
    await tester.pumpAndSettle();
    await tester.tap(find.text('احفظ يومك'));
    await settle(tester);

    final saved = await routines.getRoutine(services.patientId);
    expect(saved!.breakfast, MinuteOfDay.hm(8, 30));
    expect(saved.lunch, normalDay.lunch, reason: 'الباقي زي ما هو');

    final fixedAfter = sink.scheduled.entries
        .where((e) => e.value.body.contains('Eltroxin'))
        .map((e) => e.key)
        .toSet();

    // الجرعات بس في المقارنتين دول. درجات السلّم **مش** جزء من السؤال
    // «الثابتة اتحركت ولا لأ»: السلّم بيغطي أقرب ٧ تذكيرات، فلو تذكير
    // جديد دخل النافذة قدّامها، أبعد درجة بتخرج — وده قرار تغطية سليم،
    // مش جرعة ثابتة اتزحلقت.
    //
    // من غير الفلترة دي الاختبار بيرسب حسب **ساعة اليوم**: لو التشغيل
    // وقع بين ٧:٠٠ و٨:٠٠، جرعة المرساة بتكون عدّت قبل التعديل ولسه جاية
    // بعده، فبتدخل النافذة وبتزقّ درجة بتاعة الثابتة بره. الـ id بتاع
    // الجرعة الثابتة نفسها ما بيتغيّرش أبداً — وده اللي القاعدة الأولى
    // بتقوله.
    expect(
      fixedAfter.where(isDoseId).toSet(),
      fixedBefore.where(isDoseId).toSet(),
      reason: 'الثابتة ما اتحركتش',
    );
    expect(
      sink.cancelled.where(isDoseId).toSet(),
      anchoredBefore.where(isDoseId).toSet(),
      reason: 'المرساة اتحركت',
    );
    // قبل الفطار (٨:٣٠) بنص ساعة = ٨:٠٠ — لكل الأيام اللي في النافذة
    final anchoredAfter = sink.scheduled.keys.toSet().difference(fixedAfter);
    expect(anchoredAfter, isNotEmpty);
    // الجرعات بس — درجات السلّم بتيجي +١٥ و+٣٠ من نفس الساعة
    for (final id in anchoredAfter.where(isDoseId)) {
      expect(sink.scheduled[id]!.at.hour, 8);
      expect(sink.scheduled[id]!.at.minute, 0);
    }
  });

  screenTest('«ساعة تانية» بتفتح عجلة واحدة بس', (tester) async {
    await pumpEdit(tester);
    expect(find.byType(TimeWheel), findsNothing);

    await tester.tap(find.text('ساعة تانية').first);
    await tester.pumpAndSettle();
    expect(find.byType(TimeWheel), findsOneWidget);

    await tester.tap(find.text('ساعة تانية').first);
    await tester.pumpAndSettle();
    expect(find.byType(TimeWheel), findsOneWidget, reason: 'واحدة بس في المرة');
  });

  screenTest('زرار الحفظ ٦٤ وكل نص مش أقل من ١٧', (tester) async {
    await pumpEdit(tester);

    expect(tester.getSize(find.byType(FilledButton)).height, F.primaryButtonHeight);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size != null) {
        expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
      }
    }
  });

  screenTest('رمضان شغّال → سطر ذهبي والحفظ مقفول — التعديل من هنا كان هيضيع',
      (tester) async {
    await routines.enterRamadan(services.patientId, RamadanTimes.cairoDefaults);
    final before = await routines.getRoutine(services.patientId);
    await pumpEdit(tester);

    final line = tester.widget<Text>(find.text('وضع رمضان شغّال — عدّل من شاشة رمضان'));
    expect(line.style?.color, F.gold);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(find.text('احفظ يومك'), warnIfMissed: false);
    await settle(tester);
    expect(await routines.getRoutine(services.patientId), before);
    expect(await routines.ramadanTimes(services.patientId), isNotNull);
  });

  screenTest('رمضان مقفول → مفيش سطر والحفظ شغّال', (tester) async {
    await pumpEdit(tester);
    expect(find.textContaining('وضع رمضان شغّال'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });
}
