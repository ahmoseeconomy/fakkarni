import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fakkarni/ai/prescription_reader.dart';
import 'package:fakkarni/ai/prescription_reading.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
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
    Future<List<Uint8List>> Function(int limit)? pickMany,
  }) =>
      h.pump(
        tester,
        ScanPrescriptionScreen(
          
          reader: reader,
          today: aug31,
          pickImage: pick ?? (_) async => bytes,
          pickImages: pickMany ??
              (limit) async {
                final one = await (pick ?? (_) async => bytes)(ImageSource.gallery);
                return [?one];
              },
        ),
      );

  /// صورة ← «اقرا الروشتة» (الصفحات بتتجمّع الأول، والقراية بدوسة).
  Future<void> shoot(WidgetTester tester, [String label = 'صوّر الروشتة']) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump();
    final read = find.byKey(const ValueKey('pages-read'));
    if (read.evaluate().isNotEmpty) await tester.tap(read);
  }

  screenTest('نصيحة التصوير قبل الكاميرا، والتأكيد بإيد إنسان مكتوب', (tester) async {
    await pumpScan(tester, reader: FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine])));

    expect(find.text('حطها على سطح مستوي والنور يكون كويس'), findsOneWidget);
    expect(find.textContaining('مفيش دوا بيتضاف'), findsOneWidget);
    expect(find.text('صوّر الروشتة'), findsOneWidget);
    expect(find.text('اختار من الصور'), findsOneWidget);
    expect(find.text('أكتبها بإيدي'), findsOneWidget);
    expectNoRedAndMinSize(tester);
  });

  // ⚠️ أمانة الكشف: Gemini بيرجّع كله مرة واحدة. أثناء الانتظار مفيش ولا
  // سطر متعلّم — والكشف بعد الرد بعدد السطور اللي رجعت فعلاً، مش أكتر.
  screenTest('أمانة: وإحنا مستنيين الرد مفيش ولا سطر — بس «بيقرا الروشتة…»', (tester) async {
    final pending = Completer<PrescriptionReading>();
    final reader = FakeReader(() => pending.future);
    await pumpScan(tester, reader: reader);

    await shoot(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(reader.calls, 1);
    expect(find.text('بيقرا الروشتة…'), findsOneWidget);
    expect(find.textContaining('سطور'), findsNothing, reason: 'مفيش عدّاد قبل ما نقرا');
    expect(find.textContaining('Concor'), findsNothing, reason: 'ولا سطر قبل الرد');
    expect(find.byType(ReviewPrescriptionScreen), findsNothing);

    // الرد وصل بسطرين حقيقيين → الكشف بيعدّ ٢ بالظبط، وأسماءهم هما
    final second = ReadLine(
      name: ok('Amaryl 2mg'),
      amount: ok('قرص'),
      timings: ok([FixedTiming(MinuteOfDay.hm(20))]),
      duration: const ReadField(value: null, confidence: 1),
    );
    pending.complete(PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine, second]));
    await tester.pump();
    await tester.pump();

    expect(find.text('بيقرا — ٠/٢ سطور'), findsOneWidget);
    expect(find.textContaining('Concor 5mg'), findsOneWidget);
    expect(find.textContaining('Amaryl 2mg'), findsOneWidget);

    await tester.pump(ScanPrescriptionScreen.revealPerLine);
    expect(find.text('بيقرا — ١/٢ سطور'), findsOneWidget);
    await tester.pump(ScanPrescriptionScreen.revealPerLine);
    expect(find.text('بيقرا — ٢/٢ سطور'), findsOneWidget);

    await tester.pump(ScanPrescriptionScreen.revealHold);
    await settle(tester);
    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
    // وولا حاجة اتحفظت — القاعدة ٤
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);
  });

  screenTest('«أكتبها بإيدي» بتفتح المحرر فاضي', (tester) async {
    await pumpScan(tester, reader: FakeReader(() async => throw StateError('مش المفروض')));
    await tester.tap(find.text('أكتبها بإيدي'));
    await settle(tester);
    expect(find.byType(AddMedicationScreen), findsOneWidget);
  });

  screenTest('مفيش مفتاح → رسالة --dart-define واضحة، ومفيش كاميرا', (tester) async {
    await pumpScan(tester, reader: null);

    expect(find.textContaining('--dart-define=GEMINI_API_KEY'), findsOneWidget);
    expect(find.text('صوّر الروشتة'), findsNothing);
  });

  screenTest('صورة → قراءة → شاشة المراجعة', (tester) async {
    final reader = FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine]));
    await pumpScan(tester, reader: reader);

    await shoot(tester);
    await settle(tester);

    expect(reader.calls, 1);
    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
    expect(find.text('Concor 5mg'), findsOneWidget);
  });

  screenTest('رجع من الكاميرا من غير صورة → ولا طلب', (tester) async {
    final reader = FakeReader(() async => throw StateError('ما كانش المفروض'));
    await pumpScan(tester, reader: reader, pick: (_) async => null);

    await shoot(tester);
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

    await shoot(tester);
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

    await shoot(tester);
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
    await shoot(tester, 'اختار من الصور');
    await settle(tester);
    expect(sources, [ImageSource.gallery]);
    expect(reader.calls, 0);
    expect(find.byType(ScanPrescriptionScreen), findsOneWidget);
    expect(find.byType(ReviewPrescriptionScreen), findsNothing);
    expect(await h.meds.activeSchedules(h.services.patientId), isEmpty);

    // اختيار صورة → نفس الطريق للمراجعة
    cancelNext = false;
    await shoot(tester, 'اختار من الصور');
    await settle(tester);
    expect(reader.calls, 1);
    expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
  });

  group('كذا صفحة في تصويرة واحدة', () {
    screenTest('صورة ← «صوّر صفحة كمان» ← «اقرا الروشتة»: طلب واحد بالصفحتين', (tester) async {
      final reader = FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine]));
      await pumpScan(tester, reader: reader);

      await tester.tap(find.text('صوّر الروشتة'));
      await settle(tester);
      expect(reader.calls, 0, reason: 'الصورة لوحدها ما بتقراش — «اقرا» هي اللي بتقرا');
      expect(find.text('صفحة واحدة جاهزة. لو الورقة أكتر من صفحة، صوّر الباقي قبل ما تدوس «اقرا».'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pages-camera')));
      await settle(tester);
      expect(find.textContaining('٢ صفحات جاهزين'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pages-read')));
      await settle(tester);
      expect(reader.calls, 1);
      expect(reader.pages, [2]);
      expect(find.byType(ReviewPrescriptionScreen), findsOneWidget);
      expectNoRedAndMinSize(tester);
    });

    screenTest('المعرض بيختار كذا صورة — والسقف ٤، وبعده مفيش «صفحة كمان»', (tester) async {
      final reader = FakeReader(() async => PrescriptionReading(doctor: const ReadField.missing(), lines: [clearLine]));
      final limits = <int>[];
      await pumpScan(tester, reader: reader, pickMany: (limit) async {
        limits.add(limit);
        return List.filled(6, bytes);
      });

      await tester.tap(find.text('اختار من الصور'));
      await settle(tester);
      expect(limits, [maxScanPages]);
      expect(find.textContaining('٤ صفحات جاهزين — ده أقصى عدد في المرة.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.descendant(of: find.byKey(const ValueKey('pages-camera')), matching: find.byType(OutlinedButton))).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('pages-read')));
      await settle(tester);
      expect(reader.pages, [4]);
    });

    screenTest('«ابدأ من الأول» بيرمي الصفحات من غير قراية', (tester) async {
      final reader = FakeReader(() async => throw StateError('مش المفروض'));
      await pumpScan(tester, reader: reader);
      await tester.tap(find.text('صوّر الروشتة'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pages-clear')));
      await settle(tester);
      expect(reader.calls, 0);
      expect(find.text('صوّر الروشتة'), findsOneWidget);
      expect(find.byKey(const ValueKey('pages-read')), findsNothing);
    });
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
