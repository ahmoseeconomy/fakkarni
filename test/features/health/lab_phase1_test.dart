// المرحلة ١ (٥ أكتوبر ٢٠٢٦ مساءً) على شاشات التحاليل:
// (١) تاريخ ناقص/مش واضح = «هيتسجّل بتاريخ النهارده» بالذهبي **قبل** الدوسة —
//     زي شاشة الروشتة بالحرف (المالك 2A).
// (٢) صفحات فوق السقف ما بتتقصّش في صمت: «اتقرا أول ٤ صفحات بس.» (المالك 4A).
// (٣) وتثبيت قياس (ب) من خطوة القياس: تقرير من غير ولا نتيجة (أشعة MRI مثلاً)
//     «تمام، احفظه» مقفول — مفيش حاجة تتحفظ، والمخرج «صوّر تاني» بس.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/lab_reader.dart';
import 'package:fakkarni/ai/lab_reading.dart';
import 'package:fakkarni/ai/prescription_reading.dart' show ReadField;
import 'package:fakkarni/ai/prescription_reader.dart' show maxScanPages;
import 'package:fakkarni/core/format/arabic_time.dart' show arabicNumber;
import 'package:fakkarni/features/health/lab_report_screen.dart';
import 'package:fakkarni/features/health/scan_lab_screen.dart';

import '../scan/scan_test_support.dart';

class _Reader implements LabReportReader {
  _Reader(this.reading);
  final LabReading reading;
  @override
  Future<LabReading> read(Uint8List image,
          {String mimeType = 'image/jpeg', List<Uint8List> morePages = const []}) async =>
      reading;
}

LabLine _line() => const LabLine(
      test: ReadField(value: 'TSH', confidence: 0.95),
      value: ReadField(value: 1.2, confidence: 0.95),
      unit: ReadField(value: 'mIU/L', confidence: 0.95),
    );

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);
  final today = DateTime(2026, 10, 5);

  Future<void> pumpReport(WidgetTester tester, LabReading reading) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, LabReportScreen(reading: reading, today: today));
    await settle(tester);
  }

  screenTest('تاريخ ناقص = «هيتسجّل بتاريخ النهارده» بالذهبي قبل الدوسة', (tester) async {
    await pumpReport(tester, LabReading(date: const ReadField.missing(), lab: const ReadField.missing(), lines: [_line()]));
    expect(find.byKey(const ValueKey('date-fallback')), findsOneWidget);
    expect(find.textContaining('هيتسجّل بتاريخ النهارده'), findsOneWidget);
    expect(find.textContaining('٥ أكتوبر'), findsOneWidget, reason: 'اليوم نفسه مكتوب — مش وعد مبهم');
  });

  screenTest('تاريخ مستقبلي (١٢/٠٩ اللي اتقرت أمريكي) = نفس الملاحظة — مش تاريخ غلط صامت', (tester) async {
    final reading = LabReading.fromJson({
      'reportDate': {'value': '2026-12-09', 'confidence': 0.99},
      'results': [
        {
          'test': {'value': 'TSH', 'confidence': 0.95},
          'value': {'value': 1.2, 'confidence': 0.95},
          'unit': {'value': null, 'confidence': 0},
          'refLow': {'value': null, 'confidence': 0},
          'refHigh': {'value': null, 'confidence': 0},
          'refText': {'value': null, 'confidence': 0},
        },
      ],
    }, now: today);
    await pumpReport(tester, reading);
    expect(find.byKey(const ValueKey('date-fallback')), findsOneWidget);
    expect(find.textContaining('٩ ديسمبر'), findsNothing, reason: 'التاريخ المرفوض ما بيتعرضش كأنه سليم');
  });

  screenTest('تاريخ ماضي واثق = مفيش ملاحظة، والتاريخ معروض فوق', (tester) async {
    await pumpReport(
      tester,
      LabReading(
        date: ReadField(value: DateTime(2026, 9, 12), confidence: 0.95),
        lab: const ReadField.missing(),
        lines: [_line()],
      ),
    );
    expect(find.byKey(const ValueKey('date-fallback')), findsNothing);
    expect(find.textContaining('١٢ سبتمبر'), findsOneWidget);
  });

  screenTest('تقرير من غير ولا نتيجة (أشعة): «تمام، احفظه» مقفول — ولا ملاحظة تاريخ فوق فراغ', (tester) async {
    await pumpReport(tester, const LabReading(date: ReadField.missing(), lab: ReadField.missing(), lines: []));
    expect(find.textContaining('مفيش نتايج اتقرت'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.ancestor(of: find.text('تمام، احفظه'), matching: find.byType(FilledButton)),
    );
    expect(confirm.onPressed, isNull, reason: 'مفيش حاجة تتحفظ — مش بنكتب سجل فاضي');
    expect(find.byKey(const ValueKey('date-fallback')), findsNothing);
  });

  screenTest('صفحات فوق السقف: «اتقرا أول ٤ صفحات بس.» — مش قصّ صامت، وبتروح مع «امسح»', (tester) async {
    final six = [for (var i = 0; i < 6; i++) Uint8List.fromList([i])];
    await h.pump(
      tester,
      ScanLabScreen(
        reader: _Reader(LabReading(date: const ReadField.missing(), lab: const ReadField.missing(), lines: [_line()])),
        pickImage: (_) async => Uint8List.fromList([9]),
        pickImages: (limit) async => six,
        today: today,
      ),
    );
    await settle(tester);
    await tester.tap(find.text('اختار من الصور'));
    await settle(tester);
    expect(find.byKey(const ValueKey('pages-dropped')), findsOneWidget);
    // «٤» في الجملة مرآة maxScanPages — لو السقف اتغيّر الجملة تتغيّر معاه
    expect(
      find.textContaining('اتقرا أول ${arabicNumber(maxScanPages)} صفحات بس'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('pages-clear'))); // «ابدأ من الأول»
    await settle(tester);
    expect(find.byKey(const ValueKey('pages-dropped')), findsNothing, reason: 'مسح الصفحات بيمسح السطر');
  });

  screenTest('أربع صفحات بالظبط = مفيش سطر — السطر للقصّ بس', (tester) async {
    final four = [for (var i = 0; i < 4; i++) Uint8List.fromList([i])];
    await h.pump(
      tester,
      ScanLabScreen(
        reader: _Reader(LabReading(date: const ReadField.missing(), lab: const ReadField.missing(), lines: [_line()])),
        pickImage: (_) async => Uint8List.fromList([9]),
        pickImages: (limit) async => four.take(limit).toList(),
        today: today,
      ),
    );
    await settle(tester);
    await tester.tap(find.text('اختار من الصور'));
    await settle(tester);
    expect(find.byKey(const ValueKey('pages-dropped')), findsNothing);
  });
}
