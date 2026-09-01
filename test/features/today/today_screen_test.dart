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
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/onboarding/time_wheel.dart';
import 'package:fakkarni/features/today/today_screen.dart';

/// نفس روتين اختبارات المحرك: صحيان ٧، فطار ٧:٣٠، غدا ٢:٣٠، عشا ٨، نوم ١١:٣٠ م
final normalDay = DayRoutine(
  wake: MinuteOfDay.hm(7),
  breakfast: MinuteOfDay.hm(7, 30),
  lunch: MinuteOfDay.hm(14, 30),
  dinner: MinuteOfDay.hm(20),
  sleep: MinuteOfDay.hm(23, 30),
);

final aug31 = DateTime(2026, 8, 31);

/// ٨:٠٠ ص — بعد الصحيان (٧:٠٠)، يعني جوّه يوم روتين ٣١ أغسطس.
///
/// مهم: الساعة ٦:٣٠ ص كانت هتبقى لسه في يوم ٣٠ أغسطس، لأن اليوم بيبدأ من
/// الصحيان مش من نص الليل.
final morning = DateTime(2026, 8, 31, 8);

class RecordingSink implements ReminderSink {
  final List<int> cancelled = [];

  @override
  Future<void> schedule(PlannedNotification notification) async {}
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
  @override
  Future<Set<int>> pendingIds() async => {};
  @override
  Future<void> ensurePermissions() async {}
}

/// اختبار شاشة بيفكّ الشجرة قبل ما يخلص.
///
/// drift بيجدول Timer وهو بيقفل البث. لو الشجرة فضلت مركّبة لحد ما الـbinding
/// ينضّف بعد الاختبار، الـTimer بيتعدّ «معلّق» والاختبار بيقع — والفحص ده
/// بيحصل قبل الـtearDown، فمفيش فايدة من التنضيف هناك.
void screenTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    // drift بيجدول Timer وهو بيقفل البث (عشان الكاش)، والـbinding بيعتبره
    // «مؤقّت معلّق» وبيوقّع الاختبار. بنديله فرصة يشتغل وإحنا لسه جوّه.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  });
}

