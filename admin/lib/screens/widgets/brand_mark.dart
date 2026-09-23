import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/tokens.dart';

/// مسار الشعار الرسمي — الملف الوحيد اللي بيعرفه.
const String brandTileAsset = 'assets/branding/logo_tile.png';

/// نسبة تدوير الزوايا من المقاس — الملف نفسه مربع كامل، والتدوير وقت العرض.
const double brandCornerFraction = 0.22;

// **الشعار صورة كما هي، ما بتترسمش هنا.** مكان النقطة الدهبية مقاس من
// بكسلات `logo_tile.png` نفسه (مركز الدهبي = (0.591, 0.261) من المقاس،
// نصف قطرها ≈ 0.045) — للهالة اللي بتنبض مرة على شاشة الدخول.
const Offset goldDotFraction = Offset(0.591, 0.261);
const double goldDotRadiusFraction = 0.045;

/// الشعار بمقاس، بزوايا مدوّرة — نفس الصورة في كل مكان، الفرق المقاس بس.
///
/// [border] حد عاجي شفّاف ١ بكسل — على الشريط الأخضر الغامق الشعار كان
/// هيدوب في أرضيته من غيره.
class BrandMark extends StatelessWidget {
  const BrandMark({required this.size, this.border = false, this.shadow = false, super.key});

  final double size;
  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * brandCornerFraction);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: border ? Border.all(color: F.ivory.withValues(alpha: 0.25)) : null,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        brandTileAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'فكرني',
      ),
    );
  }
}

/// شعار الدخول: بيظهر بتلاشي وتكبير خفيف، والنقطة الدهبية بتنبض **مرة
/// واحدة** — هالة بتتوسّع وتتلاشى من مكان النقطة نفسها. مع تقليل الحركة
/// بيظهر ثابت على طول.
class BrandMarkHero extends StatefulWidget {
  const BrandMarkHero({required this.size, super.key});

  final double size;

  @override
  State<BrandMarkHero> createState() => _BrandMarkHeroState();
}

class _BrandMarkHeroState extends State<BrandMarkHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (motionOn(context)) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ٠–٣٠٠ مللي: الشعار؛ ٣٠٠–٦٥٠: النبضة.
    final appear = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.46, curve: Motion.curve),
    );
    final pulse = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.46, 1, curve: Curves.easeOut),
    );
    final dotRadius = widget.size * goldDotRadiusFraction;
    final dot = Offset(
      widget.size * goldDotFraction.dx,
      widget.size * goldDotFraction.dy,
    );
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FadeTransition(
            opacity: appear,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(appear),
              child: BrandMark(size: widget.size, shadow: true),
            ),
          ),
          // الهالة فوق الشعار: بتبدأ بمقاس النقطة وتتوسّع وتتلاشى لصفر —
          // بعد ما تخلص مفيش أي أثر ثابت.
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final t = pulse.value;
              final scale = 1 + 1.8 * t;
              final alpha = (1 - t) * 0.55;
              return Positioned(
                left: dot.dx - dotRadius * scale,
                top: dot.dy - dotRadius * scale,
                child: IgnorePointer(
                  child: Container(
                    width: dotRadius * 2 * scale,
                    height: dotRadius * 2 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: F.gold.withValues(alpha: alpha),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
