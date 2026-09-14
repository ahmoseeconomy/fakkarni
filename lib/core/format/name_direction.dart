import 'package:flutter/widgets.dart';

/// اتجاه اسم الدوا من أول حرف قوي فيه.
///
/// الاسم اللاتيني (Antodine 40 mg) بيتكتب LTR وبيتحاذى شمال زي التصميم؛
/// اسم مكتوب بالعربي بيفضل RTL على اليمين. من غير ده كان يا اسم عربي بيتحاذى
/// شمال، يا اسم لاتيني بيتحاذى يمين.
TextDirection nameDirection(String name) {
  for (final rune in name.runes) {
    if (_isArabic(rune)) return TextDirection.rtl;
    final isLatin = (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);
    if (isLatin) return TextDirection.ltr;
  }
  return TextDirection.rtl;
}

/// فيه حرف عربي؟ — للي بيتصرّف مختلف مع العربي، زي تباعد الحروف.
bool hasArabic(String text) => text.runes.any(_isArabic);

bool _isArabic(int rune) =>
    (rune >= 0x0600 && rune <= 0x06FF) ||
    (rune >= 0x0750 && rune <= 0x077F) ||
    (rune >= 0xFB50 && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF);
