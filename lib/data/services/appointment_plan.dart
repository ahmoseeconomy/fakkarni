import '../../domain/health/checkup.dart';
import '../../domain/health/follow_display.dart';
import '../../domain/health/follow_up.dart';
import '../../domain/scheduling/day_routine.dart';
import 'reminder_plan.dart';

/// **خطة إشعارات المواعيد — دوال نقية، من غير قاعدة ولا جهاز.**
///
/// يوم فيه مواعيد بياخد إشعارين: واحد **هادي** امبارحه بالليل، وواحد
/// **بيرن** الصبح بتاعه. الحساب كله هنا عشان يتختبر بالأرقام — الحالات
/// اللي بتغلط (ميعاد بكرة، ميعاد النهارده، ميعاد عدّى، نافذة مليانة)
/// أسهل تتكتب كأرقام من إنها تتلقّط بالعين.
///
/// **إشعار واحد لكل لحظة، مش واحد لكل ميعاد** (طلب المالك، من جهاز
/// حقيقي): صبح واحد فيه زيارة وميعاد معمل كان بيرن مرتين، وكل رنّة
/// بتقول نصّ الخبر. بقى «النهارده عندك: زيارة الدكتور، وميعاد المعمل».

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

/// **الكلمة اللي بتقول الميعاد ده إيه** — مصدر واحد للكارت وللإشعار.
///
/// كانت مكتوبة مرتين، والنسخة اللي في الكارت كانت بتقارن على
/// `stage.label` كنص — يعني تعديل كلمة في `CheckupStage` كان بيرجّع
/// «ميعاد» من غير أي خطأ في أي مكان. الـswitch هنا على القيمة نفسها.
String appointmentHeadline(FollowStage stage) => switch (stage) {
      CheckupStage.labBooking => 'ميعاد المعمل',
      CheckupStage.waitingResult => 'النتيجة تجهز',
      CheckupStage.resultArrived => 'معاد الدكتور',
      VisitStage.booked => 'زيارة الدكتور',
      _ => 'ميعاد',
    };

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

  /// عنوان الصف **زي ما هو متخزّن**. العرض بيعدّي على
  /// [followDisplayTitle] — مش بيتعرض خام في أي مكان.
  final String title;
  final FollowKind kind;
  final FollowStage stage;

  /// لحظة الميعاد اللي **جهاز الأب** حسبها. ولا سطر هنا بيحل مرساة.
  final DateTime at;

  String get headline => appointmentHeadline(stage);

  /// «متابعة CBC» — الاسم باللي بنتابعه، وبأرقام عربية.
  String get displayTitle => followDisplayTitle(kind, title);
}

/// إشعار يوم واحد، جاهز للجدولة.
class AppointmentNoticePlan {
  const AppointmentNoticePlan({
    required this.day,
    required this.notice,
    required this.at,
    required this.title,
    required this.body,
    required this.count,
  });

  /// اليوم اللي المواعيد فيه — **ومنه الرقم**.
  final DateTime day;
  final AppointmentNotice notice;

  /// وقت الإشعار نفسه.
  final DateTime at;

  final String title;
  final String body;

  /// كام ميعاد في اليوم ده — للاختبارات وللتشخيص.
  final int count;

  bool get quiet => notice == AppointmentNotice.dayBefore;

  /// **الرقم بيتشتق جوّه**، فمفيش نداء ممكن يجدول بالرقم الغلط.
  int get id => appointmentIdFor(day, notice);

  PlannedNotification toPlanned() => PlannedNotification(
        id: id,
        at: at,
        title: title,
        body: body,
        payload: '',
        kind: quiet ? NotificationKind.appointmentQuiet : NotificationKind.appointmentAlert,
      );
}

/// «بكرة ميعادك في المعمل» — ميعاد واحد في اليوم.
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

/// **أكتر من ميعاد في يوم = عنوان واحد بيسمّيهم.**
///
/// «النهارده عندك: زيارة الدكتور، وميعاد المعمل». من تلاتة وفوق بنسمّي
/// الأولين وبنقول «وحاجة كمان» — العنوان اللي بيعدّ كل حاجة بيتقصّ في
/// شريط الإشعارات، والأولين هما اللي بيفرقوا.
const int appointmentsNamedInTitle = 2;