void main() {
  late AppDatabase db;
  late MedicationRepository meds;
  late AppServices services;
  late RecordingSink sink;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
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

  Future<void> addDose(String name, DayAnchor anchor, {int offset = 0}) =>
      meds.addMedication(
        patientId: services.patientId,
        name: name,
        timing: AnchorTiming(anchor, offset),
        startDate: aug31,
        amountLabel: 'قرص واحد',
      );

  /// `pumpAndSettle` بيرجع أول ما يبقى مفيش فريم متجدول — من غير ما يستنى
  /// كتابة قاعدة البيانات اللي لسه شغالة. بنلف على `pump` عشان الـmicrotasks
  /// بتاعة drift تخلص قبل ما نبص على الشاشة.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpToday(WidgetTester tester, {DateTime? now}) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: F.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: TodayScreen(routine: normalDay, now: now ?? morning),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('الجرعة الجاية فوق، وزرار «أخدته» ارتفاعه ٦٤', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await pumpToday(tester);

    expect(find.text('الجاية'), findsOneWidget);
    expect(find.text('٢:٠٠ م'), findsWidgets);

    final button = tester.getSize(find.byType(FilledButton).first);
    expect(button.height, F.primaryButtonHeight);
  });

  screenTest('الجرعة الجاية فوق كل حاجة تانية في الشاشة', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await addDose('Telfast', DayAnchor.sleep, offset: -15);
    await pumpToday(tester);

    final next = tester.getCenter(find.text('الجاية'));
    final rail = tester.getCenter(find.textContaining('الغدا ٢:٣٠'));
    expect(next.dy, lessThan(rail.dy));
  });

  screenTest('بعد «أخدته» الجرعة بتبقى سطر هادي وما بتختفيش', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await pumpToday(tester);

    expect(find.textContaining('Antodine'), findsWidgets);

    await tester.tap(find.text('أخدته').first);
    await settle(tester);

    // لسه موجودة — بعلامة صح وبهدوء
    expect(find.textContaining('Antodine'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.textContaining('أخدته ', skipOffstage: false), findsWidgets);
    expect(find.text('الجاية'), findsNothing);
  });

  screenTest('«أخدته» بيلغي تذكير الخانة دي', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await pumpToday(tester);

    await tester.tap(find.text('أخدته').first);
    await settle(tester);

    // التذكير والتأجيل بتاع نفس الخانة — لو كان قال «فكّرني بعدين» قبلها
    expect(sink.cancelled, [
      notificationIdFor(DateTime(2026, 8, 31, 14)),
      snoozeIdFor(DateTime(2026, 8, 31, 14)),
    ]);
  });

  screenTest('دواءين في نفس الدقيقة = كارت واحد', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await addDose('Vitamin D', DayAnchor.lunch, offset: -30);
    await pumpToday(tester);

    expect(find.text('الجاية'), findsOneWidget);
    expect(find.textContaining('Antodine'), findsWidgets);
    expect(find.textContaining('Vitamin D'), findsWidgets);
  });

  screenTest('الجرعات مرتّبة بالوقت على الشريط', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await addDose('LINEX', DayAnchor.dinner, offset: 30);
    await pumpToday(tester);

    final breakfast = tester.getCenter(find.textContaining('الفطار ٧:٣٠'));
    final dinner = tester.getCenter(find.textContaining('العشا ٨:٠٠'));
    expect(breakfast.dy, lessThan(dinner.dy));
  });

  screenTest('جرعة فات معادها مفيهاش أحمر ولا لوم', (tester) async {
    await addDose('Antodine', DayAnchor.breakfast, offset: -30);
    // الساعة ٩ الصبح، وجرعة ٧:٠٠ فاتت
    await pumpToday(tester, now: DateTime(2026, 8, 31, 9));

    expect(find.textContaining('فات معاده'), findsWidgets);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final colour = text.style?.color;
      if (colour == null) continue;
      final isRed = colour.r > 0.6 && colour.g < 0.35 && colour.b < 0.35;
      expect(isRed, isFalse, reason: 'مفيش أحمر: ${text.data}');
    }
  });

  screenTest('مفيش أدوية → الحالة الفاضية وزرار الإضافة', (tester) async {
    await pumpToday(tester);

    expect(find.textContaining('مفيش أدوية لسه'), findsOneWidget);
    expect(find.text('ضيف دوا'), findsOneWidget);
    expect(find.text('الجاية'), findsNothing);
  });

  screenTest('كل نص في الشاشة مش أقل من ١٧', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await pumpToday(tester);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final size = text.style?.fontSize;
      if (size != null) {
        expect(size, greaterThanOrEqualTo(F.minTextSize), reason: text.data);
      }
    }
  });

  group('ضيف دوا', () {
    Future<void> pumpAdd(WidgetTester tester) async {
      // الشاشة أطول من ٦٠٠ بكسل الافتراضية، وعناصر ListView اللي برّه الشاشة
      // مش بتتبني أصلاً — فبنكبّر النافذة بدل ما ندوّر بالسكرول.
      tester.view.physicalSize = const Size(1000, 3000);
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
              child: AddMedicationScreen(routine: normalDay, today: aug31),
            ),
          ),
        ),
      );
        await settle(tester);
    }

    screenTest('المرساة هي المدخل الأساسي، ومفيش منتقي ساعة', (tester) async {
      await pumpAdd(tester);

      expect(find.text('قبل الفطار'), findsOneWidget);
      expect(find.text('بعد العشا'), findsOneWidget);
      expect(find.byType(TimePickerDialog), findsNothing);
    });

    screenTest('المعاينة بتتحرك مع المرساة والإزاحة', (tester) async {
      await pumpAdd(tester);

      // قبل الفطار بـ٣٠ = ٧:٠٠ ص
      expect(find.text('يبقى حوالي ٧:٠٠ ص'), findsOneWidget);

      await tester.tap(find.text('بعد العشا'));
      await tester.pumpAndSettle();
      expect(find.text('يبقى حوالي ٨:٣٠ م'), findsOneWidget);
    });

    screenTest('المدة المفتوحة هي الافتراضي وبتتخزّن null', (tester) async {
      await pumpAdd(tester);

      expect(find.text('مفتوحة'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Concor 5mg');
      await tester.pumpAndSettle();
      await tester.tap(find.text('احفظ الجرعة'));
      await settle(tester);

      final saved = (await meds.activeSchedules(services.patientId)).single;
      expect(saved.medicationName, 'Concor 5mg');
      expect(saved.durationDays, isNull);
      expect(saved.timing, const AnchorTiming(DayAnchor.breakfast, -30));
    });

    screenTest('من غير اسم الحفظ مقفول', (tester) async {
      await pumpAdd(tester);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    screenTest('لينك الساعة الثابتة آخر حاجة — تحت «احفظ الجرعة»', (tester) async {
      await pumpAdd(tester);

      final link = find.text('أحدد ساعة ثابتة بدل كده');
      expect(link, findsOneWidget);
      expect(find.text('ساعة ثابتة — مش هتتحرك مع روتين يومك'), findsNothing);

      final linkY = tester.getCenter(link).dy;
      expect(linkY, greaterThan(tester.getCenter(find.text('احفظ الجرعة')).dy));
      expect(linkY, greaterThan(tester.getCenter(find.text('قبل الفطار')).dy));
      // لينك نصّي هادي، مش شيب جنب المراسي
      expect(tester.getSize(find.ancestor(of: link, matching: find.byType(TextButton))).height,
          F.minTapTarget);
    });

    screenTest('الساعة الثابتة بتقول عن نفسها صراحة وبتشيل المراسي', (tester) async {
      await pumpAdd(tester);

      await tester.tap(find.text('أحدد ساعة ثابتة بدل كده'));
      await tester.pumpAndSettle();

      expect(find.text('ساعة ثابتة — مش هتتحرك مع روتين يومك'), findsOneWidget);
      expect(find.byType(TimeWheel), findsOneWidget);
      expect(find.text('قبل الفطار'), findsNothing);
      expect(find.text('أحدد ساعة ثابتة بدل كده'), findsNothing);
      expect(find.text('يبقى حوالي ٨:٠٠ ص'), findsOneWidget);

      // والرجوع للمراسي متاح
      await tester.tap(find.text('ارجع للمراسي'));
      await tester.pumpAndSettle();
      expect(find.text('قبل الفطار'), findsOneWidget);
      expect(find.text('ساعة ثابتة — مش هتتحرك مع روتين يومك'), findsNothing);
    });

    screenTest('الحفظ في وضع الساعة الثابتة بيخزّن FixedTiming', (tester) async {
      await pumpAdd(tester);

      await tester.enterText(find.byType(TextField), 'Eltroxin');
      await tester.tap(find.text('أحدد ساعة ثابتة بدل كده'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('احفظ الجرعة'));
      await settle(tester);

      final saved = (await meds.activeSchedules(services.patientId)).single;
      expect(saved.timing, FixedTiming(MinuteOfDay.hm(8)));
    });
  });
}
