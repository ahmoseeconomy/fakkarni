import 'package:flutter/material.dart';

import '../format/name_direction.dart';
import '../theme/tokens.dart';

/// البدائيات — كل مقاس ولون من `F`. ولا نص هنا أقل من ١٧، وولا هدف لمس
/// أقل من ٥٦، مهما قال التصميم.

/// كارت: أبيض على العاجي، حد `line`، نصف قطر ١٤. [tone] بيغيّر التعبئة
/// (عاجي دافي للثانوي، ذهبي للي محتاج انتباه).
class FCard extends StatelessWidget {
  const FCard({
    required this.child,
    this.tone = FCardTone.plain,
    this.padding = const EdgeInsets.all(F.gap),
    this.radius = F.radiusCard,
    this.elevated = false,
    super.key,
  });

  final Widget child;
  final FCardTone tone;
  final EdgeInsets padding;
  final double radius;

  /// ظل الكارت — بس لما الكارت مرفوع عن الصفحة فعلاً.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final (fill, border, width) = switch (tone) {
      FCardTone.plain => (F.cardGround, F.line, 1.0),
      FCardTone.warm => (F.railGround, F.lineSoft, 1.0),
      FCardTone.attention => (F.cardGround, F.gold, 2.0),
      FCardTone.dark => (F.greenDeep, F.greenDeep, 1.0),
    };
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: width),
        boxShadow: elevated ? F.shadowCard : null,
      ),
      child: child,
    );
  }
}

enum FCardTone { plain, warm, attention, dark }

/// عنوان قسم — **تعريف واحد للتطبيق كله**.
///
/// كان كل شاشة بتكتبه بإيدها: شاشة الابن بـ23 من خط العرض، وملفه الصحي
/// بـ19 من غير خط العرض، و«يومك» بتالت شكل. نفس الفكرة بتلاتة مقاسات
/// بتخلي الشاشة تتقري كأنها اتكتبت على مراحل — وهي فعلاً كده.
class FSectionHead extends StatelessWidget {
  const FSectionHead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s8),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: F.displayFamily,
            fontSize: F.subtitleSize,
            fontWeight: FontWeight.w700,
            color: F.ink,
          ),
        ),
      );
}

/// الزرار الأساسي — ٦٤. أخضر افتراضياً، ذهبي لما الفعل هو التذكير نفسه
/// («أخدته»).
/// «الفقاعة اللامعة» — غلاف الشكل **الواحد** لزرارَي النداء (المرحلة ٣،
/// ٥ أكتوبر ٢٠٢٦ مساءً، المالك اختار لمعة MEDIUM): حبة شكل كبسولة
/// (مستديرة بالكامل)، لمعة بيضا من فوق (`F.glossTop` ← `F.glossMid`
/// وبتخلص بعد نص الزرار بشوية)، خيط أبيض رفيع على الحافة الجوّانية
/// الفوقانية (`F.glossEdge`)، ضل جوّاني خفيف تحت (`F.glossInnerShade`)،
/// وضل برّاني — بلون الزرار نفسه للأساسي ومحايد للثانوي.
///
/// **طبقة التعبئة فوق الطفل في شجرة الأسلاف عن قصد**: فاحص التباين
/// (`contrast_audit`) بيطلع لفوق لحد أول سطح ملوّن — لو التعبئة كانت
/// أخت مش أصل، النص كان هيتقاس على أرضية الصفحة ويقع بالغلط.
/// الزرار الحقيقي (FilledButton/OutlinedButton بتعبئة شفافة) جوّاها —
/// فالدوسة والتموّج والتعطيل والدلالات زي ما هم، والاختبارات اللي
/// بتدوّر على النوعين دول لسه بتلاقيهم.
class GlossPill extends StatelessWidget {
  const GlossPill({
    required this.fill,
    required this.shadow,
    required this.glossTop,
    required this.glossMid,
    required this.enabled,
    required this.child,
    this.edge,
    super.key,
  });

  final Color fill;
  final Color shadow;
  final Color glossTop;
  final Color glossMid;

  /// حد رفيع خفيف — الفقاعة الثانوية بس (المالك 2B): ٣:١ ضد أرضية
  /// الصفحة، فحدّها مش معتمد على الضل لوحده. الأساسي من غيره.
  final Color? edge;

