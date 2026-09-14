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
      FCardTone.plain => (Colors.white, F.line, 1.0),
      FCardTone.warm => (F.ivoryWarm, F.lineSoft, 1.0),
      FCardTone.attention => (Colors.white, F.gold, 2.0),
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

/// الزرار الأساسي — ٦٤. أخضر افتراضياً، ذهبي لما الفعل هو التذكير نفسه
/// («أخدته»).
class FPrimaryButton extends StatelessWidget {
  const FPrimaryButton({
    required this.label,
    required this.onPressed,
    this.gold = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool gold;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: F.primaryButtonHeight,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: gold ? F.gold : F.green,
            foregroundColor: gold ? F.ink : Colors.white,
            disabledBackgroundColor: F.ivoryWarm,
            disabledForegroundColor: F.mutedDark,
            textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
          ),
          child: Text(label),
        ),
      );
}

/// الزرار الثانوي — ٥٦، محدّد.
class FSecondaryButton extends StatelessWidget {
  const FSecondaryButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: F.minTapTarget,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: F.ink,
            side: const BorderSide(color: F.line, width: 1.5),
            textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
            // حشو أفقي صغير: اتنين جنب بعض على شاشة ٣٩٠ لازم يشيلوا كلمة
            // وإيموجي في سطر واحد من غير ما الخط ينزل عن ٢٠
            padding: const EdgeInsets.symmetric(horizontal: F.s8),
          ),
          child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.visible),
        ),
      );
}

/// المراسي التمانية لمحرّر الجرعة — بالترتيب بتاع التصميم.
const List<String> anchorChipLabels = [
  'قبل الفطار',
  'بعد الفطار',
  'قبل الغدا',
  'بعد الغدا',
  'قبل العشا',
  'بعد العشا',
  'قبل النوم',
  'أول ما أصحى',
];

/// شريحة مرساة: النشطة ذهبية — نفس معنى الذهبي في التطبيق كله.
class AnchorChip extends StatelessWidget {
  const AnchorChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: Material(
          color: selected ? F.gold : F.ivoryPale,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(F.radiusChip),
            side: BorderSide(color: selected ? F.gold : F.line, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(F.radiusChip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: F.s14),
              // widthFactor: الشريحة على قد كلمتها جوّه Wrap — من غير كده
              // Center بيتمدّد على عرض السطر كله وكل شريحة تبقى في سطر لوحدها
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
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
      StatusTone.neutral => (F.ivoryWarm, F.mutedDark),
      StatusTone.attention => (F.gold, F.ink),
      StatusTone.ok => (F.greenOkSoft, F.greenOk),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.s6),
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
          constraints: const BoxConstraints(minHeight: F.minTapTarget),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: F.minBodySize,
                        fontWeight: FontWeight.w700,
                        color: F.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.5),
                      ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: F.gold,
                activeThumbColor: Colors.white,
                inactiveTrackColor: F.ivoryWarm,
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
  const Kicker(this.text, {this.color = F.green, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // التتبيع للاتيني بس: العربي متصل، والمسافة بين الحروف بتكسر إيقاع
    // الوصل. الـkicker العربي بيتميّز بالوزن واللون والحجم، مش بالتباعد.
    if (hasArabic(text)) {
      return Text(
        text,
        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: color),
      );
    }
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: F.minTextSize,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: F.minTextSize * F.kickerTracking,
        fontFamily: F.monoFamily,
        fontFamilyFallback: F.monoFallback,
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
        style: const TextStyle(
          fontSize: F.sectionHeadSize,
          fontWeight: FontWeight.w700,
          color: F.ink,
          height: 1.4,
        ),
      );
}
