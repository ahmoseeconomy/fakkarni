import '../../domain/health/follow_up.dart';
import '../db/app_database.dart';
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
    required this.stage,
    required this.at,
  });

  final int recordId;
  final String title;
  final FollowStage stage;
  final DateTime at;

  /// «زيارة الدكتور» / «ميعاد المعمل» — الكلمة اللي بتقول ده إيه.
  String get headline => switch (stage.label) {
        'حجز المعمل' => 'ميعاد المعمل',
        'انتظار النتيجة' => 'النتيجة تجهز',
        'النتيجة وصلت' => 'معاد الدكتور',
        'الزيارة اتحجزت' => 'زيارة الدكتور',
        _ => 'ميعاد',
      };
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
