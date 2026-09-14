import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/features/today/widgets/water_widget.dart';

import '../scan/scan_test_support.dart' show expectNoRedAndMinSize;

void main() {
  final today = DateTime(2026, 8, 31, 10);

  Future<void> pumpWater(WidgetTester tester, DateTime Function() now) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: ListView(children: [WaterWidget(now: now)])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('الكوبايات من ٠ لـ٨ بس، والفترة بتتحفظ', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpWater(tester, () => today);

    expect(textOf(tester, 'water-cups'), '٠ من ٨ كوبايات النهارده');
    expect(textOf(tester, 'water-countdown'), '—');

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('+ كوباية'));
      await tester.pump();
    }
    expect(textOf(tester, 'water-cups'), '٨ من ٨ كوبايات النهارده');

    await tester.tap(find.text('٣ ساعات'));
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('water.everyHours'), 3);
    expect(prefs.getInt('water.cups'), 8);

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('− كوباية'));
      await tester.pump();
    }
    expect(textOf(tester, 'water-cups'), '٠ من ٨ كوبايات النهارده');
    expectNoRedAndMinSize(tester);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('العدّاد بيقل كل ثانية، والمؤقّت بيتلغي مع dispose', (tester) async {
    var clock = today;
    SharedPreferences.setMockInitialValues({
      'water.day': '2026-08-31',
      'water.cups': 3,
      'water.everyHours': 1,
      'water.lastCupMs': today.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
    });
    await pumpWater(tester, () => clock);

    expect(textOf(tester, 'water-cups'), '٣ من ٨ كوبايات النهارده');
    expect(textOf(tester, 'water-countdown'), '٥٠:٠٠');

    clock = clock.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(textOf(tester, 'water-countdown'), '٤٩:٥٩');

    // لو المؤقّت فضل شغّال بعد ما الودجت اتشال، flutter_test بيوقّع الاختبار
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('يوم جديد = عدّاد جديد', (tester) async {
    SharedPreferences.setMockInitialValues({
      'water.day': '2026-08-30',
      'water.cups': 6,
      'water.lastCupMs': today.subtract(const Duration(hours: 12)).millisecondsSinceEpoch,
    });
    await pumpWater(tester, () => today);

    expect(textOf(tester, 'water-cups'), '٠ من ٨ كوبايات النهارده');
    expect(textOf(tester, 'water-countdown'), '—');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
