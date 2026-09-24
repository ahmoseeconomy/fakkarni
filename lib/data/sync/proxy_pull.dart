import '../../core/diagnostics.dart';
import '../care/proxy_confirmations.dart';
import '../repositories/dose_event_repository.dart';
import '../repositories/routine_repository.dart';
import '../services/reminder_scheduler.dart';

/// **السحبة الوحيدة من السحابة لـdrift**: تأكيدات الجرعات اللي حد تاني
/// عملها (الممرض، ٠٠٢٣) — وبس. أي حاجة تانية لسه بتتقرا من السحابة مباشرة
/// عند الابن، وموبايل الأب لسه مصدر الحقيقة للتذكير.
///
/// تأكيد اتسحب = «أخدته» بالظبط (القاعدة ٥): الصف بيتكتب `taken` باسم اللي
/// أكّد، وبعدها [ReminderScheduler.afterConfirmation] بتلغي الإعادات ودرجات
/// السلّم بتاعة اللحظة دي وبتعيد الجدولة. بيتنده عند الفتح والرجوع للمقدمة
/// وبعد كل رفعة ناجحة. مجاملة: بيسجّل وما بيرميش.
class ProxyConfirmationPuller {
  ProxyConfirmationPuller({
    required this.remote,
    required this.routines,
    required this.events,
    required this.scheduler,
    required this.patientId,
    this.window = const Duration(days: 3),
    this.clock = DateTime.now,
  });

  final ProxyConfirmRemote remote;
  final RoutineRepository routines;
  final DoseEventRepository events;
  final ReminderScheduler scheduler;
  final int patientId;
  final Duration window;
  final DateTime Function() clock;

  bool _running = false;

  /// بيرجّع عدد الجرعات اللي اتأكّدت محلياً من السحبة دي.
  Future<int> pull() async {
    if (_running) return 0;
    _running = true;
    try {
      final patient = await routines.getPatient(patientId);
      if (patient == null) return 0;
      final now = clock();
      final rows = await remote.fetchForPatient(patient.uuid, since: now.subtract(window));
      var applied = 0;
      for (final row in rows) {
        final at = await events.confirmByProxy(
          doseEventUuid: row.doseEventUuid,
          actorName: row.actorName,
          confirmedAt: row.confirmedAt,
        );
        if (at == null) continue;
        applied++;
        // نفس سكّة «أخدته»: الإلغاء الأول، وبعدها إعادة الجدولة
        await scheduler.afterConfirmation(at, now: now);
        diag('Proxy: جرعة ${at.toIso8601String()} اتأكّدت بدال المريض — ${row.actorName ?? 'بدون اسم'}');
      }
      return applied;
    } catch (error) {
      diag('Proxy: سحب التأكيدات وقع ($error)');
      return 0;
    } finally {
      _running = false;
    }
  }
}
