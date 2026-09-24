import '../../../domain/medication/medication_purpose.dart';
import 'tips_ar.dart';

/// دوا زي ما «معلومة ليك» محتاجاه — من غير قاعدة ولا صفوف.
class TipMedication {
  const TipMedication({
    required this.id,
    required this.name,
    this.purpose,
    this.instructions,
    this.endsOn,
  });

  final int id;
  final String name;
  final MedicationPurpose? purpose;
  final String? instructions;

  /// آخر يوم فعّال لو المدة محددة — null = مفتوحة.
  final DateTime? endsOn;
}

/// جرعة من آخر أسبوع — اللي الالتزام بيتحسب منه.
class TipDose {
  const TipDose({required this.scheduledAt, required this.taken, required this.missed, this.actedAt});

  final DateTime scheduledAt;
  final bool taken;
  final bool missed;
  final DateTime? actedAt;
}

/// المعلومة اللي بتتعرض: النص، والدوا اللي هي عنه (لو فيه) — الدوسة
/// بتفتحه — وسطر تعليماته لو كتب.
class Tip {
  const Tip({required this.text, this.medicationId, this.instructions});

  final String text;
  final int? medicationId;
  final String? instructions;
}

/// **معلومة واحدة في اليوم، ثابتة طول اليوم، وبتتبدّل بكرة.**
///
/// الأولوية: (أ) من التزامه هو — دوا مدته بتخلص خلال ٣ أيام، أو أيام
/// ورا بعض كل جرعاتها اتاخدت، أو جرعات المسا اللي فاتت/اتأخّرت الأسبوع
/// ده؛ (ب) من «الدوا ده لإيه؟» لأي دوا شغّال؛ (ج) نصيحة عامة. جوّه كل
/// مستوى الاختيار بيلفّ بيوم السنة، فنفس اليوم بيدّي نفس المعلومة مهما
/// اتفتحت الشاشة. **مفيش نص بيتولّد**: كل الجمل من `tips_ar.dart`.
Tip pickTip({
  required DateTime today,
  required List<TipMedication> medications,
  required List<TipDose> lastWeek,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final index = DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  // (أ) التزامه
  final own = <Tip>[];
  for (final m in medications) {
    final end = m.endsOn;
    if (end == null) continue;
    final left = DateTime(end.year, end.month, end.day).difference(day).inDays;
    if (left >= 0 && left <= 3) {
      own.add(Tip(text: durationEndingTip(m.name, left), medicationId: m.id, instructions: m.instructions));
    }
  }
  final streak = _streakEndingYesterday(day, lastWeek);
  if (streak >= 2) own.add(Tip(text: streakTip(streak)));
  if (_eveningTroubles(lastWeek) >= 2) own.add(const Tip(text: eveningLateTip));
  if (own.isNotEmpty) return own[index % own.length];

  // (ب) الغرض
  final byPurpose = <Tip>[];
  for (final m in medications) {
    final purpose = m.purpose;
    if (purpose == null) continue;
    for (final t in purposeTips[purpose] ?? const <String>[]) {
      byPurpose.add(Tip(
        text: t.replaceAll('({name})', m.name.trim().isEmpty ? '' : '(${m.name.trim()})').replaceAll('  ', ' '),
        medicationId: m.id,
        instructions: m.instructions,
      ));
    }
  }
  if (byPurpose.isNotEmpty) return byPurpose[index % byPurpose.length];

  // (ج) عام — ومعاه تعليمات أي دوا كتب لها تعليمات، بالدور
  final withInstructions = [for (final m in medications) if ((m.instructions ?? '').trim().isNotEmpty) m];
  final m = withInstructions.isEmpty ? null : withInstructions[index % withInstructions.length];
  return Tip(text: generalTips[index % generalTips.length], medicationId: m?.id, instructions: m?.instructions);
}

/// أيام ورا بعض — لحد امبارح — كل جرعاتها اتاخدت. يوم من غير جرعات بيقطع.
int _streakEndingYesterday(DateTime day, List<TipDose> lastWeek) {
  var streak = 0;
  for (var back = 1; back <= 7; back++) {
    final d = DateTime(day.year, day.month, day.day - back);
    final doses = lastWeek.where((x) =>
        x.scheduledAt.year == d.year && x.scheduledAt.month == d.month && x.scheduledAt.day == d.day);
    if (doses.isEmpty || doses.any((x) => !x.taken)) break;
    streak++;
  }
  return streak;
}

/// جرعات بعد ٦ مساءً فاتت، أو اتاخدت بعد معادها بأكتر من ٤٥ دقيقة.
int _eveningTroubles(List<TipDose> lastWeek) => lastWeek.where((x) {
      if (x.scheduledAt.hour < 18) return false;
      if (x.missed) return true;
      final acted = x.actedAt;
      return x.taken && acted != null && acted.difference(x.scheduledAt).inMinutes > 45;
    }).length;
