import 'package:flutter/widgets.dart';

/// أرقام الحركة — مكان واحد، عشان الشاشات ما تخترعش مدد.
///
/// **كل حركة بتتعطّل مع `prefers-reduced-motion`**: فلاتر على الويب بيوصّل
/// الإعداد ده في `disableAnimations`، و[motionOn] هي الباب الوحيد اللي
/// الودجتس بتسأله. مفيش ودجت بتقرا الإعداد لوحدها.
class Motion {
  static const quick = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 300);
  static const curve = Curves.easeOutCubic;

  /// الصفوف بتدخل ورا بعض بالفرق ده، ولحد الصف الخمستاشر — اللي بعده بيدخل
  /// مع آخر واحد، عشان قايمة طويلة ما تفضلش تنقّط لثانيتين.
  static const staggerStep = Duration(milliseconds: 30);
  static const staggerMax = 15;
}

bool motionOn(BuildContext context) => !MediaQuery.disableAnimationsOf(context);

/// المدة لو الحركة شغّالة، وصفر لو المستخدم طالب تقليل الحركة.
Duration motionDuration(BuildContext context, Duration d) =>
    motionOn(context) ? d : Duration.zero;

Duration staggerDelay(BuildContext context, int index) => motionOn(context)
    ? Motion.staggerStep * index.clamp(0, Motion.staggerMax - 1)
    : Duration.zero;
