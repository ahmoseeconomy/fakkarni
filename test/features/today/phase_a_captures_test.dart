// لقطات المرحلة أ — «باقي اليوم»: خط متصل من دايرة لدايرة من غير فاصل،
// وكل دوا باسمه جنب رسمته (شرابين في نفس الدقيقة بيتفرّقوا).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/medication/medicine_form.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/today/today_screen.dart';

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
      final file = File('build/capture/phase-a/$name.png')..createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  final aug31 = DateTime(2026, 8, 31);

  for (final dark in [false, true]) {
    final mode = dark ? 'night' : 'day';

    screenTest('لقطة $mode — السكة: خط متصل وشرابين متفرّقين بأساميهم', (tester) async {
      Future<void> add(String name, int hour, {int minute = 0, MedicineForm? form}) =>
          h.meds.addMedicationWithDoses(
            patientId: h.services.patientId,
            name: name,
            timings: [FixedTiming(MinuteOfDay(hour * 60 + minute))],
            startDate: aug31,
            amountLabel: 'معلقة كبيرة',
            form: form,
          );
      await add('Concor', 7, form: MedicineForm.tablet); // في الكارت
      await add('Telfast Syrup', 14, form: MedicineForm.syrup);
      await add('Bronchicum', 14, form: MedicineForm.syrup);
      await add('Zyrtec', 17, minute: 30, form: MedicineForm.tablet);
      await add('Augmentin', 21, form: MedicineForm.capsule);

      F.setDark(on: dark);
      tester.view.physicalSize = const Size(780, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await h.pump(
        tester,
        RepaintBoundary(
          key: const ValueKey('capture-root'),
          child: TodayScreen(now: DateTime(2026, 8, 31, 7)),
        ),
      );
      await settle(tester);
      // رسومات الأنواع PNG أصول — فكّها IO حقيقي برّه الساعة المزيّفة
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await capture(tester, 'day-rail-$mode');
    });
  }
}
