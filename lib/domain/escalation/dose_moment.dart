import 'escalation_ladder.dart';

/// جرعة لسه ما اتأكدتش — هي فين من وقتها؟ **تعريف واحد** لـ«يومك» ونمط كبار
/// السن والسكة.
///
/// - [upcoming]: لسه ما جاش معادها.
/// - [dueNow]: جه معادها ولسه جوّه مهلة الجهاز ([graceWindow]، ٤٥ دقيقة) —
///   **«معادها دلوقتي»**، مش «نسيتها؟». على الآيفون (٢٦ سبتمبر ٢٠٢٦) كانت
///   بتقول «نسيتها؟ — كان معادها ٦:٥١» في نفس الدقيقة اللي التذكير رن فيها.
/// - [missed]: عدّت المهلة، أو الجهاز كتب «اتنست» — ساعتها بس الكلام بتاع
///   «لسه ما اتأكدتش».
///
/// نفس الحد اللي `sweepMissed` بيكتب عنده «اتنست»، فالكلمة والصف ما
/// بيختلفوش.
enum DoseMoment { upcoming, dueNow, missed }

DoseMoment doseMomentOf({
  required DateTime scheduledAt,
  required DateTime now,
  bool markedMissed = false,
}) {
  if (markedMissed || isPastGrace(scheduledAt: scheduledAt, now: now)) return DoseMoment.missed;
  if (!now.isBefore(scheduledAt)) return DoseMoment.dueNow;
  return DoseMoment.upcoming;
}
