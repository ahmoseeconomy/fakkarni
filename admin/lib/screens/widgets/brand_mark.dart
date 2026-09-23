import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/tokens.dart';

// **العلامة صورة من التطبيق، ما بتترسمش هنا.** الأرقام دي مقاسة من
// البكسلات بتاعة `icon-foreground.png` (١٠٢٤×١٠٢٤): الشكل بيشغل المربع
// x[332,660] y[318,646]، والنقطة الدهبية مركزها (574,348) بنصف قطر ~٣١.
// القصّ بياخد نافذة ٣٤٪ حوالين مركز الشكل عشان الحواف ما تتقطعش.
const double _window = 0.34;
const double _windowLeft = 0.3145; // مركز الشكل ٠٫٤٨٤٥ − نص النافذة
const double _windowTop = 0.301; //  مركز الشكل ٠٫٤٧١  − نص النافذة

/// مكان النقطة الدهبية جوّه النافذة المقصوصة — للهالة اللي بتنبض مرة.
const Offset goldDotFraction = Offset(
  (0.560 - _windowLeft) / _window,
  (0.340 - _windowTop) / _window,
);

/// العلامة بمقاس — نفس الصورة في كل مكان، الفرق المقاس بس.
class BrandMark extends StatelessWidget {
  const BrandMark({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Align بعامل عرض بيقصّ الصورة للنافذة؛ المحاذاة بتحدّد النافذة تبدأ فين.
    final ax = 2 * _windowLeft / (1 - _window) - 1;
    final ay = 2 * _windowTop / (1 - _window) - 1;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: Align(
          alignment: Alignment(ax, ay),
          widthFactor: _window,
          heightFactor: _window,
          child: Image.asset(
            'assets/branding/mark.png',
            width: size / _window,
            height: size / _window,
            filterQuality: FilterQuality.medium,
            semanticLabel: 'فكرني',
          ),
        ),
      ),
    );
  }
}

/// علامة الدخول: بتظهر بتلاشي وتكبير خفيف، والنقطة الدهبية بتنبض **مرة
/// واحدة** — هالة بتتوسّع وتتلاشى من مكان النقطة نفسها. مع تقليل الحركة
/// بتظهر ثابتة على طول.
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
    // ٠–٣٠٠ مللي: العلامة؛ ٣٠٠–٦٥٠: النبضة.
    final appear = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.46, curve: Motion.curve),
    );
    final pulse = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.46, 1, curve: Curves.easeOut),
    );
    final dotRadius = widget.size * 0.095;
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
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final t = pulse.value;
              // بعد ما تخلص (t=1) الهالة شفافة خالص — مفيش أثر ثابت.
              final scale = 1 + 1.6 * t;
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
          FadeTransition(
            opacity: appear,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(appear),
              child: BrandMark(size: widget.size),
            ),
          ),
        ],
      ),
    );
  }
}
