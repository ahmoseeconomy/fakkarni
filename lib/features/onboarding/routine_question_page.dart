import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import 'routine_presets.dart';
import 'time_wheel.dart';

/// شاشة سؤال واحد.
///
/// الترتيب مقصود: تلات اقتراحات كبيرة **فوق** العجلة، لأن أغلب الناس هتلاقي
/// معادها في واحد منهم وتخلص من غير ما تلف حاجة.
class RoutineQuestionPage extends StatelessWidget {
  const RoutineQuestionPage({
    required this.question,
    required this.stepNumber,
    required this.totalSteps,
    required this.value,
    required this.onChanged,
    required this.onConfirm,
    required this.onNotSure,
    super.key,
  });

  final RoutineQuestion question;
  final int stepNumber;
  final int totalSteps;
  final MinuteOfDay value;
  final ValueChanged<MinuteOfDay> onChanged;
  final VoidCallback onConfirm;
  final VoidCallback onNotSure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(F.gap, F.gap, F.gap, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'سؤال ${arabicNumber(stepNumber)} من ${arabicNumber(totalSteps)}',
                  style: const TextStyle(
                    fontSize: F.labelSize,
                    fontWeight: FontWeight.w600,
                    color: F.gold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  question.text,
                  style: const TextStyle(
                    fontSize: F.questionSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  question.hint,
                  style: const TextStyle(
                    fontSize: F.minTextSize,
                    color: F.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: F.gap),
                Row(
                  children: [
                    for (final preset in question.presets) ...[
                      Expanded(
                        child: _PresetChip(
                          time: preset,
                          selected: preset == value,
                          onTap: () => onChanged(preset),
                        ),
                      ),
                      if (preset != question.presets.last)
                        const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: F.gap),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: F.gap,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(F.radius),
                    border: Border.all(color: F.line),
                  ),
                  child: Column(
                    children: [
                      Text(
                        arabicTime(
                          DateTime(2026, 1, 1, value.hour, value.minute),
                        ),
                        style: const TextStyle(
                          fontSize: F.bigTimeSize,
                          fontWeight: FontWeight.w700,
                          color: F.greenDeep,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TimeWheel(value: value, onChanged: onChanged),
                    ],
                  ),
                ),
                const SizedBox(height: F.gap),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(onPressed: onConfirm, child: const Text('تمام')),
              const SizedBox(height: 4),
              SizedBox(
                height: F.minTapTarget,
                child: TextButton(
                  onPressed: onNotSure,
                  child: const Text(
                    'مش متأكد',
                    style: TextStyle(
                      fontSize: F.minBodySize,
                      fontWeight: FontWeight.w600,
                      color: F.green,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// اقتراح كبير. الذهبي هنا معناه «ده اللي مختار» — نفس معنى الذهبي في
/// باقي التطبيق: الحالة النشطة.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.time,
    required this.selected,
    required this.onTap,
  });

  final MinuteOfDay time;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: F.chipHeight,
      child: Material(
        color: selected ? F.gold : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(F.radius),
          side: BorderSide(color: selected ? F.gold : F.line, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(F.radius),
          child: Center(
            child: Text(
              arabicTime(DateTime(2026, 1, 1, time.hour, time.minute)),
              style: TextStyle(
                fontSize: F.minBodySize,
                fontWeight: FontWeight.w700,
                color: F.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
