import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import '../onboarding/routine_presets.dart';
import '../onboarding/time_wheel.dart';

/// تعديل روتين اليوم بعد الأسئلة الأولى.
///
/// الخمس مراسي على شاشة واحدة (المخطط 22): كل مرساة كارت فيه السؤال نفسه،
/// تلات اقتراحات، والساعة الحالية. رمضان أو سفر أو صحيان متأخر = تعديل
/// معاد واحد هنا، وكل جرعة مربوطة بيه بتتحرك لوحدها. الساعات الثابتة
/// ما بتتلمسش — وده مكتوب فوق عشان محدش يستغرب.
class EditRoutineScreen extends StatefulWidget {
  const EditRoutineScreen({required this.routine, super.key});

  final DayRoutine routine;

  @override
  State<EditRoutineScreen> createState() => _EditRoutineScreenState();
}

class _EditRoutineScreenState extends State<EditRoutineScreen> {
  late final Map<DayAnchor, MinuteOfDay> _values = {
    for (final anchor in DayAnchor.values) anchor: widget.routine.at(anchor),
  };

  /// العجلة مفتوحة لمرساة واحدة بس في المرة — خمس عجلات مع بعض حيطة.
  DayAnchor? _wheelFor;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final services = AppScope.of(context);
    final navigator = Navigator.of(context);

    await services.routines
        .saveRoutine(services.patientId, routineFromAnswers(_values));
    // الأرقام مشتقة من الوقت: جرعات المراسي بتاخد أرقام جديدة والقديمة
    // بتتلغى، والساعات الثابتة بترجع بنفس أرقامها بالظبط.
    await services.scheduler.rescheduleAll();

    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'يومك',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(F.gap),
                children: [
                  const Text(
                    'غيّر أي معاد — الجرعات المربوطة بيه بتتحرك معاه، '
                    'والساعات الثابتة بتفضل زي ما هي.',
                    style: TextStyle(
                      fontSize: F.minTextSize,
                      color: F.muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: F.gap),
                  for (final question in routineQuestions) ...[
                    _AnchorCard(
                      question: question,
                      value: _values[question.anchor]!,
                      wheelOpen: _wheelFor == question.anchor,
                      onChanged: (value) =>
                          setState(() => _values[question.anchor] = value),
                      onToggleWheel: () => setState(
                        () => _wheelFor = _wheelFor == question.anchor
                            ? null
                            : question.anchor,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(F.gap),
              child: SizedBox(
                width: double.infinity,
                height: F.primaryButtonHeight,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('احفظ يومك'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnchorCard extends StatelessWidget {
  const _AnchorCard({
    required this.question,
    required this.value,
    required this.wheelOpen,
    required this.onChanged,
    required this.onToggleWheel,
  });

  final RoutineQuestion question;
  final MinuteOfDay value;
  final bool wheelOpen;
  final ValueChanged<MinuteOfDay> onChanged;
  final VoidCallback onToggleWheel;

  String _label(MinuteOfDay time) =>
      arabicTime(DateTime(2026, 1, 1, time.hour, time.minute));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(F.gap),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(F.radius),
        border: Border.all(color: F.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  question.text,
                  style: const TextStyle(
                    fontSize: F.minBodySize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
              ),
              Text(
                _label(value),
                style: const TextStyle(
                  fontSize: F.screenTitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.greenDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final preset in question.presets) ...[
                Expanded(
                  child: _PresetChip(
                    label: _label(preset),
                    selected: preset == value,
                    onTap: () => onChanged(preset),
                  ),
                ),
                if (preset != question.presets.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: F.minTapTarget,
            child: OutlinedButton(
              onPressed: onToggleWheel,
              child: Text(
                wheelOpen ? 'تمام كده' : 'ساعة تانية',
                style: const TextStyle(
                  fontSize: F.minTextSize + 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (wheelOpen) ...[
            const SizedBox(height: 8),
            TimeWheel(value: value, onChanged: onChanged),
          ],
        ],
      ),
    );
  }
}

/// نفس اقتراح الأسئلة: الذهبي = المختار.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
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
                label,
                style: const TextStyle(
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
