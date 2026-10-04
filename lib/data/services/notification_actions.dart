import '../../core/notifications/notification_service.dart'
    show NotificationActions;
import '../../domain/scheduling/schedule_engine.dart';
import '../dose_state.dart';
import '../repositories/dose_event_repository.dart';
import '../repositories/medication_repository.dart';
import '../sync/sync_service.dart';
import 'reminder_plan.dart';
import 'reminder_scheduler.dart';
import '../../core/diagnostics.dart';

/// اللي المعالج عمله فعلاً بالدوسة — **الطابور ما بيشيلش الملف غير لو
/// [done]** (قرار المالك، ٣٠ سبتمبر ٢٠٢٦: الدوسة عمرها ما تتشال قبل ما
/// الجرعة تتسجّل). الباقي خروج هادي: الدوسة دي عمرها ما هتتسجّل، فالملف
/// بيتنقل لـ`bad/` ومعاه سطر — مش بيتمسح، ومش بيتعاد للأبد.
enum ActionOutcome {
  /// الجرعة اتكتبت taken.
  recorded,

  /// «فكّرني بعدين» اتجدول.
  snoozed,

  /// «مش هاخده» — الجرعة اتكتبت skipped.
  skipped,

  /// زرار مش بتاعنا.
  unknownAction,

  /// الـpayload ما اتفكّش.
  badPayload,

  /// مفيش جرعة شغّالة للإشعار ده (الدوا اتوقف أو مواعيده اتغيّرت).
  noActiveDose;

  bool get done => this == recorded || this == snoozed || this == skipped;
}

/// بيعالج زرار اتداس على الإشعار — من الخلفية أو من التطبيق.
///
/// من غير واجهة خالص عن قصد: بيشتغل والتطبيق مقفول، على isolate لوحده، ومع
/// قاعدة بيانات اتفتحت للحظة دي. كل اللي بيعمله: يسجّل الجرعة، يسكّت
/// الخانة، ويمدّ النافذة — وده اللي بيخلي التغطية تتجدد من شاشة القفل.
class NotificationActionHandler {
  const NotificationActionHandler({
    required this.medications,
    required this.events,
    required this.scheduler,
    required this.patientId,
    this.prepareNotifications,
    this.cloud,
  });

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
  Future<ActionOutcome> handle(String? actionId, String? payload, {DateTime? now}) async {
    // **كل خروج هادي بيتسجّل** (تشخيص «أخدته» اللي بتضيع، ٣٠ سبتمبر ٢٠٢٦):
    // الطابور بيعتبر الخروج ده «اتطبّق» وبيشيل الملف — فمن غير السطر ده
    // الدوسة بتختفي من غير أثر. أرقام وأيام بس، ولا اسم دوا.
    if (!NotificationActions.isAction(actionId)) {
      diag('Handle: خروج — الزرار مش معروف (action=$actionId)');
      return ActionOutcome.unknownAction;
    }
    final decoded = decodePayload(payload);
    if (decoded == null) {
      diag('Handle: خروج — الـpayload ما اتفكّش (action=$actionId، طوله ${payload?.length ?? 0})');
      return ActionOutcome.badPayload;
    }

    const engine = ScheduleEngine();
    final day = decoded.routineDay;
    final reminders = engine.remindersForDay(
      await medications.activeSchedules(patientId),
      day,
    );

    // الجرعات اللي الإشعار ده كان عشانها — الساعة بنحسبها من الجدول
    // الحالي، مش من الإشعار: الـpayload فيه اليوم والجداول بس.
    final doses = [
      for (final reminder in reminders)
        for (final dose in reminder.doses)
          if (decoded.scheduleIds.contains(dose.id)) dose,
    ];
    if (doses.isEmpty) {
      // دوا اتوقف أو مواعيده اتغيّرت بعد ما الإشعار اتجدول
      diag('Handle: خروج — مفيش جرعة شغّالة للإشعار ده (action=$actionId، '
          'يوم=${_day(decoded.routineDay)}، جداول=${decoded.scheduleIds.join(',')}، '
          'جرعات اليوم=${reminders.fold<int>(0, (n, r) => n + r.doses.length)})');
      return ActionOutcome.noActiveDose;
    }
    final at = engine.resolve(doses.first, day);
    final outcome = switch (actionId) {
      NotificationActions.taken => ActionOutcome.recorded,
      NotificationActions.skip => ActionOutcome.skipped,
      _ => ActionOutcome.snoozed,
    };
    final state = actionId == NotificationActions.skip ? DoseState.skipped : DoseState.taken;

    switch (actionId) {
      // «مش هاخده» = نفس وعد «أخدته» بحالة تانية: الصف الأول، وبعده إلغاء
      // كل اللي الخانة دي لسه ممكن ترنّه (القاعدة ٥). مفيش مخزون بينقص.
      case NotificationActions.taken || NotificationActions.skip:
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
            state: state,
          );
        }
        diag('Handle: اتكتب ${state.name} — ${doses.length} جرعة، يوم=${_day(day)}، '
            'جداول=${doses.map((d) => d.id).join(',')}');

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
        // المخزون بينقص بعد الإلغاءات والجدولة — مجاملة، زي الرفع
        await _courtesy('المخزون', events.flushStock);

      case NotificationActions.snooze:
        // التأجيل نفسه إشعار، فمفيش حاجة تتكتب قبل التهيئة هنا — هو ده
        // الوعد كله.
        await prepareNotifications?.call();
        await scheduler.snooze(
          originalAt: at,
          body: reminderBodyFor([
            for (final d in doses) (name: d.medicationName, amount: d.amountLabel, note: d.ruleLabel),
          ]),
          payload: payload!,
          now: now,
        );
        diag('Handle: اتأجّل ربع ساعة — ${doses.length} جرعة، يوم=${_day(day)}');
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
      diag(
          'Handle: الرفع للسحابة — ${describePushOutcome(PushOutcome.noConfig)}');
      return outcome;
    }
    SyncService? service;
    try {
      service = await build();
    } catch (error, stack) {
      diag('Handle: ⚠ تهيئة السحابة فشلت (التأكيد اتسجّل برضه): '
          '$error\n$stack');
      return outcome;
    }
    if (service == null) {
      diag(
          'Handle: الرفع للسحابة — ${describePushOutcome(PushOutcome.noConfig)}');
      return outcome;
    }
    await _courtesy('الرفع للسحابة', service.pushOnce);
    return outcome;
  }

  /// خطوة مسموح لها تفشل — بس مش مسموح لها تفشل في صمت.
  ///
  /// الوعد (تسجيل الجرعة وتسكيت الخانة) خلص قبل ما نوصل هنا، فأي رمية من
  /// تحت ما بتلغيهوش. بنسجّلها بوضوح عشان تبان في Console.app وبنكمّل.
  Future<void> _courtesy(String what, Future<void> Function() step) async {
    try {
      await step();
    } catch (error, stack) {
      diag('Handle: ⚠ $what فشلت (التأكيد اتسجّل برضه): $error\n$stack');
    }
  }
}

/// «٢٠٢٦-٠٩-٣٠» بأرقام لاتيني — للسجل بس.
String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
