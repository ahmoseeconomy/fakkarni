import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../core/widgets/patient_voice.dart';
import '../../core/widgets/primitives.dart';
import '../onboarding/routine_presets.dart';
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
  /// null = المستخدم ما حدّدهاش — الكارت بيقول «مش متحدد» وبيعرض مكان
  /// الراحة على البكرة بس. بتتحدد باقتراح أو حركة بكرة أو «تمام كده».
  late final Map<DayAnchor, MinuteOfDay?> _values = {
    for (final anchor in DayAnchor.values)
      anchor: widget.routine.isSet(anchor) ? widget.routine.at(anchor) : null,
  };

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
                      value: _values[question.anchor],
                      onChanged: (value) =>
                          setState(() => _values[question.anchor] = value),
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
    required this.onChanged,
  });

  final RoutineQuestion question;

  /// null = مش متحدد — البكرة واقفة على مكان الراحة وما بتكتبش غير لما
  /// تتحرّك.
  final MinuteOfDay? value;
  final ValueChanged<MinuteOfDay> onChanged;

  /// «مش متحدد» — الكلمة اللي الإعدادات بتقولها للمرساة اللي ما اتحددتش.
  static const String unsetLabel = 'مش متحدد';

  String _label(MinuteOfDay? time) => time == null
      ? unsetLabel
      : arabicTime(DateTime(2026, 1, 1, time.hour, time.minute));

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
                style: TextStyle(
                  fontSize: value == null ? F.minBodySize : F.screenTitleSize,
                  fontWeight: FontWeight.w700,
                  // مش متحدد بلون المتن الثانوي: مش حالة نشطة ولا تنبيه
                  color: value == null ? F.mutedDark : F.greenDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s8),
          // البكرة على طول — مفيش اقتراحات ولا «ساعة تانية»
          FTimeWheel(value: value ?? question.fallback, onChanged: onChanged),
        ],
      ),
    );
  }
}
