import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';
import 'package:fakkarni/core/widgets/dark_mode_toggle.dart';

/// الوضع الليلي: الأسطح والنصوص بتقلب من مكان واحد، والتباين بيفضل فوق AA.
///
/// الأرقام محسوبة هنا مش متكتوبة من برّه — لو حد غيّر لون في `tokens.dart`
/// وكسر القراءة في الليل، الاختبار ده بيقع.
double _lum(Color c) {
  double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  tearDown(() => F.setDark(on: false));

  test('الأسطح والنصوص بتقلب مع الوضع', () {
    F.setDark(on: false);
    final lightPage = F.pageGround, lightInk = F.ink, lightCard = F.cardGround;

    F.setDark(on: true);
    expect(F.pageGround, isNot(lightPage));
    expect(F.ink, isNot(lightInk));
    expect(F.cardGround, isNot(lightCard));
    expect(F.isDark, isTrue);

    F.setDark(on: false);
    expect(F.pageGround, lightPage);
    expect(F.ink, lightInk);
  });

  test('التباين في الليل فوق ٤.٥ للنص وفوق ٣ للأيقونات', () {
    F.setDark(on: true);
    for (final (name, colour, ground, min) in <(String, Color, Color, double)>[
      ('النص على الصفحة', F.ink, F.pageGround, 4.5),
      ('النص على الكارت', F.ink, F.cardGround, 4.5),
      ('الثانوي على الكارت', F.mutedDark, F.cardGround, 4.5),
      ('الأخضر على الكارت', F.green, F.cardGround, 4.5),
      ('الذهبي على الكارت', F.gold, F.cardGround, 4.5),
      ('نص المية على كارتها', F.waterInk, F.waterGround, 4.5),
      ('الأيقونات على الصفحة', F.muted, F.pageGround, 3.0),
    ]) {
      expect(_contrast(colour, ground), greaterThanOrEqualTo(min), reason: name);
    }
  });

  test('نفس التباين في النهار', () {
    F.setDark(on: false);
    for (final (name, colour, ground) in <(String, Color, Color)>[
      ('النص على الكارت', F.ink, F.cardGround),
      ('الثانوي على الكارت', F.mutedDark, F.cardGround),
      ('نص المية على كارتها', F.waterInk, F.waterGround),
    ]) {
      expect(_contrast(colour, ground), greaterThanOrEqualTo(4.5), reason: name);
    }
  });

  testWidgets('المفتاح بيقلب الوضع وبيقول اللي هيحصل', (tester) async {
    F.setDark(on: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(appBar: AppBar(actions: const [DarkModeToggle()])),
        ),
      ),
    );

    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'وضع ليلي');
    await tester.tap(find.byKey(const ValueKey('dark-mode-toggle')));
    await tester.pump();
    expect(F.isDark, isTrue);
  });
}
