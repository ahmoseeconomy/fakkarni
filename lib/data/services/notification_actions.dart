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
    this.prepareNotifications,
    this.cloud,
  });

  final RoutineRepository routines;
  final MedicationRepository medications;
  final DoseEventRepository events;
  final ReminderScheduler scheduler;
  final int patientId;

  /// تهيئة الإشعارات — بتتنده **بعد** ما صف الجرعة اتكتب، وقبل أول
  /// نداء على الجدولة.
  ///
  /// كانت بتتعمل في `bootstrap` قبل المعالج كله. على iOS الصحوة دي
  /// مالهاش مهلة مضمونة (شوف `BackgroundTask`)، فأي نداء قناة قبل
  /// الكتابة بيتصرف من وقت الكتابة نفسها. الترتيب بقى: نكتب الأول،
  /// وبعدين نجهّز اللي محتاجينه عشان نسكّت.
  final Future<void> Function()? prepareNotifications;

  /// السحابة — **دالة**، مش خدمة جاهزة، عن قصد.
  ///
  /// تهيئة Supabase بتاخد لحد ثانيتين، وكانت بتتعمل قبل تسجيل الجرعة.
  /// القاعدة الخامسة بتقول إن التأكيد بيلغي كل درجة ما رنّتش **في
  /// نفس اللحظة**؛ تهيئة سحابة قدام الكتابة المحلية هي القاعدة دي
  /// مكسورة في الترتيب. دلوقتي الدالة دي ما بتتندهش غير في آخر سطر،
  /// بعد ما كل وعد اتنفّذ.
  final Future<SyncService?> Function()? cloud;

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
        // ---------------------------------------------------- الوعد
        // أصغر كتابة ممكنة، الأول خالص. صف الحدث ممكن يكون لسه مش
        // موجود — «يومك» هي اللي بتنزّله، والتطبيق ما اتفتحش النهاردة —
        // فـ[confirmDose] بتزرعه وتكتب حالته في معاملة واحدة.
        //
        // لو الكتابة دي وقعت، بنرمي. **تأكيد فشل عمره ما يشبه تأكيد
        // نجح**: الإشعار بيختفي من شاشة القفل في الحالتين، فلو بلعنا
        // الخطأ المريض بيفتكر إنه أكّد والجرعة مش مسجّلة.
        for (final dose in doses) {
          await events.confirmDose(
            doseScheduleId: int.parse(dose.id),
            routineDay: day,
            scheduledAt: at,
            state: DoseState.taken,
          );
        }

        // القاعدة الخامسة — وعد كمان: التأكيد بيسكّت كل درجات السلّم
        // للخانة دي في نفس اللحظة. الإلغاء بيمرّ على الإضافة، فالتهيئة
        // بتحصل هنا — **بعد** الصف، مش قبله.
        await prepareNotifications?.call();
        await scheduler.cancelReminderAt(at);

        // -------------------------------------------------- المجاملات
        // مدّ النافذة ورفع السحابة. الاتنين مهمين — من غير مدّ النافذة
        // التغطية بتخلص بعد أيام لمريض مالوش سبب يفتح التطبيق — لكن ولا
        // واحد فيهم وعد. فشلهم بيتسجّل بصوت عالي وبيتساب، ومش مسموح له
        // يوقّع تأكيد اتسجّل خلاص.
        await _courtesy('مدّ النافذة', () => scheduler.rescheduleAll(now: now));

      case NotificationActions.snooze:
        // التأجيل نفسه إشعار، فمفيش حاجة تتكتب قبل التهيئة هنا — هو ده
        // الوعد كله.
        await prepareNotifications?.call();
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
    //
    // **والنتيجة بتتقال في كل الحالات**، حتى لما مفيش سحابة أصلاً: ساعتها
    // `pushOnce` ما بتتندهش خالص، فالسطر ده هو الوحيد اللي بيقول ليه.
    // من غيره، الجرعة اللي اتأكدت من شاشة القفل وما وصلتش السحابة بتبان
    // بالظبط زي الجهاز اللي مش مربوط — والاتنين ساكتين بنفس الشكل.
    final build = cloud;
    if (build == null) {
      debugPrint(
          'Handle: الرفع للسحابة — ${describePushOutcome(PushOutcome.noConfig)}');
      return;
    }
    SyncService? service;
    try {
      service = await build();
    } catch (error, stack) {
      debugPrint('Handle: ⚠ تهيئة السحابة فشلت (التأكيد اتسجّل برضه): '
          '$error\n$stack');
      return;
    }
    if (service == null) {
      debugPrint(
          'Handle: الرفع للسحابة — ${describePushOutcome(PushOutcome.noConfig)}');
      return;
    }
    await _courtesy('الرفع للسحابة', service.pushOnce);
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
