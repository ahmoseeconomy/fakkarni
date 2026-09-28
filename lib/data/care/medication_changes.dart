/// تغييرات الأدوية المعلّقة (المرحلة ب): الممرض بيبعت، وموبايل الأب بيسحب
/// ويطبّق ويعلّم. الـSDK في `supabase_medication_changes.dart` وبس.
library;

import '../../domain/care/medication_change.dart';

abstract interface class MedicationChangeRemote {
  /// [uuid] من موبايل الممرض (0035): الطابور الأوفلاين بيعيد نفس الصف
  /// بنفس الـuuid، والمفتاح الأساسي في السحابة هو الحارس — تكرار = نجاح.
  Future<void> submit({
    required String patientUuid,
    required MedicationChangeKind kind,
    required MedicationChangePayload payload,
    String? uuid,
    String? medicationUuid,
    String? medicationName,
    String? actorName,
  });

  /// اللي لسه ما اتطبّقش على موبايل المريض ده.
  Future<List<MedicationChange>> fetchPending(String patientUuid);

  /// بعد التطبيق (أو التعارض): الصف بيتعلّم ومش بيتسحب تاني.
  Future<void> markApplied(String changeUuid, ChangeOutcome outcome);

  /// «تراجع» على موبايل المريض (0035) — الصف بيقول `reverted` والممرض بيشوفه.
  Future<void> markReverted(String changeUuid);

  /// عند الممرض: اللي بعته ولسه معلّق — الشاشة بتقول «اتبعت لموبايله».
  Future<List<MedicationChange>> pendingFor(String patientUuid);

  /// «التعديلات» (0035): كل التغييرات على المريض ده، الأحدث الأول، بنتيجتها.
  /// المريض والممرض والمتابع بيقروا نفس القايمة (RLS: `can_access_patient`).
  Future<List<MedicationChange>> history(String patientUuid, {int limit = 50});
}
