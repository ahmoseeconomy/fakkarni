import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/adherence/weekly_summary.dart';
import '../adherence/summary_range.dart';
import '../adherence/weekly_summary_card.dart' show snapshotDaysBack;
import 'caregiver_ui.dart';

/// **ملخص الأسبوع** بكثافة الابن — فوق «متابعة» (طلب المدير، ٤ أكتوبر ٢٠٢٦).
/// نفس الحساب ونفس الجمل اللي عند المريض والممرض، بمقاسات `F.care…`.
class CareWeeklySummary extends StatefulWidget {
  const CareWeeklySummary({required this.summaryFor, required this.today, super.key});

  /// بيحسب الملخص للمدة المختارة — «غيّر المدة» (٥ أكتوبر مساءً) بنفس بكر
  /// المريض؛ الصورة فيها آخر ٨ أيام بس فالبكر محدودة بيهم.
  final WeeklySummary Function(SummaryRange range) summaryFor;
  final DateTime today;

  @override
  State<CareWeeklySummary> createState() => _CareWeeklySummaryState();
}

class _CareWeeklySummaryState extends State<CareWeeklySummary> {
  late SummaryRange _range = SummaryRange.lastWeek(widget.today);

  Future<void> _pick() async {
    final picked = await pickSummaryRange(context, today: widget.today, current: _range, daysBack: snapshotDaysBack);
    if (picked != null && mounted) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summaryFor(_range);
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: F.careRowGap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: F.mutedDark),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(fontSize: F.careBodySize, color: F.ink, height: 1.45))),
            ],
          ),
        );
    return CareCard(
      key: const ValueKey('care-weekly-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.title, style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w800, color: F.ink)),
              ),
              const SizedBox(width: 8),
              SummaryRangeButton(onTap: _pick, height: F.careTapTarget, fontSize: F.careTextSize),
            ],
          ),
          line(Icons.check_circle_outline, s.dosesLine),
          if (s.missedLine.isNotEmpty) line(Icons.schedule, s.missedLine),
          line(Icons.inventory_2_outlined, s.lowStockLine),
          line(Icons.event_outlined, s.appointmentLine),
        ],
      ),
    );
  }
}
