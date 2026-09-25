import '../../domain/escalation/escalation_ladder.dart';
import '../../domain/escalation/repeat_alerts.dart';
import '../../domain/scheduling/day_routine.dart';
import '../../domain/scheduling/schedule_engine.dart';
import '../repositories/dose_event_repository.dart';
import '../repositories/medication_repository.dart';
import '../repositories/preferences_repository.dart';
import '../repositories/routine_repository.dart';
import 'reminder_plan.dart';
import 'reminder_sink.dart';

/// بيربط المحرك بالإشعارات.
///
/// بيتندَه بعد أي حاجة بتغيّر المواعيد: فتح التطبيق، حفظ الروتين، إضافة دوا،
/// إيقاف دوا. مش بيتندَه في خلفية ولا بتوقيت — كل تغيير بيعيد الحساب كامل.
class ReminderScheduler {
  ReminderScheduler({
    required this.routines,
    required this.medications,
    required this.events,
    required this.patientId,
    this.patientIndex = 0,
    this.sink = const NotificationReminderSink(),
    this.preferences,
  });

  final RoutineRepository routines;
  final MedicationRepository medications;

  /// عشان نعرف إيه اللي اتأكد خلاص وما نعيدش جدولته.
  final DoseEventRepository events;
  final ReminderSink sink;
  final int patientId;

  /// «التنبيهات» (D3.3): درجتين +١٥ و+٣٠ ممكن يتقفلوا. null = السلّم كامل.
  ///
  /// بيتقرا **وقت الجدولة بس** وبيفلتر الدرجات اللي طالعة من
  /// [planEscalations] — السلّم نفسه ما اتغيّرش. الدرجة اللي اتقفلت وكانت
  /// متجدولة بتتلغي لوحدها في المقارنة تحت (رقمها في نطاق إعادة الجدولة
  /// ومش في الخطة).
  final PreferencesRepository? preferences;

  /// خانة المريض في نطاق أرقام الإشعارات — بتفصل أرقام كل مريض عن التاني.
  final int patientIndex;

  /// آخر عدد تذكيرات جرعة الخطة طلعته — null قبل أول إعادة جدولة في
  /// العملية دي. بيتقرا في فحص السلامة وبس.
  int? lastPlannedDoseCount;

  /// آخر خطة اتقصّت؟ (تذكيرات أساسية في النافذة أكتر من الميزانية) —
  /// فحص السلامة بيقراها عشان «التغطية قليلة» تتقال بس لما دي الحقيقة.
  bool lastPlanTruncated = false;

  /// لحد آخر تذكير أساسي متجدول — null = الخطة ما اتقصّتش.
  Duration? lastCoverage;

