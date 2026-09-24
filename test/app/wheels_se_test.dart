import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/f_wheels.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_plan.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';
import 'package:fakkarni/data/services/reminder_sink.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/dose_editor.dart';
import 'package:fakkarni/features/onboarding/routine_onboarding_screen.dart';
import 'package:fakkarni/features/records/checkup_screen.dart' show FastingSheet;
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/features/routine/ask_anchor_time.dart';
import 'package:fakkarni/features/routine/edit_routine_screen.dart';

import '../support/seeded_clock.dart';

/// **كل شاشة اتحطّت فيها بكرة لازم تسيع iPhone SE (٣٧٥×٦٦٧) والزرار
/// الأساسي ظاهر** — بالخطوط الحقيقية، لأن خط الاختبار بيرسم كل حرف مربّع
/// وبيطلّع فيض مش حقيقي.
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
  await load('IBM Plex Mono', ['IBMPlexMono-Medium.ttf', 'IBMPlexMono-SemiBold.ttf']);
}

class _SilentSink implements ReminderSink {
  @override
  Future<void> schedule(PlannedNotification notification) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<Set<int>> pendingIds() async => {};
  @override
  Future<void> ensurePermissions() async {}
}

final _routine = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

void main() {
  setUpAll(_loadFonts);
  late AppDatabase db;
  late AppServices services;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db, clock: seededLongAgo);
    final patientId = await routines.ensurePatient();
    await routines.saveRoutine(patientId, _routine);
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
        sink: _SilentSink(),
      ),
      patientId: patientId,
    );
  });

  tearDown(() async {
    // بنفضّي الشجرة قبل القفل عشان الـstreams تتقفل بهدوء
    await db.close();
  });

  Future<void> pumpSE(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(textDirection: TextDirection.rtl, child: child),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  /// الزرار الأساسي كامل جوّه ٦٦٧ بكسل ومفيش فيض.
  void expectPrimaryVisible(WidgetTester tester, String label) {
    expect(tester.takeException(), isNull, reason: 'فيض على SE');
    final button = tester.getRect(find.widgetWithText(FilledButton, label).first);
    expect(button.top, greaterThanOrEqualTo(0), reason: label);
    expect(button.bottom, lessThanOrEqualTo(667), reason: '«$label» تحت حافة SE: $button');
  }

  testWidgets('محرّر الجرعة: المراسي وبكرة الإزاحة، و«احفظ الجرعة» ظاهر', (tester) async {
    await pumpSE(tester, DoseEditor(name: 'Concor', routine: _routine, onSave: (_) async {}));
    expect(find.byKey(const ValueKey('gap-wheel')), findsOneWidget);
    expectPrimaryVisible(tester, 'احفظ الجرعة');
    expect(find.byType(FTimeWheel), findsNothing);
  });

  testWidgets('محرّر الجرعة على ساعة ثابتة: بكرة الساعة و«احفظ الجرعة» ظاهر', (tester) async {
    await pumpSE(tester, DoseEditor(name: 'Concor', routine: _routine, onSave: (_) async {}));
    await tester.tap(find.text('أحدد ساعة ثابتة بدل كده'));
    await settle(tester);
    expect(find.byType(FTimeWheel), findsOneWidget);
    expectPrimaryVisible(tester, 'احفظ الجرعة');
  });

  testWidgets('«ضيف دوا» بـ«أكتر» و«أيام محددة» مفتوحين: بكرتين و«كمّل» ظاهر', (tester) async {
    await pumpSE(tester, AddMedicationScreen(routine: _routine));
    await tester.tap(find.byKey(const ValueKey('count-more')));
    await settle(tester);
    // كارت المدة تحت الفورم — بيتلفّ له؛ الزرار الأساسي نفسه مثبّت تحت
    await tester.dragUntilVisible(find.text('أيام محددة'), find.byType(ListView), const Offset(0, -120));
    await settle(tester);
    await tester.tap(find.text('أيام محددة'));
    await settle(tester);
    expect(find.byKey(const ValueKey('count-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('days-wheel')), findsOneWidget);
    expectPrimaryVisible(tester, 'كمّل — إمتى؟');
  });

  testWidgets('سؤال الروتين: بكرة الساعة و«تمام» ظاهر', (tester) async {
    await pumpSE(tester, const RoutineOnboardingScreen(askProfile: false));
    expect(find.byType(FTimeWheel), findsOneWidget);
    expectPrimaryVisible(tester, 'تمام');
  });

  testWidgets('عدّل يومك وبكرة مفتوحة: «احفظ يومك» ظاهر', (tester) async {
    await pumpSE(tester, EditRoutineScreen(routine: _routine));
    await tester.tap(find.text('ساعة تانية').first);
    await settle(tester);
    expect(find.byType(FTimeWheel), findsOneWidget);
    expectPrimaryVisible(tester, 'احفظ يومك');
  });

  testWidgets('«عدّل يومك» وكل المراسي مش متحددة: خمس «مش متحدد» و«احفظ يومك» ظاهر', (tester) async {
    await pumpSE(tester, EditRoutineScreen(routine: DayRoutine.none));
    // القايمة كسولة على SE — اللي ظاهر بيقول «مش متحدد»، والزرار مثبّت تحت
    expect(find.text('مش متحدد'), findsWidgets);
    expectPrimaryVisible(tester, 'احفظ يومك');
  });

  testWidgets('شيت «بتفطر الساعة كام؟» جوّه SE: الاقتراحات والبكرة و«تمام» ظاهرين', (tester) async {
    await pumpSE(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => askAnchorTime(context, anchor: DayAnchor.breakfast, say: const Say(null)),
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح'));
    await settle(tester);
    expect(find.text('بتفطر الساعة كام؟'), findsOneWidget);
    expect(find.byType(FTimeWheel), findsOneWidget);
    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.byKey(const ValueKey('anchor-confirm')));
    expect(button.bottom, lessThanOrEqualTo(667), reason: '«تمام» تحت الحافة: $button');
    expect(button.top, greaterThanOrEqualTo(0));
  });

  testWidgets('شيت تذكير الصيام: بكرة الساعة وبكرة الساعات و«اضبط التذكير» جوّه SE', (tester) async {
    await pumpSE(tester, Scaffold(body: FastingSheet(now: DateTime(2026, 9, 15, 10))));
    expect(find.byType(FTimeWheel), findsOneWidget);
    expect(find.byKey(const ValueKey('fasting-hours')), findsOneWidget);
    expect(tester.takeException(), isNull);
    // الشيت بيلفّ لو ضاق، بس على SE الزرار لازم يبان من غير لفّ
    final button = tester.getRect(find.byKey(const ValueKey('fasting-save')));
    expect(button.bottom, lessThanOrEqualTo(667), reason: 'الزرار تحت الحافة: $button');
  });
}
