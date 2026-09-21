import '../../data/care/caregiver_remote.dart';
import '../../data/services/reminder_plan.dart';
import '../../data/services/reminder_sink.dart';
import 'caregiver_status.dart';

/// **مواعيد الأب على موبايل الابن — إشعارات محلية، من السحبة.**
///
/// مفيش APNs لسه، فمفيش دفع من السيرفر للابن على iOS. اللي موجود إن
/// تطبيق الابن بيسحب صورة كل شوية — فبنجدول من الصورة دي **على موبايله
/// هو**: هادي امبارح الميعاد، وواحد بيرن في يومه، نفس تقسيمة الأب.
///
/// **والحد اللي ده بيسيبه لازم يتقال**: ميعاد اتحجز بعد آخر سحبة عمره ما
/// يوصل موبايل الابن غير لما يفتح التطبيق تاني. الحل الحقيقي دفع من
/// السيرفر (FCM شغّال لابن على أندرويد؛ iOS مستني APNs) — وده مكتوب في
/// CLAUDE.md مش مخبّى هنا.
///
/// **وما بتلمسش تنبيهات التصعيد ولا قناتها.** دي آخر درجة في السلّم؛
/// الإلغاء هنا مقصور على نطاق مواعيد الابن وبس.

/// الساعة اللي إشعارات الابن بتترمي عليها — **رقم ثابت على موبايله هو**.
///
/// الأب بياخد مرساة العشا بتاعته من روتينه؛ الابن **ما بيحلّش مراسي
/// أبوه** — دي قاعدة مكتوبة (`no_scheduling_imports_test`)، ومحرّك تاني
/// على جهازه معناه جدولين ممكن يختلفوا في صمت. فالمساء هنا رقم تشغيلي
/// على موبايله، زي ٩ الصبح لما مفيش روتين.
const int caregiverEveningMinute = 20 * 60;
const int caregiverMorningMinute = 8 * 60;

/// إشعارات مواعيد الأب اللي المفروض تبقى متجدولة على موبايل الابن.
///
/// بترجّع خريطة رقم → إشعار، مقصوصة عند [caregiverAppointmentCap] ميعاد.
Map<int, PlannedNotification> caregiverAppointmentNotices(
  CaregiverSnapshot snapshot, {
  required DateTime now,
}) {
  final dated = [
    for (final f in careFollowUps(snapshot, now))
      if (f.stageDate case final at? when at.isAfter(now)) (f, at),
  ]..sort((a, b) => a.$2.compareTo(b.$2));

  final out = <int, PlannedNotification>{};
  for (final (index, entry) in dated.take(caregiverAppointmentCap).indexed) {
    final (follow, at) = entry;
    final day = DateTime(at.year, at.month, at.day);
    final before = DateTime(day.year, day.month, day.day - 1, 0, caregiverEveningMinute);
    final of = DateTime(day.year, day.month, day.day, 0, caregiverMorningMinute);
    final what = follow.kind.word; // «تحليل» / «زيارة»
    for (final (notice, fireAt, title, quiet) in [
      (AppointmentNotice.dayBefore, before, 'بكرة عند والدك $what', true),
      (AppointmentNotice.dayOf, of, 'النهارده عند والدك $what', false),
    ]) {
      if (!fireAt.isAfter(now)) continue;
      out[caregiverAppointmentIdFor(index, notice)] = PlannedNotification(
        id: caregiverAppointmentIdFor(index, notice),
        at: fireAt,
        title: title,
        body: follow.record.title,
        payload: '',
        kind: quiet ? NotificationKind.appointmentQuiet : NotificationKind.appointmentAlert,
      );
    }
  }
  return out;
}

/// بيطابق اللي على الجهاز مع اللي المفروض يكون — **إلغاء قبل جدولة**.
///
/// بيتنده مع كل سحبة، فلازم يبقى بلا أثر لو مفيش حاجة اتغيّرت: الأرقام
/// مشتقة من مكان الميعاد في القايمة، وجدولة نفس الرقم بتستبدل مش بتزوّد.
Future<void> syncCaregiverAppointments(
  CaregiverSnapshot snapshot, {
  required ReminderSink sink,
  required DateTime now,
}) async {
  final wanted = caregiverAppointmentNotices(snapshot, now: now);
  final pending = await sink.pendingIds();
  for (final id in pending) {
    // **نطاقنا وبس** — تنبيهات التصعيد بتاعة الابن مالهاش أي علاقة بده.
    if (!isCaregiverAppointmentId(id)) continue;
    if (wanted.containsKey(id)) continue;
    await sink.cancel(id);
  }
  for (final n in wanted.values) {
    await sink.schedule(n);
  }
}
