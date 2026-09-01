import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/features/scan/review_prescription_screen.dart';
import 'package:fakkarni/features/scan/scan_prescription_screen.dart';

import 'scan_test_support.dart';

/// منصّة وهمية بتسجّل اللي ImagePicker بعته — عشان نثبت إن الكاميرا والمعرض
/// بيمرّوا بنفس القيود من غير جهاز.
class RecordingPickerPlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  final sources = <ImageSource>[];
  final options = <ImagePickerOptions>[];
  bool cancel = false;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    sources.add(source);
    this.options.add(options);
    return cancel ? null : XFile.fromData(Uint8List.fromList([1, 2, 3]));
  }
}

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
    expect(find.text('صوّر الروشتة'), findsOneWidget);
    expect(find.text('اختار من الصور'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('مفيش مفتاح → رسالة --dart-define واضحة، ومفيش كاميرا', (tester) async {
    await pumpScan(tester, reader: null);

    expect(find.textContaining('--dart-define=GEMINI_API_KEY'), findsOneWidget);
    expect(find.text('صوّر الروشتة'), findsNothing);
  });

  screenTest('صورة → قراءة → شاشة المراجعة', (tester) async {
    final reader = FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine]));
    await pumpScan(tester, reader: reader);

    await tester.tap(find.text('صوّر الروشتة'));
    await settle(tester);

    expect(reader.calls, 1);
    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
    expect(find.text('Concor 5mg'), findsOneWidget);
  });

  screenTest('رجع من الكاميرا من غير صورة → ولا طلب', (tester) async {
    final reader = FakeReader(() async => throw StateError('ما كانش المفروض'));
    await pumpScan(tester, reader: reader, pick: (_) async => null);

    await tester.tap(find.text('صوّر الروشتة'));
    await settle(tester);

    expect(reader.calls, 0);
    expect(find.byType(ScanPrescriptionScreen), findsOneWidget);
  });

  screenTest('القراءة فشلت → رسالتها من غير أحمر وزرار «صوّر تاني»', (tester) async {
    final reader = FakeReader(() async => throw const PrescriptionReadException(
          'مقدرتش أقرا الروشتة دلوقتي — صوّر تاني.',
          'HTTP 400: {"error":"schema"}',
        ));
    await pumpScan(tester, reader: reader);

    await tester.tap(find.text('صوّر الروشتة'));
    await settle(tester);

    expect(find.text('مقدرتش أقرا الروشتة دلوقتي — صوّر تاني.'), findsOneWidget);
    // نسخة التطوير بتعرض السبب الخام عشان نقراه على الجهاز
    expect(find.text('HTTP 400: {"error":"schema"}'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'صوّر تاني'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  screenTest('«صوّر تاني» من المراجعة بترجّع لشاشة التصوير بالاختيارين — من غير ما تفتح حاجة لوحدها',
      (tester) async {
    final reader = FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [unclearLine]));
    var picks = 0;
    await pumpScan(tester, reader: reader, pick: (_) async {
      picks++;
      return bytes;
    });

    await tester.tap(find.text('صوّر الروشتة'));
    await settle(tester);
    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);

    await tester.tap(find.text('صوّر تاني'));
    await settle(tester);

    expect(find.byType(ScanPrescriptionScreen), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'صوّر تاني'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'اختار من الصور'), findsOneWidget);
    expect(picks, 1, reason: 'مفيش كاميرا اتفتحت لوحدها');
    expect(reader.calls, 1);
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
  });

  screenTest('«اختار من الصور» بتوصل للقارئ زي الكاميرا، ولو اتلغت مفيش حاجة بتتغيّر',
      (tester) async {
    final reader = FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine]));
    final sources = <ImageSource>[];
    var cancelNext = true;
    await pumpScan(tester, reader: reader, pick: (source) async {
      sources.add(source);
      if (cancelNext) return null;
      return bytes;
    });

    // إلغاء من المعرض → الشاشة زي ما هي وولا حاجة اتكتبت
    await tester.tap(find.text('اختار من الصور'));
    await settle(tester);
    expect(sources, [ImageSource.gallery]);
    expect(reader.calls, 0);
    expect(find.byType(ScanPrescriptionScreen), findsOneWidget);
    expect(find.byType(ReviewPrescriptionScreen), findsNothing);
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);

    // اختيار صورة → نفس الطريق للمراجعة
    cancelNext = false;
    await tester.tap(find.text('اختار من الصور'));
    await settle(tester);
    expect(reader.calls, 1);
    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
  });

  group('نفس القيود للكاميرا والمعرض — على ImagePicker نفسه', () {
    late RecordingPickerPlatform platform;

    setUp(() {
      platform = RecordingPickerPlatform();
      ImagePickerPlatform.instance = platform;
    });

    test('pickWithSystemCamera بيبعت نفس maxWidth/maxHeight/imageQuality للاتنين', () async {
      final fromCamera = await pickWithSystemCamera(ImageSource.camera);
      final fromGallery = await pickWithSystemCamera(ImageSource.gallery);

      expect(fromCamera, bytes);
      expect(fromGallery, bytes);
      expect(platform.sources, [ImageSource.camera, ImageSource.gallery]);
      expect(platform.options.length, 2);
      for (final o in platform.options) {
        expect(o.maxWidth, 2560);
        expect(o.maxHeight, 2560);
        expect(o.imageQuality, 92);
      }
    });

    test('إلغاء المعرض → null من غير رمي', () async {
      platform.cancel = true;
      expect(await pickWithSystemCamera(ImageSource.gallery), isNull);
    });
  });
}
