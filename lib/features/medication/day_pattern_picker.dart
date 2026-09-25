import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/f_wheels.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/day_pattern.dart';
import '../../domain/wording/rule_wording.dart' show weekdayNamesSatFirst, nextDaysPreview;
import 'add_medication_screen.dart' show DosePattern;

/// «أيام معينة» / «كل كام يوم» / «فترة وراحة» — الإعداد والمعاينة («الأيام
/// الجاية: السبت ٢٧، التلات ٣٠، …»). كله محسوب من يوم البداية.
class DayPatternPicker extends StatelessWidget {
  const DayPatternPicker({
    required this.pattern,
    required this.weekdays,
    required this.everyN,
    required this.cycleOn,
    required this.cycleOff,
    required this.start,
    required this.today,
    required this.onWeekdays,
    required this.onEveryN,
    required this.onCycle,
    super.key,
  });

  final DosePattern pattern;
  final Set<int> weekdays;
  final int everyN;
  final int cycleOn;
  final int cycleOff;
  final DateTime start;
  final DateTime today;
  final ValueChanged<Set<int>> onWeekdays;
  final ValueChanged<int> onEveryN;
  final void Function(int on, int off) onCycle;

  DayPattern? get _pattern => switch (pattern) {
        DosePattern.weekdays when weekdays.isNotEmpty => OnWeekdays(weekdays),
        DosePattern.everyNDays => EveryNDays(everyN),
        DosePattern.cycle => OnOffCycle(cycleOn, cycleOff),
        _ => null,
      };

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: F.s8),
        child: Text(text, style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
      );

  @override
  Widget build(BuildContext context) {
    final p = _pattern;
    return Column(
      key: const ValueKey('day-pattern-picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pattern == DosePattern.weekdays) ...[
          _label('أنهي أيام؟'),
          Wrap(
            spacing: F.s8,
            runSpacing: F.s8,
            children: [
              for (final (d, name) in weekdayNamesSatFirst)
                AnchorChip(
                  key: ValueKey('weekday-$d'),
                  label: name,
                  selected: weekdays.contains(d),
                  onTap: () => onWeekdays(
                    weekdays.contains(d) ? ({...weekdays}..remove(d)) : {...weekdays, d},
                  ),
                ),
            ],
          ),
        ],
        if (pattern == DosePattern.everyNDays) ...[
          _label('كل كام يوم؟'),
          FNumberWheel(
            key: const ValueKey('every-n-days'),
            value: everyN,
            min: 2,
            max: everyNDaysMax,
            unit: 'يوم',
            semanticsLabel: 'كل كام يوم',
            onChanged: onEveryN,
          ),
        ],
        if (pattern == DosePattern.cycle) ...[
          _label('كام يوم بياخده؟'),
          FNumberWheel(
            key: const ValueKey('cycle-on'),
            value: cycleOn,
            min: 1,
            max: cycleMaxDays,
            unit: 'يوم',
            semanticsLabel: 'أيام الدوا',
            onChanged: (v) => onCycle(v, cycleOff),
          ),
          const SizedBox(height: F.s10),
          _label('وكام يوم راحة؟'),
          FNumberWheel(
            key: const ValueKey('cycle-off'),
            value: cycleOff,
            min: 1,
            max: cycleMaxDays,
            unit: 'يوم',
            semanticsLabel: 'أيام الراحة',
            onChanged: (v) => onCycle(cycleOn, v),
          ),
        ],
        const SizedBox(height: F.s10),
        Text(
          p == null ? 'اختار يوم واحد على الأقل.' : nextDaysPreview(nextActiveDays(p, start: start, from: today)),
          key: const ValueKey('next-days-preview'),
          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink, height: 1.5),
        ),
        const SizedBox(height: F.s4),
        Text('بيتحسب من يوم البداية تحت.',
            style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
      ],
    );
  }
}
