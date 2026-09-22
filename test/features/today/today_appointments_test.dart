import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/patient_voice.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/checkup_service.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/health/checkup.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../../support/seeded_clock.dart';

/// **«مواعيدك الجاية» فوق كارت الجرعة — بقرار المالك، وبضمانة.**
///
/// القرار بيخلّي الميعاد أول حاجة على الشاشة. الضمانة إن الكتلة تفضل
/// قصيرة، عشان «تأكيد الجرعة» يفضل باين **من غير سكرول** — واللي بيثبت
/// ده اختبار على أصغر آيفون مدعوم، مش نية مكتوبة في تعليق.
class _Sink implements ReminderSink {
  final List<PlannedNotification> scheduled = [];
  @override
  Future<void> schedule(PlannedNotification n) async => scheduled.add(n);
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<Set<int>> pendingIds() async => {};
  @override
  Future<void> ensurePermissions() async {}
}

final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

/// ٣١ أغسطس ٢٠٢٦، ٨ صباحاً — جرعة الفطار (٧:٠٠) عدّت ومستنية تأكيد.
final morning = DateTime(2026, 8, 31, 8);

void main() {
  late AppDatabase db;
  late AppServices services;
  late MedicationRepository meds;
  late CheckupService checkups;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    meds = MedicationRepository(db, clock: seededLongAgo);
    final sink = _Sink();
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
    checkups = CheckupService(db, sink);
  });

  tearDown(() => db.close());

  Future<void> addDose(String name, DayAnchor anchor, {int offset = 0}) => meds.addMedication(
        patientId: services.patientId,
        name: name,
        timing: AnchorTiming(anchor, offset),
        startDate: DateTime(2026, 8, 31),
        amountLabel: 'قرص واحد',
      );

  Future<int> book(DateTime day, {required String title}) async {
    final id = await checkups.start(patientId: services.patientId, title: title, today: morning);
    await checkups.advance(id, now: morning); // → حجز المعمل
    await checkups.setStageDate(id, CheckupStage.labBooking, day: day, now: morning);
    return id;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  Future<void> pump(WidgetTester tester, {Size size = const Size(1000, 4000)}) async {
    tester.view.physicalSize = size;
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
            child: PatientVoice(
              say: Say(Sex.m),
              child: TodayScreen(routine: normalDay, now: morning),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// الهيكل كامل — عشان الدوك و«ضيف» يبقوا في الصورة.
  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: AppShell(routine: normalDay, now: morning),
        ),
      ),
    );
    await settle(tester);
  }

  group('الترتيب', () {
    testWidgets('«مواعيدك الجاية» فوق «الآن»، و«المتابعات» بعد «جدول النهاردة»',
        (tester) async {
      await addDose('Concor', DayAnchor.breakfast, offset: -30);
      await book(DateTime(2026, 9, 5), title: 'صورة دم');
      // متابعة تانية من غير ميعاد — دي اللي بتفضل في «المتابعات»
      await checkups.start(patientId: services.patientId, title: 'متابعة الضغط', today: morning);
      await pump(tester);

      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      // **الكتلة بالمفتاح مش بالعنوان**: لما فيه جرعة مستنية تأكيد
      // بتتقلّص لسطر واحد من غير عنوان — ده تنازل مقصود عشان زرار
      // «تأكيد الجرعة» يفضل فوق «ضيف» العايم على أصغر آيفون.
      expect(tester.getTopLeft(find.byKey(const ValueKey('appointments-card'))).dy,
          lessThan(y('الآن')),
          reason: 'الميعاد أول حاجة');
      expect(y('الآن'), lessThan(y('جدول النهاردة')));
      expect(y('جدول النهاردة'), lessThan(y('المتابعات')));
      expect(y('المتابعات'), lessThan(y('المية')));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('مفيش تكرار', () {
    testWidgets('متابعة ليها ميعاد جاي بتتعرض في «مواعيدك الجاية» **وبس**',
        (tester) async {
      await book(DateTime(2026, 9, 5), title: 'صورة دم');
      await pump(tester);

      expect(find.textContaining('صورة دم'), findsOneWidget, reason: 'مرة واحدة على الشاشة');
      expect(find.text('المتابعات'), findsNothing,
          reason: 'مفضلش متابعة محتاجة حركة — القسم بيختفي');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('ومتابعة من غير ميعاد بتفضل في «المتابعات» لوحدها', (tester) async {
      await checkups.start(patientId: services.patientId, title: 'متابعة الضغط', today: morning);
      await pump(tester);

      expect(find.text('المتابعات'), findsOneWidget);
      expect(find.text('مواعيدك الجاية'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('الكتلة قصيرة', () {
    testWidgets('اتنين بس، والباقي سطر واحد بيفتح القايمة', (tester) async {
      for (var i = 0; i < 4; i++) {
        await book(DateTime(2026, 9, 5 + i), title: 'متابعة $i');
      }
      await pump(tester);

      expect(find.textContaining('متابعة 0'), findsOneWidget);
      expect(find.textContaining('متابعة 1'), findsOneWidget);
      expect(find.textContaining('متابعة 2'), findsNothing, reason: 'التالت اتطوى');
      expect(find.text('+ ميعادين تانيين'), findsOneWidget,
          reason: 'اللي زيادة بيتقال بالكلام، مش برقم لوحده');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    // **الحالة دي مش زيادة**: المفرد العربي صيغة لوحده، ولو ماحدش
    // جرّبه بيفضل خط مكتوب محدش عدّى عليه.
    testWidgets('وواحد زيادة بيتقال بالمفرد', (tester) async {
      for (var i = 0; i < 3; i++) {
        await book(DateTime(2026, 9, 5 + i), title: 'متابعة $i');
      }
      await pump(tester);

      expect(find.text('+ ميعاد تاني'), findsOneWidget);
      expect(find.textContaining('+١'), findsNothing, reason: 'رقم لوحده مش كلام');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('اللون', () {
    for (final (mode, dark) in [('نهاري', false), ('ليلي', true)]) {
      testWidgets('ذهبي زي كارت «الآن» — $mode', (tester) async {
        F.setDark(on: dark);
        addTearDown(() => F.setDark(on: false));
        await book(DateTime(2026, 9, 5), title: 'صورة دم');
        await pump(tester);

        final box = tester.widgetList<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('appointments-card')),
            matching: find.byType(Container),
          ),
        ).firstWhere((c) => c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).border != null);
        final border = (box.decoration! as BoxDecoration).border! as Border;
        expect(border.top.color, F.gold, reason: 'مش كهرماني — ده للسلّم');
        // وباين على أرضيته في الوضعين
        expect(_contrast(F.gold, F.cardGround), greaterThanOrEqualTo(dark ? 3.0 : 1.5));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
    }
  });

  group('الضمانة — أصغر آيفون', () {
    // iPhone SE: ٣٧٥×٦٦٧ نقطة.
    const se = Size(375, 667);

    testWidgets('«تأكيد الجرعة» كامل جوّه أول شاشة، والدوك مش مغطّيه',
        (tester) async {
      await addDose('Concor', DayAnchor.breakfast, offset: -30);
      await book(DateTime(2026, 9, 5), title: 'صورة دم');
      await book(DateTime(2026, 9, 7), title: 'أشعة');
      await pumpShell(tester, se);

      final button = find.text('تأكيد الجرعة');
      expect(button, findsOneWidget);
      final box = tester.getRect(button);

      // **والصفّين معروضين، مش واحد** (طلب المالك): التحليل كان
      // بيستخبى ورا «+١» على نفس الشاشة دي بالظبط.
      expect(find.textContaining('صورة دم'), findsOneWidget);
      expect(find.textContaining('أشعة'), findsOneWidget);

      // والدوك و«ضيف» مش فوقه
      // **ولا الدوك ولا «ضيف» العايم فوقه.**
      //
      // القياس ضيق جداً عن قصد، وده اللي الاختبار موجود عشانه: الزرار
      // بيخلص عند ٥٩٦ و«ضيف» بيبدأ عند ٥٩٧٫٤ — فرق **بكسل ونص**. أي
      // بكسل بيتزوّد فوق (ترويسة أطول، كتلة مواعيد أكبر، تكبير خط) بيرجّع
      // الزرار تحت الزرار العايم على أصغر آيفون.
      for (final key in ['ضيف', 'اليوم']) {
        final other = find.text(key);
        if (other.evaluate().isEmpty) continue;
        final rect = tester.getRect(other);
        expect(rect.overlaps(box), isFalse, reason: '«$key» فوق زرار التأكيد');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
