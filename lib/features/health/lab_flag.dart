import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/health/lab_range.dart';
import 'usual_words.dart';

/// العلامة اللي بتتحط جنب رقم تحليل — **المكان الوحيد اللي فيه أحمر برّه
/// `features/emergency/`**.
///
/// القاعدة اللي اتفقنا عليها، مكتوبة هنا مرة واحدة:
///
/// * **برّه النطاق** ياخد الأحمر **نص وإطار** — بيبان، ومش الحبّاية
///   المليانة بتاعة الطوارئ. الحبّاية دي معناها محفوظ لأنها لوحدها؛ لو
///   بقت علامة على تحليل كمان تبقى مش معناها حاجة. اللي هنا مقارنة بين
///   رقمين مطبوعين على ورقة، مش نداء استغاثة.
/// * **قريب من الحد** بياخد الذهبي اللي موجود أصلاً — «دي لسه عايزاك».
///   إطار ذهبي ونص حبر، مش نص ذهبي: الذهبي كنص ٢:١ على الأبيض (الدين ٥).
/// * **جوّه النطاق** ما بياخدش لون خالص — ولا إطار ولا كلمة.
///
/// ومع اللون كلمة، دايماً ([labFlagWord]): الملف بيتطبع أبيض وأسود،
/// والواحد اللي مابيفرّقش الألوان بيقرا نفس الشاشة.
class LabFlagBadge extends StatelessWidget {
  const LabFlagBadge(this.flag, {super.key});

  final LabFlag flag;

  /// لون العلامة، أو null لو السطر ما بياخدش علامة.
  static Color? tint(LabFlag flag) => switch (flag) {
    AboveRange() || BelowRange() => F.outOfRangeInk,
    NearBoundary() => F.gold,
    InsideRange() || NoPrintedRange() || RangeNotNumeric() => null,
  };

  /// لون كلمة العلامة. الأحمر بيتكتب بنفسه (مقرا في الوضعين)، والذهبي
  /// بيسيب الكلمة حبر ويشتغل إطار بس.
  static Color? wordInk(LabFlag flag) => switch (flag) {
    AboveRange() || BelowRange() => F.outOfRangeInk,
    NearBoundary() => F.ink,
    InsideRange() || NoPrintedRange() || RangeNotNumeric() => null,
  };

  @override
  Widget build(BuildContext context) {
    final word = labFlagWord(flag);
    final edge = tint(flag);
    if (word == null || edge == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: F.s10, vertical: F.s4),
      decoration: BoxDecoration(
        // **مفيش حشو.** الإطار بس — الحبّاية المليانة للطوارئ لوحدها،
        // واختبار بيقرا الـdecoration دي ويوقع لو اتحطّ لون جوّه.
        border: Border.all(color: edge, width: 1.5),
        borderRadius: BorderRadius.circular(F.radiusChip),
      ),
      child: Text(
        word,
        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: wordInk(flag)),
      ),
    );
  }
}
