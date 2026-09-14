import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/scan/debug_panel.dart';
import 'package:fakkarni/features/scan/review_prescription_screen.dart';

import 'scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<Future<ReviewResult?> Function()> pumpReview(
    WidgetTester tester,
    List<ReadLine> lines,
  ) async {
    ReviewResult? result;
    final screen = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ReviewResult>(
                MaterialPageRoute(
                  builder: (_) => ReviewPrescriptionScreen(
                    reading: PrescriptionReading(
                      doctor: const ReadField.missing(),
                      lines: lines,
                    ),
                    routine: normalDay,
                    today: aug31,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await h.pump(tester, screen);
    return () async => result;
  }

  Future<void> open(WidgetTester tester) async {
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  screenTest('صف الثقة القليلة: حافة ذهبية + «مش متأكد من دي — راجعها» + الحقل وملاحظته',
      (tester) async {
    await pumpReview(tester, [unclearLine]);
    await open(tester);

    expect(find.text('الذكاء يقترح، وأنت تؤكّد'), findsOneWidget);
    expect(find.text('مش متأكد من دي — راجعها'), findsOneWidget);
    expect(find.byKey(const ValueKey('unsure-edge')), findsOneWidget);
    final edge = tester.widget<Container>(find.byKey(const ValueKey('unsure-edge')));
    expect(edge.color, F.gold);
    // الحقل بالاسم وملاحظته «اسأل الصيدلي» — مقروءة، مش ذهبي باهت
    expect(find.textContaining(unclearTimingNote, findRichText: true), findsOneWidget);
    expect(find.textContaining('التوقيت: ', findRichText: true), findsOneWidget);
    // الاسم نفسه واضح ومش ذهبي
    final name = tester.widget<Text>(find.text('Cataflam'));
    expect(name.style?.color, F.ink);
    expectNoRedAndMinSize(tester);
  });

  screenTest('صف لكل دوا: الاسم mono ٢٤+، الوقت المحسوب بأرقام عربي، والشريحة بالقاعدة', (tester) async {
    final line = ReadLine(
      name: ok('Antodine 40 mg'),
      amount: ok('قرص واحد'),
      timings: ok([const AnchorTiming(DayAnchor.breakfast, -30)]),
      duration: const ReadField(value: null, confidence: 1),
    );
    await pumpReview(tester, [line]);
    await open(tester);

    final name = tester.widget<Text>(find.text('Antodine 40 mg'));
    expect(name.style?.fontSize, greaterThanOrEqualTo(F.medicationNameSize));
    expect(name.style?.fontFamily, F.monoFamily);
    expect(name.textDirection, TextDirection.ltr);
    // الفطار ٧:٣٠ − ٣٠ = ٧:٠٠ ص — للعرض بس
    expect(find.text('٧:٠٠ ص'), findsOneWidget);
    expect(find.text('الفطار − ٣٠ د'), findsOneWidget, reason: 'القاعدة، مش الساعة');
    expect(find.widgetWithText(OutlinedButton, 'عدّل'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget, reason: 'أيقونة وكلمة');
    // الصف الواضح مفيهوش حافة شك
    expect(find.byKey(const ValueKey('unsure-edge')), findsNothing);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«أضف دوا ما اتعرفش عليه» بتفتح المحرر فاضي', (tester) async {
    await pumpReview(tester, [clearLine]);
    await open(tester);

    await tester.tap(find.text('أضف دوا ما اتعرفش عليه'));
    await settle(tester);
    expect(find.byType(AddMedicationScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Concor 5mg'), findsNothing);
  });

  screenTest('ولا حاجة بتتحفظ قبل الدوسة', (tester) async {
    await pumpReview(tester, [clearLine]);
    await open(tester);

    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
    expect(h.sink.scheduled, isEmpty);
  });

  screenTest('«تمام» مقفولة لما في سطر محتاج تحديد، ومفتوحة لما كله واضح',
      (tester) async {
    await pumpReview(tester, [clearLine, unclearLine]);
    await open(tester);

    FilledButton confirm() => tester.widget<FilledButton>(
          find.ancestor(of: find.text('تمام، ظبّطهم'), matching: find.byType(FilledButton)),
        );
    expect(confirm().onPressed, isNull);
    expect(find.textContaining('مش واضح — دوس'), findsOneWidget);
  });

  screenTest('«أعدّل» و«تمام، ظبّطهم» بنفس الوزن بالظبط — نفس المقاس، مليانين، نفس الخط', (tester) async {
    await pumpReview(tester, [clearLine]);
    await open(tester);

    final edit = tester.getSize(
      find.ancestor(of: find.text('أعدّل'), matching: find.byType(FilledButton)),
    );
    final confirm = tester.getSize(
      find.ancestor(of: find.text('تمام، ظبّطهم'), matching: find.byType(FilledButton)),
    );
    expect(edit, confirm);
    expect(edit.height, F.primaryButtonHeight);

    // مش لينك باهت: الاتنين FilledButton بتعبئة غامقة ونفس الخط
    FilledButton button(String label) => tester.widget<FilledButton>(
          find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
        );
    final e = button('أعدّل').style!, c = button('تمام، ظبّطهم').style!;
    Color bg(ButtonStyle st) => st.backgroundColor!.resolve({})!;
    expect(bg(e).computeLuminance(), lessThan(0.2), reason: '«أعدّل» مليان وغامق');
    expect(bg(c).computeLuminance(), lessThan(0.2));
    expect(e.textStyle!.resolve({}), c.textStyle!.resolve({}));
    expect(e.foregroundColor!.resolve({}), c.foregroundColor!.resolve({}));
  });

  screenTest('«تمام» بتحفظ السطور الواضحة — كل توقيت جدول — وبتعيد الجدولة',
      (tester) async {
    final thrice = ReadLine(
      name: ok('Augmentin'),
      amount: ok('قرص'),
      timings: ok([
        const AnchorTiming(DayAnchor.breakfast, 0),
        const AnchorTiming(DayAnchor.lunch, 0),
        const AnchorTiming(DayAnchor.dinner, 0),
      ]),
      duration: ok<int?>(7),
    );
    final result = await pumpReview(tester, [clearLine, thrice]);
    await open(tester);

    await tester.tap(find.text('تمام، ظبّطهم'));
    await settle(tester);

    final saved = await h.meds.activeSchedules(h.services.patientId);
    expect(saved.length, 4);
    final concor = saved.singleWhere((s) => s.medicationName == 'Concor 5mg');
    expect(concor.timing, const AnchorTiming(DayAnchor.breakfast, 0));
    expect(concor.durationDays, isNull, reason: 'مفتوحة زي ما الورقة سابتها');
    expect(concor.amountLabel, 'قرص واحد');
    final augmentin = saved.where((s) => s.medicationName == 'Augmentin');
    expect(augmentin.length, 3);
    expect(augmentin.every((s) => s.durationDays == 7), isTrue);

    expect(h.sink.scheduled, isNotEmpty, reason: 'اتجدولت بعد التأكيد');
    expect(await result(), ReviewResult.confirmed);
  });

  screenTest('«عدّل» في الصف بتفتح المحرر متعبّي، والحفظ منه بيعلّم الصف «اتضاف»',
      (tester) async {
    await pumpReview(tester, [unclearLine]);
    await open(tester);

    await tester.tap(find.text('عدّل'));
    await settle(tester);

    expect(find.byType(AddMedicationScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Cataflam'), findsOneWidget);

    await tester.tap(find.text('احفظ الجرعة'));
    await settle(tester);

    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
    expect(find.text('اتضاف'), findsOneWidget);
    // دلوقتي مفيش سطر معلّق → «تمام» مفتوحة
    final confirm = tester.widget<FilledButton>(
      find.ancestor(of: find.text('تمام، ظبّطهم'), matching: find.byType(FilledButton)),
    );
    expect(confirm.onPressed, isNotNull);
    expect((await h.meds.activeSchedules(h.services.patientId)).single.medicationName, 'Cataflam');
  });

  screenTest('«صوّر تاني» موجودة وبترجّع retake', (tester) async {
    final result = await pumpReview(tester, [unclearLine]);
    await open(tester);

    await tester.tap(find.text('صوّر تاني'));
    await settle(tester);

    expect(await result(), ReviewResult.retake);
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
  });

  group('مجهول بيقفل ومجهول ما بيقفلش', () {
    final unknownAmount = ReadLine(
      name: ok('Telfast 180 mg'),
      amount: const ReadField.missing('الورقة مش كاتبة الجرعة'),
      timings: ok([const AnchorTiming(DayAnchor.dinner, 0)]),
      duration: const ReadField(value: null, confidence: 1),
    );

    screenTest('جرعة مش معروفة بس → «تمام» مفتوحة والسطر الهادي تحتها', (tester) async {
      await pumpReview(tester, [unknownAmount]);
      await open(tester);

      final confirm = tester.widget<FilledButton>(
        find.ancestor(of: find.text('تمام، ظبّطهم'), matching: find.byType(FilledButton)),
      );
      expect(confirm.onPressed, isNotNull);
      expect(find.text('هتتحفظ من غير الجرعة — تقدر تضيفها بعدين'), findsOneWidget);
      expect(find.textContaining('مش واضح — دوس'), findsNothing);
      // لسه معلّمة بملاحظتها — ما اتنستش في صمت
      expect(find.text('مش متأكد من دي — راجعها'), findsOneWidget);
      expect(find.textContaining('الجرعة: الورقة مش كاتبة الجرعة', findRichText: true), findsOneWidget);
    });

    screenTest('«تمام» بتحفظها من غير جرعة ومعلّمة «مش معروفة» — مفيش قيمة مخترعة', (tester) async {
      await pumpReview(tester, [unknownAmount]);
      await open(tester);

      await tester.tap(find.text('تمام، ظبّطهم'));
      await settle(tester);

      final saved = (await h.meds.activeSchedules(h.services.patientId)).single;
      expect(saved.medicationName, 'Telfast 180 mg');
      expect(saved.amountLabel, isNull);
      final row = (await h.db.select(h.db.medications).get()).single;
      expect(row.amountUnknown, isTrue);
    });

    screenTest('توقيت مش واضح → لسه بيقفل، والسطر الهادي مش بيظهر', (tester) async {
      await pumpReview(tester, [unclearLine, unknownAmount]);
      await open(tester);

      final confirm = tester.widget<FilledButton>(
        find.ancestor(of: find.text('تمام، ظبّطهم'), matching: find.byType(FilledButton)),
      );
      expect(confirm.onPressed, isNull);
      expect(find.text('هتتحفظ من غير الجرعة — تقدر تضيفها بعدين'), findsNothing);
      expect(find.textContaining('مش واضح — دوس'), findsOneWidget);
    });
  });

  screenTest('تحذير تقاعد الموديل بيظهر في نسخة التطوير فوق', (tester) async {
    ReviewResult? result;
    await h.pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ReviewResult>(
                MaterialPageRoute(
                  builder: (_) => ReviewPrescriptionScreen(
                    reading: PrescriptionReading(
                      doctor: const ReadField.missing(),
                      lines: [clearLine],
                      modelWarning: 'pinned gemini-3.6-flash retired',
                    ),
                    routine: normalDay,
                    today: aug31,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await open(tester);

    expect(find.byType(DebugPanel), findsOneWidget);
    expect(find.text('pinned gemini-3.6-flash retired'), findsOneWidget);
    expect(result, isNull);
  });
}
