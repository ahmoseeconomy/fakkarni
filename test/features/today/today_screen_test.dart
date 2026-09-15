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
import 'package:fakkarni/domain/escalation/escalation_ladder.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/core/widgets/patient_voice.dart';
import 'package:fakkarni/core/widgets/primitives.dart';
import 'package:fakkarni/domain/patient/sex.dart';
import 'package:fakkarni/features/today/widgets/now_card.dart';
import 'package:fakkarni/data/db/tables.dart' show GlucoseContext;
import 'package:fakkarni/data/repositories/readings_repository.dart';
import 'package:fakkarni/features/health/glucose_screen.dart';
import 'package:fakkarni/features/health/usual_words.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/dose_editor.dart';
import 'package:fakkarni/features/onboarding/time_wheel.dart';
import 'package:fakkarni/features/reminder/reminder_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../scan/scan_test_support.dart' show expectNoRedAndMinSize;
import '../../support/seeded_clock.dart';

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
  final List<PlannedNotification> scheduled = [];

  @override
  Future<void> schedule(PlannedNotification notification) async => scheduled.add(notification);
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

void expectNoRed(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final colour = text.style?.color;
    if (colour == null) continue;
    final isRed = colour.r > 0.6 && colour.g < 0.35 && colour.b < 0.35;
    expect(isRed, isFalse, reason: 'مفيش أحمر: ${text.data}');
  }
}

