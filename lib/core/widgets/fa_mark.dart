import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// علامة «ف» — بترسم بالكود، مش صورة.
///
/// حرف ف هندسي ونقطة إعجام ذهبية فوقه (في المخطوطات كانت بتتكتب بالدهب).
/// الذهبي للنقطة والتذكير والحالة النشطة — ومش لأي حاجة تانية. الحرف
/// عمره ما يبقى ذهبي، والنقطة ما تتحركش من مكانها، ومفيش تدرّج ولا ظل.
///
/// المسارات هي هي بتاعة الـSVG في README (viewBox 120):
/// حلقة (76,56) r17، ذيل `M59 56 H40 C24 56 15 68 21 80 C27 91 44 92 55 85`،
/// نقطة (76,18) r8. تحت ١٦ نقطة الحرف بيتشال والعلامة بتبقى نقطة ذهبية
/// جوّه حلقتين عاجي (لوحة 05 في ملف الهوية).
class FaMark extends StatefulWidget {
  const FaMark({
    required this.size,
    this.letterColor = F.ivory,
    this.dotColor = F.gold,
    this.breathing = false,
    super.key,
  });

  final double size;
  final Color letterColor;
  final Color dotColor;

  /// نبضة الراحة: ٣.٤ ث، ساكنة ٧٢٪ منها ثم دقّة واحدة. بتتعطّل مع
  /// «تقليل الحركة» — النقطة بتفضل ساكنة.
  final bool breathing;

  /// تحت المقاس ده الحرف بيتشال.
  static const double reducedBelow = 16.0;

  @override
  State<FaMark> createState() => _FaMarkState();
}

class _FaMarkState extends State<FaMark> with SingleTickerProviderStateMixin {
  /// الدقّة نفسها: ٠.٥ ث (من ٧٢٪ لـ٨٦.٨٪ من دورة ٣.٤ ث).
  ///
  /// مش controller بيلف ٣.٤ ث على طول عن قصد: الراحة الطويلة مؤقّت، مش
  /// أنيميشن — فمفيش فريمات بتتطلب وهي ساكنة (وpumpAndSettle في
  /// الاختبارات بيقدر يهدى).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  Timer? _rest;

  static const _cycle = Duration(milliseconds: 3400);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !widget.breathing || MediaQuery.disableAnimationsOf(context);
    if (still) {
      _rest?.cancel();
      _rest = null;
      _pulse.stop();
      _pulse.value = 0;
    } else {
      _rest ??= Timer.periodic(_cycle, (_) {
        if (mounted) _pulse.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _rest?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => CustomPaint(
          painter: FaMarkPainter(
            letterColor: widget.letterColor,
            dotColor: widget.dotColor,
            reduced: widget.size <= FaMark.reducedBelow,
            // ساكنة = 0؛ وقت الدقّة بنمشي جوّه نافذة ٧٢٪→٨٦.٨٪ من الدورة
            beat: _pulse.isAnimating || _pulse.value > 0 && _pulse.value < 1
                ? 0.72 + _pulse.value * (0.868 - 0.72)
                : 0,
          ),
        ),
      ),
    );
  }
}

/// الرسّام نفسه — عام عشان شاشة البداية ترسم الحرف تدريجياً بنفس المسارات.
class FaMarkPainter extends CustomPainter {
  const FaMarkPainter({
    required this.letterColor,
    required this.dotColor,
    this.reduced = false,
    this.beat = 0,
    this.bowlProgress = 1,
    this.tailProgress = 1,
    this.dotOpacity = 1,
    this.dotDrop = 0,
    this.halo = 0,
  });

  final Color letterColor;
  final Color dotColor;
  final bool reduced;

  /// موضع دورة الراحة 0→1 (٣.٤ ث). ساكنة لحد ٠.٧٢ ثم دقّة.
  final double beat;

  /// لشاشة البداية: رسم الحلقة والذيل 0→1، ظهور النقطة، وهبوطها ٤px.
  final double bowlProgress;
  final double tailProgress;
  final double dotOpacity;
  final double dotDrop;

  /// هالة واحدة 0→1: بتكبر من ٠.٥ لـ٢.٦ وبتختفي.
  final double halo;

  static const _viewBox = 120.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / _viewBox;
    canvas.save();
    canvas.scale(s);

    if (reduced) {
      _paintReduced(canvas);
      canvas.restore();
      return;
    }

    final stroke = Paint()
      ..color = letterColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // الحلقة
    final bowl = Path()..addOval(Rect.fromCircle(center: const Offset(76, 56), radius: 17));
    _drawPartial(canvas, bowl, bowlProgress, stroke);

    // الذيل
    final tail = Path()
      ..moveTo(59, 56)
      ..lineTo(40, 56)
      ..cubicTo(24, 56, 15, 68, 21, 80)
      ..cubicTo(27, 91, 44, 92, 55, 85);
    _drawPartial(canvas, tail, tailProgress, stroke);

    // النقطة — والدقّة: ١ → ١.١٨ → ١ بين ٧٢٪ و٨٦.٨٪ من الدورة
    final dotCenter = Offset(76, 18 + dotDrop);
    final beatScale = _dotBeatScale(beat);
    final haloT = halo > 0 ? halo : _haloFromBeat(beat);
    if (haloT > 0) {
      final scale = 0.5 + (2.6 - 0.5) * haloT;
      final opacity = 0.75 * (1 - haloT);
      canvas.drawCircle(
        dotCenter,
        8 * scale,
        Paint()..color = dotColor.withValues(alpha: opacity * dotOpacity),
      );
    }
    canvas.drawCircle(
      dotCenter,
      8 * beatScale,
      Paint()..color = dotColor.withValues(alpha: dotOpacity),
    );

    canvas.restore();
  }

  /// نقطة ذهبية جوّه حلقتين عاجي — الشكل المختزل.
  void _paintReduced(Canvas canvas) {
    const c = Offset(60, 60);
    canvas.drawCircle(c, 12, Paint()..color = dotColor);
    final ring = Paint()
      ..color = letterColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;
    canvas.drawCircle(c, 27, ring);
    canvas.drawCircle(c, 48, ring);
  }

  static void _drawPartial(Canvas canvas, Path path, double t, Paint paint) {
    if (t <= 0) return;
    if (t >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
    }
  }

  /// dotBeat: 0–72% ساكنة، 79.4% → 1.18، 86.8% → 1.
  static double _dotBeatScale(double t) {
    if (t < 0.72 || t >= 0.868) return 1;
    if (t < 0.794) return 1 + 0.18 * _easeOut((t - 0.72) / (0.794 - 0.72));
    return 1.18 - 0.18 * _easeOut((t - 0.794) / (0.868 - 0.794));
  }

  /// haloBeat: بتبدأ عند 72% وبتنتهي 86.8% — نفس نافذة الدقّة.
  static double _haloFromBeat(double t) {
    if (t < 0.72 || t >= 0.868) return 0;
    return (t - 0.72) / (0.868 - 0.72);
  }

  static double _easeOut(double x) => 1 - math.pow(1 - x, 2).toDouble();

  @override
  bool shouldRepaint(FaMarkPainter old) =>
      old.letterColor != letterColor ||
      old.dotColor != dotColor ||
      old.reduced != reduced ||
      old.beat != beat ||
      old.bowlProgress != bowlProgress ||
      old.tailProgress != tailProgress ||
      old.dotOpacity != dotOpacity ||
      old.dotDrop != dotDrop ||
      old.halo != halo;
}
