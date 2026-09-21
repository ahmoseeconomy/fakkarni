import 'dart:io' show Platform;

import '../../domain/scheduling/day_routine.dart';
import '../../domain/health/follow_up.dart';
import '../db/app_database.dart';
import '../repositories/records_repository.dart';
import '../repositories/routine_repository.dart';
import 'appointment_plan.dart';
import 'checkup_service.dart';
import 'reminder_plan.dart';
import 'reminder_sink.dart';

/// **جدولة المواعيد — دالة لوحدها، بتتنده بعد `rescheduleAll` وبس.**
///
/// القيد الأول في المواصفة: **ما نلمسش تذكير الدوا**. الطريقة اللي
/// بتضمن ده مش النية، دي الفصل:
///  * الملف ده ما بيعرفش حاجة عن الجرعات ولا عن السلّم ولا عن التأجيل.
///  * بيتنده **بعد** ما `rescheduleAll` ترجع، في `try/catch` بتاعه —
///    فاستثناء هنا مستحيل يمنع جرعة من إنها تتجدول.
///  * بيلغي **أرقامه هو بس**، من نطاق محجوز مالوش أي تقاطع مع أي نطاق
///    تاني. ومفيش `cancelAll()` في أي سطر.
///
/// **والمنصّتين بيختلفوا عن قصد**، وده مكتوب في CLAUDE.md:
///  * **iOS** سقفه ٦٤ إشعار معلّق، وبيرمي الزيادة **في صمت** — ممكن
///    يرمي جرعة على حدّ النافذة. فالمواعيد بتاخد خانتين بس
///    (`checkupPendingSlack`) كـ**نافذة متدحرجة**: أقرب إشعارين، وبيتعاد
///    حسابهم مع كل فتحة وكل تأكيد جرعة.
///  * **أندرويد** مفيش عنده السقف ده، فكل الإشعارات بتتجدول من ساعة
///    الحجز. النافذة المتدحرجة بتعتمد على إن التطبيق يتفتح — وده بالظبط
///    اللي قتلة البطارية بتاعة المصنّعين بتخليه أقل ضمانة على أندرويد.
class AppointmentScheduler {
  AppointmentScheduler({
    required this.db,
    required this.patientId,
    required this.sink,
    bool? rolling,
  }) : rolling = rolling ?? Platform.isIOS;

  final AppDatabase db;
  final int patientId;
  final ReminderSink sink;

  /// نافذة متدحرجة (iOS) ولا كله مرة واحدة (أندرويد)؟
  final bool rolling;

  /// **الجدولة كلها — إلغاء الخارج قبل جدولة الداخل.**
  ///
  /// الترتيب ده مش تفصيلة على iOS: لو جدولنا الجديد الأول، بيبقى فيه
  /// لحظة عدد المعلّق فيها أكبر من السقف — ولو الجهاز كان قريب من ٦٤
  /// ساعتها، بيرمي إشعار **في صمت**، وممكن يبقى جرعة. الاختبار بيقيس
  /// الأقصى **اللحظي**، مش النهائي.
  Future<void> refresh({DateTime? now}) async {
    final from = now ?? DateTime.now();
    final routine = await RoutineRepository(db).getRoutine(patientId) ?? DayRoutine.fallback;
    final rows = await RecordsRepository(db).all(patientId);

    final appointments = <AppointmentInput>[];
    for (final row in rows) {
      if (row.deletedAt != null || row.checkupStage == null) continue;
      final kind = CheckupService.kindOf(row);
      final current = CheckupService.stageOf(row);
      if (current == null) continue;
      // **كل مرحلة ليها ميعاد لسه له لازمة — مش المرحلة الحالية بس.**
      // ميعاد المعمل بيعيش لحد ما العينة تتسحب: الواحد بيعدّي على
      // «التحضير» **قبل** ما يروح، فقراية المرحلة الحالية لوحدها كانت
      // بتلغي الميعاد اللي هو رايح له بكرة. نفس قاعدة
      // [followReminderStillUseful] اللي `advance` بتمشي عليها.
      for (final stage in kind.datedStages) {
        if (!followReminderStillUseful(kind, stage, current)) continue;
        final at = CheckupService.stageDateOf(row, stage);
        if (at == null || !at.isAfter(from)) continue;
        appointments.add(AppointmentInput(
          recordId: row.id,
          title: row.title,
          kind: kind,
          stage: stage,
          at: at,
        ));
      }
    }

    final all = appointmentNotices(appointments: appointments, routine: routine, now: from);
    final wanted = rolling ? rollingWindow(all) : all;

    final wantedIds = <int, AppointmentNoticePlan>{
      for (final n in wanted)
        appointmentIdFor(n.recordId, n.stageSlot, n.notice): n,
    };

    // **الإلغاء الأول.** أي رقم من نطاقنا معلّق ومش في الخطة الجديدة
    // بيتشال قبل ما نجدول أي حاجة.
    final pending = await sink.pendingIds();
    for (final id in pending) {
      if (!isAppointmentId(id)) continue;
      if (wantedIds.containsKey(id)) continue;
      await sink.cancel(id);
    }
    for (final MapEntry(key: id, value: plan) in wantedIds.entries) {
      await sink.schedule(plan.toPlanned(id));
    }
  }
}