void main() {
  late AppDatabase db;
  late MedicationRepository meds;
  late AppServices services;
  late RecordingSink sink;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final routines = RoutineRepository(db);
    meds = MedicationRepository(db, clock: seededLongAgo);
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

  Future<void> pumpToday(WidgetTester tester, {DateTime? now, Sex? sex}) async {
    // الرئيسية (D3.2) فوق السكة — الشاشة أطول من ٦٠٠ بكسل الافتراضية
    tester.view.physicalSize = const Size(1000, 4000);
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
              say: Say(sex),
              child: TodayScreen(routine: normalDay, now: now ?? morning),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('«الآن»: الجرعة الجاية فوق، و«تأكيد الجرعة» ارتفاعه ٦٤', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await pumpToday(tester);

    expect(find.text('جدول النهاردة'), findsOneWidget);
    expect(find.text('الجاية'), findsOneWidget);
    expect(find.text('كمان ٦ ساعات · ٢:٠٠ م'), findsOneWidget);

    final button = tester.getSize(find.byType(FilledButton).first);
    expect(button.height, F.primaryButtonHeight);
    // اسم الدوا mono LTR ٢٤+
    final name = tester.widget<Text>(find.text('Antodine').first);
    expect(name.style?.fontSize, greaterThanOrEqualTo(F.medicationNameSize));
    expect(name.textDirection, TextDirection.ltr);
  });

  screenTest('الجرعة الجاية فوق كل حاجة تانية في الشاشة', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await addDose('Telfast', DayAnchor.sleep, offset: -15);
    await pumpToday(tester);

    final next = tester.getCenter(find.text('الجاية'));
    final rail = tester.getCenter(find.textContaining('الغدا · ٢:٣٠'));
    expect(next.dy, lessThan(rail.dy));
  });

  screenTest('بعد «تأكيد الجرعة» الجرعة بتبقى سطر هادي وما بتختفيش', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await pumpToday(tester);

    expect(find.textContaining('Antodine'), findsWidgets);

    await tester.tap(find.text('تأكيد الجرعة'));
    await settle(tester);

    // لسه موجودة على السكة — بعلامة صح وبهدوء
    expect(find.textContaining('Antodine'), findsWidgets);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.textContaining('أخدته ', skipOffstage: false), findsWidgets);
    expect(find.text('الجاية'), findsNothing);
  });


  screenTest('جرعة اتنست بعد المهلة → «نسيتها؟» فوق و«لسه ما اتأكدتش» على السكة، والزرار شغّال', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30); // ٢:٠٠ م
    // فتحة الساعة ٣:٠٠ — عدّى ساعة على الجرعة من غير تأكيد
    await services.scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 15));
    await pumpToday(tester, now: DateTime(2026, 8, 31, 15));

    expect(find.text('نسيتها؟'), findsOneWidget);
    expect(find.text('لسه ما اتأكدتش'), findsOneWidget);
    expect(find.text('الجاية'), findsNothing);
    expect(find.text('تأكيد الجرعة'), findsOneWidget, reason: 'نسي — لسه يقدر يأكّد');

    await tester.tap(find.text('تأكيد الجرعة'));
    await settle(tester);
    expect(find.text('نسيتها؟'), findsNothing);
    expect(find.textContaining('أخدته ', skipOffstage: false), findsWidgets);
  });

  screenTest('«تأكيد الجرعة» بيلغي تذكير الخانة دي', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await pumpToday(tester);

    await tester.tap(find.text('تأكيد الجرعة'));
    await settle(tester);

    // التذكير والتأجيل والسلّم بتوع نفس الخانة — لو كان قال «فكّرني بعدين»
    // قبلها، أو كان السلّم شغّال
    expect(sink.cancelled, [
      notificationIdFor(DateTime(2026, 8, 31, 14)),
      snoozeIdFor(DateTime(2026, 8, 31, 14)),
      escalationIdFor(DateTime(2026, 8, 31, 14), EscalationRung.first),
      escalationIdFor(DateTime(2026, 8, 31, 14), EscalationRung.second),
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

    final breakfast = tester.getCenter(find.textContaining('الفطار · ٧:٣٠'));
    final dinner = tester.getCenter(find.textContaining('العشا · ٨:٠٠'));
    expect(breakfast.dy, lessThan(dinner.dy));
  });

  screenTest('جرعة فات معادها مفيهاش أحمر ولا لوم', (tester) async {
    await addDose('Antodine', DayAnchor.breakfast, offset: -30);
    // الساعة ٩ الصبح، وجرعة ٧:٠٠ فاتت
    await pumpToday(tester, now: DateTime(2026, 8, 31, 9));

    expect(find.textContaining('كان معادها'), findsOneWidget);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final colour = text.style?.color;
      if (colour == null) continue;
      final isRed = colour.r > 0.6 && colour.g < 0.35 && colour.b < 0.35;
      expect(isRed, isFalse, reason: 'مفيش أحمر: ${text.data}');
    }
  });

  screenTest('الفايتة والمنتظرة الاتنين بحافة ذهبية — والمأخوذة سطر ✓ ما بيتشالش', (tester) async {
    await addDose('Antodine', DayAnchor.breakfast, offset: -30); // ٧:٠٠ — هتتاخد
    await addDose('LINEX', DayAnchor.breakfast, offset: 30); // ٨:٠٠ — فاتت
    await addDose('Telfast', DayAnchor.dinner, offset: 0); // ٨:٠٠ م — منتظرة
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpToday(tester, now: DateTime(2026, 8, 31, 9));

    // ٧:٠٠ اتاخدت — بالمستودع مباشرة: زرار الكارت بيعيد الجدولة بساعة
    // الجهاز الحقيقية، واللي كانت هتكتب «اتنست» على يوم ٣١ أغسطس كله
    final antodine = (await meds.activeSchedules(services.patientId))
        .singleWhere((s) => s.medicationName == 'Antodine');
    await services.events.markTaken(int.parse(antodine.id), aug31);
    await settle(tester);

    // أقرب Material ليه حافة — الكارت نفسه، مش الـScaffold
    Color? edgeOf(String name) {
      for (final m in tester.widgetList<Material>(
        find.ancestor(of: find.text(name), matching: find.byType(Material)),
      )) {
        final shape = m.shape;
        if (shape is RoundedRectangleBorder && shape.side != BorderSide.none) {
          return shape.side.color;
        }
      }
      return null;
    }

    // LINEX فاتت — ذهبي و«لسه ما اتأكدتش»، مش رمادي
    expect(edgeOf('LINEX'), F.gold);
    expect(find.text('لسه ما اتأكدتش'), findsOneWidget);
    // Telfast منتظرة — نفس الحافة
    expect(edgeOf('Telfast'), F.gold);
    // Antodine لسه على السكة، سطر هادي — وكمان تحت «خلال ٤٨ ساعة» بتاع بكرة
    expect(find.text('Antodine'), findsWidgets);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // زرار أساسي واحد بس — مفيش «أخدته» على كل كارت
    expect(find.byType(FilledButton), findsOneWidget);
    expectNoRed(tester);
  });

  screenTest('الدوسة على كارت في السكة بتفتح شاشة التذكير بتاعته', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    await addDose('Telfast', DayAnchor.dinner, offset: 0);
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpToday(tester);

    await tester.tap(find.text('Telfast').last);
    await settle(tester);
    expect(find.byType(ReminderScreen), findsOneWidget);
  });

  screenTest('مفيش زرار رمضان ولا «اربط ابني» ولا تكرار لـ«ضيف» في الشاشة دي', (tester) async {
    await addDose('Antodine', DayAnchor.lunch, offset: -30);
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpToday(tester);

    for (final gone in ['وضع رمضان', 'اربط ابني', 'ضيف دوا', 'صوّر روشتة', 'عدّل يومك', 'أدويتك']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.byType(FilledButton).evaluate().length, lessThanOrEqualTo(2));
  });

  screenTest('دوا جرعته مش معروفة → سطر هادي «اسأل الصيدلي عن جرعة …»', (tester) async {
    await meds.addMedication(
      patientId: services.patientId,
      name: 'Telfast 180 mg',
      timing: const AnchorTiming(DayAnchor.dinner, 0),
      startDate: aug31,
      amountUnknown: true,
    );
    // السطر تحت الشريط — برّه الـ٦٠٠ بكسل الافتراضية، فبنكبّر النافذة
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpToday(tester);

    expect(find.text('اسأل الصيدلي عن جرعة Telfast 180 mg'), findsOneWidget);
    final text = tester.widget<Text>(find.text('اسأل الصيدلي عن جرعة Telfast 180 mg'));
    expect(text.style?.color, F.muted, reason: 'هادي، مش تنبيه');
  });

  screenTest('مفيش أدوية → الحالة الفاضية بتشاور على «ضيف»', (tester) async {
    await pumpToday(tester);

    expect(find.textContaining('مفيش أدوية لسه'), findsOneWidget);
    expect(find.text('الجاية'), findsNothing);
  });

  screenTest('فيه دوا بس مفيش جرعة النهارده → ما بتقولش «مفيش أدوية»', (tester) async {
    await meds.addMedication(
      patientId: services.patientId,
      name: 'Concor 5mg',
      timing: const AnchorTiming(DayAnchor.breakfast, -30),
      startDate: DateTime(2026, 9, 1),
    );
    await pumpToday(tester);

    expect(find.textContaining('مفيش أدوية لسه'), findsNothing);
    expect(find.textContaining('مفيش جرعات فاضلة النهارده'), findsOneWidget);
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

  group('الرئيسية (D3.2)', () {
    screenTest('الترحيب بالاسم والسن، والعنوان بجنس المريض — مش فصحى', (tester) async {
      await services.routines.saveProfile(services.patientId, name: 'فاطمة', sex: Sex.f, age: 68);
      await pumpToday(tester, sex: Sex.f);

      expect(find.text('يومك'), findsOneWidget);
      expect(find.text('صباح الخير يا فاطمة'), findsOneWidget);
      expect(find.text('فاطمة · ٦٨ سنة'), findsOneWidget);
      expect(find.text('تعملي إيه دلوقتي؟'), findsOneWidget);
      expect(find.text('ماذا أفعل الآن؟'), findsNothing);
    });

    screenTest('راجل بالليل من غير سن → «مساء الخير يا محمد» ومفيش سطر سن', (tester) async {
      await services.routines.saveProfile(services.patientId, name: 'محمد', sex: Sex.m);
      await pumpToday(tester, now: DateTime(2026, 8, 31, 21), sex: Sex.m);

      expect(find.text('مساء الخير يا محمد'), findsOneWidget);
      expect(find.textContaining('سنة'), findsNothing);
      expect(find.text('تعمل إيه دلوقتي؟'), findsOneWidget);
    });

    screenTest('«الآن»: الفايتة قبل الجاية، ذهبي من غير أحمر، وزرار أساسي واحد', (tester) async {
      await addDose('Antodine', DayAnchor.breakfast, offset: -30); // ٧:٠٠ — فاتت
      await addDose('LINEX', DayAnchor.lunch, offset: -30); // ٢:٠٠ م — الجاية
      await pumpToday(tester, now: DateTime(2026, 8, 31, 9));

      final cards = find.byType(NowCard);
      expect(cards, findsNWidgets(2));
      final missed = tester.getCenter(find.descendant(of: cards.first, matching: find.text('Antodine')));
      final next = tester.getCenter(find.descendant(of: cards.last, matching: find.text('LINEX')));
      expect(missed.dy, lessThan(next.dy));
      expect(find.text('لسه ما اتأكدتش · كان معادها ٧:٠٠ ص'), findsOneWidget);
      for (final card in tester.widgetList<FCard>(find.descendant(of: cards, matching: find.byType(FCard)))) {
        expect(card.tone, FCardTone.attention);
      }
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('افتح'), findsOneWidget, reason: 'الكارت التاني بيفتح شاشة التذكير');
      expectNoRed(tester);
    });

    screenTest('«لاحقًا» تأجيل حقيقي ربع ساعة وبيقول كده', (tester) async {
      await addDose('Antodine', DayAnchor.breakfast, offset: -30); // ٧:٠٠
      await pumpToday(tester);

      await tester.tap(find.text('لاحقًا').first);
      await settle(tester);

      expect(sink.scheduled.map((n) => n.id), contains(snoozeIdFor(DateTime(2026, 8, 31, 7))));
      expect(find.text('هنفكّرك تاني بعد ربع ساعة'), findsOneWidget);
    });

    screenTest('«خلال ٤٨ ساعة» فيها جرعات بكرة، ومفيش سكر ولا تحاليل', (tester) async {
      await addDose('Telfast', DayAnchor.dinner, offset: 0);
      await pumpToday(tester);

      final section = tester.getCenter(find.text('خلال ٤٨ ساعة'));
      final tomorrow = tester.getCenter(find.text('بكرة ٨:٠٠ م'));
      expect(tomorrow.dy, greaterThan(section.dy));
      for (final gone in ['السكر', 'سكر', 'التحاليل', 'تحليل']) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
    });

    screenTest('الرئيسية فوق «جدول النهاردة»', (tester) async {
      await addDose('Antodine', DayAnchor.lunch, offset: -30);
      await pumpToday(tester);

      expect(tester.getCenter(find.text('الآن')).dy, lessThan(tester.getCenter(find.text('جدول النهاردة')).dy));
      expect(tester.getCenter(find.text('المية')).dy, lessThan(tester.getCenter(find.text('جدول النهاردة')).dy));
      expectNoRedAndMinSize(tester);
    });
  });

  group('كارت السكر على الرئيسية (D3.6)', () {
    Future<void> seed(List<int> fasting, {required int latest}) async {
      final repo = ReadingsRepository(db);
      for (final (i, v) in fasting.indexed) {
        await repo.add(patientId: services.patientId, valueMgDl: v, context: GlucoseContext.fasting, measuredAt: DateTime(2026, 8, 20 + i, 7));
      }
      await repo.add(patientId: services.patientId, valueMgDl: latest, context: GlucoseContext.fasting, measuredAt: DateTime(2026, 8, 31, 7, 30));
    }

    FCard glucoseCard(WidgetTester tester) => tester.widget<FCard>(find.byKey(const ValueKey('glucose-home')));

    screenTest('من غير قياسات → مفيش كارت سكر', (tester) async {
      await pumpToday(tester);
      expect(find.byKey(const ValueKey('glucose-home')), findsNothing);
    });

    screenTest('برّه المعتاد ليه هو → في «الآن»، ذهبي، رقم وفرق، من غير أحمر ولا نصيحة، و«افتح» ثانوي', (tester) async {
      await seed([118, 110, 131, 122, 125], latest: 152);
      await pumpToday(tester);

      expect(glucoseCard(tester).tone, FCardTone.attention);
      expect(find.text('الآن'), findsOneWidget, reason: 'حتى من غير جرعات');
      expect(find.text('أعلى من أعلى قياس معتاد ليك (١٣١) بـ ٢١'), findsOneWidget);
      expect(tester.getCenter(find.byKey(const ValueKey('glucose-home'))).dy,
          lessThan(tester.getCenter(find.text('المية')).dy));
      expect(find.byType(FilledButton), findsNothing, reason: '«افتح» مش أساسي');
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        for (final w in adviceWords.where((w) => !RegExp(r'^[a-z]+$').hasMatch(w))) {
          expect((t.data ?? '').contains(w), isFalse, reason: '«$w» في ${t.data}');
        }
      }
      expectNoRed(tester);

      await tester.tap(find.descendant(of: find.byKey(const ValueKey('glucose-home')), matching: find.text('افتح')));
      await settle(tester);
      expect(find.byType(GlucoseScreen), findsOneWidget);
    });

    screenTest('جوّه المعتاد أو لسه مش كفاية → كارت هادي مش ذهبي، ومش في «الآن»', (tester) async {
      await seed([118, 110], latest: 152);
      await pumpToday(tester);
      expect(glucoseCard(tester).tone, FCardTone.plain);
      expect(find.text(notEnoughForUsual), findsOneWidget);
      expect(find.text('الآن'), findsNothing);
    });
  });

  group('ضيف دوا → محرّر الجرعة', () {
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

    /// الاسم ثم «كمّل» → محرّر الجرعة (جرعة واحدة قبل الأكل).
    Future<void> pumpEditor(WidgetTester tester, {String name = 'Concor 5mg'}) async {
      await pumpAdd(tester);
      await tester.enterText(find.byType(TextField).first, name);
      await tester.pumpAndSettle();
      await tester.tap(find.text('كمّل — إمتى؟'));
      await settle(tester);
      expect(find.byType(DoseEditor), findsOneWidget);
    }

    screenTest('الحقول الأول، ومفيش منتقي ساعة ولا مراسي قبل «كمّل»', (tester) async {
      await pumpAdd(tester);
      expect(find.text('ضيف دوا وجرعته'), findsOneWidget);
      expect(find.text('كام مرة في اليوم؟'), findsOneWidget);
      expect(find.text('مع الأكل؟'), findsOneWidget);
      expect(find.text('مفتوحة'), findsOneWidget);
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.byType(TimeWheel), findsNothing);
      expectNoRedAndMinSize(tester);
    });

    screenTest('المرساة هي المدخل الأساسي في المحرّر، بالترتيب، والنشطة ذهبية — ومفيش منتقي ساعة',
        (tester) async {
      await pumpEditor(tester);

      expect(find.text('إمتى؟'), findsOneWidget);
      expect(find.text('Concor 5mg'), findsOneWidget);
      expect(find.text('اختار المرساة الأول — الساعة بتتحسب لوحدها.'), findsOneWidget);
      final labels = [for (final c in anchorChoices) c.label];
      expect(labels, anchorChipLabels, reason: 'ترتيب التصميم');
      for (final label in labels) {
        expect(find.widgetWithText(AnchorChip, label), findsOneWidget);
      }
      final active = tester.widget<Material>(find
          .descendant(of: find.widgetWithText(AnchorChip, 'قبل الفطار'), matching: find.byType(Material))
          .first);
      expect(active.color, F.gold);
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.byType(TimeWheel), findsNothing);
      // العدّاد بكلمة مش أيقونة لوحدها
      expect(find.text('أقل'), findsOneWidget);
      expect(find.text('أكتر'), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expectNoRedAndMinSize(tester);
    });

    screenTest('المعاينة بتتحرك مع المرساة والإزاحة', (tester) async {
      await pumpEditor(tester);

      // قبل الفطار بـ٣٠ = ٧:٠٠ ص
      expect(find.text('يعني حوالي ٧:٠٠ ص'), findsOneWidget);

      await tester.tap(find.text('بعد العشا'));
      await tester.pumpAndSettle();
      expect(find.text('يعني حوالي ٨:٣٠ م'), findsOneWidget);

      await tester.tap(find.text('أكتر'));
      await tester.pumpAndSettle();
      expect(find.text('يعني حوالي ٨:٣٥ م'), findsOneWidget);
    });

    screenTest('«قبل النوم» بتاخد ١٥ دقيقة، والوجبات ٣٠', (tester) async {
      await pumpEditor(tester);
      expect(find.text('٣٠ دقيقة'), findsOneWidget); // قبل الفطار

      await tester.tap(find.text('قبل النوم'));
      await tester.pumpAndSettle();
      expect(find.text('١٥ دقيقة'), findsOneWidget);
      // نوم ١١:٣٠ م − ١٥ = ١١:١٥ م
      expect(find.text('يعني حوالي ١١:١٥ م'), findsOneWidget);

      await tester.tap(find.text('قبل الغدا'));
      await tester.pumpAndSettle();
      expect(find.text('٣٠ دقيقة'), findsOneWidget);
    });

    screenTest('المدة المفتوحة هي الافتراضي وبتتخزّن null', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('احفظ الجرعة'));
      await settle(tester);

      final saved = (await meds.activeSchedules(services.patientId)).single;
      expect(saved.medicationName, 'Concor 5mg');
      expect(saved.durationDays, isNull);
      expect(saved.timing, const AnchorTiming(DayAnchor.breakfast, -30));
    });

    screenTest('من غير اسم «كمّل» مقفولة', (tester) async {
      await pumpAdd(tester);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    screenTest('٣ مرات مع الأكل → تلات محرّرات بالترتيب وتلات جداول على دوا واحد بإزاحة صفر',
        (tester) async {
      await pumpAdd(tester);
      await tester.enterText(find.byType(TextField).first, 'Augmentin');
      await tester.tap(find.text('٣ مرات'));
      await tester.tap(find.text('مع الأكل'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('كمّل — إمتى؟'));
      await settle(tester);

      expect(find.text('الجرعة ١ من ٣'), findsOneWidget);
      expect(find.text('٠ دقيقة'), findsOneWidget, reason: 'مع الأكل = إزاحة صفر');
      expect(find.text('الجرعة اللي بعدها'), findsOneWidget);
      // ولا حاجة اتحفظت لسه
      expect(await meds.activeSchedules(services.patientId), isEmpty);

      await tester.tap(find.text('الجرعة اللي بعدها'));
      await settle(tester);
      expect(find.text('الجرعة ٢ من ٣'), findsOneWidget);
      await tester.tap(find.text('الجرعة اللي بعدها'));
      await settle(tester);
      expect(find.text('الجرعة ٣ من ٣'), findsOneWidget);
      expect(await meds.activeSchedules(services.patientId), isEmpty, reason: 'الحفظ بعد الأخيرة بس');

      await tester.tap(find.text('احفظ الجرعة'));
      await settle(tester);

      final saved = await meds.activeSchedules(services.patientId);
      expect(saved.length, 3);
      expect(saved.map((s) => s.medicationName).toSet(), {'Augmentin'});
      expect(saved.map((s) => s.timing).toList(), [
        const AnchorTiming(DayAnchor.breakfast, 0),
        const AnchorTiming(DayAnchor.lunch, 0),
        const AnchorTiming(DayAnchor.dinner, 0),
      ]);
    });

    screenTest('رجع من المحرّر في النص → ولا دوا اتحفظ', (tester) async {
      await pumpAdd(tester);
      await tester.enterText(find.byType(TextField).first, 'Augmentin');
      await tester.tap(find.text('مرتين'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('كمّل — إمتى؟'));
      await settle(tester);
      await tester.tap(find.text('الجرعة اللي بعدها'));
      await settle(tester);
      expect(find.text('الجرعة ٢ من ٢'), findsOneWidget);

      await tester.pageBack();
      await settle(tester);
      expect(find.byType(AddMedicationScreen), findsOneWidget);
      expect(await meds.activeSchedules(services.patientId), isEmpty);
    });

    screenTest('لينك الساعة الثابتة آخر حاجة — تحت «احفظ الجرعة»', (tester) async {
      await pumpEditor(tester);

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
      await pumpEditor(tester);

      await tester.tap(find.text('أحدد ساعة ثابتة بدل كده'));
      await tester.pumpAndSettle();

      expect(find.text('ساعة ثابتة — مش هتتحرك مع روتين يومك'), findsOneWidget);
      expect(find.byType(TimeWheel), findsOneWidget);
      expect(find.text('قبل الفطار'), findsNothing);
      expect(find.text('أحدد ساعة ثابتة بدل كده'), findsNothing);
      expect(find.text('يعني حوالي ٨:٠٠ ص'), findsOneWidget);

      // والرجوع للمراسي متاح
      await tester.tap(find.text('ارجع للمراسي'));
      await tester.pumpAndSettle();
      expect(find.text('قبل الفطار'), findsOneWidget);
      expect(find.text('ساعة ثابتة — مش هتتحرك مع روتين يومك'), findsNothing);
    });

    screenTest('الحفظ في وضع الساعة الثابتة بيخزّن FixedTiming', (tester) async {
      await pumpEditor(tester, name: 'Eltroxin');
      await tester.tap(find.text('أحدد ساعة ثابتة بدل كده'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('احفظ الجرعة'));
      await settle(tester);

      final saved = (await meds.activeSchedules(services.patientId)).single;
      expect(saved.timing, FixedTiming(MinuteOfDay.hm(8)));
    });
  });
}
