import '../../app/app_scope.dart';
import '../../data/repositories/dose_event_repository.dart';
import '../../data/services/reminder_plan.dart';

/// اللي بيتعمل على مجموعة جرعات من «الآن» — الرئيسية ونمط كبار السن
/// الاتنين بيندهوا هنا، فمفيش نسختين من «تأكيد» ولا من «بعد شوية».

/// بتجمّع الأحداث اللي في نفس الدقيقة — نفس تجميع المحرك بالظبط.
List<List<DoseEventView>> groupByMinute(List<DoseEventView> events) {
  final byTime = <DateTime, List<DoseEventView>>{};
  for (final event in events) {
    byTime.putIfAbsent(event.scheduledAt, () => []).add(event);
  }
  final times = byTime.keys.toList()..sort();
  return [for (final time in times) byTime[time]!];
}

/// «الآن»: اللي فات معاده من غير تأكيد (الأقدم الأول)، وبعده الجاية.
List<List<DoseEventView>> nowGroups(List<List<DoseEventView>> groups, DateTime now) {
  final open = [for (final g in groups) if (g.any((d) => !d.isDone)) g];
  final overdue = [for (final g in open) if (g.first.scheduledAt.isBefore(now)) g];
  final upcoming = [for (final g in open) if (!g.first.scheduledAt.isBefore(now)) g];
  return [...overdue, if (upcoming.isNotEmpty) upcoming.first];
}

/// «تأكيد» — كل جرعة في المجموعة اتاخدت، وبعدها القاعدة ٥: الخانة كلها
/// بتسكت ونافذة الجدولة بتتمد.
Future<void> confirmGroup(AppServices services, DateTime routineDay, List<DoseEventView> group) async {
  for (final dose in group) {
    await services.events.markTaken(dose.doseScheduleId, routineDay);
  }
  await services.scheduler.afterConfirmation(group.first.scheduledAt);
}

/// «لاحقًا» / «بعد شوية» = التأجيل الحقيقي (ربع ساعة).
Future<void> snoozeGroup(
  AppServices services,
  DateTime routineDay,
  List<DoseEventView> group, {
  required DateTime now,
}) =>
    services.scheduler.snooze(
      originalAt: group.first.scheduledAt,
      body: reminderBodyFor([
        for (final d in group) (name: d.medicationName, amount: d.amountLabel),
      ]),
      payload: encodePayloadFor(
        routineDay,
        [for (final d in group) d.doseScheduleId.toString()],
      ),
      now: now,
    );
