import '../../domain/patient/sex.dart';
import '../../domain/scheduling/day_routine.dart';

/// سؤال واحد من أسئلة الروتين الخمسة.
class RoutineQuestion {
  const RoutineQuestion({
    required this.anchor,
    required this.text,
    required this.hint,
  });

  final DayAnchor anchor;

  /// النص بالظبط زي ما اتكتب — عامية مصرية، مش فصحى.
  final String text;

  final String hint;

  /// مكان راحة البكرة قبل ما يجاوب — نفس قيم [DayRoutine.fallback].
  ///
  /// **مش بيتحفظ كإجابة**: «مش دلوقتي» بتسيب المرساة مش متحددة، والرقم ده
  /// بيفضل مكان راحة بس.
  MinuteOfDay get fallback => DayRoutine.fallback.at(anchor);
}

/// الأسئلة بترتيبها. الترتيب ده جزء من التصميم — اليوم بيبدأ من الصحيان.
final List<RoutineQuestion> routineQuestions = [
  RoutineQuestion(
    anchor: DayAnchor.wake,
    text: 'بتصحى الساعة كام؟',
    hint: 'يومك بيبدأ من هنا — كل المواعيد بتترتب عليه.',
  ),
  RoutineQuestion(
    anchor: DayAnchor.breakfast,
    text: 'بتفطر الساعة كام؟',
    hint: 'أدوية كتير بتتاخد قبل الأكل بنص ساعة.',
  ),
  RoutineQuestion(
    anchor: DayAnchor.lunch,
    text: 'بتتغدى الساعة كام؟',
    hint: 'مش لازم تظبطها بالدقيقة.',
  ),
  RoutineQuestion(
    anchor: DayAnchor.dinner,
    text: 'بتتعشى الساعة كام؟',
    hint: 'لو بتتعشى بدري أو متأخر، اظبطها هنا.',
  ),
  RoutineQuestion(
    anchor: DayAnchor.sleep,
    text: 'بتنام الساعة كام؟',
    hint: 'لو بتنام بعد نص الليل، اختار من بدري الصبح.',
  ),
];

/// بيبني الروتين من إجابات الأسئلة الخمسة.
///
/// **سؤال ما اتجاوبش = مرساة مش متحددة**، مش الافتراضي. الرقم اللي بيتحط
/// مكانها مكان راحة للبكرة وبس؛ العلم هو اللي بيمنع المحرّك يجدول عليه.
DayRoutine routineFromAnswers(Map<DayAnchor, MinuteOfDay?> answers) => DayRoutine(
      wake: answers[DayAnchor.wake] ?? DayRoutine.fallback.wake,
      breakfast: answers[DayAnchor.breakfast] ?? DayRoutine.fallback.breakfast,
      lunch: answers[DayAnchor.lunch] ?? DayRoutine.fallback.lunch,
      dinner: answers[DayAnchor.dinner] ?? DayRoutine.fallback.dinner,
      sleep: answers[DayAnchor.sleep] ?? DayRoutine.fallback.sleep,
      unset: {for (final a in DayAnchor.values) if (answers[a] == null) a},
    );

/// «مش دلوقتي» — تخطّي سؤال روتين. كلمة واحدة للاتنين، ومحايدة.
const String notNowLabel = 'مش دلوقتي';

/// نص السؤال بجنس المريض — «بتفطر» / «بتفطري». [RoutineQuestion.text]
/// هو المذكّر الافتراضي، وده اللي بيتعرض فعلاً.
String questionTextFor(RoutineQuestion question, Say say) => switch (question.anchor) {
      DayAnchor.wake => say.wakeQuestion,
      DayAnchor.breakfast => say.breakfastQuestion,
      DayAnchor.lunch => say.lunchQuestion,
      DayAnchor.dinner => say.dinnerQuestion,
      DayAnchor.sleep => say.sleepQuestion,
    };

/// الشرح تحت السؤال — بالغايب في مسار «لحد تاني» (D4). الأسئلة اللي
/// شرحها بيكلّم اللي بيظبط (الفطار والغدا) زي ما هي.
String questionHintFor(RoutineQuestion question, Say say) => switch (question.anchor) {
      DayAnchor.wake => say.wakeHint,
      DayAnchor.dinner => say.dinnerHint,
      DayAnchor.sleep => say.sleepHint,
      _ => question.hint,
    };
