import '../../domain/patient/sex.dart';
import '../../domain/scheduling/day_routine.dart';

/// سؤال واحد من أسئلة الروتين الخمسة.
class RoutineQuestion {
  const RoutineQuestion({
    required this.anchor,
    required this.text,
    required this.hint,
    required this.presets,
  });

  final DayAnchor anchor;

  /// النص بالظبط زي ما اتكتب — عامية مصرية، مش فصحى.
  final String text;

  final String hint;

  /// تلات اقتراحات كبيرة فوق العجلة. أغلب الناس بتختار واحد منهم وتخلص.
  /// النصّاني هو الافتراضي (المخطط 22) — نفس [fallback].
  final List<MinuteOfDay> presets;

  /// اللي بيتاخد لما المستخدم يقول «مش متأكد».
  ///
  /// دي نفس قيم [DayRoutine.fallback] — نقطة بداية بيعدّلها بعدين، مش
  /// نصيحة طبية ولا تخمين.
  MinuteOfDay get fallback => DayRoutine.fallback.at(anchor);
}

/// الأسئلة بترتيبها. الترتيب ده جزء من التصميم — اليوم بيبدأ من الصحيان.
final List<RoutineQuestion> routineQuestions = [
  RoutineQuestion(
    anchor: DayAnchor.wake,
    text: 'بتصحى الساعة كام؟',
    hint: 'يومك بيبدأ من هنا — كل المواعيد بتترتب عليه.',
    presets: [MinuteOfDay.hm(6), MinuteOfDay.hm(6, 30), MinuteOfDay.hm(7)],
  ),
  RoutineQuestion(
    anchor: DayAnchor.breakfast,
    text: 'بتفطر الساعة كام؟',
    hint: 'أدوية كتير بتتاخد قبل الأكل بنص ساعة.',
    presets: [MinuteOfDay.hm(7), MinuteOfDay.hm(7, 30), MinuteOfDay.hm(8)],
  ),
  RoutineQuestion(
    anchor: DayAnchor.lunch,
    text: 'بتتغدى الساعة كام؟',
    hint: 'مش لازم تظبطها بالدقيقة.',
    presets: [MinuteOfDay.hm(13, 30), MinuteOfDay.hm(14), MinuteOfDay.hm(15, 30)],
  ),
  RoutineQuestion(
    anchor: DayAnchor.dinner,
    text: 'بتتعشى الساعة كام؟',
    hint: 'لو بتتعشى بدري أو متأخر، اظبطها هنا.',
    presets: [MinuteOfDay.hm(19), MinuteOfDay.hm(20), MinuteOfDay.hm(21, 30)],
  ),
  RoutineQuestion(
    anchor: DayAnchor.sleep,
    text: 'بتنام الساعة كام؟',
    hint: 'لو بتنام بعد نص الليل، اختار من بدري الصبح.',
    presets: [MinuteOfDay.hm(22, 30), MinuteOfDay.hm(23, 30), MinuteOfDay.hm(0, 30)],
  ),
];

/// بيبني الروتين من إجابات الأسئلة الخمسة.
DayRoutine routineFromAnswers(Map<DayAnchor, MinuteOfDay> answers) => DayRoutine(
      wake: answers[DayAnchor.wake] ?? DayRoutine.fallback.wake,
      breakfast: answers[DayAnchor.breakfast] ?? DayRoutine.fallback.breakfast,
      lunch: answers[DayAnchor.lunch] ?? DayRoutine.fallback.lunch,
      dinner: answers[DayAnchor.dinner] ?? DayRoutine.fallback.dinner,
      sleep: answers[DayAnchor.sleep] ?? DayRoutine.fallback.sleep,
    );

/// نص السؤال بجنس المريض — «بتفطر» / «بتفطري». [RoutineQuestion.text]
/// هو المذكّر الافتراضي، وده اللي بيتعرض فعلاً.
String questionTextFor(RoutineQuestion question, Say say) => switch (question.anchor) {
      DayAnchor.wake => say.wakeQuestion,
      DayAnchor.breakfast => say.breakfastQuestion,
      DayAnchor.lunch => say.lunchQuestion,
      DayAnchor.dinner => say.dinnerQuestion,
      DayAnchor.sleep => say.sleepQuestion,
    };
