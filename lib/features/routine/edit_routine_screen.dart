import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../core/widgets/patient_voice.dart';
import '../../core/widgets/primitives.dart';
import '../onboarding/routine_presets.dart';
import '../onboarding/routine_question_page.dart' show PresetRow;
import '../../core/widgets/f_wheels.dart';

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

  /// رمضان شغّال → الحفظ هنا مقفول. تعديل من هنا كان بيتحفظ فوق روتين
  /// رمضان، وقفل رمضان بعدها بيرجّع الأصل المحفوظ ويرمي التعديل في صمت.
  /// الحل الكامل (تعديل الأصل من ورا رمضان) مش دلوقتي — بس الوقوع فيه
  /// بالغلط لازم يبقى مستحيل.
  bool _ramadanOn = false;
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    final services = AppScope.of(context);
    services.routines.ramadanTimes(services.patientId).then((times) {
      if (mounted) setState(() => _ramadanOn = times != null);
    });
  }

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
                  if (_ramadanOn) ...[
                    // الذهبي = «إنت هنا»: الحالة اللي الجهاز عليها دلوقتي
                    const GoldNote('وضع رمضان شغّال — عدّل من شاشة رمضان'),
                    const SizedBox(height: F.gap),
                  ],
                  Text(
                    'غيّر أي معاد — الجرعات المربوطة بيه بتتحرك معاه، '
                    'والساعات الثابتة بتفضل زي ما هي.',
                    style: TextStyle(
                      fontSize: F.minTextSize,
                      color: F.mutedDark,
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
                  onPressed: _saving || _ramadanOn ? null : _save,
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
    return FCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  questionTextFor(question, PatientVoice.of(context)),
                  style: TextStyle(
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
          const SizedBox(height: F.s12),
          // نفس اقتراحات الأسئلة الأولى — الذهبي = المختار
          PresetRow(presets: question.presets, value: value, onChanged: onChanged),
          const SizedBox(height: F.s8),
          FSecondaryButton(
            label: wheelOpen ? 'تمام كده' : 'ساعة تانية',
            onPressed: onToggleWheel,
          ),
          if (wheelOpen) ...[
            const SizedBox(height: F.s8),
            FTimeWheel(value: value, onChanged: onChanged),
          ],
        ],
      ),
    );
  }
}
