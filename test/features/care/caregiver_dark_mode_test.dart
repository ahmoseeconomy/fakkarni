import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/theme_mode_store.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';

import '../../app/root_test.dart' show SilentSink;
import '../scan/scan_test_support.dart' show settle, screenTest;
import 'caregiver_screen_test.dart' show FakeCaregiverRemote, event, now;

/// **الوضع الليلي عند الابن — نفس المفتاح، نفس التخزين، نفس الويدجت.**
///
/// مفيش آلية تانية ولا مفتاح `shared_preferences` تاني ولا علم خاص بالابن:
/// الإعداد بتاع الموبايل ده، أي دور اشتغل عليه. الاختبار بيثبت التلاتة —
/// إن الدوسة بتقلب `F.darkMode`، وإنها بتوصل `ui.dark` (نفس مفتاح الأب)،
/// وإن التبويبات الأربعة بتترسم في الليل من غير نص غايب.
///
/// **وليه مكانين مش مكان واحد:** عند الأب المفتاح في شريط الهيكل، اللي
/// ظاهر فوق كل تبويب. عند الابن مفيش شريط هيكل — كل تبويب ليه شريطه،
/// و«الإعدادات» مالهاش شريط أصلاً. فشريط «متابعة» بيغطي التبويب اللي
/// بيفتح عليه، وصف الإعدادات هو الوحيد اللي بيتوصّل له من أي تبويب.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() async {
    await db.close();
    F.setDark(on: false);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final routines = RoutineRepository(db);
    final meds = MedicationRepository(db);
    final events = DoseEventRepository(db);
    final patientId = await routines.ensurePatient();
    final remote = FakeCaregiverRemote()
      ..next = CaregiverSnapshot(
        patient: const CaregiverPatient(uuid: 'p1', name: 'الحاج أحمد'),
        medications: const [
          CaregiverMedication(uuid: 'm1', name: 'Concor 5mg', amountLabel: 'قرص واحد', rules: ['الفطار − ٣٠ د']),
        ],
        events: [
          // مأخوذة: دي اللي كان لونها `greenDeep` الثابت — ١.٥١:١ في الليل
          event('Concor 5mg', DateTime(2026, 8, 31, 7), 'taken', actedAt: DateTime(2026, 8, 31, 7, 5)),
          event('Glucophage', DateTime(2026, 8, 31, 9), 'missed'),
        ],
        alerts: [
          CaregiverAlert(
            uuid: 'a1',
            medicationName: 'Glucophage',
            scheduledAt: DateTime(2026, 8, 31, 9),
            doseState: 'missed',
            deliveryStatus: 'no_token',
            createdAt: DateTime(2026, 8, 31, 10),
          ),
        ],
        lastUpdated: DateTime(2026, 8, 31, 13),
        records: [
          CaregiverRecord(
            uuid: 'r1',
            kind: 'lab',
            title: 'تحليل سكر تراكمي',
            happenedAt: DateTime(2026, 8, 20),
            updatedAt: DateTime(2026, 8, 31, 12),
            labLines: const [CaregiverLabLine(testName: 'HbA1c', value: 7.1, unit: '%')],
          ),
        ],
        questions: [
          // «اتسأل ✓» — التاني اللي كان `greenDeep`
          CaregiverQuestion(
            uuid: 'q1',
            body: 'ينفع أوقف الملح؟',
            writtenAt: DateTime(2026, 8, 30),
            asked: true,
            updatedAt: DateTime(2026, 8, 30, 9),
          ),
        ],
      );

    await tester.pumpWidget(
      AppScope(
        services: AppServices(
          db: db,
          routines: routines,
          medications: meds,
          events: events,
          scheduler: ReminderScheduler(
            routines: routines,
            medications: meds,
            events: events,
            patientId: patientId,
            sink: SilentSink(),
          ),
          patientId: patientId,
          caregiver: remote,
        ),
        // نفس تركيب `main`: الجذر بيعيد البناء بمفتاح على الوضع، وإلا
        // شجرة `const` ما بتتبنيش تاني والقلبة ما بتبانش.
        child: ValueListenableBuilder<bool>(
          valueListenable: F.darkMode,
          builder: (context, dark, _) => KeyedSubtree(
            key: ValueKey(dark),
            child: MaterialApp(
              theme: F.light,
              builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
              home: CaregiverShell(onNotLinked: () {}, now: now),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  screenTest('الدوسة على شريط «متابعة» بتقلب الوضع وبتتخزّن في نفس المفتاح', (tester) async {
    await pumpShell(tester);
    expect(F.isDark, isFalse);

    expect(find.byKey(const ValueKey('dark-mode-toggle')), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('dark-mode-toggle')).first);
    await settle(tester);

    expect(F.isDark, isTrue, reason: 'الدوسة المفروض تقلب الوضع');
    // **نفس مفتاح الأب** — مش مفتاح تاني للابن
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ui.dark'), isTrue);

    // وبترجع
    await tester.tap(find.byKey(const ValueKey('dark-mode-toggle')).first);
    await settle(tester);
    expect(F.isDark, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('ui.dark'), isFalse);
  });

  screenTest('صف «الوضع الليلي» في إعدادات الابن بيقلب نفس القلبة', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('الإعدادات'));
    await settle(tester);

    expect(find.text('الوضع الليلي'), findsOneWidget);
    expect(find.text('مقفول'), findsOneWidget);

    // مفتاح الصف هو **نفس الويدجت**، مش نسخة: بندوس اللي جوّه الصف
    final rowToggle = find.descendant(
      of: find.ancestor(of: find.text('الوضع الليلي'), matching: find.byType(Row)).first,
      matching: find.byKey(const ValueKey('dark-mode-toggle')),
    );
    expect(rowToggle, findsOneWidget);
    await tester.tap(rowToggle);
    await settle(tester);

    expect(F.isDark, isTrue);
    expect((await SharedPreferences.getInstance()).getBool('ui.dark'), isTrue);

    // **والقلبة بترجّعه لأول تبويب** — مش قرار اتاخد هنا: `main` بيحط
    // مفتاح على الوضع (`KeyedSubtree(key: ValueKey(dark))`) عشان الشجر
    // الـ`const` يتبني تاني، والمفتاح ده بيرمي كل الـState ومعاه التبويب
    // المختار. نفس الحاجة بتحصل عند الأب من قبل الجولة دي. الاختبار
    // بيثبّت السلوك ده بالاسم بدل ما يخبّيه.
    expect(find.text('الوضع الليلي'), findsNothing, reason: 'رجع لتبويب «متابعة»');
    await tester.tap(find.text('الإعدادات'));
    await settle(tester);
    expect(find.text('شغّال'), findsOneWidget);
  });

  /// **ولا سطر نص معروض دلوقتي تحت ٤.٥:١ على أي أرضية.**
  ///
  /// بتتنده بعد **كل** تبويب. أول نسخة كانت بتنده مرة واحدة في الآخر،
  /// و`find.byType(Text)` بيعدّي على المعروض بس — فالتبويب اللي فيه
  /// «اتاخد» كان offstage وقتها، والحارس كان **بيعدّي فاضي**: رجّعنا
  /// `F.greenDeep` وما وقعش. حارس شرطه عمره ما بيتحقّق مش حارس.
  void expectReadable(WidgetTester tester, String where) {
    final grounds = [F.pageGround, F.cardGround, F.railGround];
    var checked = 0;
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final colour = text.style?.color;
      if (colour == null) continue;
      checked++;
      final best = grounds.map((g) => _contrast(colour, g)).reduce(math.max);
      expect(
        best,
        greaterThanOrEqualTo(4.5),
        reason: '«$where»: نص «${text.data}» بلون $colour مالوش تباين كافي في الليل',
      );
    }
    expect(checked, greaterThan(0), reason: '«$where»: مفيش ولا نص بلون — الحارس عدّى فاضي');
  }

  screenTest('التبويبات الأربعة بتترسم في الليل — ومفيش نص بيختفي', (tester) async {
    F.setDark(on: true);
    await pumpShell(tester);
    expect(F.isDark, isTrue);

    // «متابعة»: التنبيه، وحالة الجرعة المأخوذة — دي اللي كان لونها
    // `F.greenDeep` الثابت: ٩.٣٨:١ في النهار و**١.٥١:١** في الليل على
    // الكارت، يعني «اتاخد» كانت بتختفي خالص.
    expect(find.textContaining('والدك ما أكّدش جرعة Glucophage'), findsOneWidget);
    expect(find.textContaining('اتاخد'), findsOneWidget);
    expect(find.textContaining('اتنست'), findsWidgets);
    expectReadable(tester, 'متابعة');

    await tester.tap(find.text('الأدوية'));
    await settle(tester);
    expect(find.text('قرص واحد — الفطار − ٣٠ د'), findsOneWidget);
    expectReadable(tester, 'الأدوية');

    await tester.tap(find.text('السجل'));
    await settle(tester);
    expect(find.byKey(const ValueKey('care-entry-questions')), findsOneWidget);
    expectReadable(tester, 'السجل');

    await tester.tap(find.byKey(const ValueKey('care-entry-questions')));
    await settle(tester);
    // «اتسأل ✓» — التاني اللي كان `greenDeep`
    expect(find.text('اتسأل ✓'), findsOneWidget);
    expectReadable(tester, 'أسئلة للدكتور');

    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('الإعدادات'));
    await settle(tester);
    expect(find.text('الوضع الليلي'), findsOneWidget);
    expectReadable(tester, 'الإعدادات');
  });

  screenTest('القلبة من شريط «متابعة» بتوصل كل التبويبات — إعداد واحد للموبايل', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('dark-mode-toggle')).first);
    await settle(tester);
    expect(F.isDark, isTrue);

    await tester.tap(find.text('الإعدادات'));
    await settle(tester);
    // الصف بيقرا من نفس المصدر — مفيش علم تاني للابن
    expect(find.text('شغّال'), findsOneWidget);
    expect(ThemeModeStore, isNotNull);
  });
}
