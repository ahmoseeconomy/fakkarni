import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/features/today/tips/tip_picker.dart';
import 'package:fakkarni/features/today/widgets/tip_card.dart';

/// «معلومة تهمك» — الشكل: عنوان أكبر وأتقل من النص، أرضية `tipSurface`،
/// ولمبة بتتوهّج من غير ما تكبر، وبتقف تحت «تقليل الحركة» وفي الخلفية.
void main() {
  const tip = Tip(text: 'خزّن أدويتك في مكان بارد وناشف.');

  Future<void> pump(WidgetTester tester, {bool reduceMotion = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Padding(padding: EdgeInsets.all(16), child: TipCard(tip: tip))),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('العنوان «معلومة تهمك» أكبر وأتقل من نص المعلومة، والنص فوق الحد', (tester) async {
    await pump(tester);
    final title = tester.widget<Text>(find.byKey(const ValueKey('tip-title')));
    final body = tester.widget<Text>(find.byKey(const ValueKey('tip-text')));
    expect(title.data, 'معلومة تهمك');
    expect(title.style!.fontSize!, greaterThan(body.style!.fontSize!));
    expect(title.style!.fontWeight!.index, greaterThan(body.style!.fontWeight!.index));
    expect(body.style!.fontSize!, greaterThanOrEqualTo(F.minTextSize));
    expect(find.text('معلومة ليك'), findsNothing);
  });

  testWidgets('الأرضية tipSurface والحواف زي كارت المية — واللمبة في بلاطتها على البداية', (tester) async {
    await pump(tester);
    final material = tester.widget<Material>(
      find.ancestor(of: find.byKey(const ValueKey('tip-card')), matching: find.byType(Material)).first,
    );
    expect(material.color, F.tipSurface);
    expect(material.borderRadius, BorderRadius.circular(F.radiusLarge));
    expect(find.byIcon(Icons.lightbulb), findsOneWidget);
    expect(find.byIcon(Icons.water_drop), findsNothing);
    // البلاطة على ناحية البداية (يمين في العربي) من العنوان
    final bulb = tester.getCenter(find.byType(GlowingBulb));
    final title = tester.getCenter(find.byKey(const ValueKey('tip-title')));
    expect(bulb.dx, greaterThan(title.dx));
  });

  testWidgets('التوهّج بيتغيّر مع الوقت من غير أي تكبير — ودورته ١٫٦ ثانية', (tester) async {
    await pump(tester);
    expect(GlowingBulb.cycle, const Duration(milliseconds: 1600));
    Color colourNow() => tester.widget<Icon>(find.byIcon(Icons.lightbulb)).color!;
    final at0 = colourNow();
    await tester.pump(const Duration(milliseconds: 800));
    final at800 = colourNow();
    expect(at800, isNot(at0), reason: 'السطوع بيتحرّك');
    expect(find.descendant(of: find.byType(GlowingBulb), matching: find.byType(Transform)), findsNothing,
        reason: 'توهّج بس — مفيش تكبير ولا هزّ');
    final size = tester.getSize(find.byType(GlowingBulb));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byType(GlowingBulb)), size);
  });

  testWidgets('تحت «تقليل الحركة»: لمبة منوّرة ثابتة، ومفيش حركة', (tester) async {
    await pump(tester, reduceMotion: true);
    Color colourNow() => tester.widget<Icon>(find.byIcon(Icons.lightbulb)).color!;
    final at0 = colourNow();
    expect(at0, F.tipGlow);
    await tester.pump(const Duration(milliseconds: 800));
    expect(colourNow(), at0);
    expect(find.descendant(of: find.byType(GlowingBulb), matching: find.byType(AnimatedBuilder)), findsNothing);
  });

  testWidgets('التطبيق في الخلفية → اللمبة بتقف، وترجع مع المقدمة', (tester) async {
    await pump(tester);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(binding.transientCallbackCount, 0, reason: 'مفيش ticker شغّال في الخلفية');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(binding.transientCallbackCount, greaterThan(0));
    expect(SchedulerBinding.instance, binding);
  });
}
