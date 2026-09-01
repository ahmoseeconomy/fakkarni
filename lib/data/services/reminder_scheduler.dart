import '../../domain/scheduling/day_routine.dart';
import '../repositories/dose_event_repository.dart';
import '../repositories/medication_repository.dart';
import '../repositories/routine_repository.dart';
import 'reminder_plan.dart';
import 'reminder_sink.dart';

/// بيربط المحرك بالإشعارات.
///
/// بيتندَه بعد أي حاجة بتغيّر المواعيد: فتح التطبيق، حفظ الروتين، إضافة دوا،
/// إيقاف دوا. مش بيتندَه في خلفية ولا بتوقيت — كل تغيير بيعيد الحساب كامل.
class ReminderScheduler {
  const ReminderScheduler({
    required this.routines,
    required this.medications,
    required this.events,
    required this.patientId,
    this.patientIndex = 0,
    this.sink = const NotificationReminderSink(),
  });

  final RoutineRepository routines;
  final MedicationRepository medications;

  /// عشان نعرف إيه اللي اتأكد خلاص وما نعيدش جدولته.
  final DoseEventRepository events;
  final ReminderSink sink;
  final int patientId;

  /// خانة المريض في نطاق أرقام الإشعارات — بتفصل أرقام كل مريض عن التاني.
  final int patientIndex;

  /// بيعيد جدولة النافذة كلها من الأول.
  ///
  /// الأرقام مشتقة من الوقت، فتشغيل الدالة دي مية مرة ورا بعض بيدي نفس
  /// النتيجة بالظبط — مفيش إشعار بيتكرر.
  Future<void> rescheduleAll({DateTime? now}) async {
    final from = now ?? DateTime.now();

    // مفيش روتين لسه؟ نستخدم الافتراضي بدل ما نسيب المريض من غير تذكير.
    final routine = await routines.getRoutine(patientId) ?? DayRoutine.fallback;
    final schedules = await medications.activeSchedules(patientId);

    final planned = planWindow(
      routine: routine,
      schedules: schedules,
      from: from,
      patientIndex: patientIndex,
      // جرعة اتأكدت بدري لسه «قدام» بالساعة — من غير السطر ده كانت
      // هتتجدول تاني وترن على حاجة اتعملت.
      done: await events.doneKeys(from: from),
    );

    final plan = reconcile(planned, await sink.pendingIds());

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
  Future<void> cancelReminderAt(DateTime at) async {
    await sink.cancel(notificationIdFor(at, patientIndex: patientIndex));
    await sink.cancel(snoozeIdFor(at, patientIndex: patientIndex));
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
  Future<void> snooze({
    required DateTime originalAt,
    required String body,
    required String payload,
    Duration delay = snoozeDelay,
    DateTime? now,
  }) =>
      sink.schedule(
        PlannedNotification(
          id: snoozeIdFor(originalAt, patientIndex: patientIndex),
          at: (now ?? DateTime.now()).add(delay),
          title: 'وقت الدوا',
          body: body,
          payload: payload,
        ),
      );
}
