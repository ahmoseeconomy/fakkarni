import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/fa_mark.dart';

/// شاشة البداية — ١.٩ ث مؤلّفة، وعمرها ما بتوقف التطبيق.
///
/// الشاشة الأولى بتتبني **تحتها** من أول فريم؛ دي طبقة فوقها بتتلاشى.
/// أرضيتها هي هي أرضية `LaunchScreen.storyboard` (`greenDeep` مسطّحة)،
/// فالقطع من شاشة النظام مش بيبان. الحكاية:
///   0.07 الحلقة، 0.29 الذيل، 0.58 النقطة الدهبي بتيجي **من بره الشاشة**
///   على قوس وبتنطّ لحد مكانها، 0.94 نطّة صغيرة وميض، 1.11 «فكرني» تطلع
///   ٨px، **1.33 الوقفة**، 1.75 تكبير ١.٠٤ وتلاشي ٠.١٦ ث.
/// مع «تقليل الحركة» بتظهر الحالة النهائية على طول وتختفي بسرعة.
///
/// نفس القصة والحركات، لكن خطها مضغوط بنسبة واحدة عشان الصفحة الجاهزة
/// محلياً تظهر خلال ثانيتين. بعد ما الكلمة تستقر العلامة بتقف **٠.٤١ ث**
/// قبل التلاشي؛ ده يكفي لرؤية العلامة من غير فرض حد أدنى أطول على الفتحة.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({required this.child, super.key});

  final Widget child;

  /// إجمالي الطبقة: ١.٣٣ ث حركة + ٠.٤١ ث وقفة + ٠.١٦ ث تلاشي.
  static const Duration total = Duration(milliseconds: 1900);

  /// بداية التلاشي — ونفسها الحالة اللي «تقليل الحركة» بتقف عليها.
  static const int _exitAtMs = 1745;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

/// اتعرضت خلاص في التشغيلة دي؟ قلب الوضع الليلي بيعيد بناء الشجرة كلها
/// (مفتاح على الوضع في `main`)، ومن غير السطر ده كانت البداية بتتعاد كل
/// مرة يدوس على المفتاح.
bool _splashShown = false;

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SplashOverlay.total,
  );
  bool _done = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _done = _splashShown;
  }

  // كل الفترات نسبة من ١.٩ ث؛ ترتيب القصة ونِسَبها ثابتة.
  static double _at(int ms) => ms / SplashOverlay.total.inMilliseconds;

  late final _bowl = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(73), _at(339), curve: Curves.easeOut),
  );
  late final _tail = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(291), _at(556), curve: Curves.easeOut),
  );

  /// الرحلة: النقطة داخلة من بره الشاشة لحد مكانها.
  late final _fly = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(581), _at(944), curve: Curves.easeInOutCubic),
  );

  /// النطّة بعد ما توصل — مرتدّة صغيرة فوق وتحت.
  late final _land = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(944), _at(1138), curve: Curves.elasticOut),
  );

  /// الوميض — بيولّع مع الوصول ويهدى.
  late final _flash = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(919), _at(1160), curve: Curves.easeOut),
  );
  late final _halo = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(944), _at(1305), curve: Curves.easeOut),
  );
  late final _word = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(1113), _at(1330), curve: Curves.easeOut),
  );
  late final _exit = CurvedAnimation(
    parent: _c,
    curve: Interval(
      _at(SplashOverlay._exitAtMs),
      _at(SplashOverlay.total.inMilliseconds),
      curve: Curves.easeIn,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // الحالة النهائية على طول، وتلاشي قصير
      _c.value = _at(SplashOverlay._exitAtMs);
    }
    // الساعة بتبدأ مع أول فريم **مرسوم**، مش مع أول build: في أول فتحة
    // الـUI thread مشغول بالتحميل، ولو الساعة بدأت قبل ما يرسم، الحركة
    // بتعدّي كلها ومحدش شافها.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _c.forward().whenComplete(() {
        _splashShown = true;
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
                                letterColor: F.onDark,
                                dotColor: F.gold,
                                bowlProgress: _bowl.value,
                                tailProgress: _tail.value,
                                // بتبان أول ما تبدأ تطير — قبلها مش موجودة
                                dotOpacity: _fly.value == 0 ? 0 : 1,
                                // القوس: داخلة من بره على اليمين (٩٠ وحدة رسم)
                                // وبتنزل على مكانها، والنطّة بعدها ٦px لفوق
                                dotSlide: 90 * (1 - _fly.value),
                                dotDrop:
                                    -14 * _hop(_fly.value) -
                                    6 * (1 - _land.value).clamp(0.0, 1.0),
                                dotFlash: _flashValue,
                                halo: _halo.value,
                              ),
                            ),
                          ),
                          // ١٤px أقرب للعلامة، من غير تغيير للأنيميشن.
                          const SizedBox(height: F.s8),
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
                                  color: F.onDark,
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
