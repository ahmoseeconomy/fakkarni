// لقطات المرحلة ب — «أوراقك» أرشيف بأربع فولدرات: مليان وفاضي، نهاري وليلي.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/data/db/tables.dart';
import 'package:fakkarni/data/repositories/records_repository.dart';
import 'package:fakkarni/features/records/health_file_screen.dart';

import '../scan/scan_test_support.dart';

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
      final file = File('build/capture/phase-b/$name.png')..createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  final sep14 = DateTime(2026, 9, 14);

  Future<void> pumpShot(WidgetTester tester, {required bool dark}) async {
    F.setDark(on: dark);
    tester.view.physicalSize = const Size(780, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(
      tester,
      RepaintBoundary(key: const ValueKey('capture-root'), child: HealthFileScreen(today: sep14)),
    );
    await settle(tester);
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'night' : 'day';

    screenTest('لقطة $mode — الفولدرات بعدّها', (tester) async {
      final repo = RecordsRepository(h.db);
      Future<void> add(RecordKind kind, String title, DateTime at) =>
          repo.add(patientId: h.services.patientId, kind: kind, title: title, happenedAt: at);
      await add(RecordKind.prescription, 'روشتة الباطنة', DateTime(2026, 9, 2));
      await add(RecordKind.prescription, 'روشتة القلب', DateTime(2026, 8, 10));
      await add(RecordKind.lab, 'تقرير تحليل — نتيجتين', DateTime(2026, 8, 28));
      await add(RecordKind.imaging, 'MRI Lumbar Spine', DateTime(2026, 9, 12));
      await add(RecordKind.visit, 'زيارة د. حسام', DateTime(2026, 9, 1));
      await add(RecordKind.booking, 'كشف قديم', DateTime(2026, 8, 1));
      await pumpShot(tester, dark: dark);
      await capture(tester, 'folders-full-$mode');
    });

    screenTest('لقطة $mode — الفاضي: «لسه مفيش أوراق» ومن غير زرار', (tester) async {
      await pumpShot(tester, dark: dark);
      await capture(tester, 'folders-empty-$mode');
    });
  }
}
