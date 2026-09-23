import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../format/arabic_time.dart';
import '../../format/relative_time.dart';
import '../../theme/tokens.dart';

/// حالة صف في الجدول — **دالة نقية**، بتتختبر بأرقام من غير ما نرسم حاجة.
///
/// الترتيب هو الخطورة: الساكت أخطر من التنبيه، والتنبيه أخطر من الملاحظة.
enum RowTone {
  /// الموبايل ما بعتش نبضة خالص، أو بقاله أكتر من يومين — **الغياب أخطر من
  /// أي كود** (قاعدة ٠٠١٨): جهاز ساكت مش بيقدر يقول عن نفسه إنه مكسور.
  silent,

  /// فيه تنبيه مفتوح — جرعة بتفوت دلوقتي.
  alarm,

  /// حاجة هتكسر التذكير لو اتسابت: البطارية مقيّدة، أو المدى خلص.
  warn,

  quiet,
}

/// بعد كام ساعة سكوت نعتبر الموبايل ساكت. يومين — يوم من غير نبضة ممكن
/// يبقى عطلة، يومين معناهم حاجة وقفت.
const Duration silentAfter = Duration(hours: 48);

RowTone rowTone(AdminAccount account, DateTime now) {
  final seen = account.seenAt;
  if (seen == null || now.difference(seen) > silentAfter) return RowTone.silent;
  if (account.pendingEscalations > 0) return RowTone.alarm;
  if (account.batteryRestricted || !account.reminderHorizonOk) return RowTone.warn;
  return RowTone.quiet;
}

/// الخطورة كرقم — الأقل أخطر. ده اللي «مترتّبين بالخطورة» بيقصده.
int severityIndex(RowTone tone) => tone.index;

/// الكلمة اللي جنب اللون — **اللون عمره ما يشيل المعنى لوحده**.
String toneWord(RowTone tone) => switch (tone) {
      RowTone.silent => 'مش بيبعت نبضة',
      RowTone.alarm => 'تنبيه',
      RowTone.warn => 'ملاحظة',
      RowTone.quiet => 'تمام',
    };

/// سطر الشرح تحت الكلمة في بلاطة الفرز.
String toneDescription(RowTone tone) => switch (tone) {
      RowTone.silent => 'موبايلات ما بعتتش نبضة من أكتر من يومين — التذكير ممكن يكون واقف.',
      RowTone.alarm => 'جرعة بتفوت دلوقتي والمتابع اتبلّغ.',
      RowTone.warn => 'بطارية مقيّدة أو مدى التذكير خلص — هيقع لو اتساب.',
      RowTone.quiet => 'النبضة وصلت، ومفيش تنبيه مفتوح.',
    };

/// ليه الحساب ده في قايمة «أوحش الحسابات» — بكلام الحالة نفسها.
String toneReason(AdminAccount account, DateTime now) =>
    switch (rowTone(account, now)) {
      RowTone.silent => account.seenAt == null
          ? 'الموبايل عمره ما بعت نبضة'
          : 'آخر نبضة ${timeSince(now, account.seenAt!)}',
      RowTone.alarm =>
        '${arabicNumber(account.pendingEscalations)} تنبيه مفتوح — '
            '${arabicNumber(account.missedDoses24h)} جرعة ما اتأكدتش',
      RowTone.warn => account.batteryRestricted
          ? 'البطارية مقيّدة — التذكير ممكن يتأخر'
          : 'مدى التذكير خلص — محتاج يفتح التطبيق',
      RowTone.quiet => 'كله تمام',
    };

Color toneColour(RowTone tone) => switch (tone) {
      RowTone.silent => F.mutedDark,
      RowTone.alarm => F.outOfRangeInk,
      RowTone.warn => F.gold,
      RowTone.quiet => F.green,
    };

/// نفس اللون بس بقيم النهار — للحبّة البيضا على رأس اللوحة الغامق.
Color toneColourLight(RowTone tone) => switch (tone) {
      RowTone.silent => const Color(0xFF43544C),
      RowTone.alarm => F.red,
      RowTone.warn => F.gold,
      RowTone.quiet => F.greenLight,
    };

/// **شكل مختلف لكل حالة، مش لون مختلف بس** — أحمر وأخضر بيتشابهوا عند
/// واحد من كل اتناشر راجل، والدايرة والمثلث لأ.
IconData toneIcon(RowTone tone) => switch (tone) {
      RowTone.silent => Icons.sensors_off_rounded,
      RowTone.alarm => Icons.warning_rounded,
      RowTone.warn => Icons.error_rounded,
      RowTone.quiet => Icons.check_circle_rounded,
    };

/// حبّة الحالة: أيقونة بشكلها ولونها، والكلمة بلون المتن، على تظليل خفيف.
/// [onWhite] للرأس الغامق: حبّة بيضا بألوان النهار.
class ToneBadge extends StatelessWidget {
  const ToneBadge(this.tone, {this.onWhite = false, super.key});

  final RowTone tone;
  final bool onWhite;

  @override
  Widget build(BuildContext context) {
    final colour = onWhite ? toneColourLight(tone) : toneColour(tone);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(F.s8, F.s4, F.s10, F.s4),
      decoration: BoxDecoration(
        color: onWhite ? F.white : colour.withValues(alpha: F.isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(toneIcon(tone), size: 14, color: colour),
          const SizedBox(width: F.s6),
          Text(
            toneWord(tone),
            style: TextStyle(
              fontFamily: F.bodyFamily,
              fontSize: F.careMicroSize,
              fontWeight: FontWeight.w600,
              color: onWhite ? F.inkLight : F.ink,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
