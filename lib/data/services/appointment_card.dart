import '../../core/format/arabic_time.dart';
import '../../domain/health/follow_display.dart';
import '../../domain/health/follow_up.dart';
import '../db/app_database.dart';
import 'appointment_plan.dart' show appointmentHeadline;
import 'checkup_service.dart';

/// **الكارت الثابت على الشاشة — من ساعة الحجز لحد ما اليوم يعدّي.**
///
/// ده مش إشعار: الكارت عمره ما يرن. هو **شبكة الأمان** بتاعة نافذة iOS
/// المتدحرجة — إشعارات ميعاد بعيد ممكن تكون لسه ما دخلتش النافذة،
/// والكارت بيعرض الميعاد على أي حال وبيقول إن الموبايل هيفكّر امبارحه.
///
/// دوال نقية هنا عشان الترتيب والعدّ التنازلي يتختبروا بالأرقام.

/// ميعاد جاي زي ما الكارت بيعرضه.
class UpcomingAppointment {
  const UpcomingAppointment({
    required this.recordId,
    required this.title,
    required this.kind,
    required this.stage,
    required this.at,
  });

  final int recordId;

  /// عنوان الصف زي ما هو متخزّن — [displayTitle] هي اللي بتتعرض.
  final String title;
  final FollowKind kind;
  final FollowStage stage;
  final DateTime at;

  /// «زيارة الدكتور» / «ميعاد المعمل» — **من نفس الدالة اللي الإشعار
  /// بيقراها**. كانت نسخة تانية هنا بتقارن على `stage.label` كنص.
  String get headline => appointmentHeadline(stage);

  /// «متابعة CBC» — الاسم باللي بنتابعه، وبأرقام عربية.
  String get displayTitle => followDisplayTitle(kind, title);
}

// `countdownWord` عاشت هنا نسخة تانية لحد الجولة دي. بقت واحدة في
// `domain/health/follow_display.dart`: الكارت والشاشات والابن كلهم
// بيقروا نفس الجملة، ونسختين معناها اتنين يختلفوا في صمت.

/// المواعيد اللي الكارت بيعرضها — **الأقرب الأول**.
///
/// الشرط نفس شرط الإشعارات بالظبط: مرحلة ليها ميعاد، والميعاد لسه في
/// اليوم ده أو بعده، والتذكير لسه له لازمة. يوم الميعاد نفسه بيفضل
/// معروض لحد آخره — الراجل رايح النهارده.
List<UpcomingAppointment> upcomingAppointments(
  List<RecordRow> rows, {
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <UpcomingAppointment>[];
  for (final row in rows) {
    if (row.deletedAt != null || row.checkupStage == null) continue;
    final kind = CheckupService.kindOf(row);
    final current = CheckupService.stageOf(row);
    if (current == null) continue;
    for (final stage in kind.datedStages) {
      if (!followReminderStillUseful(kind, stage, current)) continue;
      final at = CheckupService.stageDateOf(row, stage);
      if (at == null) continue;
      if (DateTime(at.year, at.month, at.day).isBefore(today)) continue;
      out.add(UpcomingAppointment(
        recordId: row.id,
        title: row.title,
        kind: kind,
        stage: stage,
        at: at,
      ));
    }
  }
  out.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.recordId.compareTo(b.recordId);
  });
  return out;
}


/// **اللي زيادة بيتقال بالكلام** — «+ ميعاد تاني» / «+ ٢ مواعيد تانية».
///
/// «+١» لوحده رقم مالوش سياق: راجل عنده ٧٢ سنة بيقرا كارت فيه ميعاد
/// واحد ورقم صغير جنبه، فبيفتكر الرقم زينة — والميعاد التاني بيعدّي.
/// العربي بيعدّ تلات صيغ، فالمفرد والمثنى مكتوبين بالإيد.
String moreAppointmentsLabel(int rest) => switch (rest) {
      1 => '+ ميعاد تاني',
      2 => '+ ميعادين تانيين',
      _ => '+ ${arabicNumber(rest)} مواعيد تانية',
    };

/// **المتابعات اللي لسه مستنية حركة من الأب — ومالهاش ميعاد جاي.**
///
/// اللي ليها ميعاد جاي بتتعرض في «مواعيدك الجاية»، فعرضها هنا كمان
/// بيخلّي نفس الحاجة على الشاشة مرتين — والراجل بيفضل يدوّر أي واحدة
/// الحقيقية. القايمة الكاملة في «زيارات» و«تحاليل» زي ما هي؛ ده عن
/// الشاشة الرئيسية بس.
List<RecordRow> needsActionFollowUps(
  List<RecordRow> rows, {
  required DateTime now,
}) {
  final dated = {for (final a in upcomingAppointments(rows, now: now)) a.recordId};
  return [
    for (final row in rows)
      if (row.deletedAt == null && row.checkupStage != null && !dated.contains(row.id)) row,
  ];
}
