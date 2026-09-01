import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/features/scan/review_prescription_screen.dart';
import 'package:fakkarni/features/scan/scan_prescription_screen.dart';

import 'scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  final bytes = Uint8List.fromList([1, 2, 3]);

  Future<void> pumpScan(
    WidgetTester tester, {
    required PrescriptionReader? reader,
    Future<Uint8List?> Function(ImageSource)? pick,
  }) =>
      h.pump(
        tester,
        ScanPrescriptionScreen(
          routine: normalDay,
          reader: reader,
          today: aug31,
          pickImage: pick ?? (_) async => bytes,
        ),
      );

  screenTest('نصيحة التصوير قبل الكاميرا، والتأكيد بإيد إنسان مكتوب', (tester) async {
    await pumpScan(tester, reader: FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine])));

    expect(find.text('حطها على سطح مستوي والنور يكون كويس'), findsOneWidget);
    expect(find.textContaining('مفيش دوا بيتضاف'), findsOneWidget);
    expect(find.text('افتح الكاميرا'), findsOneWidget);
    expect(find.text('اختار من الصور'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('مفيش مفتاح → رسالة --dart-define واضحة، ومفيش كاميرا', (tester) async {
    await pumpScan(tester, reader: null);

    expect(find.textContaining('--dart-define=GEMINI_API_KEY'), findsOneWidget);
    expect(find.text('افتح الكاميرا'), findsNothing);
  });

  screenTest('صورة → قراءة → شاشة المراجعة', (tester) async {
    final reader = FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine]));
    await pumpScan(tester, reader: reader);

    await tester.tap(find.text('افتح الكاميرا'));
    await settle(tester);

    expect(reader.calls, 1);
    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
    expect(find.text('Concor 5mg'), findsOneWidget);
  });

  screenTest('رجع من الكاميرا من غير صورة → ولا طلب', (tester) async {
    final reader = FakeReader(() async => throw StateError('ما كانش المفروض'));
    await pumpScan(tester, reader: reader, pick: (_) async => null);

    await tester.tap(find.text('افتح الكاميرا'));
    await settle(tester);

    expect(reader.calls, 0);
    expect(find.byType(ScanPrescriptionScreen), findsOneWidget);
  });

  screenTest('القراءة فشلت → رسالتها من غير أحمر وزرار «صوّر تاني»', (tester) async {
    final reader = FakeReader(() async => throw const PrescriptionReadException('مقدرتش أقرا الروشتة دلوقتي — صوّر تاني.'));
    await pumpScan(tester, reader: reader);

    await tester.tap(find.text('افتح الكاميرا'));
    await settle(tester);

    expect(find.text('مقدرتش أقرا الروشتة دلوقتي — صوّر تاني.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'صوّر تاني'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«صوّر تاني» من المراجعة بتفتح الكاميرا تاني', (tester) async {
    final reader = FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [unclearLine]));
    var picks = 0;
    await pumpScan(tester, reader: reader, pick: (_) async {
      picks++;
      return bytes;
    });

    await tester.tap(find.text('افتح الكاميرا'));
    await settle(tester);
    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);

    await tester.tap(find.text('صوّر تاني'));
    await settle(tester);

    expect(picks, 2);
    expect(reader.calls, 2);
  });
}
