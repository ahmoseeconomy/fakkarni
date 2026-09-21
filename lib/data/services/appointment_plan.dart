import '../../domain/health/checkup.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/scheduling/day_routine.dart';
import 'reminder_plan.dart';

/// **خطة إشعارات المواعيد — دوال نقية، من غير قاعدة ولا جهاز.**
///
/// ميعاد المتابعة بقى إشعارين: واحد **هادي** امبارح الميعاد بالليل،
/// وواحد **بيرن** الصبح بتاعه. الحساب كله هنا عشان يتختبر بالأرقام —
/// الحالات اللي بتغلط (ميعاد بكرة، ميعاد النهارده، ميعاد عدّى، نافذة
/// مليانة) أسهل تتكتب كأرقام من إنها تتلقّط بالعين.

/// **المرساة المسائية لإشعار امبارح الميعاد: العشا.**
///
/// مش رقم مخترع: «اليوم بيبدأ من الصحيان» هي قاعدة التطبيق، والعشا هو
/// المرساة المسائية اللي الراجل نفسه قالها في «ظبّط يومك». ساعتها هو
/// قاعد في البيت وخلاص يومه — وده بالظبط وقت «بكرة عندك ميعاد».
/// من غير روتين متحفوظ بنرجع للافتراضي، زي باقي التطبيق.
MinuteOfDay dayBeforeMinute(DayRoutine routine) => routine.dinner;

/// **وإشعار اليوم نفسه على الصحيان** — نفس اللي `setStageDate` كانت
/// بتعمله من الأول، ومفيش سبب يتغيّر: أول ما يصحى يعرف إن النهارده ميعاد.
MinuteOfDay dayOfMinute(DayRoutine routine) => routine.wake;

/// إشعار ميعاد واحد، جاهز للجدولة.
class AppointmentNoticePlan {
  const AppointmentNoticePlan({
    required this.recordId,
    required this.kind,
    required this.stage,
    required this.notice,
    required this.at,
    required this.title,
    required this.body,
    required this.appointmentAt,
  });

  final int recordId;

  /// نوع المتابعة — منه بتتاخد خانة المرحلة في الرقم المشتق.
  final FollowKind kind;
  final FollowStage stage;
  final AppointmentNotice notice;

  /// وقت الإشعار نفسه.
  final DateTime at;

  /// وقت الميعاد — بيستعمل في الترتيب وفي الكارت.
  final DateTime appointmentAt;

  final String title;
  final String body;

  bool get quiet => notice == AppointmentNotice.dayBefore;

  /// خانة المرحلة جوّه نوعها — ٠..٢، زي ما الرقم المشتق بيتوقع.
  int get stageSlot => kind.slotOf(stage);

  PlannedNotification toPlanned(int id) => PlannedNotification(
        id: id,
        at: at,
        title: title,
        body: body,
        payload: '',
        kind: quiet ? NotificationKind.appointmentQuiet : NotificationKind.appointmentAlert,
      );
}

/// ميعاد مفتوح زي ما الحساب بيشوفه — صف الأب أو صف السحابة، الاتنين
/// بيتحوّلوا للشكل ده قبل ما يوصلوا هنا.
class AppointmentInput {
  const AppointmentInput({
    required this.recordId,
    required this.title,
    required this.kind,
    required this.stage,
    required this.at,
  });

  final int recordId;
  final String title;
  final FollowKind kind;
  final FollowStage stage;

  /// لحظة الميعاد اللي **جهاز الأب** حسبها. ولا سطر هنا بيحل مرساة.
  final DateTime at;
}

/// «بكرة عندك زيارة — …» / «بكرة ميعادك في المعمل — …».
String appointmentDayBeforeTitle(AppointmentInput a) => switch (a.stage) {
      CheckupStage.labBooking => 'بكرة ميعادك في المعمل',
      CheckupStage.waitingResult => 'بكرة نتيجة التحليل',
      CheckupStage.resultArrived => 'بكرة معادك مع الدكتور',
      VisitStage.booked => 'بكرة عندك زيارة',
      _ => 'بكرة عندك ميعاد',
    };

String appointmentDayOfTitle(AppointmentInput a) => switch (a.stage) {
      CheckupStage.labBooking => 'النهارده ميعادك في المعمل',
      CheckupStage.waitingResult => 'النهارده النتيجة المفروض تجهز',
      CheckupStage.resultArrived => 'النهارده معادك مع الدكتور',
      VisitStage.booked => 'النهارده عندك زيارة',
      _ => 'النهارده عندك ميعاد',
    };

/// كل إشعارات المواعيد اللي **لسه جاية**، مرتّبة بوقتها.
///
/// الإشعار اللي وقته عدّى ما بيدخلش: جدولته بتتجاهل في الجهاز أصلاً،
/// ولو عدّيناه كان هياخد مكان في النافذة من غير ما يرن.
List<AppointmentNoticePlan> appointmentNotices({
  required List<AppointmentInput> appointments,
  required DayRoutine routine,
  required DateTime now,
}) {
  final out = <AppointmentNoticePlan>[];
  for (final a in appointments) {
    final day = DateTime(a.at.year, a.at.month, a.at.day);
    // **الوقت بيتبني بالمنشئ مش بـadd(Duration)** — مصر بتغيّر الساعة،
    // والمنشئ بيشتغل بساعة الحيطة.
    final before = DateTime(day.year, day.month, day.day - 1, 0, dayBeforeMinute(routine).minutes);
    final of = DateTime(day.year, day.month, day.day, 0, dayOfMinute(routine).minutes);
    for (final (notice, at) in [
      (AppointmentNotice.dayBefore, before),
      (AppointmentNotice.dayOf, of),
    ]) {
      if (!at.isAfter(now)) continue;
      out.add(AppointmentNoticePlan(
        recordId: a.recordId,
        kind: a.kind,
        stage: a.stage,
        notice: notice,
        at: at,
        appointmentAt: a.at,
        title: notice == AppointmentNotice.dayBefore
            ? appointmentDayBeforeTitle(a)
            : appointmentDayOfTitle(a),
        body: a.title,
      ));
    }
  }
  out.sort((x, y) {
    final byTime = x.at.compareTo(y.at);
    if (byTime != 0) return byTime;
    // ترتيب ثابت لما اتنين يقعوا على نفس الدقيقة — عشان النافذة ما
    // تتغيّرش من تشغيلة للتانية على نفس الداتا.
    final byRecord = x.recordId.compareTo(y.recordId);
    return byRecord != 0 ? byRecord : x.notice.index.compareTo(y.notice.index);
  });
  return out;
}

/// **نافذة iOS المتدحرجة**: أقرب [max] إشعار وبس.
///
/// السقف ده هو `checkupPendingSlack` نفسه اللي كان محجوز للمواعيد —
/// **ولا خانة واحدة اتاخدت من الجرعات**. اللي برّه النافذة بيستنى دوره،
/// والكارت على «يومك» هو اللي بيقول إنه موجود.
List<AppointmentNoticePlan> rollingWindow(
  List<AppointmentNoticePlan> notices, {
  int max = checkupPendingSlack,
}) =>
    notices.take(max).toList();
