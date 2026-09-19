import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/domain/scheduling/day_routine.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/core/widgets/f_sheet.dart';
import 'package:fakkarni/features/medication/add_sheet.dart';
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
    expect(find.widgetWithText(OutlinedButton, 'خيارات'), findsNWidgets(3), reason: 'زرار واحد بيفتح التلاتة');
    expect(find.byIcon(Icons.mic), findsNothing, reason: 'مفيش زرار صوت');
    expectNoRedAndMinSize(tester);
  });

  group('التلات أفعال من زرار واحد', () {
    Future<void> openActions(WidgetTester tester) async {
      await tester.tap(find.text('خيارات').first);
      await settle(tester);
    }

    screenTest('«خيارات» بيفتح التلاتة: عدّل، وقّفه، شيله', (tester) async {
      await add('Concor 5mg', const AnchorTiming(DayAnchor.breakfast, -30), amount: 'قرص');
      await pump(tester);
      await openActions(tester);

      expect(find.widgetWithText(FilledButton, 'عدّل'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'وقّفه دلوقتي'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'شيله خالص'), findsOneWidget);
      expectNoRedAndMinSize(tester);
    });

    screenTest('«وقّفه دلوقتي» بينقله لـ«موقوفة»، و«رجّعه تاني» بترجّعه', (tester) async {
      await add('Concor 5mg', const AnchorTiming(DayAnchor.breakfast, -30), amount: 'قرص');
      await pump(tester);

      await openActions(tester);
      await tester.tap(find.text('وقّفه دلوقتي'));
      await settle(tester);
      expect(find.text('موقوفة'), findsOneWidget);
      expect(find.text('موقوف — التذكيرات واقفة'), findsOneWidget);

      await openActions(tester);
      expect(find.widgetWithText(OutlinedButton, 'رجّعه تاني'), findsOneWidget,
          reason: 'الإيقاف بيتراجع — والشيل لأ');
      await tester.tap(find.text('رجّعه تاني'));
      await settle(tester);
      expect(find.text('موقوفة'), findsNothing);
    });

    screenTest('**التأكيد شرط**: «شيله خالص» بتسأل بالاسم، و«لا، سيبه» ما بتشيلش',
        (tester) async {
      await add('Concor 5mg', const AnchorTiming(DayAnchor.breakfast, -30), amount: 'قرص');
      await pump(tester);

      await openActions(tester);
      await tester.tap(find.text('شيله خالص'));
      await settle(tester);

      // السؤال بالاسم، ومكتوب إنه مالوش رجوع
      expect(find.text('تشيل Concor 5mg؟'), findsOneWidget);
      expect(find.textContaining('مفيش رجوع'), findsOneWidget);
      expectNoRedAndMinSize(tester);

      await tester.tap(find.text('لا، سيبه'));
      await settle(tester);
      expect(find.text('Concor 5mg'), findsOneWidget, reason: 'لسه مكانه');
      // قراية مباشرة: بث drift جوّه اختبار ودجت ممكن يستنى إشعار مش جاي
      expect((await h.db.select(h.db.medications).get()).single.removedAt, isNull);
    });

    screenTest('«أيوه، شيله» بتشيله من القايمة — ومن غير مسح', (tester) async {
      await add('Concor 5mg', const AnchorTiming(DayAnchor.breakfast, -30), amount: 'قرص');
      await add('Telfast 180 mg', const AnchorTiming(DayAnchor.dinner, 0), amount: 'قرص');
      await pump(tester);

      await openActions(tester);
      await tester.tap(find.text('شيله خالص'));
      await settle(tester);
      await tester.tap(find.text('أيوه، شيله'));
      await settle(tester);

      expect(find.text('Concor 5mg'), findsNothing);
      expect(find.text('Telfast 180 mg'), findsOneWidget);
      expect(find.text('موقوفة'), findsNothing, reason: 'المتشال مش موقوف — مش في أي قسم');
      // الصف مكانه — إيقاف ناعم مش مسح
      expect((await h.db.select(h.db.medications).get()), hasLength(2));
    });
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

  screenTest('فاضي → «لسه مفيش أدوية.» وكارت «ضيف دوا» هو الدعوة — مش جملة بتشاور على الدوك', (tester) async {
    await pump(tester);
    expect(find.text('لسه مفيش أدوية.'), findsOneWidget);
    expect(find.textContaining('دوس «ضيف»'), findsNothing);
    expect(find.byKey(const ValueKey('add-medication-card')), findsOneWidget);
    expect(find.text('موقوفة'), findsNothing);
  });

  screenTest('زرار «قريب منك» اتشال من الشاشة دي — مكانه حبّاية الرئيسية', (tester) async {
    await add('Concor 5mg', const AnchorTiming(DayAnchor.breakfast, -30), amount: 'قرص');
    await pump(tester);
    expect(find.textContaining('قريب منك'), findsNothing);
    expect(find.textContaining('صيدليات'), findsNothing);
  });

  screenTest('كارت «ضيف دوا» فوق المجموعات: زايد وكلمتين، ≥٥٦، وبيفتح نفس شيت الدوك بنفس المداخل', (tester) async {
    await add('Concor 5mg', const AnchorTiming(DayAnchor.breakfast, -30), amount: 'قرص');
    await pump(tester);

    final card = find.byKey(const ValueKey('add-medication-card'));
    expect(card, findsOneWidget);
    expect(tester.getSize(card).height, greaterThanOrEqualTo(F.minTapTarget));
    expect(find.descendant(of: card, matching: find.byIcon(Icons.add)), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('ضيف دوا')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(Text)), findsOneWidget, reason: 'كلمتين وبس');
    expect(tester.getCenter(card).dy, lessThan(tester.getCenter(find.text('Concor 5mg')).dy), reason: 'فوق المجموعات');

    await tester.tap(card);
    await tester.pump();
    await tester.pump(F.sheetDuration);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(FSheet), findsOneWidget);
    for (final label in addSheetLabels) {
      expect(find.descendant(of: find.byType(FSheet), matching: find.text(label)), findsOneWidget, reason: label);
    }
    expectNoRedAndMinSize(tester);
  });
}
