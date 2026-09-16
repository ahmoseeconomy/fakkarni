import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/fa_mark.dart';

/// شاشة البداية — ٣ ثواني مؤلّفة، وعمرها ما بتوقف التطبيق.
///
/// الشاشة الأولى بتتبني **تحتها** من أول فريم؛ دي طبقة فوقها بتتلاشى.
/// أرضيتها هي هي أرضية `LaunchScreen.storyboard` (`greenDeep` مسطّحة)،
/// فالقطع من شاشة النظام مش بيبان. الحكاية:
///   0.15 الحلقة، 0.60 الذيل، 1.20 النقطة الدهبي بتيجي **من بره الشاشة**
///   على قوس وبتنطّ لحد مكانها، 2.00 نطّة صغيرة وميض، 2.30 «فكرني» تطلع
///   ٨px، 3.00 تكبير ١.٠٤ وتلاشي ٠.٣٥ ث.
/// مع «تقليل الحركة» بتظهر الحالة النهائية على طول وتختفي بسرعة.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({required this.child, super.key});

  final Widget child;

  /// إجمالي الطبقة: ٣ ث + ٠.٣٥ ث تلاشي.
  static const Duration total = Duration(milliseconds: 3350);

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SplashOverlay.total,
  );
  bool _done = false;
  bool _started = false;

  // كل الفترات نسبة من ٣.٣٥ ث
  static double _at(int ms) => ms / 3350;

  late final _bowl = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(150), _at(700), curve: Curves.easeOut),
  );
  late final _tail = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(600), _at(1150), curve: Curves.easeOut),
  );

  /// الرحلة: النقطة داخلة من بره الشاشة لحد مكانها.
  late final _fly = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(1200), _at(1950), curve: Curves.easeInOutCubic),
  );

  /// النطّة بعد ما توصل — مرتدّة صغيرة فوق وتحت.
  late final _land = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(1950), _at(2350), curve: Curves.elasticOut),
  );

  /// الوميض — بيولّع مع الوصول ويهدى.
  late final _flash = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(1900), _at(2400), curve: Curves.easeOut),
  );
  late final _halo = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(1950), _at(2700), curve: Curves.easeOut),
  );
  late final _word = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(2300), _at(2750), curve: Curves.easeOut),
  );
  late final _exit = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(3000), _at(3350), curve: Curves.easeIn),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // الحالة النهائية على طول، وتلاشي قصير
      _c.value = _at(3000);
    }
    // الساعة بتبدأ مع أول فريم **مرسوم**، مش مع أول build: في أول فتحة
    // الـUI thread مشغول بالتحميل، ولو الساعة بدأت قبل ما يرسم، الحركة
    // بتعدّي كلها ومحدش شافها.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _c.forward().whenComplete(() {
        if (mounted) setState(() => _done = true);
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// قوس الطيران: بترتفع في النص وبترجع لمكانها — نطّة، مش خط.
  static double _hop(double t) {
    if (t <= 0 || t >= 1) return 0;
    return math.sin(math.pi * t);
  }

  /// وميضة واحدة: بتولّع لحد النص وبتهدى.
  double get _flashValue {
    final t = _flash.value;
    if (t <= 0 || t >= 1) return 0;
    return t < 0.35 ? t / 0.35 : 1 - (t - 0.35) / 0.65;
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // مفيش لمس بيوصل للطبقة دي — التطبيق تحتها شغّال من أول لحظة.
        // Material شفاف لأن الطبقة فوق الـNavigator: من غيره النص بياخد
        // الخط الأصفر بتاع «مفيش Material».
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final exit = _exit.value;
              return Opacity(
                opacity: 1 - exit,
                child: Material(
                  type: MaterialType.transparency,
                  child: ColoredBox(
                    color: F.greenDeep,
                    child: Transform.scale(
                      scale: 1 + 0.04 * exit,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox.square(
                            dimension: 132,
                            child: CustomPaint(
                              painter: FaMarkPainter(
                                letterColor: F.ivory,
                                dotColor: F.gold,
                                bowlProgress: _bowl.value,
                                tailProgress: _tail.value,
                                // بتبان أول ما تبدأ تطير — قبلها مش موجودة
                                dotOpacity: _fly.value == 0 ? 0 : 1,
                                // القوس: داخلة من بره على اليمين (٩٠ وحدة رسم)
                                // وبتنزل على مكانها، والنطّة بعدها ٦px لفوق
                                dotSlide: 90 * (1 - _fly.value),
                                dotDrop: -14 * _hop(_fly.value) - 6 * (1 - _land.value).clamp(0.0, 1.0),
                                dotFlash: _flashValue,
                                halo: _halo.value,
                              ),
                            ),
                          ),
                          const SizedBox(height: F.s22),
                          Transform.translate(
                            offset: Offset(0, 8 * (1 - _word.value)),
                            child: Opacity(
                              opacity: _word.value,
                              child: const Text(
                                'فكرني',
                                style: TextStyle(
                                  fontFamily: F.displayFamily,
                                  fontSize: F.display3,
                                  fontWeight: FontWeight.w700,
                                  color: F.ivory,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
