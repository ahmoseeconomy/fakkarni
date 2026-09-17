import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/features/medication/medications_screen.dart';

import '../scan/scan_test_support.dart';

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  Future<int> add(String name, DoseTiming timing, {String? amount, bool unknown = false}) =>
      h.meds.addMedication(
        patientId: h.services.patientId,
        name: name,
        timing: timing,
        startDate: aug31,
        amountLabel: amount,
        amountUnknown: unknown,
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pump(tester, MedicationsScreen(today: aug31));
  }

  screenTest('مجموعات بالمرساة بترتيب الوقت، والدوا اللي بياخده مرتين بيظهر في الاتنين', (tester) async {
    final id = await add('Augmentin', const AnchorTiming(DayAnchor.dinner, 0), amount: 'قرص');
    await h.meds.addDoseSchedule(id, timing: const AnchorTiming(DayAnchor.breakfast, 0), startDate: aug31);
    await add('Concor 5mg', const AnchorTiming(DayAnchor.breakfast, -30), amount: 'قرص واحد');
    await pump(tester);

    // الفطار ٧:٣٠ قبل العشا ٨:٠٠ م
    final breakfast = tester.getCenter(find.text('الفطار — ٧:٣٠ ص'));
    final dinner = tester.getCenter(find.text('العشا — ٨:٠٠ م'));
    expect(breakfast.dy, lessThan(dinner.dy));
    expect(find.text('Augmentin'), findsNWidgets(2), reason: 'جرعتين = كارتين');
    expect(find.text('Concor 5mg'), findsOneWidget);
    expect(find.text('دواءين — مرتّبة على مواعيد يومك'), findsOneWidget, reason: 'العدّ بالدوا مش بالجرعة');
    // الاسم mono ٢٤+
    final name = tester.widget<Text>(find.text('Concor 5mg'));
    expect(name.style?.fontSize, greaterThanOrEqualTo(F.medicationNameSize));
    expect(name.style?.fontFamily, F.monoFamily);
    expect(find.widgetWithText(OutlinedButton, 'عدّل'), findsNWidgets(3));
    expect(find.byIcon(Icons.mic), findsNothing, reason: 'مفيش زرار صوت');
    expectNoRedAndMinSize(tester);
  });

  screenTest('جرعة مش معروفة → «الجرعة مش معروفة» بهدوء، مش ذهبي ولا أحمر', (tester) async {
    await add('Telfast 180 mg', const AnchorTiming(DayAnchor.dinner, 0), unknown: true);
    await pump(tester);

    final line = tester.widget<Text>(find.textContaining('الجرعة مش معروفة'));
    expect(line.style?.color, F.mutedDark);
    expectNoRedAndMinSize(tester);
  });

  screenTest('الساعة الثابتة في مجموعة «ساعة ثابتة» في الآخر', (tester) async {
    await add('Eltroxin', FixedTiming(MinuteOfDay.hm(6)), amount: 'قرص');
    await add('Concor 5mg', const AnchorTiming(DayAnchor.breakfast, -30), amount: 'قرص');
    await pump(tester);

    expect(find.text('ساعة ثابتة'), findsOneWidget);
    expect(tester.getCenter(find.text('ساعة ثابتة')).dy,
        greaterThan(tester.getCenter(find.text('الفطار — ٧:٣٠ ص')).dy));
  });

  screenTest('فاضي → سطر هادي بيشاور على «ضيف»', (tester) async {
    await pump(tester);
    expect(find.text('لسه مفيش أدوية. دوس «ضيف» تحت.'), findsOneWidget);
    expect(find.text('موقوفة'), findsNothing);
  });
}