String groupedAppointmentTitle(List<AppointmentInput> day, {required bool dayBefore}) {
  final lead = dayBefore ? 'بكرة عندك' : 'النهارده عندك';
  final names = [for (final a in day.take(appointmentsNamedInTitle)) a.headline];
  final more = day.length > appointmentsNamedInTitle;
  return '$lead: ${names.first}، و${names.last}${more ? '، وحاجة كمان' : ''}';
}

/// المتن: أسامي اللي العنوان سمّاهم، مش أكتر — عنوان بيقول «وحاجة كمان»
/// ومتن بيعدّ التلاتة بيتناقضوا قدّام عين واحدة بتقرا بسرعة.
String groupedAppointmentBody(List<AppointmentInput> day) =>
    [for (final a in day.take(appointmentsNamedInTitle)) a.displayTitle].join(' — ');

/// كل إشعارات المواعيد اللي **لسه جاية**، مرتّبة بوقتها — **واحد لكل
/// (يوم، نوع)**.
///
/// الإشعار اللي وقته عدّى ما بيدخلش: جدولته بتتجاهل في الجهاز أصلاً،
/// ولو عدّيناه كان هياخد مكان في النافذة من غير ما يرن.
List<AppointmentNoticePlan> appointmentNotices({
  required List<AppointmentInput> appointments,
  required DayRoutine routine,
  required DateTime now,
}) {
  // اليوم هو المفتاح. الترتيب جوّه اليوم بالوقت ثم بالصف، عشان الجملة
  // ما تتغيّرش من تشغيلة للتانية على نفس الداتا.
  final byDay = <DateTime, List<AppointmentInput>>{};
  for (final a in appointments) {
    byDay.putIfAbsent(DateTime(a.at.year, a.at.month, a.at.day), () => []).add(a);
  }
  for (final list in byDay.values) {
    list.sort((x, y) {
      final byTime = x.at.compareTo(y.at);
      return byTime != 0 ? byTime : x.recordId.compareTo(y.recordId);
    });
  }

  final out = <AppointmentNoticePlan>[];
  for (final MapEntry(key: day, value: list) in byDay.entries) {
    // **الوقت بيتبني بالمنشئ مش بـadd(Duration)** — مصر بتغيّر الساعة،
    // والمنشئ بيشتغل بساعة الحيطة.
    final before = DateTime(day.year, day.month, day.day - 1, 0, dayBeforeMinute(routine).minutes);
    final of = DateTime(day.year, day.month, day.day, 0, dayOfMinute(routine).minutes);
    final one = list.length == 1;
    for (final (notice, at) in [
      (AppointmentNotice.dayBefore, before),
      (AppointmentNotice.dayOf, of),
    ]) {
      if (!at.isAfter(now)) continue;
      final dayBefore = notice == AppointmentNotice.dayBefore;
      out.add(AppointmentNoticePlan(
        day: day,
        notice: notice,
        at: at,
        count: list.length,
        title: one
            ? (dayBefore
                ? appointmentDayBeforeTitle(list.single)
                : appointmentDayOfTitle(list.single))
            : groupedAppointmentTitle(list, dayBefore: dayBefore),
        body: one ? list.single.displayTitle : groupedAppointmentBody(list),
      ));
    }
  }
  out.sort((x, y) {
    final byTime = x.at.compareTo(y.at);
    return byTime != 0 ? byTime : x.notice.index.compareTo(y.notice.index);
  });
  return out;
}

/// **نافذة iOS المتدحرجة**: أقرب [max] إشعار وبس.
///
/// السقف ده هو `checkupPendingSlack` نفسه اللي كان محجوز للمواعيد —
/// **ولا خانة واحدة اتاخدت من الجرعات**. اللي برّه النافذة بيستنى دوره،
/// والكارت على «يومك» هو اللي بيقول إنه موجود.
///
/// **والخانتين بقوا بيغطّوا أكتر بعد التجميع**: كانوا إشعارين لميعاد
/// واحد، بقوا إشعارين ليوم كامل مهما كان فيه كام ميعاد.
List<AppointmentNoticePlan> rollingWindow(
  List<AppointmentNoticePlan> notices, {
  int max = checkupPendingSlack,
}) =>
    notices.take(max).toList();
