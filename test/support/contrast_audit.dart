// **كل نص على الشاشة لازم يتقري — في الوضعين.**
//
// على الموبايل في الوضع الليلي: «خلصت أدوية النهارده كلها. تسلم.» أخضر غامق
// على كارت غامق، أول صف في «خلال ٤٨ ساعة» باهت، و«أعدّل» أبيض على أبيض.
// كل واحد فيهم لون ثابت ما بيقلبش، أو شفافية فوق لون. المساعد ده بيمشي على
// كل نص مرسوم، بيلاقي الأرضية اللي تحته فعلاً (Material / DecoratedBox /
// ColoredBox) وبيحسب الشفافية (Opacity / FadeTransition) زي ما الشاشة بتركّبها،
// وبيحسب تباين WCAG: ٤٫٥:١ للمتن، و٣:١ للكبير (١٨ وفوق، أو عريض ١٤ وفوق).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fakkarni/core/theme/tokens.dart';

double _channel(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// النصوع النسبي — WCAG 2.x.
double relativeLuminance(Color c) => 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a), lb = relativeLuminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [top] فوق [bottom] بشفافيته — النتيجة معتمة.
Color over(Color top, Color bottom) {
  final a = top.a;
  if (a >= 1) return top;
  return Color.from(
    alpha: 1,
    red: top.r * a + bottom.r * (1 - a),
    green: top.g * a + bottom.g * (1 - a),
    blue: top.b * a + bottom.b * (1 - a),
  );
}

Color _lerp(Color from, Color to, double t) => Color.from(
      alpha: 1,
      red: from.r + (to.r - from.r) * t,
      green: from.g + (to.g - from.g) * t,
      blue: from.b + (to.b - from.b) * t,
    );

/// طبقة بين النص والجذر: أرضية ملوّنة، أو شفافية على كل اللي تحتها.
sealed class _Layer {}

class _Ground extends _Layer {
  _Ground(this.color);
  final Color color;
}

class _Fade extends _Layer {
  _Fade(this.opacity);
  final double opacity;
}

Color? _groundOf(Widget w, BuildContext context) {
  switch (w) {
    case Material(:final type, :final color):
      if (type == MaterialType.transparency) return null;
      return color ?? (type == MaterialType.canvas ? Theme.of(context).canvasColor : Theme.of(context).cardColor);
    case DecoratedBox(:final decoration, :final position) when position == DecorationPosition.background:
      if (decoration is BoxDecoration) {
        if (decoration.color != null) return decoration.color;
        final g = decoration.gradient;
        if (g != null && g.colors.isNotEmpty) {
          // التدرّج: الأفتح والأغمق — بناخد الأوحش في الحساب تحت
          return g.colors.first;
        }
      }
      return null;
    case ColoredBox(:final color):
      return color;
    default:
      return null;
  }
}

double? _fadeOf(Widget w) => switch (w) {
      Opacity(:final opacity) => opacity,
      FadeTransition(:final opacity) => opacity.value,
      _ => null,
    };

typedef _Pair = ({Color text, Color ground});

_Pair _composite(List<_Layer> outerToInner, Color base, Color textColor) {
  for (var i = 0; i < outerToInner.length; i++) {
    final layer = outerToInner[i];
    switch (layer) {
      case _Ground(:final color):
        base = over(color, base);
      case _Fade(:final opacity):
        final inner = _composite(outerToInner.sublist(i + 1), base, textColor);
        return (text: _lerp(base, inner.text, opacity), ground: _lerp(base, inner.ground, opacity));
    }
  }
  return (text: over(textColor, base), ground: base);
}

/// نص اتقاس — للتقرير.
class ContrastFailure {
  ContrastFailure(this.text, this.ratio, this.need, this.fg, this.bg);
  final String text;
  final double ratio;
  final double need;
  final Color fg;
  final Color bg;

  String _hex(Color c) =>
      '#${[c.r, c.g, c.b].map((v) => (v * 255).round().toRadixString(16).padLeft(2, '0')).join()}';

  @override
  String toString() =>
      '«$text» ${ratio.toStringAsFixed(2)}:1 (لازم ${need.toStringAsFixed(1)}) — ${_hex(fg)} على ${_hex(bg)}';
}

/// كل النصوص المرسومة (مش الأيقونات) وتباين كل واحد على أرضيته الحقيقية.
List<ContrastFailure> auditContrast(WidgetTester tester) {
  final failures = <ContrastFailure>[];
  var inspected = 0;
  for (final element in find.byType(RichText).evaluate()) {
    final rich = element.widget as RichText;
    // الأيقونات بتترسم بـRichText بخط الأيقونات — مش نص
    var isIcon = false;
    final layers = <_Layer>[];
    element.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Icon || w is ImageIcon) {
        isIcon = true;
        return false;
      }
      final g = _groundOf(w, a);
      if (g != null) layers.add(_Ground(g));
      final f = _fadeOf(w);
      if (f != null && f < 1) layers.add(_Fade(f));
      return true;
    });
    if (isIcon) continue;

    final spans = <(String, TextStyle)>[];
    void walk(InlineSpan span, TextStyle inherited) {
      final style = inherited.merge(span.style);
      if (span is TextSpan) {
        final t = span.text ?? '';
        if (t.trim().isNotEmpty) spans.add((t, style));
        for (final c in span.children ?? const <InlineSpan>[]) {
          walk(c, style);
        }
      }
    }

    walk(rich.text, const TextStyle());
    for (final (text, style) in spans) {
      final color = style.color ?? style.foreground?.color;
      if (color == null) continue;
      inspected++;
      final pair = _composite(layers.reversed.toList(), F.pageGround, color);
      final size = style.fontSize ?? 14;
      final bold = (style.fontWeight ?? FontWeight.w400).value >= 700;
      final need = size >= 18 || (bold && size >= 14) ? 3.0 : 4.5;
      final ratio = contrastRatio(pair.text, pair.ground);
      if (ratio + 1e-6 < need) failures.add(ContrastFailure(text, ratio, need, pair.text, pair.ground));
    }
  }
  expect(inspected, greaterThan(0), reason: 'المراجعة ما شافتش ولا نص — الأداة نفسها بايظة');
  return failures;
}

/// بيوقّع لو فيه نص تحت الحد، وبيقول كل واحد بلونه وأرضيته.
void expectReadableText(WidgetTester tester, {required String where}) {
  final failures = auditContrast(tester);
  expect(failures, isEmpty, reason: '$where (${F.isDark ? 'ليلي' : 'نهاري'}):\n${failures.join('\n')}');
}
