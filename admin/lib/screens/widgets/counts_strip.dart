import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../format/arabic_time.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'motion_widgets.dart';

/// شريط الأربع أرقام. **محسوبين في السيرفر من نفس صفوف الجدول**، فالشريط
/// والجدول ما يقدروش يختلفوا.
///
/// **مفيش خط اتجاه ولا سهم**: `admin_counts()` بترجّع لحظة واحدة، من غير
/// تاريخ — وسهم من غير رقم قبله كان هيبقى اختراع.
class CountsStrip extends StatelessWidget {
  const CountsStrip(this.counts, {this.accountsWithOpenAlerts = 0, super.key});

  final AdminCounts counts;

  /// عدد الحسابات اللي فيها تنبيه مفتوح — من نفس الصفوف اللي الجدول
  /// بيعرضها (مش نداء تاني)، عشان كارت «الحسابات» يقول لو فيه حاجة.
  final int accountsWithOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final cells = <_Stat>[
      _Stat(
        Icons.people_alt_rounded,
        'الحسابات',
        counts.totalPatients,
        attention: accountsWithOpenAlerts > 0,
        note: accountsWithOpenAlerts > 0
            ? 'منهم ${arabicNumber(accountsWithOpenAlerts)} فيهم تنبيه مفتوح'
            : null,
      ),
      _Stat(Icons.family_restroom_rounded, 'المتابعين', counts.totalFollowers),
      _Stat(Icons.bolt_rounded, 'نشط آخر ٧ أيام', counts.active7d),
      _Stat(
        Icons.battery_alert_rounded,
        'بطارية مقيّدة',
        counts.batteryRestricted,
        attention: counts.batteryRestricted > 0,
      ),
    ];
    // على الموبايل اتنين في الصف بدل واحد — أربع كروت بعرض ٢٠٠ على شاشة
    // ٣٩٠ بيبقوا عمود طوله شاشة كاملة قبل أول حساب في القايمة.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < phoneBreakpoint;
        final width = narrow ? (constraints.maxWidth - F.careRowGap) / 2 : 210.0;
        return Wrap(
          spacing: F.careRowGap,
          runSpacing: F.careRowGap,
          children: [
            for (final (i, stat) in cells.indexed)
              FadeSlideIn(
                delay: staggerDelay(context, i),
                child: SizedBox(
                  width: width,
                  child: _StatCard(stat: stat, narrow: narrow),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Stat {
  const _Stat(this.icon, this.label, this.value, {this.attention = false, this.note});
  final IconData icon;
  final String label;
  final int value;
  final bool attention;
  final String? note;
}

/// كارت رقم: أيقونة في دايرة، الرقم بيعدّ لحد قيمته، وتحته الكلمة.
/// الحد الجانبي دهبي لما الرقم محتاج نظرة — الدهبي هو «محتاجاك دلوقتي».
///
/// **على الموبايل الكارت بيتمدّ عرضاً مش طولاً**: أيقونة على الشمال والرقم
/// والكلمة جنبها. أربع كروت طويلة (٣٥٠ بكسل) كانت بتزقّ قايمة الحسابات
/// تحت الشاشة على ٣٧٥×٦٦٧ — والمدير فاتح الموبايل عشان يشوف الحسابات.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat, required this.narrow});

  final _Stat stat;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final accent = stat.attention ? F.gold : F.green;
    final icon = Container(
      width: narrow ? 30 : 34,
      height: narrow ? 30 : 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: F.isDark ? 0.2 : 0.14),
      ),
      child: Icon(stat.icon, size: narrow ? 16 : 18, color: accent),
    );
    final number = CountUp(
      stat.value,
      style: TextStyle(
        fontFamily: F.displayFamily,
        fontSize: narrow ? F.subtitleSize : F.display3,
        fontWeight: FontWeight.w700,
        color: F.ink,
        height: 1.1,
      ),
    );
    final label = Text(
      stat.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: F.bodyFamily,
        fontSize: narrow ? F.careMicroSize : F.careTextSize,
        color: F.mutedDark,
      ),
    );
    final note = stat.note == null
        ? null
        : Text(
            stat.note!,
            maxLines: narrow ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: F.bodyFamily,
              fontSize: F.careMicroSize,
              fontWeight: FontWeight.w600,
              color: F.ink,
            ),
          );

    if (narrow) {
      return AdminCard(
        edge: stat.attention ? F.gold : null,
        padding: const EdgeInsets.all(F.s10),
        child: Row(
          children: [
            icon,
            const SizedBox(width: F.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [number, label, ?note],
              ),
            ),
          ],
        ),
      );
    }
    return AdminCard(
      edge: stat.attention ? F.gold : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          const SizedBox(height: F.s10),
          number,
          const SizedBox(height: F.s4),
          label,
          if (note != null) ...[const SizedBox(height: F.s4), note],
        ],
      ),
    );
  }
}
