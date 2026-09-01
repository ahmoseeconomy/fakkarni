import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/dose_state.dart';
import '../../../data/repositories/dose_event_repository.dart';
import '../../../domain/scheduling/day_routine.dart';

/// علامة مرساة على الشريط — «الفطار ٧:٣٠ ص».
class AnchorMark {
  const AnchorMark(this.anchor, this.at);
  final DayAnchor anchor;
  final DateTime at;
}

/// شريط اليوم: المراسي علامات، والجرعات واقفة بينها بترتيب الوقت.
class DayRail extends StatelessWidget {
  const DayRail({
    required this.anchors,
    required this.groups,
    required this.now,
    required this.ruleLabelFor,
    required this.onTaken,
    super.key,
  });

  final List<AnchorMark> anchors;

  /// الجرعات متجمّعة بالوقت — كل مجموعة دقيقة واحدة.
  final List<List<DoseEventView>> groups;
  final DateTime now;
  final String? Function(int doseScheduleId) ruleLabelFor;
  final void Function(List<DoseEventView> group) onTaken;

  @override
  Widget build(BuildContext context) {
    final entries = <({DateTime at, Widget child})>[
      for (final anchor in anchors)
        (at: anchor.at, child: _anchorRow(anchor)),
      for (final group in groups)
        (at: group.first.scheduledAt, child: _groupCard(group)),
    ]..sort((a, b) => a.at.compareTo(b.at));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final entry in entries) entry.child],
    );
  }

  Widget _anchorRow(AnchorMark mark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: F.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${mark.anchor.label} ${arabicTime(mark.at)}',
              style: const TextStyle(
                fontSize: F.minTextSize,
                fontWeight: FontWeight.w600,
                color: F.muted,
              ),
            ),
          ],
        ),
      );

  Widget _groupCard(List<DoseEventView> group) {
    final done = group.every((d) => d.isDone);
    return Padding(
      padding: const EdgeInsets.only(right: 20, bottom: 10),
      child: done ? _quietLine(group) : _activeCard(group),
    );
  }

  /// جرعة اتاخدت: سطر هادي بعلامة صح. **ما بتتشالش من القايمة أبداً** —
  /// المريض لازم يشوف إنه خدها، مش يلاقي السطر اختفى ويشك إنه نسي.
  Widget _quietLine(List<DoseEventView> group) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.check, size: 20, color: F.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                group.map((d) => d.medicationName).join(' + '),
                style: const TextStyle(
                  fontSize: F.minTextSize,
                  color: F.muted,
                  fontFamily: F.monoFamily,
                  fontFamilyFallback: F.monoFallback,
                ),
              ),
            ),
            Text(
              group.first.state == DoseState.skipped
                  ? 'اتأجّل'
                  : 'أخدته ${arabicTime(group.first.actedAt ?? group.first.scheduledAt)}',
              style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
            ),
          ],
        ),
      );

  Widget _activeCard(List<DoseEventView> group) {
    final at = group.first.scheduledAt;
    // فات معاده — بالذهبي والرمادي، من غير أحمر ومن غير لوم.
    final overdue = at.isBefore(now);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(F.radius),
        border: Border.all(color: overdue ? F.line : F.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final dose in group)
            Text(
              dose.amountLabel == null
                  ? dose.medicationName
                  : '${dose.medicationName} — ${dose.amountLabel}',
              style: const TextStyle(
                fontSize: F.minBodySize,
                fontWeight: FontWeight.w600,
                color: F.ink,
                fontFamily: F.monoFamily,
                fontFamilyFallback: F.monoFallback,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            [
              arabicTime(at),
              ruleLabelFor(group.first.doseScheduleId),
              if (overdue) 'فات معاده',
            ].nonNulls.join(' · '),
            style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: F.minTapTarget,
            child: OutlinedButton(
              onPressed: () => onTaken(group),
              style: OutlinedButton.styleFrom(
                foregroundColor: F.greenDeep,
                side: const BorderSide(color: F.green, width: 1.5),
                textStyle: const TextStyle(
                  fontSize: F.minBodySize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('أخدته'),
            ),
          ),
        ],
      ),
    );
  }
}
