// لقطات المرحلة ٦ (تقرير الأشعة) — PNG حقيقية من نفس الحزام، نهاري وليلي:
// التصوير (صفحة رنين جاهزة) ← المراجعة (الخلاصة بالحرف) ← الورقة المحفوظة
// في «أوراقك».
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/ai/lab_reader.dart';
import 'package:fakkarni/ai/lab_reading.dart';
import 'package:fakkarni/ai/prescription_reading.dart' show ReadField;
import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/features/health/radiology_report_screen.dart';
import 'package:fakkarni/features/health/scan_lab_screen.dart';
import 'package:fakkarni/features/records/records_of_kind_screen.dart';

import '../scan/scan_test_support.dart';

ReadField<T> sure<T>(T v) => ReadField(value: v, confidence: 0.95);

class _IdleReader implements LabReportReader {
  @override
  Future<LabReading> read(Uint8List image, {String mimeType = 'image/jpeg', List<Uint8List> morePages = const []}) =>
      throw StateError('اللقطة قبل «اقرا التقرير» — القارئ ما بيتندهش');
}

const mriConclusion =
    'Mild lumbar spondylosis with L4-L5 disc bulge.\nNo disc herniation. The spinal cord is normal.';

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
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/capture/phase6/$name.png')..createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  /// ورقة رنين صناعية — أبيض وعليها سطور رمادية وعنوان، عشان معاينة
  /// الصورة على شاشة التصوير تبان ورقة مش بايتات مكسورة.
  Future<Uint8List> paperPng(WidgetTester tester) async {
    late Uint8List bytes;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 600, 820), Paint()..color = const Color(0xFFFFFFFF));
      final grey = Paint()..color = const Color(0xFFB9B9B9);
      canvas.drawRect(const Rect.fromLTWH(40, 48, 320, 22), Paint()..color = const Color(0xFF444444));
      for (var i = 0; i < 14; i++) {
        canvas.drawRect(Rect.fromLTWH(40, 120.0 + i * 44, i.isEven ? 520 : 430, 10), grey);
      }
      final image = await recorder.endRecording().toImage(600, 820);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      bytes = data!.buffer.asUint8List();
    });
    return bytes;
  }

  LabReading reading() => LabReading(
        lab: sure('مركز الأشعة التخصصي'),
        date: sure(DateTime(2026, 9, 12)),
        lines: const [],
        reportKind: sure('imaging'),
        examName: sure('MRI Lumbar Spine'),
        conclusion: sure(mriConclusion),
      );

  Future<void> pumpShot(WidgetTester tester, Widget screen, {required bool dark, double height = 1900}) async {
    F.setDark(on: dark);
    tester.view.physicalSize = Size(780, height);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, RepaintBoundary(key: const ValueKey('capture-root'), child: screen));
    await settle(tester);
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'night' : 'day';

    screenTest('لقطة $mode — التصوير: صفحة رنين جاهزة قبل «اقرا التقرير»', (tester) async {
      final paper = await paperPng(tester);
      await pumpShot(
        tester,
        ScanLabScreen(reader: _IdleReader(), pickImage: (_) async => paper, today: DateTime(2026, 9, 15)),
        dark: dark,
        height: 1688,
      );
      await tester.tap(find.text('صوّر التقرير'));
      await settle(tester);
      // فكّ الصورة IO حقيقي — نديه لفّة
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(tester);
      await capture(tester, 'mri-scan-$mode');
    });

    screenTest('لقطة $mode — المراجعة: الخلاصة بالحرف والزرارين بنفس الوزن', (tester) async {
      await pumpShot(
        tester,
        RadiologyReportScreen(reading: reading(), today: DateTime(2026, 9, 15)),
        dark: dark,
        height: 1700,
      );
      await capture(tester, 'mri-review-$mode');
    });

    screenTest('لقطة $mode — الورقة المحفوظة في «أوراقك»', (tester) async {
      await RecordsRepository(h.db).add(
        patientId: h.services.patientId,
        kind: RecordKind.imaging,
        title: 'MRI Lumbar Spine',
        happenedAt: DateTime(2026, 9, 12),
        place: 'مركز الأشعة التخصصي',
        notes: mriConclusion,
      );
      await pumpShot(
        tester,
        RecordsOfKindScreen(kind: RecordKind.imaging, today: DateTime(2026, 9, 15)),
        dark: dark,
        height: 1400,
      );
      await capture(tester, 'mri-saved-$mode');
    });
  }
}
