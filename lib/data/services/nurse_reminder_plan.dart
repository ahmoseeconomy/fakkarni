/// **تذكيرات الممرض — الخطة، دارت نقية.**
///
/// موبايل الممرض بيفكّره بجرعات المريض من **الأوقات اللي موبايل المريض
/// حسبها** (`dose_events.scheduled_at`) — مفيش حلّ مراسي هنا: جدول واحد في
/// المنتج، على موبايل المريض. ولا حاجة هنا بتلمس تذكيرات المريض ولا سلّمه
/// ولا تصعيد السيرفر: نطاق أرقام لوحده ([nurseIdBase])، على جهاز تاني.
library;

import 'dart:convert';

import 'reminder_plan.dart';

/// جرعة واحدة زي ما موبايل المريض رفعها.
class NurseDose {
  const NurseDose({
    required this.eventUuid,
    required this.medicationName,
    required this.scheduledAt,
    required this.state,
    this.confirmedHere = false,
    this.insistent = true,
  });

  final String eventUuid;
  final String medicationName;
  final DateTime scheduledAt;

  /// بالحرف من السحابة — `pending` بس هو اللي ليه تذكير.
  final String state;

  /// اتأكّدت من موبايل ممرض ولسه موبايل المريض ما سحبهاش.
  final bool confirmedHere;

  /// نوع تنبيه الدوا مش «مرة واحدة» → النغمة بتلفّ لحد ما يلمسه.
  final bool insistent;
}

class NursePatientDoses {
  const NursePatientDoses({required this.index, required this.uuid, required this.name, required this.doses});

  /// ترتيب المريض عند الممرض — جزء من الرقم، فلازم يبقى ثابت (بالـuuid).
  final int index;
  final String uuid;
  final String name;
  final List<NurseDose> doses;
}

class NurseNotification {
  const NurseNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
    required this.insistent,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
  final bool insistent;
}

/// أبعد من كده مفيش أحداث في السحابة أصلاً (موبايل المريض بيجهّز لحد بكرة).
const Duration nurseReminderHorizon = Duration(hours: 36);

/// الحمولة: `{"v":1,"nurse":{"p":uuid,"e":[uuids]}}` — عمرها ما تتلخبط مع
/// حمولة جرعة المريض (مفيها `nurse`)، والباب اللي بيقراها لوحده.
String nursePayload(String patientUuid, List<String> events) => jsonEncode({
      'v': 1,
      'nurse': {'p': patientUuid, 'e': events},
    });

/// null = مش حمولة ممرض.
({String patient, List<String> events})? parseNursePayload(String? payload) {
  if (payload == null) return null;
  try {
    final json = jsonDecode(payload);
    if (json is! Map || json['nurse'] is! Map) return null;
    final n = json['nurse'] as Map;
    final p = n['p'];
    final e = n['e'];
    if (p is! String || e is! List) return null;
    return (patient: p, events: [for (final x in e) if (x is String) x]);
  } catch (_) {
    return null;
  }
}

/// «ميعاد دوا الحاج أحمد: كونكور» — دواءين في نفس الدقيقة إشعار واحد.
List<NurseNotification> planNurseReminders(List<NursePatientDoses> patients, {required DateTime now}) {
  final out = <NurseNotification>[];
  final until = now.add(nurseReminderHorizon);
  for (final p in patients) {
    if (p.index < 0 || p.index >= maxPatients) continue;
    final byMinute = <DateTime, List<NurseDose>>{};
    for (final d in p.doses) {
      if (d.state != 'pending' || d.confirmedHere) continue;
      if (!d.scheduledAt.isAfter(now) || d.scheduledAt.isAfter(until)) continue;
      final m = d.scheduledAt;
      byMinute.putIfAbsent(DateTime(m.year, m.month, m.day, m.hour, m.minute), () => []).add(d);
    }
    for (final entry in byMinute.entries) {
      final doses = entry.value;
      final names = <String>{for (final d in doses) d.medicationName}.toList();
      out.add(NurseNotification(
        id: nurseIdFor(entry.key, patientIndex: p.index),
        at: entry.key,
        title: 'ميعاد دوا ${p.name}: ${names.join('، ')}',
        body: 'لما ياخده، دوس «أكّد إنه أخدها».',
        payload: nursePayload(p.uuid, [for (final d in doses) d.eventUuid]),
        insistent: doses.any((d) => d.insistent),
      ));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(maxPendingNurseReminders).toList();
}
