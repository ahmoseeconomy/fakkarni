import '../../core/notifications/notification_service.dart';
import 'reminder_plan.dart';

/// الحتة الوحيدة اللي بتلمس الجهاز.
///
/// موجودة كواجهة عشان منطق إعادة الجدولة يتختبر من غير إضافات ولا جهاز حقيقي.
abstract interface class ReminderSink {
  Future<void> schedule(PlannedNotification notification);
  Future<void> cancel(int id);
  Future<Set<int>> pendingIds();

  /// بيطلب أذونات الإشعار والمنبّه الدقيق.
  ///
  /// موجودة هنا مش في الشاشة عشان الشاشة تفضل تتختبر من غير إضافات جهاز.
  Future<void> ensurePermissions();
}

/// التنفيذ الحقيقي — بيمرّر لـ[NotificationService] من غير ما يغيّر فيها حاجة.
class NotificationReminderSink implements ReminderSink {
  const NotificationReminderSink();

  @override
  Future<void> schedule(PlannedNotification notification) => switch (notification.kind) {
        // تذكير الصيام طريقه لوحده: من غير أزرار الجرعة ومن غير payload
        NotificationKind.fasting => NotificationService.scheduleCheckup(
            id: notification.id,
            title: notification.title,
            body: notification.body,
            at: notification.at,
          ),
        // ميعاد متابعة: قناته هو، منبّه غير دقيق، والهادي صامت تماماً
        NotificationKind.appointmentQuiet || NotificationKind.appointmentAlert =>
          NotificationService.scheduleAppointment(
            id: notification.id,
            title: notification.title,
            body: notification.body,
            at: notification.at,
            quiet: notification.kind == NotificationKind.appointmentQuiet,
          ),
        _ => NotificationService.scheduleDose(
            id: notification.id,
            title: notification.title,
            body: notification.body,
            at: notification.at,
            payload: notification.payload,
            escalation: notification.kind == NotificationKind.escalation,
          ),
      };

  @override
  Future<void> cancel(int id) => NotificationService.cancel(id);

  @override
  Future<Set<int>> pendingIds() async =>
      (await NotificationService.pending()).map((r) => r.id).toSet();

  @override
  Future<void> ensurePermissions() async {
    await NotificationService.requestPermissions();
    if (!await NotificationService.canScheduleExact()) {
      await NotificationService.requestExactAlarmPermission();
    }
  }
}
