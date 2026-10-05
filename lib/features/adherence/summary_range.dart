import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';

/// مدة الملخص — «من/إلى» أيام روتين، الاتنين داخلين (المالك، ٥ أكتوبر
/// مساءً). الافتراضي عند الفتح آخر ٧ أيام كاملة — زي ما كان بالظبط.
class SummaryRange {
  const SummaryRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  /// آخر ٧ أيام كاملة — النهارده برّه (اليوم لسه ماشي وعدّه ناقص).
  factory SummaryRange.lastWeek(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    return SummaryRange(DateTime(t.year, t.month, t.day - 7), DateTime(t.year, t.month, t.day - 1));
  }

  @override
  bool operator ==(Object other) => other is SummaryRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// ورقة «من/إلى» ببكرتين تاريخ — بترجّع المدة المختارة أو null لو اتقفلت.
///
/// الأيام المعروضة من [daysBack] يوم ورا (٣٠ للمريض — قرار المالك،
/// ٥ أكتوبر) لحد **امبارح** (الملخص أيام
/// كاملة بس — النهارده برّه زي الافتراضي). «من» بعد «إلى» = «تمام» بيقفل
/// بجملة مكتوبة، مش بحساب صامت.
Future<SummaryRange?> pickSummaryRange(
  BuildContext context, {
  required DateTime today,
  required SummaryRange current,
  int daysBack = 30,
}) {
  final t = DateTime(today.year, today.month, today.day);
  final days = [for (var i = daysBack; i >= 1; i--) DateTime(t.year, t.month, t.day - i)];
  var from = current.from;
  var to = current.to;
  return FSheet.show<SummaryRange>(
    context,
    title: 'الملخص من إمتى لإمتى؟',
    children: [
      StatefulBuilder(
        builder: (context, setState) {
          final valid = !from.isAfter(to);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('من', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark)),
              const SizedBox(height: F.s8),
              FChoiceWheel<DateTime>(
                wheelKey: const ValueKey('range-from-wheel'),
                noneLabel: null,
                choices: days,
                labelOf: arabicDate,
                value: days.contains(from) ? from : days.first,
                semanticsLabel: 'من يوم',
                onChanged: (d) => setState(() => from = d ?? from),
              ),
              const SizedBox(height: F.gap),
              Text('إلى', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark)),
              const SizedBox(height: F.s8),
              FChoiceWheel<DateTime>(
                wheelKey: const ValueKey('range-to-wheel'),
                noneLabel: null,
                choices: days,
                labelOf: arabicDate,
                value: days.contains(to) ? to : days.last,
                semanticsLabel: 'لحد يوم',
                onChanged: (d) => setState(() => to = d ?? to),
              ),
              if (!valid) ...[
                const SizedBox(height: F.s8),
                Text(
                  '«من» بعد «إلى» — ظبّط البكرتين.',
                  key: const ValueKey('range-invalid'),
                  style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.4),
                ),
              ],
              const SizedBox(height: F.gap),
              FPrimaryButton(
                key: const ValueKey('range-save'),
                label: 'تمام',
                onPressed: valid ? () => Navigator.of(context).pop(SummaryRange(from, to)) : null,
              ),
            ],
          );
        },
      ),
    ],
  );
}

/// زرار «غيّر المدة» — بكلمته، على كارت الملخص في التلات أماكن.
/// المقاسات بارامترات: كثافة الابن بتتبعت **من ملفه هو** — رموز تدرّجه
/// ممنوعة برّه فولدره (حارس الكثافة بيقرا المصدر، والتعليق اللي بيسمّيها
/// بيوقّعه — اتمسك هنا فعلاً).
class SummaryRangeButton extends StatelessWidget {
  const SummaryRangeButton({
    required this.onTap,
    this.height = F.minTapTarget,
    this.fontSize = F.minTextSize,
    super.key,
  });

  final VoidCallback onTap;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: IntrinsicWidth(
          child: OutlinedButton(
            key: const ValueKey('summary-range'),
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: F.ink,
              side: BorderSide(color: F.buttonEdge, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: F.s10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
              textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
            ),
            child: const Text('غيّر المدة'),
          ),
        ),
      );
}
