import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../theme/tokens.dart';

/// حالة صف في الجدول — **دالة نقية**، بتتختبر بأرقام من غير ما نرسم حاجة.
enum RowTone {
  /// محتاج تدخّل دلوقتي: الموبايل ساكت، أو فيه تنبيه مفتوح.
  alarm,

  /// حاجة هتكسر التذكير لو اتسابت: البطارية مقيّدة، أو المدى خلص.
  warn,

  quiet,
}

/// بعد كام ساعة سكوت نعتبر الموبايل ساكت. اليوم كامل زي `staleAfter` بتاع
/// شاشة الابن — يوم من غير نبضة يعني حاجة وقفت، مش إنه نام بدري.
const Duration silentAfter = Duration(hours: 48);

/// **الغياب أخطر من أي كود** (قاعدة ٠٠١٨): موبايل عمره ما بعت نبضة
/// مش بيقدر يقول عن نفسه إنه مكسور.
RowTone rowTone(AdminAccount account, DateTime now) {
  final seen = account.seenAt;
  if (seen == null || now.difference(seen) > silentAfter) return RowTone.alarm;
  if (account.pendingEscalations > 0) return RowTone.alarm;
  if (account.batteryRestricted || !account.reminderHorizonOk) return RowTone.warn;
  return RowTone.quiet;
}

/// كلمة بتشرح اللون — **اللون عمره ما يشيل المعنى لوحده**.
String toneWord(RowTone tone) => switch (tone) {
      RowTone.alarm => 'محتاج نظرة',
      RowTone.warn => 'فيه ملاحظة',
      RowTone.quiet => 'تمام',
    };

Color toneColour(RowTone tone) => switch (tone) {
      RowTone.alarm => F.outOfRangeInk,
      RowTone.warn => F.gold,
      RowTone.quiet => F.green,
    };

/// شارة الحالة: حد ملوّن + كلمة. **مفيش تعبئة حمرا** — نفس ضبط النفس
/// اللي في التطبيق.
class ToneBadge extends StatelessWidget {
  const ToneBadge(this.tone, {super.key});

  final RowTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: F.s8, vertical: F.s4),
      decoration: BoxDecoration(
        border: Border.all(color: toneColour(tone), width: 1.5),
        borderRadius: BorderRadius.circular(F.radiusChip),
      ),
      child: Text(
        toneWord(tone),
        style: TextStyle(
          fontFamily: F.bodyFamily,
          fontSize: F.careTextSize,
          fontWeight: FontWeight.w600,
          color: F.ink,
        ),
      ),
    );
  }
}
