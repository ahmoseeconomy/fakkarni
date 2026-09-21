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

/// «النهارده» / «بكرة» / «بعد ٣ أيام» — بأيام تقويمية مش بضرب في ٢٤.
///
/// مصر بتغيّر الساعة، والعدّ بالأيام لازم يمشي بساعة الحيطة.
String countdownWord(DateTime now, DateTime at) {
  final days = DateTime(at.year, at.month, at.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (days <= 0) return 'النهارده';
  if (days == 1) return 'بكرة';
  if (days == 2) return 'بعد بكرة';
  return 'بعد ${_arabic(days)} أيام';
}

String _arabic(int v) {
  const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return v.toString().split('').map((c) => digits[int.parse(c)]).join();
}

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
