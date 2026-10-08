// لقطات «ضيف دوا» بعد تجربة الآيفون (٦ أكتوبر ٢٠٢٦): بكرة العدد على
// «مرتين» ورجوعها لـ«مرة»، صفوف «مواعيد الجرعات» بـ«عدّل» و«شيل»، وسطر
// «اتشالت الجرعة / رجّعها» — نهاري وليلي، بعرض آيفون SE وبالخطوط الحقيقية.
// بتتكتب في build/capture/dose-rows/.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/medication/add_medication_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(() async {
    F.setDark(on: false);
    await h.tearDown();
  });

  setUpAll(() async {
    final cairo = FontLoader('Cairo');
    for (final f in ['Cairo-Regular.ttf', 'Cairo-Medium.ttf', 'Cairo-SemiBold.ttf', 'Cairo-Bold.ttf', 'Cairo-ExtraBold.ttf']) {
      cairo.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await cairo.load();
    // البكر (CupertinoPicker) بتاخد خط النظام بالاسم ده — على الجهاز هو خط
    // آبل؛ في اللقطة Cairo بداله، وإلا الكلام بيطلع مربعات.
    final system = FontLoader('CupertinoSystemDisplay');
    for (final f in ['Cairo-Regular.ttf', 'Cairo-SemiBold.ttf']) {
      system.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await system.load();
    final home = Platform.environment['HOME'];
    final icons = File('$home/develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
    }
  });

  const size = Size(375, 2300);

  Future<void> open(WidgetTester tester, {required bool dark}) async {
    F.setDark(on: dark);
    await h.pump(
      tester,
      RepaintBoundary(
        key: const ValueKey('capture-root'),
        child: AddMedicationScreen(today: aug31),
      ),
    );
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    await settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture-root')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/capture/dose-rows/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'night' : 'day';

    screenTest('لقطات صفوف الجرعات — $mode', (tester) async {
      await open(tester, dark: dark);
      await pickWheel(tester, const ValueKey('count-wheel'), 1); // مرتين
      await pickTime(tester, const MinuteOfDay(9 * 60));
      await shot(tester, '1-count-2-$mode');

      // رجوع لـ«مرة» بدوسة على الصف — الكارت بيستخبى
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('count-wheel')), matching: find.text('مرة')));
      await settle(tester);
      await shot(tester, '2-back-to-1-$mode');

      await pickWheel(tester, const ValueKey('count-wheel'), 2); // ٣ مرات
      await shot(tester, '3-rows-edit-remove-$mode');

      await tester.tap(find.byKey(const ValueKey('dose-remove-1')));
      await settle(tester);
      await shot(tester, '4-undo-line-$mode');
    });
  }
}
