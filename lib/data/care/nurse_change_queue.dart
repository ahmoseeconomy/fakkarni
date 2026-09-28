import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics.dart';
import '../../domain/care/medication_change.dart';
import '../db/tables.dart' show newSyncUuid;
import 'care_circle_service.dart';
import 'medication_changes.dart';

/// نتيجة إرسال تغيير من الممرض.
enum SubmitOutcome {
  /// وصل السحابة — موبايل المريض هيسحبه.
  sent,

  /// النت واقع: اتحفظ على الموبايل وهيتبعت لوحده («هيوصل لموبايل … أول ما
  /// يفتح النت»).
  queued,

  /// السيرفر رفض (صلاحية، اشتراك، نوع قبل 0035…) — الجملة في `error`.
  failed,
}

class QueuedChange {
  const QueuedChange({
    required this.uuid,
    required this.patientUuid,
    required this.patientName,
    required this.kind,
    required this.payload,
    this.medicationUuid,
    this.medicationName,
    this.actorName,
  });

  final String uuid;
  final String patientUuid;
  final String patientName;
  final MedicationChangeKind kind;
  final MedicationChangePayload payload;
  final String? medicationUuid;
  final String? medicationName;
  final String? actorName;

  Map<String, Object?> toJson() => {
        'uuid': uuid,
        'patient': patientUuid,
        'patient_name': patientName,
        'kind': kind.stored,
        'payload': payload.toJson(),
        'medication_uuid': medicationUuid,
        'medication_name': medicationName,
        'actor_name': actorName,
      };

  static QueuedChange? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = MedicationChangeKind.fromStored(json['kind'] as String?);
    final uuid = json['uuid'];
    final patient = json['patient'];
    if (kind == null || uuid is! String || patient is! String) return null;
    return QueuedChange(
      uuid: uuid,
      patientUuid: patient,
      patientName: (json['patient_name'] as String?) ?? '',
      kind: kind,
      payload: MedicationChangePayload.fromJson((json['payload'] as Map?)?.cast<String, dynamic>() ?? const {}),
      medicationUuid: json['medication_uuid'] as String?,
      medicationName: json['medication_name'] as String?,
      actorName: json['actor_name'] as String?,
    );
  }
}

/// **طابور الممرض الأوفلاين** (0035): كل تغيير بياخد uuid من الموبايل
/// **قبل** ما يتبعت، فإعادة الإرسال بعد نت وقع في النص بترجع نفس الصف —
/// والمفتاح الأساسي في السحابة هو اللي بيمنع التكرار، مش ذاكرة هنا.
///
/// اللي بيتحط في الطابور هو عطل الشبكة بس. الرفض (صلاحية، اشتراك، نوع
/// تغيير السيرفر لسه ما يعرفوش) بيرجع `failed` بجملته وما بيتخزّنش —
/// إعادة طلب مرفوض لحد الأبد مش طابور.
class NurseChangeQueue {
  NurseChangeQueue(this.remote);

  final MedicationChangeRemote remote;

  static const key = 'nurse.changeQueue';

  Future<List<QueuedChange>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return const [];
      final json = jsonDecode(raw);
      if (json is! List) return const [];
      return [for (final e in json) ?QueuedChange.fromJson(e)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<QueuedChange> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (list.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode([for (final q in list) q.toJson()]));
      }
    } catch (_) {}
  }

  /// اللي لسه مستني النت لمريض بعينه.
  Future<List<QueuedChange>> pendingFor(String patientUuid) async =>
      [for (final q in await load()) if (q.patientUuid == patientUuid) q];

  Future<({SubmitOutcome outcome, String? error})> submit(QueuedChange change) async {
    try {
      await remote.submit(
        patientUuid: change.patientUuid,
        kind: change.kind,
        payload: change.payload,
        uuid: change.uuid,
        medicationUuid: change.medicationUuid,
        medicationName: change.medicationName,
        actorName: change.actorName,
      );
      return (outcome: SubmitOutcome.sent, error: null);
    } on CareCircleException catch (e) {
      if (e.failure == CareCircleFailure.offline) {
        final list = await load();
        if (!list.any((q) => q.uuid == change.uuid)) await _save([...list, change]);
        diag('NurseQueue: ${change.kind.stored} اتحفظ لحد ما النت يرجع');
        return (outcome: SubmitOutcome.queued, error: null);
      }
      return (outcome: SubmitOutcome.failed, error: e.message);
    } catch (e) {
      diag('NurseQueue: إرسال وقع (${e.runtimeType})');
      return (outcome: SubmitOutcome.failed, error: 'مقدرناش نبعت. جرّب تاني.');
    }
  }

  /// بيبعت اللي في الطابور بالترتيب، ويقف عند أول عطل شبكة. بيرجّع عدد
  /// اللي اتبعت. المرفوض بيتشال من الطابور (مش هيتقبل بكرة).
  Future<int> flush() async {
    final list = await load();
    if (list.isEmpty) return 0;
    var sent = 0;
    final remaining = <QueuedChange>[];
    var stopped = false;
    for (final q in list) {
      if (stopped) {
        remaining.add(q);
        continue;
      }
      try {
        await remote.submit(
          patientUuid: q.patientUuid,
          kind: q.kind,
          payload: q.payload,
          uuid: q.uuid,
          medicationUuid: q.medicationUuid,
          medicationName: q.medicationName,
          actorName: q.actorName,
        );
        sent++;
      } on CareCircleException catch (e) {
        if (e.failure == CareCircleFailure.offline) {
          stopped = true;
          remaining.add(q);
        } else {
          diag('NurseQueue: ${q.kind.stored} اترفض من السيرفر — اتشال من الطابور (${e.failure.name})');
        }
      } catch (e) {
        stopped = true;
        remaining.add(q);
      }
    }
    await _save(remaining);
    return sent;
  }

  /// «هيوصل لموبايل الحاج أحمد أول ما يفتح النت» — من غير كلمة تقنية.
  static String queuedLine(String patientName) =>
      'هيوصل لموبايل ${patientName.trim().isEmpty ? 'المريض' : patientName.trim()} أول ما يفتح النت';

  static String newUuid() => newSyncUuid();
}
