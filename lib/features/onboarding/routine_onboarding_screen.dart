import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/patient_voice.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/patient/sex.dart';
import '../../domain/scheduling/day_routine.dart';
import 'profile_page.dart';
import 'routine_presets.dart';
import 'routine_question_page.dart';

/// خمس أسئلة، كل سؤال لوحده على شاشة.
///
/// سؤال واحد في المرة عن قصد: المستخدم عنده ٧٢ سنة وبيقرا بنضارة، وشاشة
/// فيها خمس أسئلة مع بعض بتبقى حيطة.
class RoutineOnboardingScreen extends StatefulWidget {
  const RoutineOnboardingScreen({
    this.onDone,
    this.askProfile = true,
    this.onBack,
    super.key,
  });

  /// بيتندَه بعد ما الروتين يتحفظ وتتعاد جدولة التذكيرات.
  final VoidCallback? onDone;

  /// «نتعرّف عليك» قبل الأسئلة لو الجنس لسه ما اتسألش. false = الأسئلة على
  /// طول (اختبارات الأسئلة نفسها).
  final bool askProfile;

  /// الرجوع لشاشة البداية — موجود بس قبل ما يبقى فيه مريض (اختيار غلط
  /// ما يحبسش حد في مسار مش بتاعه).
  final VoidCallback? onBack;

  @override
  State<RoutineOnboardingScreen> createState() =>
      _RoutineOnboardingScreenState();
}

class _RoutineOnboardingScreenState extends State<RoutineOnboardingScreen> {
  final _controller = PageController();
  final Map<DayAnchor, MinuteOfDay> _answers = {};
  int _index = 0;
  bool _saving = false;

  /// null = لسه بنقرا صف المريض. true = «نتعرّف عليك» الأول.
  bool? _needsProfile;
  Sex? _sex;
  String? _name;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsProfile != null) return;
    if (!widget.askProfile) {
      _needsProfile = false;
      return;
    }
    final services = AppScope.of(context);
    services.routines.getPatient(services.patientId).then((row) {
      if (!mounted) return;
      setState(() {
        _sex = row?.sex;
        _name = row?.name;
        _needsProfile = row?.sex == null;
      });
    });
  }

  Future<void> _saveProfile({required String name, required Sex sex, int? age}) async {
    final services = AppScope.of(context);
    await services.routines.saveProfile(services.patientId, name: name, sex: sex, age: age);
    if (mounted) {
      setState(() {
        _sex = sex;
        _needsProfile = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MinuteOfDay _valueFor(RoutineQuestion question) =>
      _answers[question.anchor] ?? question.fallback;

  Future<void> _advance() async {
    if (_index < routineQuestions.length - 1) {
      setState(() => _index++);
      await _controller.animateToPage(
        _index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);

    final services = AppScope.of(context);
    await services.routines
        .saveRoutine(services.patientId, routineFromAnswers(_answers));

    // الأذونات بتتطلب هنا مش عند أول فتح — دلوقتي بقى واضح ليه التطبيق
    // محتاجها.
    await services.scheduler.ensurePermissions();
    await services.scheduler.rescheduleAll();

    if (!mounted) return;
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _needsProfile == true;
    return Scaffold(
      body: SafeArea(
        child: _needsProfile == null
            ? const SizedBox.shrink()
            // الأسئلة بتتكتب بجنس المريض اللي لسه مختاره — مش مستنية القاعدة
            : PatientVoice(
                say: Say(_sex),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(F.gap, F.gap, F.gap, F.s4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.onBack != null)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: SizedBox(
                                height: F.minTapTarget,
                                child: TextButton.icon(
                                  onPressed: widget.onBack,
                                  icon: const Icon(Icons.arrow_back, size: 22),
                                  label: const Text('رجوع'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: F.green,
                                    minimumSize: const Size(0, F.minTapTarget),
                                    textStyle: const TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                          Kicker(profile ? 'أول خطوة' : 'مرة واحدة بس'),
                          const SizedBox(height: F.s4),
                          Text(
                            profile ? 'نتعرّف عليك' : Say(_sex).routineTitle,
                            style: TextStyle(
                              fontFamily: F.displayFamily,
                              fontSize: F.screenTitleSize,
                              fontWeight: FontWeight.w700,
                              color: F.ink,
                            ),
                          ),
                          if (!profile) ...[
                            const SizedBox(height: F.s4),
                            Text(
                              Say(_sex).routineSubtitle,
                              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: profile
                          ? ProfilePage(initialName: _name, onDone: _saveProfile)
                          : PageView.builder(
                              controller: _controller,
                              // مفيش سحب بالإيد: كل سؤال بيتقفل بـ«تمام» أو «مش متأكد»،
                              // عشان محدش يعدّي سؤال من غير ما ياخد باله.
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: routineQuestions.length,
                              itemBuilder: (context, i) {
                                final question = routineQuestions[i];
                                return RoutineQuestionPage(
                                  question: question,
                                  stepNumber: i + 1,
                                  totalSteps: routineQuestions.length,
                                  value: _valueFor(question),
                                  onChanged: (value) => setState(
                                    () => _answers[question.anchor] = value,
                                  ),
                                  onConfirm: () {
                                    _answers[question.anchor] = _valueFor(question);
                                    _advance();
                                  },
                                  onNotSure: () {
                                    // «مش دلوقتي» بتعدّي من غير إجابة — المرساة
                                    // بتتحفظ **مش متحددة**، ومفيش افتراضي بيتكتب
                                    // كأنه اختاره. بيحدّدها بعدين من «عدّل يومك»
                                    // أو أول ما دوا يحتاجها.
                                    _answers.remove(question.anchor);
                                    _advance();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
