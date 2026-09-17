import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../core/theme/tokens.dart';

// الإطار والكشف المشترك بين تصوير الروشتة (٥) وتصوير التحليل (٧) — نفس
// قاعدة الأمانة: ولا سطر بيتعلّم قبل ما الرد يوصل، والكشف بيمشي على اللي
// رجع فعلاً.

/// الإطار بأركان: فاضي بنصيحة قبل التصوير، وبعده الصورة الحقيقية مغمّقة.
class ScanStage extends StatelessWidget {
  const ScanStage({
    required this.image,
    required this.busy,
    required this.labels,
    required this.revealed,
    required this.adviceTitle,
    required this.adviceBody,
    required this.waitingText,
    super.key,
  });

  final Uint8List? image;

  /// بنقرا أو بنكشف — الشارة النابضة ظاهرة.
  final bool busy;

  /// السطور اللي **رجعت فعلاً** — null لحد ما الرد يوصل.
  final List<String>? labels;
  final int revealed;
  final String adviceTitle;
  final String adviceBody;

  /// «بيقرا الروشتة…» / «بيقرا التقرير…» — قبل ما الرد يوصل.
  final String waitingText;

  @override
  Widget build(BuildContext context) {
    final lines = labels;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(F.radiusSection),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: F.greenDark),
            if (image != null) ...[
              Image.memory(
                image!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              // الصورة تحت، مغمّقة عشان الصناديق والنص يتقروا فوقها
              ColoredBox(color: F.inkDeep.withValues(alpha: 0.6)),
            ],
            const Padding(
              padding: EdgeInsets.all(F.s18),
              child: CustomPaint(painter: _CornerFrame()),
            ),
            if (image == null)
              Padding(
                padding: const EdgeInsets.all(F.s30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      adviceTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: F.subtitleSize,
                        fontWeight: FontWeight.w700,
                        color: F.onDark,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: F.s10),
                    Text(
                      adviceBody,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: F.minTextSize,
                        color: F.onDarkMuted,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            // السطور — بس بعد ما الرد يوصل، وبعدد اللي رجع فعلاً
            if (lines != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(F.s30, F.s30, F.s30, 84),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, label) in lines.indexed) ...[
                        _LineBox(label: label, read: i < revealed),
                        const SizedBox(height: F.s12),
                      ],
                    ],
                  ),
                ),
              ),
            if (busy)
              Positioned(
                left: 0,
                right: 0,
                bottom: F.s26,
                child: Center(
                  child: _ReadingBadge(
                    text: lines == null
                        ? waitingText
                        : 'بيقرا — ${arabicNumber(revealed)}/${arabicNumber(lines.length)} سطور',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// سطر واحد: متقطع شفاف قبل ما يتعلّم، ممتلئ عاجي بعده.
class _LineBox extends StatelessWidget {
  const _LineBox({required this.label, required this.read});

  final String label;
  final bool read;

  /// rgba(255,255,255,.28) و rgba(234,231,219,.18) — من README.
  static const _unreadStroke = Color(0x47FFFFFF);
  static final _readFill = F.onDarkMuted.withValues(alpha: 0.18);

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(minHeight: F.minTapTarget - F.s8),
      padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s8),
      alignment: AlignmentDirectional.centerStart,
      decoration: read
          ? BoxDecoration(
              color: _readFill,
              borderRadius: BorderRadius.circular(F.radiusChip),
              border: Border.all(color: F.onDarkMuted, width: 1.5),
            )
          : null,
      child: Text(
        label,
        textDirection: nameDirection(label),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: F.minTextSize,
          fontWeight: FontWeight.w600,
          color: read ? F.onDark : F.onDark.withValues(alpha: 0.5),
          fontFamily: F.monoFamily,
          fontFamilyFallback: F.monoFallback,
        ),
      ),
    );
    if (read) return content;
    return CustomPaint(
      painter: const _DashedRect(color: _unreadStroke, radius: F.radiusChip),
      child: content,
    );
  }
}

class _ReadingBadge extends StatelessWidget {
  const _ReadingBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s8),
    decoration: BoxDecoration(
      color: F.inkDeep.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(F.radiusTile),
      border: Border.all(color: F.onDark.withValues(alpha: 0.28)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PulseDot(),
        const SizedBox(width: F.s8),
        Text(
          text,
          style: const TextStyle(
            fontSize: F.minTextSize,
            fontWeight: FontWeight.w600,
            color: F.onDark,
          ),
        ),
      ],
    ),
  );
}

/// نقطة نابضة — ساكنة مع «تقليل الحركة».
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(color: F.onDark, shape: BoxShape.circle),
    ),
  );
}

/// أركان الإطار — أربع زوايا عاجي، من غير مستطيل كامل.
class _CornerFrame extends CustomPainter {
  const _CornerFrame();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = F.onDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const arm = 30.0;
    final w = size.width, h = size.height;
    for (final (x, y, dx, dy) in [
      (0.0, 0.0, 1.0, 1.0),
      (w, 0.0, -1.0, 1.0),
      (0.0, h, 1.0, -1.0),
      (w, h, -1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(x, y), Offset(x + arm * dx, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + arm * dy), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerFrame old) => false;
}

class _DashedRect extends CustomPainter {
  const _DashedRect({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
          Radius.circular(radius),
        ),
      );
    const dash = 6.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRect old) =>
      old.color != color || old.radius != radius;
}

/// ثانوي على الغامق — محدّد عاجي، ٥٦.
class SecondaryOnDark extends StatelessWidget {
  const SecondaryOnDark({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: F.minTapTarget,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: F.onDark,
        disabledForegroundColor: F.mutedLight,
        side: BorderSide(color: F.onDark.withValues(alpha: 0.4), width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: F.s8),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          fontSize: F.minTextSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// معلومة أو غلطة على الغامق — من غير أحمر، حتى للخطأ.
class PanelOnDark extends StatelessWidget {
  const PanelOnDark({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(F.s14),
    decoration: BoxDecoration(
      color: F.railGround,
      borderRadius: BorderRadius.circular(F.radiusCard),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: F.minBodySize,
        color: F.ink,
        height: 1.6,
      ),
    ),
  );
}
