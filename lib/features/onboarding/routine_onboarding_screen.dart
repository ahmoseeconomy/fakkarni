import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/scheduling/day_routine.dart';
import 'routine_presets.dart';
import 'routine_question_page.dart';

/// خمس أسئلة، كل سؤال لوحده على شاشة.
///
/// سؤال واحد في المرة عن قصد: المستخدم عنده ٧٢ سنة وبيقرا بنضارة، وشاشة
/// فيها خمس أسئلة مع بعض بتبقى حيطة.
class RoutineOnboardingScreen extends StatefulWidget {
  const RoutineOnboardingScreen({this.onDone, super.key});

  /// بيتندَه بعد ما الروتين يتحفظ وتتعاد جدولة التذكيرات.
  final VoidCallback? onDone;

  @override
  State<RoutineOnboardingScreen> createState() =>
      _RoutineOnboardingScreenState();
}

class _RoutineOnboardingScreenState extends State<RoutineOnboardingScreen> {
  final _controller = PageController();
  final Map<DayAnchor, MinuteOfDay> _answers = {};
  int _index = 0;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MinuteOfDay _valueFor(RoutineQuestion question) =>
      _answers[question.anchor] ?? question.presets[1];

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
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(F.gap, F.gap, F.gap, F.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Kicker('مرة واحدة بس'),
                  SizedBox(height: F.s4),
                  Text(
                    'خلينا نعرف يومك',
                    style: TextStyle(
                      fontFamily: F.displayFamily,
                      fontSize: F.screenTitleSize,
                      fontWeight: FontWeight.w700,
                      color: F.ink,
                    ),
                  ),
                  SizedBox(height: F.s4),
                  Text(
                    'خمس أسئلة — وبعدها أي روشتة هتتظبط لوحدها على مواعيدك.',
                    style: TextStyle(fontSize: F.minTextSize, color: F.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
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
                      // «مش متأكد» بياخد الافتراضي ويمشي — مش بيوقف حد.
                      _answers[question.anchor] = question.fallback;
                      _advance();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