  /// بيعيد جدولة النافذة كلها من الأول.
  ///
  /// الأرقام مشتقة من الوقت، فتشغيل الدالة دي مية مرة ورا بعض بيدي نفس
  /// النتيجة بالظبط — مفيش إشعار بيتكرر.
  Future<void> rescheduleAll({DateTime? now}) async {
    final from = now ?? DateTime.now();

    // مفيش روتين لسه؟ نستخدم الافتراضي بدل ما نسيب المريض من غير تذكير.
    final routine = await routines.getRoutine(patientId) ?? DayRoutine.fallback;
    final schedules = await medications.activeSchedules(patientId);

    // بننزّل امبارح والنهارده وبكرة — تلات أيام، كل واحد لسبب مختلف:
    //
    // * **امبارح**: جرعة «قبل النوم» بتاعته بتقع بعد نص الليل وممكن تكون
    //   عدّت المهلة وإحنا بنفتح الصبح.
    // * **النهارده**: يوم ما التطبيق اتفتحش فيه لازم يبقى له صفوف تتحسب.
    // * **بكرة**: عشان السحابة تعرف الجرعة **قبل معادها**. السيرفر
    //   بيصعّد لابنه من صفوف موجودة (٤.٢ب)، وهو ما بيحلّش مراسي أبداً —
    //   بيقرا اللحظات اللي جهاز الأب حسبها. أب ما بيلمسش الإشعارات مش
    //   بيصحّي حاجة، فلو ما نزّلناش بكرة النهارده، جرعة بكرة اللي هيهملها
    //   مش هيبقى ليها صف في السحابة أصلاً والتصعيد بيسكت في صمت.
    //
    // القيد اللي بيسيبه ده مكتوب صراحةً في «دين تقني»: التغطية يومين،
    // وبعدها السحابة بتقدم — والابن بيشوف ده في تذييل شاشته بالذهبي.
    final engine = ScheduleEngine(routine);
    final today = currentRoutineDay(routine, from);
    final activeFrom = await events.activeFromOf({for (final s in schedules) int.parse(s.id)});
    // جرعات معادها قبل ما قاعدتها تبقى سارية — مالهاش صف، وما ينفعش يترن
    // لها سلّم: دوا اتضاف ١١:١٧ وجرعته ١١:٠٠ كانت هتاخد درجة +٣٠ على حاجة
    // مش موجودة.
    final notYetActive = <String>{};
    for (final day in [
      DateTime(today.year, today.month, today.day - 1),
      today,
      DateTime(today.year, today.month, today.day + 1),
    ]) {
      final reminders = engine.remindersForDay(schedules, day);
      await events.materializeDay(day, reminders);
      for (final reminder in reminders) {
        for (final dose in reminder.doses) {
          if (activeFrom[int.parse(dose.id)] case final start? when reminder.at.isBefore(start)) {
            notYetActive.add(doneKey(dose.id, day));
          }
        }
      }
    }
    await events.sweepMissed(now: from);

    // جرعة اتأكدت بدري لسه «قدام» بالساعة — من غير السطر ده كانت
    // هتتجدول تاني وترن على حاجة اتعملت.
    final done = {...await events.doneKeys(from: from), ...notYetActive};

    // **كل** التذكيرات الأساسية في النافذة، وبعدين القسمة: لحد ٢٤ الخطة زي
    // الأول بالحرف؛ فوقه الأساسي بياخد من خانات الإعادات (الأقرب الأول).
    final everything = planWindow(
      routine: routine,
      schedules: schedules,
      from: from,
      patientIndex: patientIndex,
      done: done,
      maxPending: 1 << 20,
    );
    final budget = splitPendingBudget(everything.length);
    final planned = everything.take(budget.mains).toList();
    lastPlanTruncated = everything.length > planned.length;
    lastCoverage = coverageOf(planned, from: from, truncated: lastPlanTruncated);

    // السلّم بيتبني من قبل «دلوقتي» بمهلة: جرعة رنّت من ١٠ دقايق لسه
    // درجاتها قدام، وفتح التطبيق ما ينفعش يسكّتها. الإعادات بتتبني من
    // نفس الخطة المزاحة — إعادة ٨:١٠ لجرعة ٨:٠٠ لسه قدام الساعة ٨:٠٧.
    final recent = planWindow(
      routine: routine,
      schedules: schedules,
      from: DateTime(from.year, from.month, from.day, from.hour,
          from.minute - graceWindow.inMinutes),
      patientIndex: patientIndex,
      done: done,
      maxPending: maxPendingEscalations ~/ EscalationRung.values.length,
    );
    final ladder = planEscalations(recent, from: from, patientIndex: patientIndex);

    final settings = await preferences?.get();
    final enabled = settings?.enabledRungs ?? EscalationRung.values.toSet();
    final defaultMode = settings?.alertMode ?? AlertMode.standard;
    final allowedLadder = [
      for (final n in ladder)
        if (enabled.contains(escalationRungOf(n.id))) n,
    ];

    // إعادة التنبيه (+٥/+١٠/+١٥): نفس التذكير تاني لحد ما حد يتصرّف.
    // بتعرف الدرجات الشغّالة عشان ما ترنّش مرتين في نفس الدقيقة — السلّم
    // نفسه ما اتلمسش، ولا وقته ولا أرقامه.
    final repeats = planRepeats(
      recent,
      from: from,
      patientIndex: patientIndex,
      enabledRungs: enabled,
      maxPending: budget.repeats,
      // نوع التنبيه: بتاع الدوا، وإلا إعداد الجهاز — بيتقرا وقت الجدولة بس
      modeOf: (r) => alertModeOf(r, fallback: defaultMode),
    );

    // **الرقم ده بيتسجّل من الخطة الحقيقية، مش من نسخة منها.** فحص
    // السلامة بيقارنه باللي الجهاز ماسك فعلاً؛ لو اتحسب تاني في مكان
    // تاني، أي فرق صغير بين الحسبتين بيبقى إنذار كذب على شاشة المريض.
    lastPlannedDoseCount = planned.length;

    final plan = reconcile(
      [...planned, ...allowedLadder, ...repeats],
      await sink.pendingIds(),
      inBand: isRescheduledId,
    );

    for (final id in plan.toCancel) {
      await sink.cancel(id);
    }
    for (final notification in plan.toSchedule) {
      // نفس الرقم بيستبدل المتجدول مكانه بدل ما يزوّد إشعار تاني.
      await sink.schedule(notification);
    }
  }

