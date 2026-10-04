import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/adherence/weekly_summary.dart';
import 'caregiver_ui.dart';

/// **ملخص الأسبوع** بكثافة الابن — فوق «متابعة» (طلب المدير، ٤ أكتوبر ٢٠٢٦).
/// نفس الحساب ونفس الجمل اللي عند المريض والممرض، بمقاسات `F.care…`.
class CareWeeklySummary extends StatelessWidget {
  const CareWeeklySummary({required this.summary, super.key});

  final WeeklySummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
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
          Text(s.title, style: TextStyle(fontSize: F.careBodySize, fontWeight: FontWeight.w800, color: F.ink)),
          line(Icons.check_circle_outline, s.dosesLine),
          if (s.missedLine.isNotEmpty) line(Icons.schedule, s.missedLine),
          line(Icons.inventory_2_outlined, s.lowStockLine),
          line(Icons.event_outlined, s.appointmentLine),
        ],
      ),
    );
  }
}
