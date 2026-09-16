import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/format/name_direction.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/patient_voice.dart';
import '../../../domain/patient/sex.dart';
import '../../../data/dose_state.dart';
import '../../../data/repositories/dose_event_repository.dart';
import '../../../domain/scheduling/day_routine.dart';

/// علامة مرساة على الشريط — «الفطار · ٧:٣٠ ص».
class AnchorMark {
  const AnchorMark(this.anchor, this.at);
  final DayAnchor anchor;
  final DateTime at;
}

/// سكة اليوم (المخطط 24): خط رأسي على **اليمين**، المراسي عُقد خضرا
/// بالاسم والوقت، والجرعات كروت متعلّقة بالسكة بينهم بترتيب الوقت.
///
/// قاعدة اللون: الذهبي معناه «دي لسه عايزاك» — الجرعة المنتظرة والفايتة
/// الاتنين بحافة ذهبية، والفايتة بتقول «لسه ما اتأكدتش» من غير لوم. مفيش
/// رمادي للفايتة ومفيش أحمر. المأخوذة بتنطوي لسطر ✓ هادي وما بتتشالش.
///
/// الكروت مفيهاش زرار «أخدته» — الزرار الأساسي الوحيد هو اللي في الكارت
/// المثبّت فوق. الدوسة على كارت بتفتح شاشة التذكير بتاعته — والكارت
/// موصوف بالكلام (الاسم والوقت والقاعدة)، فمش محتاج كلمة «افتح».
class DayRail extends StatelessWidget {
  const DayRail({
    required this.anchors,
    required this.groups,
    required this.now,
    required this.ruleLabelFor,
    required this.onOpen,
    super.key,
  });

  final List<AnchorMark> anchors;

  /// الجرعات متجمّعة بالوقت — كل مجموعة دقيقة واحدة.
  final List<List<DoseEventView>> groups;
  final DateTime now;
  final String? Function(int doseScheduleId) ruleLabelFor;
  final void Function(List<DoseEventView> group) onOpen;

  /// عرض عمود السكة، ومقاس العقدة.
  static const double _railWidth = 28;
  static const double _node = 14;

  @override
  Widget build(BuildContext context) {
    final entries = <({DateTime at, bool isAnchor, Widget child})>[
      for (final anchor in anchors)
        (at: anchor.at, isAnchor: true, child: _anchorLabel(anchor)),
      for (final group in groups)
        (at: group.first.scheduledAt, isAnchor: false, child: _dose(group, PatientVoice.of(context))),
    ]..sort((a, b) {
        final byTime = a.at.compareTo(b.at);
        // مرساة وجرعة في نفس الدقيقة: المرساة الأول
        if (byTime != 0) return byTime;
        return a.isAnchor == b.isAnchor ? 0 : (a.isAnchor ? -1 : 1);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          _railRow(
            node: entries[i].isAnchor,
            first: i == 0,
            last: i == entries.length - 1,
            child: entries[i].child,
          ),
      ],
    );
  }

  /// صف واحد: عمود السكة على اليمين (أول ابن في RTL) والمحتوى جنبه.
  Widget _railRow({
    required bool node,
    required bool first,
    required bool last,
    required Widget child,
  }) =>
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _railWidth,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  // الخط — متصل من أول صف لآخر صف
                  Positioned(
                    top: first ? F.s20 : 0,
                    bottom: last ? null : 0,
                    height: last ? F.s20 : null,
                    child: Container(width: 2, color: F.line),
                  ),
                  if (node)
                    Positioned(
                      top: F.s20 - _node / 2,
                      child: Container(
                        width: _node,
                        height: _node,
                        decoration: const BoxDecoration(
                          color: F.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: F.s10),
            Expanded(child: child),
          ],
        ),
      );

  Widget _anchorLabel(AnchorMark mark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: F.s8),
        child: SizedBox(
          height: F.s20 + F.s4,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '${mark.anchor.label} — ${arabicTime(mark.at)}',
              style: const TextStyle(
                fontSize: F.minTextSize,
                fontWeight: FontWeight.w700,
                color: F.ink,
              ),
            ),
          ),
        ),
      );

  Widget _dose(List<DoseEventView> group, Say say) => Padding(
        padding: const EdgeInsets.only(bottom: F.s10),
        child: group.every((d) => d.isDone) ? _quietLine(group, say) : _card(group),
      );

  /// جرعة اتاخدت: سطر هادي بعلامة صح. **ما بتتشالش من السكة أبداً** —
  /// المريض لازم يشوف إنه خدها، مش يلاقي السطر اختفى ويشك إنه نسي.
  Widget _quietLine(List<DoseEventView> group, Say say) => Padding(
        padding: const EdgeInsets.symmetric(vertical: F.s8),
        child: Row(
          children: [
            const Icon(Icons.check, size: 22, color: F.greenOk),
            const SizedBox(width: F.s8),
            Expanded(
              child: Text(
                group.map((d) => d.medicationName).join(' + '),
                textDirection: nameDirection(group.first.medicationName),
                textAlign: TextAlign.start,
                style: const TextStyle(
                  fontSize: F.minTextSize,
                  color: F.muted,
                  fontFamily: F.monoFamily,
                  fontFamilyFallback: F.monoFallback,
                ),
              ),
            ),
            const SizedBox(width: F.s8),
            Text(
              group.first.state == DoseState.skipped
                  ? 'اتأجّل'
                  : say.takenAt(arabicTime(group.first.actedAt ?? group.first.scheduledAt)),
              style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
            ),
          ],
        ),
      );

  /// جرعة لسه عايزاك — منتظرة أو فايتة، نفس الحافة الذهبية.
  Widget _card(List<DoseEventView> group) {
    final at = group.first.scheduledAt;
    // فات معادها أو جهازه كتب «اتنست» — نفس الجملة الهادية. نسي، ما فشلش.
    final unconfirmed =
        at.isBefore(now) || group.any((d) => d.state == DoseState.missed);

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(F.radiusCard),
        side: const BorderSide(color: F.gold, width: 2),
      ),
      child: InkWell(
        onTap: () => onOpen(group),
        borderRadius: BorderRadius.circular(F.radiusCard),
        child: Container(
          constraints: const BoxConstraints(minHeight: F.minTapTarget),
          padding: const EdgeInsets.all(F.s14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final dose in group)
                      Text(
                        dose.medicationName,
                        textDirection: nameDirection(dose.medicationName),
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                          fontSize: F.minBodySize,
                          fontWeight: FontWeight.w600,
                          color: F.ink,
                          fontFamily: F.monoFamily,
                          fontFamilyFallback: F.monoFallback,
                          height: 1.4,
                        ),
                      ),
                    const SizedBox(height: F.s4),
                    Text(
                      [
                        arabicTime(at),
                        ruleLabelFor(group.first.doseScheduleId),
                      ].nonNulls.join(' — '),
                      style: const TextStyle(fontSize: F.minTextSize, color: F.muted),
                    ),
                    if (unconfirmed) ...[
                      const SizedBox(height: F.s4),
                      const Text(
                        'لسه ما اتأكدتش',
                        style: TextStyle(
                          fontSize: F.minTextSize,
                          fontWeight: FontWeight.w700,
                          color: F.ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
