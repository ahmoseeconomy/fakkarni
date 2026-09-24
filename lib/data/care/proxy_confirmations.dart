/// التأكيد نيابةً عن المريض — الواجهة اللي الممرض بيكتب بيها وموبايل الأب
/// بيسحب منها. الـSDK في `supabase_proxy_remote.dart` وبس.
library;

/// صف واحد من `proxy_confirmations`: مين أكّد أنهي حدث وإمتى.
class ProxyConfirmation {
  const ProxyConfirmation({
    required this.doseEventUuid,
    required this.actorName,
    required this.confirmedAt,
  });

  final String doseEventUuid;

  /// اسم اللي أكّد زي ما كتبه في تفضيلاته — null = ما كتبش اسم.
  final String? actorName;
  final DateTime confirmedAt;
}

abstract interface class ProxyConfirmRemote {
  /// الممرض بيأكّد جرعة بدال المريض. السيرفر هو اللي بيرفض لو مش مسموح
  /// (مفيش صلاحية، الجرعة لسه جاية، مريض تاني) — بيوصل كـ[CareCircleException].
  Future<void> confirmOnBehalf({
    required String patientUuid,
    required String doseEventUuid,
    required String? actorName,
  });

  /// التأكيدات اللي حصلت للمريض ده من [since] — موبايله بيسحبها.
  Future<List<ProxyConfirmation>> fetchForPatient(String patientUuid, {required DateTime since});
}
