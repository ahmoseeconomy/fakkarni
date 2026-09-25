import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../domain/health/vitals.dart';
import 'vital_chart.dart';

/// الفترات اللي الرسم بيعرضها.
const vitalPeriods = [7, 30, 90];

String vitalPeriodLabel(int days) => switch (days) {
      7 => 'أسبوع',
      30 => 'شهر',
      _ => '٣ شهور',
    };

/// **نوع واحد: آخر رقم، المعتاد ليك، الفرق، الرسم، والقايمة باليوم.**
///
/// نفس الودجت عند المريض وعيلته والممرض — رقم ووقت وفرق وبس، والكلام
/// الطبي بيخلص عند «اسأل دكتورك». الأرقام بلون المتن؛ **مفيش لون خطر**.
class VitalHistoryView extends StatefulWidget {
  const VitalHistoryView({required this.kind, required this.vitals, required this.now, this.onAdd, super.key});

  final VitalKind kind;

  /// كل القياسات (أي نوع) — الودجت بتفلتر.
  final List<Vital> vitals;
  final DateTime now;

  /// «سجّل قياس» — للمريض بس؛ null عند العيلة والممرض (قراية بس).
  final VoidCallback? onAdd;

  @override
  State<VitalHistoryView> createState() => _VitalHistoryViewState();
}

class _VitalHistoryViewState extends State<VitalHistoryView> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final mine = [for (final v in widget.vitals) if (v.kind == kind) v]
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final latest = mine.firstOrNull;
    final usual = vitalUsual(widget.vitals, kind, widget.now);
    final series = vitalSeries(widget.vitals, kind, widget.now, _days);
    final text = TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5);

    final children = <Widget>[
      if (latest == null)
        Text('لسه مفيش قياسات ${kind.label}.', style: text)
      else ...[
        Text(
          vitalValueText(latest),
          key: const ValueKey('vital-latest'),
          style: TextStyle(fontSize: F.bigTimeSize * 0.8, fontWeight: FontWeight.w800, color: F.ink),
        ),
        Text('${arabicDate(latest.measuredAt)} — ${arabicTime(latest.measuredAt)}',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
        const SizedBox(height: F.s10),
        Text(vitalUsualLine(usual, kind), key: const ValueKey('vital-usual'), style: text),
        if (vitalDifferenceLine(latest, usual) case final d?) Text(d, key: const ValueKey('vital-diff'), style: text),
        const SizedBox(height: F.gap),
        Row(
          children: [
            for (final d in vitalPeriods) ...[
              Expanded(
                child: AnchorChip(
                  key: ValueKey('vital-period-$d'),
                  label: vitalPeriodLabel(d),
                  selected: _days == d,
                  onTap: () => setState(() => _days = d),
                ),
              ),
              if (d != vitalPeriods.last) const SizedBox(width: F.s8),
            ],
          ],
        ),
        const SizedBox(height: F.s12),
        if (series.first.isEmpty)
          Text('مفيش قياسات في الفترة دي.', style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark))
        else
          VitalChart(
            kind: kind,
            first: series.first,
            second: series.second,
            from: widget.now.subtract(Duration(days: _days)),
            to: widget.now,
          ),
        const SizedBox(height: F.gap),
      ],
      if (widget.onAdd != null) ...[
        FSecondaryButton(key: const ValueKey('vital-add'), label: 'سجّل قياس', onPressed: widget.onAdd),
        const SizedBox(height: F.gap),
      ],
    ];

    // القايمة مجمّعة باليوم، الأحدث الأول
    DateTime? lastDay;
    for (final v in mine) {
      final day = DateTime(v.measuredAt.year, v.measuredAt.month, v.measuredAt.day);
      if (day != lastDay) {
        lastDay = day;
        children.add(Padding(
          padding: const EdgeInsets.only(top: F.s8, bottom: F.s4),
          child: Text(arabicDate(day), style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark)),
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: F.s4),
        child: Text('${arabicTime(v.measuredAt)} — ${vitalValueText(v)}', style: text),
      ));
    }
    // «اسأل دكتورك» — الكلمة الطبية الوحيدة، وعند المريض بس (الكلام ليه
    // هو). عند العيلة والممرض الشاشة قراية أرقام وخلاص.
    if (widget.onAdd != null) {
      children.addAll([
        const SizedBox(height: F.gap),
        Text(vitalsAskDoctor, key: const ValueKey('vital-ask-doctor'), style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// «آخر قياس لكل نوع» — صف لكل نوع ليه قياسات، ودوسة بتفتح تاريخه.
class VitalsSummary extends StatelessWidget {
  const VitalsSummary({required this.vitals, required this.onOpen, super.key});

  final List<Vital> vitals;
  final void Function(VitalKind kind) onOpen;

  @override
  Widget build(BuildContext context) {
    final latest = <VitalKind, Vital>{};
    for (final v in vitals) {
      final cur = latest[v.kind];
      if (cur == null || v.measuredAt.isAfter(cur.measuredAt)) latest[v.kind] = v;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final kind in VitalKind.values)
          if (latest[kind] case final v?)
            Padding(
              padding: const EdgeInsets.only(bottom: F.s8),
              child: Material(
                color: F.cardGround,
                borderRadius: BorderRadius.circular(F.radiusCard),
                child: InkWell(
                  key: ValueKey('vital-summary-${kind.name}'),
                  borderRadius: BorderRadius.circular(F.radiusCard),
                  onTap: () => onOpen(kind),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: F.minTapTarget),
                    padding: const EdgeInsets.symmetric(horizontal: F.s14, vertical: F.s10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(kind.label,
                              style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                        ),
                        Flexible(
                          child: Text(
                            vitalValueText(v),
                            textAlign: TextAlign.end,
                            style: TextStyle(fontSize: F.minTextSize, color: F.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