  /// المعطّل مسطّح: من غير لمعة ولا ضل — زرار نايم مش فقاعة.
  final bool enabled;
  final Widget child;

  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(999));

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: pillRadius,
          // الحد على الطبقة البرّانية (مش المقصوصة) عشان يتبع الكبسولة
          border: enabled && edge != null ? Border.all(color: edge!, width: 1) : null,
          boxShadow: enabled
              ? [BoxShadow(color: shadow, blurRadius: 14, offset: const Offset(0, 6))]
              : const [],
        ),
        child: ClipRRect(
          borderRadius: pillRadius,
          child: DecoratedBox(
            decoration: BoxDecoration(color: enabled ? fill : F.railGround),
            child: Stack(
              children: [
                if (enabled) ...[
                  // اللمعة: ٣٢٪ فوق ← ١١٪ قرب النص ← مفيش بعد النص بشوية
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.45, 0.56],
                          colors: [glossTop, glossMid, glossMid.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                  // الضل الجوّاني الخفيف تحت
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.8, 1],
                          colors: [
                            F.glossInnerShade.withValues(alpha: 0),
                            F.glossInnerShade.withValues(alpha: 0),
                            F.glossInnerShade,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // الخيط الأبيض الرفيع على الحافة الفوقانية
                  Positioned(
                    top: 1.5,
                    left: 14,
                    right: 14,
                    child: Container(
                      key: const ValueKey('gloss-edge-line'),
                      height: 1.2,
                      decoration: BoxDecoration(
                        color: F.glossEdge,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
                Positioned.fill(child: child),
              ],
            ),
          ),
        ),
      );
}

/// سطح الأزرار الأساسية الملوّنة: نفس الكبسولة المعروفة، لكن بوجه مطفي
/// وحافة سفلية أغمق وظل ناعم. اللمعة تخص الأزرار البيضاء الثانوية فقط؛
/// وجودها فوق الأخضر كان بيُقرا كخط غريب وليس كعمق.
class RaisedPrimarySurface extends StatelessWidget {
  const RaisedPrimarySurface({
    required this.fill,
    required this.enabled,
    required this.child,
    this.borderRadius = GlossPill.pillRadius,
    super.key,
  });

  final Color fill;
  final bool enabled;
  final Widget child;
  final BorderRadius borderRadius;

  /// الحافة السفلية بس، مش حد داير حوالين الزرار.
  Color get rim => Color.lerp(fill, Colors.black, 0.18)!;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: enabled
              ? [BoxShadow(color: fill.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))]
              : const [],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: ColoredBox(
            color: enabled ? rim : F.railGround,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (enabled)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: fill, borderRadius: borderRadius),
                    ),
                  ),
                child,
              ],
            ),
          ),
        ),
      );
}

class FPrimaryButton extends StatelessWidget {
  const FPrimaryButton({
    required this.label,
    required this.onPressed,
    this.gold = false,
    this.height = F.primaryButtonHeight,
    this.fontSize = F.minBodySize,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool gold;

  /// أيقونة **جنب** الكلمة (مش بدالها — مفيش زرار أيقونة لوحده). null = كلمة
  /// بس، زي كل الأزرار قبل «قريب منك» (المرحلة ج، ٦ أكتوبر ٢٠٢٦).
  final IconData? icon;

  /// نمط كبار السن بيكبّره (٨٠) — عمره ما بيصغر عن الحد.
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final fill = gold ? F.gold : F.green;
    final button = FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        // التعبئة والعمق في السطح الخارجي؛ الزرار شفاف عشان يفضل التموج فوقه.
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: gold ? F.onGold : F.onGreen,
        disabledBackgroundColor: Colors.transparent,
        disabledForegroundColor: F.mutedDark,
        textStyle: TextStyle(
          fontFamily: F.bodyFamily,
          fontFamilyFallback: F.fontFallback,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
        shape: const RoundedRectangleBorder(borderRadius: GlossPill.pillRadius),
      ),
      child: _withIcon(icon, Text(label)),
    );
    return SizedBox(
      width: double.infinity,
      height: height,
      child: gold
          ? GlossPill(
              fill: fill,
              shadow: F.glossShadowOf(fill),
              glossTop: F.glossTop,
              glossMid: F.glossMid,
              enabled: onPressed != null,
              child: button,
            )
          : RaisedPrimarySurface(
              fill: fill,
              enabled: onPressed != null,
              child: button,
            ),
      ),
    );
  }
}

/// الكلمة لوحدها، أو الأيقونة جنبها في سطر واحد بيصغر لو المكان ضاق —
/// الكلمة عمرها ما بتتشال عشان الأيقونة.
Widget _withIcon(IconData? icon, Text text) => icon == null
    ? text
    : FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 22), const SizedBox(width: F.s6), text],
        ),
      );

/// الزرار الثانوي — ٥٦، محدّد.
class FSecondaryButton extends StatelessWidget {
  const FSecondaryButton({
    required this.label,
    required this.onPressed,
    this.height = F.minTapTarget,
    this.fontSize = F.minBodySize,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;

  /// زي [FPrimaryButton.icon] — جنب الكلمة، مش بدالها.
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: height,
        // «فقاعة» بيضا بنفس بنية لمعة الأساسي — من غير حد صلب (قرار
        // المالك): حدّها الضل المحايد. بالليل السطح غامق واللمعة أضعف
        // بكتير (`glossTopWeak`) عشان ما تلمعش في العين.
        child: GlossPill(
          fill: F.bubbleGround,
          shadow: F.bubbleShadow,
          edge: F.bubbleEdge,
          glossTop: F.isDark ? F.glossTopWeak : F.glossTop,
          glossMid: F.isDark ? F.glossMidWeak : F.glossMid,
          enabled: onPressed != null,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: F.ink,
              side: BorderSide.none,
              disabledForegroundColor: F.mutedDark,
              textStyle: TextStyle(fontFamily: F.bodyFamily, fontFamilyFallback: F.fontFallback, fontSize: fontSize, fontWeight: FontWeight.w600),
              shape: const RoundedRectangleBorder(borderRadius: GlossPill.pillRadius),
              // حشو أفقي صغير: اتنين جنب بعض على شاشة ٣٩٠ لازم يشيلوا كلمة
              // وإيموجي في سطر واحد من غير ما الخط ينزل عن ٢٠
              padding: EdgeInsets.symmetric(horizontal: F.s8),
            ),
            child: _withIcon(icon, Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.visible)),
          ),
        ),
      );
}

