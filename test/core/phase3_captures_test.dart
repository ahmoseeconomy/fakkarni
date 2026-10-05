// لقطات المرحلة ٣ («الفقاعة اللامعة»، المالك MEDIUM) — PNG حقيقية من نفس
// الحزام، نهاري وليلي، للشاشات الأساسية اللي فيها زرارَي النداء المشتركين:
// نمط كبار السن (أكبر زوج — «تم ✅» ٨٠ أساسي و«بعد شوية ⏰» ثانوي)، وفورم
// «ضيف دوا» بزرار «احفظ» شغّال، ومحرّر الجرعة. نفس تحفظ لقطات الممرض
// (أيقونات/أرقام البكر مربعات في الحزام — عيب لقطة مش شاشة).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/elder/elder_home_screen.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';
import 'package:fakkarni/features/medication/dose_editor.dart';

import '../features/scan/scan_test_support.dart';

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
      final file = File('build/capture/phase3/$name.png')..createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> pumpShot(WidgetTester tester, Widget screen, {required bool dark}) async {
    F.setDark(on: dark);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, RepaintBoundary(key: const ValueKey('capture-root'), child: screen));
    await settle(tester);
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'night' : 'day';

    screenTest('لقطة $mode — نمط كبار السن: «تم ✅» فقاعة خضرا و«بعد شوية ⏰» فقاعة بيضا', (tester) async {
      // جرعة معادها دلوقتي — عشان الكارت بزراريه يظهر
      await h.meds.addMedicationWithDoses(
        patientId: h.services.patientId,
        name: 'Concor 5mg',
        timings: [FixedTiming(MinuteOfDay.hm(8))],
        startDate: DateTime(2026, 8, 1),
      );
      await pumpShot(tester, ElderHomeScreen(now: DateTime(2026, 8, 31, 8, 5)), dark: dark);
      await capture(tester, 'elder-home-$mode');
    });

    screenTest('لقطة $mode — «ضيف دوا» بزرار «احفظ» شغّال (فقاعة خضرا بضلها)', (tester) async {
      await pumpShot(tester, AddMedicationScreen(today: aug31, initialName: 'Concor 5mg'), dark: dark);
      await pickTime(tester, const MinuteOfDay(9 * 60));
      await capture(tester, 'add-form-$mode');
    });

    screenTest('لقطة $mode — محرّر الجرعة («احفظ الجرعة» فقاعة)', (tester) async {
      await pumpShot(tester, DoseEditor(name: 'Concor 5mg', onSave: (_) async {}, today: aug31), dark: dark);
      await capture(tester, 'dose-editor-$mode');
    });
  }
}
