import 'package:flutter/material.dart';

import '../data/admin_models.dart';
import '../format/arabic_time.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'widgets/admin_ui.dart';
import 'widgets/counts_strip.dart';
import 'widgets/device_problems.dart';
import 'widgets/fleet_health_bar.dart';
import 'widgets/motion_widgets.dart';
import 'widgets/status_cues.dart';
import 'widgets/tone_filter_chips.dart';
import 'widgets/triage_tile.dart';

/// النظرة العامة بتفتح على «محتاج نظرة دلوقتي» — الفرز الأول، والأرقام
/// حواليه. كل حاجة هنا محسوبة من نفس الصفوف اللي شاشة الحسابات بتعرضها.
///
/// **مفيش كارت «التنبيهات آخر ٢٤ ساعة»**: عدّ حالات التسليم على الأسطول
/// كله محتاج دالة سيرفر مش موجودة (`0022` المقترحة) — وكارت من غير داتا
/// اختراع.
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({
    required this.counts,
    required this.accounts,
    required this.now,
    required this.onNavigate,
    required this.onOpen,
    this.devices = const [],
    this.onOpenDevice,
    super.key,
  });

  final AdminCounts counts;
  final List<AdminAccount> accounts;

  /// كل الأجهزة (0022) — «أجهزة فيها مشكلة» بتتحسب منها هنا.
  final List<AdminDevice> devices;
  final void Function(AdminDevice device)? onOpenDevice;
  final DateTime now;
  final void Function(AdminScreen screen, {ToneFilter? tone}) onNavigate;
  final void Function(AdminAccount account) onOpen;

  static const worstLimit = 8;
  static const deviceLimit = 5;

  @override
  Widget build(BuildContext context) {
    final tones = {for (final t in RowTone.values) t: 0};
    for (final a in accounts) {
      final t = rowTone(a, now);
      tones[t] = tones[t]! + 1;
    }
    final worst = [
      for (final a in accounts)
        if (rowTone(a, now) != RowTone.quiet) a,
    ]..sort((a, b) {
        final s = severityIndex(rowTone(a, now)).compareTo(severityIndex(rowTone(b, now)));
        if (s != 0) return s;
        return b.pendingEscalations.compareTo(a.pendingEscalations);
      });
    final withOpen = accounts.where((a) => a.pendingEscalations > 0).length;

    final triage = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHead(
          'محتاج نظرة دلوقتي',
          trailing: Text(
            'مترتّبين بالخطورة — الساكت الأول',
            style: TextStyle(fontFamily: F.bodyFamily, fontSize: F.careMicroSize, color: F.mutedDark),
          ),
        ),
        const SizedBox(height: F.s10),
        for (final (i, t) in const [RowTone.silent, RowTone.alarm, RowTone.warn].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: F.s8),
            child: FadeSlideIn(
              delay: staggerDelay(context, i),
              child: TriageTile(
                tone: t,
                count: tones[t]!,
                onTap: () => onNavigate(AdminScreen.accounts, tone: ToneFilter.of(t)),
              ),
            ),
          ),
        FleetHealthBar(counts: tones, total: accounts.length),
      ],
    );

    final worstList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHead(
          'أوحش الحسابات',
          trailing: AdminTextAction(
            label: 'كل الحسابات',
            size: F.careTextSize,
            onPressed: () => onNavigate(AdminScreen.accounts),
          ),
        ),
        const SizedBox(height: F.s10),
        if (worst.isEmpty)
          const AdminPanel(text: 'مفيش حساب محتاج نظرة دلوقتي — كل النبضات وصلت.')
        else
          Container(
            decoration: BoxDecoration(
              color: F.cardGround,
              border: Border.all(color: F.line),
              borderRadius: BorderRadius.circular(F.careRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, a) in worst.take(worstLimit).indexed)
                  FadeSlideIn(
                    delay: staggerDelay(context, i),
                    child: _WorstRow(
                      account: a,
                      now: now,
                      last: i == worst.take(worstLimit).length - 1,
                      onTap: () => onOpen(a),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    // قاعدة المالك: المريض ما يشوفش مشكلة تقنية — فهي بتيجي هنا. الأكواد
    // من نبضة كل جهاز، والساكت محسوب معاهم.
    final problems = DeviceProblemsList.problems(devices, now);
    final devicesBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHead(
          'أجهزة فيها مشكلة — ${arabicNumber(problems.length)}',
          trailing: AdminTextAction(
            label: 'كل الأجهزة',
            size: F.careTextSize,
            onPressed: () => onNavigate(AdminScreen.devices),
          ),
        ),
        const SizedBox(height: F.s10),
        DeviceProblemsList(
          key: const ValueKey('overview-device-problems'),
          devices: devices,
          now: now,
          limit: deviceLimit,
          onOpen: onOpenDevice,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CountsStrip(
          counts,
          accountsWithOpenAlerts: withOpen,
          onTap: (target) => onNavigate(
            target == StatTarget.devices ? AdminScreen.devices : AdminScreen.accounts,
          ),
        ),
        const SizedBox(height: F.s16),
        devicesBlock,
        const SizedBox(height: F.s16),
        LayoutBuilder(
          builder: (context, c) {
            final twoColumns = c.maxWidth >= 860;
            if (!twoColumns) {
              return Column(children: [triage, const SizedBox(height: F.s16), worstList]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: triage),
                const SizedBox(width: F.s16),
                Expanded(child: worstList),
              ],
            );
          },
        ),
        const SizedBox(height: F.s16),
        // 0033: الممسوح بيختفي من كل قايمة — اللي فاضل عدّ مجهول
        AdminPanel(key: const ValueKey('overview-deleted'), text: deletedAccountsLine(counts)),
      ],
    );
  }
}

class _WorstRow extends StatefulWidget {
  const _WorstRow({required this.account, required this.now, required this.last, required this.onTap});

  final AdminAccount account;
  final DateTime now;
  final bool last;
  final VoidCallback onTap;

  @override
  State<_WorstRow> createState() => _WorstRowState();
}

class _WorstRowState extends State<_WorstRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: motionDuration(context, Motion.quick),
          padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
          decoration: BoxDecoration(
            color: _hover ? F.greenTint : Colors.transparent,
            border: widget.last ? null : Border(bottom: BorderSide(color: F.lineSoft)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.patientName.isEmpty ? 'من غير اسم' : a.patientName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careTextSize,
                        fontWeight: FontWeight.w600,
                        color: F.ink,
                      ),
                    ),
                    Text(
                      toneReason(a, widget.now),
                      style: TextStyle(
                        fontFamily: F.bodyFamily,
                        fontSize: F.careMicroSize,
                        color: F.mutedDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: F.s10),
              ToneBadge(rowTone(a, widget.now)),
              const SizedBox(width: F.s6),
              Icon(Icons.chevron_left_rounded, size: 18, color: F.muted),
            ],
          ),
        ),
      ),
    );
  }
}
