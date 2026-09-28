// اسم الدوا بيبدأ من يمين الكارت دايماً — عربي أو إنجليزي — والساعة شمال
// في نفس الصف (المالك، ٢٨ سبتمبر ٢٠٢٦).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/med_name.dart';
import 'package:fakkarni/domain/scheduling/dose_schedule.dart';
import 'package:fakkarni/domain/scheduling/minute_of_day.dart';
import 'package:fakkarni/features/medication/medications_screen.dart';
import 'package:fakkarni/features/today/today_screen.dart';

import '../features/scan/scan_test_support.dart';

void main() {
  const pad = 14.0;
  const width = 360.0;

  Future<void> pumpRow(WidgetTester tester, String name) async {
    await tester.pumpWidget(MaterialApp(
      theme: F.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Container(
                key: const ValueKey('card'),
                padding: const EdgeInsets.all(pad),
                child: NameTimeRow(name: name, time: '٥:٠٠ م', timeKey: const ValueKey('time'), nameStyle: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  for (final name in ['كونكور', 'concor', 'Augmentin 1g', '500 Glucophage']) {
    testWidgets('«$name»: حافته اليمين على حشو الكارت، والساعة شمال في نفس الصف', (tester) async {
      await pumpRow(tester, name);
      final card = tester.getRect(find.byKey(const ValueKey('card')));
      final text = find.text(name);
      expect(text, findsOneWidget, reason: 'الاسم زي ما هو — مفيش حروف خفية جوّاه');
      // حدود الحروف المرسومة، مش صندوق الويدجت
      final paragraph = tester.renderObject<RenderParagraph>(text);
      final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: name.length));
      final origin = paragraph.localToGlobal(Offset.zero);
      final inkRight = boxes.map((b) => origin.dx + b.right).reduce((a, b) => a > b ? a : b);
      expect(inkRight, closeTo(card.right - pad, 1.5), reason: '«$name» بيبدأ من اليمين');
      final time = tester.getRect(find.byKey(const ValueKey('time')));
      expect(time.left, closeTo(card.left + pad, 1.5), reason: 'الساعة على الشمال');
      expect(time.center.dy, closeTo(tester.getRect(text).top + time.height / 2, 6), reason: 'نفس الصف');
    });
  }

  testWidgets('«Augmentin 1g» ما بيتلخبطش — الحروف بترتيبها اللاتيني', (tester) async {
    await pumpRow(tester, 'Augmentin 1g');
    final paragraph = tester.renderObject<RenderParagraph>(find.text('Augmentin 1g'));
    final a = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).single;
    final g = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 11, extentOffset: 12)).single;
    expect(a.left, lessThan(g.left), reason: 'A على شمال g زي ما بتتقري');
  });

  testWidgets('اسم طويل بيتقصّ في سطرين قبل ما يزقّ الساعة', (tester) async {
    await pumpRow(tester, 'Augmentin Duo Forte Extended Release 1000 mg Film Coated Tablets');
    expect(tester.widget<Text>(find.byKey(const ValueKey('time'))).data, '٥:٠٠ م');
    final name = tester.widget<Text>(find.textContaining('Augmentin Duo'));
    expect(name.maxLines, 2);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  group('على الشاشات', () {
    final h = Harness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    screenTest('«جدول النهاردة» و«خلال ٤٨ ساعة» و«الأدوية»: «concor» يمين والساعة شمال', (tester) async {
      await h.meds.addMedication(patientId: h.services.patientId, name: 'concor', timing: FixedTiming(MinuteOfDay.hm(21)), startDate: DateTime(2026, 8, 31));
      await h.services.scheduler.rescheduleAll(now: DateTime(2026, 8, 31, 10));
      tester.view.physicalSize = const Size(390, 3200);
      await h.pump(tester, TodayScreen(now: DateTime(2026, 8, 31, 10)));
      for (final e in find.text('concor').evaluate()) {
        final name = tester.getRect(find.byWidget(e.widget));
        final row = find.ancestor(of: find.byWidget(e.widget), matching: find.byType(NameTimeRow));
        if (row.evaluate().isEmpty) continue;
        final rowRect = tester.getRect(row.first);
        expect(name.right, closeTo(rowRect.right, 1.5), reason: 'الاسم يمين الصف');
        final times = find.descendant(of: row.first, matching: find.byType(FittedBox));
        expect(tester.getRect(times.first).center.dx, lessThan(name.center.dx), reason: 'الساعة شمال');
      }
      expect(find.byType(NameTimeRow), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await h.pump(tester, const MedicationsScreen());
      final row = find.ancestor(of: find.text('concor'), matching: find.byType(NameTimeRow));
      expect(row, findsOneWidget);
      expect(tester.getRect(find.text('concor')).right, closeTo(tester.getRect(row).right, 1.5));
    });
  });
}
