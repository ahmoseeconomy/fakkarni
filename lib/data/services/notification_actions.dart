import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/notifications/notification_service.dart'
    show NotificationActions;
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../dose_state.dart';
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
    debugPrint('Handle: ٠- دخلنا — action=$actionId payload=$payload');
    if (!NotificationActions.isAction(actionId)) {
      debugPrint('Handle: خرجنا — actionId مش معروف');
      return;
    }
    final decoded = decodePayload(payload);
    if (decoded == null) {
      debugPrint('Handle: خرجنا — الـpayload مش اتفكّ');
      return;
    }
    debugPrint('Handle: ٠.٥- الـpayload اتفكّ');

    debugPrint('Handle: أ- بنجيب الروتين');
    final routine = await routines.getRoutine(patientId) ?? DayRoutine.fallback;
    debugPrint('Handle: ب- الروتين جه');
    final engine = ScheduleEngine(routine);
    final day = decoded.routineDay;
    final reminders = engine.remindersForDay(
      await medications.activeSchedules(patientId),
      day,
    );
    debugPrint('Handle: ج- التذكيرات اتحسبت (${reminders.length})');

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
        // ---------------------------------------------------- الوعد
        // أصغر كتابة ممكنة، الأول خالص. صف الحدث ممكن يكون لسه مش
        // موجود — «يومك» هي اللي بتنزّله، والتطبيق ما اتفتحش النهاردة —
        // فـ[confirmDose] بتزرعه وتكتب حالته في معاملة واحدة.
        //
        // لو الكتابة دي وقعت، بنرمي. **تأكيد فشل عمره ما يشبه تأكيد
        // نجح**: الإشعار بيختفي من شاشة القفل في الحالتين، فلو بلعنا
        // الخطأ المريض بيفتكر إنه أكّد والجرعة مش مسجّلة.
        debugPrint('Handle: د- بنسجّل التأكيد');
        for (final dose in doses) {
          await events.confirmDose(
            doseScheduleId: int.parse(dose.id),
            routineDay: day,
            scheduledAt: at,
            state: DoseState.taken,
          );
        }
        debugPrint('Handle: هـ- التأكيد اتسجّل');

        // القاعدة الخامسة — وعد كمان: التأكيد بيسكّت كل درجات السلّم
        // للخانة دي في نفس اللحظة.
        await scheduler.cancelReminderAt(at);
        debugPrint('Handle: و- الخانة اتسكّتت');

        // -------------------------------------------------- المجاملات
        // مدّ النافذة ورفع السحابة. الاتنين مهمين — من غير مدّ النافذة
        // التغطية بتخلص بعد أيام لمريض مالوش سبب يفتح التطبيق — لكن ولا
        // واحد فيهم وعد. فشلهم بيتسجّل بصوت عالي وبيتساب، ومش مسموح له
        // يوقّع تأكيد اتسجّل خلاص.
        await _courtesy('مدّ النافذة', () => scheduler.rescheduleAll(now: now));

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
    debugPrint('Handle: ح- بنرفع للسحابة');
    await _courtesy('الرفع للسحابة', () async => sync?.pushOnce());
    debugPrint('Handle: ط- الرفع خلص');
  }

  /// خطوة مسموح لها تفشل — بس مش مسموح لها تفشل في صمت.
  ///
  /// الوعد (تسجيل الجرعة وتسكيت الخانة) خلص قبل ما نوصل هنا، فأي رمية من
  /// تحت ما بتلغيهوش. بنسجّلها بوضوح عشان تبان في Console.app وبنكمّل.
  Future<void> _courtesy(String what, Future<void> Function() step) async {
    try {
      await step();
    } catch (error, stack) {
      debugPrint('Handle: ⚠ $what فشلت (التأكيد اتسجّل برضه): $error\n$stack');
    }
  }
}
