import 'package:flutter/material.dart';

import '../format/name_direction.dart';
import '../theme/tokens.dart';

/// **اسم الدوا — بيبدأ من اليمين دايماً**، عربي أو إنجليزي (المالك، ٢٨ سبتمبر
/// ٢٠٢٦: «concor» كان لازق شمال).
///
/// الكتلة بتتحاذى يمين، والحروف جوّاها بتترتّب **باتجاهها هي**: اسم لاتيني
/// بيتكتب LTR («Augmentin 1g»، «500 Glucophage» — ما بيتلخبطش زي ما كان هيحصل
/// لو اتحط في فقرة RTL)، واسم عربي RTL. ده نفس اللي عزل FSI…PDI بيعمله، من
/// غير ما نحط حروف خفية جوّه النص (البحث والنسخ والاختبارات بتشوف الاسم زي ما هو).
///
/// سطرين بحد أقصى، و«…» قبل ما يزقّ الساعة اللي جنبه.
class MedName extends StatelessWidget {
  const MedName(this.name, {this.style, this.maxLines = 2, super.key});

  final String name;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
        name,
        textDirection: nameDirection(name),
        // يمين الكارت في الحالتين — «البداية» بتاعة الواجهة العربية
        textAlign: TextAlign.right,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
}

/// **صف الجرعة**: الاسم على اليمين، والساعة على الشمال في **نفس الصف** —
/// الاسم بياخد الباقي ويتقصّ قبل ما يزقّ الساعة. كل مكان بيعرض جرعة بيعدّي
/// من هنا («جدول النهاردة»، «خلال ٤٨ ساعة»، «الآن»، الأدوية، نمط كبار السن).
class NameTimeRow extends StatelessWidget {
  const NameTimeRow({
    required this.name,
    required this.time,
    this.nameStyle,
    this.timeStyle,
    this.timeKey,
    this.nameMaxLines = 2,
    super.key,
  });

  final String name;

  /// «٥:٠٠ م» / «بكرة ٥:٠٠ م» — أو أي جملة وقت. null = الاسم لوحده.
  final String? time;
  final TextStyle? nameStyle;
  final TextStyle? timeStyle;
  final Key? timeKey;
  final int nameMaxLines;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: MedName(name, style: nameStyle, maxLines: nameMaxLines)),
          if (time != null) ...[
            const SizedBox(width: F.s10),
            // الساعة ما بتلفّش ولا بتفيض: لحد تلت الصف، وبتصغر لو المكان ضيق
            // جداً (SE بخط ×١٫٣ جنب صورة وزرار). من غير LayoutBuilder عشان
            // «جدول النهاردة» جوّه IntrinsicHeight.
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    time!,
                    key: timeKey,
                    maxLines: 1,
                    style: timeStyle ?? TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
}
