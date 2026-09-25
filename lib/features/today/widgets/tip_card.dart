import '../../voice/help_button.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../tips/tip_picker.dart';
import '../tips/tips_ar.dart';

/// **«معلومة تهمك»** — مكان كارت المية على «يومك».
///
/// معلومة واحدة في اليوم عن أدويته هو، من نص مكتوب بإيد إنسان ومراجَع
/// (`tips/tips_ar.dart`) — لا ذكاء ولا شبكة. نفس شكل كارت المية القديم:
/// نفس الحواف والحشو، والأيقونة في بلاطة لوحدها على ناحية البداية، على
/// أرضية `F.tipSurface` (أزرق فاتح جداً). كارت هادي تحت كتلتي «الآن»
/// و«جدول النهاردة» — مش تنبيه ومش ذهبي. الدوسة بتفتح الدوا اللي المعلومة
/// عنه لو فيه، وإلا ولا حاجة.
class TipCard extends StatelessWidget {
  const TipCard({required this.tip, this.onOpenMedication, super.key});

  final Tip tip;
  final void Function(int medicationId)? onOpenMedication;

  /// العنوان أكبر وأتقل من نص المعلومة بوضوح — مش نفس الحجم بلون تاني.
  static const double titleSize = F.subtitleSize;

  @override
  Widget build(BuildContext context) {
    final medicationId = tip.medicationId;
    final onTap = medicationId == null || onOpenMedication == null ? null : () => onOpenMedication!(medicationId);
    return Semantics(
      button: onTap != null,
      child: Material(
        color: F.tipSurface,
        borderRadius: BorderRadius.circular(F.radiusLarge),
        child: InkWell(
          key: const ValueKey('tip-card'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(F.radiusLarge),
          child: Container(
            padding: const EdgeInsets.all(F.gap),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(F.radiusLarge),
              border: Border.all(color: F.tipGlow.withValues(alpha: 0.35), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GlowingBulb(),
                const SizedBox(width: F.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HelpRow(
                        id: 'help_tip',
                        child: Text(
                          tipCardTitle,
                          key: const ValueKey('tip-title'),
                          style: TextStyle(
                            fontFamily: F.displayFamily,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            color: F.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: F.s6),
                      Text(
                        tip.text,
                        key: const ValueKey('tip-text'),
                        style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w500, color: F.ink, height: 1.45),
                      ),
                      if ((tip.instructions ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: F.s8),
                        GoldNote(
                          key: const ValueKey('tip-instructions'),
                          tip.instructions!.trim(),
                        ),
                      ],
                      if (onTap != null) ...[
                        const SizedBox(height: F.s6),
                        Text(
                          'افتح الدوا',
                          style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.green),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// لمبة بتنوّر وتطفي بالتوهّج وبس — مفيش هزّ ولا تكبير.
///
/// دورة [cycle] (١٫٦ ثانية) بمنحنى ناعم. تحت «تقليل الحركة» لمبة منوّرة
/// ثابتة. وبتقف لما الشاشة مش ظاهرة: `TickerMode` بيوقّفها في
/// `IndexedStack`/`Offstage` لوحده، والتطبيق في الخلفية بيوقّفها من هنا.
class GlowingBulb extends StatefulWidget {
  const GlowingBulb({super.key});

  static const Duration cycle = Duration(milliseconds: 1600);

  @override
  State<GlowingBulb> createState() => _GlowingBulbState();
}

class _GlowingBulbState extends State<GlowingBulb>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _glow = AnimationController(vsync: this, duration: GlowingBulb.cycle);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _glow.repeat(reverse: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_glow.isAnimating) _glow.repeat(reverse: true);
    } else {
      _glow.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _glow.dispose();
    super.dispose();
  }

  Widget _tile(Color colour, double glow) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: F.pageGround.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(F.radiusTile),
          boxShadow: [
            if (glow > 0)
              BoxShadow(color: F.tipGlow.withValues(alpha: 0.45 * glow), blurRadius: 10 + 12 * glow),
          ],
        ),
        child: Icon(Icons.lightbulb, size: 26, color: colour),
      );

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return _tile(F.tipGlow, 0.6);
    }
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_glow.value);
        // النور بيتغيّر بالسطوع: من نسخة باهتة للون الكامل
        final colour = Color.lerp(F.tipGlow.withValues(alpha: 0.45), F.tipGlow, t)!;
        return _tile(colour, t);
      },
    );
  }
}
