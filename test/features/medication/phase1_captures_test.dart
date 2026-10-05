// لقطات المرحلة ١ (٥ أكتوبر ٢٠٢٦ مساءً) — PNG حقيقية من نفس الحزام، نهاري
// وليلي، للّي اتغيّر: «ضيف دوا» (البكر بمايكاتها، «الساعة كام؟» من غير
// شرايح، كارت «مواعيد الجرعات» مستخبي لجرعة واحدة، «نوع التنبيه» اتنين في
// الصف)، ومحرّر الجرعة (البكرة وبس)، وشاشة قراءة التقرير (ملاحظة «هيتسجّل
// بتاريخ النهارده» الذهبية)، وشاشة التصوير (سطر «اتقرا أول ٤ صفحات بس»).
// نفس أسلوب لقطات الممرض (المحاكي الحقيقي محتاج جولة جهاز).
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
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/health/lab_report_screen.dart';
import 'package:fakkarni/features/health/scan_lab_screen.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/dose_editor.dart';

import 'package:fakkarni/ai/lab_reader.dart';

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
      final file = File('build/capture/phase1/$name.png')..createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> pumpShot(WidgetTester tester, Widget screen, {required bool dark}) async {
    F.setDark(on: dark);
    tester.view.physicalSize = const Size(780, 1688); // 390×844 @2x
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(
      tester,
      RepaintBoundary(key: const ValueKey('capture-root'), child: screen),
    );
    await settle(tester);
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'night' : 'day';

    screenTest('لقطة $mode — «ضيف دوا»: بكرة «الساعة كام؟» وجرعة واحدة من غير كارت صفوف', (tester) async {
      await pumpShot(tester, AddMedicationScreen(today: aug31, initialName: 'Concor 5mg'), dark: dark);
      // اللقطة بتطلع الفورم كله بطوله («نوع التنبيه» اتنين في الصف جوّاها)
      await capture(tester, 'add-form-$mode');
    });

    screenTest('لقطة $mode — محرّر الجرعة بالبكرة وبس', (tester) async {
      await pumpShot(
        tester,
        DoseEditor(name: 'Concor 5mg', onSave: (_) async {}, today: aug31),
        dark: dark,
      );
      await capture(tester, 'dose-editor-$mode');
    });

    screenTest('لقطة $mode — قراءة التقرير بملاحظة «هيتسجّل بتاريخ النهارده»', (tester) async {
      await pumpShot(
        tester,
        LabReportScreen(
          reading: LabReading(date: const ReadField.missing(), lab: const ReadField.missing(), lines: [_line()]),
          today: DateTime(2026, 10, 5),
        ),
        dark: dark,
      );
      await capture(tester, 'lab-date-note-$mode');
    });

    screenTest('لقطة $mode — «اتقرا أول ٤ صفحات بس» على شاشة التصوير', (tester) async {
      final six = [for (var i = 0; i < 6; i++) Uint8List.fromList([i])];
      await pumpShot(
        tester,
        ScanLabScreen(
          reader: _Reader(LabReading(date: const ReadField.missing(), lab: const ReadField.missing(), lines: [_line()])),
          pickImage: (_) async => Uint8List.fromList([9]),
          pickImages: (limit) async => six,
          today: DateTime(2026, 10, 5),
        ),
        dark: dark,
      );
      await tester.tap(find.text('اختار من الصور'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('pages-dropped')));
      await settle(tester);
      await capture(tester, 'lab-pages-dropped-$mode');
    });
  }
}
