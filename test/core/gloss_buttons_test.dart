// «الفقاعة اللامعة» (المرحلة ٣، المالك MEDIUM) — شكل واحد لزرارَي النداء
// من غلاف واحد [GlossPill]: كبسولة، لمعة ٣٢٪←١١٪ بتخلص بعد النص بشوية،
// خيط أبيض على الحافة الفوقانية، ضل جوّاني تحت، وضل برّاني بلون الزرار
// (محايد للثانوي). الليل نفس البنية ولمعة الثانوي أضعف بكتير.
// المعطّل مسطّح: من غير لمعة ولا ضل.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/primitives.dart';

void main() {
  tearDown(() => F.setDark(on: false));

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: F.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: child))),
        ),
      ),
    );
    await tester.pump();
  }

  GlossPill pill(WidgetTester tester) => tester.widget<GlossPill>(find.byType(GlossPill));

  LinearGradient glossOf(WidgetTester tester) {
    // أول طبقة متدرّجة جوّه الفقاعة هي اللمعة
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(of: find.byType(GlossPill), matching: find.byType(DecoratedBox)),
    );
    for (final b in boxes) {
      final d = b.decoration;
      if (d is BoxDecoration && d.gradient is LinearGradient) {
        final g = d.gradient! as LinearGradient;
        if (g.colors.first.a > (g.colors.last.a)) return g; // اللمعة بتبدأ قوية
      }
    }
    fail('مفيش طبقة لمعة');
  }

  testWidgets('الأساسي الأخضر: كبسولة، لمعة ٣٢٪←١١٪، خيط الحافة، وضل بلون الزرار', (tester) async {
    var taps = 0;
    await pump(tester, FPrimaryButton(label: 'احفظ', onPressed: () => taps++));

    final p = pill(tester);
    expect(p.fill, F.green);
    expect(p.shadow, F.glossShadowOf(F.green), reason: 'الضل بلون الزرار نفسه');
    expect(p.glossTop, F.glossTop);
    expect(p.glossTop.a, closeTo(0.32, 0.001), reason: 'لمعة MEDIUM');
    expect(p.glossMid.a, closeTo(0.11, 0.001));

    final g = glossOf(tester);
    expect(g.stops!.last, closeTo(0.56, 0.01), reason: 'اللمعة بتخلص بعد النص بشوية');
    expect(find.byKey(const ValueKey('gloss-edge-line')), findsOneWidget);

    // كبسولة — الزرار الجوّاني نفسه بنصف قطر الكبسولة، ومن غير حد صلب
    final filled = tester.widget<FilledButton>(find.byType(FilledButton));
    final shape = filled.style!.shape!.resolve(const {})! as RoundedRectangleBorder;
    expect(shape.borderRadius, GlossPill.pillRadius);
    expect(shape.side, BorderSide.none);

    // والسلوك زي ما هو
    await tester.tap(find.text('احفظ'));
    expect(taps, 1);
  });

  testWidgets('الدهبي: نفس البنية والضل دهبي', (tester) async {
    await pump(tester, FPrimaryButton(label: 'تم', gold: true, onPressed: () {}));
    expect(pill(tester).fill, F.gold);
    expect(pill(tester).shadow, F.glossShadowOf(F.gold));
  });

  testWidgets('الثانوي بالنهار: فقاعة بيضا بحد رفيع خفيف (2B) — ٣:١ ضد أرضية الصفحة بالرقم', (tester) async {
    await pump(tester, FSecondaryButton(label: 'افتح', onPressed: () {}));
    final p = pill(tester);
    expect(p.fill, F.bubbleGround);
    expect(p.shadow, F.bubbleShadow);
    expect(p.glossTop.a, closeTo(0.32, 0.001), reason: 'بالنهار نفس لمعة الأساسي');
    // الحد على الكبسولة نفسها (مش OutlinedButton — ده شفاف جوّاها)
    expect(p.edge, F.bubbleEdge);
    expect(_contrast(F.bubbleEdge, F.pageGround), greaterThanOrEqualTo(3.0),
        reason: 'WCAG 1.4.11 — حد عنصر ٣:١ نهاري');
    final outlined = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(outlined.style!.side!.resolve(const {}), BorderSide.none);
    // والأساسي من غير حد — حدّه تعبئته
    await pump(tester, FPrimaryButton(label: 'احفظ', onPressed: () {}));
    expect(pill(tester).edge, isNull);
  });

  testWidgets('بالليل: بنية الأساسي زي ما هي، ولمعة الثانوي أضعف بكتير', (tester) async {
    F.setDark(on: true);
    await pump(tester, Column(mainAxisSize: MainAxisSize.min, children: [
      FPrimaryButton(label: 'احفظ', onPressed: () {}),
      const SizedBox(height: 16),
      FSecondaryButton(label: 'افتح', onPressed: () {}),
    ]));
    final pills = tester.widgetList<GlossPill>(find.byType(GlossPill)).toList();
    expect(pills.first.glossTop.a, closeTo(0.32, 0.001), reason: 'الأساسي بالليل زي النهار');
    expect(pills.last.glossTop.a, closeTo(0.10, 0.001), reason: 'الثانوي بالليل مش كشّاف');
    expect(pills.last.glossTop.a, lessThan(pills.first.glossTop.a / 2));
    // والعقد التبايني: الكلمة على السطح الليلي، وحد الفقاعة ٣:١ بالليل برضه
    expect(_contrast(F.ink, F.bubbleGround), greaterThan(4.5), reason: 'AA بالليل');
    expect(pills.last.edge, F.bubbleEdge);
    expect(_contrast(F.bubbleEdge, F.pageGround), greaterThanOrEqualTo(3.0),
        reason: 'WCAG 1.4.11 — حد عنصر ٣:١ ليلي');
  });

  testWidgets('المعطّل مسطّح: من غير لمعة ولا ضل ولا خيط — والكلمة بلون التعطيل', (tester) async {
    await pump(tester, const FPrimaryButton(label: 'احفظ', onPressed: null));
    expect(pill(tester).enabled, isFalse);
    expect(find.byKey(const ValueKey('gloss-edge-line')), findsNothing);
    // الطبقة الخارجية (صاحبة الضل) فاضية
    final outer = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(GlossPill), matching: find.byType(DecoratedBox), matchRoot: true).first,
    );
    expect((outer.decoration as BoxDecoration).boxShadow, isEmpty, reason: 'زرار نايم مش فقاعة');
    // ومفيش ولا طبقة متدرّجة
    for (final b in tester.widgetList<DecoratedBox>(
        find.descendant(of: find.byType(GlossPill), matching: find.byType(DecoratedBox)))) {
      expect((b.decoration as BoxDecoration).gradient, isNull);
    }
  });
}

/// نفس حساب AA (WCAG) — لزوج واحد.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  }

  final l1 = lum(a) + 0.05, l2 = lum(b) + 0.05;
  return l1 > l2 ? l1 / l2 : l2 / l1;
}
