import 'package:flutter/material.dart';

import '../../format/grouped.dart';
import '../../theme/tokens.dart';
import 'admin_ui.dart';
import 'status_cues.dart';

/// شريط مقسوم بنسبة كل حالة، وتحته مفتاحه بالكلمة والعدد والنسبة.
/// **أصغر حصة بتفضل باينة** (٣ بكسل على الأقل) — تلات حسابات ساكتة من
/// ألفين ما ينفعش يختفوا من الشريط.
class FleetHealthBar extends StatelessWidget {
  const FleetHealthBar({required this.counts, required this.total, super.key});

  final Map<RowTone, int> counts;
  final int total;

  static const order = [RowTone.quiet, RowTone.warn, RowTone.alarm, RowTone.silent];

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.symmetric(horizontal: F.s16, vertical: F.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'صحة الأسطول — ${arabicGrouped(total)} حساب',
            style: TextStyle(
              fontFamily: F.bodyFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: F.ink,
            ),
          ),
          const SizedBox(height: F.s10),
          LayoutBuilder(
            builder: (context, c) {
              final width = c.maxWidth;
              final present = [for (final t in order) if ((counts[t] ?? 0) > 0) t];
              final gaps = present.isEmpty ? 0 : (present.length - 1) * 2.0;
              return Container(
                height: 12,
                decoration: BoxDecoration(
                  color: F.railGround,
                  borderRadius: BorderRadius.circular(999),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    for (final (i, t) in present.indexed) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Container(
                        width: total == 0
                            ? 0
                            : ((counts[t]! / total) * (width - gaps)).clamp(3.0, width),
                        color: toneColour(t),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: F.s10),
          Wrap(
            spacing: F.s16,
            runSpacing: F.s6,
            children: [
              for (final t in order) _Legend(tone: t, count: counts[t] ?? 0, total: total),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.tone, required this.count, required this.total});

  final RowTone tone;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontFamily: F.bodyFamily, fontSize: 13, color: F.mutedDark);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(shape: BoxShape.circle, color: toneColour(tone)),
        ),
        const SizedBox(width: F.s6),
        Text(toneWord(tone), style: muted),
        const SizedBox(width: F.s4),
        Text(
          arabicGrouped(count),
          style: TextStyle(
            fontFamily: F.bodyFamily,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: F.ink,
          ),
        ),
        const SizedBox(width: F.s4),
        Text('(${total == 0 ? '٠٫٠٪' : arabicPercent(count / total)})', style: muted),
      ],
    );
  }
}
