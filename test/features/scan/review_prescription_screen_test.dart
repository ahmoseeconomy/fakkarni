import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
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
    expect(find.textContaining('في سطر محتاج تحديد'), findsOneWidget);
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
}
