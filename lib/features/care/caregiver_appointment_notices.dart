import '../../data/care/caregiver_remote.dart';
import '../../data/services/reminder_plan.dart';
import '../../data/services/reminder_sink.dart';
import '../../data/services/appointment_plan.dart' show appointmentsNamedInTitle;
import '../../domain/care/follower_profile.dart';
import '../../domain/health/follow_display.dart';
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
/// بترجّع خريطة رقم → إشعار، مقصوصة عند [caregiverAppointmentCap] **يوم**.
///
/// **إشعار واحد لكل يوم، زي موبايل الأب بالظبط** — أب عنده زيارة وميعاد
/// معمل في يوم واحد كان بيرنّ على ابنه مرتين بنفس الخبر مقسوم نصّين.
Map<int, PlannedNotification> caregiverAppointmentNotices(
  CaregiverSnapshot snapshot, {
  required DateTime now,

  /// نافذة هدوء الابن — **بتأجّل إشعارات المواعيد دي وبس**.
  ///
  /// تنبيه الجرعة الفايتة مش هنا أصلاً: بيجي دفع من السيرفر، و**بيعدّي في
  /// أي وقت** (قرار المالك ٢٢ سبتمبر ٢٠٢٦). تأجيله لحد الصبح هو بالظبط
  /// اللي السلّم موجود عشان يمنعه.
  QuietHours? quiet,
}) {
  final byDay = <DateTime, List<CareFollowUp>>{};
  for (final f in careFollowUps(snapshot, now)) {
    if (f.stageDate case final at? when at.isAfter(now)) {
      byDay.putIfAbsent(DateTime(at.year, at.month, at.day), () => []).add(f);
    }
  }
  final days = byDay.keys.toList()..sort();

  final out = <int, PlannedNotification>{};
  for (final day in days.take(caregiverAppointmentCap)) {
    final list = byDay[day]!
      ..sort((a, b) => a.stageDate!.compareTo(b.stageDate!));
    final before = DateTime(day.year, day.month, day.day - 1, 0, caregiverEveningMinute);
    final of = DateTime(day.year, day.month, day.day, 0, caregiverMorningMinute);
    for (final (notice, fireAt, lead, silent) in [
      (AppointmentNotice.dayBefore, before, 'بكرة', true),
      (AppointmentNotice.dayOf, of, 'النهارده', false),
    ]) {
      if (!fireAt.isAfter(now)) continue;
      // **بيتأجّل لآخر النافذة، ما بيتلغيش**: الابن لازم يعرف إن في ميعاد
      // بكرة، بس مش الساعة اتنين بالليل.
      final at = heldUntil(fireAt, quiet);
      final id = caregiverAppointmentIdFor(day, notice);
      out[id] = PlannedNotification(
        id: id,
        at: at,
        title: list.length == 1
            // «تحليل» / «زيارة» — كلمة النوع زي ما الأب بيقراها.
            ? '$lead عند والدك ${list.single.kind.word}'
            : '$lead عند والدك ${_kindsLine(list)}',
        // نفس قاعدة الأب: الاسم باللي بنتابعه، مش عنوان الورقة الخام.
        body: [
          for (final f in list.take(appointmentsNamedInTitle))
            followDisplayTitle(f.kind, f.record.title),
        ].join(' — '),
        payload: '',
        kind: silent ? NotificationKind.appointmentQuiet : NotificationKind.appointmentAlert,
      );
    }
  }
  return out;
}

/// «زيارة وتحليل» — أو «زيارة وتحليل وحاجة كمان» من تلاتة وفوق.
String _kindsLine(List<CareFollowUp> day) {
  final names = [for (final f in day.take(appointmentsNamedInTitle)) f.kind.word];
  final more = day.length > appointmentsNamedInTitle;
  return '${names.first} و${names.last}${more ? ' وحاجة كمان' : ''}';
}

/// بيطابق اللي على الجهاز مع اللي المفروض يكون — **إلغاء قبل جدولة**.
///
/// بيتنده مع كل سحبة، فلازم يبقى بلا أثر لو مفيش حاجة اتغيّرت: الأرقام
/// مشتقة من مكان الميعاد في القايمة، وجدولة نفس الرقم بتستبدل مش بتزوّد.
Future<void> syncCaregiverAppointments(
  CaregiverSnapshot snapshot, {
  required ReminderSink sink,
  required DateTime now,
  QuietHours? quiet,
}) async {
  final wanted = caregiverAppointmentNotices(snapshot, now: now, quiet: quiet);
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
