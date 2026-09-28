import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_scope.dart';
import '../../core/diagnostics.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/care/caregiver_preferences.dart';
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

/// **تذكيرات الممرض بمواعيد مريضه** — على موبايل الممرض، من الأوقات اللي
/// موبايل المريض حسبها (مفيش حلّ مراسي). **تذكيرات المريض نفسه على
/// موبايله زي ما هي وهي مصدر الحقيقة.**
///
/// - نطاق أرقام لوحده ([isNurseId] + [isNurseSnoozeId]) — الإلغاء من جوّاه
///   بس، فتذكيرات المريض وسلّمه وتصعيد السيرفر ما بيتلمسوش (ودول أصلاً على
///   جهاز تاني).
/// - **إعادة الجدولة = المقارنة** ([sync]): بعد كل صورة من السحابة، وعند
///   الفتح والرجوع للمقدمة — أي تعديل جدول (من المريض أو الممرض) بيوصل
///   بالصورة الجاية وبيتحوّل لأرقام جديدة، والقديم بيتلغي كـ«مش في الخطة».
/// - **تأكيد من أي ناحية بيلغي الناحية التانية** ([onConfirmed]): إشارة
///   الدفع من السيرفر، ولو ما وصلتش المقارنة الجاية بتلغيه.
/// - مفتاحين: «فكّرني بمواعيده» على الموبايل ده، و«نبهني بمواعيد الدوا»
///   لكل مريض (0035، في السحابة). والاشتراك لو خلص: بيلغي كله.
class NurseReminders {
  NurseReminders({required this.sink, this.remote, this.preferences, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  final NurseReminderSink sink;

  /// لصور المرضى التانيين (غير المختار) — بتتسحب كل [otherEvery] بس.
  final MultiPatientRemote? remote;

  /// مفتاح «نبهني بمواعيد الدوا» لكل مريض (0035). null = مفتوح.
  final CaregiverPreferencesService? preferences;
  final DateTime Function() clock;

  static const enabledKey = 'nurse.remind';
  static const plannedKey = 'nurse.planned';
  static const otherEvery = Duration(minutes: 15);
  static const laterBy = Duration(minutes: 15);

  final _latest = <String, CaregiverSnapshot>{};
  final _doseRemindersOn = <String, bool>{};
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

  /// «نبهني بمواعيد الدوا» للمريض ده — بيتقرا من السحابة مرة، ويتحدّث بـ
  /// [setDoseRemindersOn]. فشل القراية = مفتوح (الافتراضي).
  Future<bool> doseRemindersOn(String patientUuid) async {
    final cached = _doseRemindersOn[patientUuid];
    if (cached != null) return cached;
    final prefs = preferences;
    if (prefs == null) return true;
    try {
      final on = (await prefs.load(patientUuid)).nurseDoseReminders;
      _doseRemindersOn[patientUuid] = on;
      return on;
    } catch (_) {
      return true;
    }
  }

  void setDoseRemindersOn(String patientUuid, bool on) => _doseRemindersOn[patientUuid] = on;

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
      // التأجيلات («لاحقاً») اللي جرعتها اتقفلت أو راحت من الخطة بتتلغي
      final slots = {for (final n in planned) n.id - nurseIdBase};
      for (final id in (await sink.pendingIds()).where(isNurseSnoozeId)) {
        if (!slots.contains(id - nurseSnoozeIdBase)) await sink.cancel(id);
      }
      await _savePlanned(planned);
    } catch (error) {
      diag('Nurse: جدولة تذكيرات الممرض فشلت — المرة الجاية بتكمّل ($error)');
    }
  }

