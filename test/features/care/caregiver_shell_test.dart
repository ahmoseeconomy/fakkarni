import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/app/app_scope.dart';
import 'package:fakkarni/app/shell.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/care/caregiver_remote.dart';
import 'package:fakkarni/data/care/supabase_caregiver_remote.dart' show medicationFromRow;
import 'package:fakkarni/data/db/app_database.dart';
import 'package:fakkarni/data/repositories/dose_event_repository.dart';
import 'package:fakkarni/data/repositories/medication_repository.dart';
import 'package:fakkarni/data/repositories/routine_repository.dart';
import 'package:fakkarni/data/services/reminder_scheduler.dart';

import '../../app/root_test.dart' show SilentSink;
import '../scan/scan_test_support.dart' show settle, screenTest;
import 'caregiver_screen_test.dart' show FakeCaregiverRemote, event, now;

/// D4: الابن بيتابع، ما بيكتبش. أي زرار ممكن يغيّر بيانات الأب **مش موجود
/// خالص** — مش متعطّل. الاختبار بيمشي على كل حاجة بتتداس في الشجرة (على
/// التبويبين) وبيقرا الكلام اللي جواها: المسموح بس التنقّل والخروج من الحساب.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  // التبويبات والخروج — **ومداخل الملف الصحي**: دي بتفتح قايمة قراية،
  // مش زرار بيكتب في بيانات الأب. أي كلمة تانية قابلة للدوس غلط.
  const allowedTaps = {
    'متابعة',
    'السجل',
    'الإعدادات',
    'الأدوية',
    'تسجيل الخروج',
    // **إعادة سؤال، مش كتابة.** «حدّث» و«حاول تاني» بيندهوا نفس
    // `holder.refresh` اللي السحب لتحت بينده عليه — قراية من السحابة
    // وخلاص. ولا واحد منهم بيلمس ولا صف من بيانات الأب.
    'حدّث',
    'حاول تاني',
    // فحص سلامة الموبايل ده هو — بيقرا إذن التنبيهات وتوكن الدفع
    // بتوع موبايل الابن، وما بيلمسش ولا صف من بيانات الأب.
    'اطمن إن التنبيه هيوصلك',
    'تحاليل',
    'روشتات',
    'زيارات',
    'أشعة',
    'حجوزات',
    'قياسات السكر — آخر ٣٠ يوم',
    // القياسات الحيوية (٠٠٢٧) — مدخل قراية زي السكر
    'القياسات — الضغط والوزن وغيرهم',
    'أسئلة للدكتور',
  };

  Set<String> tappableTexts(WidgetTester tester) {
    final texts = <String>{};
    final tappables = [
      ...tester.widgetList<InkWell>(find.byType(InkWell)).map((w) => (w, w.onTap != null)),
      ...tester.widgetList<GestureDetector>(find.byType(GestureDetector)).map((w) => (w, w.onTap != null)),
    ];
    for (final (widget, live) in tappables) {
      if (!live) continue;
      for (final t in tester.widgetList<Text>(find.descendant(of: find.byWidget(widget), matching: find.byType(Text)))) {
        texts.add((t.data ?? t.textSpan?.toPlainText() ?? '').trim());
      }
    }
    // العدد اللي جنب المدخل جزء من اسمه، مش زرار لوحده — «٢» مش فعل.
    // الحارس لسه بيمسك أي **كلمة** قابلة للدوس مش مسموح بيها.
    texts.removeWhere((t) => RegExp(r'^[\u0660-\u0669]+$').hasMatch(t));
    return texts..remove('');
  }

  screenTest('تطبيق الابن: أربع تبويبات، ولا زرار بيكتب في بيانات الأب — على الأربعة', (tester) async {
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
          event('Concor 5mg', DateTime(2026, 8, 31, 7), 'taken', actedAt: DateTime(2026, 8, 31, 7, 5)),
          event('Glucophage', DateTime(2026, 8, 31, 9), 'missed'),
          event('Glucophage', DateTime(2026, 8, 31, 12), 'pending'),
          event('Concor 5mg', DateTime(2026, 8, 31, 20), 'pending'),
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
            doctor: 'د. سامي',
            labLines: const [CaregiverLabLine(testName: 'HbA1c', value: 7.1, unit: '%')],
          ),
        ],
        readings: [
          CaregiverReading(
            uuid: 'g1',
            valueMgDl: 128,
            measuredAt: DateTime(2026, 8, 31, 8),
            context: 'fasting',
            updatedAt: DateTime(2026, 8, 31, 8, 5),
          ),
        ],
        emergency: const CaregiverEmergency(bloodType: 'O+', allergies: 'بنسلين'),
        questions: [
          CaregiverQuestion(
            uuid: 'q1',
            body: 'ينفع أوقف الملح؟',
            writtenAt: DateTime(2026, 8, 30),
            asked: false,
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
        child: MaterialApp(
          theme: F.light,
          builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          home: CaregiverShell(onNotLinked: () {}, now: now),
        ),
      ),
    );
    await settle(tester);

    // «متابعة» بقت عن الحالة وبس — الأدوية بقت تبويب لوحده (جولة ٢٩)
    expect(find.text('متابعة الحاج أحمد'), findsOneWidget);
    expect(find.textContaining('والدك ما أكّدش جرعة Glucophage'), findsOneWidget);
    expect(find.text('قرص واحد — الفطار − ٣٠ د'), findsNothing,
        reason: 'باب واحد للأوضة: القايمة اتنقلت، ما اتنسختش');

    // ومفيش حاجة بتتكتب
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    for (final word in ['ضيف', 'عدّل', 'وقّف', 'امسح', 'رجّعه', 'أخدته', 'تأكيد الجرعة', 'مش هاخده', 'احفظ', 'طوارئ', 'يومك']) {
      expect(find.textContaining(word), findsNothing, reason: '«$word» مالوش مكان عند الابن');
    }
    expect(tappableTexts(tester).difference(allowedTaps), isEmpty);

    // تبويب الأدوية: القايمة بقواعدها، ومفيش ولا زرار بيغيّر حاجة
    await tester.tap(find.text('الأدوية'));
    await settle(tester);
    expect(find.text('قرص واحد — الفطار − ٣٠ د'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    for (final word in ['ضيف', 'عدّل', 'وقّف', 'امسح', 'احفظ']) {
      expect(find.textContaining(word), findsNothing, reason: '«$word» مالوش مكان عند الابن');
    }
    expect(tappableTexts(tester).difference(allowedTaps), isEmpty);

    await tester.tap(find.text('السجل'));
    await settle(tester);
    expect(find.byKey(const ValueKey('emergency-facts')), findsOneWidget);
    // الملف بقى مداخل: المحتوى جوّه قايمة كل مدخل
    expect(find.byKey(const ValueKey('care-entry-lab')), findsOneWidget);
    expect(find.byKey(const ValueKey('care-entry-questions')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Image), findsNothing, reason: 'الصور في D5.3 — ولا مكان فاضي ولا صورة مكسورة');
    for (final word in ['ضيف', 'عدّل', 'امسح', 'رجّعه', 'اتصال', 'الإسعاف', 'احفظ', 'خيارات']) {
      expect(find.textContaining(word), findsNothing, reason: '«$word» مالوش مكان عند الابن');
    }
    expect(tappableTexts(tester).difference(allowedTaps), isEmpty);

    await tester.tap(find.text('الإعدادات'));
    await settle(tester);
    expect(find.text('حسابك'), findsOneWidget);
    // «الملف الصحي» هنا اسم تبويب الابن نفسه — الصفوف اللي بتخص مريض على الموبايل ده هي الممنوعة
    for (final word in ['مواعيد يومك', 'رمضان', 'نمط كبار السن', 'التنبيهات', 'معلومات الطوارئ', 'قريب منك']) {
      expect(find.textContaining(word), findsNothing, reason: '«$word» بيخص مريض على الموبايل ده');
    }
    expect(tappableTexts(tester).difference(allowedTaps), isEmpty);
  });

  group('قواعد أدوية الأب من صف السحابة — نص، مش ساعة محسوبة', () {
    test('مرساة بإزاحة، مرساة من غير إزاحة، وساعة ثابتة بساعتها المكتوبة', () {
      final med = medicationFromRow({
        'uuid': 'm1',
        'name': 'Concor 5mg',
        'amount_label': 'قرص واحد',
        'dose_schedules': [
          {'timing_kind': 'anchor', 'anchor': 'breakfast', 'offset_minutes': -30, 'fixed_timings': null},
          {'timing_kind': 'anchor', 'anchor': 'dinner', 'offset_minutes': 0, 'fixed_timings': null},
          {
            'timing_kind': 'fixed',
            'anchor': null,
            'offset_minutes': null,
            'fixed_timings': {'minute_of_day': 8 * 60},
          },
        ],
      });

      expect(med.rules, ['الفطار − ٣٠ د', 'العشا', 'ساعة ثابتة — ٨:٠٠ ص']);
      expect(med.amountLabel, 'قرص واحد');
    });

    test('٠٠٢٨: المخزون من الـembed — قراية بس، والأيام من جداوله اليومية', () {
      final med = medicationFromRow({
        'uuid': 'm1',
        'name': 'Concor',
        'amount_label': 'قرص واحد',
        'medication_stock': {'quantity': 8, 'warn_days': null},
        'dose_schedules': [
          {'timing_kind': 'anchor', 'anchor': 'breakfast', 'offset_minutes': 0, 'repeat': 'daily', 'fixed_timings': null},
          {'timing_kind': 'anchor', 'anchor': 'dinner', 'offset_minutes': 0, 'repeat': 'daily', 'fixed_timings': null},
        ],
      });
      expect((med.stockQuantity, med.dosesPerDay, med.stockDaysLeft, med.stockLow), (8.0, 2, 4, true));
      expect(med.stockLine, 'Concor فاضله ٤ أيام');
      final none = medicationFromRow({'uuid': 'm2', 'name': 'X', 'amount_label': null});
      expect(none.stockLine, isNull, reason: 'من غير مخزون متكتب مفيش سطر');
    });

    test('من غير جداول → من غير قواعد (ما بنخمّنش)', () {
      final med = medicationFromRow({'uuid': 'm1', 'name': 'X', 'amount_label': null});
      expect(med.rules, isEmpty);
    });
  });
}
