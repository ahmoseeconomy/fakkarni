import '../../data/care/caregiver_remote.dart';
import '../../data/dose_state.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../domain/adherence/adherence.dart';

/// من صفوف «يومك» المحلية لمدخلات الحساب. المفتاح `جدول|يوم` عشان
/// «أخدتها متأخر» يرجع للصف نفسه ويعدّي على نفس سكّة التأكيد.
String viewKey(DoseEventView v) {
  final d = v.routineDay ?? v.scheduledAt;
  return '${v.doseScheduleId}|${d.year}-${d.month}-${d.day}';
}

AdherenceState _fromLocal(DoseState s) => switch (s) {
      DoseState.taken => AdherenceState.taken,
      DoseState.skipped => AdherenceState.skipped,
      DoseState.missed => AdherenceState.missed,
      // `superseded` مش بيوصل هنا أصلاً (الاستعلام بيشيله) — لو وصل، ده
      // مش جرعة: بيتعامل كـ«لسه» وبيتشال بالفلتر اللي تحت.
      DoseState.pending || DoseState.superseded => AdherenceState.pending,
    };

List<AdherenceDose> dosesFromViews(List<DoseEventView> views) => [
      for (final v in views)
        if (v.state != DoseState.superseded)
          AdherenceDose(
            id: viewKey(v),
            medicationName: v.medicationName,
            routineDay: v.routineDay ?? v.scheduledAt,
            scheduledAt: v.scheduledAt,
            state: _fromLocal(v.state),
          ),
    ];

/// من الصورة اللي وصلت للعيلة والممرض. تأكيد الممرض اللي لسه موبايل
/// المريض ما سحبهوش (`proxied`) بيتحسب «اتاخدت» — هو كده فعلاً على
/// السيرفر (٠٠٢٣).
List<AdherenceDose> dosesFromSnapshot(CaregiverSnapshot s) => [
      for (final e in s.events)
        AdherenceDose(
          id: e.uuid,
          medicationName: e.medicationName,
          routineDay: e.routineDay ?? e.scheduledAt,
          scheduledAt: e.scheduledAt,
          state: s.proxied.containsKey(e.uuid)
              ? AdherenceState.taken
              : switch (e.state) {
                  'taken' => AdherenceState.taken,
                  'skipped' => AdherenceState.skipped,
                  'missed' => AdherenceState.missed,
                  _ => AdherenceState.pending,
                },
        ),
    ];

/// الصورة بتتسحب من «دلوقتي − ٧ أيام» بالساعة، فأول يوم فيها ممكن يبقى
/// ناقص — بيتشال، والعدّ اللي يوصل لأول يوم كامل بيتقال «أو أكتر».
DateTime snapshotDataFrom(DateTime now) => DateTime(now.year, now.month, now.day - 6);

Adherence adherenceFromSnapshot(CaregiverSnapshot s, DateTime now) => computeAdherence(
      dosesFromSnapshot(s),
      today: DateTime(now.year, now.month, now.day),
      now: now,
      dataFrom: snapshotDataFrom(now),
    );

DateTime? firstDoseDay(List<AdherenceDose> doses) {
  DateTime? first;
  for (final d in doses) {
    final day = DateTime(d.routineDay.year, d.routineDay.month, d.routineDay.day);
    if (first == null || day.isBefore(first)) first = day;
  }
  return first;
}