  /// آخر خطة (رقم ← الأحداث) — عشان إشارة «اتأكّدت» تلاقي رقمها حتى بعد
  /// إعادة تشغيل التطبيق.
  Future<void> _savePlanned(List<NurseNotification> planned) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, Object?>{};
      for (final n in planned) {
        final parsed = parseNursePayload(n.payload);
        if (parsed != null) map['${n.id}'] = {'p': parsed.patient, 'e': parsed.events};
      }
      await prefs.setString(plannedKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<Map<int, ({String patient, List<String> events})>> _loadPlanned() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(plannedKey);
      if (raw == null) return const {};
      final json = jsonDecode(raw);
      if (json is! Map) return const {};
      return {
        for (final e in json.entries)
          if (int.tryParse(e.key) case final id? when e.value is Map)
            id: (
              patient: (e.value as Map)['p'] as String? ?? '',
              events: [for (final x in ((e.value as Map)['e'] as List? ?? const [])) if (x is String) x],
            ),
      };
    } catch (_) {
      return const {};
    }
  }

  /// **الجرعة اتأكّدت من الناحية التانية** (المريض على موبايله، أو ممرض
  /// تاني) — التذكير وتأجيله بيتلغوا حالاً. بيرجّع عدد اللي اتلغى.
  /// اللي الإشارة ما وصلتش له بيتلغى في [sync] الجاي — التعريف واحد.
  Future<int> onConfirmed({required String patientUuid, required String doseEventUuid}) async {
    var cancelled = 0;
    try {
      final planned = await _loadPlanned();
      for (final entry in planned.entries) {
        if (entry.value.patient != patientUuid || !entry.value.events.contains(doseEventUuid)) continue;
        await sink.cancel(entry.key);
        await sink.cancel(nurseSnoozeIdBase + (entry.key - nurseIdBase));
        cancelled++;
      }
      // والصورة المحلية تعرف — عشان sync اللي جاي ما يرجّعهوش قبل الصورة الجديدة
      final s = _latest[patientUuid];
      if (s != null) {
        _latest[patientUuid] = CaregiverSnapshot(
          patient: s.patient,
          medications: s.medications,
          events: s.events,
          alerts: s.alerts,
          lastUpdated: s.lastUpdated,
          records: s.records,
          readings: s.readings,
          emergency: s.emergency,
          questions: s.questions,
          proxied: {...s.proxied, doseEventUuid: null},
          sharedPapers: s.sharedPapers,
          vitals: s.vitals,
          departures: s.departures,
        );
      }
    } catch (error) {
      diag('Nurse: إلغاء بعد التأكيد وقع ($error)');
    }
    return cancelled;
  }

  /// «لاحقاً»: نفس التذكير بعد ربع ساعة، برقم التأجيل بتاع خانته. الأصلي
  /// بيتشال من الجهاز (النظام شاله أصلاً بالدوسة).
  Future<bool> later({required int? id, required String? payload}) async {
    final parsed = parseNursePayload(payload);
    final at = parsed?.at;
    final index = parsed?.patientIndex;
    if (parsed == null || at == null || index == null) return false;
    try {
      if (id != null && (isNurseId(id) || isNurseSnoozeId(id))) await sink.cancel(id);
      final when = clock().add(laterBy);
      await sink.schedule(NurseNotification(
        id: nurseSnoozeIdFor(at, patientIndex: index),
        at: when,
        title: parsed.title ?? 'ميعاد دوا',
        body: nurseReminderBody,
        payload: payload!,
        insistent: true,
      ));
      return true;
    } catch (error) {
      diag('Nurse: «لاحقاً» وقع ($error)');
      return false;
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
    final list = <NursePatientDoses>[];
    for (final (i, p) in sorted.indexed) {
      final s = _latest[p.uuid];
      if (s == null || !await doseRemindersOn(p.uuid)) continue;
      list.add(NursePatientDoses(
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
      ));
    }
    return planNurseReminders(list, now: now);
  }
}

/// **«أخدها» من الإشعار = تأكيد نيابةً** — نفس نداء الشاشة
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
  if (id != null && (isNurseId(id) || isNurseSnoozeId(id))) {
    try {
      await NotificationService.cancel(id);
      // وتأجيله لو كان فيه — الجرعة اتأكّدت
      if (isNurseId(id)) await NotificationService.cancel(nurseSnoozeIdBase + (id - nurseIdBase));
    } catch (_) {}
  }
  return done;
}

/// باب زراير تذكير الممرض — «أخدها» تأكيد نيابةً، و«لاحقاً» تأجيل ربع ساعة
/// على الموبايل ده. مفيش زرار منهم بيلمس جرعات المريض على موبايله.
Future<void> handleNurseNotificationAction(AppServices services, String actionId, int? id, String? payload) async {
  if (actionId == NotificationActions.nurseLater) {
    await NurseReminders(sink: const DeviceNurseReminderSink()).later(id: id, payload: payload);
    return;
  }
  await confirmFromNurseNotification(services, id, payload);
}
