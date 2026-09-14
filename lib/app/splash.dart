import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/fa_mark.dart';

/// شاشة البداية — ١.٦ ث مؤلّفة، وعمرها ما بتوقف التطبيق.
///
/// الشاشة الأولى بتتبني **تحتها** من أول فريم؛ دي طبقة فوقها بتتلاشى.
/// أرضيتها هي هي أرضية `LaunchScreen.storyboard` (`greenDeep` مسطّحة)،
/// فالقطع من شاشة النظام مش بيبان. جدول التوقيت من README:
///   0.10 رسم الحلقة ثم الذيل (0.55 ث) · 0.65 النقطة تظهر وتنزل ٤px ·
///   0.85 هالة واحدة · 0.95 «فكرني» تطلع ٨px · 1.60 تكبير ١.٠٤ وتلاشي ٠.٣ ث.
/// مع «تقليل الحركة» بتظهر الحالة النهائية على طول وتختفي بسرعة.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({required this.child, super.key});

  final Widget child;

  /// إجمالي الطبقة: ١.٦ ث + ٠.٣ ث تلاشي.
  static const Duration total = Duration(milliseconds: 1900);

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

  // كل الفترات نسبة من ١.٩ ث
  static double _at(int ms) => ms / 1900;

  late final _bowl = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(100), _at(400), curve: Curves.easeOut),
  );
  late final _tail = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(350), _at(650), curve: Curves.easeOut),
  );
  late final _dot = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(650), _at(900), curve: Curves.easeOut),
  );
  late final _halo = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(850), _at(1450), curve: Curves.easeOut),
  );
  late final _word = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(950), _at(1300), curve: Curves.easeOut),
  );
  late final _exit = CurvedAnimation(
    parent: _c,
    curve: Interval(_at(1600), _at(1900), curve: Curves.easeIn),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // الحالة النهائية على طول، وتلاشي قصير
      _c.value = _at(1600);
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
                                dotOpacity: _dot.value,
                                dotDrop: -4 + 4 * _dot.value,
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
