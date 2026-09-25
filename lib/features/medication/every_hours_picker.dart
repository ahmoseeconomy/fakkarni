import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/every_hours.dart';
import '../../domain/wording/rule_wording.dart' show everyHoursLabel, everyHoursPreview;

/// «كل كام ساعة»: الفاصل (قواسم ٢٤ بس)، وأول جرعة على عجلة بالدقيقة،
/// والساعات اللي هتطلع قدّامه **قبل** ما يحفظ. نفس الودجت في «ضيف دوا»
/// وفي تعديل دوا موجود.
class EveryHoursPicker extends StatelessWidget {
  const EveryHoursPicker({
    required this.hours,
    required this.first,
    required this.onChanged,
    super.key,
  });

  final int hours;
  final MinuteOfDay first;
  final void Function(int hours, MinuteOfDay first) onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('كل قد إيه؟', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
          const SizedBox(height: F.s8),
          Wrap(
            spacing: F.s8,
            runSpacing: F.s8,
            children: [
              for (final h in everyHoursChoices)
                AnchorChip(
                  key: ValueKey('every-$h'),
                  label: everyHoursLabel(h),
                  selected: hours == h,
                  onTap: () => onChanged(h, first),
                ),
            ],
          ),
          const SizedBox(height: F.gap),
          Text('أول جرعة الساعة كام؟', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
          FTimeWheel(
            key: const ValueKey('every-first'),
            value: first,
            onChanged: (t) => onChanged(hours, t),
          ),
          const SizedBox(height: F.s10),
          Text(
            everyHoursPreview([
              for (final t in everyHoursTimes(first, hours)) DateTime(2026, 1, 1, 0, t.minutes),
            ]),
            key: const ValueKey('every-hours-preview'),
            style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink, height: 1.5),
          ),
          const SizedBox(height: F.s6),
          Text('ساعات ثابتة — مش هتتحرك مع روتين يومك.',
              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
        ],
      );
}
