/// تغييرات الأدوية المعلّقة (المرحلة ب): الممرض بيبعت، وموبايل الأب بيسحب
/// ويطبّق ويعلّم. الـSDK في `supabase_medication_changes.dart` وبس.
library;

import '../../domain/care/medication_change.dart';

abstract interface class MedicationChangeRemote {
  Future<void> submit({
    required String patientUuid,
    required MedicationChangeKind kind,
    required MedicationChangePayload payload,
    String? medicationUuid,
    String? medicationName,
    String? actorName,
  });

  /// اللي لسه ما اتطبّقش على موبايل المريض ده.
  Future<List<MedicationChange>> fetchPending(String patientUuid);

  /// بعد التطبيق (أو التعارض): الصف بيتعلّم ومش بيتسحب تاني.
  Future<void> markApplied(String changeUuid, ChangeOutcome outcome);

  /// عند الممرض: اللي بعته ولسه معلّق — الشاشة بتقول «اتبعت لموبايله».
  Future<List<MedicationChange>> pendingFor(String patientUuid);
}
