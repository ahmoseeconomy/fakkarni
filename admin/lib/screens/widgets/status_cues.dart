import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../theme/tokens.dart';

/// حالة صف في الجدول — **دالة نقية**، بتتختبر بأرقام من غير ما نرسم حاجة.
///
/// الترتيب هو الأولوية: الساكت أخطر من التنبيه، والتنبيه أخطر من الملاحظة.
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

/// الكلمة اللي جنب اللون — **اللون عمره ما يشيل المعنى لوحده**.
String toneWord(RowTone tone) => switch (tone) {
      RowTone.silent => 'مش بيبعت نبضة',
      RowTone.alarm => 'تنبيه',
      RowTone.warn => 'ملاحظة',
      RowTone.quiet => 'تمام',
    };

Color toneColour(RowTone tone) => switch (tone) {
      RowTone.silent => F.mutedDark,
      RowTone.alarm => F.outOfRangeInk,
      RowTone.warn => F.gold,
      RowTone.quiet => F.green,
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
class ToneBadge extends StatelessWidget {
  const ToneBadge(this.tone, {super.key});

  final RowTone tone;

  @override
  Widget build(BuildContext context) {
    final colour = toneColour(tone);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(F.s8, F.s4, F.s10, F.s4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: F.isDark ? 0.18 : 0.12),
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
              color: F.ink,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
