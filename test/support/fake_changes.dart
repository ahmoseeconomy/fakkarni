import 'package:fakkarni/data/care/medication_changes.dart';
import 'package:fakkarni/domain/care/medication_change.dart';

/// سحابة تغييرات وهمية — بتسجّل اللي اتبعت واللي اتعلّم واللي اترجع.
class FakeChanges implements MedicationChangeRemote {
  final pending = <MedicationChange>[];
  final marked = <(String, ChangeOutcome)>[];
  final reverted = <String>[];
  /// الحمولات بالترتيب، وأنواعها — زي ما اختبارات الشاشات بتقرا.
  final submitted = <MedicationChangePayload>[];
  final kinds = <MedicationChangeKind>[];
  final submittedUuids = <String?>[];

  /// null = شغّال؛ غير كده كل submit بيرمي بيه (أوفلاين مثلاً).
  Object? submitFailure;
  int submitCalls = 0;

  @override
  Future<void> submit({
    required String patientUuid,
    required MedicationChangeKind kind,
    required MedicationChangePayload payload,
    String? uuid,
    String? medicationUuid,
    String? medicationName,
    String? actorName,
  }) async {
    submitCalls++;
    if (submitFailure != null) throw submitFailure!;
    if (uuid != null && submittedUuids.contains(uuid)) return; // نفس الصف — نجاح
    submittedUuids.add(uuid);
    submitted.add(payload);
    kinds.add(kind);
    pending.add(MedicationChange(
      uuid: uuid ?? 'sub-${submitted.length}',
      kind: kind,
      medicationUuid: medicationUuid,
      medicationName: medicationName,
      payload: payload,
      actorName: actorName,
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<List<MedicationChange>> fetchPending(String patientUuid) async => List.of(pending);

  @override
  Future<List<MedicationChange>> pendingFor(String patientUuid) async => List.of(pending);

  @override
  Future<List<MedicationChange>> history(String patientUuid, {int limit = 50}) async => List.of(pending);

  @override
  Future<void> markApplied(String changeUuid, ChangeOutcome outcome) async {
    marked.add((changeUuid, outcome));
    pending.removeWhere((c) => c.uuid == changeUuid);
  }

  @override
  Future<void> markReverted(String changeUuid) async => reverted.add(changeUuid);
}
