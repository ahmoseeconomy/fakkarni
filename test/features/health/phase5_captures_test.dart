// لقطات المرحلة ٥ (النتيجة النصية، المالك 1A) — PNG حقيقية من نفس الحزام،
// نهاري وليلي: شاشة «قراءة التقرير» وفيها «Negative» جنب رقم على نفس
// الصفحة — النص بالحرف من غير علامة ولا «المعتاد»، والرقم بكل عدّته.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/lab_reading.dart';
import 'package:fakkarni/ai/prescription_reading.dart' show ReadField;
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/features/health/lab_report_screen.dart';

import '../scan/scan_test_support.dart';

ReadField<T> sure<T>(T v) => ReadField(value: v, confidence: 0.95);

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(() async {
    F.setDark(on: false);
    await h.tearDown();
  });

  setUpAll(() async {
    final loader = FontLoader('Cairo');
    for (final f in [
      'Cairo-Regular.ttf',
      'Cairo-Medium.ttf',
      'Cairo-SemiBold.ttf',
      'Cairo-Bold.ttf',
      'Cairo-ExtraBold.ttf',
    ]) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture-root')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final file = File('build/capture/phase5/$name.png')..createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'night' : 'day';

    screenTest('لقطة $mode — «قراءة التقرير»: «Negative» بالحرف جنب رقم بنطاقه', (tester) async {
      F.setDark(on: dark);
      // طويلة شوية عشان الكارتين والزرارين يبانوا في لقطة واحدة
      tester.view.physicalSize = const Size(780, 2200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await h.pump(
        tester,
        RepaintBoundary(
          key: const ValueKey('capture-root'),
          child: LabReportScreen(
            today: DateTime(2026, 9, 15),
            reading: LabReading(
              lab: sure('معمل البرج'),
              date: sure(DateTime(2026, 9, 12)),
              lines: [
                LabLine(
                  test: sure('Pus Cells'),
                  value: const ReadField.missing(),
                  valueText: sure('Negative'),
                  unit: const ReadField.missing(),
                ),
                LabLine(
                  test: sure('HbA1c'),
                  value: sure(7.6),
                  unit: sure('%'),
                  refLow: sure(4),
                  refHigh: sure(6),
                ),
              ],
            ),
          ),
        ),
      );
      await settle(tester);
      await capture(tester, 'lab-text-result-$mode');
    });
  }
}
