import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/health/vitals.dart';

/// **رسم بسيط للأرقام — مفيش خط «طبيعي» ولا منطقة ملوّنة ولا أحمر.**
///
/// خط واحد (وللضغط خطين: الكبير أخضر والصغير رمادي غامق، ومكتوب تحت
/// مين مين — اللون مش حامل المعنى لوحده). أقل وأعلى رقم مكتوبين على الجنب
/// بالأرقام العربي. مفيش خط مرجعي: أي خط أفقي كان هيتقري «الحد».
class VitalChart extends StatelessWidget {
  const VitalChart({required this.kind, required this.first, this.second = const [], required this.from, required this.to, super.key});

  final VitalKind kind;
  final List<(DateTime, double)> first;
  final List<(DateTime, double)> second;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in first) p.$2, for (final p in second) p.$2];
    final (lo, hi) = vitalChartBounds(values);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 180,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(vitalNumber(hi, kind), style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                  Text(vitalNumber(lo, kind), style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                ],
              ),
              const SizedBox(width: F.s8),
              Expanded(
                child: Directionality(
                  // الوقت من الشمال لليمين زي أي رسم — النص حواليه عربي
                  textDirection: TextDirection.ltr,
                  child: CustomPaint(
                    key: const ValueKey('vital-chart'),
                    painter: _ChartPainter(
                      first: first,
                      second: second,
                      from: from,
                      to: to,
                      lo: lo,
                      hi: hi,
                      line: F.line,
                      primary: F.green,
                      secondary: F.mutedDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (kind == VitalKind.bloodPressure) ...[
          const SizedBox(height: F.s6),
          Row(
            children: [
              _Legend(color: F.green, text: 'الرقم الكبير'),
              const SizedBox(width: F.s12),
              _Legend(color: F.mutedDark, text: 'الرقم الصغير'),
            ],
          ),
        ],
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 16, height: 4, color: color),
          const SizedBox(width: F.s4),
          Text(text, style: TextStyle(fontSize: F.minTextSize, color: F.ink)),
        ],
      );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.first,
    required this.second,
    required this.from,
    required this.to,
    required this.lo,
    required this.hi,
    required this.line,
    required this.primary,
    required this.secondary,
  });

  final List<(DateTime, double)> first;
  final List<(DateTime, double)> second;
  final DateTime from;
  final DateTime to;
  final double lo;
  final double hi;
  final Color line;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Paint()
      ..color = line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), frame);
    canvas.drawLine(Offset.zero, Offset(0, size.height), frame);
    final span = to.difference(from).inMinutes.clamp(1, 1 << 30).toDouble();
    Offset at((DateTime, double) p) => Offset(
          size.width * (p.$1.difference(from).inMinutes / span).clamp(0.0, 1.0),
          size.height * (1 - ((p.$2 - lo) / (hi - lo)).clamp(0.0, 1.0)),
        );
    void series(List<(DateTime, double)> points, Color color) {
      if (points.isEmpty) return;
      final stroke = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final dot = Paint()..color = color;
      final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
      for (final p in points.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      canvas.drawPath(path, stroke);
      for (final p in points) {
        canvas.drawCircle(at(p), 3.5, dot);
      }
    }

    series(second, secondary);
    series(first, primary);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.first != first || old.second != second || old.from != from || old.to != to;
}