  /// بيطلب الأذونات في وقت واضح — بعد ما المستخدم يخلص أسئلة يومه، مش
  /// عند أول فتح وهو لسه مش عارف التطبيق ده بيعمل إيه.
  Future<void> ensurePermissions() => sink.ensurePermissions();

  /// المريض قال «أخدته» — نلغي تذكير الخانة دي بس، من غير دورة كاملة.
  ///
  /// بنلغي التأجيل بتاعها كمان: لو كان قال «فكّرني بعدين» وبعدين خدها من
  /// «يومك»، الموبايل ما يرنّش تاني على حاجة اتعملت.
  ///
  /// والسلّم كله معاها — القاعدة الخامسة: التأكيد بيلغي التصعيد فوراً، في
  /// أي درجة كان. وإعادات التنبيه التلاتة كمان: إعادة بترن على راجل خد
  /// دواه خلاص هي نفس الزنّ اللي القاعدة الخامسة موجودة عشان تمنعه.
  Future<void> cancelReminderAt(DateTime at) async {
    await sink.cancel(notificationIdFor(at, patientIndex: patientIndex));
    await sink.cancel(snoozeIdFor(at, patientIndex: patientIndex));
    for (final rung in EscalationRung.values) {
      await sink.cancel(escalationIdFor(at, rung, patientIndex: patientIndex));
    }
    await _cancelRepeatsAt(at);
  }

  Future<void> _cancelRepeatsAt(DateTime at) async {
    // العشرة كلهم — مهما كان النوع وقت الجدولة، الإلغاء ما بيعرفش النوع
    for (var i = 0; i < maxRepeatsAny; i++) {
      await sink.cancel(repeatIdFor(at, i, patientIndex: patientIndex));
    }
  }

  /// المريض أكّد (خدها أو مش هياخدها): نسكّت الخانة **الأول**، وبعدين نمدّ
  /// النافذة.
  ///
  /// الترتيب ده هو القاعدة الخامسة: التأكيد بيلغي التذكير في نفس اللحظة.
  /// وإعادة الجدولة بعده هي اللي بتخلي التغطية تتجدد كل مرة يأكّد — من
  /// الإشعار نفسه على شاشة القفل، من غير ما يفتح التطبيق أبداً. مريض على
  /// ١٢ جرعة في اليوم عنده ٤ أيام في السقف؛ من غير ده كانت التذكيرات
  /// بتقف في صمت يوم ٥ بالظبط للي محتاجها أكتر من أي حد.
  Future<void> afterConfirmation(DateTime at, {DateTime? now}) async {
    await cancelReminderAt(at);
    await rescheduleAll(now: now);
  }

  /// «فكّرني بعد ربع ساعة» — تذكير واحد بعد [delay] بنفس المحتوى.
  ///
  /// الرقم مشتق من الخانة الأصلية، فتأجيل التأجيل بيستبدل نفسه بدل ما
  /// يزوّد إشعار تاني، و«أخدته» بتلغيه من غير ما تعرف إنه كان موجود.
  ///
  /// التأجيل مش تأكيد، فالسلّم ما بيتلغيش. بس الدرجات اللي التأجيل
  /// **بيسبقها أو بيقع عليها** بتتشال: «فكّرني بعدين» الساعة ٨:١٠ معناه
  /// «سيبني لـ٨:٢٥» — درجة ٨:١٥ كانت هتزنّ عكس اللي طلبه. درجة ٨:٣٠ بعدها
  /// بتفضل: السلّم سلّم.
  ///
  /// **وإعادات التنبيه بتتلغي كلها**: هي «نفس التذكير تاني»، والتأجيل هو
  /// نفسه التذكير تاني في الوقت اللي هو اختاره — إعادة جنبه زنّ مش
  /// تذكير.
  Future<void> snooze({
    required DateTime originalAt,
    required String body,
    required String payload,
    Duration delay = snoozeDelay,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).add(delay);
    await _cancelRepeatsAt(originalAt);
    for (final step in ladderFor(originalAt)) {
      if (step.at.isAfter(at)) continue;
      await sink.cancel(
        escalationIdFor(originalAt, step.rung, patientIndex: patientIndex),
      );
    }
    await sink.schedule(
      PlannedNotification(
        id: snoozeIdFor(originalAt, patientIndex: patientIndex),
        at: at,
        title: 'وقت الدوا',
        body: body,
        payload: payload,
      ),
    );
  }
}
