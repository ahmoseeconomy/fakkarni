import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import '../today_progress.dart';

/// **«٢ من ٥ — جرعات اليوم»** والسطر جنبها بالورقة الخضرا (التصميم).
///
/// الدايرة أخضر على خط هادي — مش دهبي: دي حالة اليوم، مش حاجة محتاجاك دلوقتي.
/// مفيش جرعات → مفيش دايرة، والسطر لوحده.
class TodayProgressRow extends StatelessWidget {
  const TodayProgressRow({required this.progress, super.key});

  final TodayProgress progress;

  static const double ringSize = 112;

  /// الدايرة الصغيرة جنب التحية على الشاشات القصيرة (آيفون SE) — الرقم بس.
  static const double compactRingSize = 76;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final line = p.line;
    if (!p.showsRing && line == null) return const SizedBox.shrink();
    // **الدايرة بتكبر مع تكبير الخط** — الرقم جوّاها عمره ما بيصغر تحت ١٧
    // عشان يلحق (على ×١٫٣ كان بيفيض ٤ بكسل من دايرة ١١٢).
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final ring = ringSize * scale;
    return Row(
      key: const ValueKey('today-progress'),
      children: [
        if (line != null)
          Expanded(
            child: Row(
              children: [
                Icon(Icons.eco, size: 34, color: F.green),
                const SizedBox(width: F.s8),
                Expanded(
                  child: Text(
                    line,
                    key: const ValueKey('today-progress-line'),
                    style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink, height: 1.4),
                  ),
                ),
              ],
            ),
          )
        else
          const Spacer(),
        if (p.showsRing) ...[
          const SizedBox(width: F.s12),
          Semantics(
            label: 'اتاخد ${arabicNumber(p.taken)} من ${arabicNumber(p.total)} جرعات النهارده',
            excludeSemantics: true,
            child: SizedBox.square(
              key: const ValueKey('today-progress-ring'),
              dimension: ring,
              child: CustomPaint(
                painter: _RingPainter(
                  fraction: p.total == 0 ? 0 : p.taken / p.total,
                  track: F.line,
                  fill: F.green,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${arabicNumber(p.taken)} من ${arabicNumber(p.total)}',
                        key: const ValueKey('today-progress-count'),
                        style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w800, color: F.ink, height: 1.2),
                      ),
                      Text(
                        'جرعات اليوم',
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// **الشاشات القصيرة** (المالك، ٤ أكتوبر ٢٠٢٦): الدايرة صغيرة جنب التحية
/// والسطر تحتها — عشان «أخدتها» يفضل في أول شاشة فوق الدوك على آيفون SE.
class TodayProgressRing extends StatelessWidget {
  const TodayProgressRing({required this.progress, super.key});

  final TodayProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (!p.showsRing) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return Semantics(
      label: 'اتاخد ${arabicNumber(p.taken)} من ${arabicNumber(p.total)} جرعات النهارده',
      excludeSemantics: true,
      child: SizedBox.square(
        key: const ValueKey('today-progress-ring'),
        dimension: TodayProgressRow.compactRingSize * scale,
        child: CustomPaint(
          painter: _RingPainter(fraction: p.total == 0 ? 0 : p.taken / p.total, track: F.line, fill: F.green),
          child: Center(
            child: Text(
              '${arabicNumber(p.taken)} من ${arabicNumber(p.total)}',
              key: const ValueKey('today-progress-count'),
              style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w800, color: F.ink, height: 1.2),
            ),
          ),
        ),
      ),
    );
  }
}

/// سطر الدايرة لوحده بالورقة — للشاشات القصيرة تحت التحية.
class TodayProgressLine extends StatelessWidget {
  const TodayProgressLine({required this.progress, super.key});

  final TodayProgress progress;

  @override
  Widget build(BuildContext context) {
    final line = progress.line;
    if (line == null) return const SizedBox.shrink();
    return Row(
      key: const ValueKey('today-progress'),
      children: [
        Icon(Icons.eco, size: 26, color: F.green),
        const SizedBox(width: F.s6),
        Flexible(
          child: Text(
            line,
            key: const ValueKey('today-progress-line'),
            style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.track, required this.fill});

  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final circle = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(circle, 0, math.pi * 2, false, base);
    if (fraction <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = fill;
    // من فوق، مع اتجاه القراية العربي (عكس عقارب الساعة)
    canvas.drawArc(circle, -math.pi / 2, -math.pi * 2 * fraction.clamp(0, 1), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.track != track || old.fill != fill;
}
