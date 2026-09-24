import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_scope.dart';
import '../../core/diagnostics.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/care/caregiver_remote.dart';
import '../../data/services/nurse_reminder_plan.dart';
import '../../data/services/reminder_plan.dart';
import '../../domain/billing/family_plan.dart';

/// الجهاز اللي تذكيرات الممرض بتتجدول عليه — Flutter Local Notifications
/// في الحقيقي، وفيك في الاختبار.
abstract interface class NurseReminderSink {
  Future<void> schedule(NurseNotification n);
  Future<void> cancel(int id);
  Future<Set<int>> pendingIds();
}

class DeviceNurseReminderSink implements NurseReminderSink {
  const DeviceNurseReminderSink();

  @override
  Future<void> schedule(NurseNotification n) => NotificationService.scheduleNurseDose(
        id: n.id,
        title: n.title,
        body: n.body,
        at: n.at,
        payload: n.payload,
        insistent: n.insistent,
      );

  @override
  Future<void> cancel(int id) => NotificationService.cancel(id);

  @override
  Future<Set<int>> pendingIds() async => (await NotificationService.pending()).map((r) => r.id).toSet();
}

/// **«فكّرني بمواعيده»** — تذكيرات محلية على موبايل الممرض بجرعات المريض.
///
/// - الأوقات من موبايل المريض بالحرف (مفيش حلّ مراسي).
/// - نطاق أرقام لوحده ([isNurseId]) — الإلغاء من جوّاه بس، فتذكيرات المريض
///   وسلّمه وتصعيد السيرفر ما بيتلمسوش (ودول أصلاً على جهاز تاني).
/// - مفتوح افتراضياً؛ قفله بيلغي كله. والاشتراك لو خلص: بيلغي كله برضه —
///   حساب الممرض شغّال مع التجربة/الاشتراك بس.
class NurseReminders {
  NurseReminders({required this.sink, this.remote, DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  final NurseReminderSink sink;

  /// لصور المرضى التانيين (غير المختار) — بتتسحب كل [otherEvery] بس.
  final MultiPatientRemote? remote;
  final DateTime Function() clock;

  static const enabledKey = 'nurse.remind';
  static const otherEvery = Duration(minutes: 15);

  final _latest = <String, CaregiverSnapshot>{};
  DateTime? _othersAt;

  static Future<bool> isEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(enabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool on) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(enabledKey, on);
    } catch (_) {}
  }

  /// بيتنده بعد كل صورة جديدة للمريض المختار. [allowed] = الاشتراك شغّال.
  Future<void> sync({
    required List<CaregiverPatient> patients,
    required CaregiverSnapshot? current,
    required bool allowed,
  }) async {
    try {
      final nurseOf = [for (final p in patients) if (p.isNurse) p];
      if (current != null) _latest[current.patient.uuid] = current;
      final on = allowed && await isEnabled();
      final planned = on ? await _plan(nurseOf, current?.patient.uuid) : const <NurseNotification>[];
      final want = {for (final n in planned) n.id};
      final pending = (await sink.pendingIds()).where(isNurseId).toSet();
      for (final id in pending.difference(want)) {
        await sink.cancel(id);
      }
      for (final n in planned) {
        await sink.schedule(n); // نفس الرقم = بيستبدل، مش بيضيف
      }
    } catch (error) {
      diag('Nurse: جدولة تذكيرات الممرض فشلت — المرة الجاية بتكمّل ($error)');
    }
  }

  Future<List<NurseNotification>> _plan(List<CaregiverPatient> patients, String? currentUuid) async {
    final now = clock();
    final others = remote;
    if (others != null && (_othersAt == null || now.difference(_othersAt!) >= otherEvery)) {
      _othersAt = now;
      for (final p in patients) {
        if (p.uuid == currentUuid) continue; // المختار جاي طازة من الحامل
        try {
          final s = await others.snapshotFor(p.uuid);
          if (s != null) _latest[p.uuid] = s;
        } catch (_) {}
      }
    }
    // الترتيب بالـuuid — ثابت مهما اتغيّر المختار، والرقم مشتق منه
    final sorted = [...patients]..sort((a, b) => a.uuid.compareTo(b.uuid));
    return planNurseReminders([
      for (final (i, p) in sorted.indexed)
        if (_latest[p.uuid] case final s?)
          NursePatientDoses(
            index: i,
            uuid: p.uuid,
            name: p.name,
            doses: [
              for (final e in s.events)
                NurseDose(
                  eventUuid: e.uuid,
                  medicationName: e.medicationName,
                  scheduledAt: e.scheduledAt,
                  state: e.state,
                  confirmedHere: s.proxied.containsKey(e.uuid),
                  insistent: s.medications.where((m) => m.name == e.medicationName).firstOrNull?.alertMode != 'once',
                ),
            ],
          ),
    ], now: now);
  }
}

/// **«أكّد إنه أخدها» من الإشعار = تأكيد نيابةً** — نفس نداء الشاشة
/// (`proxy_confirmations`)، وموبايل المريض بيسحبه ويلغي سلّمه (القاعدة ٥).
/// بيرجّع عدد اللي اتأكّد. **عمره ما بيعدّي على معالج «أخدته» بتاع المريض.**
Future<int> confirmFromNurseNotification(AppServices services, int? id, String? payload) async {
  final parsed = parseNursePayload(payload);
  final proxy = services.proxy;
  if (parsed == null || proxy == null) return 0;
  final sub = services.subscription;
  if (sub != null && sub.notice().kind == FamilyNoticeKind.ended) {
    diag('Nurse: تأكيد من الإشعار اتجاهل — الاشتراك خلص');
    return 0;
  }
  String? name;
  try {
    name = (await services.caregiverPreferences?.load(parsed.patient))?.name;
  } catch (_) {}
  var done = 0;
  for (final event in parsed.events) {
    try {
      await proxy.confirmOnBehalf(patientUuid: parsed.patient, doseEventUuid: event, actorName: name);
      done++;
    } catch (error) {
      diag('Nurse: تأكيد $event من الإشعار ما وصلش ($error)');
    }
  }
  if (id != null && isNurseId(id)) {
    try {
      await NotificationService.cancel(id);
    } catch (_) {}
  }
  return done;
}
