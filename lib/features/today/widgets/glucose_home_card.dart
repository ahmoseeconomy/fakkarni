import 'package:flutter/material.dart';

import '../../../core/format/arabic_time.dart';
import '../../../core/theme/tokens.dart';
import 'card_type_icon.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/health/usual_range.dart';
import '../../health/glucose_screen.dart' show judgeReading;
import '../../health/usual_words.dart';

/// هل آخر قياس برّه المعتاد **ليه هو**؟ لو لسه مفيش قياسات كفاية: لأ — مفيش
/// حاجة نقارن بيها، ومش هنقارن بكتاب.
bool latestOutsideUsual(List<ReadingRow> newestFirst) {
  if (newestFirst.isEmpty) return false;
  final c = judgeReading(newestFirst, newestFirst.first).comparison;
  return c != null && c is! WithinUsual;
}

/// كارت السكر على الرئيسية (D3.6 فوق D3.2).
///
/// **ذهبي بس لو آخر قياس برّه المعتاد ليه هو** — ده معنى الذهبي: «محتاج
/// انتباهك». الكلام رقم وفرق من غير لوم، ومفيش أحمر. غير كده كارت هادي.
/// الزرار «افتح» ثانوي — الأساسي الوحيد في الرئيسية «تأكيد الجرعة».
class GlucoseHomeCard extends StatelessWidget {
  const GlucoseHomeCard({required this.readings, required this.onOpen, super.key});

  /// الأحدث الأول — مش فاضية.
  final List<ReadingRow> readings;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final latest = readings.first;
    final judged = judgeReading(readings, latest);
    final outside = latestOutsideUsual(readings);
    return FCard(
      key: const ValueKey('glucose-home'),
      tone: outside ? FCardTone.attention : FCardTone.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // أيقونة النوع على اليمين زي التصميم
          Row(
            children: [
              CardTypeIcon(icon: Icons.water_drop_outlined),
              SizedBox(width: F.s8),
              Expanded(
                child: Text('آخر قياس سكر',
                    style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark)),
              ),
            ],
          ),
          Text(
            '${arabicNumber(latest.valueMgDl)} ${latest.context.label}',
            style: TextStyle(fontFamily: F.displayFamily, fontSize: F.subtitleSize, fontWeight: FontWeight.w700, color: F.ink),
          ),
          Text(
            '${arabicDate(latest.measuredAt)} — ${arabicTime(latest.measuredAt)}',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
          ),
          const SizedBox(height: F.s4),
          Text(
            judged.range == null ? notEnoughForUsual : comparisonText(judged.comparison!, judged.range!),
            style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.ink, height: 1.5),
          ),
          const SizedBox(height: F.s10),
          FSecondaryButton(label: 'افتح', onPressed: onOpen),
        ],
      ),
    );
  }
}
