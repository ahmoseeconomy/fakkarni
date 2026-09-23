import 'dart:async';

import 'package:flutter/material.dart';

import '../../format/arabic_time.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';

/// دخول بتلاشي وانزلاق خفيف، بعد تأخير — الصفوف بتدخل ورا بعض.
///
/// مع تقليل الحركة الودجت بتظهر جاهزة من أول فريم، ومفيش مؤقّت أصلاً.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    required this.child,
    this.delay = Duration.zero,
    this.dy = 0.08,
    super.key,
  });

  final Widget child;
  final Duration delay;

  /// مسافة الانزلاق كنسبة من ارتفاع الودجت.
  final double dy;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.base,
  );
  Timer? _timer;
  bool _armed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    if (!motionOn(context)) {
      _c.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Motion.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset(0, widget.dy), end: Offset.zero)
            .animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// رقم بيعدّ من الصفر لقيمته — وبيتحرّك من القديمة للجديدة عند التحديث.
/// بأرقام عربية، زي كل رقم في اللوحة.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {required this.style, super.key});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: motionDuration(context, Motion.slow),
      curve: Motion.curve,
      builder: (context, v, _) => Text(arabicNumber(v.round()), style: style),
    );
  }
}

/// كتلة لمعان مكان محتوى لسه ما وصلش — بدل شاشة فاضية. مع تقليل الحركة
/// بتبقى كتلة هادية من غير لمعان.
class Shimmer extends StatefulWidget {
  const Shimmer({required this.width, required this.height, this.radius = F.radiusChip, super.key});

  final double width;
  final double height;
  final double radius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _armed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    if (motionOn(context)) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = F.railGround;
    final sheen = F.cardGround;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final x = _c.value * 3 - 1.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(x - 1, 0),
              end: Alignment(x + 1, 0),
              colors: [base, sheen, base],
            ),
          ),
        );
      },
    );
  }
}

/// أيقونة بتلفّ طول ما [spinning] شغّالة — زرار «حدّث» وهو بيجيب.
class SpinWhile extends StatefulWidget {
  const SpinWhile({required this.spinning, required this.child, super.key});

  final bool spinning;
  final Widget child;

  @override
  State<SpinWhile> createState() => _SpinWhileState();
}

class _SpinWhileState extends State<SpinWhile> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SpinWhile old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.spinning && motionOn(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else if (_c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _c, child: widget.child);
}
