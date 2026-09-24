import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/patient_voice.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/day_routine.dart';
import 'routine_presets.dart';
import '../../core/widgets/f_wheels.dart';

/// شاشة سؤال واحد (المخطط 22 — سؤال في المرة).
///
/// الترتيب مقصود: تلات اقتراحات كبيرة **فوق** العجلة، لأن أغلب الناس هتلاقي
/// معادها في واحد منهم وتخلص من غير ما تلف حاجة. «مش متأكد» بياخد الافتراضي
/// ويمشي — عمره ما بيوقف حد. خمس نقط تحت: الحالية ذهبية والباقي line.
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
            padding: const EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  questionTextFor(question, PatientVoice.of(context)),
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.questionSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: F.s6),
                Text(
                  questionHintFor(question, PatientVoice.of(context)),
                  style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                ),
                const SizedBox(height: F.gap),
                PresetRow(presets: question.presets, value: value, onChanged: onChanged),
                const SizedBox(height: F.gap),
                FCard(
                  padding: const EdgeInsets.symmetric(horizontal: F.s12, vertical: F.gap),
                  child: Column(
                    children: [
                      Text(
                        arabicTime(DateTime(2026, 1, 1, value.hour, value.minute)),
                        style: const TextStyle(
                          fontSize: F.bigTimeSize,
                          fontWeight: FontWeight.w700,
                          color: F.greenDeep,
                        ),
                      ),
                      const SizedBox(height: F.s8),
                      FTimeWheel(value: value, onChanged: onChanged),
                    ],
                  ),
                ),
                const SizedBox(height: F.gap),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(F.gap, 0, F.gap, F.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(label: 'تمام', onPressed: onConfirm),
              const SizedBox(height: F.s4),
              SizedBox(
                height: F.minTapTarget,
                child: TextButton(
                  onPressed: onNotSure,
                  child: Text(
                    PatientVoice.of(context).notSure,
                    style: TextStyle(
                      fontSize: F.minBodySize,
                      fontWeight: FontWeight.w600,
                      color: F.green,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: F.s8),
              ProgressDots(current: stepNumber, total: totalSteps),
            ],
          ),
        ),
      ],
    );
  }
}

/// تلات اقتراحات كبيرة — الذهبي = «ده اللي مختار»، نفس معناه في التطبيق.
class PresetRow extends StatelessWidget {
  const PresetRow({
    required this.presets,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<MinuteOfDay> presets;
  final MinuteOfDay value;
  final ValueChanged<MinuteOfDay> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final preset in presets) ...[
            Expanded(
              child: SizedBox(
                height: F.chipHeight,
                child: AnchorChip(
                  label: arabicTime(DateTime(2026, 1, 1, preset.hour, preset.minute)),
                  selected: preset == value,
                  onTap: () => onChanged(preset),
                ),
              ),
            ),
            if (preset != presets.last) const SizedBox(width: F.s10),
          ],
        ],
      );
}

/// خمس نقط تقدّم — الحالية ذهبية (إنت هنا)، والباقي line.
class ProgressDots extends StatelessWidget {
  const ProgressDots({required this.current, required this.total, super.key});

  /// ١-based.
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'سؤال ${arabicNumber(current)} من ${arabicNumber(total)}',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= total; i++)
              Container(
                key: ValueKey('dot-$i'),
                width: i == current ? 28 : 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: F.s4),
                decoration: BoxDecoration(
                  color: i == current ? F.gold : F.line,
                  borderRadius: BorderRadius.circular(F.radiusChip),
                ),
              ),
          ],
        ),
      );
}
