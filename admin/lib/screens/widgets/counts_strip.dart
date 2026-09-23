import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../format/arabic_time.dart';
import '../../format/grouped.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'motion_widgets.dart';

/// الكارت بيودّي فين لما يتداس عليه.
enum StatTarget { accounts, devices }

/// شريط الأربع أرقام. **محسوبين في السيرفر من نفس صفوف الجدول**، فالشريط
/// والجدول ما يقدروش يختلفوا.
///
/// **مفيش خط اتجاه ولا سهم**: `admin_counts()` بترجّع لحظة واحدة، من غير
/// تاريخ — وسهم من غير رقم قبله كان هيبقى اختراع.
class CountsStrip extends StatelessWidget {
  const CountsStrip(
    this.counts, {
    this.accountsWithOpenAlerts = 0,
    this.onTap,
    super.key,
  });

  final AdminCounts counts;

  /// عدد الحسابات اللي فيها تنبيه مفتوح — من نفس الصفوف اللي الجدول
  /// بيعرضها (مش نداء تاني)، عشان كارت «الحسابات» يقول لو فيه حاجة.
  final int accountsWithOpenAlerts;
  final void Function(StatTarget target)? onTap;

  @override
  Widget build(BuildContext context) {
    final total = counts.totalPatients;
    final activePct = total == 0 ? null : arabicPercent(counts.active7d / total);
    final cells = <StatSpec>[
      StatSpec(
        Icons.people_alt_rounded,
        'الحسابات',
        total,
        attention: accountsWithOpenAlerts > 0,
        note: accountsWithOpenAlerts > 0
            ? 'منهم ${arabicNumber(accountsWithOpenAlerts)} فيهم تنبيه مفتوح'
            : null,
        target: StatTarget.accounts,
      ),
      StatSpec(Icons.family_restroom_rounded, 'المتابعين', counts.totalFollowers,
          target: StatTarget.accounts),
      StatSpec(Icons.bolt_rounded, 'نشط آخر ٧ أيام', counts.active7d,
          note: activePct == null ? null : '$activePct من الأسطول', target: StatTarget.accounts),
      StatSpec(
        Icons.battery_alert_rounded,
        'بطارية مقيّدة',
        counts.batteryRestricted,
        attention: counts.batteryRestricted > 0,
        target: StatTarget.devices,
      ),
    ];
    return StatCards(cells, onTap: onTap);
  }
}

/// مواصفة كارت رقم — بتتستعمل في النظرة العامة وفي صحة الأجهزة.
class StatSpec {
  const StatSpec(this.icon, this.label, this.value, {this.attention = false, this.note, this.target});
  final IconData icon;
  final String label;
  final int value;
  final bool attention;
  final String? note;
  final StatTarget? target;
}

/// شبكة كروت الأرقام. على الموبايل اتنين في الصف وكل كارت عرضي.
class StatCards extends StatelessWidget {
  const StatCards(this.cells, {this.onTap, super.key});

  final List<StatSpec> cells;
  final void Function(StatTarget target)? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < phoneBreakpoint;
        final perRow = narrow ? 2 : cells.length;
        final width = (constraints.maxWidth - F.careRowGap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: F.careRowGap,
          runSpacing: F.careRowGap,
          children: [
            for (final (i, stat) in cells.indexed)
              FadeSlideIn(
                delay: staggerDelay(context, i),
                child: SizedBox(
                  width: width.clamp(120.0, 420.0),
                  child: _StatCard(
                    stat: stat,
                    narrow: narrow,
                    onTap: stat.target == null || onTap == null ? null : () => onTap!(stat.target!),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// كارت رقم: أيقونة في دايرة، الرقم بيعدّ لحد قيمته، وتحته الكلمة.
/// الحد الجانبي دهبي لما الرقم محتاج نظرة — الدهبي هو «محتاجاك دلوقتي».
///
/// **على الموبايل الكارت بيتمدّ عرضاً مش طولاً**: أربع كروت طويلة كانت
/// بتزقّ قايمة الحسابات تحت الشاشة على ٣٧٥×٦٦٧.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat, required this.narrow, this.onTap});

  final StatSpec stat;
  final bool narrow;
  final VoidCallback? onTap;

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
        onTap: onTap,
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
      onTap: onTap,
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
