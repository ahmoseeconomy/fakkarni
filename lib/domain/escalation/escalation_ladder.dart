/// سلّم التصعيد — دارت نقي، من غير إشعارات ولا قاعدة بيانات.
///
/// جرعة اترنّ لها ومحدش قال «أخدته». إيه اللي بيحصل بعدها بالدقيقة:
///
/// | بعد   | إيه                                  | فين            |
/// |-------|--------------------------------------|----------------|
/// | ٠     | تذكير الجرعة                          | المرحلة الأولى |
/// | +١٥   | الدرجة الأولى — تنبيه أعلى             | الجولة ٤.١     |
/// | +٣٠   | الدرجة التانية — تنبيه واهتزاز         | الجولة ٤.١     |
/// | +٤٥   | انتهاء المهلة: الجرعة «اتنست»          | الجولة ٤.١     |
/// | +٤٥   | إشعار لابنه                            | الجولة ٤.٢     |
///
/// الأرقام دي تشغيلية، مش طبية: هي المهلة اللي بعدها بنقول «الجرعة دي
/// اتنست» وبنبلّغ ابنه. القاعدة الخامسة فوقها كلها: أي تأكيد بيلغي كل
/// الدرجات فوراً، في أي مرحلة كانت.
library;

/// درجة على السلّم — كل درجة إشعار لوحده على جهاز المريض.
enum EscalationRung {
  /// +١٥ دقيقة: «لسه ما أخدتش الدوا؟» بنغمة أعلى.
  first(Duration(minutes: 15)),

  /// +٣٠ دقيقة: نفس السؤال، وبيهزّ.
  second(Duration(minutes: 30));

  const EscalationRung(this.delay);

  /// المسافة من معاد الجرعة الأصلي — مش من آخر درجة.
  final Duration delay;
}

/// المهلة اللي بعدها الجرعة بتتحسب «اتنست».
///
/// مش بتتعمل درجة على السلّم: عند الـ٤٥ مفيش إشعار للمريض تاني — التطبيق
/// بيكتب الحالة وبيسيب الباقي لابنه (٤.٢). لو المريض قال «أخدته» بعدها،
/// الحالة بتتبدّل عادي: «اتنست» قرار مهلة، مش حكم نهائي.
const Duration graceWindow = Duration(minutes: 45);

/// درجة السلّم في وقتها الحقيقي لتذكير معيّن.
class EscalationStep {
  const EscalationStep({required this.rung, required this.at});

  final EscalationRung rung;

  /// إمتى بترنّ.
  final DateTime at;

  @override
  String toString() => 'EscalationStep(${rung.name} @ $at)';
}

/// السلّم كامل لتذكير معاده [reminderAt] — كل الدرجات، بالترتيب.
///
/// المُنشئ بالدقايق مش `.add(Duration)`: مصر بتغيّر التوقيت الصيفي، والمُنشئ
/// بيحسب بالساعة اللي على الحيطة زي باقي المحرك.
List<EscalationStep> ladderFor(DateTime reminderAt) => [
      for (final rung in EscalationRung.values)
        EscalationStep(rung: rung, at: _plusMinutes(reminderAt, rung.delay)),
    ];

/// آخر لحظة قبل ما الجرعة تتحسب «اتنست».
DateTime graceEndFor(DateTime reminderAt) => _plusMinutes(reminderAt, graceWindow);

/// المهلة خلصت؟ عند الـ٤٥ بالظبط = خلصت.
bool isPastGrace({required DateTime scheduledAt, required DateTime now}) =>
    !now.isBefore(graceEndFor(scheduledAt));

DateTime _plusMinutes(DateTime at, Duration delay) => DateTime(
      at.year,
      at.month,
      at.day,
      at.hour,
      at.minute + delay.inMinutes,
    );