/// شريحة مرساة: النشطة ذهبية — نفس معنى الذهبي في التطبيق كله.
class AnchorChip extends StatelessWidget {
  const AnchorChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconColor,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// أيقونة قبل الكلمة (فلاتر «القريب مني») — بلونها، وعلى الشريحة المختارة
  /// بلون الكلمة عشان تتقري على الدهبي.
  final IconData? icon;
  final Color? iconColor;

  Widget get _labelText => Text(
        label,
        style: TextStyle(
          fontSize: F.minBodySize,
          fontWeight: FontWeight.w700,
          color: selected ? F.onGold : F.ink,
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: Material(
          color: selected ? F.gold : F.railGround,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radiusChip),
            side: BorderSide(color: selected ? F.gold : F.line, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radiusChip),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: F.s14),
              // widthFactor: الشريحة على قد كلمتها جوّه Wrap — من غير كده
              // Center بيتمدّد على عرض السطر كله وكل شريحة تبقى في سطر لوحدها
              child: Center(
                widthFactor: 1,
                // من غير أيقونة الكلمة زي ما كانت (بتلفّ في الشرايح الضيقة)
                child: icon == null
                    ? _labelText
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 22, color: selected ? F.onGold : (iconColor ?? F.ink)),
                          const SizedBox(width: F.s6),
                          Flexible(child: _labelText),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
}

/// شارة حالة: كلمة بلون — «اتاخد» أخضر، «لسه» ذهبي، الباقي رمادي.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, this.tone = StatusTone.neutral, super.key});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (fill, text) = switch (tone) {
      StatusTone.neutral => (F.railGround, F.mutedDark),
      StatusTone.attention => (F.gold, F.ink),
      StatusTone.ok => (F.greenOkSoft, F.greenOk),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(F.radiusChip),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: text),
      ),
    );
  }
}

enum StatusTone { neutral, attention, ok }

/// مفتاح بكلمة — صف كامل ٥٦+، الكلمة على اليمين والمفتاح على الشمال.
/// شغّال = ذهبي (الحالة اللي إنت عليها).
class FSwitch extends StatelessWidget {
  const FSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(F.radiusCard),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: F.minTapTarget),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: FontWeight.w700,
                        color: F.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                      ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: F.gold,
                activeThumbColor: F.onDark,
                inactiveTrackColor: F.railGround,
                inactiveThumbColor: F.muted,
              ),
            ],
          ),
        ),
      );
}

/// Kicker: سطر صغير فوق العنوان — اللاتيني mono بحروف متباعدة ‎.14em،
/// والعربي من غير تباعد.
///
/// التصميم بيرسمه ١٠؛ إحنا **١٧** — الحد الأدنى بتاعنا قاعدة، وده نص
/// ثانوي فعلاً، فمش بيخسر حاجة لما يكبر شوية.
class Kicker extends StatelessWidget {
  const Kicker(this.text, {this.color, super.key});

  final String text;

  /// null = الأخضر بتاع الوضع الحالي (الرمز دلوقتي getter، فما ينفعش يبقى
  /// قيمة افتراضية ثابتة).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // التتبيع للاتيني بس: العربي متصل، والمسافة بين الحروف بتكسر إيقاع
    // الوصل. الـkicker العربي بيتميّز بالوزن واللون والحجم، مش بالتباعد.
    if (hasArabic(text)) {
      return Text(
        text,
        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: color ?? F.green),
      );
    }
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: F.minTextSize,
        fontWeight: FontWeight.w600,
        color: color ?? F.green,
        letterSpacing: F.minTextSize * F.kickerTracking,
        fontFamily: F.bodyFamily,
        fontFamilyFallback: F.fontFallback,
      ),
    );
  }
}

/// عنوان قسم — ١٩.
class SectionHead extends StatelessWidget {
  const SectionHead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: F.sectionHeadSize,
          fontWeight: FontWeight.w700,
          color: F.ink,
          height: 1.4,
        ),
      );
}

/// ملاحظة «محتاجة انتباهك»: نص غامق جنب حافة ذهبي.
///
/// **مش نص ذهبي**: الذهبي على العاجي تباينه ≈ ١.٩:١ — راجل عنده ٧٢ سنة
/// بنضارة القراية مش هيقراه. الذهبي بيفضل هو المعنى، على الحافة.
class GoldNote extends StatelessWidget {
  const GoldNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.only(start: F.s10, top: F.s4, bottom: F.s4),
        decoration: const BoxDecoration(
          border: BorderDirectional(start: BorderSide(color: F.gold, width: 4)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
        ),
      );
}
