import '../../core/notifications/notification_service.dart'
    show NotificationActions;
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../repositories/dose_event_repository.dart';
import '../repositories/medication_repository.dart';
import '../repositories/routine_repository.dart';
import '../sync/sync_service.dart';
import 'reminder_plan.dart';
import 'reminder_scheduler.dart';

/// بيعالج زرار اتداس على الإشعار — من الخلفية أو من التطبيق.
///
/// من غير واجهة خالص عن قصد: بيشتغل والتطبيق مقفول، على isolate لوحده، ومع
/// قاعدة بيانات اتفتحت للحظة دي. كل اللي بيعمله: يسجّل الجرعة، يسكّت
/// الخانة، ويمدّ النافذة — وده اللي بيخلي التغطية تتجدد من شاشة القفل.
class NotificationActionHandler {
  const NotificationActionHandler({
    required this.routines,
    required this.medications,
    required this.events,
    required this.scheduler,
    required this.patientId,
    this.sync,
  });

  final RoutineRepository routines;
  final MedicationRepository medications;
  final DoseEventRepository events;
  final ReminderScheduler scheduler;
  final int patientId;

  /// المزامنة اختيارية: من غير جلسة أو من غير ربط، الجهاز أوفلاين ١٠٠٪.
  final SyncService? sync;

  /// [now] للاختبارات — على الجهاز الساعة الحقيقية.
  Future<void> handle(String? actionId, String? payload, {DateTime? now}) async {
    if (!NotificationActions.isAction(actionId)) return;
    final decoded = decodePayload(payload);
    if (decoded == null) return;

    final routine = await routines.getRoutine(patientId) ?? DayRoutine.fallback;
    final engine = ScheduleEngine(routine);
    final day = decoded.routineDay;
    final reminders = engine.remindersForDay(
      await medications.activeSchedules(patientId),
      day,
    );

    // الجرعات اللي الإشعار ده كان عشانها — الساعة بنحسبها من الروتين
    // الحالي، مش من الإشعار: الـpayload فيه اليوم والجداول بس.
    final doses = [
      for (final reminder in reminders)
        for (final dose in reminder.doses)
          if (decoded.scheduleIds.contains(dose.id)) dose,
    ];
    if (doses.isEmpty) return; // دوا اتوقف بعد ما الإشعار اتجدول
    final at = engine.resolve(doses.first, day);

    switch (actionId) {
      case NotificationActions.taken:
        // صف الحدث ممكن يكون لسه مش موجود — «يومك» هي اللي بتنزّله، والتطبيق
        // ما اتفتحش النهاردة. من غير السطر ده التأكيد كان بيروح في صمت.
        await events.materializeDay(day, reminders);
        for (final dose in doses) {
          await events.markTaken(int.parse(dose.id), day);
        }
        await scheduler.afterConfirmation(at, now: now);

      case NotificationActions.snooze:
        await scheduler.snooze(
          originalAt: at,
          body: reminderBodyFor([
            for (final d in doses) (name: d.medicationName, amount: d.amountLabel),
          ]),
          payload: payload!,
          now: now,
        );
    }

    // السحابة **آخر حاجة خالص**، وبعد ما كل اللي فوق خلص.
    //
    // القاعدة الخامسة بتقول إن التأكيد بيسكّت التصعيد في نفس اللحظة. لو في
    // نداء شبكة قبل الإلغاء، يبقى على شبكة بايظة درجة الـ+٣٠ بتفضل مسلّحة
    // والموبايل بيزنّ على راجل خد دواه خلاص. الكتابة المحلية والإلغاء وعد
    // للمريض؛ الرفع مجاملة للسيرفر ومسموح له يفشل.
    //
    // [SyncService.pushOnce] عمرها ما بترمي، فمفيش حاجة فوق ممكن تتلغي
    // بسببها — وهي كمان آخر سطر، فمفيش حاجة بعدها تتأثر.
    await sync?.pushOnce();
  }
}
