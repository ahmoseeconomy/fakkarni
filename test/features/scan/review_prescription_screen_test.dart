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

  screenTest('اللي ثقته قليلة بالذهبي و«محتاج تحديد» وملاحظته «اسأل الصيدلي»',
      (tester) async {
    await pumpReview(tester, [unclearLine]);
    await open(tester);

    expect(find.text('فهمت الروشتة كده'), findsOneWidget);
    expect(find.text('محتاج تحديد'), findsOneWidget);
    expect(find.text(unclearTimingNote), findsOneWidget);

    final flag = tester.widget<Text>(find.text('محتاج تحديد'));
    expect(flag.style?.color, F.gold);
    final note = tester.widget<Text>(find.text(unclearTimingNote));
    expect(note.style?.color, F.gold);
    // الحقول الواضحة مش ذهبية
    final name = tester.widget<Text>(find.text('Cataflam'));
    expect(name.style?.color, F.ink);
    expectNoRedAndMinSize(tester);
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
          find.ancestor(of: find.text('تمام'), matching: find.byType(FilledButton)),
        );
    expect(confirm().onPressed, isNull);
    expect(find.textContaining('مش واضح — دوس'), findsOneWidget);
  });

  screenTest('«أعدّل» و«تمام» بنفس الحجم بالظبط', (tester) async {
    await pumpReview(tester, [clearLine]);
    await open(tester);

    final edit = tester.getSize(
      find.ancestor(of: find.text('أعدّل'), matching: find.byType(FilledButton)),
    );
    final confirm = tester.getSize(
      find.ancestor(of: find.text('تمام'), matching: find.byType(FilledButton)),
    );
    expect(edit, confirm);
    expect(edit.height, F.primaryButtonHeight);
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

    await tester.tap(find.text('تمام'));
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

  screenTest('«أعدّل السطر ده» بتفتح المحرر متعبّي، والحفظ منه بيعلّم السطر «اتضاف»',
      (tester) async {
    await pumpReview(tester, [unclearLine]);
    await open(tester);

    await tester.tap(find.text('أعدّل السطر ده'));
    await settle(tester);

    expect(find.byType(AddMedicationScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Cataflam'), findsOneWidget);

    await tester.tap(find.text('احفظ الجرعة'));
    await settle(tester);

    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
    expect(find.text('اتضاف'), findsOneWidget);
    // دلوقتي مفيش سطر معلّق → «تمام» مفتوحة
    final confirm = tester.widget<FilledButton>(
      find.ancestor(of: find.text('تمام'), matching: find.byType(FilledButton)),
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
        find.ancestor(of: find.text('تمام'), matching: find.byType(FilledButton)),
      );
      expect(confirm.onPressed, isNotNull);
      expect(find.text('هتتحفظ من غير الجرعة — تقدر تضيفها بعدين'), findsOneWidget);
      expect(find.textContaining('مش واضح — دوس'), findsNothing);
      // لسه ذهبية بملاحظتها
      expect(find.text('محتاج تحديد'), findsOneWidget);
      expect(find.text('الورقة مش كاتبة الجرعة'), findsOneWidget);
    });

    screenTest('«تمام» بتحفظها من غير جرعة ومعلّمة «مش معروفة» — مفيش قيمة مخترعة', (tester) async {
      await pumpReview(tester, [unknownAmount]);
      await open(tester);

      await tester.tap(find.text('تمام'));
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
        find.ancestor(of: find.text('تمام'), matching: find.byType(FilledButton)),
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
