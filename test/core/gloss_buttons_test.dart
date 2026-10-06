// الأبيض الثانوي وحده يفضل «فقاعة لامعة». الأخضر والدهبي الأساسيان سطح
// بارز مطفي: وجه موحّد، حافة سفلية أغمق وظل ناعم؛ لا لمعة ولا خط فوق.
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

  testWidgets('الأساسي الأخضر: بارز مطفي بحافة سفلية وظل، بلا لمعة أو خط فوق', (tester) async {
    var taps = 0;
    await pump(tester, FPrimaryButton(label: 'احفظ', onPressed: () => taps++));

    final surface = tester.widget<RaisedPrimarySurface>(find.byType(RaisedPrimarySurface));
    expect(surface.fill, F.green);
    expect(surface.rim, isNot(F.green), reason: 'الحافة السفلية أغمق من الوجه');
    expect(find.byType(GlossPill), findsNothing);
    expect(find.byKey(const ValueKey('gloss-edge-line')), findsNothing);

    // كبسولة — الزرار الجوّاني نفسه بنصف قطر الكبسولة، ومن غير حد صلب
    final filled = tester.widget<FilledButton>(find.byType(FilledButton));
    final shape = filled.style!.shape!.resolve(const {})! as RoundedRectangleBorder;
    expect(shape.borderRadius, GlossPill.pillRadius);
    expect(shape.side, BorderSide.none);

    // والسلوك زي ما هو
    await tester.tap(find.text('احفظ'));
    expect(taps, 1);
  });

  testWidgets('الدهبي: يفضل باللمعة الحالية؛ التغيير للأخضر فقط', (tester) async {
    await pump(tester, FPrimaryButton(label: 'تم', gold: true, onPressed: () {}));
    final surface = pill(tester);
    expect(surface.fill, F.gold);
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
  });

  testWidgets('بالليل: الأساسي بارز مطفي والثانوي وحده لمعته أضعف', (tester) async {
    F.setDark(on: true);
    await pump(tester, Column(mainAxisSize: MainAxisSize.min, children: [
      FPrimaryButton(label: 'احفظ', onPressed: () {}),
      const SizedBox(height: 16),
      FSecondaryButton(label: 'افتح', onPressed: () {}),
    ]));
    final surface = tester.widget<RaisedPrimarySurface>(find.byType(RaisedPrimarySurface));
    expect(surface.fill, F.green);
    final secondary = pill(tester);
    expect(secondary.glossTop.a, closeTo(0.10, 0.001), reason: 'الثانوي بالليل مش كشّاف');
    // والعقد التبايني: الكلمة على السطح الليلي، وحد الفقاعة ٣:١ بالليل برضه
    expect(_contrast(F.ink, F.bubbleGround), greaterThan(4.5), reason: 'AA بالليل');
    expect(secondary.edge, F.bubbleEdge);
    expect(_contrast(F.bubbleEdge, F.pageGround), greaterThanOrEqualTo(3.0),
        reason: 'WCAG 1.4.11 — حد عنصر ٣:١ ليلي');
  });

  testWidgets('الأساسي المعطّل مسطّح: من غير لمعة ولا ضل ولا حافة بارزة', (tester) async {
    await pump(tester, const FPrimaryButton(label: 'احفظ', onPressed: null));
    final surface = tester.widget<RaisedPrimarySurface>(find.byType(RaisedPrimarySurface));
    expect(surface.enabled, isFalse);
    expect(find.byKey(const ValueKey('gloss-edge-line')), findsNothing);
    // الطبقة الخارجية (صاحبة الضل) فاضية
    final outer = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(RaisedPrimarySurface), matching: find.byType(DecoratedBox), matchRoot: true).first,
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
